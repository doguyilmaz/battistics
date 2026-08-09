import BattisticsCore
import Foundation
import UserNotifications

/// Delivers core-evaluated alerts as user notifications. Authorization is
/// requested lazily on the first alert, never at launch.
@MainActor
final class AlertDispatcher {
    private var authorizationRequested = false

    func deliver(_ alert: BatteryAlert) {
        Task { [weak self] in
            await self?.deliverAsync(alert)
        }
    }

    private func deliverAsync(_ alert: BatteryAlert) async {
        let center = UNUserNotificationCenter.current()
        if !authorizationRequested {
            authorizationRequested = true
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        else { return }

        let content = UNMutableNotificationContent()
        let message = Self.message(for: alert)
        content.title = message.title
        content.body = message.body
        if UserDefaults.standard.bool(forKey: Prefs.alertSoundEnabled) {
            content.sound = .default
        }
        let request = UNNotificationRequest(
            identifier: Self.identifier(for: alert), content: content, trigger: nil)
        try? await center.add(request)
    }

    static func message(for alert: BatteryAlert) -> (title: String, body: String) {
        switch alert {
        case .lowBattery(let percent):
            ("Battery Low", "Charge is at \(percent)%. Connect power soon.")
        case .significantDrop(let percent):
            ("Battery Draining", "Charge dropped to \(percent)%.")
        case .chargeLimitReached(let percent):
            ("Charge Limit Reached", "Battery is at \(percent)%. Unplug now to reduce battery wear.")
        case .fullyCharged:
            ("Fully Charged", "Battery is fully charged. You can unplug the power adapter.")
        case .highTemperature(let celsius):
            (
                "Battery Running Hot",
                "Battery temperature is \(Formatting.temperature(celsius, unit: Prefs.temperatureUnitValue))."
            )
        case .onBatteryDuration(let hours):
            (
                "Still on Battery",
                "The Mac has been on battery power for \(Formatting.duration(minutes: Int(hours * 60)))."
            )
        case .healthDropped(let from, let to):
            (
                "Battery Health Declined",
                "Maximum capacity dropped from \(Formatting.percentPrecise(from)) to \(Formatting.percentPrecise(to))."
            )
        }
    }

    static func identifier(for alert: BatteryAlert) -> String {
        switch alert {
        case .lowBattery: "battistics.lowBattery"
        case .significantDrop: "battistics.significantDrop"
        case .chargeLimitReached: "battistics.chargeLimit"
        case .fullyCharged: "battistics.fullyCharged"
        case .highTemperature: "battistics.highTemperature"
        case .onBatteryDuration: "battistics.onBatteryDuration"
        case .healthDropped: "battistics.healthDropped"
        }
    }
}
