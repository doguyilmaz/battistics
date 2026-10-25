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
        public var statuses: [String: RemoteStatus] = [:]
        /// Status records written by a newer build that this one cannot read.
        public var unreadable: Set<String> = []
        /// Status records deleted since the previous read, such as a Mac a phone removed.
        public var removedStatuses: Set<String> = []
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

    private let database: CKDatabase
    private var prepared = false
    private var subscribed = false
    private var statusRecords: [String: CKRecord] = [:]
    private var changeToken: CKServerChangeToken?

    public init() {
        database = CKContainer(identifier: Self.containerID).privateCloudDatabase
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
    public func prepare() async throws {
        if !prepared {
            let zones = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: Self.zoneID)], deleting: [])
            for result in zones.saveResults.values { _ = try result.get() }
            prepared = true
        }
        // Polling still works without pushes, so a failed subscription only retries.
        guard !subscribed else { return }
        let subscription = CKRecordZoneSubscription(zoneID: Self.zoneID, subscriptionID: "remote-zone")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        subscribed = (try? await database.modifySubscriptions(saving: [subscription], deleting: [])) != nil
    }

    /// The whole zone is a handful of small records, so it is read in full.
    public func fetch() async throws -> Snapshot {
        try await guarded { try await self.read(since: nil).snapshot }
    }

    /// Only what changed since the previous call, for callers that poll often.
    public func fetchChanges() async throws -> Snapshot {
        try await guarded {
            let result: (snapshot: Snapshot, token: CKServerChangeToken?)
            do {
                result = try await self.read(since: self.changeToken)
            } catch let error as CKError where error.code == .changeTokenExpired {
                // Also what another device recreating the zone looks like,
                // which took this zone's subscription with the old one.
                self.subscribed = false
                self.statusRecords = [:]
                result = try await self.read(since: nil)
            }
            self.changeToken = result.token
            return result.snapshot
        }
    }

    /// Sets the zone up again on the next call after iCloud lost it.
    private func guarded<T>(_ body: () async throws -> T) async throws -> T {
        try await prepare()
        do {
            return try await body()
        } catch let error as CKError where [.zoneNotFound, .userDeletedZone].contains(error.code) {
            prepared = false
            subscribed = false
            changeToken = nil
            statusRecords = [:]
            throw error
        }
    }

    private func read(since start: CKServerChangeToken?) async throws -> (snapshot: Snapshot, token: CKServerChangeToken?) {
        var snapshot = Snapshot(isFull: start == nil)
        var token = start
        repeat {
            let changes = try await database.recordZoneChanges(inZoneWith: Self.zoneID, since: token)
            for case .success(let modification) in changes.modificationResultsByID.values {
                let record = modification.record
                if record.recordType == Self.eventType {
                    snapshot.events[record.recordID.recordName] = record.creationDate ?? .distantPast
                    continue
                }
                guard let payload = record.encryptedValues["payload"] as? Data else { continue }
                switch record.recordType {
                case Self.statusType:
                    statusRecords[record.recordID.recordName] = record
                    if let status = try? RemoteWire.decode(RemoteStatus.self, from: payload) {
                        snapshot.statuses[record.recordID.recordName] = status
                    } else {
                        snapshot.unreadable.insert(record.recordID.recordName)
                    }
                case Self.commandType:
                    if let request = try? RemoteWire.decode(RemoteRequest.self, from: payload),
                       let mac = record["mac"] as? String {
                        snapshot.commands.append(.init(recordName: record.recordID.recordName, macID: mac, request: request))
                    }
                default: break
                }
            }
            for deletion in changes.deletions where deletion.recordType == Self.statusType {
                statusRecords[deletion.recordID.recordName] = nil
                snapshot.removedStatuses.insert(deletion.recordID.recordName)
            }
            token = changes.changeToken
            if !changes.moreComing { break }
        } while true
        return (snapshot, token)
    }

    public func publish(_ status: RemoteStatus, macID: String) async throws {
        try await prepare()
        let id = CKRecord.ID(recordName: macID, zoneID: Self.zoneID)
        let record: CKRecord
        if let cached = statusRecords[macID] {
            record = cached
        } else if let existing = try? await database.record(for: id) {
            record = existing
        } else {
            record = CKRecord(recordType: Self.statusType, recordID: id)
        }
        record.encryptedValues["payload"] = try RemoteWire.encode(status)
        let saved = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        for result in saved.saveResults.values {
            statusRecords[macID] = try result.get()
        }
    }

    public func send(_ request: RemoteRequest, to macID: String) async throws -> String {
        try await prepare()
        let record = CKRecord(recordType: Self.commandType, recordID: .init(recordName: request.id, zoneID: Self.zoneID))
        record["mac"] = macID
        record.encryptedValues["payload"] = try RemoteWire.encode(request)
        let saved = try await database.modifyRecords(saving: [record], deleting: [])
        for result in saved.saveResults.values { _ = try result.get() }
        return record.recordID.recordName
    }

    /// An alert iOS shows on the account's phones straight from the push,
    /// even while Battistics Remote is not running. Push payloads cannot
    /// carry encrypted fields, so the text names no Mac and no network.
    public func post(title: String, body: String, collapseID: String) async throws {
        try await prepare()
        let record = CKRecord(recordType: Self.eventType, recordID: .init(recordName: UUID().uuidString, zoneID: Self.zoneID))
        record["title"] = title
        record["body"] = body
        record["collapse"] = collapseID
        let saved = try await database.modifyRecords(saving: [record], deleting: [])
        for result in saved.saveResults.values { _ = try result.get() }
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
        subscription.notificationInfo = info
        _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
    }

    /// Whether the account still holds the alert subscription; another phone
    /// or a recreated zone can remove it.
    public func hasAlertSubscription() async throws -> Bool {
        do {
            _ = try await database.subscription(for: Self.alertSubscriptionID)
            return true
        } catch let error as CKError where error.code == .unknownItem {
            return false
        }
    }

    public func unsubscribeFromAlerts() async throws {
        let result = try await database.modifySubscriptions(saving: [], deleting: [Self.alertSubscriptionID])
        for case .failure(let error) in result.deleteResults.values
        where (error as? CKError)?.code != .unknownItem {
            throw error
        }
    }

    public func delete(_ recordNames: [String]) async throws {
        guard !recordNames.isEmpty else { return }
        for name in recordNames { statusRecords[name] = nil }
        let result = try await database.modifyRecords(
            saving: [], deleting: recordNames.map { .init(recordName: $0, zoneID: Self.zoneID) })
        for case .failure(let error) in result.deleteResults.values
        where (error as? CKError)?.code != .unknownItem {
            throw error
        }
    }
}
