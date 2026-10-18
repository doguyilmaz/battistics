import AppKit
import SwiftUI

struct AutomationSettings: View {
    @Environment(AutomationModel.self) private var automation
    @State private var codexConfiguration = false
    @State private var copied = false

    var body: some View {
        @Bindable var automation = automation
        Section("Local automation") {
            Toggle("Allow terminal and AI tasks", isOn: $automation.enabled)
            Text("Terminal commands and AI clients can start a named task for up to 12 hours. Your battery and thermal protections still apply.")
                .font(.caption).foregroundStyle(.secondary)
            if automation.enabled {
                if automation.errorMessage == nil {
                    Label(automation.isListening ? String(localized: "Ready for local clients") : String(localized: "Starting…"),
                          systemImage: automation.isListening ? "checkmark.circle" : "clock")
                        .foregroundStyle(.secondary)
                }
                Toggle("Allow closed-lid tasks", isOn: $automation.closedLidAllowed)
                Text("Requires an already installed power helper. Only connect clients you trust; applications running as your macOS user can access this local connection.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Client configuration", selection: $codexConfiguration) {
                    Text("JSON (Claude / Cursor)").tag(false)
                    Text("TOML (Codex)").tag(true)
                }
                Button(copied ? String(localized: "Copied") : String(localized: "Copy MCP configuration")) {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(configuration, forType: .string)
                }
                .onChange(of: codexConfiguration) { _, _ in copied = false }
                Text("Keep Battistics open. If the client disconnects or stops responding, its task ends and normal sleep is allowed again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = automation.errorMessage { Text(error).foregroundStyle(.red) }
        }
        Section("Keep awake until a command finishes") {
            Text("Run a build, test suite or script from Terminal. Keep Awake ends when the command exits, or earlier if its time limit or your protection settings apply.")
                .font(.caption).foregroundStyle(.secondary)
            Text("battistics run --name Build -- swift build")
                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Button("Copy Terminal setup") {
                let path = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/battistics").path
                let quote: (String) -> String = { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("alias battistics=\(quote(quote(path)))\n", forType: .string)
            }
            Text("Paste once in your shell, then run the example. Enable local automation above and keep Battistics open. The default limit is 12 hours; use --minutes to choose a shorter limit.")
                .font(.caption).foregroundStyle(.secondary)
            Text("An interactive AI terminal can stay open after work finishes. Use MCP to start a task before work and stop it afterward; process lifetime alone cannot detect AI task completion.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var configuration: String {
        let path = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/battistics-mcp").path
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if codexConfiguration {
            // JSON string escaping is compatible with TOML basic strings for
            // filesystem paths, including backslashes and quotation marks.
            let quoted = (try? encoder.encode(path)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
            return "[mcp_servers.battistics]\ncommand = \(quoted)\n"
        }
        struct Server: Encodable { let command: String; let args: [String] }
        struct Config: Encodable { let mcpServers: [String: Server] }
        let data = try? encoder.encode(Config(mcpServers: ["battistics": .init(command: path, args: [])]))
        return data.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}
