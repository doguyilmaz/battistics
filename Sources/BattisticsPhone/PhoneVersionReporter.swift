import BattisticsRemote
import Foundation

/// Publishes only after an actual foreground iCloud read. Silent pushes never
/// echo another write, and failed reports do not block battery data or controls.
@MainActor
final class PhoneVersionReporter {
    private var work: Task<Void, Never>?
    private var reported: [String: Date] = [:]
    private var generation = 0
    private let id: String

    init(defaults: UserDefaults = .standard) {
        let saved = defaults.string(forKey: "remotePhoneInstallationID")
        id = saved.flatMap { UUID(uuidString: $0)?.uuidString } ?? UUID().uuidString
        defaults.set(id, forKey: "remotePhoneInstallationID")
    }

    func report(to macIDs: [String], name: String, cloud: RemoteCloud) {
        guard work == nil, let app = RemoteAppInfo.current(minimumPeerVersion: RemoteCompatibility.minimumMac) else { return }
        let due = Array(macIDs.filter { reported[$0].map { -$0.timeIntervalSinceNow >= 300 } ?? true }.sorted().prefix(8))
        guard !due.isEmpty else { return }
        let phone = RemotePhoneInfo(id: id, name: name, app: app)
        let generation = self.generation
        work = Task { [weak self] in
            defer { if self?.generation == generation { self?.work = nil } }
            let epoch = await cloud.accountEpoch()
            do { _ = try await cloud.accountIdentity() } catch { return }
            for macID in due {
                guard !Task.isCancelled, self?.generation == generation else { return }
                do {
                    try await cloud.reportPhone(phone, to: macID, accountEpoch: epoch)
                    guard !Task.isCancelled, self?.generation == generation else { return }
                    self?.reported[macID] = .now
                } catch {}
            }
        }
    }

    func pause() {
        generation += 1
        work?.cancel()
        work = nil
    }

    func reset() {
        pause()
        reported = [:]
    }
}
