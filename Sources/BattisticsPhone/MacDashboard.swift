import BattisticsRemote
import SwiftUI

struct MacDashboard: View {
    @Environment(MacStore.self) private var store
    let mac: MacStore.Mac

    var body: some View {
        let reading = store.reading(for: mac)
        let reachable = reading?.reachable == true

        DashboardPage(glow: reading?.status.map { Glow($0, reachable: reachable) } ?? .offline,
                      refresh: { await store.refreshAll() }) {
            StatusLine(reading: reading, checking: store.checking, waiting: store.waitingForUpdate, problem: store.problem
                       ?? (store.outdated.contains(mac.id) ? String(localized: "Update Battistics Remote to read this Mac") : nil))
            if let status = reading?.status {
                Group {
                    BatteryCard(mac: mac, status: status, reachable: reachable)
                    KeepAwakeCard(mac: mac, status: status, reachable: reachable)
                    ConditionsGrid(status: status)
                        .opacity(reachable ? 1 : 0.6)
                    if status.battery != nil { HotspotCard(mac: mac, status: status, reachable: reachable) }
                    MacExtrasCard(mac: mac, status: status, reachable: reachable)
                }
                .animation(.snappy, value: reachable)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if store.isSample && !DemoData.isEnabled { SampleBar() }
        }
        .task {
            guard !store.isSample, Notifications.isEnabled else { return }
            await Notifications.requestPermission()
        }
    }
}

/// Stays in view while the Macs on screen are made up.
private struct SampleBar: View {
    @Environment(MacStore.self) private var store

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Sample Mac")
                    .font(.subheadline.weight(.semibold))
                Text("Made-up readings. Every control works.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Exit") {
                withAnimation(.snappy) { store.endSample() }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .fontWeight(.semibold)
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .capsule)
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
    }
}

private struct StatusLine: View {
    let reading: MacStore.Reading?
    let checking: Bool
    let waiting: Bool
    let problem: String?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(problem != nil ? .orange : reading?.reachable == true ? .green
                      : reading?.status?.sleptAt != nil || checking ? .gray : .orange)
                .frame(width: 8, height: 8)
            if let problem {
                Text(problem)
            } else if waiting {
                Text(String(localized: "Updating your Mac's status…", table: "RemoteSync"))
            } else if let readAt = reading?.status?.readAt {
                if reading?.reachable == true {
                    Text("Updated \(Ago.text(readAt))")
                } else if checking, reading?.status?.sleptAt == nil {
                    Text("Updating…")
                } else if let sleptAt = reading?.status?.sleptAt {
                    Text("Went to sleep \(Ago.text(sleptAt))")
                } else {
                    Text("Last seen \(Ago.text(readAt))")
                }
            } else {
                Text("Connecting…")
            }
            Spacer(minLength: 0)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}
