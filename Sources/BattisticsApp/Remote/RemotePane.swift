import AppKit
import BattisticsRemote
import SwiftUI

struct RemotePane: View {
    @Environment(RemoteAccessModel.self) private var remote
    @Environment(NetworkMonitor.self) private var network

    var body: some View {
        @Bindable var remote = remote
        Form {
            Section {
                Toggle("Show this Mac in Battistics Remote", isOn: $remote.enabled)
                    .disabled(!remote.isAvailable)
                Text("Sharing uses your private iCloud. Allow Bluetooth and Local Network on both devices to add nearby connections.")
                    .font(.caption).foregroundStyle(.secondary)
                if !remote.isAvailable {
                    Label("This copy of Battistics is not signed for iCloud.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else if remote.enabled {
                    if let problem = remote.problem {
                        Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    } else if let published = remote.lastPublished {
                        Label("Shared \(published, style: .relative) ago", systemImage: "checkmark.icloud")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Connecting to iCloud…", systemImage: "icloud")
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Allow closed-lid sessions from iPhone", isOn: $remote.closedLidAllowed)
                }
                RemoteAppStoreRow()
            } header: {
                InfoHeader("Battistics Remote",
                           info: "Your iPhone sees battery, connection and Keep Awake, and can start or stop it. Use the same Apple Account for private iCloud sharing. Nearby devices also exchange encrypted updates and controls over Bluetooth or the local network.",
                           "Allowing closed-lid sessions sets up the power helper they need. A closed-lid session from iPhone always stops at 10% battery and under high thermal pressure.")
            }

            if remote.enabled {
                Section("Nearby Connections") {
                    NearbyAccessView(bluetooth: remote.bluetoothState, localNetwork: remote.localNetworkState)
                }
            }

            Section {
                LabeledContent("Connection") {
                    if let ssid = network.ssid {
                        Text("\(network.state.label) · \(ssid)")
                    } else {
                        Text(network.state.label)
                    }
                }
                if !network.canReadSSID && (network.state == .wifi || network.state == .hotspot) {
                    HStack {
                        Text("Allow Location access so Battistics Remote can display your Wi‑Fi or Personal Hotspot name.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Show Network Name") {
                            network.requestSSIDPermission()
                        }
                        .controlSize(.small)
                    }
                }
                Button("Open Wi‑Fi Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
                }
            } header: {
                InfoHeader("Stay online with the lid closed", info: "With no known Wi‑Fi nearby, this Mac can join your iPhone’s hotspot by itself. In Wi‑Fi settings, set Ask to join hotspots to Automatic. Keep Awake keeps the Mac, and so the connection, awake.")
            }
        }
        .formStyle(.grouped)
        .onAppear { remote.refreshNearbyAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            remote.refreshNearbyAccess()
        }
    }
}

extension RemoteStatus.Network {
    var label: String {
        switch self {
        case .wifi: String(localized: "Wi‑Fi")
        case .hotspot: String(localized: "Phone hotspot")
        case .wired: String(localized: "Ethernet")
        case .other: String(localized: "Connected")
        case .offline: String(localized: "Offline")
        }
    }
}
