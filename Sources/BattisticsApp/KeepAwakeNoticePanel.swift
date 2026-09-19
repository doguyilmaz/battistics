import AppKit

/// A status notice must never steal typing focus from another app.
final class KeepAwakeNoticePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
