import BattisticsCore
import SwiftUI

struct MenuBarLabelView: View {
    var model: AppModel

    @AppStorage(Prefs.menuBarIconStyle) private var iconStyleRaw = MenuBarIconStyle.bat.rawValue
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
            iconStyle: MenuBarIconStyle(rawValue: iconStyleRaw) ?? .bat,
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
        // Reading the generation is what subscribes this view to system
        // light/dark changes; the value itself is not used.
        let _ = model.appearanceGeneration
        Image(nsImage: MenuBarIconRenderer.image(snapshot: model.snapshot, config: config))
    }
}
