import BattisticsRemote
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(MacStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(Notifications.enabledKey) private var notify = true
    @State private var permission: UNAuthorizationStatus = .notDetermined
    @State private var phone = LocalPhoneMonitor.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if store.macs.isEmpty {
                        Label("No Macs sharing right now", systemImage: "laptopcomputer.slash")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.macs) { mac in
                            let reading = store.reading(for: mac)
                            let status = reading?.status
                            let isSelected = !store.isLocalPhoneSelected && store.selected?.id == mac.id
                            Button {
                                withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                                    store.selectedID = mac.id
                                }
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: status?.network == .hotspot ? "personalhotspot" : "laptopcomputer")
                                        .font(.title3)
                                        .foregroundStyle(status?.network == .hotspot ? PowerPalette.hotspot : Color.accentColor)
                                        .frame(width: 28)

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(mac.name)
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            if status?.session != nil {
                                                Image(systemName: "cup.and.saucer.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                        HStack(spacing: 6) {
                                            if let status {
                                                Text(status.networkDisplayLabel(fallbackHotspot: UIDevice.current.name))
                                            }
                                            if let seen = reading?.lastSeen {
                                                Text("·")
                                                Text(reading?.reachable == true
                                                     ? String(localized: "Updated \(seen.formatted(.relative(presentation: .named)))")
                                                     : String(localized: "Last seen \(seen.formatted(.relative(presentation: .named)))"))
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if let battery = status?.battery {
                                        HStack(spacing: 3) {
                                            if battery.lowPowerMode == true {
                                                Image(systemName: "leaf.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(PowerPalette.lowPower)
                                            } else if battery.isCharging {
                                                Image(systemName: "bolt.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(PowerPalette.charging)
                                            }
                                            Text("\(battery.percent)%")
                                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        phone.refresh()
                        withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                            store.selectedID = MacStore.localPhoneID
                        }
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "iphone")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(UIDevice.current.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("\(phone.modelName) · iOS \(UIDevice.current.systemVersion)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            HStack(spacing: 3) {
                                if phone.lowPowerMode {
                                    Image(systemName: "leaf.fill")
                                        .font(.caption2)
                                        .foregroundStyle(PowerPalette.lowPower)
                                } else if phone.isCharging {
                                    Image(systemName: "bolt.fill")
                                        .font(.caption2)
                                        .foregroundStyle(PowerPalette.charging)
                                }
                                Text("\(phone.percent)%")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            if store.isLocalPhoneSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Devices on Your Apple ID")
                } footer: {
                    Text("Every Mac with Battistics › iPhone enabled on your Apple ID appears here automatically. Tap a Mac to switch to it.")
                }

                Section {
                    Button {
                        HotspotOpener.open(using: openURL)
                    } label: {
                        Label("Open Personal Hotspot Settings", systemImage: "personalhotspot")
                            .foregroundStyle(PowerPalette.hotspot)
                    }
                    Text("With no Wi‑Fi nearby, turn on Settings › Personal Hotspot › Allow Others to Join. A Mac with Ask to join hotspots set to Automatic connects by itself, and Keep Awake keeps it connected with the lid closed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Personal Hotspot & Closed-Lid")
                }

                Section {
                    Toggle("Notify me", isOn: $notify)
                    if permission == .denied {
                        Button("Allow Notifications in Settings") {
                            openURL(URL(string: UIApplication.openNotificationSettingsURLString)!)
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Alerts you when Keep Awake ends, the battery runs low or will not last the session, or a Mac stops answering mid-session.")
                }
            }
            .navigationTitle("Devices & Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
        }
    }
}
