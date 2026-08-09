import AppKit
import BattisticsCore
import SwiftUI

/// Top energy consumers. Sampling only runs while this pane is visible;
/// the `.task` cancels the loop the moment the view disappears.
struct EnergyPane: View {
    @State private var samples: [ProcessEnergySample] = []
    @State private var hasResults = false

    var body: some View {
        VStack(spacing: 0) {
            if samples.isEmpty {
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
                        ForEach(samples) { sample in
                            GlassCard {
                                row(for: sample)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            Text("Sampling runs only while this view is open and stops the moment it closes.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 10)
        }
        .navigationTitle("Energy")
        .task {
            while !Task.isCancelled {
                let result = await ProcessEnergySampler.sample(over: .seconds(3))
                guard !Task.isCancelled else { break }
                samples = result
                hasResults = true
            }
        }
    }

    private func row(for sample: ProcessEnergySample) -> some View {
        let app = NSRunningApplication(processIdentifier: sample.pid)
        return HStack(spacing: 12) {
            if let icon = app?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "gearshape.2")
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(app?.localizedName ?? sample.name)
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
        }
    }
}
