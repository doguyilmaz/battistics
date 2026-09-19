import BattisticsCore
import SwiftUI

struct MenuBarLabelView: View {
    var snapshot: BatterySnapshot?
    var keepAwakeActive: Bool

    @AppStorage(Prefs.menuBarIconStyle) private var iconStyleRaw = MenuBarIconStyle.bat.rawValue
    @AppStorage(Prefs.menuBarPercentInside) private var percentInside = false
    @AppStorage(Prefs.menuBarShowGlyph) private var showGlyph = true
    @AppStorage(Prefs.menuBarPrimaryText) private var primaryRaw = MenuBarText.chargePercent.rawValue
    @AppStorage(Prefs.menuBarSecondaryText) private var secondaryRaw = MenuBarText.none.rawValue
    @AppStorage(Prefs.menuBarColorLow) private var colorLow = true
    @AppStorage(Prefs.menuBarLowThreshold) private var lowThreshold = 20
    @AppStorage(Prefs.menuBarColorHigh) private var colorHigh = false
    @AppStorage(Prefs.menuBarColorCharging) private var colorCharging = false
    @AppStorage(Prefs.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.both.rawValue
    @AppStorage(Prefs.keepAwakeMenuBarIcon) private var keepAwakeMenuBarIcon = true

    private var config: MenuBarConfig {
        MenuBarConfig(
            iconStyle: MenuBarIconStyle(rawValue: iconStyleRaw) ?? .bat,
            showGlyph: showGlyph,
            primaryText: MenuBarText(rawValue: primaryRaw) ?? .chargePercent,
            secondaryText: MenuBarText(rawValue: secondaryRaw) ?? .none,
            percentInside: percentInside,
            colorLow: colorLow,
            lowThreshold: lowThreshold,
            colorHigh: colorHigh,
            colorCharging: colorCharging,
            temperatureUnit: TemperatureUnit(rawValue: temperatureUnitRaw) ?? .both,
            keepAwakeIcon: keepAwakeMenuBarIcon && keepAwakeActive
        )
    }

    var body: some View {
        Image(nsImage: MenuBarIconRenderer.image(snapshot: snapshot, config: config))
    }
}
