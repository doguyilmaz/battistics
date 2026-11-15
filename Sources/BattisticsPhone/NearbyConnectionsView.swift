import BattisticsRemote
import SwiftUI

struct NearbyConnectionsView: View {
    @Environment(MacStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                LabeledContent("Bluetooth", value: store.bluetoothState.label)
                if store.bluetoothState == .restricted {
                    Text("Bluetooth access is restricted by iOS or device management.")
                } else if store.bluetoothState == .poweredOff {
                    Text("Turn on Bluetooth in Settings to connect to a nearby Mac.")
                }
                if store.localNetworkState == .denied {
                    Label("Local Network access denied", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else if store.localNetworkState == .unavailable {
                    Label("Local discovery unavailable", systemImage: "wifi.exclamationmark")
                }
                Button("Open App Settings") {
                    openURL(URL(string: UIApplication.openSettingsURLString)!)
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Allow Bluetooth and Local Network for Battistics Remote in Settings. On the Mac, allow Battistics in System Settings › Privacy & Security. A denied permission can be changed later; iCloud continues when nearby connections are unavailable.")
            }
            Section {
                Label("Bluetooth connects nearby devices, even on different networks.", systemImage: "antenna.radiowaves.left.and.right")
                Label("Local Network connects devices over reachable Wi‑Fi or Ethernet while this app is open.", systemImage: "wifi")
                Label("Your private iCloud connects devices when they are apart. The first setup requires the same Apple Account and an internet connection.", systemImage: "icloud")
            } footer: {
                Text("Background updates depend on iOS and available connections. Bluetooth access does not guarantee continuous Live Activity updates.")
            }
        }
        .navigationTitle("Nearby Connections")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.refreshNearbyAccess() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshNearbyAccess() }
        }
    }
}
