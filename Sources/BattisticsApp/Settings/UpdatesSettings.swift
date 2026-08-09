import SwiftUI

struct UpdatesSettings: View {
    @Environment(UpdaterModel.self) private var updater

    var body: some View {
        @Bindable var updater = updater
        Form {
            Section {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                Toggle("Download updates automatically", isOn: $updater.automaticallyDownloadsUpdates)
            }
            Section {
                LabeledContent("Version", value: Self.versionString)
                Button("Check Now") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
            Section {
                Text("Updates are the only network traffic Battistics ever makes. No analytics, no tracking, nothing else leaves this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    static var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version ?? "dev"
    }
}
