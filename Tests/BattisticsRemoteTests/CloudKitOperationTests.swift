import CloudKit
import Foundation
import Testing
@testable import BattisticsRemote

@Suite("CloudKit operation boundary")
struct CloudKitOperationTests {
    @Test func lateCleanupCannotEraseAnotherPhonesCommand() async throws {
        let newer = RemoteRequest(operation: .stop)
        let writes = CloudKitBuffer(0)
        let cloud = RemoteCloud(operations: .init { operation in
            if let read = operation as? CKFetchRecordsOperation, let id = read.recordIDs?.first {
                let record = CKRecord(recordType: RemoteCloud.commandType, recordID: id)
                record.encryptedValues["payload"] = try! RemoteWire.encode(newer)
                read.perRecordResultBlock?(id, .success(record))
                read.fetchRecordsResultBlock?(.success(()))
            } else if let write = operation as? CKModifyRecordsOperation {
                writes.update { $0 += 1 }
                write.modifyRecordsResultBlock?(.success(()))
            } else { Issue.record("Unexpected cleanup operation") }
        })
        try await cloud.cancelCommand("older-command", macID: "mac")
        #expect(writes.read() == 0)
    }

    @Test func cleanupUsesAConditionalTombstoneInsteadOfDeletingTheSlot() async throws {
        let request = RemoteRequest(operation: .start)
        let writes = CloudKitBuffer(0)
        let cloud = RemoteCloud(operations: .init { operation in
            if let read = operation as? CKFetchRecordsOperation, let id = read.recordIDs?.first {
                let record = CKRecord(recordType: RemoteCloud.commandType, recordID: id)
                record.encryptedValues["payload"] = try! RemoteWire.encode(request)
                read.perRecordResultBlock?(id, .success(record))
                read.fetchRecordsResultBlock?(.success(()))
            } else if let write = operation as? CKModifyRecordsOperation {
                writes.update { $0 += 1 }
                #expect(write.savePolicy == .ifServerRecordUnchanged)
                #expect(write.recordIDsToDelete?.isEmpty ?? true)
                for record in write.recordsToSave ?? [] {
                    #expect(record.encryptedValues["payload"] as? Data == Data("{}".utf8))
                    write.perRecordSaveBlock?(record.recordID, .success(record))
                }
                write.modifyRecordsResultBlock?(.success(()))
            } else { Issue.record("Unexpected cleanup operation") }
        })
        try await cloud.cancelCommand(request.id, macID: "mac")
        #expect(writes.read() == 1)
    }

    @Test func nearbyCredentialsUseAnImmutableNameInTheExistingEncryptedSchema() async throws {
        let credential = try NearbyCredential(macID: "mac", key: Data(repeating: 42, count: 32))
        let stored = CloudKitBuffer<Data?>(nil)
        let cloud = RemoteCloud(operations: .init { operation in
            if let zone = operation as? CKModifyRecordZonesOperation { zone.modifyRecordZonesResultBlock?(.success(())) }
            else if let subscription = operation as? CKModifySubscriptionsOperation { subscription.modifySubscriptionsResultBlock?(.success(())) }
            else if let read = operation as? CKFetchRecordsOperation {
                for id in read.recordIDs ?? [] {
                    if let payload = stored.read() {
                        let record = CKRecord(recordType: RemoteCloud.commandType, recordID: id)
                        record.encryptedValues["payload"] = payload
                        read.perRecordResultBlock?(id, .success(record))
                    } else { read.perRecordResultBlock?(id, .failure(CKError(.unknownItem))) }
                }
                read.fetchRecordsResultBlock?(.success(()))
            } else if let write = operation as? CKModifyRecordsOperation {
                for record in write.recordsToSave ?? [] {
                    #expect(record.recordType == RemoteCloud.commandType)
                    #expect(record.recordID.recordName == RemoteCloud.nearbyCredentialRecordName(for: "mac", discoveryID: credential.discoveryID))
                    stored.update { $0 = record.encryptedValues["payload"] as? Data }
                    write.perRecordSaveBlock?(record.recordID, .success(record))
                }
                write.modifyRecordsResultBlock?(.success(()))
            } else { Issue.record("Unexpected credential operation") }
        })
        try await cloud.publishNearbyCredential(credential)
        #expect(try await cloud.nearbyCredential(macID: "mac", discoveryID: credential.discoveryID) == credential)
        await #expect(throws: NearbyError.self) { try await cloud.nearbyCredential(macID: "mac", discoveryID: "wrong-id") }
    }

