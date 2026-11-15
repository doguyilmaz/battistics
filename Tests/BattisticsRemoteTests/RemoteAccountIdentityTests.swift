import CloudKit
import Testing
@testable import BattisticsRemote

@Suite("Nearby account trust")
struct RemoteAccountIdentityTests {
    @Test func anOldCommandEpochCannotWriteReadOrCleanUpTheReplacementAccount() async {
        let cloud = RemoteCloud(operations: .init { _ in Issue.record("Stale command reached the SDK") })
        let epoch = await cloud.accountEpoch()
        await cloud.accountDidChange()
        await #expect(throws: CancellationError.self) {
            try await cloud.send(.init(operation: .stop), to: "mac", accountEpoch: epoch)
        }
        await #expect(throws: CancellationError.self) {
            try await cloud.status(macID: "mac", until: .now.advanced(by: .seconds(1)), accountEpoch: epoch)
        }
        await #expect(throws: CancellationError.self) {
            try await cloud.cancelCommand("old", macID: "mac", accountEpoch: epoch)
        }
    }
    @Test func aLateZonePreparationCannotPrepareTheReplacementAccount() async throws {
        let first = RemoteTestGate<CKModifyRecordZonesOperation>()
        let calls = CloudKitBuffer(0)
        let cloud = RemoteCloud(operations: .init { operation in
            if let zone = operation as? CKModifyRecordZonesOperation {
                calls.update { $0 += 1 }
                if calls.read() == 1 { Task { await first.finish(zone) } }
                else { zone.modifyRecordZonesResultBlock?(.success(())) }
            } else if let subscription = operation as? CKModifySubscriptionsOperation {
                subscription.modifySubscriptionsResultBlock?(.success(()))
            } else { Issue.record("Unexpected operation") }
        })
        let old = Task { try await cloud.prepare() }
        let operation = await first.value()
        await cloud.accountDidChange()
        try await RemoteDeadline.perform(until: .now.advanced(by: .seconds(2))) { try await cloud.prepare() }
        operation.modifyRecordZonesResultBlock?(.success(()))
        do { try await old.value; Issue.record("Old preparation was accepted") } catch {}
        try await cloud.prepare()
        #expect(calls.read() == 2)
    }
    @Test func identityIsVerifiedOncePerAccountAndProcess() async throws {
        let calls = CloudKitBuffer(0)
        let cloud = RemoteCloud(operations: .init { _ in Issue.record("Unexpected database access") }, identity: {
            calls.update { $0 += 1 }
            return "account-a"
        })
        #expect(try await cloud.accountIdentity() == "account-a")
        #expect(try await cloud.accountIdentity() == "account-a")
        #expect(calls.read() == 1)
    }

    @Test func anAccountChangeInvalidatesTheCachedIdentity() async throws {
        let calls = CloudKitBuffer(0)
        let cloud = RemoteCloud(operations: .init { _ in }, identity: {
            calls.update { $0 += 1 }
            return calls.read() == 1 ? "account-a" : "account-b"
        })
        #expect(try await cloud.accountIdentity() == "account-a")
        await cloud.accountDidChange()
        #expect(try await cloud.accountIdentity() == "account-b")
        #expect(calls.read() == 2)
    }

    @Test func aLateOldAccountResponseCannotAuthorizeItsReplacement() async throws {
        let entered = RemoteTestGate<Bool>()
        let old = RemoteTestGate<String>()
        let calls = CloudKitBuffer(0)
        let cloud = RemoteCloud(operations: .init { _ in }, identity: {
            calls.update { $0 += 1 }
            if calls.read() == 1 {
                await entered.finish(true)
                return await old.value()
            }
            return "account-b"
        })
        let previous = Task { try await cloud.accountIdentity() }
        _ = await entered.value()
        await cloud.accountDidChange()
        #expect(try await cloud.accountIdentity() == "account-b")
        await old.finish("account-a")
        do { _ = try await previous.value; Issue.record("Old account was accepted") } catch {}
        #expect(try await cloud.accountIdentity() == "account-b")
        #expect(calls.read() == 2)
    }

    @Test func aFailedIdentityCheckCannotBecomeCachedTrust() async throws {
        let calls = CloudKitBuffer(0)
        let cloud = RemoteCloud(operations: .init { _ in }, identity: {
            calls.update { $0 += 1 }
            if calls.read() == 1 { throw CKError(.notAuthenticated) }
            return "account-a"
        })
        await #expect(throws: CKError.self) { try await cloud.accountIdentity() }
        #expect(try await cloud.accountIdentity() == "account-a")
        #expect(calls.read() == 2)
    }
}
