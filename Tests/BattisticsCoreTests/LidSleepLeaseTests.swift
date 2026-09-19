import Foundation
import Testing
@testable import BattisticsCore

struct LidSleepLeaseTests {
    @Test func expiresAndRestoresOriginalState() throws {
        for original in [false, true] {
            var state = original
            var journal: Bool?
            let lease = LidSleepLease(read: { state }, write: { state = $0 },
                                      save: { journal = $0 }, clear: { journal = nil })
            let now = Date()
            let owner = UUID()
            try lease.renew(owner: owner, now: now)
            #expect(state)
            #expect(journal == original)
            try lease.expire(now: now.addingTimeInterval(44))
            #expect(state)
            try lease.expire(now: now.addingTimeInterval(46))
            #expect(state == original)
            #expect(journal == nil)
        }
    }

    @Test func disconnectAndCrashRecoveryRestore() throws {
        var state = false
        var journal: Bool?
        let lease = LidSleepLease(read: { state }, write: { state = $0 },
                                  save: { journal = $0 }, clear: { journal = nil })
        let owner = UUID()
        try lease.renew(owner: owner)
        try lease.release(owner: UUID())
        #expect(state)
        try lease.release(owner: owner)
        #expect(!state)
        state = true
        journal = false
        try lease.recover(original: false)
        #expect(!state)
        #expect(journal == nil)
    }

    @Test func journalFailurePreventsMutation() {
        var mutated = false
        let lease = LidSleepLease(read: { false }, write: { _ in mutated = true },
                                  save: { _ in throw CocoaError(.fileWriteNoPermission) }, clear: {})
        #expect(throws: (any Error).self) { try lease.renew(owner: UUID()) }
        #expect(!mutated)
    }
    @Test func renewalExtendsLeaseAndAnotherOwnerCannotStealIt() throws {
        var state = false
        let lease = LidSleepLease(read: { state }, write: { state = $0 }, save: { _ in }, clear: {})
        let owner = UUID()
        let now = Date()
        try lease.renew(owner: owner, now: now)
        #expect(throws: (any Error).self) { try lease.renew(owner: UUID(), now: now) }
        try lease.renew(owner: owner, now: now.addingTimeInterval(30))
        try lease.expire(now: now.addingTimeInterval(46))
        #expect(state)
        try lease.expire(now: now.addingTimeInterval(76))
        #expect(!state)
    }

    @Test func failedRestoreRetainsJournalAndRetries() throws {
        var state = false
        var failRestore = false
        var journal: Bool?
        let lease = LidSleepLease(read: { state }, write: { value in
            if failRestore { throw CocoaError(.fileWriteNoPermission) }
            state = value
        }, save: { journal = $0 }, clear: { journal = nil })
        let now = Date()
        let owner = UUID()
        try lease.renew(owner: owner, now: now)
        failRestore = true
        #expect(throws: (any Error).self) { try lease.release(owner: owner) }
        #expect(journal == false)
        failRestore = false
        try lease.expire(now: now.addingTimeInterval(46))
        #expect(!state)
        #expect(journal == nil)
    }

}
