import BattisticsCore
import SwiftUI

/// Theme plus everything about the menu bar item: icon style with visual
/// previews, live status preview strip, text slots and color rules.
struct AppearanceSettings: View {
    @AppStorage(Prefs.theme) private var themeRaw = ThemePreference.automatic.rawValue
    @AppStorage(Prefs.menuBarIconStyle) private var iconStyleRaw = MenuBarIconStyle.bat.rawValue
    @AppStorage(Prefs.menuBarShowGlyph) private var showGlyph = true
    @AppStorage(Prefs.menuBarPrimaryText) private var primaryRaw = MenuBarText.chargePercent.rawValue
    @AppStorage(Prefs.menuBarSecondaryText) private var secondaryRaw = MenuBarText.none.rawValue
    @AppStorage(Prefs.menuBarColorLow) private var colorLow = true
    @AppStorage(Prefs.menuBarLowThreshold) private var lowThreshold = 20
    @AppStorage(Prefs.menuBarColorHigh) private var colorHigh = false
    @AppStorage(Prefs.menuBarColorCharging) private var colorCharging = false

    private var iconStyle: MenuBarIconStyle {
        MenuBarIconStyle(rawValue: iconStyleRaw) ?? .bat
    }

    private var config: MenuBarConfig {
        MenuBarConfig(
            iconStyle: iconStyle,
            colorLow: colorLow,
            lowThreshold: lowThreshold,
            colorHigh: colorHigh,
            colorCharging: colorCharging
        )
    }

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $themeRaw) {
                    ForEach(ThemePreference.allCases) { theme in
                        Text(theme.label).tag(theme.rawValue)
                    }
                }
            }
            Section("Icon Style") {
                HStack(spacing: 14) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        stylePicker(style)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Section("Preview") {
                HStack(spacing: 18) {
                    statusPreview(percent: 100, charging: false, label: String(localized: "Full"))
                    statusPreview(percent: 57, charging: false, label: String(localized: "Normal"))
                    statusPreview(percent: 20, charging: false, label: String(localized: "Low"))
                    statusPreview(percent: 5, charging: false, label: String(localized: "Critical"))
                    statusPreview(percent: 57, charging: true, label: String(localized: "Charging"))
                }
                .frame(maxWidth: .infinity)
            }
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
                Toggle("Orange when low, red when critical", isOn: $colorLow)
                if colorLow {
                    LabeledContent("Low threshold: \(lowThreshold)%") {
                        Slider(
                            value: Binding(
                                get: { Double(lowThreshold) },
                                set: { lowThreshold = Int($0) }
                            ), in: 5...50, step: 5)
                    }
                    Text("Critical red kicks in at 10%.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Green when full", isOn: $colorHigh)
                Toggle("Blue while charging", isOn: $colorCharging)
                Text("With every color rule off, the icon stays monochrome and matches the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func stylePicker(_ style: MenuBarIconStyle) -> some View {
        let selected = style == iconStyle
        return VStack(spacing: 8) {
            Image(
                nsImage: BatGlyph.image(
                    size: NSSize(width: 58, height: 36),
                    fillFraction: 0.8, charging: false,
                    color: .labelColor, shape: style)
            )
            Text(style.label)
                .font(.caption)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    selected ? Color.accentColor : Color.secondary.opacity(0.25),
                    lineWidth: selected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            iconStyleRaw = style.rawValue
        }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func statusPreview(percent: Int, charging: Bool, label: String) -> some View {
        let tint = MenuBarIconRenderer.tintColor(
            percent: percent, charging: charging, external: charging, config: config)
        return VStack(spacing: 6) {
            Image(
                nsImage: BatGlyph.image(
                    size: NSSize(width: 44, height: 27),
                    fillFraction: charging ? nil : CGFloat(percent) / 100,
                    charging: charging,
                    color: tint ?? .labelColor,
                    shape: iconStyle)
            )
            Text("\(percent)%")
                .font(.caption2)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
