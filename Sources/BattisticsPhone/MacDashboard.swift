import BattisticsRemote
import SwiftUI

struct MacDashboard: View {
    @Environment(MacStore.self) private var store
    let mac: MacStore.Mac
    @State private var message: String?

    var body: some View {
        let reading = store.reading(for: mac)
        let reachable = reading?.reachable == true

        DashboardPage(refresh: { await store.refreshAll() }) {
            StatusLine(reading: reading, problem: store.problem)
            if let status = reading?.status {
                Group {
                    BatteryCard(mac: mac, status: status, reachable: reachable, message: $message)
                    KeepAwakeCard(mac: mac, status: status, reachable: reachable, message: $message)
                    HotspotCard(mac: mac, status: status, reachable: reachable)
                    ConditionsGrid(status: status)
                        .opacity(reachable ? 1 : 0.6)
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
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(reading?.reachable == true
                         ? String(localized: "Updated \(readAt.formatted(.relative(presentation: .named)))")
                         : String(localized: "Last seen \(readAt.formatted(.relative(presentation: .named)))"))
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
