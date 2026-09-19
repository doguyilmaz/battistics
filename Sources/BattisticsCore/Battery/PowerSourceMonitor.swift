import Foundation
import IOKit.ps

/// Event-driven power source observation. macOS invokes the run loop source
/// on every power state change (each percent step, plug or unplug), so no
/// a low-frequency fallback catches delayed controller updates.
@MainActor
public final class PowerSourceMonitor {
    private var powerSourceNotification: CFRunLoopSource?
    private var refreshTimer: Timer?
    private var runLoopSource: CFRunLoopSource?
    private var continuation: AsyncStream<Void>.Continuation?

    public init() {}

    /// Starts observing and returns a stream that yields on every change.
    public func start() -> AsyncStream<Void> {
        stop()
        // Events request a fresh read; queued duplicates contain no state.
        let (stream, continuation) = AsyncStream.makeStream(
            of: Void.self, bufferingPolicy: .bufferingNewest(1))
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
        // Separate source events cover adapter transitions even when the
        // time estimate stays unchanged. Both callbacks run on the main loop.
        powerSourceNotification = IOPSCreateLimitedPowerNotification({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { _ = monitor.continuation?.yield() }
        }, context)?.takeRetainedValue()
        if let powerSourceNotification {
            CFRunLoopAddSource(CFRunLoopGetMain(), powerSourceNotification, .commonModes)
        }
        // Controller charging flags may settle after the source notification.
        // A cheap sensor tick keeps status fresh even when history is disabled.
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.continuation?.yield() }
        }
        timer.tolerance = 3
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        continuation.yield()
        return stream
    }

    public func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let powerSourceNotification {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceNotification, .commonModes)
        }
        powerSourceNotification = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        continuation?.finish()
        continuation = nil
    }
}
