import BattisticsRemote
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(Notifications.enabledKey) private var notify = true
    @AppStorage(Notifications.chargeTargetKey) private var chargeTarget = 0
    @State private var permission: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Notifications", isOn: $notify)
                        .onChange(of: notify) {
                            if !notify { Notifications.cancelAll() }
                            if notify { Task { await Notifications.requestPermission(); await readPermission() } }
                            Task { await MacStore.shared.syncAlertSubscription(removing: !notify) }
                        }
                    if notify {
                        Picker("When Charged To", selection: $chargeTarget) {
                            Text("Off").tag(0)
                            ForEach([80, 90, 100], id: \.self) { Text($0.percentText).tag($0) }
                        }
                    }
                    if notify, permission == .notDetermined {
                        Button("Allow Notifications") {
                            Task { await Notifications.requestPermission(); await readPermission() }
                        }
                    }
                    if notify, permission == .denied {
                        Button("Open Notification Settings") {
                            openURL(URL(string: UIApplication.openNotificationSettingsURLString)!)
                        }
                    }
                } footer: {
                    if notify {
                        Text("Before a timed session ends, when Keep Awake ends unexpectedly, the Mac runs hot, its battery runs low or will not last the session, the lid closes away from Hotspot, repeated checks find no new Mac status, or it charges to the level you pick.")
                    } else {
                        // iCloud alert subscriptions belong to the account, not to one iPhone.
                        Text("The Mac’s own alerts still arrive here while another iPhone on your Apple Account has them on. To silence this iPhone, turn them off in Settings › Notifications.")
                    }
                }

                Section {
                    NavigationLink { AppearanceSettingsView() } label: {
                        Label("Appearance", systemImage: "paintbrush")
                    }
                    NavigationLink { WidgetSettingsView() } label: {
                        Label("Widgets", systemImage: "square.grid.2x2")
                    }
                }

                Section {
                    NavigationLink { NearbyConnectionsView() } label: {
                        Label("Nearby Connections", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    NavigationLink {
                        SetupGuide().navigationTitle("Set Up a Mac").navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label("Set Up a Mac", systemImage: "laptopcomputer.and.iphone")
                    }
                } footer: {
                    Text("Away from Wi‑Fi, turn on Personal Hotspot on this iPhone. A Mac set to join it automatically stays online in a bag with the lid closed.")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                    Link(destination: URL(string: "https://battistics.doguyilmaz.com")!) {
                        Label("Website and Help", systemImage: "safari")
                    }
                    Link(destination: URL(string: "https://battistics.doguyilmaz.com/docs/privacy/")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }
            }
            .topBlur()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await readPermission() }
        }
        .softScrollEdge()
    }

    private func readPermission() async {
        permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

struct AppearanceSettingsView: View {
    @Environment(LocalPhoneMonitor.self) private var phone
    @AppStorage(PhoneTheme.key) private var theme = PhoneTheme.automatic

    var body: some View {
        @Bindable var phone = phone
        Form {
            Section("Theme") {
                Picker("Theme", selection: $theme) {
                    ForEach(PhoneTheme.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                TextField(phone.hotspotName ?? String(localized: "iPhone"), text: $phone.customName)
            } header: {
                Text("This iPhone’s Name")
            } footer: {
                Text("iOS does not tell apps your iPhone’s name. It appears in the device menu as \(phone.pickerName).")
            }
        }
        .topBlur()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum PhoneTheme: String, CaseIterable, Identifiable {
    case automatic, light, dark

    static let key = "phoneThemePreference"
    var id: Self { self }

    var label: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    /// Set on the window rather than through `preferredColorScheme`, which
    /// never hands an open sheet back to the system appearance.
    @MainActor
    func apply() {
        let style: UIUserInterfaceStyle = switch self {
        case .automatic: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.windows.forEach { $0.overrideUserInterfaceStyle = style }
        }
    }
}
