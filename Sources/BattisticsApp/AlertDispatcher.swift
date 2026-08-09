import BattisticsCore
import Foundation
import UserNotifications

/// Delivers core-evaluated alerts as user notifications. Authorization is
/// requested lazily on the first alert, never at launch.
@MainActor
final class AlertDispatcher {
    /// Single shared authorization request so alerts arriving while the
    /// permission prompt is still open wait for its outcome instead of
    /// reading .notDetermined and getting dropped.
    private var authorizationTask: Task<Void, Never>?

    func deliver(_ alert: BatteryAlert) {
        Task { [weak self] in
            await self?.deliverAsync(alert)
        }
    }

    private func deliverAsync(_ alert: BatteryAlert) async {
        let center = UNUserNotificationCenter.current()
        if authorizationTask == nil {
            authorizationTask = Task {
                _ = try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound])
            }
        }
        await authorizationTask?.value
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
            (
                String(localized: "Battery Low"),
                String(localized: "Charge is at \(percent)%. Connect power soon.")
            )
        case .significantDrop(let percent):
            (
                String(localized: "Battery Draining"),
                String(localized: "Charge dropped to \(percent)%.")
            )
        case .chargeLimitReached(let percent):
            (
                String(localized: "Charge Limit Reached"),
                String(localized: "Battery is at \(percent)%. Unplug now to reduce battery wear.")
            )
        case .fullyCharged:
            (
                String(localized: "Fully Charged"),
                String(localized: "Battery is fully charged. You can unplug the power adapter.")
            )
        case .highTemperature(let celsius):
            (
                String(localized: "Battery Running Hot"),
                String(
                    localized:
                        "Battery temperature is \(Formatting.temperature(celsius, unit: Prefs.temperatureUnitValue))."
                )
            )
        case .onBatteryDuration(let hours):
            (
                String(localized: "Still on Battery"),
                String(
                    localized:
                        "The Mac has been on battery power for \(Formatting.duration(minutes: Int(hours * 60)))."
                )
            )
        case .healthDropped(let from, let to):
            (
                String(localized: "Battery Health Declined"),
                String(
                    localized:
                        "Maximum capacity dropped from \(Formatting.percentPrecise(from)) to \(Formatting.percentPrecise(to))."
                )
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
