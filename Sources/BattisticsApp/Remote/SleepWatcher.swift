import Foundation
import IOKit
import IOKit.pwr_mgt

/// Hears the Mac about to sleep and waking up. Sleep waits for `willSleep`,
/// a few seconds at most, so a last word can reach iCloud first.
@MainActor
final class SleepWatcher {
    // From IOKit/IOMessage.h, whose function-like macros Swift does not import.
    private static let canSystemSleep: natural_t = 0xE000_0270
    private static let systemWillSleep: natural_t = 0xE000_0280
    private static let systemHasPoweredOn: natural_t = 0xE000_0300

    private let willSleep: @MainActor () async -> Void
    private let didWake: @MainActor () -> Void
    private var pendingSleep: Int?
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
    }

    deinit {
        guard rootPort != 0 else { return }
        IODeregisterForSystemPower(&notifier)
        IOServiceClose(rootPort)
        if let notifyPort { IONotificationPortDestroy(notifyPort) }
    }

    private func handle(_ message: natural_t, token: Int) {
        switch message {
        case Self.canSystemSleep:
            IOAllowPowerChange(rootPort, token)
        case Self.systemWillSleep:
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
