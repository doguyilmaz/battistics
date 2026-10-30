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
        var moreComing = false
    }

    private let submit: @Sendable (CKDatabaseOperation) -> Void
    private let readPage: @Sendable (CKServerChangeToken?) async throws -> Changes
    private let trace = RemoteConnectionTrace()
    private static let logger = Logger(subsystem: "com.doguyilmaz.Battistics.Remote", category: "CloudKit")

    init(database: CKDatabase) {
        submit = { database.add($0) }
        readPage = { token in
            // The same batch boundary used by the working build (3). Do not
            // replace this with fetchAllChanges + operation-wide completion:
            // the account's first page must not depend on that aggregate tail.
            let page = try await database.recordZoneChanges(inZoneWith: RemoteCloud.zoneID, since: token)
            return Changes(
                records: page.modificationResultsByID.mapValues { $0.map { $0.record } },
                deletions: Dictionary(page.deletions.map { ($0.recordID, $0.recordType) }, uniquingKeysWith: { _, new in new }),
                token: page.changeToken, moreComing: page.moreComing)
        }
    }

    /// Operation-backed requests can be exercised without a signed account.
    /// Zone reads use the separate native-page seam below.
    init(submit: @escaping @Sendable (CKDatabaseOperation) -> Void) {
        self.submit = submit
        readPage = { _ in throw CKError(.internalError) }
    }

    init(submit: @escaping @Sendable (CKDatabaseOperation) -> Void,
         readPage: @escaping @Sendable (CKServerChangeToken?) async throws -> Changes) {
        self.submit = submit
        self.readPage = readPage
    }

    func changes(since token: CKServerChangeToken?, until deadline: ContinuousClock.Instant) async throws -> Changes {
        let started = ContinuousClock.now
        let id = UUID().uuidString
        trace.record(.started, phase: .zonePage, id: id)
        do {
            let changes = try await RemoteDeadline.perform(until: deadline) {
                try await readPage(token)
            }
            // Preserve the partial-failure fix: an unreadable record is not
            // evidence that a Mac has disappeared.
            for record in changes.records.values { _ = try record.get() }
            trace.record(.finished, phase: .zonePage, id: id)
            Self.logger.notice("Zone page received in \(String(describing: started.duration(to: .now)), privacy: .public): \(changes.records.count) records, \(changes.deletions.count) deletions, more \(changes.moreComing)")
            return changes
        } catch {
            trace.record(.failed(error), phase: .zonePage, id: id)
            let domain = (error as NSError).domain
            let code = (error as NSError).code
            Self.logger.error("Zone page failed in \(String(describing: started.duration(to: .now)), privacy: .public), domain \(domain, privacy: .public), code \(code)")
            throw error
        }
    }

    func record(_ id: CKRecord.ID, until deadline: ContinuousClock.Instant) async throws -> CKRecord? {
        let operation = CKFetchRecordsOperation(recordIDs: [id])
        let buffer = CloudKitBuffer<Result<CKRecord, Error>?>(nil)
        let trace = trace
        let requestID = operation.operationID
        do {
            return try await perform(operation, phase: .recordRead, until: deadline) { finish in
                operation.perRecordResultBlock = { _, result in
                    buffer.update { $0 = result }
                    trace.record(.item(result.map { _ in () }), phase: .recordRead, id: requestID)
                }
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
        let trace = trace
        let requestID = operation.operationID
        return try await perform(operation, phase: .recordWrite, until: deadline) { finish in
            operation.perRecordSaveBlock = { id, result in
                completed.update { $0 += 1 }
                trace.record(.item(result.map { _ in () }), phase: .recordWrite, id: requestID)
                switch result {
                case .success(let record): saved.update { $0[id] = record }
                case .failure(let error): failures.update { $0.append(error) }
                }
            }
            operation.perRecordDeleteBlock = { _, result in
                completed.update { $0 += 1 }
                trace.record(.item(result), phase: .recordWrite, id: requestID)
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
        let trace = trace
        let requestID = operation.operationID
        try await perform(operation, phase: .zoneSetup, until: deadline) { finish in
            operation.perRecordZoneSaveBlock = { _, result in
                if case .failure(let error) = result { failure.update { $0 = error } }
                trace.record(.item(result.map { _ in () }), phase: .zoneSetup, id: requestID)
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
        let trace = trace
        let requestID = operation.operationID
        do {
            return try await perform(operation, phase: .subscriptionRead, until: deadline) { finish in
                operation.perSubscriptionResultBlock = { _, result in
                    buffer.update { $0 = result }
                    trace.record(.item(result.map { _ in () }), phase: .subscriptionRead, id: requestID)
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
        let trace = trace
        let requestID = operation.operationID
        try await perform(operation, phase: .subscriptionWrite, until: deadline) { finish in
            operation.perSubscriptionSaveBlock = { _, result in
                trace.record(.item(result.map { _ in () }), phase: .subscriptionWrite, id: requestID)
                if case .failure(let error) = result { failure.update { $0 = error } }
            }
            operation.perSubscriptionDeleteBlock = { _, result in
                trace.record(.item(result), phase: .subscriptionWrite, id: requestID)
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
        _ operation: CKDatabaseOperation, phase tracePhase: RemoteConnectionTrace.Phase, until deadline: ContinuousClock.Instant,
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
        trace.record(.started, phase: tracePhase, id: id)
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
            trace.record(.finished, phase: tracePhase, id: id)
            return value
        } catch {
            operation.cancel()
            trace.record(.failed(error), phase: tracePhase, id: id)
            let code = (error as? CKError)?.errorCode ?? (error as NSError).code
            let retry = (error as? CKError)?.retryAfterSeconds ?? 0
            Self.logger.error("\(phase, privacy: .public) \(id, privacy: .public) failed in \(String(describing: started.duration(to: .now)), privacy: .public), code \(code), retry \(retry)s")
            throw error
        }
    }

    func connectionReport() -> String { trace.report() }
}
