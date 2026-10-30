import CloudKit
import Foundation
import os

/// The SDK's convenience async calls do not expose operation lifetime or QoS.
/// Keep those policies at the CloudKit boundary, not in a polling UI task.
struct CloudKitOperations: Sendable {
    struct Changes: Sendable {
        var records: [CKRecord.ID: Result<CKRecord, Error>] = [:]
        var deletions: [CKRecord.ID: CKRecord.RecordType] = [:]
        var token: CKServerChangeToken?
        var zoneError: Error?
    }

    private let submit: @Sendable (CKDatabaseOperation) -> Void
    private static let logger = Logger(subsystem: "com.doguyilmaz.Battistics.Remote", category: "CloudKit")

    init(database: CKDatabase) { submit = { database.add($0) } }

    /// An operation-level seam: tests execute the real callback and deadline
    /// code without an iCloud account, signed app or a live network.
    init(submit: @escaping @Sendable (CKDatabaseOperation) -> Void) { self.submit = submit }

    func changes(since token: CKServerChangeToken?, until deadline: ContinuousClock.Instant) async throws -> Changes {
        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration(previousServerChangeToken: token)
        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [RemoteCloud.zoneID], configurationsByRecordZoneID: [RemoteCloud.zoneID: configuration])
        operation.fetchAllChanges = true
        let buffer = CloudKitBuffer(Changes())
        return try await perform(operation, until: deadline) { finish in
            operation.recordWasChangedBlock = { id, result in
                buffer.update { $0.records[id] = result; $0.deletions[id] = nil }
            }
            operation.recordWithIDWasDeletedBlock = { id, type in
                buffer.update { $0.records[id] = nil; $0.deletions[id] = type }
            }
            operation.recordZoneFetchResultBlock = { _, result in
                buffer.update { changes in
                    switch result {
                    case .success(let page): changes.token = page.serverChangeToken
                    case .failure(let error): changes.zoneError = error
                    }
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                finish(Result {
                    try result.get()
                    let changes = buffer.read()
                    if let error = changes.zoneError { throw error }
                    // A failed record is not a missing Mac. Do not advance the
                    // token or let a full fetch erase the phone's saved Macs.
                    for record in changes.records.values { _ = try record.get() }
                    return changes
                })
            }
        }
    }

