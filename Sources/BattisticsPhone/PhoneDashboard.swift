import BattisticsRemote
import SwiftUI

struct PhoneDashboard: View {
    @Environment(MacStore.self) private var store
    @Environment(LocalPhoneMonitor.self) private var phone
    @State private var editingHealth = false

    var body: some View {
        DashboardPage(refresh: {
            phone.refresh()
            await store.refreshAll()
        }) {
            Text("iOS \(UIDevice.current.systemVersion)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            batteryCard
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                StatTile(title: String(localized: "Low Power Mode"),
                         value: phone.lowPowerMode ? String(localized: "On") : String(localized: "Off"),
                         symbol: phone.lowPowerMode ? "leaf.fill" : "leaf",
                         tint: phone.lowPowerMode ? PowerPalette.lowPower : .accentColor,
                         highlighted: phone.lowPowerMode)
                StatTile(title: String(localized: "Heat"), value: phone.thermal.label, symbol: "thermometer.medium",
                         tint: phone.thermal == .nominal || phone.thermal == .fair ? .accentColor : phone.thermal.tint)
                StatTile(title: String(localized: "Free Storage"),
                         value: phone.availableStorage.formatted(.byteCount(style: .file)),
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

    private var batteryCard: some View {
        let battery = phone.batteryStatus
        let tint = battery.map(PowerPalette.batteryTint) ?? .secondary
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                BatteryGauge(percent: phone.percent, symbol: battery?.symbol ?? "battery.0percent", tint: tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(battery?.headline ?? String(localized: "Battery level unavailable"))
                        .font(.headline)
                    if phone.lowPowerMode {
                        Text("Low Power Mode is on")
                            .font(.subheadline)
                            .foregroundStyle(PowerPalette.lowPower)
                    }
                }
                Spacer(minLength: 0)
            }
            Button {
                editingHealth = true
            } label: {
                HStack(spacing: 8) {
                    MetricPill(label: String(localized: "Health"),
                               value: phone.enteredHealth.map { $0.percentText } ?? String(localized: "Add"),
                               symbol: "heart.fill",
                               tint: (phone.enteredHealth ?? 100) < 80 ? .orange : .accentColor)
                    MetricPill(label: String(localized: "Cycles"),
                               value: phone.enteredCycles.map(String.init) ?? String(localized: "Add"),
                               symbol: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Edit the values from Settings › Battery"))
            if phone.chargeHistory.count > 1 {
                ChargeSparkline(points: phone.chargeHistory, tint: tint)
            }
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
    }
}
