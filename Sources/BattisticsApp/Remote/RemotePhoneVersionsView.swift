import BattisticsRemote
import SwiftUI

struct RemotePhoneVersionsView: View {
    let phones: [RemotePhoneInfo]

    var body: some View {
        LabeledContent("This Mac", value: RemoteAppInfo.current(minimumPeerVersion: RemoteCompatibility.minimumPhone)?.displayVersion ?? "—")
        if phones.isEmpty {
            Text("No iPhone app version received yet. Open Battistics Remote on your iPhone with the same Apple Account. Older apps may not share version information.")
                .foregroundStyle(.secondary)
        }
        ForEach(phones) { phone in
            VStack(alignment: .leading, spacing: 5) {
                LabeledContent(phone.name, value: phone.app.displayVersion)
                Text(RemoteCompatibility.message(peer: phone.app, name: phone.name, appName: "Battistics Remote", localAppName: "Battistics",
                    local: .current(minimumPeerVersion: RemoteCompatibility.minimumPhone), minimum: RemoteCompatibility.minimumPhone))
                    .font(.caption).foregroundStyle(.secondary)
                Text("Last reported \(phone.seenAt, style: .relative) ago")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        Text("Nearby connections require Battistics Remote 1.1.0 or later. Version information is the last report received through your private iCloud; it does not mean the phone is online.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
