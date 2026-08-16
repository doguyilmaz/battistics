import SwiftUI

struct AboutSettings: View {
    @Environment(UpdaterModel.self) private var updater

    static var versionString: String { IssueReporter.appVersion }

    /// Looked up once when the pane appears rather than per redraw: it hits
    /// the filesystem, and a crash that happened before launch will not
    /// appear while the window is open.
    @State private var crashReport: URL?

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
                        if let url = URL(
                            string: "https://github.com/doguyilmaz/battistics/blob/main/CHANGELOG.md") {
                            Link("Changelog", destination: url)
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
                LabeledContent {
                    Button("Check Now") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)
                } label: {
                    Text(lastCheckedText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Support") {
                if let crashReport {
                    LabeledContent {
                        Button("Show Report") { CrashWatch.reveal(crashReport) }
                    } label: {
                        Text(crashedText(CrashWatch.date(of: crashReport)))
                            .font(.callout)
                    }
                }
                LabeledContent {
                    HStack(spacing: 8) {
                        Button("Open an Issue") {
                            IssueReporter.openGitHubIssue(title: issueTitle)
                        }
                        Button("Send an Email") {
                            IssueReporter.openEmail(subject: issueTitle)
                        }
                    }
                } label: {
                    Text("Found a bug, or something behaving oddly?")
                        .font(.callout)
                }
                Text("Both open prefilled with your version, macOS release and Mac model. Nothing is sent until you send it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("Updates are the only network traffic Battistics ever makes. No analytics, no tracking, nothing else leaves this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { crashReport = CrashWatch.latestReport() }
    }

    private var issueTitle: String {
        crashReport == nil
            ? String(localized: "Battistics \(Self.versionString)")
            : String(localized: "Crash on Battistics \(Self.versionString)")
    }

    /// macOS shows its own "quit unexpectedly" dialog, so this is not news by
    /// the time it is read; it is here to put the file next to the buttons
    /// that send it.
    private func crashedText(_ date: Date?) -> String {
        guard let date else {
            return String(localized: "Battistics quit unexpectedly recently")
        }
        return String(
            localized: "Battistics quit unexpectedly \(date.formatted(.relative(presentation: .named)))")
    }

    /// Sparkle checks daily, counted from the last check rather than from
    /// launch, so "never" here means it has not run yet, not that it is off.
    private var lastCheckedText: String {
        guard let date = updater.lastCheckDate else {
            return String(localized: "Checked automatically every 24 hours")
        }
        return String(
            localized: "Last checked \(date.formatted(.relative(presentation: .named)))")
    }
}
