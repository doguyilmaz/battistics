import SwiftUI

/// Shown until a Mac on this Apple ID shares itself.
struct SetupIntro: View {
    @Environment(MacStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "laptopcomputer.and.iphone")
                        .font(.system(size: 44)).foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Your Mac, from your pocket")
                        .font(.title2.weight(.semibold))
                    Text("See whether your Mac is awake, online and how long its battery lasts, and start or stop Keep Awake, even with the lid closed in a bag.")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Step(number: 1, text: String(localized: "On the Mac, open Battistics › iPhone and turn on Show this Mac in Battistics Remote."))
                    Step(number: 2, text: String(localized: "Use the same Apple ID with iCloud on this iPhone and on the Mac. There is nothing to pair."))
                }
                if let problem = store.problem {
                    Label(problem, systemImage: "exclamationmark.icloud")
                        .font(.footnote).foregroundStyle(.orange)
                }
                Button {
                    Task { await store.refreshAll() }
                } label: {
                    HStack {
                        if store.refreshing { ProgressView() }
                        Text("Look for my Mac")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.refreshing)
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private struct Step: View {
        let number: Int
        let text: String
        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(number)")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor, in: Circle())
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
