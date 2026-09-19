import AppKit
import CoreGraphics

@MainActor
final class KeepAwakeNoticeController {
    private var panel: KeepAwakeNoticePanel?
    private var lastNoticedSessionID: String?
    private var pendingMessage: String?
    private var suspended = false
    private var screenLocked = false
    private var sessionInactive = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenObservers: [NSObjectProtocol] = []

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.sessionInactive = true
                self?.deferVisibleNotice()
            }
        })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.sessionInactive = false
                self?.presentPendingNotice()
            }
        })
        // These system notifications cover screen locking without asking for
        // notification permission or polling the foreground application.
        let distributed = DistributedNotificationCenter.default()
        screenObservers.append(distributed.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.screenLocked = true
                self?.deferVisibleNotice()
            }
        })
        screenObservers.append(distributed.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.screenLocked = false
                self?.presentPendingNotice()
            }
        })
    }

    func show(sessionID: String, message: String) {
        guard lastNoticedSessionID != sessionID else { return }
        lastNoticedSessionID = sessionID
        panel?.close()
        panel = nil
        suspended = false
        pendingMessage = message
        presentPendingNotice()
    }

    func dismiss() {
        pendingMessage = nil
        suspended = false
        panel?.close()
        panel = nil
    }

    private func deferVisibleNotice() {
        // Keep the same notice for unlock; never create another notice for
        // the same stopped session. A manually closed panel stays closed.
        if panel?.isVisible == true {
            suspended = true
            panel?.orderOut(nil)
        }
    }

    private func presentPendingNotice() {
        guard !screenLocked, !sessionInactive,
            let session = CGSessionCopyCurrentDictionary() as? [String: Any],
            session[kCGSessionOnConsoleKey as String] as? Bool == true else { return }
        if let panel, suspended {
            suspended = false
            panel.orderFrontRegardless()
            return
        }
        guard let message = pendingMessage else { return }
        let detailFont = NSFont.systemFont(ofSize: 13)
        let detailBounds = (message as NSString).boundingRect(
            with: NSSize(width: 366, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: detailFont])
        let contentHeight = max(134, ceil(detailBounds.height) + 68)
        let panel = KeepAwakeNoticePanel(
            contentRect: NSRect(x: 0, y: 0, width: 410, height: contentHeight),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered, defer: false)
        panel.title = "Battistics"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let title = NSTextField(labelWithString: String(localized: "Keep Awake stopped"))
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: message)
        detail.font = detailFont
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 0
        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 8
        text.translatesAutoresizingMaskIntoConstraints = false
        if let content = panel.contentView {
            content.addSubview(text)
            NSLayoutConstraint.activate([
                detail.widthAnchor.constraint(equalTo: text.widthAnchor),
                text.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
                text.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
                text.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
                text.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16),
            ])
        }
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: visible.maxX - panel.frame.width - 24, y: visible.maxY - 24))
        }
        self.panel = panel
        pendingMessage = nil
        panel.orderFrontRegardless()
    }
}
