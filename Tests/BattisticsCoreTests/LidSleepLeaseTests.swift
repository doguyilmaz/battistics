import Foundation
import Testing
@testable import BattisticsCore

struct LidSleepLeaseTests {
    private final class Fixture {
        var value = false
        var writes: [Bool] = []
        var reads = 0
        var journal: LidSleepLeaseJournal?
        var saved: [LidSleepLeaseJournal] = []
        var failRead = false
        var failWrite = false
        var ignoreWrite = false
        var failSave = false
        var failAbandon = false
        var failClear = false
        var failReadAfterWrite = false
        var onRead: ((Int) -> Void)?
        let owner = UUID()
        let session = UUID()
        let now = Date(timeIntervalSince1970: 1_000)

        func makeLease() -> LidSleepLease {
            LidSleepLease(read: { [self] in
                reads += 1
                onRead?(reads)
                if failRead { throw CocoaError(.fileReadUnknown) }
                return value
            }, write: { [self] value in
                if failWrite { throw CocoaError(.fileWriteNoPermission) }
                writes.append(value)
                if !ignoreWrite { self.value = value }
                if failReadAfterWrite { failRead = true }
            }, save: { [self] record in
                if failSave || (record.phase == .abandoned && failAbandon) {
                    throw CocoaError(.fileWriteNoPermission)
                }
                saved.append(record)
                journal = record
            }, clear: { [self] in
                if failClear { throw CocoaError(.fileWriteNoPermission) }
                journal = nil
            })
        }
    }

    @Test func explicitAcquisitionAndExpiryRestoreOnlyOwnedOverride() {
        for original in [false, true] {
            let f = Fixture()
            f.value = original
            let lease = f.makeLease()
            #expect(lease.acquire(owner: f.owner, session: f.session, now: f.now) == .success)
            #expect(f.value)
            #expect(f.journal?.original == original)
            let reads = f.reads
            #expect(lease.expire(now: f.now.addingTimeInterval(44)) == .inactive)
            #expect(f.reads == reads)
            #expect(lease.expire(now: f.now.addingTimeInterval(45)) == .success)
            #expect(f.value == original)
            #expect(f.writes == (original ? [] : [true, false]))
            #expect(f.journal == nil)
            #expect(f.saved.last?.phase == .abandoned)
            #expect(lease.renew(owner: f.owner, session: f.session) == .inactive)
            #expect(lease.acquire(owner: f.owner, session: f.session) == .inactive)
        }
    }

    @Test func externalChangeEndsBorrowedAndOwnedSessionsWithoutRollback() {
        for original in [false, true] {
            let f = Fixture()
            f.value = original
            let lease = f.makeLease()
            #expect(lease.acquire(owner: f.owner, session: f.session, now: f.now) == .success)
            f.value = false // Another application changed SleepDisabled.
            let writes = f.writes
            #expect(lease.renew(owner: f.owner, session: f.session, now: f.now) == .ownershipLost)
            #expect(lease.release(owner: f.owner, session: f.session) == .ownershipLost)
            #expect(lease.renew(owner: f.owner, session: f.session, now: f.now) == .ownershipLost)
            #expect(lease.acquire(owner: f.owner, session: f.session) == .inactive)
            #expect(f.writes == writes)
            #expect(!f.value)
            #expect(f.saved.last?.phase == .abandoned)
            // An explicit new user session can acquire again.
            #expect(lease.acquire(owner: f.owner, session: UUID(), now: f.now) == .success)
        }
    }

    @Test func stopDisconnectAndExpiryCheckExternalStateBeforeRollback() {
        for original in [false, true] {
            for operation in 0...2 {
                let f = Fixture()
                f.value = original
                let lease = f.makeLease()
                #expect(lease.acquire(owner: f.owner, session: f.session, now: f.now) == .success)
                f.value = false
                let writes = f.writes
                let result: LidSleepLeaseResult
                switch operation {
                case 0: result = lease.release(owner: f.owner, session: f.session)
                case 1: result = lease.disconnected(owner: f.owner)
                default: result = lease.expire(now: f.now.addingTimeInterval(46))
                }
                #expect(result == .ownershipLost)
                #expect(f.writes == writes)
                #expect(!f.value)
            }
        }
    }

