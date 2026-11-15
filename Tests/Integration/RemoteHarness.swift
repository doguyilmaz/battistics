import AppKit
import BattisticsCore
import BattisticsRemote
import SwiftUI

/// Runs the Mac side of the iPhone companion without iCloud: the same command
/// handling and status the CloudKit records carry. Takes only short-lived
/// idle/display assertions; never installs the helper.
@main
@MainActor
struct RemoteHarness {
    static func main() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        UserDefaults.standard.setVolatileDomain([
            Prefs.keepAwakeWarnOnLowBattery: false, Prefs.keepAwakeStopOnLowBattery: false,
            Prefs.keepAwakeStopOnThermalPressure: false, Prefs.remoteEnabled: true,
            Prefs.remoteClosedLidAllowed: false, Prefs.powerSamplingEnabled: false, Prefs.hasSeenTour: true,
        ], forName: UserDefaults.argumentDomain)
        Prefs.registerDefaults()
        let helper = PowerHelperClient()
        let awake = KeepAwakeModel(helper: helper)
        let automation = AutomationModel(awake: awake, helper: helper,
                                         endpoint: .init(directory: "/private/tmp/battistics-remote-\(UUID())"),
                                         initiallyEnabled: false)
        let network = NetworkMonitor()
        let journalURL = FileManager.default.temporaryDirectory.appendingPathComponent("remote-handoff-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: journalURL) }
        let remote = RemoteAccessModel(
            awake: awake, automation: automation, helper: helper, network: network, cloud: nil,
            commandJournal: RemoteCommandJournal(url: journalURL),
            chargeHistory: {
                let now = Date()
                return (0..<48).map { .init(at: now.addingTimeInterval(Double($0 - 47) * 1800), percent: 50) }
            })
        precondition(!remote.isAvailable)
        try await render(RemotePane().environment(remote).environment(network), name: "remote-pane")
        try await render(Form {
            Section("Nearby Connections") { NearbyAccessView(bluetooth: .denied, localNetwork: .denied) }
        }.formStyle(.grouped), name: "nearby-permissions-denied")
        try await render(Form {
            Section("Nearby Connections") { NearbyAccessView(bluetooth: .poweredOff, localNetwork: .inactive) }
        }.formStyle(.grouped), name: "nearby-bluetooth-off")

        let withdrawal = RemoteWithdrawal()
        let entered = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let publicationStarted = AsyncStream<Void>.makeStream()
        let order = AsyncStream<String>.makeStream()
        let deleting = Task {
            await withdrawal.run {
                entered.continuation.yield(())
                _ = await release.stream.first(where: { @Sendable _ in true })
                order.continuation.yield("delete")
            }
        }
        _ = await entered.stream.first(where: { @Sendable _ in true })
        let publishing = Task {
            publicationStarted.continuation.yield(())
            await withdrawal.settle()
            order.continuation.yield("publish")
        }
        _ = await publicationStarted.stream.first(where: { @Sendable _ in true })
        release.continuation.yield(())
        await deleting.value
        await publishing.value
        var events = order.stream.makeAsyncIterator()
        let firstEvent = await events.next()
        let secondEvent = await events.next()
        precondition(firstEvent == "delete" && secondEvent == "publish")

        // A canceled setup or alert task can still have an SDK save in flight.
        // Join both saves (including a failed one), then delete, then re-enable.
        let writesEntered = AsyncStream<Void>.makeStream()
        let finishCredential = AsyncStream<Void>.makeStream()
        let finishAlert = AsyncStream<Void>.makeStream()
        let deletionQueued = AsyncStream<Void>.makeStream()
        let nextPublicationQueued = AsyncStream<Void>.makeStream()
        let writeOrder = AsyncStream<String>.makeStream()
        let credentialWrite = Task {
            try await withdrawal.publish {
                writesEntered.continuation.yield(())
                _ = await finishCredential.stream.first(where: { @Sendable _ in true })
                writeOrder.continuation.yield("credential")
            }
        }
        let alertWrite = Task {
            try await withdrawal.publish {
                writesEntered.continuation.yield(())
                _ = await finishAlert.stream.first(where: { @Sendable _ in true })
                writeOrder.continuation.yield("alert")
                throw CocoaError(.fileWriteUnknown)
            }
        }
        var writes = writesEntered.stream.makeAsyncIterator()
        _ = await writes.next()
        _ = await writes.next()
        let withdrawalAfterWrites = Task {
            deletionQueued.continuation.yield(())
            await withdrawal.run { writeOrder.continuation.yield("delete") }
        }
        _ = await deletionQueued.stream.first(where: { @Sendable _ in true })
        let publicationAfterWithdrawal = Task {
            nextPublicationQueued.continuation.yield(())
            await withdrawal.settle()
            writeOrder.continuation.yield("publish")
        }
        _ = await nextPublicationQueued.stream.first(where: { @Sendable _ in true })
        finishCredential.continuation.yield(())
        finishAlert.continuation.yield(())
        _ = await credentialWrite.result
        _ = await alertWrite.result
        await withdrawalAfterWrites.value
        await publicationAfterWithdrawal.value
        var orderedWrites = writeOrder.stream.makeAsyncIterator()
        let firstWrite = await orderedWrites.next()
        let secondWrite = await orderedWrites.next()
        let deletion = await orderedWrites.next()
        let replacement = await orderedWrites.next()
        precondition(Set([firstWrite, secondWrite]) == Set(["credential", "alert"]))
        precondition(deletion == "delete" && replacement == "publish")

        func command(_ operation: RemoteRequest.Operation, mode: RemoteStatus.Mode? = nil, minutes: Int? = nil) async -> RemoteFailure? {
            await remote.handle(.init(operation: operation, mode: mode, durationMinutes: minutes, deviceName: "Test iPhone"))
        }

        let initial = await remote.fullStatus()
        precondition(initial.session == nil && initial.chargeHistory?.count == 48)

        let invalidDuration = await command(.start, mode: .displayMaySleep, minutes: -5)
        let closedLid = await command(.start, mode: .lidClosed, minutes: 15)
        precondition(invalidDuration?.code == .invalidRequest && closedLid?.code == .closedLidNotAllowed)
        precondition(!awake.isActive)

        let startedIndefinite = await command(.start, mode: .displayMaySleep, minutes: 0)
        precondition(startedIndefinite == nil)
        let indefiniteSession = try require(await remote.fullStatus().session)
        precondition(indefiniteSession.origin == .phone && indefiniteSession.deadline == nil)
        let extendedIndefinite = await command(.extend, minutes: 30)
        precondition(extendedIndefinite?.code == .startFailed)
        _ = await command(.stop)
        let extendedIdle = await command(.extend, minutes: 30)
        precondition(extendedIdle?.code == .startFailed)

        let started = await command(.start, mode: .displayMaySleep, minutes: 15)
        precondition(started == nil)
        let session = try require(await remote.fullStatus().session)
        precondition(session.origin == .phone && session.name == "Test iPhone" && awake.sessionOrigin == .phone)
        precondition(session.deadline.map { abs($0.timeIntervalSinceNow - 900) < 5 } == true)
        let oddExtension = await command(.extend, minutes: 7)
        precondition(oddExtension?.code == .invalidRequest)
        let extended = await command(.extend, minutes: 30)
        let longer = try require(await remote.fullStatus().session)
        precondition(extended == nil && longer.startedAt == session.startedAt)
        precondition(longer.deadline.map { abs($0.timeIntervalSinceNow - 2700) < 5 } == true)
        let busy = await command(.start, mode: .displayOn, minutes: 30)
        precondition(busy?.code == .busy)
        precondition(awake.session?.mode == .displayMaySleep)

        let stop = await command(.stop)
        precondition(stop == nil)
        let stopped = await remote.fullStatus()
        precondition(stopped.session == nil && stopped.lastEnd?.reason == .phone && !awake.isActive)

        precondition(stopped.extras == nil)
        let inspected = await command(.inspect)
        let extras = try require(await remote.fullStatus().extras)
        precondition(inspected == nil && abs(extras.sampledAt.timeIntervalSinceNow) < 30 && extras.apps.count <= 5)

        let start = RemoteRequest(operation: .start, mode: .displayMaySleep, durationMinutes: 15)
        let first = try await remote.executeCommand(start)
        let repeated = try await remote.executeCommand(start)
        precondition(first.lastCommand?.failure == nil && repeated.lastCommand?.failure == nil)
        precondition(first.session?.startedAt == repeated.session?.startedAt)
        let addTime = RemoteRequest(operation: .extend, durationMinutes: 30)
        let extendedOnce = try await remote.executeCommand(addTime)
        let extendedAgain = try await remote.executeCommand(addTime)
        precondition(extendedOnce.session?.deadline == extendedAgain.session?.deadline)
        precondition(extendedOnce.session?.deadline == first.session?.deadline?.addingTimeInterval(30 * 60))
        precondition((extendedAgain.revision ?? 0) > (extendedOnce.revision ?? 0))
        let stoppedOnce = try await remote.executeCommand(.init(operation: .stop))
        precondition(stoppedOnce.session == nil && !awake.isActive)

        // A remote authorization can be withdrawn before the queued startup
        // reaches an assertion/helper effect. The real controller must abort.
        UserDefaults.standard.set(false, forKey: Prefs.remoteWithdrawPending)
        let revokedStart = awake.start(mode: .displayMaySleep, duration: .fifteenMinutes,
                                       allowHelperSetup: false, origin: .phone, authorizing: { remote.enabled })
        remote.enabled = false
        precondition(UserDefaults.standard.bool(forKey: Prefs.remoteWithdrawPending))
        await revokedStart?.value
        precondition(!awake.isActive && !awake.isChanging)

        let off = await command(.stop)
        precondition(off?.code == .unavailable)
        print("PASS: start limits, extend, busy, closed-lid gate, phone stop reason, history, inspect, disabled, handoff replay, revisions and withdrawal write ordering")
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw CocoaError(.coderValueNotFound) }
        return value
    }

    private static func render(_ view: some View, name: String) async throws {
        let host = NSHostingView(rootView: view.frame(width: 640, height: 560))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 560)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(300))
        let bitmap = try require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        try require(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/private/tmp/battistics-\(name)-\(language).png"))
        window.close()
    }
}
