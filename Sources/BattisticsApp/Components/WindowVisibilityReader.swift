import AppKit
import SwiftUI

/// Event-driven visibility for tasks whose work is only useful onscreen.
/// SwiftUI can retain a window's views after it closes or is minimized.
struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onChange = { visible in
            if isVisible != visible { isVisible = visible }
        }
        return view
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {}

    final class TrackerView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observerToken: ObserverToken?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observerToken = nil
            // Attaching an NSView can happen during a SwiftUI update. Read
            // the current window when delivered, so a move cannot publish
            // an earlier window's visibility after the view has detached.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onChange?(self.window?.occlusionState.contains(.visible) ?? false)
            }
            guard let window else { return }
            let token = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window, queue: .main
            ) { [weak self, weak window] _ in
                DispatchQueue.main.async {
                    guard let self, let window, self.window === window else { return }
                    self.onChange?(window.occlusionState.contains(.visible))
                }
            }
            observerToken = ObserverToken(token)
        }
    }

    private final class ObserverToken: @unchecked Sendable {
        private let token: any NSObjectProtocol

        init(_ token: any NSObjectProtocol) {
            self.token = token
        }

        deinit {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
