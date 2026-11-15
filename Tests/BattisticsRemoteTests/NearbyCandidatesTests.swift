import Foundation
import Testing
@testable import BattisticsRemote

@Suite("Untrusted Bluetooth discovery")
struct NearbyCandidatesTests {
    @Test func fakeAdvertisementsCannotPermanentlyConsumeDiscoverySlots() {
        var pool = NearbyCandidates()
        let fake = [UUID(), UUID()]
        for id in fake { let accepted = pool.admit(id, macID: "mac"); #expect(accepted) }
        let real = UUID()
        let full = pool.admit(real, macID: "mac")
        #expect(!full)
        for id in fake { let retry = pool.failed(id, reason: .rejected); #expect(!retry) }
        let recovered = pool.admit(real, macID: "mac")
        #expect(recovered)
        pool.authenticate(real)
        let reconnect = pool.failed(real, reason: .disconnected)
        #expect(reconnect)
    }

    @Test func transientSetupFailuresHaveABoundedNativeRetry() {
        var pool = NearbyCandidates()
        let id = UUID()
        let admitted = pool.admit(id, macID: "mac")
        let firstRetry = pool.failed(id, reason: .setup)
        let secondRetry = pool.failed(id, reason: .setup)
        let exhausted = pool.failed(id, reason: .setup)
        let replacement = pool.admit(UUID(), macID: "mac")
        #expect(admitted && firstRetry && secondRetry && !exhausted && replacement)
    }

    @Test func anObservedUUIDDoesNotConferTrustAndOtherMacsKeepTheirBudget() {
        var pool = NearbyCandidates()
        let fake = [UUID(), UUID()]
        for id in fake { let accepted = pool.admit(id, macID: "spoofed-mac"); #expect(accepted) }
        let overBudget = pool.admit(UUID(), macID: "spoofed-mac")
        let differentMac = pool.admit(UUID(), macID: "another-mac")
        let untrustedRetry = pool.failed(fake[0], reason: .disconnected)
        #expect(!overBudget && differentMac && !untrustedRetry)
    }

    @Test func revocationRemovesEvenPreviouslyAuthenticatedCandidates() {
        var pool = NearbyCandidates()
        let id = UUID()
        let accepted = pool.admit(id, macID: "mac")
        #expect(accepted)
        pool.authenticate(id)
        let rejectedRetry = pool.failed(id, reason: .rejected)
        let laterRetry = pool.failed(id, reason: .disconnected)
        #expect(!rejectedRetry && !laterRetry)
    }
}
