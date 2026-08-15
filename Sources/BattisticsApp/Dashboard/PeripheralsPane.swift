import BattisticsCore
import SwiftUI

struct PeripheralsPane: View {
    @State private var peripherals: [PeripheralBattery] = []
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if peripherals.isEmpty {
                ContentUnavailableView(
                    "No peripheral batteries",
                    systemImage: "keyboard",
                    description: Text(
                        "Connected keyboards, mice, trackpads and headphones that report a battery level appear here. Many third-party devices, including Logitech's MX range, keep their level to themselves and cannot be shown by any app.")
                )
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(peripherals) { peripheral in
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
        .navigationTitle("Peripherals")
        .task {
            while !Task.isCancelled {
                // The IORegistry scan is instant and covers Apple's own Magic
                // peripherals. Everything else — AirPods and other earpieces —
                // is only in system_profiler, which costs about a second, so
                // it runs on the same slow tick rather than a faster one.
                async let hid = PeripheralBatteryReader.read()
                async let bluetooth = BluetoothBatteryReader.fetch()
                peripherals = await (hid + bluetooth).sorted {
                    ($0.name, $0.detail ?? "") < ($1.name, $1.detail ?? "")
                }
                hasLoaded = true
                try? await Task.sleep(for: .seconds(15))
            }
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
