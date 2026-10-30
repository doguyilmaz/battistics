import CloudKit
import Foundation
import Testing
@testable import BattisticsRemote

@Suite("CloudKit operation boundary")
struct CloudKitOperationTests {
    private static func acceptBootstrap(_ operation: CKDatabaseOperation) {
        if let zone = operation as? CKModifyRecordZonesOperation {
            zone.modifyRecordZonesResultBlock?(.success(()))
        } else if let subscription = operation as? CKModifySubscriptionsOperation {
            subscription.modifySubscriptionsResultBlock?(.success(()))
        } else { Issue.record("Unexpected bootstrap operation \(operation)") }
    }

    @Test func bootstrapPrecedesTheFirstPageAndIsReused() async throws {
        let submitted = CloudKitBuffer<[String]>([])
        let operations = CloudKitOperations(submit: { operation in
            submitted.update { $0.append(String(describing: type(of: operation))) }
            Self.acceptBootstrap(operation)
        }, readPage: { _ in
            submitted.update { $0.append("native-page") }
            let record = CKRecord(recordType: RemoteCloud.statusType, recordID: .init(recordName: "mac", zoneID: RemoteCloud.zoneID))
            record.encryptedValues["payload"] = try RemoteWire.encode(RemoteStatus(machineName: "Mac", readAt: .now))
            return .init(records: [record.recordID: .success(record)])
        })
        let cloud = RemoteCloud(operations: operations)
        let snapshot = try await cloud.fetch()
        _ = try await cloud.fetch()
        #expect(snapshot.statuses["mac"]?.machineName == "Mac")
        #expect(submitted.read().first == "CKModifyRecordZonesOperation")
        #expect(submitted.read().filter { $0 == "CKModifyRecordZonesOperation" }.count == 1)
        #expect(submitted.read().filter { $0 == "native-page" }.count == 2)
    }

    @Test func aFailedRecordIsNotReportedAsAnEmptySuccessfulSnapshot() async {
        let cloud = RemoteCloud(operations: .init(submit: Self.acceptBootstrap, readPage: { _ in
            .init(records: [.init(recordName: "mac", zoneID: RemoteCloud.zoneID): .failure(CKError(.permissionFailure))])
        }))
        do {
            _ = try await cloud.fetch()
            Issue.record("A failed record must not remove the cached Mac")
        } catch {
            #expect((error as? CKError)?.code == .permissionFailure)
        }
    }

    @Test func inaccessibleEncryptedPayloadIsNotAMissingMac() async {
        let cloud = RemoteCloud(operations: .init(submit: Self.acceptBootstrap, readPage: { _ in
            let record = CKRecord(recordType: RemoteCloud.statusType, recordID: .init(recordName: "mac", zoneID: RemoteCloud.zoneID))
            return .init(records: [record.recordID: .success(record)])
        }))
        await #expect(throws: CKError.self) { try await cloud.fetch() }
    }

    @Test func anUnchangedMacSurvivesAnEmptyDeltaButNotAnExplicitDeletion() {
        let mac = RemoteStatus(machineName: "Mac", readAt: .now)
        var saved = RemoteCloud.Snapshot(statuses: ["mac": mac], isFull: true)
        saved.events["old-event"] = .now
        let unchanged = saved.applying(.init())
        #expect(unchanged.statuses["mac"] == mac)
        var deleted = RemoteCloud.Snapshot()
        deleted.removedRecords = ["mac", "old-event"]
        deleted.removedStatuses = ["mac"]
        let full = unchanged.applying(deleted)
        #expect(full.statuses.isEmpty)
        #expect(full.events.isEmpty)
    }

    @Test func aFullReadReplacesTheSnapshotAndANewerFormatRetainsTheMacAsUnreadable() {
        let mac = RemoteStatus(machineName: "Mac", readAt: .now)
        let saved = RemoteCloud.Snapshot(statuses: ["mac": mac], isFull: true)
        let tooNew = saved.applying(.init(unreadable: ["mac"]))
        #expect(tooNew.statuses["mac"] == nil)
        #expect(tooNew.unreadable.contains("mac"))
        #expect(saved.applying(.init(isFull: true)).statuses.isEmpty)
    }

    @Test func aTimedOutRequestCancelsTheActualSDKOperation() async {
        let entered = RemoteTestGate<CKFetchRecordsOperation>()
        let operations = CloudKitOperations { operation in
            if let fetch = operation as? CKFetchRecordsOperation { Task { await entered.finish(fetch) } }
        }
        let work = Task {
            try await operations.record(.init(recordName: "mac", zoneID: RemoteCloud.zoneID),
                                        until: .now.advanced(by: .milliseconds(80)))
        }
        let operation = await entered.value()
        #expect(operation.configuration.qualityOfService == .userInitiated)
        #expect(operation.configuration.timeoutIntervalForResource <= 0.08)
        await #expect(throws: RemoteDeadline.Failure.self) { try await work.value }
        #expect(operation.isCancelled)
        // A late SDK callback must be harmless and release its continuation.
        operation.fetchRecordsResultBlock?(.failure(CKError(.operationCancelled)))
    }

