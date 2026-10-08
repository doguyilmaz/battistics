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

    // Details is not listed: it opens as a sheet from Overview, which
    // already shows most of it. The case stays for battistics:// links.
    static let batteryPanes: [DashboardPane] = [.overview, .history, .energy, .peripherals]
    static let controlPanes: [DashboardPane] = [.system]
    static let settingsPanes: [DashboardPane] = [.general, .appearance, .notifications, .data]
    static let helpPanes: [DashboardPane] = [.about]

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .history: String(localized: "History")
        case .details: String(localized: "Details")
        case .peripherals: String(localized: "Peripherals")
        case .energy: String(localized: "Energy")
        // Raw values stay "system" and "appearance" so existing links and
        // saved state keep working.
        case .system: String(localized: "Power")
        case .general: String(localized: "General")
        case .appearance: String(localized: "Menu Bar")
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
        case .appearance: "menubar.rectangle"
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
    @State private var windowVisible = false
    @State private var showingDetails = false

    private func keepAwakeTitle(at date: Date) -> String {
        guard let seconds = keepAwake.remaining(at: date) else {
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
                        Group {
                            if windowVisible, let session = keepAwake.session, session.deadline != nil {
                                TimelineView(.periodic(from: session.startedAt, by: 60)) { _ in
                                    Label(keepAwakeTitle(at: Date()), systemImage: "cup.and.saucer.fill")
                                }
                            } else {
                                Label(keepAwakeTitle(at: Date()), systemImage: "cup.and.saucer.fill")
                            }
                        }
                            .labelStyle(.titleAndIcon)
                            .monospacedDigit()
                    }
                    .help("Keep Awake is on. Click to turn it off.")
                }
            }
        }
        .navigationTitle(model.dashboardPane.title)
        .background(WindowLevelConfigurator(keepOnTop: keepOnTop))
        .background(WindowVisibilityReader(isVisible: $windowVisible))
        .task(id: windowVisible) {
            guard windowVisible else { return }
            await model.refreshSensorsWhileVisible(every: .seconds(3))
        }
        .sheet(isPresented: $showingDetails) {
            BatteryDetailsSheet()
        }
        // A battistics://dashboard/details link lands on Overview with the
        // details sheet open.
        .onChange(of: model.dashboardPane, initial: true) {
            switch model.dashboardPane {
            case .details:
                model.dashboardPane = .overview
                showingDetails = true
            case .overview:
                break
            default:
                // The sheet belongs to Overview.
                showingDetails = false
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
            Section("Battery") { rows(DashboardPane.batteryPanes) }
            Section("Controls") { rows(DashboardPane.controlPanes) }
            Section("Settings") { rows(DashboardPane.settingsPanes) }
            Section("Help") { rows(DashboardPane.helpPanes) }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .frame(width: 180)
        // Stops at the toolbar. The toolbar spans the whole window in this
        // layout, so a full-height line ran through its title.
        .overlay(alignment: .trailing) {
            Divider()
        }
    }

    private func rows(_ panes: [DashboardPane]) -> some View {
        ForEach(panes) { pane in
            Label(pane.title, systemImage: pane.icon).tag(pane)
        }
    }

    @ViewBuilder private var detailView: some View {
        switch model.dashboardPane {
        case .overview, .details:
            OverviewPane(isVisible: windowVisible) { showingDetails = true }
        case .history: HistoryPane()
        case .peripherals: PeripheralsPane()
        case .energy: EnergyPane(isVisible: windowVisible)
        case .system: SystemPane()
        case .general: GeneralSettings()
        case .appearance: AppearanceSettings()
        case .notifications: NotificationSettings()
        case .data: HistorySettings()
        case .about: AboutSettings()
        }
    }
}
