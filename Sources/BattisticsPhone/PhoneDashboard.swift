import BattisticsRemote
import SwiftUI

struct PhoneDashboard: View {
    @Environment(MacStore.self) private var store
    @Environment(LocalPhoneMonitor.self) private var phone
    @State private var editingHealth = false

    var body: some View {
        DashboardPage(glow: Glow(battery: phone.batteryStatus.map(PowerPalette.batteryTint) ?? .accentColor), refresh: {
            phone.refresh()
            await store.refreshAll()
        }) {
            batteryCard
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                StatTile(title: String(localized: "Power"), value: powerText,
                         symbol: phone.isCharging ? "bolt.fill" : phone.onAdapter ? "powerplug.fill" : "battery.75percent",
                         tint: phone.isCharging ? PowerPalette.charging : .accentColor)
                StatTile(title: String(localized: "Last Hour"), value: rateText,
                         symbol: "chart.line.uptrend.xyaxis",
                         tint: (phone.chargeRate ?? 0) > 0 ? PowerPalette.charging : .accentColor)
                StatTile(title: String(localized: "Last Full Charge"), value: lastFullText, symbol: "battery.100percent")
                StatTile(title: String(localized: "Low Power Mode"),
                         value: phone.lowPowerMode ? String(localized: "On") : String(localized: "Off"),
                         symbol: phone.lowPowerMode ? "leaf.fill" : "leaf",
                         tint: phone.lowPowerMode ? PowerPalette.lowPower : .accentColor,
                         highlighted: phone.lowPowerMode)
                StatTile(title: String(localized: "Heat"), value: phone.thermal.label, symbol: "thermometer.medium",
                         tint: phone.thermal == .nominal || phone.thermal == .fair ? .accentColor : phone.thermal.tint)
                StatTile(title: phone.lowDataMode ? String(localized: "Low Data Mode") : String(localized: "Network"),
                         value: connectionText, symbol: connectionSymbol,
                         tint: phone.connection == .offline ? .orange : .accentColor)
                StatTile(title: String(localized: "of \(phone.totalStorage.formatted(.byteCount(style: .file)))"),
                         value: String(localized: "\(phone.availableStorage.formatted(.byteCount(style: .file))) free"),
                         symbol: "internaldrive")
                StatTile(title: String(localized: "Since Restart"),
                         value: Duration.seconds(phone.uptime).formatted(.units(allowed: [.days, .hours, .minutes],
                                                                                 width: .narrow, maximumUnitCount: 2)),
                         symbol: "clock.arrow.circlepath")
            }
            if !store.macs.isEmpty { macsCard }
        }
        .sheet(isPresented: $editingHealth) {
            BatteryHealthSheet()
                .presentationDetents([.medium, .large])
        }
        .onAppear { phone.refresh() }
    }

    /// "About 5 hr left at this rate", worded as the estimate it is.
    private var estimateText: String? {
        guard let percent = phone.percent, let rate = phone.chargeRate,
              (rate < 0) != phone.isCharging,
              let minutes = ChargeRate.minutesLeft(percent: percent, rate: rate) else { return nil }
        let time = DurationLabel.long(minutes: minutes)
        return rate < 0
            ? String(localized: "About \(time) left at this rate")
            : String(localized: "About \(time) to full at this rate")
    }

    private var powerText: String {
        if phone.isCharging { return String(localized: "Charging") }
        if phone.onAdapter { return String(localized: "Charged") }
        guard let since = phone.unpluggedAt else { return String(localized: "On Battery") }
        let time = Duration.seconds(Date.now.timeIntervalSince(since))
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2))
        return String(localized: "\(time) on battery")
    }

    /// "−8% per hour" from this app's own readings; "Steady" once an hour shows no change.
    private var rateText: String {
        if let rate = phone.chargeRate {
            let value = Int(rate.rounded())
            return String(localized: "\(value > 0 ? "+" : "")\(value)% per hour")
        }
        let recent = phone.chargeHistory.filter { -$0.at.timeIntervalSinceNow <= 90 * 60 }
        guard let first = recent.first, let last = recent.last,
              last.at.timeIntervalSince(first.at) >= 15 * 60 else { return String(localized: "Measuring") }
        return String(localized: "Steady")
    }

    private var lastFullText: String {
        if phone.percent == 100 { return String(localized: "Now") }
        guard let full = phone.chargeHistory.last(where: { $0.percent >= 99 }) else {
            let covered = phone.chargeHistory.first.map { -$0.at.timeIntervalSinceNow > 23 * 3600 } ?? false
            return covered ? String(localized: "Over a day ago") : String(localized: "Not seen yet")
        }
        return full.at.formatted(.relative(presentation: .named))
    }

    private var connectionText: String {
        switch phone.connection {
        case .wifi: String(localized: "Wi‑Fi")
        case .cellular: String(localized: "Cellular")
        case .wired: String(localized: "Ethernet")
        case .offline: String(localized: "Offline")
        }
    }

    private var connectionSymbol: String {
        switch phone.connection {
        case .wifi: "wifi"
        case .cellular: "antenna.radiowaves.left.and.right"
        case .wired: "cable.connector"
        case .offline: "wifi.slash"
        }
    }

    private var batteryCard: some View {
        let battery = phone.batteryStatus
        let tint = battery.map(PowerPalette.batteryTint) ?? .secondary
        let totals = ChargeRate.totals(phone.chargeHistory)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                BatteryGauge(percent: phone.percent, symbol: battery?.symbol ?? "battery.0percent", tint: tint,
                             charging: phone.isCharging)
                VStack(alignment: .leading, spacing: 3) {
                    Text(battery?.headline ?? String(localized: "Battery level unavailable"))
                        .font(.headline)
                    if let estimate = estimateText {
                        Text(estimate)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if phone.lowPowerMode {
                        Text("Low Power Mode is on")
                            .font(.subheadline)
                            .foregroundStyle(PowerPalette.lowPower)
                    }
                }
                Spacer(minLength: 0)
            }
            if phone.chargeHistory.count > 1 {
                ChargeSparkline(points: phone.chargeHistory, tint: tint)
                if totals.gained + totals.used > 0 {
                    HStack(spacing: 14) {
                        Label(String(localized: "\(totals.gained)% charged"), systemImage: "arrow.up")
                        Label(String(localized: "\(totals.used)% used"), systemImage: "arrow.down")
                        Spacer(minLength: 0)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .labelStyle(TightLabel())
                }
            }
            Divider()
            Button {
                editingHealth = true
            } label: {
                HStack(spacing: 6) {
                    Label("Battery Health", systemImage: "heart.fill")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let health = phone.enteredHealth {
                        Text(health.percentText)
                            .foregroundStyle(health < 80 ? Color.orange : .primary)
                        if let cycles = phone.enteredCycles {
                            Text("· \(cycles) cycles").foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Add from Settings").foregroundStyle(Color.accentColor)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .font(.subheadline)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .card(border: phone.isCharging || phone.lowPowerMode ? tint.opacity(0.35) : nil)
    }

    private var macsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Macs")
                .font(.headline)
            ForEach(store.macs) { mac in
                let reading = store.reading(for: mac)
                Button {
                    store.selectedID = mac.id
                } label: {
                    HStack {
                        Label(mac.name, systemImage: "laptopcomputer")
                            .lineLimit(1)
                        Spacer()
                        if reading?.reachable != true {
                            Text("Offline").foregroundStyle(.secondary)
                        } else if let percent = reading?.status?.battery?.percent {
                            Text("\(percent)%").monospacedDigit().foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.subheadline)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }
}

private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.caption2.weight(.bold))
            configuration.title
        }
    }
}

/// iOS shows battery health and cycle count only in Settings, so the user copies them here.
private struct BatteryHealthSheet: View {
    @Environment(LocalPhoneMonitor.self) private var phone
    @Environment(\.dismiss) private var dismiss
    @State private var health = 100
    @State private var cycles = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $health, in: 50...100) {
                        LabeledContent("Maximum Capacity", value: health.percentText)
                    }
                    LabeledContent("Cycle Count") {
                        TextField("Optional", text: $cycles)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("iOS does not share these with apps. Copy them from Settings › Battery › Battery Health.")
                }
                if phone.enteredHealth != nil || phone.enteredCycles != nil {
                    Section {
                        Button("Clear", role: .destructive) {
                            phone.enteredHealth = nil
                            phone.enteredCycles = nil
                            dismiss()
                        }
                    }
                }
            }
            .topBlur()
            .navigationTitle("Battery Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        phone.enteredHealth = health
                        phone.enteredCycles = Int(cycles.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                }
            }
            .onAppear {
                health = phone.enteredHealth ?? 100
                cycles = phone.enteredCycles.map(String.init) ?? ""
            }
        }
        .softScrollEdge()
    }
}
