import Foundation
import Darwin
import IOKit.ps

/// Event-driven power source observation. macOS invokes the run loop source
/// on every power state change (each percent step, plug or unplug), so no
/// polling timer exists anywhere in the app while idle.
@MainActor
public final class PowerSourceMonitor {
    private var powerSourceToken: Int32?
    private var runLoopSource: CFRunLoopSource?
    private var continuation: AsyncStream<Void>.Continuation?

    public init() {}

    /// Starts observing and returns a stream that yields on every change.
    public func start() -> AsyncStream<Void> {
        stop()
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        self.continuation = continuation

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(
            { context in
                guard let context else { return }
                let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
                // The source is scheduled on the main run loop, so the
                // callback always arrives on the main thread.
                MainActor.assumeIsolated {
                    _ = monitor.continuation?.yield()
                }
            }, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        // The run-loop source tracks time estimates, which need not change
        // when charging pauses/resumes on AC. Also observe all source updates.
        var token: Int32 = 0
        let status = notify_register_dispatch(kIOPSNotifyAnyPowerSource, &token, .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.continuation?.yield() }
        }
        if status == NOTIFY_STATUS_OK { powerSourceToken = token }
        continuation.yield()
        return stream
    }

    public func stop() {
        if let powerSourceToken { notify_cancel(powerSourceToken) }
        powerSourceToken = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        continuation?.finish()
        continuation = nil
    }
}
