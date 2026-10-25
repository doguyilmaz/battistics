import BattisticsCore
import SwiftUI

enum DashboardPane: String, CaseIterable, Identifiable {
    case overview
    case history
    case details
    case peripherals
    case energy
    case system
    case power
    case phone
    case general
    case appearance
    case notifications
    case data
    case developer
    case about
    case help

    var id: String { rawValue }

    // Not in the sidebar; kept for battistics://dashboard/details.
    static let batteryPanes: [DashboardPane] = [.overview, .history, .energy, .peripherals]
    static let controlPanes: [DashboardPane] = [.system, .power, .phone]
    static let settingsPanes: [DashboardPane] = [.general, .appearance, .notifications, .data]
    static let developerPanes: [DashboardPane] = [.developer]
    static let helpPanes: [DashboardPane] = [.help, .about]

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .history: String(localized: "History")
        case .details: String(localized: "Details")
        case .peripherals: String(localized: "Peripherals")
        case .energy: String(localized: "Energy")
        // Raw values are persisted and used in links: never rename them.
        case .system: String(localized: "Keep Awake")
        case .power: String(localized: "Power")
        case .phone: String(localized: "iPhone")
        case .general: String(localized: "General")
        case .appearance: String(localized: "Menu Bar")
        case .notifications: String(localized: "Notifications")
        case .data: String(localized: "Data")
        case .developer: String(localized: "Automation")
        case .about: String(localized: "About")
        case .help: String(localized: "Help & Assistant")
        }
    }

    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .history: "chart.xyaxis.line"
        case .details: "list.bullet.rectangle"
        case .peripherals: "keyboard"
        case .energy: "bolt.circle"
        case .system: "cup.and.saucer"
        case .power: "bolt.batteryblock"
        case .phone: "iphone"
        case .general: "gearshape"
        case .appearance: "menubar.rectangle"
        case .notifications: "bell.badge"
        case .data: "internaldrive"
        case .developer: "terminal"
        case .about: "info.circle"
        case .help: "questionmark.circle"
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
    @State private var tourStep = TourStep.overview
    @State private var tourCardHeight: CGFloat = 0

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
                    .allowsHitTesting(!model.tourRequested)
                    .disabled(model.tourRequested)
                    .accessibilityHidden(model.tourRequested)
            }
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .allowsHitTesting(!model.tourRequested)
                .disabled(model.tourRequested)
                .accessibilityHidden(model.tourRequested)
        }
        .frame(width: 860, height: 620)
        .environment(\.tourStep, model.tourRequested ? tourStep : nil)
        .overlayPreferenceValue(TourTargetPreference.self) { anchors in
            if model.tourRequested {
                GeometryReader { geometry in
                    let available = CGRect(x: 0, y: 0, width: geometry.size.width,
                                           height: max(0, geometry.size.height - tourCardHeight - 32))
                    let focus = anchors[tourStep].map { geometry[$0].insetBy(dx: -6, dy: -6).intersection(available) }
                    ZStack(alignment: .bottom) {
                        TourSpotlight(focus: focus.flatMap { $0.isNull ? nil : $0 })
                            .allowsHitTesting(false)
                        GuidedTourView(step: $tourStep)
                            .frame(maxWidth: 620)
                            .background {
                                GeometryReader { card in
                                    Color.clear.onChange(of: card.size.height, initial: true) {
                                        tourCardHeight = card.size.height
                                    }
                                }
                            }
                            .padding(16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
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
                .disabled(model.tourRequested)
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
                    .disabled(model.tourRequested)
                }
            }
        }
        .navigationTitle(model.dashboardPane.title)
        .background(WindowLevelConfigurator(keepOnTop: keepOnTop))
        .background(WindowVisibilityReader(isVisible: $windowVisible))
        .onChange(of: windowVisible) {
            if windowVisible && !UserDefaults.standard.bool(forKey: Prefs.hasSeenTour) {
                model.tourRequested = true
            }
        }
        .onChange(of: model.tourRequested, initial: true) { wasRequested, _ in
            if wasRequested, !model.tourRequested {
                UserDefaults.standard.set(true, forKey: Prefs.hasSeenTour)
            }
            if model.tourRequested {
                sidebarVisible = true
                showingDetails = false
                tourStep = .overview
                model.dashboardPane = .overview
            }
        }
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
            if model.tourRequested, model.dashboardPane != tourStep.pane { model.tourRequested = false }
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
            Section("Developer") { rows(DashboardPane.developerPanes) }
            Section("Help") { rows(DashboardPane.helpPanes) }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .frame(width: 180)
        // No ignoresSafeArea: the line would cross the toolbar title.
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
        case .system: KeepAwakePane()
        case .power: PowerPane()
        case .phone: RemotePane()
        case .general: GeneralSettings()
        case .appearance: AppearanceSettings()
        case .notifications: NotificationSettings()
        case .data: HistorySettings()
        case .developer: DeveloperPane()
        case .about: AboutSettings()
        case .help: HelpPane()
        }
    }
}
