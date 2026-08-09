import SwiftUI

enum DashboardPane: String, CaseIterable, Identifiable {
    case overview
    case history
    case details
    case peripherals
    case energy
    case general
    case appearance
    case notifications
    case data
    case about

    var id: String { rawValue }

    static let monitorPanes: [DashboardPane] = [.overview, .history, .details, .peripherals, .energy]
    static let settingsPanes: [DashboardPane] = [.general, .appearance, .notifications, .data, .about]

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .history: String(localized: "History")
        case .details: String(localized: "Details")
        case .peripherals: String(localized: "Peripherals")
        case .energy: String(localized: "Energy")
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
    @AppStorage(Prefs.keepDashboardOnTop) private var keepOnTop = false
    @State private var sidebarVisible = true

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
        .background(SidebarBackground().ignoresSafeArea())
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
        case .general: GeneralSettings()
        case .appearance: AppearanceSettings()
        case .notifications: NotificationSettings()
        case .data: HistorySettings()
        case .about: AboutSettings()
        }
    }
}

/// The translucent material NavigationSplitView gives its sidebar, applied
/// to the custom one.
private struct SidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
