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
            StatusLine(reading: reading, problem: store.problem)
            if let status = reading?.status {
                Group {
                    BatteryCard(mac: mac, status: status, reachable: reachable)
                    KeepAwakeCard(mac: mac, status: status, reachable: reachable)
                    ConditionsGrid(status: status)
                        .opacity(reachable ? 1 : 0.6)
                    HotspotCard(mac: mac, status: status, reachable: reachable)
                    MacExtrasCard(mac: mac, status: status, reachable: reachable)
                }
                .animation(.snappy, value: reachable)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
    }
}

private struct StatusLine: View {
    let reading: MacStore.Reading?
    let problem: String?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(problem != nil || reading?.reachable != true ? Color.orange : .green)
                .frame(width: 8, height: 8)
            if let problem {
                Text(problem)
            } else if let readAt = reading?.status?.readAt {
                if reading?.reachable == true {
                    Text("Updated \(Ago.text(readAt))")
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
