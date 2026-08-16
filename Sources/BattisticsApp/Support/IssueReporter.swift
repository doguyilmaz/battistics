import AppKit
import Foundation

/// Prefilled bug reports, opened in the user's browser or mail client.
///
/// Nothing here transmits anything. The app builds a URL and hands it over;
/// the user reads what it says and decides whether to send it. That is the
/// difference between this and crash telemetry, and it is what lets the About
/// pane keep promising that updates are the only traffic Battistics makes.
enum IssueReporter {
    static let email = "hello@doguyilmaz.com"
    private static let repository = "https://github.com/doguyilmaz/battistics"

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// Version, OS and machine model: enough to reproduce a report, and
    /// nothing that says who sent it.
    ///
    /// Deliberately not the crash file. An `.ips` embeds the account name in
    /// every path it lists, so attaching one is the user's call to make after
    /// reading it — `CrashWatch.reveal` only opens Finder on it.
    static var diagnostics: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return """
            Battistics \(appVersion)
            macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)
            \(hardwareModel)
            """
    }

    static func openGitHubIssue(title: String) {
        var components = URLComponents(string: "\(repository)/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: bodyTemplate),
        ]
        open(components?.url)
    }

    static func openEmail(subject: String) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: bodyTemplate),
        ]
        open(components.url)
    }

    private static var bodyTemplate: String {
        """
        \(String(localized: "What happened?"))


        \(String(localized: "What did you expect instead?"))


        ---
        \(diagnostics)
        """
    }

    private static func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    private static var hardwareModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var bytes = [UInt8](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
}

/// Finds the crash reports macOS already wrote for this app.
///
/// The alternative was a "did we shut down cleanly" flag, which cannot tell a
/// crash from a force quit or from a logout that never delivered
/// `applicationWillTerminate`. The `.ips` file is the system's own evidence:
/// if one is there, it really crashed, and the file is what the user needs to
/// attach anyway.
enum CrashWatch {
    /// macOS also names the privileged helper's reports after its executable,
    /// and a helper crash is exactly the kind the user cannot see.
    private static let prefixes = ["Battistics-", "PowerHelper-"]

    /// Older reports are somebody else's problem by now, and surfacing one
    /// months later reads as a bug in this app rather than a record of one.
    private static let window: TimeInterval = 7 * 86400

    static func latestReport() -> URL? {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/DiagnosticReports")
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return nil }

        let cutoff = Date().addingTimeInterval(-window)
        return
            files
            .filter { file in
                file.pathExtension == "ips"
                    && prefixes.contains { file.lastPathComponent.hasPrefix($0) }
            }
            .compactMap { file -> (URL, Date)? in
                guard
                    let date = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate, date > cutoff
                else { return nil }
                return (file, date)
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    static func reveal(_ report: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([report])
    }

    static func date(of report: URL) -> Date? {
        try? report.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