    @Test func renewalNeverAcquiresAndTokensCannotStealOrReviveSession() {
        let f = Fixture()
        let lease = f.makeLease()
        #expect(lease.renew(owner: f.owner, session: f.session, now: f.now) == .inactive)
        #expect(f.reads == 0)
        #expect(lease.acquire(owner: f.owner, session: f.session, now: f.now) == .success)
        let other = UUID()
        #expect(lease.renew(owner: other, session: f.session, now: f.now) == .rejected)
        #expect(lease.release(owner: other, session: f.session) == .rejected)
        #expect(lease.acquire(owner: other, session: UUID(), now: f.now) == .rejected)
        #expect(lease.disconnected(owner: other) == .inactive)
        #expect(lease.renew(owner: f.owner, session: UUID(), now: f.now) == .inactive)
        #expect(lease.renew(owner: f.owner, session: f.session, now: f.now.addingTimeInterval(46)) == .inactive)
        #expect(!f.value)
        #expect(lease.acquire(owner: f.owner, session: f.session, now: f.now) == .inactive)
    }

    @Test func renewalExtendsDeadlineWithoutRepeatingMutation() {
        let f = Fixture()
        let lease = f.makeLease()
        #expect(lease.acquire(owner: f.owner, session: f.session, now: f.now) == .success)
        #expect(lease.renew(owner: f.owner, session: f.session, now: f.now.addingTimeInterval(30)) == .success)
        #expect(lease.expire(now: f.now.addingTimeInterval(46)) == .inactive)
        #expect(f.writes == [true])
        #expect(lease.expire(now: f.now.addingTimeInterval(75)) == .success)
        #expect(f.writes == [true, false])
        let reads = f.reads
        #expect(lease.expire(now: f.now.addingTimeInterval(90)) == .inactive)
        #expect(f.reads == reads)
    }

    @Test func unknownReadsNeverAuthorizeAcquisitionOrBlindRestoration() {
        let f = Fixture()
        let lease = f.makeLease()
        f.failRead = true
        #expect(lease.acquire(owner: f.owner, session: f.session) == .unavailable)
        #expect(f.writes.isEmpty)
        f.failRead = false
        let session = UUID()
        #expect(lease.acquire(owner: f.owner, session: session, now: f.now) == .success)
        f.failRead = true
        #expect(lease.release(owner: f.owner, session: session) == .unavailable)
        #expect(f.writes == [true])
        #expect(f.journal == nil)
        f.failRead = false
        #expect(lease.renew(owner: f.owner, session: session, now: f.now) == .unavailable)
        #expect(lease.expire(now: f.now.addingTimeInterval(100)) == .inactive)
        #expect(f.writes == [true])
    }

    @Test func mutationRequiresVerifiedLiveValueBeforeAcquisitionSuccess() {
        for unknown in [false, true] {
            let f = Fixture()
            f.ignoreWrite = !unknown
            f.failReadAfterWrite = unknown
            let lease = f.makeLease()
            #expect(lease.acquire(owner: f.owner, session: f.session) == (unknown ? .unavailable : .ownershipLost))
            #expect(f.journal == nil)
            #expect(lease.acquire(owner: f.owner, session: f.session) == .inactive)
        }
    }

    @Test func activeJournalMustBeSavedBeforeMutation() {
        let f = Fixture()
        f.failSave = true
        let lease = f.makeLease()
        #expect(lease.acquire(owner: f.owner, session: f.session) == .failed)
        #expect(f.writes.isEmpty)
        #expect(f.journal == nil)
    }

