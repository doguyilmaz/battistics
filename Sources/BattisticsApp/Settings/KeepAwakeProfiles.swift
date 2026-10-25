import SwiftUI

struct KeepAwakeProfiles: View {
    @Environment(KeepAwakeModel.self) private var awake

    var body: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(KeepAwakeProfile.allCases) { profile in
                    ProfileTile(profile: profile) { awake.start(profile: profile) }
                }
            }
            .tourTarget(.profiles)
            .disabled(awake.isActive || awake.isChanging || awake.isAwaitingHelperApproval)
        } header: {
            InfoHeader("Ready-made profiles", info: "Profiles keep your battery and thermal protections. Stop the current session before starting another. Closed-lid mode is a separate choice.")
        }
    }
}

private struct ProfileTile: View {
    let profile: KeepAwakeProfile
    let start: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: start) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: profile.symbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(height: 22)
                Text(profile.title).fontWeight(.medium)
                Text(profile.duration.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.fill.opacity(hovering && isEnabled ? 0.9 : 0.5), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .help(profile.detail)
        .accessibilityLabel(String(localized: "Start \(profile.title)"))
        .accessibilityHint(profile.detail)
    }
}
