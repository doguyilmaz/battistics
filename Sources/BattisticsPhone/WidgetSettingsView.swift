import BattisticsRemote
import SwiftUI
import WidgetKit

struct WidgetSettingsView: View {
    @Environment(MacStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @State private var prefs = WidgetPreferences.load()

    var body: some View {
        let entry = MacEntry(date: .now, snapshot: snapshot, prefs: prefs)
        Form {
            Section {
                Picker("Layout", selection: $prefs.lockScreenLayout) {
                    ForEach(WidgetPreferences.LockScreenLayout.allCases) { Text($0.label).tag($0) }
                }
                Picker("Details", selection: $prefs.metricFocus) {
                    ForEach(WidgetPreferences.MetricFocus.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Show Network Name", isOn: $prefs.showNetworkSSID)
            } footer: {
                Text("Applies to every Battistics widget. Add them from the Home Screen or Lock Screen editor.")
            }

            Section("Lock Screen") {
                ScrollView(.horizontal) {
                    HStack(alignment: .center, spacing: 14) {
                        preview(width: 170, height: 76, shape: .rect(cornerRadius: 16), dark: true) {
                            MacLockScreenDetailView(entry: entry, familyOverride: .accessoryRectangular)
                        }
                        preview(width: 76, height: 76, shape: .circle, dark: true) {
                            MacLockScreenDetailView(entry: entry, familyOverride: .accessoryCircular)
                        }
                        preview(width: 230, height: 32, shape: .capsule, dark: true) {
                            MacLockScreenDetailView(entry: entry, familyOverride: .accessoryInline)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section("Home Screen") {
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        preview(width: 158, height: 158, shape: .rect(cornerRadius: 22)) {
                            MacWidgetView(entry: entry, familyOverride: .systemSmall)
                        }
                        preview(width: 338, height: 158, shape: .rect(cornerRadius: 22)) {
                            MacWidgetView(entry: entry, familyOverride: .systemMedium)
                        }
                        preview(width: 158, height: 158, shape: .rect(cornerRadius: 22)) {
                            MacTelemetryWidgetView(entry: entry, familyOverride: .systemSmall)
                        }
                        preview(width: 338, height: 158, shape: .rect(cornerRadius: 22)) {
                            MacTelemetryWidgetView(entry: entry, familyOverride: .systemMedium)
                        }
                        preview(width: 338, height: 158, shape: .rect(cornerRadius: 22)) {
                            AllMacsWidgetView(entry: AllMacsEntry(date: .now, snapshots: allSnapshots), familyOverride: .systemMedium)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .topBlur()
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: prefs) {
            prefs.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private var snapshot: SharedSnapshot {
        guard let mac = store.selected, let reading = store.reading(for: mac), let status = reading.status else {
            return .sample()
        }
        return SharedSnapshot(macName: mac.name, status: status, reachable: reading.reachable)
    }

    private var allSnapshots: [SharedSnapshot] {
        let snapshots = store.macs.map {
            SharedSnapshot(macName: $0.name, status: store.reading(for: $0)?.status,
                           reachable: store.reading(for: $0)?.reachable ?? false)
        }
        return snapshots.isEmpty ? [.sample()] : snapshots
    }

    private func preview<S: Shape, Content: View>(width: CGFloat, height: CGFloat, shape: S, dark: Bool = false,
                                                  @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(dark ? 8 : 14)
            .frame(width: width, height: height)
            .background(dark ? AnyShapeStyle(.black.opacity(0.85)) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)), in: shape)
            .environment(\.colorScheme, dark ? .dark : colorScheme)
            .clipShape(shape)
    }
}
