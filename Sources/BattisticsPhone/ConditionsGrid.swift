import BattisticsRemote
import SwiftUI

struct ConditionsGrid: View {
    let status: RemoteStatus
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let isHotspot = status.network == .hotspot
        let name = status.resolvedNetworkName()
        let columns = typeSize.isAccessibilitySize ? 1 : 2
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
            StatTile(title: name == nil ? String(localized: "Network") : status.network.label,
                     value: name ?? status.network.label,
                     symbol: status.network.symbol,
                     tint: status.network == .offline ? .orange : (isHotspot ? PowerPalette.hotspot : .accentColor),
                     highlighted: isHotspot,
                     flashesOnChange: true)
            if let battery = status.battery {
                StatTile(title: String(localized: "Lid"),
                         value: status.lidClosed == true ? String(localized: "Closed") : String(localized: "Open"),
                         symbol: status.lidClosed == true ? "laptopcomputer.slash" : "laptopcomputer",
                         flashesOnChange: true)
                StatTile(title: String(localized: "Power Adapter"),
                         value: battery.onAdapter
                            ? battery.adapterWatts.map { "\($0) W" } ?? String(localized: "Connected")
                            : String(localized: "Not connected"),
                         symbol: battery.onAdapter ? "powerplug.fill" : "powerplug",
                         tint: battery.onAdapter ? PowerPalette.charging : .accentColor,
                         flashesOnChange: true)
                StatTile(title: String(localized: "Battery stop"),
                         value: status.protection.stopAtPercent?.percentText ?? String(localized: "Off"),
                         symbol: "shield.lefthalf.filled")
            } else {
                StatTile(title: String(localized: "Heat"), value: status.thermal.label, symbol: "thermometer.medium",
                         tint: status.thermal.isHot ? status.thermal.tint : .accentColor)
            }
        }
    }
}

/// Whether the Mac can stay online in a bag, and what to do if not.
struct HotspotCard: View {
    let mac: MacStore.Mac
    let status: RemoteStatus
    let reachable: Bool
    @State private var showingHelp = false

    var body: some View {
        let ready = reachable && status.isBagReady
        let (symbol, tint, title, detail) = content(ready: ready)
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: .circle)
                .background { ReadyPulse(tint: tint, ready: ready) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !ready {
                Button("How") { showingHelp = true }
                    .accessibilityLabel(Text("How to turn on Personal Hotspot"))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .card(border: ready ? tint.opacity(0.5) : (reachable && status.network == .hotspot ? tint.opacity(0.3) : nil))
        .animation(.snappy, value: ready)
        .animation(.snappy, value: status.network)
        .sensoryFeedback(trigger: ready) { _, ready in ready ? .success : nil }
        .hotspotHelp(isPresented: $showingHelp)
    }

    private func content(ready: Bool) -> (String, Color, String, String) {
        if !reachable, status.sleptAt != nil {
            return ("moon.zzz.fill", .gray, String(localized: "\(mac.name) is asleep"),
                    String(localized: "It answers again once it wakes."))
        }
        if !reachable {
            return ("antenna.radiowaves.left.and.right.slash", .orange,
                    String(localized: "Can’t reach \(mac.name)"),
                    status.session?.isActive(at: .now) != true
                        ? String(localized: "Asleep, or away from Wi‑Fi without Hotspot.")
                        : String(localized: "It was keeping awake. If it left Wi‑Fi, turn on Hotspot."))
        }
        if status.network == .hotspot {
            let name = status.resolvedNetworkName() ?? String(localized: "Personal Hotspot")
            return ready
                ? ("checkmark.seal.fill", PowerPalette.hotspot, String(localized: "Bag Ready"),
                   String(localized: "Online on \(name), even with the lid closed."))
                : ("personalhotspot", PowerPalette.hotspot, String(localized: "On \(name)"),
                   String(localized: "Allow closed-lid sessions from iPhone on the Mac."))
        }
        return ("personalhotspot", .accentColor,
                String(localized: "Before the Mac goes in a bag"),
                String(localized: "Turn on Personal Hotspot. A Mac set to join it stays online."))
    }
}

/// One ring that spreads from the icon when the Mac becomes Bag Ready.
private struct ReadyPulse: View {
    let tint: Color
    let ready: Bool

    var body: some View {
        Circle()
            .stroke(tint, lineWidth: 2)
            .keyframeAnimator(initialValue: Ring(), trigger: ready) { ring, value in
                ring.scaleEffect(value.scale).opacity(value.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    LinearKeyframe(1, duration: 0.01)
                    SpringKeyframe(2.2, duration: 0.9)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(ready ? 0.9 : 0, duration: 0.01)
                    LinearKeyframe(0, duration: 0.9)
                }
            }
            .allowsHitTesting(false)
    }

    private struct Ring {
        var scale = 1.0
        var opacity = 0.0
    }
}
