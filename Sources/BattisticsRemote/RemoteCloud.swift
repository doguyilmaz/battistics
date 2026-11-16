import CloudKit
import Foundation

/// The iCloud side of the companion: one private zone holding a status record
/// and a command slot per Mac. Payloads live in encrypted fields, so only the
/// account's own devices can read them. Discovery supplies record IDs; direct
/// reads supply current values without replaying the account's history.
public actor RemoteCloud {
    public static let containerID = "iCloud.com.doguyilmaz.Battistics"
    static let zoneID = CKRecordZone.ID(zoneName: "Remote")
    static let statusType = "MacStatus"
    static let commandType = "Command"
    static let eventType = "Event"
    static let alertSubscriptionID = "remote-alerts"
    static let zoneSubscriptionID = "remote-zone"
    static let subscriptionCheckInterval: Duration = .seconds(30 * 60)
    static let subscriptionRetryInterval: Duration = .seconds(5 * 60)

    public struct Snapshot: Sendable {
        /// Phone-side time, used to keep an earlier discovery read from
        /// removing a Mac that just confirmed a command.
        public var requestedAt = Date.now
        public var statuses: [String: RemoteStatus] = [:]
        /// Status records written by a newer build that this one cannot read.
        public var unreadable: Set<String> = []
        /// Nearby telemetry is a partial update and cannot remove other Macs.
        public var isComplete = true

        public init(statuses: [String: RemoteStatus] = [:], isComplete: Bool = true) {
            self.statuses = statuses
            self.isComplete = isComplete
        }
    }

    /// What a Mac reads each poll: its own record and its command slot.
    public struct Inbox: Sendable {
        /// Nil when the record is gone, such as after a phone removed this Mac.
        public var status: RemoteStatus?
        public var command: RemoteRequest?
        public var phones: [RemotePhoneInfo] = []
    }

    private let operations: CloudKitOperations
    private let subscriptionClock: @Sendable () -> ContinuousClock.Instant
    private let identity: @Sendable () async throws -> String
    private var identityWork: Task<String, Error>?
    private var verifiedIdentity: String?
    private var accountGeneration = 0
    private var prepared = false
    private var preparing: Task<Void, Error>?
    private var subscribed = false
    private var subscribing = false
    private var subscriptionCheckAt: ContinuousClock.Instant?
    private var zoneGeneration = 0
    private var retryAt: Date?
    private var statusRecords: [String: CKRecord] = [:]

    public init() {
        let container = CKContainer(identifier: Self.containerID)
        operations = CloudKitOperations(database: container.privateCloudDatabase)
        subscriptionClock = { .now }
        identity = { try await container.userRecordID().recordName }
    }

    init(operations: CloudKitOperations, subscriptionClock: @escaping @Sendable () -> ContinuousClock.Instant = { .now },
         identity: @escaping @Sendable () async throws -> String = { throw NearbyError.unavailable }) {
        self.operations = operations
        self.subscriptionClock = subscriptionClock
        self.identity = identity
    }

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
        let generation = zoneGeneration
        if !prepared {
            let work: Task<Void, Error>
            if let preparing {
                work = preparing
            } else {
                let operations = operations
                work = Task { try await operations.createZone(until: deadline) }
                preparing = work
            }
            defer { if generation == zoneGeneration { preparing = nil } }
            try await work.value
            guard generation == zoneGeneration else { throw CancellationError() }
            prepared = true
        }
        scheduleSubscription()
    }

    private func scheduleSubscription() {
        guard !subscribing, subscriptionCheckDue else { return }
        Task { await refreshPushSubscription() }
    }

    private var subscriptionCheckDue: Bool {
        subscriptionCheckAt.map { subscriptionClock() >= $0 } ?? true
    }

    /// Maintenance runs during existing app activity, independently of reads.
    /// A saved subscription may disappear while this process keeps running.
    func refreshPushSubscription() async {
        guard !subscribing, subscriptionCheckDue else { return }
        subscribing = true
        defer { subscribing = false }
        let generation = zoneGeneration
        subscriptionCheckAt = subscriptionClock().advanced(by: Self.subscriptionRetryInterval)
        do {
            try await attempt {
                let deadline = ContinuousClock.now.advanced(by: .seconds(30))
                if subscribed,
                   let existing = try await operations.subscription(Self.zoneSubscriptionID, until: deadline) as? CKRecordZoneSubscription,
                   existing.zoneID == Self.zoneID, existing.recordType == nil,
                   existing.notificationInfo?.shouldSendContentAvailable == true { return }
                let subscription = CKRecordZoneSubscription(zoneID: Self.zoneID, subscriptionID: Self.zoneSubscriptionID)
                let info = CKSubscription.NotificationInfo()
                info.shouldSendContentAvailable = true
                subscription.notificationInfo = info
                try await operations.modifySubscriptions(saving: [subscription], until: deadline)
            }
            if generation == zoneGeneration {
                subscribed = true
                subscriptionCheckAt = subscriptionClock().advanced(by: Self.subscriptionCheckInterval)
            }
        } catch {
            // A failed push subscription does not stop a direct read or command.
        }
    }

    /// The query discovers IDs; direct reads get current values because the
    /// query index can lag writes and deletions. Known Macs are read even if
    /// the index temporarily omits them. Reading never creates the zone.
    public func fetch(knownMacIDs: [String] = [],
                      until deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(30))) async throws -> Snapshot {
        try await attempt {
            var snapshot = Snapshot()
            let records: [CKRecord]
            do {
                let discovered = try await operations.query(Self.statusType, until: deadline)
                let ids = Set(discovered.map(\.recordID)).union(knownMacIDs.map {
                    CKRecord.ID(recordName: $0, zoneID: Self.zoneID)
                })
                records = ids.isEmpty ? [] : Array(try await operations.records(Array(ids), until: deadline).values)
            } catch let error as CKError where [.zoneNotFound, .userDeletedZone].contains(error.code) {
                invalidateZone()
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
            let generation = accountGeneration
            return try await guarded(until: deadline) {
                let statusID = CKRecord.ID(recordName: macID, zoneID: Self.zoneID)
                let commandID = Self.commandRecordID(for: macID)
                let phonesID = CKRecord.ID(recordName: Self.phoneRegistryRecordName(for: macID), zoneID: Self.zoneID)
                let records = try await self.operations.records([statusID, commandID, phonesID], until: deadline)
                guard generation == self.accountGeneration else { throw CancellationError() }
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
                if let payload = records[phonesID]?.encryptedValues["payload"] as? Data,
                   let registry = try? RemoteWire.decode(RemotePhoneRegistry.self, from: payload) {
                    inbox.phones = Array(registry.phones.filter { $0.isValid && $0.seenAt > Date.now.addingTimeInterval(-30 * 86400) && $0.seenAt <= Date.now.addingTimeInterval(300) }.prefix(8))
                }
                return inbox
            }
        }
    }

    /// One slot per Mac, overwritten by each command. A Mac answers one change
    /// at a time and a phone never sends a second before the first is answered.
    public static func commandRecordName(for macID: String) -> String { "command.\(macID)" }

    public static func phoneRegistryRecordName(for macID: String) -> String { "phones.\(macID)" }

    /// Reuses the deployed encrypted Command payload; never overwrites a command.
    public func reportPhone(_ phone: RemotePhoneInfo, to macID: String, accountEpoch: Int,
                            until deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(15))) async throws {
        guard phone.isValid, accountEpoch == accountGeneration else { throw CancellationError() }
        try await attempt {
            try await guarded(until: deadline) {
                let id = CKRecord.ID(recordName: Self.phoneRegistryRecordName(for: macID), zoneID: Self.zoneID)
                for retry in 0..<3 {
                    try Task.checkCancellation()
                    guard accountEpoch == self.accountGeneration else { throw CancellationError() }
                    let records = try await self.operations.records([id, CKRecord.ID(recordName: macID, zoneID: Self.zoneID)], until: deadline)
                    guard accountEpoch == self.accountGeneration else { throw CancellationError() }
                    guard records[CKRecord.ID(recordName: macID, zoneID: Self.zoneID)] != nil else { return }
                    let record = records[id] ?? CKRecord(recordType: Self.commandType, recordID: id)
                    guard record.recordType == Self.commandType else { throw CKError(.internalError) }
                    var registry = RemotePhoneRegistry()
                    if records[id] != nil {
                        guard let payload = record.encryptedValues["payload"] as? Data else { throw CKError(.internalError) }
                        registry = try RemoteWire.decode(RemotePhoneRegistry.self, from: payload)
                    }
                    registry.record(phone)
                    record.encryptedValues["payload"] = try RemoteWire.encode(registry)
                    do {
                        _ = try await self.operations.modifyRecords(saving: [record], until: deadline)
                        return
                    } catch let error as CKError where error.code == .serverRecordChanged && retry < 2 {
                        continue
                    }
                }
            }
        }
    }

    /// Uses the existing encrypted Command schema, outside the command mailbox.
    public static func nearbyCredentialRecordName(for macID: String, discoveryID: String) -> String { "nearby.\(macID).\(discoveryID)" }

    public func nearbyCredential(macID: String, discoveryID: String) async throws -> NearbyCredential? {
        try await attempt {
            let id = CKRecord.ID(recordName: Self.nearbyCredentialRecordName(for: macID, discoveryID: discoveryID), zoneID: Self.zoneID)
            guard let record = try await operations.record(id, until: .now.advanced(by: .seconds(15))) else { return nil }
            guard record.recordType == Self.commandType,
                  let data = record.encryptedValues["payload"] as? Data else { throw NearbyError.authentication }
            let credential = try RemoteWire.decode(NearbyCredential.self, from: data)
            guard credential.isValid, credential.macID == macID, credential.discoveryID == discoveryID else { throw NearbyError.authentication }
            return credential
        }
    }

    public func publishNearbyCredential(_ credential: NearbyCredential) async throws {
        guard credential.isValid else { throw NearbyError.authentication }
        try await attempt {
            let generation = accountGeneration
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            try await prepare(until: deadline)
            let id = CKRecord.ID(recordName: Self.nearbyCredentialRecordName(for: credential.macID, discoveryID: credential.discoveryID), zoneID: Self.zoneID)
            let record = try await operations.record(id, until: deadline)
                ?? CKRecord(recordType: Self.commandType, recordID: id)
            guard generation == accountGeneration else { throw CancellationError() }
            guard record.recordType == Self.commandType else { throw NearbyError.authentication }
            record.encryptedValues["payload"] = try RemoteWire.encode(credential)
            _ = try await operations.modifyRecords(saving: [record], policy: .allKeys, until: deadline)
        }
    }

    public func accountDidChange() {
        accountGeneration += 1
        identityWork?.cancel()
        identityWork = nil
        verifiedIdentity = nil
        invalidateZone()
        retryAt = nil
    }

    public func accountEpoch() -> Int { accountGeneration }

    /// Verify once per process/account before reusing nearby credentials. A
    /// notification cannot tell us about an account change while the app quit.
    public func accountIdentity() async throws -> String {
        if let verifiedIdentity { return verifiedIdentity }
        let generation = accountGeneration
        let work: Task<String, Error>
        if let identityWork { work = identityWork }
        else {
            let identity = identity
            work = Task { try await RemoteDeadline.perform(until: .now.advanced(by: .seconds(15)), operation: identity) }
            identityWork = work
        }
        defer { if generation == accountGeneration { identityWork = nil } }
        let value = try await work.value
        guard generation == accountGeneration, !value.isEmpty else { throw NearbyError.authentication }
        verifiedIdentity = value
        return value
    }

    static func commandRecordID(for macID: String) -> CKRecord.ID {
        .init(recordName: commandRecordName(for: macID), zoneID: zoneID)
    }

    private func guarded<T>(until deadline: ContinuousClock.Instant, _ body: () async throws -> T) async throws -> T {
        try await prepare(until: deadline)
        do {
            return try await body()
        } catch let error as CKError where [.zoneNotFound, .userDeletedZone].contains(error.code) {
            invalidateZone()
            try await prepare(until: deadline)
            return try await body()
        }
    }

    private func invalidateZone() {
        preparing?.cancel()
        preparing = nil
        prepared = false
        subscribed = false
        subscriptionCheckAt = nil
        zoneGeneration += 1
        statusRecords = [:]
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
            let generation = accountGeneration
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
            guard generation == accountGeneration else { throw CancellationError() }
            record.encryptedValues["payload"] = try RemoteWire.encode(status)
            let saved = try await operations.modifyRecords(saving: [record], policy: .allKeys, until: deadline)
            guard generation == accountGeneration else { throw CancellationError() }
            statusRecords[macID] = saved[id]
        }
    }

    public func send(_ request: RemoteRequest, to macID: String,
                     until deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(30)), accountEpoch: Int? = nil) async throws {
        guard accountEpoch == nil || accountEpoch == accountGeneration else { throw CancellationError() }
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

    /// Cancel only this command, using the fetched change tag. A late cleanup
    /// must not delete/overwrite a newer command occupying the shared slot.
    /// Nil clears the observed mailbox version during sharing withdrawal.
    public func cancelCommand(_ commandID: String?, macID: String,
                              until deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(5)), accountEpoch: Int? = nil) async throws {
        guard accountEpoch == nil || accountEpoch == accountGeneration else { throw CancellationError() }
        try await attempt {
            let generation = accountGeneration
            guard let record = try await operations.record(Self.commandRecordID(for: macID), until: deadline),
                  record.recordType == Self.commandType,
                  let payload = record.encryptedValues["payload"] as? Data,
                  commandID == nil || Self.request(from: payload)?.id == commandID else { return }
            guard generation == accountGeneration else { throw CancellationError() }
            record.encryptedValues["payload"] = Data("{}".utf8)
            _ = try await operations.modifyRecords(saving: [record], policy: .ifServerRecordUnchanged, until: deadline)
        }
    }

    /// A command answer reads only its Mac, independent of discovery and alert
    /// subscriptions. No zone replay or unrelated Mac can hold the answer up.
    public func status(macID: String, until deadline: ContinuousClock.Instant, accountEpoch: Int? = nil) async throws -> RemoteStatus? {
        guard accountEpoch == nil || accountEpoch == accountGeneration else { throw CancellationError() }
        return try await attempt {
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
            do {
                _ = try await operations.modifyRecords(saving: [record], until: deadline)
            } catch let error as CKError where error.code == .serverRecordChanged {
                // A previous save may have reached iCloud before its response
                // was lost. Reusing this event must not create another push.
                let saved = try await operations.record(record.recordID, until: deadline)
                guard saved?["title"] as? String == title,
                      saved?["body"] as? String == body,
                      saved?["collapse"] as? String == collapseID else { throw error }
            }
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
        let generation = accountGeneration
        if let retryAt, retryAt > .now {
            throw CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: retryAt.timeIntervalSinceNow])
        }
        do {
            let value = try await body()
            guard generation == accountGeneration else { throw CancellationError() }
            return value
        }
        catch {
            guard generation == accountGeneration else { throw CancellationError() }
            if let seconds = (error as? CKError)?.retryAfterSeconds {
                retryAt = .now.addingTimeInterval(seconds)
            }
            throw error
        }
    }
}
