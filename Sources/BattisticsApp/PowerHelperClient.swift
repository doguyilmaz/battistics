import AppKit
import BattisticsCore
import Foundation
import Observation
import ServiceManagement

/// Talks to the privileged helper, when one is installed.
///
/// Installing it is the "ask once, ever" path: the daemon runs as root under
/// launchd, so changes afterwards need no authorization at all. The app falls
/// back to `PowerAuthorization` when it is absent, which asks once per
/// session instead.
@MainActor
@Observable
final class PowerHelperClient {
    private static let plistName = "com.doguyilmaz.Battistics.PowerHelper.plist"

    enum Failure: Error { case notConnected, unreachable, rejected(Int32) }

    /// A continuation can only be resumed once, but three things race to do
    /// it here: the reply, the XPC error handler, and the timeout.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Int32, Error>?

        init(_ continuation: CheckedContinuation<Int32, Error>) {
            self.continuation = continuation
        }

        private func take() -> CheckedContinuation<Int32, Error>? {
            lock.lock()
            defer { lock.unlock() }
            let value = continuation
            continuation = nil
            return value
        }

        func succeed(_ value: Int32) { take()?.resume(returning: value) }
        func fail(_ error: Error) { take()?.resume(throwing: error) }
    }

    /// A registered daemon that launchd never manages to spawn leaves the
    /// connection valid and simply never replies, so an error handler alone
    /// is not enough to avoid hanging forever. A warm call answers in about
    /// 50ms and a cold spawn in a few hundred, so this is a backstop rather
    /// than a wait anyone should ever see.
    private static let replyTimeout: Duration = .seconds(2)
    private static let probeTimeout: Duration = .seconds(1)

    private(set) var status: SMAppService.Status = .notRegistered
    /// Registered is not the same as running: launchd refuses to spawn an
    /// unnotarized binary, leaving a service that exists and never answers.
    private(set) var isReachable = false

    @ObservationIgnored private var connection: NSXPCConnection?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    init() {
        status = SMAppService.daemon(plistName: Self.plistName).status
        // The user approves or revokes this in System Settings, which no
        // notification reports back. Re-reading when the app is activated
        // catches it the moment they return, without polling: SMAppService
        // has no observable status, and a timer would burn cycles forever to
        // notice something that changes once a year.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshStatus() }
        }
        reregisterAfterUpdateIfNeeded()
    }

    /// Every Sparkle update replaces the helper executable, and Apple's own
    /// note is that a service "must be re-registered or it may not launch"
    /// when that happens. Left alone, someone who chose never to be asked
    /// quietly starts being asked again after an update, with nothing to
    /// explain why.
    ///
    /// Deliberately narrow: it only runs when the helper is already
    /// registered and approved, so it can never be a first install, and the
    /// version is recorded *before* the attempt, so a failure cannot retry
    /// on every launch. If it does fail, the pane's existing repair state
    /// takes over.
    private func reregisterAfterUpdateIfNeeded() {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let defaults = UserDefaults.standard
        guard status == .enabled,
            defaults.string(forKey: Prefs.helperRegisteredVersion) != current
        else { return }
        defaults.set(current, forKey: Prefs.helperRegisteredVersion)
        try? reinstall()
    }

    private func recordRegisteredVersion() {
        UserDefaults.standard.set(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            forKey: Prefs.helperRegisteredVersion)
    }

    private var service: SMAppService {
        SMAppService.daemon(plistName: Self.plistName)
    }

    var isInstalled: Bool { status == .enabled }
    /// Installed *and* answering, which is what callers actually need.
    var canApply: Bool { isInstalled && isReachable }
    var isInstalledButSilent: Bool { isInstalled && !isReachable }
    /// macOS wants the user to approve the daemon in Login Items first.
    var needsApproval: Bool { status == .requiresApproval }

    func refreshStatus() {
        status = service.status
        guard status == .enabled else {
            isReachable = false
            return
        }
        // Probed here, off the critical path, so a change never waits on a
        // timeout to discover the helper is dead.
        Task { await probeReachability() }
    }

    private func probeReachability() async {
        do {
            _ = try await send(timeout: Self.probeTimeout) { proxy, done in
                proxy.version { @Sendable _ in done(0) }
            }
            isReachable = true
        } catch {
            isReachable = false
            connection?.invalidate()
            connection = nil
        }
    }

    /// ServiceManagement's own codes. The enum in SMErrors.h starts at 2, so
    /// anything below it is a POSIX errno in SMAppService's domain — code 1
    /// is EPERM, which macOS returns for several unrelated reasons.
    enum RegistrationError: Int {
        case notPermitted = 1
        case internalFailure = 2
        case invalidSignature = 3
        case authorizationFailure = 4
        case toolNotValid = 5
        case jobNotFound = 6
        case serviceUnavailable = 7
        case jobPlistNotFound = 8
        case jobMustBeEnabled = 9
        case invalidPlist = 10
        case deniedByUser = 11
        case alreadyRegistered = 12
    }

    func install() throws {
        do {
            try service.register()
        } catch {
            // Already registered is the state we wanted, not a failure.
            if (error as NSError).code == RegistrationError.alreadyRegistered.rawValue {
                refreshStatus()
                return
            }
            // The attempt itself can move the status — a denial recorded in
            // Login Items shows up here — so re-read before reporting.
            refreshStatus()
            throw error
        }
        recordRegisteredVersion()
        refreshStatus()
    }

    /// Apple: "If an app updates either the plist or the executable ... the
    /// SMAppService must be re-registered or it may not launch. It is
    /// recommended to also call unregister before re-registering." Every
    /// Sparkle update replaces the helper, so a registration made before one
    /// can end up pointing at a binary that no longer matches.
    func reinstall() throws {
        connection?.invalidate()
        connection = nil
        try? service.unregister()
        try service.register()
        recordRegisteredVersion()
        refreshStatus()
    }

    func remove() throws {
        connection?.invalidate()
        connection = nil
        try service.unregister()
        UserDefaults.standard.removeObject(forKey: Prefs.helperRegisteredVersion)
        refreshStatus()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Applying

    /// Sends the change as enumerated codes. No argument vector crosses the
    /// connection; the daemon rebuilds it from cases it validated itself.
    func apply(_ change: PowerChange) async throws {
        let code = try await send(timeout: Self.replyTimeout) { proxy, done in
            switch change {
            case .lowPowerMode(let setting):
                proxy.setLowPowerMode(setting.wireCode, reply: done)
            case .energyMode(let mode):
                proxy.setEnergyMode(mode.rawValue, reply: done)
            case .sleepTimer(let timer, let interval, let source):
                proxy.setSleepTimer(
                    timer.wireCode, minutes: interval.rawValue, source: source.wireCode,
                    reply: done)
            }
        }
        guard code == 0 else { throw Failure.rejected(code) }
    }

    /// The reply and error blocks are marked `@Sendable` deliberately.
    ///
    /// XPC invokes them on a background queue, but a plain closure written
    /// inside this `@MainActor` type inherits that isolation, so Swift emits
    /// an isolation assertion that trips the instant XPC calls back — a
    /// guaranteed crash rather than a race. A `@Sendable` closure does not
    /// inherit isolation, so no check is emitted; `ResumeOnce` is what makes
    /// that safe, since it is the only shared state they touch.
    private func send(
        timeout: Duration,
        _ body: @escaping (PowerHelperProtocol, @escaping @Sendable (Int32) -> Void) -> Void
    ) async throws -> Int32 {
        let connection = try activeConnection()
        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            // remoteObjectProxy (no handler) drops messages silently when the
            // service is not answering, which reads as the app doing nothing.
            guard
                let proxy = connection.remoteObjectProxyWithErrorHandler({ @Sendable error in
                    once.fail(error)
                }) as? PowerHelperProtocol
            else {
                once.fail(Failure.notConnected)
                return
            }
            Task {
                try? await Task.sleep(for: timeout)
                once.fail(Failure.unreachable)
            }
            body(proxy) { @Sendable value in once.succeed(value) }
        }
    }

    private func activeConnection() throws -> NSXPCConnection {
        if connection == nil {
            let new = NSXPCConnection(
                machServiceName: powerHelperMachServiceName, options: .privileged)
            new.remoteObjectInterface = NSXPCInterface(with: PowerHelperProtocol.self)
            new.invalidationHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            new.interruptionHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            new.resume()
            connection = new
        }
        guard let connection else { throw Failure.notConnected }
        return connection
    }
}
