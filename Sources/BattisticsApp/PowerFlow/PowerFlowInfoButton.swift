import SwiftUI

struct PowerFlowInfoButton: View {
    @Environment(AppModel.self) private var model
    @State private var showingInfo = false

    var body: some View {
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
                        Text("Adapter capacity reported by macOS: \(watts) W")
                    }
                    if let updated = model.snapshot?.powerFlow?.registryUpdatedAt {
                        Text("Registry updated: \(updated, format: .dateTime.hour().minute().second())")
                    } else {
                        Text("Registry update time unavailable")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if model.snapshot?.powerFlow?.hasInconsistentReadings == true {
                    Label("Conflicting source readings are hidden.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Divider()
                Text("Shows power reported at the Mac’s input, system and battery. Input is not the adapter’s rated capacity or power measured at the wall socket.")
                Text("Uses AppleSmartBattery power telemetry, which is not a documented public data contract. Availability and behavior vary by Mac and macOS version.")
                Text("Readings can update slowly and at different times. They may not add up exactly. Battery arrows are hidden when direction is uncertain. Negative battery watts mean reported discharge; positive means reported charging. Missing or conflicting readings appear as a dash, never an assumed zero.")
                Text("The registry update time is not a confirmed hardware sample time. Re-reading cached values does not make them new; a reported zero does not prove zero instantaneous flow. This preview uses existing battery sampling and adds no background polling loop.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(width: 340, alignment: .leading)
        }
    }
}
