import BattisticsRemote
import SwiftUI
import UIKit

struct PairingIntro: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "laptopcomputer.and.iphone")
                        .font(.system(size: 44)).foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Your Mac, from your pocket")
                        .font(.title2.weight(.semibold))
                    Text("See whether your Mac is awake, online and how long its battery lasts, and start or stop Keep Awake, even with the lid closed in a bag.")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Step(number: 1, text: String(localized: "Install Tailscale on this iPhone and on your Mac, signed in to the same account."))
                    Step(number: 2, text: String(localized: "On the Mac, open Battistics › iPhone, turn on access and choose Pair an iPhone."))
                    Step(number: 3, text: String(localized: "Scan the code with the Camera app and open the link in Battistics Remote."))
                }
                PasteLinkButton()
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private struct Step: View {
        let number: Int
        let text: String
        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(number)")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor, in: Circle())
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// For a link copied from the Mac instead of scanned.
struct PasteLinkButton: View {
    @Environment(PairingFlow.self) private var flow

    var body: some View {
        PasteButton(payloadType: String.self) { strings in
            guard let url = strings.first.flatMap(URL.init(string:)) else { return }
            Task { @MainActor in flow.open(url) }
        }
        .labelStyle(.titleAndIcon)
        .buttonBorderShape(.capsule)
    }
}

/// Holds a pairing link between opening it and confirming it.
@MainActor
@Observable
final class PairingFlow {
    var candidate: RemotePairing?
    var failure: String?
    var isPairing = false

    func open(_ url: URL) {
        guard let pairing = RemotePairing(url: url) else {
            failure = String(localized: "This is not a Battistics pairing link. Create a new one on the Mac.")
            return
        }
        failure = nil
        candidate = pairing
    }

    func confirm(_ store: MacStore) async {
        guard let candidate else { return }
        isPairing = true
        defer { isPairing = false }
        do {
            try await store.pair(candidate)
            self.candidate = nil
            await Notifications.requestPermission()
        } catch MacStore.PairingFailure.rejected(let message) {
            failure = message
        } catch {
            failure = String(localized: "Could not reach \(candidate.name). Check that Tailscale is on for both devices, then try again.")
        }
    }
}

struct PairingSheet: View {
    @Environment(MacStore.self) private var store
    @Environment(PairingFlow.self) private var flow
    @Environment(\.dismiss) private var dismiss
    let pairing: RemotePairing

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 52)).foregroundStyle(.tint)
                .accessibilityHidden(true)
                .padding(.top, 28)
            VStack(spacing: 6) {
                Text("Pair with \(pairing.name)?").font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                Text("This iPhone will see its battery and connection, and can start or stop Keep Awake.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Label(pairing.host, systemImage: pairing.isTailscaleHost ? "lock.shield" : "exclamationmark.shield")
                .font(.footnote.monospaced())
                .foregroundStyle(pairing.isTailscaleHost ? Color.secondary : Color.orange)
            if !pairing.isTailscaleHost {
                Text("This address is not on Tailscale. Pair only with a code shown by Battistics on your own Mac.")
                    .font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
            if let failure = flow.failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                Task { await flow.confirm(store) }
            } label: {
                Group {
                    if flow.isPairing { ProgressView() } else { Text("Pair") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(flow.isPairing)
            Button("Cancel") {
                flow.failure = nil
                flow.candidate = nil
            }
                .disabled(flow.isPairing)
        }
        .padding(24)
        .presentationDetents([.medium])
        .interactiveDismissDisabled(flow.isPairing)
    }
}
