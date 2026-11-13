import Foundation

/// The Mac saves the latch and pending events together before sending.
/// Relaunching cannot repeat a sent warning or lose an unsent one.
public struct RemoteAlertOutbox: Codable, Sendable, Equatable {
    private var state = RemoteAlertState()
    public private(set) var pending: [RemoteAlertEvent] = []

    public init() {}

    public mutating func record(from previous: RemoteStatus?, to current: RemoteStatus) {
        let candidates = previous.map { RemoteAlert.pushed(from: $0, to: current) } ?? []
        let alerts = state.filter(candidates, status: current)
        pending.removeAll { !$0.isRelevant(to: current) }
        pending += alerts.map { RemoteAlertEvent(alert: $0, status: current) }
    }

    public mutating func acknowledge(_ id: String) {
        pending.removeAll { $0.id == id }
    }
}
