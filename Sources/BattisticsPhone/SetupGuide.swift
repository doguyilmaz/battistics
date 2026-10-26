import BattisticsRemote
import SwiftUI

/// How to get a Mac to show up, with what the app can see right now.
struct SetupGuide: View {
    @Environment(MacStore.self) private var store
    @Environment(LocalPhoneMonitor.self) private var phone
    @Environment(\.dismiss) private var dismiss

    private static let download = URL(string: "https://battistics.apps.doguyilmaz.com/#download")!

    var body: some View {
        DashboardPage(refresh: { await store.refreshAll() }) {
            VStack(spacing: 6) {
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .padding(.bottom, 4)
                Text("Your Mac on your iPhone")
                    .font(.title2.weight(.bold))
                Text("See your Mac’s battery and control Keep Awake through your own iCloud.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 12)

            VStack(alignment: .leading, spacing: 14) {
                step(1, "Install Battistics on the Mac", "macOS 14 or later.")
                step(2, "Turn on iPhone access", "In Battistics on the Mac, open iPhone and turn on Show this Mac in Battistics Remote.")
                step(3, "Use the same Apple Account", "This iPhone and the Mac must be signed in to iCloud with the same Apple Account.")
                HStack(spacing: 10) {
                    Link(destination: Self.download) {
                        Label("Get for Mac", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    ShareLink(item: Self.download) {
                        Label("Share Link", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                }
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .card()

            VStack(alignment: .leading, spacing: 10) {
                if let problem = store.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if store.remoteMacs.isEmpty, !store.outdated.isEmpty {
                    Label("Update Battistics Remote to read this Mac", systemImage: "arrow.down.app")
                        .foregroundStyle(.orange)
                } else if store.remoteMacs.isEmpty {
                    Label("No Mac is sharing with this Apple Account yet.", systemImage: "magnifyingglass")
                        .foregroundStyle(.secondary)
                } else {
                    Label("^[\(store.remoteMacs.count) Mac](inflect: true) found", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button {
                    // Looks for a real Mac, which the sample stands in for.
                    if store.isSample { store.endSample() } else { Task { await store.refreshAll() } }
                } label: {
                    HStack {
                        if store.refreshing { ProgressView() }
                        Text("Check Again")
                    }
                    .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.bordered)
                .disabled(store.refreshing)
            }
            .font(.subheadline)
            .card()

            DisclosureGroup("Still not showing up?") {
                VStack(alignment: .leading, spacing: 10) {
                    tip("Is the Mac awake?", "It reports once Battistics is running and iPhone access is on. After that it keeps reporting while awake, also with the lid closed during Keep Awake.")
                    tip("Same Apple Account?", "Battistics Remote reads only your own private iCloud data, so a Mac on another account never appears.")
                    tip("Signed in to iCloud?", "Check Settings › Apple Account on this iPhone and System Settings › Apple Account on the Mac.")
                }
                .padding(.top, 8)
            }
            .font(.subheadline)
            .card()

            if store.macs.isEmpty {
                VStack(spacing: 14) {
                    Button {
                        dismiss()
                        withAnimation(.snappy) { store.showSample() }
                    } label: {
                        Label("Try a Sample Mac", systemImage: "laptopcomputer")
                    }
                    Button {
                        dismiss()
                        store.selectedID = MacStore.localPhoneID
                    } label: {
                        Label("Show This iPhone’s Battery", systemImage: "iphone")
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func step(_ number: Int, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.tint, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func tip(_ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fontWeight(.semibold)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
        }
    }
}
