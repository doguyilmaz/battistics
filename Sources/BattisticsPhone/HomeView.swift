import BattisticsRemote
import SwiftUI

struct HomeView: View {
    @Environment(MacStore.self) private var store
    @Environment(LocalPhoneMonitor.self) private var phone
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false
    @State private var showingSetup = false
    @State private var showingDetails = false

    var body: some View {
        let mac = store.isLocalPhoneSelected ? nil : store.selected
        NavigationStack {
            Group {
                if store.isLocalPhoneSelected {
                    PhoneDashboard()
                } else if let mac {
                    MacDashboard(mac: mac).id(mac.id)
                } else {
                    SetupGuide()
                }
            }
            .transition(.opacity)
            .animation(.snappy, value: store.selectedID)
            .navigationTitle(store.isLocalPhoneSelected ? phone.pickerName : (mac?.name ?? String(localized: "Battistics Remote")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu { deviceMenu }
            .toolbar {
                if store.isLocalPhoneSelected || mac?.status(in: store) != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showingDetails = true } label: { Label("Details", systemImage: "info.circle") }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                }
            }
            .navigationDestination(isPresented: $showingDetails) {
                if store.isLocalPhoneSelected {
                    PhoneDetailsView()
                } else if let mac, let status = mac.status(in: store) {
                    MacDetailsView(mac: mac, status: status)
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingSetup) {
                NavigationStack {
                    SetupGuide()
                        .navigationTitle("Set Up a Mac")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSetup = false } }
                        }
                }
                .softScrollEdge()
            }
        }
        .softScrollEdge()
        .task(id: scenePhase == .active) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await store.refreshAll()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    @ViewBuilder
    private var deviceMenu: some View {
        let selection = Binding(
            get: { store.isLocalPhoneSelected ? MacStore.localPhoneID : store.selected?.id },
            set: { store.selectedID = $0 })
        Picker("Device", selection: selection) {
            ForEach(store.macs) { mac in
                let reading = store.reading(for: mac)
                deviceRow(mac.name, detail: reading?.reachable == true
                          ? reading?.status?.battery.map { $0.percent.percentText }
                          : String(localized: "Offline"),
                          symbol: "laptopcomputer")
                    .tag(Optional(mac.id))
            }
            deviceRow(phone.pickerName, detail: phone.percent.map { $0.percentText }, symbol: "iphone")
                .tag(Optional(MacStore.localPhoneID))
        }
        .pickerStyle(.inline)
        Button {
            showingSetup = true
        } label: {
            Label("Set Up a Mac", systemImage: "plus")
        }
    }

    private func deviceRow(_ name: String, detail: String?, symbol: String) -> some View {
        Label {
            Text(name)
            if let detail { Text(detail) }
        } icon: {
            Image(systemName: symbol)
        }
    }
}

private extension MacStore.Mac {
    @MainActor
    func status(in store: MacStore) -> RemoteStatus? { store.reading(for: self)?.status }
}
