import SwiftUI

struct KeepAwakeProfiles: View {
    @Environment(KeepAwakeModel.self) private var awake

    var body: some View {
        Section("Ready-made profiles") {
            ForEach(KeepAwakeProfile.allCases) { profile in
                HStack(alignment: .top) {
                    Image(systemName: profile.symbol).frame(width: 22).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.title).fontWeight(.medium)
                        Text(profile.detail).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Button("Start") { awake.start(profile: profile) }
                        .accessibilityLabel(String(localized: "Start \(profile.title)"))
                }
                .tourTarget(profile == .aiFocus ? .profiles : nil)
            }
            .disabled(awake.isActive || awake.isChanging || awake.isAwaitingHelperApproval)
            Text("Profiles keep your battery and thermal protections. Stop the current session before starting another. Closed-lid mode is a separate choice.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
