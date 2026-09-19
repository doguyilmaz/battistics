import SwiftUI

struct PowerFlowInfoButton: View {
    @Environment(AppModel.self) private var model
    @State private var showingInfo = false

    var body: some View {
        let flow = PowerFlowPresentation(snapshot: model.snapshot, lastReadAt: model.powerFlowReadAt)
        Button {
            showingInfo.toggle()
        } label: {
            Label("About Power Flow", systemImage: "info.circle")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("About Power Flow")
        .popover(isPresented: $showingInfo, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Power Flow · Experimental")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 4) {
                    if let watts = model.snapshot?.adapter?.watts {
                        Text("Adapter capacity: \(watts) W")
                    }
                    if let updated = model.snapshot?.powerFlow?.registryUpdatedAt {
                        Text("System updated: \(updated, format: .dateTime.hour().minute().second())")
                    } else {
                        Text("Update time unavailable")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if flow.batteryIsEstimated || flow.systemIsEstimated {
                    Label {
                        Text("Yellow warnings mark calculated values.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    }
                    .font(.caption)
                } else if flow.telemetry?.hasInconsistentReadings == true {
                    Label("Some readings are unavailable.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Divider()
                Text("Input is power entering your Mac, not the adapter’s maximum wattage or power at the wall.")
                Text("Battery: + means charging, - means discharging. Open a yellow warning for calculation details.")
                Text("These experimental macOS readings can be delayed or unavailable. Different update times and power losses make the split approximate.")
                Text("The update time does not confirm when each reading was measured.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(width: 340, alignment: .leading)
        }
    }
}
