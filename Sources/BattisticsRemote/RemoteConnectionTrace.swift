import CloudKit
import Foundation

/// Small, local-only breadcrumbs. Never retain payloads, record identifiers,
/// account identifiers, localized error descriptions or error userInfo.
final class RemoteConnectionTrace: Sendable {
    enum Phase: String, Sendable {
        case query = "query"
        case zoneSetup = "zone-setup"
        case recordRead = "record-read"
        case recordWrite = "record-write"
        case subscriptionRead = "subscription-read"
        case subscriptionWrite = "subscription-write"
    }

    enum Event {
        case started, finished
        case item(Result<Void, Error>)
        case failed(Error)
    }

    private let started = ContinuousClock.now
    private let entries = CloudKitBuffer<[String]>([])
    private static let limit = 20

    func record(_ event: Event, phase: Phase, id: String) {
        let elapsed = started.duration(to: .now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        let detail: String
        switch event {
        case .started: detail = "started"
        case .finished: detail = "finished"
        case .item(.success): detail = "item-ready"
        case .item(.failure(let error)): detail = "item-failed " + Self.describe(error)
        case .failed(let error): detail = "failed " + Self.describe(error)
        }
        let line = String(format: "t=%.3fs", seconds) + " \(phase.rawValue) \(id.prefix(8)) \(detail)"
        entries.update {
            $0.append(line)
            if $0.count > Self.limit { $0.removeFirst($0.count - Self.limit) }
        }
    }

    func report() -> String {
        let elapsed = started.duration(to: .now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        return String(format: "clock=%.3fs\n", seconds) + entries.read().joined(separator: "\n")
    }

    private static func describe(_ error: Error) -> String {
        let kind = error is RemoteDeadline.Failure ? "deadline" : error is CancellationError ? "cancelled" : "framework"
        let ns = error as NSError
        let retry = (error as? CKError)?.retryAfterSeconds ?? 0
        return "\(kind) \(ns.domain)/\(ns.code) retry=\(retry)s"
    }
}
