import SwiftUI
import UserNotifications

/// A menu bar app must survive its last window closing; SwiftUI's default
/// is to terminate once no regular windows remain, which kills the app the
/// moment Settings closes while the Dock icon is enabled.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// iCloud's silent push for the iPhone companion's zone. Alerts another
    /// Mac on the account posts for the phones arrive here too and are
    /// taken down, since they are not about this Mac.
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        NotificationCenter.default.post(name: .battisticsRemotePush, object: nil)
        Task {
            let center = UNUserNotificationCenter.current()
            let pushed = await center.deliveredNotifications().filter { $0.request.content.userInfo["ck"] != nil }
            center.removeDeliveredNotifications(withIdentifiers: pushed.map(\.request.identifier))
        }
    }

    /// Opens the dashboard at launch through the app's own URL scheme.
    /// This works in every icon configuration; a view-based approach only
    /// runs when the menu bar label happens to exist.
    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: Prefs.openDashboardAtLaunch)
            || !UserDefaults.standard.bool(forKey: Prefs.hasSeenTour) {
            Self.openDashboard()
        }
    }

    /// Clicking the Dock icon with no open windows sends "reopen"; answer
    /// it with the dashboard, the expected macOS behavior.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            Self.openDashboard()
        }
        return true
    }

    fileprivate static func openDashboard() {
        if let url = URL(string: "battistics://dashboard") {
            // Target this bundle so another installed copy cannot receive
            // navigation initiated by the running app.
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: Bundle.main.bundleURL,
                configuration: NSWorkspace.OpenConfiguration(),
                completionHandler: nil
            )
        }
    }

    /// battistics://dashboard/<pane> deep links select a dashboard pane.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "battistics" {
            guard let pane = url.pathComponents.dropFirst().first else { continue }
            NotificationCenter.default.post(
                name: .battisticsSelectPane, object: nil, userInfo: ["pane": pane])
        }
    }
}

@main
struct BattisticsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @State private var updater = UpdaterModel()
    @State private var keepAwake: KeepAwakeModel
    @State private var automation: AutomationModel
    @State private var network: NetworkMonitor
    @State private var remote: RemoteAccessModel
    @State private var powerAuth = PowerAuthorization()
    @State private var powerSettings: PowerSettingsModel
    @State private var powerHelper: PowerHelperClient
    @State private var bluetooth = BluetoothGATTReader()

    @AppStorage(Prefs.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(Prefs.theme) private var themeRaw = ThemePreference.automatic.rawValue

    init() {
        Prefs.markTourSeenForExistingInstall()
        Prefs.registerDefaults()
        let helper = PowerHelperClient()
        let awake = KeepAwakeModel(helper: helper)
        _powerHelper = State(initialValue: helper)
        _keepAwake = State(initialValue: awake)
        let automation = AutomationModel(awake: awake, helper: helper)
        let network = NetworkMonitor()
        _automation = State(initialValue: automation)
        _network = State(initialValue: network)
        let model = AppModel(
            onBatteryReading: { [weak awake] in awake?.safety.update($0) },
            suppressLowBatteryNotification: { [weak awake] in awake?.safety.batteryWarningActive == true })
        _model = State(initialValue: model)
        let history = model.history
        let powerSettings = PowerSettingsModel()
        _powerSettings = State(initialValue: powerSettings)
        _remote = State(initialValue: RemoteAccessModel(
            awake: awake, automation: automation, helper: helper, network: network, powerSettings: powerSettings,
            battery: { [weak model] in model?.snapshot },
            chargeHistory: {
                let now = Date()
                return await history.chargeSeries(from: now.addingTimeInterval(-86_400), to: now, bucketSeconds: 1800)
                    .map { .init(at: $0.date, percent: $0.value) }
            }))
    }

    private var colorScheme: ColorScheme? {
        (ThemePreference(rawValue: themeRaw) ?? .automatic).colorScheme
    }

    private var appEnvironment: AppEnvironment {
        AppEnvironment(model: model, updater: updater, keepAwake: keepAwake, automation: automation,
                       network: network, remote: remote, powerAuth: powerAuth, powerSettings: powerSettings,
                       powerHelper: powerHelper, bluetooth: bluetooth, colorScheme: colorScheme)
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            PopoverView()
                .modifier(appEnvironment)
        } label: {
            MenuBarLabelView(snapshot: model.snapshot, keepAwakeActive: keepAwake.isActive)
        }
        .menuBarExtraStyle(.window)

        Window("Battistics", id: "dashboard") {
            DashboardView()
                .modifier(appEnvironment)
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: ["dashboard"])

        // Compact always-on-top stats window ("pinned popover").
        Window("Battistics", id: "mini") {
            PopoverView(isPinnedWindow: true)
                .modifier(appEnvironment)
                .background(WindowLevelConfigurator(keepOnTop: true))
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: ["mini"])
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updater)
            }
            // Settings live inside the dashboard; keep the standard app
            // menu item and Cmd+, pointing there.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    model.dashboardPane = .general
                    AppDelegate.openDashboard()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("Take a Tour…") {
                    model.tourRequested = true
                    AppDelegate.openDashboard()
                }
                Button("Help & Assistant") {
                    model.dashboardPane = .help
                    AppDelegate.openDashboard()
                }
                Button("Report a Problem…") {
                    model.reportRequested = true
                    model.dashboardPane = .about
                    AppDelegate.openDashboard()
                }
            }
        }
    }
}

/// Everything each window reads from the environment, in one place.
private struct AppEnvironment: ViewModifier {
    let model: AppModel
    let updater: UpdaterModel
    let keepAwake: KeepAwakeModel
    let automation: AutomationModel
    let network: NetworkMonitor
    let remote: RemoteAccessModel
    let powerAuth: PowerAuthorization
    let powerSettings: PowerSettingsModel
    let powerHelper: PowerHelperClient
    let bluetooth: BluetoothGATTReader
    let colorScheme: ColorScheme?

    func body(content: Content) -> some View {
        content
            .environment(model)
            .environment(updater)
            .environment(keepAwake)
            .environment(automation)
            .environment(network)
            .environment(remote)
            .environment(powerAuth)
            .environment(powerSettings)
            .environment(powerHelper)
            .environment(bluetooth)
            .preferredColorScheme(colorScheme)
    }
}
