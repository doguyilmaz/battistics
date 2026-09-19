import SwiftUI

/// Native hover help, with the same explanation available by click or keyboard.
struct PowerFlowEstimateBadge: View {
    @State private var showingExplanation = false

    var body: some View {
        Button {
            showingExplanation.toggle()
        } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Estimated battery power")
        .accessibilityHint(PowerFlowPresentation.batteryEstimateExplanation)
        .help(PowerFlowPresentation.batteryEstimateExplanation)
        .popover(isPresented: $showingExplanation) {
            Text(PowerFlowPresentation.batteryEstimateExplanation)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(width: 290, alignment: .leading)
        }
    }
}
