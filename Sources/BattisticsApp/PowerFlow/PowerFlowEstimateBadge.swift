import SwiftUI

/// Native hover help, with the same explanation available by click or keyboard.
struct PowerFlowEstimateBadge: View {
    enum Kind {
        case battery
        case system
    }

    var kind: Kind = .battery
    @State private var showingExplanation = false

    private var title: String {
        kind == .battery ? String(localized: "Estimated battery power") : String(localized: "Estimated system power")
    }

    private var explanation: String {
        kind == .battery ? PowerFlowPresentation.batteryEstimateExplanation : PowerFlowPresentation.systemEstimateExplanation
    }

    var body: some View {
        Button {
            showingExplanation.toggle()
        } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(explanation)
        .help(explanation)
        .popover(isPresented: $showingExplanation) {
            Text(explanation)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(width: 290, alignment: .leading)
        }
    }
}