    @Test func abandonedJournalSurvivesDeletionFailureAndCannotReplayRollback() throws {
        let f = Fixture()
        let lease = f.makeLease()
        #expect(lease.acquire(owner: f.owner, session: f.session, now: f.now) == .success)
        f.value = false
        f.failClear = true
        #expect(lease.renew(owner: f.owner, session: f.session, now: f.now) == .ownershipLost)
        let record = try #require(f.journal)
        #expect(record.phase == .abandoned)
        f.value = true // A later external change must not revive this journal.
        let reads = f.reads
        #expect(f.makeLease().recover(journal: record) == .inactive)
        #expect(f.reads == reads)
        #expect(f.writes == [true])
    }

    @Test func failedAbandonmentUsesDeletionFallbackAndBothFailuresBlockNewLeases() {
        for failClear in [false, true] {
            let f = Fixture()
            let lease = f.makeLease()
            #expect(lease.acquire(owner: f.owner, session: f.session, now: f.now) == .success)
            f.value = false
            f.failAbandon = true
            f.failClear = failClear
            #expect(lease.renew(owner: f.owner, session: f.session, now: f.now) == (failClear ? .failed : .ownershipLost))
            f.value = true
            #expect(lease.renew(owner: f.owner, session: f.session, now: f.now) == (failClear ? .failed : .ownershipLost))
            #expect(lease.expire(now: f.now.addingTimeInterval(100)) == .inactive)
            #expect(f.writes == [true])
            if failClear {
                #expect(lease.acquire(owner: f.owner, session: UUID()) == .failed)
            } else {
                #expect(f.journal == nil)
            }
        }
    }

    @Test func failedRestoreIsTerminalAndWatchdogDoesNotRepeatMutation() throws {
        let f = Fixture()
        let lease = f.makeLease()
        #expect(lease.acquire(owner: f.owner, session: f.session, now: f.now) == .success)
        f.failWrite = true
        f.failClear = true
        #expect(lease.release(owner: f.owner, session: f.session) == .failed)
        #expect(lease.renew(owner: f.owner, session: f.session) == .failed)
        let record = try #require(f.journal)
        #expect(record.phase == .abandoned)
        f.failWrite = false
        #expect(lease.expire(now: f.now.addingTimeInterval(100)) == .inactive)
        #expect(f.makeLease().recover(journal: record) == .inactive)
        #expect(f.writes == [true])
    }

    @Test func recoveryChecksExternalValueAndNeverRestoresBorrowedTrue() {
        for original in [false, true] {
            for live in [false, true] {
                let f = Fixture()
                f.value = live
                let record = LidSleepLeaseJournal(original: original, session: f.session)
                f.journal = record
                let lease = f.makeLease()
                #expect(lease.recover(journal: record) == (live ? .success : .ownershipLost))
                #expect(f.writes == (live && !original ? [false] : []))
                #expect(f.value == (live && original))
                #expect(lease.acquire(owner: f.owner, session: f.session) == .inactive)
                #expect(lease.renew(owner: f.owner, session: f.session) == (live ? .inactive : .ownershipLost))
            }
        }
    }

    @Test func unknownRecoveryDisarmsRecordWithoutMutation() {
        let f = Fixture()
        f.failRead = true
        f.failClear = true
        let record = LidSleepLeaseJournal(original: false, session: f.session)
        #expect(f.makeLease().recover(journal: record) == .unavailable)
        #expect(f.writes.isEmpty)
        #expect(f.journal?.phase == .abandoned)
    }

    @Test func takeoverOnLastPreRollbackReadIsRememberedByRenewal() {
        let f = Fixture()
        let lease = f.makeLease()
        #expect(lease.acquire(owner: f.owner, session: f.session, now: f.now) == .success)
        let finalPreRollbackRead = f.reads + 2
        f.onRead = { count in
            if count == finalPreRollbackRead { f.value = false }
        }
        #expect(lease.expire(now: f.now.addingTimeInterval(46)) == .ownershipLost)
        #expect(lease.renew(owner: f.owner, session: f.session) == .ownershipLost)
        #expect(f.writes == [true])
        #expect(f.journal == nil)
    }

