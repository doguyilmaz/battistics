import SwiftUI

struct MenuBarSettings: View {
    @AppStorage(Prefs.menuBarShowGlyph) private var showGlyph = true
    @AppStorage(Prefs.menuBarPrimaryText) private var primaryRaw = MenuBarText.chargePercent.rawValue
    @AppStorage(Prefs.menuBarSecondaryText) private var secondaryRaw = MenuBarText.none.rawValue
    @AppStorage(Prefs.menuBarColorLow) private var colorLow = true
    @AppStorage(Prefs.menuBarLowThreshold) private var lowThreshold = 20
    @AppStorage(Prefs.menuBarColorHigh) private var colorHigh = false
    @AppStorage(Prefs.menuBarColorCharging) private var colorCharging = false

    var body: some View {
        Form {
            Section("Content") {
                Toggle("Show battery glyph", isOn: $showGlyph)
                Picker("Primary text", selection: $primaryRaw) {
                    ForEach(MenuBarText.allCases) { kind in
                        Text(kind.label).tag(kind.rawValue)
                    }
                }
                Picker("Secondary text", selection: $secondaryRaw) {
                    ForEach(MenuBarText.allCases) { kind in
                        Text(kind.label).tag(kind.rawValue)
                    }
                }
                Text("The glyph reappears automatically when both texts are set to Nothing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Color") {
                Toggle("Red when charge is low", isOn: $colorLow)
                if colorLow {
                    LabeledContent("Low threshold: \(lowThreshold)%") {
                        Slider(
                            value: Binding(
                                get: { Double(lowThreshold) },
                                set: { lowThreshold = Int($0) }
                            ), in: 5...50, step: 5)
                    }
                }
                Toggle("Green when charge is high", isOn: $colorHigh)
                Toggle("Green while charging", isOn: $colorCharging)
                Text("With every color rule off, the icon stays monochrome and matches the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
