import SwiftUI

struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
            VStack(spacing: 2) {
                Text("Battistics")
                    .font(.title2.weight(.semibold))
                Text("Version \(UpdatesSettings.versionString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Battery statistics for the Mac. Free and open source.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if let url = URL(string: "https://github.com/doguyilmaz/battistics") {
                    Link("GitHub", destination: url)
                }
                if let url = URL(string: "https://github.com/doguyilmaz/battistics/blob/main/LICENSE") {
                    Link("MIT License", destination: url)
                }
            }
            .font(.callout)
            Spacer()
            Text("Runs entirely on this Mac. The only network request is the optional update check.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 28)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
