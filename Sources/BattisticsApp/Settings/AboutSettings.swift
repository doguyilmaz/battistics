import SwiftUI

struct AboutSettings: View {
    @Environment(UpdaterModel.self) private var updater

    static var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version ?? "dev"
    }

    var body: some View {
        @Bindable var updater = updater
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 76, height: 76)
                    VStack(spacing: 2) {
                        Text("Battistics")
                            .font(.title2.weight(.semibold))
                        Text("Version \(Self.versionString)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Battery statistics for the Mac. Free and open source.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(verbatim: "Created by Dogu Yilmaz")
                        .font(.callout)
                    HStack(spacing: 14) {
                        if let url = URL(string: "https://github.com/doguyilmaz") {
                            Link(destination: url) { Text(verbatim: "@doguyilmaz") }
                        }
                        if let url = URL(string: "https://github.com/doguyilmaz/battistics") {
                            Link("GitHub", destination: url)
                        }
                        if let url = URL(string: "https://github.com/doguyilmaz/battistics/blob/main/LICENSE") {
                            Link("MIT License", destination: url)
                        }
                    }
                    .font(.callout)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                Toggle("Download updates automatically", isOn: $updater.automaticallyDownloadsUpdates)
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
}
