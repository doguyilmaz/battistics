import SwiftUI

struct AboutSettings: View {
    @Environment(AppModel.self) private var model
    @State private var showingReport = false

    static var versionString: String { IssueReporter.appVersion }

    /// Looked up once when the pane appears rather than per redraw: it hits
    /// the filesystem, and a crash that happened before launch will not
    /// appear while the window is open.
    @State private var crashReport: URL?

    var body: some View {
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
            Section("Support") {
                if let crashReport {
                    Label {
                        Text(CrashWatch.description(of: crashReport))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.callout)
                }
                LabeledContent {
                    Button("Report a Problem…") { showingReport = true }
                } label: {
                    Text("Found a bug, or something behaving oddly?")
                        .font(.callout)
                }
            }
            Section {
                Text("Updates are the only network traffic Battistics ever makes. No analytics, no tracking, nothing else leaves this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingReport) {
            ReportProblemSheet(crashReport: crashReport)
        }
        .onAppear {
            crashReport = CrashWatch.latestReport()
            presentRequestedReport()
        }
        // The popover and the Help menu ask for the sheet by setting this.
        .onChange(of: model.reportRequested) { presentRequestedReport() }
    }

    private func presentRequestedReport() {
        guard model.reportRequested else { return }
        model.reportRequested = false
        showingReport = true
    }
}
