import AppKit
import BattisticsRemote
import SwiftUI

struct NearbyAccessView: View {
    let bluetooth: NearbyBluetoothState
    let localNetwork: NearbyLocalNetworkState

    var body: some View {
        LabeledContent("Bluetooth", value: bluetooth.label)
        if bluetooth == .restricted {
            Text("Bluetooth access is restricted by macOS or device management. Contact your administrator if this Mac is managed.")
                .font(.caption).foregroundStyle(.secondary)
        } else if bluetooth == .poweredOff {
            Text("Turn on Bluetooth in System Settings to use the nearby Bluetooth connection.")
                .font(.caption).foregroundStyle(.secondary)
        }
        if localNetwork == .denied {
            Label("Local Network access denied", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else if localNetwork == .unavailable {
            Label("Local discovery unavailable", systemImage: "wifi.exclamationmark")
                .foregroundStyle(.secondary)
        }
        Text("Bluetooth works with a nearby iPhone even on different networks. Local Network adds a connection over reachable Wi‑Fi or Ethernet. If access was denied, allow Battistics in Privacy & Security on this Mac and in Settings on the iPhone. iCloud continues when nearby connections are unavailable.")
            .font(.caption).foregroundStyle(.secondary)
        HStack {
            Button("Bluetooth Privacy Settings") { openPrivacy("Privacy_Bluetooth") }
            if #available(macOS 15.0, *) {
                Button("Local Network Privacy Settings") { openPrivacy("Privacy_LocalNetwork") }
            }
        }
        .controlSize(.small)
    }

    private func openPrivacy(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
