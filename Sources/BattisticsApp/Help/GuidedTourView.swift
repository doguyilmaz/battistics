import SwiftUI

struct GuidedTourView: View {
    @Environment(AppModel.self) private var model
    @State private var step = TourStep.overview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Quick Tour", systemImage: "sparkle.magnifyingglass")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Step \(step.rawValue + 1) of \(TourStep.allCases.count)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Text(step.title).font(.headline)
            Text(step.detail).font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Skip Tour") { finish() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button("Back") { move(-1) }.disabled(step == .overview)
                Button(step == .help ? String(localized: "Done") : String(localized: "Next")) {
                    if step == .help { finish() } else { move(1) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .onAppear { model.dashboardPane = step.pane }
    }

    private func move(_ delta: Int) {
        guard let next = TourStep(rawValue: step.rawValue + delta) else { return }
        step = next
        model.dashboardPane = next.pane
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Prefs.hasSeenTour)
        model.tourRequested = false
    }
}
