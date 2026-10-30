import Foundation

/// A controllable service that deliberately ignores cancellation. Every test
/// releases it, including after a timeout, so no continuation is left behind.
actor RemoteTestGate<Value: Sendable> {
    private var result: Value?
    private var waiters: [CheckedContinuation<Value, Never>] = []

    func value() async -> Value {
        if let result { return result }
        return await withCheckedContinuation { waiters.append($0) }
    }

    func finish(_ value: Value) {
        result = value
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume(returning: value) }
    }
}
