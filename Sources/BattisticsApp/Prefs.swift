import BattisticsCore
import Foundation
import SwiftUI

enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case bat
    case classic
    case gauge
    case stats
    case wings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bat: String(localized: "Bat")
        case .classic: String(localized: "Classic")
        case .gauge: String(localized: "Gauge")
        case .stats: String(localized: "Stats")
        case .wings: String(localized: "Wings")
        }
    }
}

enum AppIconStyle: String, CaseIterable, Identifiable {
    case original
    case gauge
    case batBattery
    case stats

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: String(localized: "Original")
        case .gauge: String(localized: "Gauge")
        case .batBattery: String(localized: "Bat Battery")
        case .stats: String(localized: "Stats")
        }
    }

    var resourceName: String {
        switch self {
        case .original: "original"
        case .gauge: "gauge"
        case .batBattery: "batbattery"
        case .stats: "stats"
        }
    }

    var image: NSImage? {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    /// The Dock frames the bundle icon to the system icon grid but draws
    /// runtime-set icons as-is, so a full-bleed PNG looks oversized next to
    /// other Dock icons. Inset the artwork to the standard grid (824/1024).
    var dockImage: NSImage? {
        guard let art = image else { return nil }
        let side: CGFloat = 1024
        let inset = (side - 824) / 2
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            art.draw(in: rect.insetBy(dx: inset, dy: inset))
            return true
        }
    }
}

enum MenuBarText: String, CaseIterable, Identifiable {
    case none
    case chargePercent
    case healthPercent
    case timeRemaining
    case temperature
    case watts
    case currentmAh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: String(localized: "Nothing")
        case .chargePercent: String(localized: "Charge %")
        case .healthPercent: String(localized: "Health %")
        case .timeRemaining: String(localized: "Time remaining")
        case .temperature: String(localized: "Temperature")
        case .watts: String(localized: "Power (W)")
        case .currentmAh: String(localized: "Charge (mAh)")
        }
    }
}

enum ThemePreference: String, CaseIterable, Identifiable {
    case automatic
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum Prefs {
    static let showMenuBarIcon = "showMenuBarIcon"
    static let showDockIcon = "showDockIcon"
    static let openDashboardAtLaunch = "openDashboardAtLaunch"
    static let keepDashboardOnTop = "keepDashboardOnTop"
    static let theme = "theme"
    static let temperatureUnit = "temperatureUnit"

    static let appIconStyle = "appIconStyle"
    static let menuBarIconStyle = "menuBarIconStyle"
    static let menuBarPercentInside = "menuBarPercentInside"
    static let menuBarShowGlyph = "menuBarShowGlyph"
    static let menuBarPrimaryText = "menuBarPrimaryText"
    static let menuBarSecondaryText = "menuBarSecondaryText"
    static let menuBarColorLow = "menuBarColorLow"
    static let menuBarLowThreshold = "menuBarLowThreshold"
    static let menuBarColorHigh = "menuBarColorHigh"
    static let menuBarColorCharging = "menuBarColorCharging"

    static let keepAwakeMode = "keepAwakeMode"
    static let keepAwakeDuration = "keepAwakeDuration"
    static let keepAwakeMenuBarIcon = "keepAwakeMenuBarIcon"
    static let helperRegisteredVersion = "helperRegisteredVersion"
    static let readBluetoothBatteries = "readBluetoothBatteries"

    static let showPowerFlow = "showPowerFlow"

    static let powerSamplingEnabled = "powerSamplingEnabled"
    static let powerSamplingInterval = "powerSamplingInterval"

    static let alertSoundEnabled = "alertSoundEnabled"
    static let alertLowEnabled = "alertLowEnabled"
    static let alertLowThreshold = "alertLowThreshold"
    static let alertDropEnabled = "alertDropEnabled"
    static let alertDropStep = "alertDropStep"
    static let alertChargeLimitEnabled = "alertChargeLimitEnabled"
    static let alertChargeLimitThreshold = "alertChargeLimitThreshold"
    static let alertFullEnabled = "alertFullEnabled"
    static let alertHighTempEnabled = "alertHighTempEnabled"
    static let alertHighTempThreshold = "alertHighTempThreshold"
    static let alertDurationEnabled = "alertDurationEnabled"
    static let alertDurationHours = "alertDurationHours"
    static let alertHealthDropEnabled = "alertHealthDropEnabled"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showMenuBarIcon: true,
            showDockIcon: false,
            openDashboardAtLaunch: false,
            keepDashboardOnTop: false,
            theme: ThemePreference.automatic.rawValue,
            temperatureUnit: TemperatureUnit.both.rawValue,

            appIconStyle: AppIconStyle.original.rawValue,
            menuBarIconStyle: MenuBarIconStyle.bat.rawValue,
            menuBarShowGlyph: true,
            menuBarPercentInside: false,
            menuBarPrimaryText: MenuBarText.chargePercent.rawValue,
            menuBarSecondaryText: MenuBarText.none.rawValue,
            menuBarColorLow: true,
            menuBarLowThreshold: 20,
            menuBarColorHigh: false,
            menuBarColorCharging: false,

            keepAwakeMode: KeepAwakeMode.displayOn.rawValue,
            keepAwakeDuration: KeepAwakeDuration.indefinite.rawValue,
            keepAwakeMenuBarIcon: true,
            readBluetoothBatteries: false,

            showPowerFlow: true,
            powerSamplingEnabled: true,
            powerSamplingInterval: 60,

            alertSoundEnabled: true,
            alertLowEnabled: true,
            alertLowThreshold: 20,
            alertDropEnabled: true,
            alertDropStep: 5,
            alertChargeLimitEnabled: false,
            alertChargeLimitThreshold: 80,
            alertFullEnabled: true,
            alertHighTempEnabled: true,
            alertHighTempThreshold: 40.0,
            alertDurationEnabled: false,
            alertDurationHours: 3.0,
            alertHealthDropEnabled: true,
        ])
    }

    static func alertConfig() -> AlertConfig {
        let defaults = UserDefaults.standard
        return AlertConfig(
            lowBatteryEnabled: defaults.bool(forKey: alertLowEnabled),
            lowBatteryThreshold: defaults.integer(forKey: alertLowThreshold),
            significantDropEnabled: defaults.bool(forKey: alertDropEnabled),
            significantDropStep: defaults.integer(forKey: alertDropStep),
            chargeLimitEnabled: defaults.bool(forKey: alertChargeLimitEnabled),
            chargeLimitThreshold: defaults.integer(forKey: alertChargeLimitThreshold),
            fullChargeEnabled: defaults.bool(forKey: alertFullEnabled),
            highTemperatureEnabled: defaults.bool(forKey: alertHighTempEnabled),
            highTemperatureThresholdC: defaults.double(forKey: alertHighTempThreshold),
            onBatteryDurationEnabled: defaults.bool(forKey: alertDurationEnabled),
            onBatteryDurationHours: defaults.double(forKey: alertDurationHours)
        )
    }

    static var temperatureUnitValue: TemperatureUnit {
        TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: temperatureUnit) ?? "") ?? .both
    }
}
