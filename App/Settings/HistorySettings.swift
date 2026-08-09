import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HistorySettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Prefs.powerSamplingEnabled) private var samplingEnabled = true
    @AppStorage(Prefs.powerSamplingInterval) private var samplingInterval = 60.0

    @State private var databaseSize: Int64 = 0
    @State private var confirmingDelete = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("Recording") {
                Text(
                    "Charge history is event driven and costs nothing while idle. "
                        + "Power and temperature history need one lightweight reading on a timer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Record power and temperature", isOn: $samplingEnabled)
                    .onChange(of: samplingEnabled) {
                        model.restartPowerSampling()
                    }
                if samplingEnabled {
                    Picker("Sampling interval", selection: $samplingInterval) {
                        Text("30 seconds").tag(30.0)
                        Text("1 minute").tag(60.0)
                        Text("2 minutes").tag(120.0)
                        Text("5 minutes").tag(300.0)
                    }
                    .onChange(of: samplingInterval) {
                        model.restartPowerSampling()
                    }
                }
            }
            Section("Data") {
                LabeledContent(
                    "On disk",
                    value: ByteCountFormatter.string(fromByteCount: databaseSize, countStyle: .file))
                HStack {
                    Button("Export CSV…") { exportCSV() }
                    Button("Import CSV…") { importCSV() }
                    Button("Delete History…", role: .destructive) { confirmingDelete = true }
                }
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Old samples are compacted automatically: raw power readings become hourly averages after 30 days. Daily health snapshots are kept forever.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await refreshSize() }
        .confirmationDialog(
            "Delete all recorded history?", isPresented: $confirmingDelete
        ) {
            Button("Delete Everything", role: .destructive) {
                Task {
                    await model.history.deleteAllHistory()
                    await refreshSize()
                    statusMessage = "History deleted."
                }
            }
        } message: {
            Text("Charge, power and health history will be removed permanently. Export a CSV first if you want a backup.")
        }
    }

    private func refreshSize() async {
        databaseSize = await model.history.databaseSizeBytes()
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Battistics-history.csv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                let csv = await model.history.exportCSV()
                do {
                    try csv.write(to: url, atomically: true, encoding: .utf8)
                    statusMessage = "Exported to \(url.lastPathComponent)."
                } catch {
                    statusMessage = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    let count = try await model.history.importCSV(text)
                    await refreshSize()
                    statusMessage = "Imported \(count) rows."
                } catch {
                    statusMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
