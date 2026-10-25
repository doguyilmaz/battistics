import BattisticsRemote
import SwiftUI

struct ConditionsGrid: View {
    let status: RemoteStatus

    var body: some View {
        let isHotspot = status.network == .hotspot
        let name = status.resolvedNetworkName()
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            StatTile(title: name == nil ? String(localized: "Network") : status.network.label,
                     value: name ?? status.network.label,
                     symbol: status.network.symbol,
                     tint: status.network == .offline ? .orange : (isHotspot ? PowerPalette.hotspot : .accentColor),
                     highlighted: isHotspot)
            StatTile(title: String(localized: "Lid"),
                     value: status.lidClosed == true ? String(localized: "Closed") : String(localized: "Open"),
                     symbol: status.lidClosed == true ? "laptopcomputer.slash" : "laptopcomputer")
            StatTile(title: String(localized: "Power Adapter"),
                     value: status.battery?.onAdapter == true
                        ? status.battery?.adapterWatts.map { "\($0) W" } ?? String(localized: "Connected")
                        : String(localized: "Not connected"),
                     symbol: status.battery?.onAdapter == true ? "powerplug.fill" : "powerplug",
                     tint: status.battery?.onAdapter == true ? PowerPalette.charging : .accentColor)
            StatTile(title: String(localized: "Battery stop"),
                     value: status.protection.stopAtPercent.map { String(localized: "At \($0)%") } ?? String(localized: "Off"),
                     symbol: "shield.lefthalf.filled")
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
        let (symbol, tint, title, detail) = content
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !(reachable && status.isBagReady) {
                Button("How") { showingHelp = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .card(border: reachable && status.network == .hotspot ? PowerPalette.hotspot.opacity(0.4) : nil)
        .hotspotHelp(isPresented: $showingHelp)
    }

    private var content: (String, Color, String, String) {
        if !reachable {
            return ("antenna.radiowaves.left.and.right.slash", .orange,
                    String(localized: "Can’t reach \(mac.name)"),
                    status.session == nil
                        ? String(localized: "It may be asleep, or away from Wi‑Fi without Personal Hotspot.")
                        : String(localized: "Keep Awake was running when it last answered. If it left Wi‑Fi, turn on Personal Hotspot."))
        }
        if status.network == .hotspot {
            let name = status.resolvedNetworkName() ?? String(localized: "Personal Hotspot")
            return ("personalhotspot", PowerPalette.hotspot,
                    status.protection.closedLidAllowed ? String(localized: "Bag Ready on \(name)") : String(localized: "On \(name)"),
                    status.protection.closedLidAllowed
                        ? String(localized: "The Mac stays online with the lid closed, as long as this iPhone is nearby.")
                        : String(localized: "Allow closed-lid sessions from iPhone on the Mac to use it in a bag."))
        }
        return ("personalhotspot", .accentColor,
                String(localized: "Before the Mac goes in a bag"),
                String(localized: "Turn on Personal Hotspot here. A Mac set to join it automatically stays online away from Wi‑Fi."))
    }
}
