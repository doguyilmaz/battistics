import SwiftUI

struct PowerFlowSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let flow = PowerFlowPresentation(snapshot: model.snapshot, lastReadAt: model.powerFlowReadAt)
        HStack(spacing: 4) {
            Text("In \(flow.watts(flow.telemetry?.inputWatts))")
            Text("·").foregroundStyle(.tertiary)
            Text("Mac \(flow.watts(flow.telemetry?.systemLoadWatts))")
            Text("·").foregroundStyle(.tertiary)
            if let arrow = flow.batteryArrow {
                Image(systemName: arrow).accessibilityLabel(flow.batteryLabel)
            }
            Text("Bat \(flow.watts(flow.telemetry?.batteryPowerWatts, signed: true))")
            Spacer(minLength: 0)
            PowerFlowInfoButton()
        }
        .font(.system(size: 10))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(height: 20)
        .accessibilityElement(children: .contain)
        .help("Experimental Power Flow. Use the information button for sources and limitations.")
    }
}