    @Test func theServerRetryAfterIsRespected() async throws {
        let count = CloudKitBuffer(0)
        let cloud = RemoteCloud(operations: .init(submit: Self.acceptBootstrap, readPage: { _ in
            count.update { $0 += 1 }
            throw CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 60.0])
        }))
        for _ in 0..<2 {
            do { _ = try await cloud.fetch(); Issue.record("Expected throttling") }
            catch { #expect((error as? CKError)?.code == .requestRateLimited) }
        }
        #expect(count.read() == 1)
    }

    @Test func aCommandUsesOneMacRecordNotTheDiscoveryQueue() async throws {
        let request = RemoteRequest(operation: .start, mode: .displayMaySleep, durationMinutes: 30)
        let written = CloudKitBuffer<RemoteRequest?>(nil)
        let operations = CloudKitOperations { operation in
            #expect(operation.configuration.qualityOfService == .userInitiated)
            if let zone = operation as? CKModifyRecordZonesOperation {
                zone.modifyRecordZonesResultBlock?(.success(()))
            } else if let subscription = operation as? CKModifySubscriptionsOperation {
                subscription.modifySubscriptionsResultBlock?(.success(()))
            } else if let write = operation as? CKModifyRecordsOperation {
                for record in write.recordsToSave ?? [] {
                    written.update { $0 = try? RemoteWire.decode(RemoteRequest.self, from: record.encryptedValues["payload"] as! Data) }
                    write.perRecordSaveBlock?(record.recordID, .success(record))
                }
                write.modifyRecordsResultBlock?(.success(()))
            } else if let read = operation as? CKFetchRecordsOperation {
                var status = RemoteStatus(machineName: "Mac", readAt: .now)
                status.lastCommand = .init(id: written.read()!.id, failure: nil)
                let record = CKRecord(recordType: RemoteCloud.statusType, recordID: read.recordIDs!.first!)
                record.encryptedValues["payload"] = try! RemoteWire.encode(status)
                read.perRecordResultBlock?(record.recordID, .success(record))
                read.fetchRecordsResultBlock?(.success(()))
            } else { Issue.record("Discovery must not be used for a command answer") }
        }
        let status = try await RemoteCommandExecutor.execute(request, to: "mac", cloud: RemoteCloud(operations: operations))
        #expect(written.read()?.id == request.id)
        #expect(status.lastCommand?.id == request.id)
    }

    @Test func stalledDiscoveryAndSubscriptionDoNotHoldUpACommand() async throws {
        let discoveryEntered = RemoteTestGate<Bool>()
        let discoveryPage = RemoteTestGate<CloudKitOperations.Changes>()
        let subscriptionEntered = RemoteTestGate<CKModifySubscriptionsOperation>()
        let request = RemoteRequest(operation: .stop)
        let operations = CloudKitOperations(submit: { operation in
            if let zone = operation as? CKModifyRecordZonesOperation {
                zone.modifyRecordZonesResultBlock?(.success(()))
            } else if let subscription = operation as? CKModifySubscriptionsOperation {
                Task { await subscriptionEntered.finish(subscription) }
            } else if let write = operation as? CKModifyRecordsOperation {
                for record in write.recordsToSave ?? [] { write.perRecordSaveBlock?(record.recordID, .success(record)) }
                write.modifyRecordsResultBlock?(.success(()))
            } else if let read = operation as? CKFetchRecordsOperation {
                var status = RemoteStatus(machineName: "Mac", readAt: .now)
                status.lastCommand = .init(id: request.id, failure: nil)
                let record = CKRecord(recordType: RemoteCloud.statusType, recordID: read.recordIDs!.first!)
                record.encryptedValues["payload"] = try! RemoteWire.encode(status)
                read.perRecordResultBlock?(record.recordID, .success(record))
                read.fetchRecordsResultBlock?(.success(()))
            } else { Issue.record("Unexpected command operation") }
        }, readPage: { _ in
            await discoveryEntered.finish(true)
            return await discoveryPage.value()
        })
        let cloud = RemoteCloud(operations: operations)
        let background = Task { try await cloud.fetch(until: .now.advanced(by: .seconds(2))) }
        _ = await discoveryEntered.value()
        let started = ContinuousClock.now
        let answer = try await RemoteCommandExecutor.execute(request, to: "mac", cloud: cloud)
        #expect(answer.lastCommand?.id == request.id)
        #expect(started.duration(to: .now) < .seconds(2))
        await discoveryPage.finish(.init())
        _ = try await background.value
        let subscription = await subscriptionEntered.value()
        subscription.modifySubscriptionsResultBlock?(.success(()))
    }

    @Test func aNativePageDoesNotWaitForAnAggregateOperationCallback() async throws {
        let operations = CloudKitOperations(submit: { _ in
            Issue.record("A native zone page must not be submitted as an aggregate operation")
        }, readPage: { _ in .init(moreComing: true) })
        let page = try await operations.changes(since: nil, until: .now.advanced(by: .seconds(2)))
        #expect(page.moreComing)
    }

    @Test func aMissingContinuationCursorDoesNotReplayPageOne() async {
        let reads = CloudKitBuffer(0)
        let cloud = RemoteCloud(operations: .init(submit: Self.acceptBootstrap, readPage: { _ in
            reads.update { $0 += 1 }
            return .init(moreComing: true)
        }))
        await #expect(throws: CKError.self) { try await cloud.fetch() }
        #expect(reads.read() == 1)
    }
}
