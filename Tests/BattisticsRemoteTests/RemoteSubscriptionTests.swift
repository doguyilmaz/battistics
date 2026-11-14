import CloudKit
import Foundation
import Testing
@testable import BattisticsRemote

@Suite("Silent push subscription recovery")
struct RemoteSubscriptionTests {
    @Test func aLostSubscriptionIsRecreatedWithoutRelaunching() async {
        let clock = CloudKitBuffer(ContinuousClock.now)
        let server = CloudKitBuffer<CKSubscription?>(nil)
        let saves = CloudKitBuffer(0)
        let checks = CloudKitBuffer(0)
        let cloud = RemoteCloud(operations: .init(submit: Self.server(server, saves: saves, checks: checks)),
                                subscriptionClock: { clock.read() })
        await cloud.refreshPushSubscription()
        #expect(saves.read() == 1)
        #expect(checks.read() == 0)
        #expect(server.read()?.notificationInfo?.shouldSendContentAvailable == true)
        #expect(server.read()?.notificationInfo?.alertBody == nil)
        #expect(server.read()?.notificationInfo?.soundName == nil)

        server.update { $0 = nil }
        await cloud.refreshPushSubscription()
        #expect(saves.read() == 1)
        clock.update { $0 = $0.advanced(by: RemoteCloud.subscriptionCheckInterval) }
        await cloud.refreshPushSubscription()
        #expect(checks.read() == 1)
        #expect(saves.read() == 2)
    }

    @Test func aHealthySubscriptionIsCheckedWithoutBeingRewritten() async {
        let clock = CloudKitBuffer(ContinuousClock.now)
        let server = CloudKitBuffer<CKSubscription?>(nil)
        let saves = CloudKitBuffer(0)
        let checks = CloudKitBuffer(0)
        let cloud = RemoteCloud(operations: .init(submit: Self.server(server, saves: saves, checks: checks)),
                                subscriptionClock: { clock.read() })
        await cloud.refreshPushSubscription()
        clock.update { $0 = $0.advanced(by: RemoteCloud.subscriptionCheckInterval) }
        await cloud.refreshPushSubscription()
        #expect(checks.read() == 1)
        #expect(saves.read() == 1)
    }

