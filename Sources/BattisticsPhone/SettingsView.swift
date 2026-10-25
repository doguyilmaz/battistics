import BattisticsRemote
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

struct SettingsView: View {
    @Environment(MacStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(Notifications.enabledKey) private var notify = true
    @AppStorage("phoneAppIconStyle") private var appIconRaw = PhoneIconStyle.original.rawValue
    @State private var permission: UNAuthorizationStatus = .notDetermined
    @State private var phone = LocalPhoneMonitor.shared
    @State private var widgetPrefs = WidgetPreferences.load()

    var body: some View {
        NavigationStack {
            Form {
                Section("Your Macs") {
                    if store.macs.isEmpty {
                        Label("No Macs sharing right now", systemImage: "laptopcomputer.slash")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.macs) { mac in
                            let reading = store.reading(for: mac)
                            let status = reading?.status
                            let isSelected = !store.isLocalPhoneSelected && store.selected?.id == mac.id
                            Button {
                                withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                                    store.selectedID = mac.id
                                }
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: status?.network == .hotspot ? "personalhotspot" : "laptopcomputer")
                                        .font(.title3)
                                        .foregroundStyle(status?.network == .hotspot ? PowerPalette.hotspot : Color.accentColor)
                                        .frame(width: 28)

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(mac.name)
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            if status?.session != nil {
                                                Image(systemName: "cup.and.saucer.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                        HStack(spacing: 4) {
                                            if let netName = status?.resolvedNetworkName(fallbackHotspot: phone.displayBaseName) {
                                                Text(netName)
                                            } else if let status {
                                                Text(status.network.label)
                                            }
                                            if let seen = reading?.lastSeen {
                                                Text("·")
                                                Text(seen.formatted(.relative(presentation: .named)))
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    }

                                    Spacer()

                                    if let battery = status?.battery {
                                        HStack(spacing: 3) {
                                            if battery.lowPowerMode == true {
                                                Image(systemName: "leaf.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(PowerPalette.lowPower)
                                            } else if battery.isCharging {
                                                Image(systemName: "bolt.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(PowerPalette.charging)
                                            }
                                            Text("\(battery.percent)%")
                                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Your iPhones") {
                    Button {
                        phone.refresh()
                        phone.ingestPairedPhoneName(from: store.readings)
                        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                            store.selectedID = MacStore.localPhoneID
                        }
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "iphone")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(phone.pickerDisplayName)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("iOS \(UIDevice.current.systemVersion) · \(phone.currentChargeMah) mAh")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            HStack(spacing: 3) {
                                if phone.lowPowerMode {
                                    Image(systemName: "leaf.fill")
                                        .font(.caption2)
                                        .foregroundStyle(PowerPalette.lowPower)
                                } else if phone.isCharging {
                                    Image(systemName: "bolt.fill")
                                        .font(.caption2)
                                        .foregroundStyle(PowerPalette.charging)
                                }
                                Text("\(phone.percent)%")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            if store.isLocalPhoneSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("Customization") {
                    NavigationLink {
                        PhoneAppearanceSettingsView()
                    } label: {
                        HStack {
                            Label("Appearance", systemImage: "paintbrush.pointed.fill")
                            Spacer()
                            Text((PhoneIconStyle(rawValue: appIconRaw) ?? .original).label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        PhoneWidgetSettingsView(prefs: $widgetPrefs)
                    } label: {
                        HStack {
                            Label("Widgets", systemImage: "square.grid.2x2.fill")
                            Spacer()
                            Text(widgetPrefs.lockScreenLayout.label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Section {
                    Text("With no Wi‑Fi nearby, turn on Settings › Personal Hotspot › Allow Others to Join. A Mac with Ask to join hotspots set to Automatic connects by itself, and Keep Awake keeps it connected with the lid closed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Personal Hotspot & Closed-Lid")
                }

                Section {
                    Toggle("Notify me", isOn: $notify)
                    if permission == .denied {
                        Button("Allow Notifications in Settings") {
                            openURL(URL(string: UIApplication.openNotificationSettingsURLString)!)
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Alerts you when Keep Awake ends, the battery runs low or will not last the session, or a Mac stops answering mid-session.")
                }
            }
            .navigationTitle("Devices & Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                phone.ingestPairedPhoneName(from: store.readings)
                permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            }
        }
    }
}

/// The window override reaches sheets too, unlike `preferredColorScheme(nil)`,
/// which never hands a presented sheet back to the system appearance.
@MainActor
enum PhoneThemeManager {
    static func apply(_ themeRaw: String) {
        let style: UIUserInterfaceStyle = {
            switch themeRaw {
            case "light": .light
            case "dark": .dark
            default: .unspecified
            }
        }()
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

enum PhoneIconStyle: String, CaseIterable, Identifiable {
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

    var alternateIconName: String? {
        switch self {
        case .original: nil
        case .gauge: "gauge"
        case .batBattery: "batbattery"
        case .stats: "stats"
        }
    }

    var uiImage: UIImage? {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "png"),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            return image
        }
        return UIImage(named: resourceName)
    }
}

struct PhoneAppearanceSettingsView: View {
    @AppStorage("phoneAppIconStyle") private var appIconRaw = PhoneIconStyle.original.rawValue
    @AppStorage("phoneThemePreference") private var themeRaw = "automatic"
    @AppStorage("phoneAmbientEnergyBackdrop") private var showAmbientBackdrop = true
    @State private var phone = LocalPhoneMonitor.shared
    @State private var nameInput = ""

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(PhoneIconStyle.allCases) { style in
                        iconCard(style)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("App Icon & Logo")
            } footer: {
                Text("Choose your preferred Battistics logo style.")
            }

            Section("Theme & Visuals") {
                Picker("Theme", selection: $themeRaw) {
                    Text("Automatic").tag("automatic")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }

                Toggle("Background Glow", isOn: $showAmbientBackdrop)
            }

            Section {
                HStack {
                    Text("iPhone Name")
                    Spacer()
                    TextField(phone.displayBaseName, text: $nameInput)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: nameInput) {
                            phone.customDeviceName = nameInput
                        }
                }
                LabeledContent("Picker Preview", value: phone.pickerDisplayName)
            } header: {
                Text("iPhone Identity")
            } footer: {
                Text("Shown in the device switcher as Name (\(phone.shortModelName)).")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            nameInput = phone.customDeviceName
            let current = UIApplication.shared.alternateIconName
            appIconRaw = (PhoneIconStyle.allCases.first { $0.alternateIconName == current } ?? .original).rawValue
        }
    }

    private func iconCard(_ style: PhoneIconStyle) -> some View {
        let selected = (appIconRaw == style.rawValue)
        return Button {
            Task {
                guard UIApplication.shared.supportsAlternateIcons,
                      (try? await UIApplication.shared.setAlternateIconName(style.alternateIconName)) != nil else { return }
                withAnimation(.snappy(duration: 0.2)) { appIconRaw = style.rawValue }
            }
        } label: {
            VStack(spacing: 8) {
                if let img = style.uiImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                } else {
                    Image(systemName: "bolt.batteryblock.fill")
                        .font(.largeTitle)
                        .frame(width: 60, height: 60)
                }
                HStack(spacing: 4) {
                    Text(style.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.14) : Color(.tertiarySystemFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct PhoneWidgetSettingsView: View {
    @Environment(MacStore.self) private var store
    @Binding var prefs: WidgetPreferences

    var body: some View {
        let mac = store.selected ?? store.macs.first
        let reading = mac.flatMap { store.reading(for: $0) }
        let snapshot: SharedSnapshot = {
            if let mac, let status = reading?.status {
                return SharedSnapshot(
                    macName: mac.name,
                    status: status,
                    lastSeen: reading?.lastSeen ?? .now,
                    reachable: reading?.reachable ?? true
                )
            }
            return .sample()
        }()
        let entry = MacEntry(date: .now, snapshot: snapshot, prefs: prefs)

        Form {
            Section {
                Picker("Lock Screen Layout", selection: $prefs.lockScreenLayout) {
                    ForEach(WidgetPreferences.LockScreenLayout.allCases) { layout in
                        Text(layout.label).tag(layout)
                    }
                }

                Picker("Telemetry Focus", selection: $prefs.metricFocus) {
                    ForEach(WidgetPreferences.MetricFocus.allCases) { focus in
                        Text(focus.label).tag(focus)
                    }
                }

                Toggle("Show Wi‑Fi / Hotspot Name", isOn: $prefs.showNetworkSSID)
            } header: {
                Text("Widget Options")
            } footer: {
                Text("Changes apply immediately to your widgets and the live previews below.")
            }

            Section("Lock Screen Widgets") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        BlueprintCard(title: "Rectangular · \(prefs.lockScreenLayout.label)", badge: "RECTANGULAR", width: 220, canvasHeight: 96) {
                            MacLockScreenDetailView(entry: entry, familyOverride: .accessoryRectangular)
                                .padding(10)
                                .frame(width: 180, height: 80)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.black.opacity(0.90))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                                )
                        }

                        BlueprintCard(title: "Circular Gauge", badge: "CIRCULAR", width: 140, canvasHeight: 96) {
                            MacLockScreenDetailView(entry: entry, familyOverride: .accessoryCircular)
                                .frame(width: 78, height: 78)
                                .background(
                                    Circle()
                                        .fill(Color.black.opacity(0.90))
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                                )
                        }

                        BlueprintCard(title: "Inline Header", badge: "INLINE", width: 200, canvasHeight: 96) {
                            HStack {
                                MacLockScreenDetailView(entry: entry, familyOverride: .accessoryInline)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.90))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                .listRowBackground(Color.clear)
            }

            Section("Home Screen Widgets") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        BlueprintCard(title: "Dashboard", badge: "MEDIUM · 4×2", width: 330, canvasHeight: 168) {
                            MacWidgetView(entry: entry, familyOverride: .systemMedium)
                                .padding(12)
                                .frame(width: 306, height: 148)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        }

                        BlueprintCard(title: "Dashboard", badge: "SMALL · 2×2", width: 180, canvasHeight: 168) {
                            MacWidgetView(entry: entry, familyOverride: .systemSmall)
                                .padding(12)
                                .frame(width: 148, height: 148)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        }

                        BlueprintCard(title: "Battery Telemetry", badge: "MEDIUM · 4×2", width: 330, canvasHeight: 168) {
                            MacTelemetryWidgetView(entry: entry, familyOverride: .systemMedium)
                                .padding(12)
                                .frame(width: 306, height: 148)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        }

                        BlueprintCard(title: "Battery Telemetry", badge: "SMALL · 2×2", width: 180, canvasHeight: 168) {
                            MacTelemetryWidgetView(entry: entry, familyOverride: .systemSmall)
                                .padding(12)
                                .frame(width: 148, height: 148)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        }

                        BlueprintCard(title: "Full Dashboard", badge: "LARGE · 4×4", width: 330, canvasHeight: 168) {
                            MacWidgetView(entry: entry, familyOverride: .systemLarge)
                                .padding(14)
                                .frame(width: 300, height: 300)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                .scaleEffect(0.50)
                                .frame(width: 306, height: 150)
                                .clipped()
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Widgets & Lock Screen")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: prefs) {
            prefs.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

// MARK: - Blueprint Containers

private struct BlueprintGridPattern: Shape {
    var spacing: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        return path
    }
}

private struct BlueprintCard<Content: View>: View {
    let title: LocalizedStringKey
    let badge: String
    let cardWidth: CGFloat
    let canvasHeight: CGFloat
    let content: Content

    init(
        title: LocalizedStringKey,
        badge: String,
        width: CGFloat,
        canvasHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.badge = badge
        self.cardWidth = width
        self.canvasHeight = canvasHeight
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(verbatim: badge)
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                    )
            }

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground).opacity(0.6))

                BlueprintGridPattern(spacing: 14)
                    .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                content
            }
            .frame(height: canvasHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
        .padding(10)
        .frame(width: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
