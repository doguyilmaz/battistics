import BattisticsRemote
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(MacStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(Notifications.enabledKey) private var notify = true
    @State private var permission: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(store.macs) { mac in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mac.name)
                            if let seen = store.reading(for: mac)?.lastSeen {
                                Text("Last seen \(seen.formatted(.relative(presentation: .named)))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Macs")
                } footer: {
                    Text("Macs on this Apple ID appear here when Battistics › iPhone is on. Turn it off on a Mac to remove it.")
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
                    Text("When Keep Awake ends, the battery runs low or will not last the session, or a Mac stops answering mid-session. iOS decides how often it checks in the background, so alerts can arrive late.")
                }

                Section("Stay online with the lid closed") {
                    Text("With no Wi‑Fi nearby, turn on Settings › Personal Hotspot › Allow Others to Join. A Mac with Ask to join hotspots set to Automatic connects by itself, and Keep Awake keeps it connected.")
                        .font(.subheadline)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
        }
    }
}
