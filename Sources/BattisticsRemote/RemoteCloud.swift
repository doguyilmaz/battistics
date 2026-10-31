import CloudKit
import Foundation

/// The iCloud side of the companion: one private zone holding a status record
/// and a command slot per Mac. Payloads live in encrypted fields, so only the
/// account's own devices can read them. Reads ask for records as they are now,
/// by query or by name, so first contact costs one request however long the
/// account has used Battistics.
public actor RemoteCloud {
    public static let containerID = "iCloud.com.doguyilmaz.Battistics"
    static let zoneID = CKRecordZone.ID(zoneName: "Remote")
    static let statusType = "MacStatus"
    static let commandType = "Command"
    static let eventType = "Event"
    static let alertSubscriptionID = "remote-alerts"

    public struct Snapshot: Sendable {
        /// Phone-side time, used to keep an earlier discovery read from
        /// removing a Mac that just confirmed a command.
        public var requestedAt = Date.now
        public var statuses: [String: RemoteStatus] = [:]
        /// Status records written by a newer build that this one cannot read.
        public var unreadable: Set<String> = []
    }

    /// What a Mac reads each poll: its own record and its command slot.
    public struct Inbox: Sendable {
        /// Nil when the record is gone, such as after a phone removed this Mac.
        public var status: RemoteStatus?
        public var command: RemoteRequest?
    }

    private let operations: CloudKitOperations
    private var prepared = false
    private var preparing: Task<Void, Error>?
    private var subscribed = false
    private var subscribing = false
    private var zoneGeneration = 0
    private var retryAt: Date?
    private var statusRecords: [String: CKRecord] = [:]

    public init() {
        operations = CloudKitOperations(database: CKContainer(identifier: Self.containerID).privateCloudDatabase)
    }

    init(operations: CloudKitOperations) { self.operations = operations }

    /// Whether this process is signed for the container; CloudKit traps
    /// instead of throwing when it is not.
    public static var isEntitled: Bool {
        #if os(iOS)
        return true
        #else
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) else { return false }
        return (value as? [String])?.contains(containerID) == true
        #endif
    }

    /// Creates the zone and a silent push subscription for changes in it.
    /// Subscriptions belong to the account, not the device, so every device
    /// saves the same one.
    public func prepare(until deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(45))) async throws {
        if !prepared {
            let work: Task<Void, Error>
            if let preparing {
                work = preparing
            } else {
                let operations = operations
                work = Task { try await operations.createZone(until: deadline) }
                preparing = work
            }
            defer { preparing = nil }
            try await work.value
            prepared = true
        }
        scheduleSubscription()
    }

    private func scheduleSubscription() {
        guard !subscribed, !subscribing else { return }
        subscribing = true
        let generation = zoneGeneration
        Task { await subscribe(generation: generation) }
    }

    private func subscribe(generation: Int) async {
        defer { subscribing = false }
        let subscription = CKRecordZoneSubscription(zoneID: Self.zoneID, subscriptionID: "remote-zone")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        do {
            try await attempt {
                try await operations.modifySubscriptions(saving: [subscription], until: .now.advanced(by: .seconds(30)))
            }
            if generation == zoneGeneration { subscribed = true }
        } catch {
            // A failed push subscription does not stop a direct read or command.
        }
    }

    /// Every sharing Mac, for the phone. A zone no Mac has created yet means
    /// no Mac shares, so reading never waits for zone setup.
    public func fetch(until deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(30))) async throws -> Snapshot {
        try await attempt {
            var snapshot = Snapshot()
            let records: [CKRecord]
            do {
                records = try await operations.query(Self.statusType, until: deadline)
            } catch let error as CKError where [.zoneNotFound, .userDeletedZone].contains(error.code) {
                return snapshot
            }
            for record in records {
                let name = record.recordID.recordName
                // Inaccessible encrypted data is not evidence that the Mac
                // stopped sharing. Fail rather than return an empty list.
                guard let payload = record.encryptedValues["payload"] as? Data else { throw CKError(.internalError) }
                if let status = try? RemoteWire.decode(RemoteStatus.self, from: payload) {
                    snapshot.statuses[name] = status
                } else {
                    snapshot.unreadable.insert(name)
                }
            }
            prepared = true
            scheduleSubscription()
            return snapshot
        }
    }

    /// This Mac's record and its command slot, read by name in one request.
    public func inbox(macID: String, until deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(30))) async throws -> Inbox {
        try await attempt {
            try await guarded(until: deadline) {
                let statusID = CKRecord.ID(recordName: macID, zoneID: Self.zoneID)
                let commandID = Self.commandRecordID(for: macID)
                let records = try await self.operations.records([statusID, commandID], until: deadline)
                var inbox = Inbox()
                if let record = records[statusID] {
                    self.statusRecords[macID] = record
                    guard let payload = record.encryptedValues["payload"] as? Data else { throw CKError(.internalError) }
                    // One this build cannot read is replaced by the next publish.
                    inbox.status = try? RemoteWire.decode(RemoteStatus.self, from: payload)
                } else {
                    self.statusRecords[macID] = nil
                }
                if let payload = records[commandID]?.encryptedValues["payload"] as? Data {
                    inbox.command = Self.request(from: payload)
                }
                return inbox
            }
        }
    }

    /// One slot per Mac, overwritten by each command. A Mac answers one change
    /// at a time and a phone never sends a second before the first is answered.
    public static func commandRecordName(for macID: String) -> String { "command.\(macID)" }

    static func commandRecordID(for macID: String) -> CKRecord.ID {
        .init(recordName: commandRecordName(for: macID), zoneID: zoneID)
    }

    private func guarded<T>(until deadline: ContinuousClock.Instant, _ body: () async throws -> T) async throws -> T {
        try await prepare(until: deadline)
        do {
            return try await body()
        } catch let error as CKError where [.zoneNotFound, .userDeletedZone].contains(error.code) {
            prepared = false
            subscribed = false
            zoneGeneration += 1
            statusRecords = [:]
            try await prepare(until: deadline)
            return try await body()
        }
    }

    /// A command from a newer phone, with a mode or policy this Mac does not
    /// know, is answered as an invalid request instead of left to time out.
    private static func request(from payload: Data) -> RemoteRequest? {
        if let request = try? RemoteWire.decode(RemoteRequest.self, from: payload) { return request }
        struct Envelope: Decodable { let id: String; let sentAt: Date }
        return (try? RemoteWire.decode(Envelope.self, from: payload))
            .map { RemoteRequest(id: $0.id, operation: .unknown, sentAt: $0.sentAt) }
    }

    public func publish(_ status: RemoteStatus, macID: String,
                        until deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(30))) async throws {
        try await attempt {
            try await prepare(until: deadline)
            let id = CKRecord.ID(recordName: macID, zoneID: Self.zoneID)
            let record: CKRecord
            if let cached = statusRecords[macID] {
                record = cached
            } else if let existing = try await operations.record(id, until: deadline) {
                record = existing
            } else {
                record = CKRecord(recordType: Self.statusType, recordID: id)
            }
            record.encryptedValues["payload"] = try RemoteWire.encode(status)
            let saved = try await operations.modifyRecords(saving: [record], policy: .allKeys, until: deadline)
            statusRecords[macID] = saved[id]
        }
    }

    public func send(_ request: RemoteRequest, to macID: String,
                     until deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(30))) async throws {
        try await attempt {
            try await guarded(until: deadline) {
                let record = CKRecord(recordType: Self.commandType, recordID: Self.commandRecordID(for: macID))
                // Read by Battistics 1.5.3, which finds commands in the zone's changes.
                record["mac"] = macID
                record.encryptedValues["payload"] = try RemoteWire.encode(request)
                _ = try await operations.modifyRecords(saving: [record], policy: .allKeys, until: deadline)
            }
        }
    }

    /// A command answer reads only its Mac, independent of discovery and alert
    /// subscriptions. No zone replay or unrelated Mac can hold the answer up.
    public func status(macID: String, until deadline: ContinuousClock.Instant) async throws -> RemoteStatus? {
        try await attempt {
            let id = CKRecord.ID(recordName: macID, zoneID: Self.zoneID)
            guard let record = try await operations.record(id, until: deadline) else { return nil }
            guard let payload = record.encryptedValues["payload"] as? Data else { throw CKError(.internalError) }
            return try RemoteWire.decode(RemoteStatus.self, from: payload)
        }
    }

    /// An alert iOS shows on the account's phones straight from the push,
    /// even while Battistics Remote is not running. Push payloads cannot
    /// carry encrypted fields, so the text names no Mac and no network; the
    /// phone adds the Mac's name itself.
    public func post(_ recordName: String, title: String, body: String, collapseID: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        try await attempt {
            try await prepare(until: deadline)
            let record = CKRecord(recordType: Self.eventType, recordID: .init(recordName: recordName, zoneID: Self.zoneID))
            record["title"] = title
            record["body"] = body
            record["collapse"] = collapseID
            _ = try await operations.modifyRecords(saving: [record], until: deadline)
        }
    }

    /// Shows alert records as notifications on this device's account. The
    /// text arrives already written; "%@" only places it.
    public func subscribeToAlerts() async throws {
        let subscription = CKQuerySubscription(recordType: Self.eventType, predicate: NSPredicate(value: true),
                                               subscriptionID: Self.alertSubscriptionID, options: [.firesOnRecordCreation])
        subscription.zoneID = Self.zoneID
        let info = CKSubscription.NotificationInfo()
        info.titleLocalizationKey = "%@"
        info.titleLocalizationArgs = ["title"]
        info.alertLocalizationKey = "%@"
        info.alertLocalizationArgs = ["body"]
        info.soundName = "default"
        info.collapseIDKey = "collapse"
        // Lets the phone's notification extension name the Mac.
        info.shouldSendMutableContent = true
        // Also wakes the app, which ends a Live Activity the alert says is over.
        info.shouldSendContentAvailable = true
        info.desiredKeys = ["collapse"]
        subscription.notificationInfo = info
        try await attempt {
            try await operations.modifySubscriptions(saving: [subscription], until: .now.advanced(by: .seconds(30)))
        }
    }

    /// Whether the account still holds the alert subscription; another phone
    /// or a recreated zone can remove it.
    public func hasAlertSubscription() async throws -> Bool {
        try await attempt {
            let subscription = try await operations.subscription(Self.alertSubscriptionID, until: .now.advanced(by: .seconds(30)))
            // One saved before these options existed is saved again.
            return subscription?.notificationInfo?.shouldSendMutableContent == true
                && subscription?.notificationInfo?.shouldSendContentAvailable == true
        }
    }

    public func unsubscribeFromAlerts() async throws {
        try await attempt {
            try await operations.modifySubscriptions(deleting: [Self.alertSubscriptionID], until: .now.advanced(by: .seconds(30)))
        }
    }

    public func delete(_ recordNames: [String], until deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(30))) async throws {
        guard !recordNames.isEmpty else { return }
        try await attempt {
            _ = try await operations.modifyRecords(deleting: recordNames.map { .init(recordName: $0, zoneID: Self.zoneID) }, until: deadline)
        }
        for name in recordNames { statusRecords[name] = nil }
    }

    private func attempt<Value>(_ body: () async throws -> Value) async throws -> Value {
        if let retryAt, retryAt > .now {
            throw CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: retryAt.timeIntervalSinceNow])
        }
        do { return try await body() }
        catch {
            if let seconds = (error as? CKError)?.retryAfterSeconds {
                retryAt = .now.addingTimeInterval(seconds)
            }
            throw error
        }
    }
}
