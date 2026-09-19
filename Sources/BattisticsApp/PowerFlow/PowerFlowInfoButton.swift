import SwiftUI

struct PowerFlowInfoButton: View {
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
                Text("Shows power reported at the Mac’s input, system and battery. Input is not the adapter’s rated capacity or power measured at the wall socket.")
                Text("Uses AppleSmartBattery power telemetry, which is not a documented public data contract. Availability and behavior vary by Mac and macOS version.")
                Text("Readings can update slowly and at different times. They may not add up exactly. Battery arrows are hidden when direction is uncertain; missing readings appear as a dash, never an assumed zero.")
                Text("The last successful read does not tell us when the hardware sampled the values. This preview uses existing battery sampling and adds no background polling loop.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(width: 340, alignment: .leading)
        }
    }
}