    func record(_ id: CKRecord.ID, until deadline: ContinuousClock.Instant) async throws -> CKRecord? {
        let operation = CKFetchRecordsOperation(recordIDs: [id])
        let buffer = CloudKitBuffer<Result<CKRecord, Error>?>(nil)
        do {
            return try await perform(operation, until: deadline) { finish in
                operation.perRecordResultBlock = { _, result in buffer.update { $0 = result } }
                operation.fetchRecordsResultBlock = { result in
                    finish(Result {
                        if let record = buffer.read() { return try record.get() }
                        try result.get()
                        throw CKError(.internalError)
                    })
                }
            }
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func modifyRecords(saving records: [CKRecord] = [], deleting ids: [CKRecord.ID] = [],
                       policy: CKModifyRecordsOperation.RecordSavePolicy = .ifServerRecordUnchanged,
                       until deadline: ContinuousClock.Instant) async throws -> [CKRecord.ID: CKRecord] {
        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: ids)
        operation.savePolicy = policy
        let saved = CloudKitBuffer<[CKRecord.ID: CKRecord]>([:])
        let failures = CloudKitBuffer<[Error]>([])
        let ignoredDeletions = CloudKitBuffer(0)
        let completed = CloudKitBuffer(0)
        return try await perform(operation, until: deadline) { finish in
            operation.perRecordSaveBlock = { id, result in
                completed.update { $0 += 1 }
                switch result {
                case .success(let record): saved.update { $0[id] = record }
                case .failure(let error): failures.update { $0.append(error) }
                }
            }
            operation.perRecordDeleteBlock = { _, result in
                completed.update { $0 += 1 }
                if case .failure(let error) = result {
                    if (error as? CKError)?.code == .unknownItem { ignoredDeletions.update { $0 += 1 } }
                    else { failures.update { $0.append(error) } }
                }
            }
            operation.modifyRecordsResultBlock = { result in
                finish(Result {
                    if let error = failures.read().first { throw error }
                    if case .failure(let error) = result,
                       !((error as? CKError)?.code == .partialFailure && ignoredDeletions.read() > 0
                         && completed.read() == records.count + ids.count) { throw error }
                    return saved.read()
                })
            }
        }
    }

    func createZone(until deadline: ContinuousClock.Instant) async throws {
        let operation = CKModifyRecordZonesOperation(recordZonesToSave: [CKRecordZone(zoneID: RemoteCloud.zoneID)])
        let failure = CloudKitBuffer<Error?>(nil)
        try await perform(operation, until: deadline) { finish in
            operation.perRecordZoneSaveBlock = { _, result in
                if case .failure(let error) = result { failure.update { $0 = error } }
            }
            operation.modifyRecordZonesResultBlock = { result in
                finish(Result {
                    if let error = failure.read() { throw error }
                    try result.get()
                })
            }
        }
    }

    func subscription(_ id: String, until deadline: ContinuousClock.Instant) async throws -> CKSubscription? {
        let operation = CKFetchSubscriptionsOperation(subscriptionIDs: [id])
        let buffer = CloudKitBuffer<Result<CKSubscription, Error>?>(nil)
        do {
            return try await perform(operation, until: deadline) { finish in
                operation.perSubscriptionResultBlock = { _, result in buffer.update { $0 = result } }
                operation.fetchSubscriptionsResultBlock = { result in
                    finish(Result {
                        if let subscription = buffer.read() { return try subscription.get() }
                        try result.get()
                        throw CKError(.internalError)
                    })
                }
            }
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func modifySubscriptions(saving subscriptions: [CKSubscription] = [], deleting ids: [String] = [],
                             until deadline: ContinuousClock.Instant) async throws {
        let operation = CKModifySubscriptionsOperation(subscriptionsToSave: subscriptions, subscriptionIDsToDelete: ids)
        let failure = CloudKitBuffer<Error?>(nil)
        let ignoredDeletion = CloudKitBuffer(false)
        try await perform(operation, until: deadline) { finish in
            operation.perSubscriptionSaveBlock = { _, result in
                if case .failure(let error) = result { failure.update { $0 = error } }
            }
            operation.perSubscriptionDeleteBlock = { _, result in
                if case .failure(let error) = result {
                    if (error as? CKError)?.code == .unknownItem { ignoredDeletion.update { $0 = true } }
                    else { failure.update { $0 = error } }
                }
            }
            operation.modifySubscriptionsResultBlock = { result in
                finish(Result {
                    if let error = failure.read() { throw error }
                    if case .failure(let error) = result,
                       !((error as? CKError)?.code == .partialFailure && ignoredDeletion.read()) { throw error }
                })
            }
        }
    }

    private func perform<Value: Sendable>(
        _ operation: CKDatabaseOperation, until deadline: ContinuousClock.Instant,
        callbacks: @escaping @Sendable (@escaping @Sendable (Result<Value, Error>) -> Void) -> Void
    ) async throws -> Value {
        let remaining = ContinuousClock.now.duration(to: deadline).components
        let seconds = max(0.01, Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18)
        let configuration = CKOperation.Configuration()
        configuration.qualityOfService = .userInitiated
        configuration.timeoutIntervalForRequest = min(30, seconds)
        configuration.timeoutIntervalForResource = seconds
        operation.configuration = configuration
        let id = operation.operationID
        let phase = String(describing: type(of: operation))
        let started = ContinuousClock.now
        Self.logger.info("\(phase, privacy: .public) \(id, privacy: .public) started")
        do {
            let value: Value = try await RemoteDeadline.perform(until: deadline) {
                try await withTaskCancellationHandler {
                    try Task.checkCancellation()
                    return try await withCheckedThrowingContinuation { continuation in
                        callbacks { continuation.resume(with: $0) }
                        if Task.isCancelled { operation.cancel() }
                        submit(operation)
                    }
                } onCancel: {
                    operation.cancel()
                }
            }
            Self.logger.info("\(phase, privacy: .public) \(id, privacy: .public) finished in \(String(describing: started.duration(to: .now)), privacy: .public)")
            return value
        } catch {
            operation.cancel()
            let code = (error as? CKError)?.errorCode ?? (error as NSError).code
            let retry = (error as? CKError)?.retryAfterSeconds ?? 0
            Self.logger.error("\(phase, privacy: .public) \(id, privacy: .public) failed in \(String(describing: started.duration(to: .now)), privacy: .public), code \(code), retry \(retry)s")
            throw error
        }
    }
}
