import BattisticsCore
import SwiftUI

struct PeripheralsPane: View {
    @Environment(BluetoothGATTReader.self) private var bluetooth
    @State private var peripherals: [PeripheralBattery] = []
    @State private var hasLoaded = false

    /// Levels read over Bluetooth join the rest rather than sitting in their
    /// own list: to the reader they are the same fact from another source.
    private var allBatteries: [PeripheralBattery] {
        var merged: [String: PeripheralBattery] = [:]
        for battery in peripherals + bluetooth.batteries {
            merged["\(battery.name)#\(battery.detail ?? "")"] = battery
        }
        return merged.values.sorted { ($0.name, $0.detail ?? "") < ($1.name, $1.detail ?? "") }
    }

    var body: some View {
        VStack(spacing: 0) {
        Group {
            if allBatteries.isEmpty {
                ContentUnavailableView(
                    "No peripheral batteries",
                    systemImage: "keyboard",
                    description: Text(
                        "Connected keyboards, mice, trackpads and headphones that report a battery level appear here. Many third-party devices keep their level to themselves and cannot be shown by any app.")
                )
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(allBatteries) { peripheral in
                            GlassCard {
                                HStack(spacing: 12) {
                                    Image(systemName: icon(for: peripheral.name))
                                        .font(.title3)
                                        .frame(width: 26)
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 5) {
                                            Text(peripheral.name)
                                                .fontWeight(.medium)
                                            // Earpieces report several cells;
                                            // the name alone cannot say which.
                                            if let detail = peripheral.detail {
                                                Text(detail)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        ProgressView(value: Double(peripheral.percent), total: 100)
                                            .tint(.charge(percent: Double(peripheral.percent)))
                                    }
                                    Text("\(peripheral.percent)%")
                                        .font(.callout.weight(.semibold))
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            }
            .frame(maxHeight: .infinity)
            bluetoothSection
        }
        .navigationTitle("Peripherals")
        .task {
            while !Task.isCancelled {
                // The IORegistry scan is instant and covers Apple's own Magic
                // peripherals. Everything else — AirPods and other earpieces —
                // is only in system_profiler, which costs about a second, so
                // it runs on the same slow tick rather than a faster one.
                async let hid = PeripheralBatteryReader.read()
                async let systemProfiler = BluetoothBatteryReader.fetch()
                var merged: [String: PeripheralBattery] = [:]
                for battery in await hid + systemProfiler {
                    // Same device and cell from both readers is one row.
                    merged["\(battery.name)#\(battery.detail ?? "")"] = battery
                }
                peripherals = merged.values.sorted {
                    ($0.name, $0.detail ?? "") < ($1.name, $1.detail ?? "")
                }
                hasLoaded = true
                bluetooth.refresh()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .task { bluetooth.startIfEnabled() }
    }

    /// A button, not a switch. A switch says the app owns the setting, but
    /// turning it on hands off to macOS's prompt and turning it off does not
    /// take the grant back — that only changes in System Settings. The
    /// trailing ellipsis is the convention for an action that opens a dialog.
    ///
    /// Laid out like the System pane's permission row so the app has one way
    /// of asking for things rather than a different one per pane.
    @ViewBuilder private var bluetoothSection: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: bluetoothIcon)
                .contentTransition(.symbolEffect(.replace))
            // One line, always. Measured at 10pt against the 549pt this row
            // leaves beside the icon and button: the longest string is 405pt
            // in Turkish, so nothing here wraps or truncates.
            Text(bluetoothExplanation)
                .lineLimit(1)
            Spacer(minLength: 12)
            bluetoothAction
        }
        .font(.caption)
        .foregroundStyle(bluetooth.state == .ready ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    @ViewBuilder private var bluetoothAction: some View {
        switch bluetooth.state {
        case .off:
            Button("Allow…") { bluetooth.isEnabled = true }
                .controlSize(.small)
        case .denied:
            Button("Open Settings…") {
                if let url = URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
                ) {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        case .ready:
            Button("Turn Off") { bluetooth.isEnabled = false }
                .controlSize(.small)
        case .waiting, .unavailable:
            EmptyView()
        }
    }

    private var bluetoothIcon: String {
        switch bluetooth.state {
        case .ready: "antenna.radiowaves.left.and.right"
        case .denied: "exclamationmark.triangle.fill"
        default: "antenna.radiowaves.left.and.right.slash"
        }
    }

    private var bluetoothExplanation: String {
        switch bluetooth.state {
        case .off:
            String(
                localized:
                    "Some devices publish their level only over Bluetooth. macOS asks for access once.")
        case .waiting:
            String(localized: "Waiting for Bluetooth…")
        case .denied:
            String(
                localized: "macOS is not allowing Bluetooth access, so these levels cannot be read.")
        case .unavailable:
            String(localized: "Bluetooth is switched off or unavailable on this Mac.")
        case .ready:
            bluetooth.batteries.isEmpty
                ? String(localized: "No connected device publishes its battery this way.")
                : String(localized: "Reading levels over Bluetooth.")
        }
    }

    private func icon(for name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("keyboard") { return "keyboard" }
        if lowered.contains("mouse") { return "computermouse" }
        if lowered.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if lowered.contains("airpods") || lowered.contains("headphone") || lowered.contains("buds") {
            return "airpods"
        }
        return "battery.75percent"
    }
}
