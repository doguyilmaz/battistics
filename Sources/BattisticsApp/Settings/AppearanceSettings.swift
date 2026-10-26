import BattisticsCore
import SwiftUI

/// The Menu Bar pane: everything about the menu bar item, icon style with
/// visual previews, live status preview strip, text slots and color rules.
struct AppearanceSettings: View {
    @AppStorage(Prefs.menuBarIconStyle) private var iconStyleRaw = MenuBarIconStyle.bat.rawValue
    @AppStorage(Prefs.menuBarPercentInside) private var percentInside = false
    @AppStorage(Prefs.menuBarShowGlyph) private var showGlyph = true
    @AppStorage(Prefs.menuBarPrimaryText) private var primaryRaw = MenuBarText.chargePercent.rawValue
    @AppStorage(Prefs.menuBarSecondaryText) private var secondaryRaw = MenuBarText.none.rawValue
    @AppStorage(Prefs.menuBarColorLow) private var colorLow = true
    @AppStorage(Prefs.menuBarLowThreshold) private var lowThreshold = 20
    @AppStorage(Prefs.menuBarColorHigh) private var colorHigh = false
    @AppStorage(Prefs.menuBarColorCharging) private var colorCharging = false
    @AppStorage(Prefs.keepAwakeMenuBarIcon) private var keepAwakeMenuBarIcon = true

    private var iconStyle: MenuBarIconStyle {
        MenuBarIconStyle(rawValue: iconStyleRaw) ?? .bat
    }

    private var config: MenuBarConfig {
        MenuBarConfig(
            iconStyle: iconStyle,
            showGlyph: showGlyph,
            percentInside: percentInside,
            colorLow: colorLow,
            lowThreshold: lowThreshold,
            colorHigh: colorHigh,
            colorCharging: colorCharging
        )
    }

    var body: some View {
        Form {
            Section("Icon Style") {
                HStack(spacing: 12) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        stylePicker(style)
                    }
                }
                .frame(maxWidth: .infinity)
                HStack(spacing: 22) {
                    statusPreview(percent: 100, charging: false, label: String(localized: "Full"))
                    statusPreview(percent: 57, charging: false, label: String(localized: "Normal"))
                    statusPreview(percent: 20, charging: false, label: String(localized: "Low"))
                    statusPreview(percent: 5, charging: false, label: String(localized: "Critical"))
                    statusPreview(percent: 57, charging: true, label: String(localized: "Charging"))
                }
                .frame(maxWidth: .infinity)
            }
            Section {
                Toggle("Show battery glyph", isOn: $showGlyph)
                Toggle("Show percentage inside battery", isOn: $percentInside)
                    .disabled(!showGlyph)
                LabeledContent("Text") {
                    HStack(spacing: 6) {
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
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Toggle("Show an icon while Keep Awake is on", isOn: $keepAwakeMenuBarIcon)
            } header: {
                InfoHeader("Content", info: "The glyph reappears automatically when both texts are set to Nothing.")
            }
            Section {
                ThresholdToggle("Orange when low, red when critical", isOn: $colorLow, percent: $lowThreshold, range: 5...50)
                Toggle("Green when full", isOn: $colorHigh)
                Toggle("Blue while charging", isOn: $colorCharging)
            } header: {
                InfoHeader("Color",
                           info: "Critical red kicks in at 10%. Low battery notifications have their own threshold in Notifications.",
                           "With every color rule off, the icon stays monochrome and matches the menu bar.")
            }
        }
        .formStyle(.grouped)
    }

    private func stylePicker(_ style: MenuBarIconStyle) -> some View {
        let selected = style == iconStyle
        return VStack(spacing: 4) {
            Image(
                nsImage: BatGlyph.image(
                    size: NSSize(width: 58, height: 36),
                    fillFraction: 0.8, charging: false,
                    color: .labelColor, shape: style,
                    percentage: percentInside && showGlyph ? 57 : nil)
            )
            Text(style.label)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
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
        return VStack(spacing: 6) {
            Image(
                nsImage: MenuBarIconRenderer.previewImage(
                    percent: percent, charging: charging, config: config)
            )
            .frame(height: 22)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct ThemeAndIconRows: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.theme) private var themeRaw = ThemePreference.automatic.rawValue
    @AppStorage(Prefs.appIconStyle) private var appIconRaw = AppIconStyle.original.rawValue

    var body: some View {
        Picker("Theme", selection: $themeRaw) {
            ForEach(ThemePreference.allCases) { theme in
                Text(theme.label).tag(theme.rawValue)
            }
        }
        LabeledContent {
            HStack(spacing: 10) {
                ForEach(AppIconStyle.allCases) { style in
                    appIconPicker(style)
                }
            }
        } label: {
            Text("App Icon")
            Text("Applies to the Dock and the app switcher while Battistics runs.")
        }
    }

    private func appIconPicker(_ style: AppIconStyle) -> some View {
        let selected = style.rawValue == appIconRaw
        return Button {
            appIconRaw = style.rawValue
            model.applyAppIcon()
        } label: {
            Group {
                if let image = style.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.title)
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(3)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(style.label)
        .accessibilityLabel(style.label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
