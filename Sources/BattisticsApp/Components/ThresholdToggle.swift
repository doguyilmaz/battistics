import BattisticsCore
import SwiftUI

/// A switch with its level beside it, so an alert and its threshold share
/// one row instead of growing a slider row when turned on.
struct ThresholdToggle: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let text: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                if isOn {
                    Text(text(value))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Stepper("", value: $value, in: range, step: step)
                        .labelsHidden()
                        .accessibilityValue(text(value))
                }
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }
}

extension ThresholdToggle {
    init(_ title: LocalizedStringKey, isOn: Binding<Bool>, percent: Binding<Int>,
         range: ClosedRange<Int>, step: Int = 5) {
        self.init(title: title, isOn: isOn,
                  value: Binding(get: { Double(percent.wrappedValue) }, set: { percent.wrappedValue = Int($0) }),
                  range: Double(range.lowerBound)...Double(range.upperBound), step: Double(step),
                  text: { Formatting.percent($0) })
    }
}
