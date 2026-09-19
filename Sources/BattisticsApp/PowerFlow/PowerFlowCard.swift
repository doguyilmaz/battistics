import SwiftUI

struct PowerFlowCard: View {
    @Environment(AppModel.self) private var model

    private var reading: PowerFlowPresentation {
        PowerFlowPresentation(snapshot: model.snapshot, lastReadAt: model.powerFlowReadAt)
    }

    var body: some View {
        let flow = reading
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("Power Flow").font(.headline)
                    Text("Experimental")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    PowerFlowInfoButton()
                }
                HStack(spacing: 12) {
                    node("Input", icon: "powerplug", watts: flow.telemetry?.inputWatts,
                         detail: "At the Mac")
                    arrow((flow.telemetry?.inputWatts ?? 0) > 0 ? "arrow.right" : nil)
                    node("System", icon: "laptopcomputer", watts: flow.telemetry?.systemLoadWatts,
                         detail: "Reported load")
                    arrow(flow.batteryArrow)
                    node("Battery", icon: "battery.100", watts: flow.telemetry?.batteryPowerWatts,
                         detail: flow.batteryLabel)
                }
                Text(flow.hasReadings
                     ? "System-reported readings · updates may be delayed"
                     : "Power telemetry is unavailable. Existing battery readings still work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 28, alignment: .leading)
            }
        }
    }

    private func node(_ title: LocalizedStringKey, icon: String, watts: Double?, detail: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.title3).foregroundStyle(.secondary)
            Text(title).font(.caption)
            Text(reading.watts(watts))
                .font(.system(.title3, design: .rounded).weight(.medium))
                .monospacedDigit()
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 84)
    }

    private func arrow(_ symbol: String?) -> some View {
        Image(systemName: symbol ?? "minus")
            .font(.callout)
            .foregroundStyle(symbol == nil ? Color.secondary : Color.green)
            .accessibilityHidden(true)
            .frame(width: 18)
    }
}
