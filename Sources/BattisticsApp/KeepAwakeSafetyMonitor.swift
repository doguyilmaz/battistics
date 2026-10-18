import BattisticsCore
import Foundation
import Observation

@MainActor
@Observable
final class KeepAwakeSafetyMonitor {
    var configuration: KeepAwakeSafetyPolicy.Configuration {
        didSet {
            Prefs.saveSafetyConfiguration(configuration)
            refresh()
        }
    }
    private(set) var thermalState = ProcessInfo.processInfo.thermalState
    private(set) var warningMessage: String?
    private(set) var batteryWarningActive = false
    @ObservationIgnored var onStop: ((KeepAwakeSafetyPolicy.Event) -> Void)?
    @ObservationIgnored private var policy = KeepAwakeSafetyPolicy()
    @ObservationIgnored private var active = false
    @ObservationIgnored private var thermalObserver: NSObjectProtocol?
    @ObservationIgnored private let dispatcher = AlertDispatcher()
    @ObservationIgnored private let notice = KeepAwakeNoticeController()
    @ObservationIgnored private var lastNoticeWasThermal = false

    init() {
        configuration = Prefs.safetyConfiguration()
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    func startSession() {
        policy = KeepAwakeSafetyPolicy()
        warningMessage = nil
        active = true
        refresh()
    }

    func endSession() {
        active = false
        batteryWarningActive = false
        warningMessage = nil
        notice.dismiss()
    }

    func blockingEvent() -> KeepAwakeSafetyPolicy.Event? {
        thermalState = ProcessInfo.processInfo.thermalState
        return KeepAwakeSafetyPolicy.stopReason(
            snapshot: BatteryReader.read(), thermalPressure: hasThermalPressure,
            configuration: configuration)
    }

    func refresh() { update(BatteryReader.read()) }

    /// Fed by AppModel even with every window closed and history disabled.
    func update(_ snapshot: BatterySnapshot?) {
        thermalState = ProcessInfo.processInfo.thermalState
        guard active else { return }
        var messages: [String] = []
        batteryWarningActive = snapshot.map {
            $0.batteryInstalled && !$0.externalConnected && (0...100).contains($0.percent)
                && $0.percent <= configuration.effectiveWarningPercent && configuration.warnOnLowBattery
        } ?? false
        if batteryWarningActive, let snapshot {
            messages.append(Self.message(for: .batteryWarning(
                percent: snapshot.percent,
                stopAt: configuration.stopOnLowBattery ? configuration.effectiveStopPercent : nil)))
        }
        if hasThermalPressure { messages.append(Self.message(for: .thermalWarning)) }
        warningMessage = messages.isEmpty ? nil : messages.joined(separator: "\n\n")
        if lastNoticeWasThermal ? !hasThermalPressure : !batteryWarningActive { notice.dismiss() }
        let events = policy.evaluate(
            snapshot: snapshot, thermalPressure: hasThermalPressure, configuration: configuration)
        for event in events {
            if event.endsSession {
                onStop?(event)
                return
            }
            let message = Self.message(for: event)
            // This in-app notice also works when notification permission is denied.
            let category = event == .thermalWarning ? "thermal" : "battery"
            lastNoticeWasThermal = event == .thermalWarning
            notice.show(sessionID: UUID().uuidString, message: message,
                        title: String(localized: "Keep Awake needs attention"))
            dispatcher.deliverNotice(identifier: "battistics.keepAwake.\(category)",
                                     title: String(localized: "Keep Awake needs attention"), body: message)
        }
    }

    private var hasThermalPressure: Bool { thermalState == .serious || thermalState == .critical }

    static func message(for event: KeepAwakeSafetyPolicy.Event, starting: Bool = false) -> String {
        switch event {
        case .batteryWarning(let percent, let stopAt):
            if let stopAt {
                return String(localized: "Battery is at \(percent)%. Keep Awake will stop at \(stopAt)%. Connect power or save your work; with the lid closed, the Mac may sleep immediately.")
            }
            return String(localized: "Battery is at \(percent)%. Keep Awake cannot prevent an empty battery from interrupting your work. Connect power soon.")
        case .batteryStop(let percent):
            if starting {
                return String(localized: "Keep Awake cannot start at \(percent)% with battery protection enabled. Connect power before starting a session.")
            }
            return String(localized: "Keep Awake ended because battery charge reached \(percent)%. Normal sleep is allowed again. Connect power before starting another session.")
        case .thermalWarning:
            return String(localized: "macOS reports high thermal pressure. Open the lid, keep the vents clear, and reduce heavy workloads. Battistics does not change fan speeds.")
        case .thermalStop:
            if starting {
                return String(localized: "Keep Awake cannot start while macOS reports high thermal pressure and thermal protection is enabled. Let the Mac cool first.")
            }
            return String(localized: "Keep Awake ended because macOS reported high thermal pressure. Let the Mac cool before starting another session. Battistics does not change fan speeds.")
        }
    }
}
