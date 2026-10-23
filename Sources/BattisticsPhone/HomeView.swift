import BattisticsRemote
import SwiftUI

struct HomeView: View {
    @Environment(MacStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false
    @State private var showingPairing = false

    var body: some View {
        NavigationStack {
            Group {
                if let mac = store.selected {
                    MacDashboard(mac: mac)
                } else {
                    PairingIntro()
                }
            }
            .navigationTitle(store.selected?.name ?? String(localized: "Battistics"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if store.macs.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker("Mac", selection: Binding(
                                get: { store.selected?.id }, set: { store.selectedID = $0 })) {
                                ForEach(store.macs) { Text($0.name).tag(Optional($0.id)) }
                            }
                        } label: {
                            Label("Switch Mac", systemImage: "laptopcomputer.and.arrow.down")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
        .task(id: scenePhase == .active ? store.selected?.id : nil) {
            guard scenePhase == .active, let mac = store.selected else { return }
            while !Task.isCancelled {
                await store.refresh(mac)
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }
}

struct MacDashboard: View {
    @Environment(MacStore.self) private var store
    let mac: RemotePairing
    @State private var message: String?

    var body: some View {
        let reading = store.reading(for: mac)
        ScrollView {
            VStack(spacing: 16) {
                StatusLine(reading: reading, refreshing: store.refreshing.contains(mac.id))
                if let reading, !reading.reachable {
                    UnreachableCard(reading: reading)
                }
                if let status = reading?.status {
                    Group {
                        BatteryCard(status: status)
                        KeepAwakeCard(mac: mac, status: status, enabled: reading?.reachable == true,
                                      message: $message)
                        ConditionsGrid(status: status)
                    }
                    .opacity(reading?.reachable == true ? 1 : 0.55)
                } else if reading == nil {
                    ProgressView().padding(.top, 60)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .animation(.smooth, value: reading)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await store.refresh(mac) }
    }
}

private struct StatusLine: View {
    let reading: MacStore.Reading?
    let refreshing: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(reading?.reachable == true ? Color.green : Color.secondary)
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
            if refreshing { ProgressView().controlSize(.mini) }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

private struct UnreachableCard: View {
    let reading: MacStore.Reading

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Can’t reach your Mac", systemImage: "antenna.radiowaves.left.and.right.slash")
                .font(.headline)
            Text(reading.status?.session != nil
                 ? "Keep Awake was running when the Mac last answered."
                 : "It may be asleep or offline.")
                .font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Tip(symbol: "lock.shield", text: String(localized: "Check that Tailscale is on, here and on the Mac."))
                Tip(symbol: "personalhotspot", text: String(localized: "No Wi‑Fi where the Mac is? Open Settings › Personal Hotspot and turn on Allow Others to Join; a Mac set to join hotspots automatically connects by itself."))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private struct Tip: View {
        let symbol: String
        let text: String
        var body: some View {
            Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: {
                Image(systemName: symbol).foregroundStyle(.tint)
            }
            .font(.footnote)
        }
    }
}

extension View {
    func card() -> some View {
        padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
