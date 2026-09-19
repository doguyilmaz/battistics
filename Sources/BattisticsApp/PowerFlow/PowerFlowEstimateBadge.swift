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

    private var formula: String {
        kind == .battery
            ? String(localized: "Battery = Voltage × Current")
            : String(localized: "System = Input - Battery")
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
        .accessibilityHint("\(formula). \(explanation)")
        .help("\(formula)\n\n\(explanation)")
        .popover(isPresented: $showingExplanation) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                Text(formula)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 290, alignment: .leading)
        }
    }
}