    @Test func failedOrUnknownRestorationVerificationIsRememberedByRenewal() {
        for unknown in [false, true] {
            let f = Fixture()
            let lease = f.makeLease()
            #expect(lease.acquire(owner: f.owner, session: f.session, now: f.now) == .success)
            let verificationRead = f.reads + 3
            f.onRead = { count in
                if count == verificationRead {
                    if unknown { f.failRead = true } else { f.value = true }
                }
            }
            let expected: LidSleepLeaseResult = unknown ? .unavailable : .failed
            #expect(lease.expire(now: f.now.addingTimeInterval(46)) == expected)
            #expect(lease.renew(owner: f.owner, session: f.session) == expected)
            #expect(f.writes == [true, false])
            #expect(f.journal == nil)
        }
    }

    @Test func preparedAcquisitionCannotAuthorizeCrashRollback() {
        let f = Fixture()
        f.value = true
        let record = LidSleepLeaseJournal(original: false, session: f.session, phase: .prepared)
        let lease = f.makeLease()
        #expect(lease.recover(journal: record) == .inactive)
        #expect(f.value)
        #expect(f.reads == 0)
        #expect(f.writes.isEmpty)
        #expect(lease.acquire(owner: f.owner, session: f.session) == .inactive)
    }

    @Test func acquisitionIsPreparedBeforeWriteAndPromotedOnlyAfterVerification() {
        let f = Fixture()
        let lease = f.makeLease()
        #expect(lease.acquire(owner: f.owner, session: f.session, now: f.now) == .success)
        #expect(f.saved.map(\.phase) == [.prepared, .active])
        #expect(f.journal?.phase == .active)
    }

    @Test func externalOverrideDuringAcquisitionJournalWriteIsNotClaimed() {
        let f = Fixture()
        f.onRead = { count in if count == 2 { f.value = true } }
        let lease = f.makeLease()
        #expect(lease.acquire(owner: f.owner, session: f.session) == .ownershipLost)
        #expect(f.writes.isEmpty)
        #expect(f.value)
        #expect(f.saved.last?.phase == .abandoned)
    }

    @Test func recoveringSameSessionTwiceCannotReplayRollback() {
        let f = Fixture()
        f.value = true
        let record = LidSleepLeaseJournal(original: false, session: f.session)
        let lease = f.makeLease()
        #expect(lease.recover(journal: record) == .success)
        f.value = true // A later external owner enabled it again.
        #expect(lease.recover(journal: record) == .inactive)
        #expect(f.writes == [false])
        #expect(f.value)
    }

    @Test func disconnectedEndpointCannotAcquireAfterQueuedInvalidation() {
        let f = Fixture()
        let lease = f.makeLease()
        #expect(lease.disconnected(owner: f.owner) == .inactive)
        #expect(lease.acquire(owner: f.owner, session: f.session) == .rejected)
        #expect(f.reads == 0)
        #expect(f.writes.isEmpty)
        #expect(lease.acquire(owner: UUID(), session: UUID(), now: f.now) == .success)
    }

    @Test func legacyAndVersionedJournalValidation() throws {
        #expect(try LidSleepLeaseJournal.decode(Data("0".utf8)).original == false)
        #expect(try LidSleepLeaseJournal.decode(Data("1".utf8)).original == true)
        let record = LidSleepLeaseJournal(original: false, session: UUID(), phase: .abandoned)
        #expect(try LidSleepLeaseJournal.decode(record.encoded()) == record)
        for invalid in ["", "2", "false", "{\"version\":2,\"original\":false,\"phase\":\"active\"}"] {
            #expect(throws: (any Error).self) { try LidSleepLeaseJournal.decode(Data(invalid.utf8)) }
        }
    }
}
