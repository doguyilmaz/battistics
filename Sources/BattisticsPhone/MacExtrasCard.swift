import BattisticsRemote
import SwiftUI

/// Accessory batteries and the apps using the most energy, sampled when asked.
struct MacExtrasCard: View {
    @Environment(MacStore.self) private var store
    let mac: MacStore.Mac
    let status: RemoteStatus
    let reachable: Bool
    @State private var checking = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Accessories & Apps", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Button {
                    check()
                } label: {
                    if checking { ProgressView() } else { Text(status.extras == nil ? "Check" : "Refresh") }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!reachable || checking)
            }

            if let extras = status.extras {
                if extras.accessories.isEmpty {
                    Text("No accessory reports a battery.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(extras.accessories.enumerated()), id: \.offset) { _, accessory in
                        HStack {
                            Text(accessory.detail.map { "\(accessory.name) · \($0)" } ?? accessory.name)
                                .lineLimit(1)
                            Spacer()
                            Text("\(accessory.percent)%")
                                .monospacedDigit()
                                .foregroundStyle(accessory.percent <= 15 ? .orange : .secondary)
                        }
                        .font(.subheadline)
                    }
                }
                if !extras.apps.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Using the most energy")
                            .font(.subheadline.weight(.semibold))
                        Text("Share of the energy used over 3 seconds")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(extras.apps.enumerated()), id: \.offset) { _, app in
                        HStack {
                            Text(app.name).lineLimit(1)
                            Spacer()
                            Text(app.energyShare.map { Int(($0 * 100).rounded()).percentText }
                                 ?? Int(app.cpuPercent.rounded()).percentText + " CPU")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
                Text("Checked \(Ago.text(extras.sampledAt))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("See the battery of the Mac’s keyboard, mouse and headphones, and which apps use the most energy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let failure {
                Label(failure, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .card()
        .animation(.snappy, value: status.extras)
    }

    private func check() {
        checking = true
        failure = nil
        Task {
            failure = await store.inspect(mac)
            checking = false
        }
    }
}
