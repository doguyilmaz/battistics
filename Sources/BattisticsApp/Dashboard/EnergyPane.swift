import AppKit
import BattisticsCore
import SwiftUI

/// Top energy consumers. Sampling only runs while this pane is visible;
/// the `.task` cancels the loop the moment the view disappears.
/// A sample plus the bits AppKit has to be asked for. Resolved once when the
/// sample arrives: `NSRunningApplication(processIdentifier:)` in the row
/// builder re-looked-up every process on every SwiftUI body evaluation, which
/// is far more often than a new sample lands.
private struct EnergyRow: Identifiable {
    let sample: ProcessEnergySample
    let icon: NSImage?
    let name: String

    var id: Int32 { sample.pid }

    init(sample: ProcessEnergySample) {
        self.sample = sample
        let app = NSRunningApplication(processIdentifier: sample.pid)
        icon = app?.icon
        name = app?.localizedName ?? sample.name
    }
}

struct EnergyPane: View {
    var isVisible = true

    @State private var rows: [EnergyRow] = []
    @State private var hasResults = false
    @State private var hovered: Int32?
    @State private var pendingQuit: EnergyRow?
    @State private var showingSamplingInfo = false

    var body: some View {
        VStack(spacing: 0) {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label(
                        hasResults ? "Nothing notable" : "Measuring…",
                        systemImage: "bolt.circle")
                } description: {
                    Text(
                        hasResults
                            ? "No process used meaningful energy in the last sample window."
                            : "Watching which apps use the most energy. First results arrive in a few seconds.")
                }
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(rows) { row in
                            GlassCard {
                                rowContent(row)
                            }
                            .onHover { hovered = $0 ? row.id : (hovered == row.id ? nil : hovered) }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Energy")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSamplingInfo.toggle()
                } label: {
                    Label("About energy sampling", systemImage: "info.circle")
                        .labelStyle(.iconOnly)
                }
                .help("About energy sampling")
                .popover(isPresented: $showingSamplingInfo, arrowEdge: .top) {
                    samplingInfo
                }
            }
        }
        .task(id: isVisible) {
            guard isVisible else { return }
            let sampler = ProcessEnergySampler.Session()
            while !Task.isCancelled {
                let result = await sampler.sample(over: .seconds(3), limit: 20)
                guard !Task.isCancelled else { break }
                rows = result.map(EnergyRow.init)
                hasResults = true
            }
        }
        .confirmationDialog(
            quitTitle, isPresented: quitBinding, presenting: pendingQuit
        ) { row in
            Button("Quit", role: .destructive) { quit(row) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Unsaved work in this app will be lost.")
        }
    }

    private var samplingInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Energy sampling")
                .font(.headline)
            Text("Shows up to 20 active processes, ranked by reported energy use when available, otherwise by CPU use.")
            Text("100% CPU represents one logical core. A process using multiple cores can exceed 100%.")
            Text("Sampling runs only while this view is visible.")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(width: 320, alignment: .leading)
    }

    private var quitTitle: String {
        guard let pendingQuit else { return "" }
        return String(localized: "Quit \(pendingQuit.name)?")
    }

    private var quitBinding: Binding<Bool> {
        Binding(get: { pendingQuit != nil }, set: { if !$0 { pendingQuit = nil } })
    }

    /// SIGTERM rather than NSRunningApplication.terminate(): that posts an
    /// Apple Event, which needs Automation consent per target app and would
    /// leave a permanent TCC entry for each one. A signal to a process owned
    /// by the same user needs nothing at all.
    private func quit(_ row: EnergyRow) {
        kill(row.sample.pid, SIGTERM)
        rows.removeAll { $0.id == row.id }
    }

    private func rowContent(_ row: EnergyRow) -> some View {
        let sample = row.sample
        return HStack(spacing: 12) {
            if let icon = row.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "gearshape.2")
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .fontWeight(.medium)
                Text("PID \(sample.pid)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if let share = sample.energyShare {
                ProgressView(value: share)
                    .frame(width: 90)
                    .tint(.orange)
            }
            Text(String(format: "%.1f%% CPU", sample.cpuPercent))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .trailing)
            // Reserved whether or not it shows, so hovering a row does not
            // reflow the ones beside it.
            Button {
                pendingQuit = row
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovered == row.id ? 1 : 0)
            .allowsHitTesting(hovered == row.id)
            .help("Quit this app")
        }
    }
}