    @Test(arguments: ["no-silent-content", "filtered", "wrong-zone"])
    func anIncompatibleSubscriptionIsRepaired(kind: String) async {
        let clock = CloudKitBuffer(ContinuousClock.now)
        let server = CloudKitBuffer<CKSubscription?>(nil)
        let saves = CloudKitBuffer(0)
        let checks = CloudKitBuffer(0)
        let cloud = RemoteCloud(operations: .init(submit: Self.server(server, saves: saves, checks: checks)),
                                subscriptionClock: { clock.read() })
        await cloud.refreshPushSubscription()
        let replacement = CKRecordZoneSubscription(
            zoneID: kind == "wrong-zone" ? .init(zoneName: "Other") : RemoteCloud.zoneID,
            subscriptionID: RemoteCloud.zoneSubscriptionID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = kind != "no-silent-content"
        replacement.notificationInfo = info
        if kind == "filtered" { replacement.recordType = RemoteCloud.eventType }
        server.update { $0 = replacement }
        clock.update { $0 = $0.advanced(by: RemoteCloud.subscriptionCheckInterval) }
        await cloud.refreshPushSubscription()
        #expect(checks.read() == 1)
        #expect(saves.read() == 2)
        #expect((server.read() as? CKRecordZoneSubscription)?.recordType == nil)
        #expect((server.read() as? CKRecordZoneSubscription)?.zoneID == RemoteCloud.zoneID)
        #expect(server.read()?.notificationInfo?.shouldSendContentAvailable == true)
    }

    @Test func failedChecksAreBoundedAndDoNotBlockStatusReads() async throws {
        let clock = CloudKitBuffer(ContinuousClock.now)
        let server = CloudKitBuffer<CKSubscription?>(nil)
        let saves = CloudKitBuffer(0)
        let checks = CloudKitBuffer(0)
        let failChecks = CloudKitBuffer(false)
        let answer = Self.server(server, saves: saves, checks: checks)
        let cloud = RemoteCloud(operations: .init { operation in
            if let check = operation as? CKFetchSubscriptionsOperation, failChecks.read() {
                checks.update { $0 += 1 }
                check.fetchSubscriptionsResultBlock?(.failure(CKError(.networkFailure)))
            } else if let read = operation as? CKFetchRecordsOperation {
                for id in read.recordIDs ?? [] {
                    let record = CKRecord(recordType: RemoteCloud.statusType, recordID: id)
                    record.encryptedValues["payload"] = try! RemoteWire.encode(RemoteStatus(machineName: "Mac", readAt: .now))
                    read.perRecordResultBlock?(id, .success(record))
                }
                read.fetchRecordsResultBlock?(.success(()))
            } else { answer(operation) }
        }, subscriptionClock: { clock.read() })
        await cloud.refreshPushSubscription()
        failChecks.update { $0 = true }
        clock.update { $0 = $0.advanced(by: RemoteCloud.subscriptionCheckInterval) }
        await cloud.refreshPushSubscription()
        await cloud.refreshPushSubscription()
        #expect(checks.read() == 1)
        let status = try await cloud.status(macID: "mac", until: .now.advanced(by: .seconds(1)))
        #expect(status?.machineName == "Mac")

        failChecks.update { $0 = false }
        server.update { $0 = nil }
        clock.update { $0 = $0.advanced(by: RemoteCloud.subscriptionRetryInterval) }
        await cloud.refreshPushSubscription()
        #expect(checks.read() == 2)
        #expect(saves.read() == 2)
    }

    @Test func aLostZoneInvalidatesACompletedSubscriptionCheck() async throws {
        let server = CloudKitBuffer<CKSubscription?>(nil)
        let saves = CloudKitBuffer(0)
        let checks = CloudKitBuffer(0)
        let answer = Self.server(server, saves: saves, checks: checks)
        let cloud = RemoteCloud(operations: .init { operation in
            if let query = operation as? CKQueryOperation {
                query.queryResultBlock?(.failure(CKError(.zoneNotFound)))
            } else { answer(operation) }
        })
        await cloud.refreshPushSubscription()
        #expect(saves.read() == 1)
        #expect(try await cloud.fetch().statuses.isEmpty)
        server.update { $0 = nil }
        await cloud.refreshPushSubscription()
        #expect(saves.read() == 2)
    }

    @Test func aLateSaveForALostZoneCannotSuppressRecovery() async throws {
        let entered = RemoteTestGate<CKModifySubscriptionsOperation>()
        let saves = CloudKitBuffer(0)
        let cloud = RemoteCloud(operations: .init { operation in
            if let save = operation as? CKModifySubscriptionsOperation {
                saves.update { $0 += 1 }
                if saves.read() == 1 { Task { await entered.finish(save) } }
                else { save.modifySubscriptionsResultBlock?(.success(())) }
            } else if let query = operation as? CKQueryOperation {
                query.queryResultBlock?(.failure(CKError(.zoneNotFound)))
            } else { Issue.record("Unexpected recovery operation: \(operation)") }
        })
        let first = Task { await cloud.refreshPushSubscription() }
        let save = await entered.value()
        #expect(try await cloud.fetch().statuses.isEmpty)
        save.modifySubscriptionsResultBlock?(.success(()))
        await first.value
        await cloud.refreshPushSubscription()
        #expect(saves.read() == 2)
    }

    private static func server(_ stored: CloudKitBuffer<CKSubscription?>, saves: CloudKitBuffer<Int>,
                               checks: CloudKitBuffer<Int>) -> @Sendable (CKDatabaseOperation) -> Void {
        { operation in
            if let save = operation as? CKModifySubscriptionsOperation {
                for subscription in save.subscriptionsToSave ?? [] {
                    saves.update { $0 += 1 }
                    stored.update { $0 = subscription }
                    save.perSubscriptionSaveBlock?(subscription.subscriptionID, .success(subscription))
                }
                save.modifySubscriptionsResultBlock?(.success(()))
            } else if let fetch = operation as? CKFetchSubscriptionsOperation {
                checks.update { $0 += 1 }
                for id in fetch.subscriptionIDs ?? [] {
                    if let subscription = stored.read() { fetch.perSubscriptionResultBlock?(id, .success(subscription)) }
                    else { fetch.perSubscriptionResultBlock?(id, .failure(CKError(.unknownItem))) }
                }
                fetch.fetchSubscriptionsResultBlock?(.success(()))
            } else { Issue.record("Unexpected subscription operation: \(operation)") }
        }
    }
}
