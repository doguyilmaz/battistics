import CloudKit
import Foundation
import os

/// The SDK's convenience async calls do not expose operation lifetime or QoS.
/// Keep those policies at the CloudKit boundary, not in a polling UI task.
struct CloudKitOperations: Sendable {
    private let submit: @Sendable (CKDatabaseOperation) -> Void
    private static let logger = Logger(subsystem: "com.doguyilmaz.Battistics.Remote", category: "CloudKit")

    init(database: CKDatabase) {
        submit = { database.add($0) }
    }

    init(submit: @escaping @Sendable (CKDatabaseOperation) -> Void) {
        self.submit = submit
    }

    /// The records of one type as they are now. Never the zone's change log:
    /// every heartbeat a Mac ever wrote stays in that log, and replaying it
    /// grows slower for as long as the account uses Battistics.
    func query(_ recordType: CKRecord.RecordType, until deadline: ContinuousClock.Instant) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let operation = cursor.map { CKQueryOperation(cursor: $0) }
                ?? CKQueryOperation(query: CKQuery(recordType: recordType, predicate: NSPredicate(value: true)))
            operation.zoneID = RemoteCloud.zoneID
            let page = CloudKitBuffer<[Result<CKRecord, Error>]>([])
            cursor = try await perform(operation, until: deadline) { finish in
                operation.recordMatchedBlock = { _, result in
                    page.update { $0.append(result) }
                }
                operation.queryResultBlock = { result in
                    finish(Result { try result.get() })
                }
            }
            // An unreadable record is not evidence that a Mac has disappeared.
            records += try page.read().map { try $0.get() }
        } while cursor != nil
        return records
    }

    /// Missing records are left out of the result.
    func records(_ ids: [CKRecord.ID], until deadline: ContinuousClock.Instant) async throws -> [CKRecord.ID: CKRecord] {
        let operation = CKFetchRecordsOperation(recordIDs: ids)
        let found = CloudKitBuffer<[CKRecord.ID: CKRecord]>([:])
        let failure = CloudKitBuffer<Error?>(nil)
        return try await perform(operation, until: deadline) { finish in
            operation.perRecordResultBlock = { id, result in
                switch result {
                case .success(let record): found.update { $0[id] = record }
                case .failure(let error as CKError) where error.code == .unknownItem: break
                case .failure(let error): failure.update { $0 = error }
                }
            }
            operation.fetchRecordsResultBlock = { result in
                finish(Result {
                    if let error = failure.read() { throw error }
                    // Only missing records are left in a partial failure here.
                    if case .failure(let error) = result, (error as? CKError)?.code != .partialFailure { throw error }
                    return found.read()
                })
            }
        }
    }

    func record(_ id: CKRecord.ID, until deadline: ContinuousClock.Instant) async throws -> CKRecord? {
        try await records([id], until: deadline)[id]
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
                operation.perSubscriptionResultBlock = { _, result in
                    buffer.update { $0 = result }
                }
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
