import CloudKit
import Testing
@testable import BattisticsRemote

@Suite("Nearby account trust")
struct RemoteAccountIdentityTests {
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
