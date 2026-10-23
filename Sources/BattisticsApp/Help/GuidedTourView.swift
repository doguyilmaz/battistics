import SwiftUI

struct GuidedTourView: View {
    @Environment(AppModel.self) private var model
    @Binding var step: TourStep
    @FocusState private var nextFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Quick Tour", systemImage: "sparkle.magnifyingglass")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Step \(step.rawValue + 1) of \(TourStep.allCases.count)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Text(step.title).font(.headline).accessibilityAddTraits(.isHeader)
            Text(step.detail).font(.callout).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button("Skip Tour") { finish() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("tour.skip")
                Spacer()
                Button("Back") { move(-1) }.disabled(step == .overview)
                    .accessibilityIdentifier("tour.back")
                Button(step == .help ? String(localized: "Done") : String(localized: "Next")) {
                    if step == .help { finish() } else { move(1) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .focused($nextFocused)
                .accessibilityIdentifier("tour.next")
            }
        }
        .padding(16)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.15)) }
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tour.card")
        .accessibilityAddTraits(.isModal)
        .onAppear { nextFocused = true }
        .onChange(of: step) { nextFocused = true }
    }

    private func move(_ delta: Int) {
        guard let next = TourStep(rawValue: step.rawValue + delta) else { return }
        step = next
        model.dashboardPane = next.pane
    }

    private func finish() {
        model.tourRequested = false
    }
}
