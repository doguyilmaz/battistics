import BattisticsRemote
import SwiftUI

struct BatteryCard: View {
    @Environment(MacStore.self) private var store
    let mac: MacStore.Mac
    let status: RemoteStatus
    let reachable: Bool
    @Binding var message: String?

    var body: some View {
        if let battery = status.battery {
            let tint = reachable ? PowerPalette.batteryTint(battery) : .secondary
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    BatteryGauge(percent: battery.percent, symbol: battery.symbol, tint: tint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(reachable ? battery.headline : String(localized: "Last reported"))
                            .font(.headline)
                        Text(subtitle(battery))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 4)
                    powerMenu(battery)
                }

                HStack(spacing: 8) {
                    MetricPill(label: String(localized: "Power"),
                               value: battery.flowText ?? "0 W",
                               symbol: "bolt.fill",
                               tint: battery.isCharging ? PowerPalette.charging : .accentColor)
                    MetricPill(label: battery.cycleCount.map { String(localized: "\($0) cycles") } ?? String(localized: "Health"),
                               value: battery.healthPercent.map { $0.percentText } ?? "–",
                               symbol: "heart.fill",
                               tint: (battery.healthPercent ?? 100) < 80 ? .orange : .accentColor)
                    MetricPill(label: status.thermal.label,
                               value: battery.temperatureText ?? "–",
                               symbol: "thermometer.medium",
                               tint: status.thermal == .nominal || status.thermal == .fair ? .accentColor : status.thermal.tint)
                }

                if let history = status.chargeHistory, history.count > 1 {
                    ChargeSparkline(points: history, tint: tint)
                }
            }
            .card(border: reachable && (battery.isCharging || battery.lowPowerMode == true) ? tint.opacity(0.35) : nil)
        } else {
            Label("This Mac has no battery", systemImage: "powerplug")
                .card()
        }
    }

    private func subtitle(_ battery: RemoteStatus.Battery) -> String {
        if !reachable {
            return String(localized: "\(battery.percent)% · \(status.readAt.formatted(.relative(presentation: .named)))")
        }
        if let time = battery.timeText { return time }
        if battery.onAdapter {
            return battery.percent >= 100 ? String(localized: "Fully charged") : String(localized: "Not charging")
        }
        return battery.headline
    }

    private func powerMenu(_ battery: RemoteStatus.Battery) -> some View {
        let lowPower = battery.lowPowerMode == true
        return Menu {
            Section("Low Power Mode on the Mac") {
                Picker("Low Power Mode", selection: Binding(
                    get: { battery.lowPowerPolicy },
                    set: { policy in if let policy { run { await store.setLowPower(mac, policy: policy) } } }
                )) {
                    ForEach(RemoteStatus.LowPowerPolicy.allCases, id: \.self) { policy in
                        Label(policy.label, systemImage: policy.symbol).tag(Optional(policy))
                    }
                }
            }
            Button {
                run { await store.sleepDisplay(mac) }
            } label: {
                Label("Turn Off Mac Display", systemImage: "moon.zzz.fill")
            }
        } label: {
            Label(lowPower ? String(localized: "Low Power") : (battery.lowPowerPolicy?.compactBadge ?? String(localized: "Power")),
                  systemImage: lowPower ? "leaf.fill" : (battery.lowPowerPolicy?.symbol ?? "bolt.circle"))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(lowPower ? PowerPalette.lowPower.opacity(0.18) : Color(.tertiarySystemFill), in: .capsule)
                .foregroundStyle(lowPower ? PowerPalette.lowPower : .primary)
                .fixedSize()
        }
        .disabled(!reachable || store.pending.contains(mac.id))
        .accessibilityLabel(Text("Mac power settings"))
    }

    private func run(_ action: @escaping () async -> String?) {
        Task {
            message = nil
            message = await action()
        }
    }
}
