import CloudKit
import Foundation

/// The iCloud side of the companion: one private zone holding a status record
/// per Mac and short-lived command records from phones. Payloads live in
/// encrypted fields, so only the account's own devices can read them.
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
        /// Status records deleted since the previous read, such as a Mac a phone removed.
        public var removedStatuses: Set<String> = []
        var removedRecords: Set<String> = []
        public var commands: [Command] = []
        /// Alert records by name, with when they were posted.
        public var events: [String: Date] = [:]
        /// Read from the start rather than as changes, so a missing record is really missing.
        public var isFull = false
    }

    public struct Command: Sendable {
        public let recordName: String
        public let macID: String
        public let request: RemoteRequest
    }

    private let operations: CloudKitOperations
    private var prepared = false
    private var preparing: Task<Void, Error>?
    private var subscribed = false
    private var subscribing = false
    private var zoneGeneration = 0
    private var retryAt: Date?
    private var statusRecords: [String: CKRecord] = [:]
    private var changeToken: CKServerChangeToken?
    private var snapshotToken: CKServerChangeToken?
    private var snapshotCache: Snapshot?

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

    /// A complete snapshot for the phone, assembled from deltas after the
    /// first read. A ten-second refresh must not replay the zone's history.
    public func fetch(until deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(45))) async throws -> Snapshot {
        try await attempt {
            try await guarded(until: deadline) {
                let result: (snapshot: Snapshot, token: CKServerChangeToken?)
                do {
                    result = try await self.read(since: self.snapshotToken, until: deadline)
                } catch let error as CKError where error.code == .changeTokenExpired {
                    self.snapshotCache = nil
                    self.snapshotToken = nil
                    self.subscribed = false
                    result = try await self.read(since: nil, until: deadline)
                }
                let full = (self.snapshotCache ?? Snapshot()).applying(result.snapshot)
                self.snapshotCache = full
                self.snapshotToken = result.token
                return full
            }
        }
    }

    /// Only what changed since the previous call, for callers that poll often.
    public func fetchChanges(until deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(30))) async throws -> Snapshot {
        try await attempt {
            try await guarded(until: deadline) {
                let result: (snapshot: Snapshot, token: CKServerChangeToken?)
                do {
                    result = try await self.read(since: self.changeToken, until: deadline)
                } catch let error as CKError where error.code == .changeTokenExpired {
                    self.subscribed = false
                    self.statusRecords = [:]
                    result = try await self.read(since: nil, until: deadline)
                }
                self.changeToken = result.token
                return result.snapshot
            }
        }
    }

    /// Keep the first-contact setup used by build (3). Preparation is cached
    /// for this process; reads must not race ahead of account/zone bootstrap.
    private func guarded<T>(until deadline: ContinuousClock.Instant, _ body: () async throws -> T) async throws -> T {
        try await prepare(until: deadline)
        do {
            let result = try await body()
            prepared = true
            scheduleSubscription()
            return result
        } catch let error as CKError where [.zoneNotFound, .userDeletedZone].contains(error.code) {
            prepared = false
            subscribed = false
            zoneGeneration += 1
            changeToken = nil
            snapshotToken = nil
            snapshotCache = nil
            statusRecords = [:]
            try await prepare(until: deadline)
            return try await body()
        }
    }

    private func read(since start: CKServerChangeToken?, until deadline: ContinuousClock.Instant) async throws -> (snapshot: Snapshot, token: CKServerChangeToken?) {
        var snapshot = Snapshot(isFull: start == nil)
        var commands: [String: Command] = [:]
        var token = start
        while true {
            let changes = try await operations.changes(since: token, until: deadline)
            for modification in changes.records.values {
                let record = try modification.get()
                if record.recordType == Self.eventType {
                    snapshot.events[record.recordID.recordName] = record.creationDate ?? .distantPast
                    snapshot.removedRecords.remove(record.recordID.recordName)
                    continue
                }
                guard let payload = record.encryptedValues["payload"] as? Data else {
                    // Inaccessible encrypted data is not evidence that the Mac
                    // stopped sharing. Keep it rather than returning an empty list.
                    if record.recordType == Self.statusType { throw CKError(.internalError) }
                    continue
                }
                switch record.recordType {
                case Self.statusType:
                    statusRecords[record.recordID.recordName] = record
                    if let status = try? RemoteWire.decode(RemoteStatus.self, from: payload) {
                        snapshot.statuses[record.recordID.recordName] = status
                        snapshot.unreadable.remove(record.recordID.recordName)
                    } else {
                        snapshot.statuses[record.recordID.recordName] = nil
                        snapshot.unreadable.insert(record.recordID.recordName)
                    }
                    snapshot.removedStatuses.remove(record.recordID.recordName)
                    snapshot.removedRecords.remove(record.recordID.recordName)
                case Self.commandType:
                    if let request = Self.request(from: payload), let mac = record["mac"] as? String {
                        commands[record.recordID.recordName] = .init(recordName: record.recordID.recordName, macID: mac, request: request)
                        snapshot.removedRecords.remove(record.recordID.recordName)
                    }
                default: break
                }
            }
            for (id, type) in changes.deletions {
                snapshot.removedRecords.insert(id.recordName)
                snapshot.events[id.recordName] = nil
                commands[id.recordName] = nil
                if type == Self.statusType {
                    snapshot.statuses[id.recordName] = nil
                    snapshot.unreadable.remove(id.recordName)
                    statusRecords[id.recordName] = nil
                    snapshot.removedStatuses.insert(id.recordName)
                }
            }
            token = changes.token
            if !changes.moreComing {
                snapshot.commands = Array(commands.values)
                return (snapshot, token)
            }
            // The SDK supplies a cursor with every successful page. Refuse a
            // bad adapter response rather than replaying page one indefinitely.
            guard token != nil else { throw CKError(.internalError) }
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
                let record = CKRecord(recordType: Self.commandType, recordID: .init(recordName: request.id, zoneID: Self.zoneID))
                record["mac"] = macID
                record.encryptedValues["payload"] = try RemoteWire.encode(request)
                _ = try await operations.modifyRecords(saving: [record], until: deadline)
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
    public func post(title: String, body: String, collapseID: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        try await attempt {
            try await prepare(until: deadline)
            let record = CKRecord(recordType: Self.eventType, recordID: .init(recordName: UUID().uuidString, zoneID: Self.zoneID))
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
            // One saved before the extension named the Mac is saved again.
            return subscription?.notificationInfo?.shouldSendMutableContent == true
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
