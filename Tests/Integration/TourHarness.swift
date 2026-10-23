import AppKit
import BattisticsCore
import Observation
import SwiftUI

extension Notification.Name {
    static let battisticsSelectPane = Notification.Name("battisticsSelectPane")
}

@main
@MainActor
struct TourHarness {
    @Observable final class Probe {
        var frames: [TourStep: CGRect] = [:]
    }

    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        // SwiftUI builds its accessibility tree only after an accessibility client opts in.
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        Task { @MainActor in
            do { try await exercise(); exit(0) }
            catch { FileHandle.standardError.write(Data("Tour test failed: \(error)\n".utf8)); exit(1) }
        }
        NSApp.run()
    }

    private static func exercise() async throws {
        UserDefaults.standard.setVolatileDomain([
            Prefs.hasSeenTour: true, Prefs.powerSamplingEnabled: false,
            Prefs.automationEnabled: false, Prefs.alertLowEnabled: false,
            Prefs.alertHealthDropEnabled: false, Prefs.alertHighTempEnabled: false,
        ], forName: UserDefaults.argumentDomain)
        Prefs.registerDefaults()
        let directory = URL(fileURLWithPath: "/private/tmp/battistics-tour-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(historyDirectory: directory, batteryProvider: { battery })
        let helper = PowerHelperClient()
        let awake = KeepAwakeModel(helper: helper)
        let automation = AutomationModel(awake: awake, helper: helper, initiallyEnabled: false)
        let protection = awake.safety.configuration
        let probe = Probe()
        let host = NSHostingView(rootView: DashboardView()
            .environment(model).environment(awake).environment(helper).environment(automation)
            .environment(PowerSettingsModel()).environment(PowerAuthorization()).environment(NetworkMonitor())
            .background(Color(nsColor: .windowBackgroundColor))
            .overlayPreferenceValue(TourTargetPreference.self) { anchors in
                GeometryReader { geometry in
                    let frames = anchors.mapValues { geometry[$0] }
                    Color.clear.onChange(of: frames, initial: true) { probe.frames = frames }
                }.allowsHitTesting(false)
            })
        host.frame = NSRect(x: 0, y: 0, width: 860, height: 545)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        model.tourRequested = true
        var nextFrame: CGRect?
        for step in TourStep.allCases {
            try await settle()
            precondition(model.dashboardPane == step.pane, "Wrong pane for \(step)")
            let target = try require(probe.frames[step])
            let card = try find("tour.card", in: host)
            let cardFrame = try require(attribute(card, "accessibilityFrame") as? NSValue).rectValue
            precondition(cardFrame.height < 180, "Tour card has unnecessary empty space: \(cardFrame)")
            if step == .power {
                precondition(target.height > 60, "Power focus must include switch, mode and duration: \(target)")
            }
            precondition(target.minY >= 0 && target.maxY < 545 - cardFrame.height - 20,
                         "Target obscured for \(step): \(target)")
            let button = try find("tour.next", in: host)
            let frame = try require(attribute(button, "accessibilityFrame") as? NSValue).rectValue
            precondition(frame.height > 0 && window.frame.contains(frame), "Next outside window")
            if let nextFrame { precondition(abs(frame.minY - nextFrame.minY) < 1, "Next moved between steps") }
            else { nextFrame = frame }
            try capture(host, step: step)
            precondition(!awake.isActive && awake.safety.configuration == protection && !automation.enabled)
            if step == .power {
                let scroll = try require(scrollViews(in: host).first {
                    $0.convert($0.bounds, to: host).minX >= 180
                        && ($0.documentView?.frame.height ?? 0) > $0.contentSize.height + 100
                })
                scroll.contentView.scroll(to: CGPoint(x: 0, y: scroll.documentView!.frame.height - scroll.contentSize.height))
                scroll.reflectScrolledClipView(scroll.contentView)
                try await settle()
                let afterScroll = try find("tour.next", in: host)
                let afterFrame = try require(attribute(afterScroll, "accessibilityFrame") as? NSValue).rectValue
                precondition(afterFrame == frame, "Scrolling moved tour navigation")
            }
            try press(button)
        }
        try await settle()
        precondition(!model.tourRequested, "Done did not end tour")
        model.tourRequested = true
        try await settle()
        precondition(model.dashboardPane == .overview)
        try sendKey("\r", code: 36, to: window)
        try await settle()
        precondition(model.dashboardPane == .system)
        let backButton = try find("tour.back", in: host)
        try press(backButton)
        try await settle()
        precondition(model.dashboardPane == .overview)
        let skipButton = try find("tour.skip", in: host)
        try press(skipButton)
        try await settle()
        precondition(!model.tourRequested)
        model.tourRequested = true
        try await settle()
        try sendKey("\u{1b}", code: 53, to: window)
        try await settle()
        precondition(!model.tourRequested, "Escape did not dismiss tour")
        // The live session card above Keep Awake must not push step 2 out of view.
        await awake.start(mode: .displayMaySleep, duration: .fifteenMinutes)?.value
        defer { awake.stop() }
        precondition(awake.isActive)
        model.tourRequested = true
        try await settle()
        try press(find("tour.next", in: host))
        try await settle()
        let activeTarget = try require(probe.frames[.power])
        let activeCard = try find("tour.card", in: host)
        let activeCardHeight = try require(attribute(activeCard, "accessibilityFrame") as? NSValue).rectValue.height
        precondition(activeTarget.height > 100 && activeTarget.minY >= 0
                     && activeTarget.maxY < 545 - activeCardHeight - 20,
                     "Active session obscures Power focus: \(activeTarget)")
        try capture(host, step: .power, suffix: "-active")
        precondition(awake.isActive, "Tour changed the running session")
        window.close()
        print("PASS: visible targets, pinned controls during scroll, Next/Back/Done/Skip/replay, Return/Escape, settings unchanged")
    }

    private static func find(_ identifier: String, in root: Any) throws -> NSObject {
        if let element = root as? NSObject {
            if attribute(element, "accessibilityIdentifier") as? String == identifier { return element }
            for child in attribute(element, "accessibilityChildren") as? [Any] ?? [] {
                if let match = try? find(identifier, in: child) { return match }
            }
        }
        throw CocoaError(.coderValueNotFound, userInfo: [NSLocalizedDescriptionKey: "Missing \(identifier)"])
    }

    private static func attribute(_ element: NSObject, _ name: String) -> Any? {
        guard element.responds(to: NSSelectorFromString(name)) else { return nil }
        return element.value(forKey: name)
    }

    private static func press(_ element: NSObject) throws {
        // SwiftUI's AX nodes implement these selectors without adopting NSAccessibilityProtocol.
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard element.responds(to: selector) else { throw CocoaError(.featureUnsupported) }
        typealias Action = @convention(c) (AnyObject, Selector) -> Bool
        let action = unsafeBitCast(element.method(for: selector), to: Action.self)
        precondition(action(element, selector), "Accessibility press failed")
    }

    private static func settle() async throws { try await Task.sleep(for: .milliseconds(300)) }

    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }

    private static func sendKey(_ characters: String, code: UInt16, to window: NSWindow) throws {
        let event = try require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code))
        NSApp.sendEvent(event)
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw CocoaError(.coderValueNotFound) }
        return value
    }

    private static func capture(_ host: NSView, step: TourStep, suffix: String = "") throws {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let path = "/private/tmp/battistics-tour-\(language)-\(step.rawValue)\(suffix).png"
        if ProcessInfo.processInfo.environment["BATTISTICS_TOUR_SCREENSHOTS"] == "1",
           let window = host.window {
            // Window-server capture includes the live material backdrop blur.
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String(window.windowNumber), path]
            try capture.run()
            capture.waitUntilExit()
            precondition(capture.terminationStatus == 0, "Window screenshot failed")
            return
        }
        host.layoutSubtreeIfNeeded()
        let bitmap = try require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try require(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: path))
    }

    private static var battery: BatterySnapshot {
        BatterySnapshot(timestamp: Date(), batteryInstalled: true, percent: 80,
            rawCurrentCapacity: 4800, rawMaxCapacity: 6000, nominalCapacity: nil,
            designCapacity: 6500, cycleCount: 100, designCycleCount: 1000,
            temperatureC: 30, voltageMV: nil, amperageMA: nil,
            isCharging: false, externalConnected: true, fullyCharged: false,
            avgTimeToEmptyMin: nil, avgTimeToFullMin: nil, systemTimeRemainingMin: nil,
            systemHealthStatus: nil, serialNumber: nil, deviceName: nil,
            manufactureDate: nil, adapter: nil)
    }
}
