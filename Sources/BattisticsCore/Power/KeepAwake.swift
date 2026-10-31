import Foundation

/// What "keep awake" should actually prevent. Each maps to one IOKit
/// assertion type; an assertion's type is fixed at creation, so switching
/// mode means releasing and re-taking it.
public enum KeepAwakeMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Screen stays lit. The system cannot idle-sleep while it is. (`caffeinate -d`)
    case displayOn
    /// Screen may go dark, the machine keeps running. (`caffeinate -i`)
    case displayMaySleep
    /// Idle assertion paired with the privileged helper’s closed-lid lease.
    case lidClosed

    public var id: String { rawValue }

    /// IOKit assertion type name. Spelled out rather than referencing the
    /// `kIOPMAssertionType*` constants so this stays free of an IOKit import
    /// and testable; the strings are the constants' documented values.
    public var assertionType: String {
        switch self {
        case .displayOn: "PreventUserIdleDisplaySleep"
        case .displayMaySleep: "PreventUserIdleSystemSleep"
        case .lidClosed: "PreventUserIdleSystemSleep"
        }
    }
}

/// How long to stay awake. The raw value is the duration in minutes, which
/// makes persisting a choice a single integer; 0 means "until turned off".
public enum KeepAwakeDuration: Int, Codable, Sendable, CaseIterable, Identifiable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case fourHours = 240
    case sixHours = 360
    case twelveHours = 720
    case indefinite = 0

    public var id: Int { rawValue }

    public var minutes: Int? {
        self == .indefinite ? nil : rawValue
    }

    /// What automation may ask for: never open-ended.
    public static let finite = allCases.filter { $0 != .indefinite }
}

/// An active keep-awake session. Pure: the deadline is fixed when the
/// session starts or is extended, never tracked by a ticking timer, so a
/// throttled or suspended app can always recompute the truth.
public struct KeepAwakeSession: Codable, Sendable, Equatable {
    public let mode: KeepAwakeMode
    public let duration: KeepAwakeDuration
    public let startedAt: Date
    public let deadline: Date?

    /// The longest a session may still have left after an extension.
    public static let maximumRemaining: TimeInterval = 12 * 3600

    public init(mode: KeepAwakeMode, duration: KeepAwakeDuration, startedAt: Date) {
        self.mode = mode
        self.duration = duration
        self.startedAt = startedAt
        deadline = duration.minutes.map { startedAt.addingTimeInterval(TimeInterval($0) * 60) }
    }

    private init(_ session: KeepAwakeSession, mode: KeepAwakeMode? = nil, deadline: Date?) {
        self.mode = mode ?? session.mode
        duration = session.duration
        startedAt = session.startedAt
        self.deadline = deadline
    }

    /// The same session, same deadline, in another mode.
    public func switching(to mode: KeepAwakeMode) -> KeepAwakeSession {
        KeepAwakeSession(self, mode: mode, deadline: deadline)
    }

    /// The same session ending later, capped at twelve hours from now. Nil
    /// for a session without a deadline or one already at the cap.
    public func extended(byMinutes minutes: Int, now: Date) -> KeepAwakeSession? {
        guard minutes > 0, let deadline else { return nil }
        let capped = min(max(deadline, now).addingTimeInterval(TimeInterval(minutes) * 60),
                         now.addingTimeInterval(Self.maximumRemaining))
        guard capped > deadline else { return nil }
        return KeepAwakeSession(self, deadline: capped)
    }

    /// Seconds left, floored at zero; nil when the session has no deadline.
    public func remaining(at now: Date) -> TimeInterval? {
        deadline.map { max($0.timeIntervalSince(now), 0) }
    }

    public func hasExpired(at now: Date) -> Bool {
        guard let deadline else { return false }
        return now >= deadline
    }
}

/// A running session carried across the app's relaunch for an update. The
/// two clocks tell whether the Mac slept or restarted in between: uptime
/// stops while the Mac sleeps and starts over at boot, wall time does not.
public struct KeepAwakeHandover: Codable, Sendable, Equatable {
    public enum Outcome: Sendable, Equatable { case resume, expired, slept, stale }

    public let session: KeepAwakeSession
    public let origin: String
    public let name: String?
    public let savedAt: Date
    public let uptime: TimeInterval

    /// An update relaunch takes seconds; anything slower was not one.
    public static let window: TimeInterval = 120

    public init(session: KeepAwakeSession, origin: String, name: String?, savedAt: Date, uptime: TimeInterval) {
        self.session = session
        self.origin = origin
        self.name = name
        self.savedAt = savedAt
        self.uptime = uptime
    }

    public func outcome(now: Date, uptime currentUptime: TimeInterval) -> Outcome {
        let elapsed = now.timeIntervalSince(savedAt)
        let awake = currentUptime - uptime
        if awake < 0 || elapsed - awake > 5 { return .slept }
        if session.hasExpired(at: now) { return .expired }
        return elapsed < 0 || elapsed > Self.window ? .stale : .resume
    }
}
