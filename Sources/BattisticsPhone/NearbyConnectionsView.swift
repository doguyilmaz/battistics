import BattisticsRemote
import SwiftUI

struct NearbyConnectionsView: View {
    @Environment(MacStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section("App Versions") {
                LabeledContent("This iPhone", value: RemoteAppInfo.current(minimumPeerVersion: RemoteCompatibility.minimumMac)?.displayVersion ?? "—")
                ForEach(store.macs) { mac in
                    if let status = store.readings[mac.id]?.status {
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent(mac.name, value: status.appInfo?.displayVersion ?? String(localized: "Version not shared"))
                            Text(RemoteCompatibility.message(peer: status.appInfo, name: mac.name, appName: "Battistics", localAppName: "Battistics Remote",
                                local: .current(minimumPeerVersion: RemoteCompatibility.minimumMac), minimum: RemoteCompatibility.minimumMac))
                                .font(.footnote).foregroundStyle(.secondary)
                            if status.nearbyProtocol == nil {
                                Text("This Mac has not made nearby connections available yet. Check its app version and iPhone sharing settings. iCloud remains available.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Text("Last reported \(status.readAt, style: .relative) ago")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if store.macs.isEmpty {
                    Text("Connect a Mac through iCloud to check its app version.")
                }
            }
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
                if store.bluetoothState == .notDetermined {
                    Text("Permission has not been requested. It will be requested when a compatible Mac finishes nearby setup through iCloud.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if store.bluetoothState == .denied || store.localNetworkState == .denied {
                    Button("Open App Settings") {
                        openURL(URL(string: UIApplication.openSettingsURLString)!)
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Nearby connections require Battistics 1.6.0 or later on the Mac and Battistics Remote 1.1.0 or later on iPhone. If a requested permission was denied, change it in Settings. iCloud continues when nearby connections are unavailable.")
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
