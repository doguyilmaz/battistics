import SwiftUI

enum DashboardPane: String, CaseIterable, Identifiable {
    case overview
    case history
    case details
    case peripherals
    case energy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .history: String(localized: "History")
        case .details: String(localized: "Details")
        case .peripherals: String(localized: "Peripherals")
        case .energy: String(localized: "Energy")
        }
    }

    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .history: "chart.xyaxis.line"
        case .details: "list.bullet.rectangle"
        case .peripherals: "keyboard"
        case .energy: "bolt.circle"
        }
    }
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.keepDashboardOnTop) private var keepOnTop = false
    @State private var selection: DashboardPane? = .overview
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(DashboardPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.icon).tag(pane)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 860, height: 545)
        .background(WindowLevelConfigurator(keepOnTop: keepOnTop))
        .onAppear {
            // The split view otherwise restores a previously collapsed
            // sidebar; the dashboard always opens with it visible.
            columnVisibility = .all
        }
        .task {
            while !Task.isCancelled {
                model.refreshSensors()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    @ViewBuilder private var detailView: some View {
        switch selection ?? .overview {
        case .overview: OverviewPane()
        case .history: HistoryPane()
        case .details: DetailsPane()
        case .peripherals: PeripheralsPane()
        case .energy: EnergyPane()
        }
    }
}

