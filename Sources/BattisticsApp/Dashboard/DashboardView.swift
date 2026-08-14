import BattisticsCore
import SwiftUI

enum DashboardPane: String, CaseIterable, Identifiable {
    case overview
    case history
    case details
    case peripherals
    case energy
    case system
    case general
    case appearance
    case notifications
    case data
    case about

    var id: String { rawValue }

    static let monitorPanes: [DashboardPane] = [.overview, .history, .details, .peripherals, .energy, .system]
    static let settingsPanes: [DashboardPane] = [.general, .appearance, .notifications, .data, .about]

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .history: String(localized: "History")
        case .details: String(localized: "Details")
        case .peripherals: String(localized: "Peripherals")
        case .energy: String(localized: "Energy")
        case .system: String(localized: "System")
        case .general: String(localized: "General")
        case .appearance: String(localized: "Appearance")
        case .notifications: String(localized: "Notifications")
        case .data: String(localized: "Data")
        case .about: String(localized: "About")
        }
    }

    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .history: "chart.xyaxis.line"
        case .details: "list.bullet.rectangle"
        case .peripherals: "keyboard"
        case .energy: "bolt.circle"
        case .system: "switch.2"
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .notifications: "bell.badge"
        case .data: "internaldrive"
        case .about: "info.circle"
        }
    }
}

/// Custom split layout instead of NavigationSplitView: AppKit's sidebar
/// expand animation slides the detail as a frozen layer and reflows it only
/// at the end (the "shift right then jump"). Owning the layout lets SwiftUI
/// interpolate the real frames, so opening reflows as smoothly as closing.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(KeepAwakeModel.self) private var keepAwake
    @AppStorage(Prefs.keepDashboardOnTop) private var keepOnTop = false
    @State private var sidebarVisible = true

    /// Advanced by the dashboard's existing 3s refresh loop.
    private var keepAwakeTitle: String {
        guard let seconds = keepAwake.remaining() else {
            return String(localized: "Awake")
        }
        return Formatting.duration(minutes: Int(seconds / 60))
    }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                sidebar
                    .transition(.move(edge: .leading))
            }
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 860, height: 545)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        sidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle sidebar")
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
            // Top right of the window, not inside a pane: Keep Awake applies
            // to the whole Mac, not to whatever pane happens to be showing,
            // and the toolbar costs the content no vertical space.
            if keepAwake.isActive {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        keepAwake.stop()
                    } label: {
                        Label(keepAwakeTitle, systemImage: "cup.and.saucer.fill")
                            .labelStyle(.titleAndIcon)
                            .monospacedDigit()
                    }
                    .help("Keep Awake is on. Click to turn it off.")
                }
            }
        }
        .navigationTitle(model.dashboardPane.title)
        .background(WindowLevelConfigurator(keepOnTop: keepOnTop))
        .task {
            while !Task.isCancelled {
                model.refreshSensors()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var selectionBinding: Binding<DashboardPane?> {
        Binding(
            get: { model.dashboardPane },
            set: { model.dashboardPane = $0 ?? .overview }
        )
    }

    private var sidebar: some View {
        List(selection: selectionBinding) {
            Section("Monitor") {
                ForEach(DashboardPane.monitorPanes) { pane in
                    Label(pane.title, systemImage: pane.icon).tag(pane)
                }
            }
            Section("Settings") {
                ForEach(DashboardPane.settingsPanes) { pane in
                    Label(pane.title, systemImage: pane.icon).tag(pane)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .frame(width: 180)
        .overlay(alignment: .trailing) {
            Divider().ignoresSafeArea()
        }
    }

    @ViewBuilder private var detailView: some View {
        switch model.dashboardPane {
        case .overview: OverviewPane()
        case .history: HistoryPane()
        case .details: DetailsPane()
        case .peripherals: PeripheralsPane()
        case .energy: EnergyPane()
        case .system: SystemPane()
        case .general: GeneralSettings()
        case .appearance: AppearanceSettings()
        case .notifications: NotificationSettings()
        case .data: HistorySettings()
        case .about: AboutSettings()
        }
    }
}
