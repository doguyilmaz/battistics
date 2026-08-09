import Foundation
import IOKit.ps

/// Event-driven power source observation. macOS invokes the run loop source
/// on every power state change (each percent step, plug or unplug), so no
/// polling timer exists anywhere in the app while idle.
@MainActor
public final class PowerSourceMonitor {
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
        return stream
    }

    public func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        continuation?.finish()
        continuation = nil
    }
}
