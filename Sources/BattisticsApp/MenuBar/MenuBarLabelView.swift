import BattisticsCore
import SwiftUI

struct MenuBarLabelView: View {
    var model: AppModel

    @AppStorage(Prefs.menuBarShowGlyph) private var showGlyph = true
    @AppStorage(Prefs.menuBarPrimaryText) private var primaryRaw = MenuBarText.chargePercent.rawValue
    @AppStorage(Prefs.menuBarSecondaryText) private var secondaryRaw = MenuBarText.none.rawValue
    @AppStorage(Prefs.menuBarColorLow) private var colorLow = true
    @AppStorage(Prefs.menuBarLowThreshold) private var lowThreshold = 20
    @AppStorage(Prefs.menuBarColorHigh) private var colorHigh = false
    @AppStorage(Prefs.menuBarColorCharging) private var colorCharging = false
    @AppStorage(Prefs.temperatureUnit) private var temperatureUnitRaw = TemperatureUnit.both.rawValue

    private var config: MenuBarConfig {
        MenuBarConfig(
            showGlyph: showGlyph,
            primaryText: MenuBarText(rawValue: primaryRaw) ?? .chargePercent,
            secondaryText: MenuBarText(rawValue: secondaryRaw) ?? .none,
            colorLow: colorLow,
            lowThreshold: lowThreshold,
            colorHigh: colorHigh,
            colorCharging: colorCharging,
            temperatureUnit: TemperatureUnit(rawValue: temperatureUnitRaw) ?? .both
        )
    }

    var body: some View {
        Image(nsImage: MenuBarIconRenderer.image(snapshot: model.snapshot, config: config))
    }
}
