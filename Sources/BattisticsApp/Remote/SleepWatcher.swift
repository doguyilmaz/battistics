import AppKit
import IOKit
import IOKit.pwr_mgt

/// Hears the Mac about to sleep and waking up. Sleep waits for `willSleep`,
/// a few seconds at most, so a last word can reach iCloud first.
@MainActor
final class SleepWatcher {
    // From IOKit/IOMessage.h, whose function-like macros Swift does not import.
    private static let canSystemPowerOff: natural_t = 0xE000_0240
    private static let systemWillPowerOff: natural_t = 0xE000_0250
    private static let canSystemSleep: natural_t = 0xE000_0270
    private static let systemWillSleep: natural_t = 0xE000_0280
    private static let systemHasPoweredOn: natural_t = 0xE000_0300
    private static let systemWillRestart: natural_t = 0xE000_0310

    /// Apps are asked to quit before IOKit announces a shutdown or restart,
    /// so the quit itself is where the app hears of one.
    private static weak var current: SleepWatcher?

    private let willSleep: @MainActor () async -> Void
    private let didWake: @MainActor () -> Void
    private var pendingSleep: Int?
    private var pendingQuit = false
    nonisolated(unsafe) private var rootPort: io_connect_t = 0
    nonisolated(unsafe) private var notifyPort: IONotificationPortRef?
    nonisolated(unsafe) private var notifier: io_object_t = 0

    init(willSleep: @escaping @MainActor () async -> Void, didWake: @escaping @MainActor () -> Void) {
        self.willSleep = willSleep
        self.didWake = didWake
        let context = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(context, &notifyPort, { context, _, message, argument in
            guard let context else { return }
            let watcher = Unmanaged<SleepWatcher>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.handle(message, token: Int(bitPattern: argument)) }
        }, &notifier)
        if let notifyPort { IONotificationPortSetDispatchQueue(notifyPort, .main) }
        Self.current = self
    }

    /// For `applicationShouldTerminate`: a quit for a shutdown or restart
    /// waits for `willSleep`, as sleep does.
    static func shouldTerminate(_ app: NSApplication) -> NSApplication.TerminateReply {
        guard let watcher = current, isPowerOffQuit else { return .terminateNow }
        guard !watcher.pendingQuit else { return .terminateLater }
        watcher.pendingQuit = true
        Task {
            await watcher.willSleep()
            watcher.allowQuit(app)
        }
        Task {
            try? await Task.sleep(for: .seconds(8))
            watcher.allowQuit(app)
        }
        return .terminateLater
    }

    private static var isPowerOffQuit: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEQuitApplication),
              let reason = event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue
        else { return false }
        return reason == OSType(kAEShutDown) || reason == OSType(kAERestart)
    }

    private func allowQuit(_ app: NSApplication) {
        guard pendingQuit else { return }
        pendingQuit = false
        app.reply(toApplicationShouldTerminate: true)
    }

    deinit {
        guard rootPort != 0 else { return }
        IODeregisterForSystemPower(&notifier)
        IOServiceClose(rootPort)
        if let notifyPort { IONotificationPortDestroy(notifyPort) }
    }

    private func handle(_ message: natural_t, token: Int) {
        switch message {
        case Self.canSystemSleep, Self.canSystemPowerOff:
            IOAllowPowerChange(rootPort, token)
        case Self.systemWillSleep, Self.systemWillPowerOff, Self.systemWillRestart:
            pendingSleep = token
            Task {
                await willSleep()
                allowSleep(token)
            }
            // macOS itself gives up waiting after 30 seconds.
            Task {
                try? await Task.sleep(for: .seconds(8))
                allowSleep(token)
            }
        case Self.systemHasPoweredOn:
            didWake()
        default:
            break
        }
    }

    private func allowSleep(_ token: Int) {
        guard pendingSleep == token else { return }
        pendingSleep = nil
        IOAllowPowerChange(rootPort, token)
    }
}