    @Test func retryingAnUncertainEventSaveDoesNotCreateAnotherPush() async throws {
        let stored = CloudKitBuffer<CKRecord?>(nil)
        let creations = CloudKitBuffer(0)
        let writes = CloudKitBuffer<[String]>([])
        let cloud = RemoteCloud(operations: .init { operation in
            if let zone = operation as? CKModifyRecordZonesOperation {
                zone.modifyRecordZonesResultBlock?(.success(()))
            } else if let subscription = operation as? CKModifySubscriptionsOperation {
                subscription.modifySubscriptionsResultBlock?(.success(()))
            } else if let write = operation as? CKModifyRecordsOperation {
                for record in write.recordsToSave ?? [] {
                    writes.update { $0.append(record.recordID.recordName) }
                    let error: CKError
                    if stored.read() == nil {
                        stored.update { $0 = record }
                        creations.update { $0 += 1 }
                        error = CKError(.networkFailure)
                    } else {
                        error = CKError(.serverRecordChanged)
                    }
                    write.perRecordSaveBlock?(record.recordID, .failure(error))
                }
                write.modifyRecordsResultBlock?(.failure(CKError(.partialFailure)))
            } else if let read = operation as? CKFetchRecordsOperation, let record = stored.read() {
                read.perRecordResultBlock?(record.recordID, .success(record))
                read.fetchRecordsResultBlock?(.success(()))
            } else {
                Issue.record("Unexpected event operation: \(operation)")
            }
        })
        await #expect(throws: CKError.self) {
            try await cloud.post("one-event", title: "Hot", body: "Check the Mac", collapseID: "mac.hot")
        }
        try await cloud.post("one-event", title: "Hot", body: "Check the Mac", collapseID: "mac.hot")
        #expect(creations.read() == 1)
        #expect(writes.read() == ["one-event", "one-event"])
        await #expect(throws: CKError.self) {
            try await cloud.post("one-event", title: "Different", body: "Check the Mac", collapseID: "mac.hot")
        }
    }

    private static func statusRecord(_ name: String, _ status: RemoteStatus? = RemoteStatus(machineName: "Mac", readAt: .now)) -> CKRecord {
        let record = CKRecord(recordType: RemoteCloud.statusType, recordID: .init(recordName: name, zoneID: RemoteCloud.zoneID))
        if let status { record.encryptedValues["payload"] = try! RemoteWire.encode(status) }
        return record
    }

    /// Answers discovery and direct reads, optionally simulating a lagging index.
    private static func answering(_ records: [Result<CKRecord, Error>], queries: CloudKitBuffer<Int>? = nil,
                                  current: [CKRecord]? = nil, reads: CloudKitBuffer<Int>? = nil,
                                  readError: Error? = nil, failing error: Error? = nil) -> @Sendable (CKDatabaseOperation) -> Void {
        { operation in
            if let query = operation as? CKQueryOperation {
                queries?.update { $0 += 1 }
                #expect(query.zoneID == RemoteCloud.zoneID)
                #expect(query.query?.recordType == RemoteCloud.statusType)
                if let error { query.queryResultBlock?(.failure(error)); return }
                for record in records {
                    let id = (try? record.get())?.recordID ?? .init(recordName: "mac", zoneID: RemoteCloud.zoneID)
                    query.recordMatchedBlock?(id, record)
                }
                query.queryResultBlock?(.success(nil))
            } else if let read = operation as? CKFetchRecordsOperation {
                reads?.update { $0 += 1 }
                if let readError { read.fetchRecordsResultBlock?(.failure(readError)); return }
                let available = current ?? records.compactMap { try? $0.get() }
                for id in read.recordIDs ?? [] {
                    if let record = available.first(where: { $0.recordID == id }) {
                        read.perRecordResultBlock?(id, .success(record))
                    } else {
                        read.perRecordResultBlock?(id, .failure(CKError(.unknownItem)))
                    }
                }
                read.fetchRecordsResultBlock?(.success(()))
            } else if let subscription = operation as? CKModifySubscriptionsOperation {
                subscription.modifySubscriptionsResultBlock?(.success(()))
            } else { Issue.record("Discovery must not set up or replay the zone: \(operation)") }
        }
    }

    @Test func discoveryReadsCurrentRecordsWithoutZoneSetupOrHistory() async throws {
        let queries = CloudKitBuffer(0)
        let reads = CloudKitBuffer(0)
        let cloud = RemoteCloud(operations: .init(submit: Self.answering(
            [.success(Self.statusRecord("mac"))], queries: queries, reads: reads)))
        let snapshot = try await cloud.fetch()
        _ = try await cloud.fetch()
        #expect(snapshot.statuses["mac"]?.machineName == "Mac")
        #expect(queries.read() == 2)
        #expect(reads.read() == 2)
    }

    @Test func aLaggingQueryCannotKeepAnOldReadingOnThePhone() async throws {
        let old = RemoteStatus(machineName: "Mac", readAt: .now.addingTimeInterval(-3 * 3600))
        let fresh = RemoteStatus(machineName: "Mac", readAt: Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970)))
        let cloud = RemoteCloud(operations: .init(submit: Self.answering(
            [.success(Self.statusRecord("mac", old))], current: [Self.statusRecord("mac", fresh)])))
        let snapshot = try await cloud.fetch()
        #expect(snapshot.statuses["mac"]?.readAt == fresh.readAt)
        #expect(snapshot.statuses["mac"]?.isFresh() == true)
    }

    @Test func aKnownMacMissingFromTheIndexIsStillRead() async throws {
        let fresh = RemoteStatus(machineName: "Mac", readAt: Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970)))
        let cloud = RemoteCloud(operations: .init(submit: Self.answering([], current: [Self.statusRecord("mac", fresh)])))
        let snapshot = try await cloud.fetch(knownMacIDs: ["mac"])
        #expect(snapshot.statuses["mac"]?.readAt == fresh.readAt)
    }

    @Test func aDeletedRecordStillInTheIndexDoesNotResurrectTheMac() async throws {
        let cloud = RemoteCloud(operations: .init(submit: Self.answering([.success(Self.statusRecord("mac"))], current: [])))
        let snapshot = try await cloud.fetch(knownMacIDs: ["mac"])
        #expect(snapshot.statuses.isEmpty)
        #expect(snapshot.unreadable.isEmpty)
    }

    @Test func aFailedDirectReadDoesNotFallBackToTheIndexedStatus() async {
        let cloud = RemoteCloud(operations: .init(submit: Self.answering(
            [.success(Self.statusRecord("mac"))], readError: CKError(.networkFailure))))
        await #expect(throws: CKError.self) { try await cloud.fetch(knownMacIDs: ["mac"]) }
    }

    @Test func aZoneNoMacCreatedYetMeansNoMacs() async throws {
        let cloud = RemoteCloud(operations: .init(submit: Self.answering([], failing: CKError(.zoneNotFound))))
        #expect(try await cloud.fetch().statuses.isEmpty)
    }

    @Test func aFailedRecordIsNotReportedAsAnEmptySuccessfulSnapshot() async {
        let cloud = RemoteCloud(operations: .init(submit: Self.answering([.failure(CKError(.permissionFailure))])))
        do {
            _ = try await cloud.fetch()
            Issue.record("A failed record must not remove the cached Mac")
        } catch {
            #expect((error as? CKError)?.code == .permissionFailure)
        }
    }

    @Test func inaccessibleEncryptedPayloadIsNotAMissingMac() async {
        let cloud = RemoteCloud(operations: .init(submit: Self.answering([.success(Self.statusRecord("mac", nil))])))
        await #expect(throws: CKError.self) { try await cloud.fetch() }
    }

    @Test func aNewerFormatRetainsTheMacAsUnreadable() async throws {
        let record = Self.statusRecord("mac", nil)
        record.encryptedValues["payload"] = Data("{}".utf8)
        let cloud = RemoteCloud(operations: .init(submit: Self.answering([.success(record)])))
        let snapshot = try await cloud.fetch()
        #expect(snapshot.statuses.isEmpty)
        #expect(snapshot.unreadable == ["mac"])
    }

    @Test func theMacReadsItsRecordAndCommandSlotByNameInOneRequest() async throws {
        let request = RemoteRequest(operation: .stop)
        let fetches = CloudKitBuffer<[[String]]>([])
        let cloud = RemoteCloud(operations: .init { operation in
            if let zone = operation as? CKModifyRecordZonesOperation {
                zone.modifyRecordZonesResultBlock?(.success(()))
            } else if let subscription = operation as? CKModifySubscriptionsOperation {
                subscription.modifySubscriptionsResultBlock?(.success(()))
            } else if let read = operation as? CKFetchRecordsOperation {
                let ids = read.recordIDs ?? []
                fetches.update { $0.append(ids.map(\.recordName)) }
                read.perRecordResultBlock?(ids[0], .failure(CKError(.unknownItem)))
                let slot = CKRecord(recordType: RemoteCloud.commandType, recordID: ids[1])
                slot.encryptedValues["payload"] = try! RemoteWire.encode(request)
                read.perRecordResultBlock?(ids[1], .success(slot))
                read.fetchRecordsResultBlock?(.failure(CKError(.partialFailure)))
            } else { Issue.record("The Mac must not query or replay the zone: \(operation)") }
        })
        let inbox = try await cloud.inbox(macID: "mac")
        #expect(fetches.read() == [["mac", RemoteCloud.commandRecordName(for: "mac")]])
        #expect(inbox.status == nil)
        #expect(inbox.command?.id == request.id)
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
        let queries = CloudKitBuffer(0)
        let cloud = RemoteCloud(operations: .init(submit: Self.answering(
            [], queries: queries, failing: CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 60.0]))))
        for _ in 0..<2 {
            do { _ = try await cloud.fetch(); Issue.record("Expected throttling") }
            catch { #expect((error as? CKError)?.code == .requestRateLimited) }
        }
        #expect(queries.read() == 1)
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
        let discovery = RemoteTestGate<CKQueryOperation>()
        let subscriptionEntered = RemoteTestGate<CKModifySubscriptionsOperation>()
        let request = RemoteRequest(operation: .stop)
        let operations = CloudKitOperations(submit: { operation in
            if let query = operation as? CKQueryOperation {
                Task { await discovery.finish(query) }
            } else if let zone = operation as? CKModifyRecordZonesOperation {
                zone.modifyRecordZonesResultBlock?(.success(()))
            } else if let subscription = operation as? CKModifySubscriptionsOperation {
                Task { await subscriptionEntered.finish(subscription) }
            } else if let write = operation as? CKModifyRecordsOperation {
                #expect(write.savePolicy == .allKeys)
                for record in write.recordsToSave ?? [] {
                    #expect(record.recordID.recordName == RemoteCloud.commandRecordName(for: "mac"))
                    write.perRecordSaveBlock?(record.recordID, .success(record))
                }
                write.modifyRecordsResultBlock?(.success(()))
            } else if let read = operation as? CKFetchRecordsOperation {
                var status = RemoteStatus(machineName: "Mac", readAt: .now)
                status.lastCommand = .init(id: request.id, failure: nil)
                let record = CKRecord(recordType: RemoteCloud.statusType, recordID: read.recordIDs!.first!)
                record.encryptedValues["payload"] = try! RemoteWire.encode(status)
                read.perRecordResultBlock?(record.recordID, .success(record))
                read.fetchRecordsResultBlock?(.success(()))
            } else { Issue.record("Unexpected command operation") }
        })
        let cloud = RemoteCloud(operations: operations)
        let background = Task { try await cloud.fetch(until: .now.advanced(by: .seconds(2))) }
        let query = await discovery.value()
        let started = ContinuousClock.now
        let answer = try await RemoteCommandExecutor.execute(request, to: "mac", cloud: cloud)
        #expect(answer.lastCommand?.id == request.id)
        #expect(started.duration(to: .now) < .seconds(2))
        query.queryResultBlock?(.success(nil))
        _ = try await background.value
        let subscription = await subscriptionEntered.value()
        subscription.modifySubscriptionsResultBlock?(.success(()))
    }
}
