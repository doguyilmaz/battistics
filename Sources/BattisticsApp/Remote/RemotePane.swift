import AppKit
import BattisticsRemote
import CoreImage.CIFilterBuiltins
import SwiftUI

struct RemotePane: View {
    @Environment(RemoteAccessModel.self) private var remote
    @Environment(NetworkMonitor.self) private var network

    var body: some View {
        @Bindable var remote = remote
        Form {
            Section {
                Toggle("Allow iPhone access over Tailscale", isOn: $remote.enabled)
                Text("A paired iPhone sees battery, connection and Keep Awake, and can start or stop it. Only paired iPhones on your Tailscale network can connect; nothing is opened to your local network or the internet.")
                    .font(.caption).foregroundStyle(.secondary)
                if remote.enabled {
                    if let address = remote.addresses.sorted().first {
                        Label("Reachable at \(address)", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Tailscale is not connected on this Mac", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Link("Get Tailscale", destination: URL(string: "https://tailscale.com/download")!)
                    }
                    Toggle("Allow closed-lid sessions from iPhone", isOn: $remote.closedLidAllowed)
                    Text("Needs the power helper, set up by starting closed-lid Keep Awake on this Mac once.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if remote.enabled {
                Section("Paired iPhones") {
                    if let invite = remote.invite {
                        PairingInvite(invite: invite)
                    }
                    ForEach(remote.devices.filter { $0.id != remote.invite?.deviceID }) { device in
                        DeviceRow(device: device)
                    }
                    if remote.invite == nil {
                        Button("Pair an iPhone…") { remote.startPairing() }
                            .disabled(remote.addresses.isEmpty)
                    }
                }
            }

            Section("Stay online with the lid closed") {
                LabeledContent("Connection", value: network.state.label)
                Text("With no known Wi‑Fi nearby, this Mac can join your iPhone’s hotspot by itself. In Wi‑Fi settings, set Ask to join hotspots to Automatic. Keep Awake keeps the Mac, and so the connection, awake.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Wi‑Fi Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PairingInvite: View {
    @Environment(RemoteAccessModel.self) private var remote
    let invite: RemoteAccessModel.Invite
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if let image = QRCode.image(for: invite.pairing.url.absoluteString) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 148, height: 148)
                    .padding(8)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Pairing code")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Scan with your iPhone").font(.headline)
                Text("Open the Camera, point it at the code and tap the Battistics Remote link. Tailscale must be on for both devices.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Expires \(invite.expires, style: .relative)")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(copied ? String(localized: "Copied") : String(localized: "Copy Link")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(invite.pairing.url.absoluteString, forType: .string)
                        // Keeps clipboard managers and history from storing the token.
                        NSPasteboard.general.setString("", forType: .init("org.nspasteboard.ConcealedType"))
                        copied = true
                    }
                    Button("Cancel", role: .cancel) { remote.cancelPairing() }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DeviceRow: View {
    @Environment(RemoteAccessModel.self) private var remote
    let device: RemoteAccessModel.Device

    var body: some View {
        HStack {
            Image(systemName: "iphone").foregroundStyle(.tint).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name ?? String(localized: "iPhone"))
                Group {
                    if let lastSeen = device.lastSeen {
                        Text("Last seen \(lastSeen, style: .relative) ago")
                    } else {
                        Text("Not connected yet")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Remove", role: .destructive) { remote.remove(device) }
                .accessibilityLabel(String(localized: "Remove \(device.name ?? String(localized: "iPhone"))"))
        }
    }
}

enum QRCode {
    static func image(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: output.extent.size)
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
