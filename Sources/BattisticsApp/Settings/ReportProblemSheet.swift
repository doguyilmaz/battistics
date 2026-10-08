import SwiftUI

/// The one way to report a problem. It says exactly what Battistics adds to
/// the report, offers a recent crash file, and lets the user pick GitHub or
/// email. Nothing is sent from here: both choices open a prefilled draft.
struct ReportProblemSheet: View {
    var crashReport: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Report a Problem")
                .font(.title3.weight(.semibold))
            Text("A prefilled issue or email opens for you to describe what happened. Battistics adds only these lines, and nothing is sent until you send it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: IssueReporter.diagnostics)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            if let crashReport {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(CrashWatch.description(of: crashReport))
                    Spacer(minLength: 12)
                    Button("Show in Finder") { CrashWatch.reveal(crashReport) }
                        .controlSize(.small)
                }
                .font(.callout)
                // The file lists the account name in every path, so it is
                // never attached for the user.
                Text("Crash files contain your account name in their paths, so attaching one is up to you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Send an Email") {
                    IssueReporter.openEmail(subject: issueTitle)
                    dismiss()
                }
                Button("Open a GitHub Issue") {
                    IssueReporter.openGitHubIssue(title: issueTitle)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 460)
    }

    private var issueTitle: String {
        crashReport == nil
            ? String(localized: "Battistics \(IssueReporter.appVersion)")
            : String(localized: "Crash on Battistics \(IssueReporter.appVersion)")
    }
}
