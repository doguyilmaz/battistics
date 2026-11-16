import CloudKit
import Foundation
import Testing
@testable import BattisticsRemote

@Suite("Private iCloud phone version reports")
struct RemotePhoneReportTests {
    @Test func conflictRetryMergesAnotherPhoneWithoutTouchingCommands() async throws {
        let app = RemoteAppInfo(version: "1.1.0", build: "18", minimumPeerVersion: "1.6.0")
        let first = RemotePhoneInfo(id: UUID().uuidString, name: "Phone A", app: app)
        let second = RemotePhoneInfo(id: UUID().uuidString, name: "Phone B", app: app)
        let stored = CloudKitBuffer<Data?>(nil)
        let writes = CloudKitBuffer(0)
        let cloud = RemoteCloud(operations: .init { operation in
            if let zone = operation as? CKModifyRecordZonesOperation { zone.modifyRecordZonesResultBlock?(.success(())) }
            else if let subscription = operation as? CKModifySubscriptionsOperation { subscription.modifySubscriptionsResultBlock?(.success(())) }
            else if let read = operation as? CKFetchRecordsOperation {
                for id in read.recordIDs ?? [] {
                    if id.recordName == "mac" {
                        read.perRecordResultBlock?(id, .success(CKRecord(recordType: RemoteCloud.statusType, recordID: id)))
                    } else if let payload = stored.read() {
                        let record = CKRecord(recordType: RemoteCloud.commandType, recordID: id)
                        record.encryptedValues["payload"] = payload
                        read.perRecordResultBlock?(id, .success(record))
                    } else { read.perRecordResultBlock?(id, .failure(CKError(.unknownItem))) }
                }
                read.fetchRecordsResultBlock?(.success(()))
            } else if let write = operation as? CKModifyRecordsOperation {
                #expect(write.savePolicy == .ifServerRecordUnchanged)
                let record = write.recordsToSave!.first!
                #expect(record.recordID.recordName == "phones.mac")
                #expect(record.recordType == RemoteCloud.commandType)
                #expect(record["payload"] == nil)
                writes.update { $0 += 1 }
                if writes.read() == 1 {
                    var concurrent = RemotePhoneRegistry()
                    concurrent.record(second)
                    stored.update { $0 = try! RemoteWire.encode(concurrent) }
                    write.perRecordSaveBlock?(record.recordID, .failure(CKError(.serverRecordChanged)))
                    write.modifyRecordsResultBlock?(.failure(CKError(.partialFailure)))
                } else {
                    stored.update { $0 = record.encryptedValues["payload"] as? Data }
                    write.perRecordSaveBlock?(record.recordID, .success(record))
                    write.modifyRecordsResultBlock?(.success(()))
                }
            } else { Issue.record("Unexpected report operation") }
        })
        try await cloud.reportPhone(first, to: "mac", accountEpoch: await cloud.accountEpoch())
        let result = try RemoteWire.decode(RemotePhoneRegistry.self, from: stored.read()!)
        #expect(Set(result.phones.map(\.id)) == [first.id, second.id])
        #expect(writes.read() == 2)
    }

    @Test func previousAccountCannotPublishToReplacementAccount() async {
        let cloud = RemoteCloud(operations: .init { _ in Issue.record("Stale report reached the SDK") })
        let epoch = await cloud.accountEpoch()
        await cloud.accountDidChange()
        let phone = RemotePhoneInfo(id: UUID().uuidString, name: "Phone", app: .init(version: "1.1.0", build: "18", minimumPeerVersion: "1.6.0"))
        await #expect(throws: CancellationError.self) { try await cloud.reportPhone(phone, to: "mac", accountEpoch: epoch) }
    }

    @Test func anAccountChangeDuringFetchPreventsTheFollowingWrite() async throws {
        let gate = RemoteTestGate<CKFetchRecordsOperation>()
        let cloud = RemoteCloud(operations: .init { operation in
            if let zone = operation as? CKModifyRecordZonesOperation { zone.modifyRecordZonesResultBlock?(.success(())) }
            else if let subscription = operation as? CKModifySubscriptionsOperation { subscription.modifySubscriptionsResultBlock?(.success(())) }
            else if let read = operation as? CKFetchRecordsOperation { Task { await gate.finish(read) } }
            else { Issue.record("A late report reached the write boundary") }
        })
        let phone = RemotePhoneInfo(id: UUID().uuidString, name: "Phone", app: .init(version: "1.1.0", build: "18", minimumPeerVersion: "1.6.0"))
        let epoch = await cloud.accountEpoch()
        let reporting = Task { try await cloud.reportPhone(phone, to: "mac", accountEpoch: epoch) }
        let read = await gate.value()
        await cloud.accountDidChange()
        for id in read.recordIDs ?? [] {
            read.perRecordResultBlock?(id, .success(CKRecord(recordType: RemoteCloud.statusType, recordID: id)))
        }
        read.fetchRecordsResultBlock?(.success(()))
        do { try await reporting.value; Issue.record("The stale report was accepted") }
        catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
    }
}
