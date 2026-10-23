import BattisticsRemote
import SwiftUI

@main
struct PhoneApp: App {
    @State private var store = MacStore.shared
    @State private var pairing = PairingFlow()
    @Environment(\.scenePhase) private var scenePhase

    init() { Notifications.register() }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(store)
                .environment(pairing)
                .onOpenURL { pairing.open($0) }
                .sheet(item: Binding(get: { pairing.candidate }, set: { pairing.candidate = $0 })) { candidate in
                    PairingSheet(pairing: candidate)
                        .environment(store)
                        .environment(pairing)
                }
                .alert("Pairing", isPresented: Binding(
                    get: { pairing.failure != nil && pairing.candidate == nil },
                    set: { if !$0 { pairing.failure = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(pairing.failure ?? "")
                }
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background, !store.macs.isEmpty { Notifications.schedule() }
        }
    }
}
