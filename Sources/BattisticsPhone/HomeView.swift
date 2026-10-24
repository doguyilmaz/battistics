import BattisticsRemote
import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(MacStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if let mac = store.selected {
                    MacDashboard(mac: mac, showingSettings: $showingSettings)
                        .id(mac.id)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98)),
                            removal: .opacity
                        ))
                } else {
                    SetupIntro()
                }
            }
            .animation(.spring(duration: 0.35, bounce: 0.12), value: store.selected?.id)
            .navigationTitle(store.selected?.name ?? String(localized: "Battistics"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if let mac = store.selected {
                        MacHeaderPicker(selected: mac, showingSettings: $showingSettings)
                    } else {
                        Text("Battistics").font(.headline)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Label("Devices & Settings", systemImage: store.macs.count > 1 ? "laptopcomputer.and.iphone" : "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await store.refreshAll()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }
}

private struct MacHeaderPicker: View {
    @Environment(MacStore.self) private var store
    let selected: MacStore.Mac
    @Binding var showingSettings: Bool

    var body: some View {
        let reading = store.reading(for: selected)
        let isHotspot = reading?.status?.network == .hotspot && reading?.reachable == true
        Menu {
            Section("Your Macs") {
                ForEach(store.macs) { mac in
                    Button {
                        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                            store.selectedID = mac.id
                        }
                    } label: {
                        HStack {
                            Text(mac.name)
                            if let pct = store.reading(for: mac)?.status?.battery?.percent {
                                Text("\(pct)%")
                            }
                            if mac.id == selected.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Divider()
            Button {
                showingSettings = true
            } label: {
                Label("All Devices & Settings…", systemImage: "laptopcomputer.and.iphone")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isHotspot ? "personalhotspot" : "laptopcomputer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isHotspot ? PowerPalette.hotspot : Color.accentColor)
                Text(selected.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if store.macs.count > 1 {
                    Text("\(store.macs.count)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        }
    }
}

struct MacDashboard: View {
    @Environment(MacStore.self) private var store
    let mac: MacStore.Mac
    @Binding var showingSettings: Bool
    @State private var message: String?

    var body: some View {
        let reading = store.reading(for: mac)
        let status = reading?.status
        let reachable = reading?.reachable == true

        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if reachable, let status {
                    AmbientEnergyBackdrop(status: status)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                ScrollView {
                    VStack(spacing: 12) {
                        StatusLine(reading: reading, refreshing: store.refreshing)

                        if let status {
                            BatteryCard(status: status)
                                .opacity(reachable ? 1 : 0.65)

                            KeepAwakeCard(mac: mac, status: status, enabled: reachable, message: $message)
                                .opacity(reachable ? 1 : 0.65)

                            ConditionsGrid(status: status)
                                .opacity(reachable ? 1 : 0.65)

                            Spacer(minLength: 0)

                            PocketModeDock(
                                mac: mac,
                                reading: reading,
                                status: status,
                                message: $message
                            )
                        } else if reading == nil {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                    .frame(minHeight: max(0, proxy.size.height), alignment: .top)
                    .animation(.spring(duration: 0.38, bounce: 0.10), value: reading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .refreshable { await store.refreshAll() }
            }
        }
        .task { await Notifications.requestPermission() }
    }
}

/// Subtle ambient light rays at the top of the dashboard reflecting the Mac's
/// power state (emerald when charging/plugged in, warm amber in Low Power Mode)
/// and a cyan wireless aura when tethered to the iPhone's Personal Hotspot.
/// Intentionally absent when discharging normally on battery.
private struct AmbientEnergyBackdrop: View {
    let status: RemoteStatus

    var body: some View {
        let battery = status.battery
        let isLowPower = battery?.lowPowerMode == true
        let isPowered = battery?.isCharging == true || battery?.onAdapter == true
        let isHotspot = status.network == .hotspot

        ZStack(alignment: .top) {
            if isLowPower {
                EnergyRaysView(color: PowerPalette.lowPower, intensity: 0.22)
            } else if isPowered {
                EnergyRaysView(color: PowerPalette.charging, intensity: battery?.isCharging == true ? 0.22 : 0.14)
            }

            if isHotspot {
                LinearGradient(
                    colors: [PowerPalette.hotspot.opacity(0.20), .clear],
                    startPoint: .top,
                    endPoint: .init(x: 0.5, y: 0.28)
                )
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.6), value: isLowPower)
        .animation(.easeInOut(duration: 0.6), value: isPowered)
        .animation(.easeInOut(duration: 0.6), value: isHotspot)
    }
}

private struct EnergyRaysView: View {
    let color: Color
    let intensity: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                RadialGradient(
                    colors: [color.opacity(intensity), color.opacity(intensity * 0.35), .clear],
                    center: .top,
                    startRadius: 10,
                    endRadius: geo.size.width * 0.95
                )
                HStack(spacing: geo.size.width * 0.08) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(intensity * 0.85), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 28, height: index.isMultiple(of: 2) ? 180 : 130)
                            .rotationEffect(.degrees(Double(index - 2) * 11), anchor: .top)
                            .blur(radius: 16)
                    }
                }
            }
        }
        .frame(height: 240)
    }
}

private struct StatusLine: View {
    let reading: MacStore.Reading?
    let refreshing: Bool

    var body: some View {
        let isHotspot = reading?.reachable == true && reading?.status?.network == .hotspot
        HStack(spacing: 6) {
            Circle()
                .fill(reading?.reachable == true ? (isHotspot ? PowerPalette.hotspot : Color.green) : Color.orange)
                .frame(width: 7, height: 7)
            if let lastSeen = reading?.lastSeen {
                TimelineView(.periodic(from: .now, by: 15)) { _ in
                    Text(reading?.reachable == true
                         ? String(localized: "Updated \(lastSeen.formatted(.relative(presentation: .named)))")
                         : String(localized: "Last seen \(lastSeen.formatted(.relative(presentation: .named)))"))
                }
            } else {
                Text("Connecting…")
            }
            Spacer()
            if let battery = reading?.status?.battery, battery.lowPowerMode == true {
                Label("Low Power", systemImage: "leaf.fill")
                    .foregroundStyle(PowerPalette.lowPower)
                    .fontWeight(.semibold)
            } else if isHotspot {
                Label("Hotspot Paired", systemImage: "personalhotspot")
                    .foregroundStyle(PowerPalette.hotspot)
                    .fontWeight(.semibold)
            } else if reading?.status?.battery?.isCharging == true {
                Label("Charging", systemImage: "bolt.fill")
                    .foregroundStyle(PowerPalette.charging)
                    .fontWeight(.semibold)
            }
            if refreshing { ProgressView().controlSize(.mini) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(height: 18)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

enum HotspotOpener {
    static func open(using openURL: OpenURLAction) {
        if let url = URL(string: "App-Prefs:root=INTERNET_TETHERING"), UIApplication.shared.canOpenURL(url) {
            openURL(url)
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

extension View {
    func card(borderColor: Color? = nil) -> some View {
        padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(borderColor ?? Color.clear, lineWidth: borderColor == nil ? 0 : 1.2)
            )
    }
}
