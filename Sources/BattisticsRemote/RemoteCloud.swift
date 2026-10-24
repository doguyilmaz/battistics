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

    public struct Snapshot: Sendable {
        public var statuses: [String: RemoteStatus] = [:]
        public var commands: [Command] = []
    }

    public struct Command: Sendable {
        public let recordName: String
        public let macID: String
        public let request: RemoteRequest
    }

    private let database: CKDatabase
    private var prepared = false
    private var statusRecords: [String: CKRecord] = [:]

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

    public func accountAvailable() async -> Bool {
        (try? await CKContainer(identifier: Self.containerID).accountStatus()) == .available
    }

    /// Creates the zone and a silent push subscription for changes in it.
    /// Subscriptions belong to the account, not the device, so every device
    /// saves the same one.
    public func prepare() async throws {
        guard !prepared else { return }
        let zones = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: Self.zoneID)], deleting: [])
        for result in zones.saveResults.values { _ = try result.get() }
        let subscription = CKRecordZoneSubscription(zoneID: Self.zoneID, subscriptionID: "remote-zone")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try? await database.modifySubscriptions(saving: [subscription], deleting: [])
        prepared = true
    }

    /// The whole zone is a handful of small records, so it is read in full.
    public func fetch() async throws -> Snapshot {
        try await prepare()
        var snapshot = Snapshot()
        var token: CKServerChangeToken?
        repeat {
            let changes = try await database.recordZoneChanges(inZoneWith: Self.zoneID, since: token)
            for case .success(let modification) in changes.modificationResultsByID.values {
                let record = modification.record
                guard let payload = record.encryptedValues["payload"] as? Data else { continue }
                switch record.recordType {
                case Self.statusType:
                    statusRecords[record.recordID.recordName] = record
                    if let status = try? RemoteWire.decode(RemoteStatus.self, from: payload) {
                        snapshot.statuses[record.recordID.recordName] = status
                    }
                case Self.commandType:
                    if let request = try? RemoteWire.decode(RemoteRequest.self, from: payload),
                       let mac = record["mac"] as? String {
                        snapshot.commands.append(.init(recordName: record.recordID.recordName, macID: mac, request: request))
                    }
                default: break
                }
            }
            token = changes.changeToken
            if !changes.moreComing { break }
        } while true
        return snapshot
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

    public func delete(_ recordNames: [String]) async throws {
        guard !recordNames.isEmpty else { return }
        for name in recordNames { statusRecords[name] = nil }
        _ = try await database.modifyRecords(
            saving: [], deleting: recordNames.map { .init(recordName: $0, zoneID: Self.zoneID) })
    }
}
