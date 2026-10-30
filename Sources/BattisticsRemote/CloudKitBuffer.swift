import Foundation

/// Callback-local result storage. CloudKit callbacks and Swift task cancellation
/// may run on different queues; no callback or continuation runs under this lock.
final class CloudKitBuffer<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    func read() -> Value { lock.withLock { stored } }

    func update(_ body: (inout Value) -> Void) {
        lock.withLock { body(&stored) }
    }
}
