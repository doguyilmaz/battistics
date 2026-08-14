import Foundation

/// What "keep awake" should actually prevent. Each maps to one IOKit
/// assertion type; an assertion's type is fixed at creation, so switching
/// mode means releasing and re-taking it.
public enum KeepAwakeMode: String, Sendable, CaseIterable, Identifiable {
    /// Screen stays lit. The system cannot idle-sleep while it is. (`caffeinate -d`)
    case displayOn
    /// Screen may go dark, the machine keeps running. (`caffeinate -i`)
    case displayMaySleep
    /// Stays awake with the lid shut. (`caffeinate -s`)
    case lidClosed

    public var id: String { rawValue }

    /// IOKit assertion type name. Spelled out rather than referencing the
    /// `kIOPMAssertionType*` constants so this stays free of an IOKit import
    /// and testable; the strings are the constants' documented values.
    public var assertionType: String {
        switch self {
        case .displayOn: "PreventUserIdleDisplaySleep"
        case .displayMaySleep: "PreventUserIdleSystemSleep"
        case .lidClosed: "PreventSystemSleep"
        }
    }

    /// macOS ignores `PreventSystemSleep` on battery, so the UI has to say
    /// so rather than let the user pick a mode that silently does nothing.
    public var requiresExternalPower: Bool {
        self == .lidClosed
    }
}

/// How long to stay awake. The raw value is the duration in minutes, which
/// makes persisting a choice a single integer; 0 means "until turned off".
public enum KeepAwakeDuration: Int, Sendable, CaseIterable, Identifiable {
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
}

/// An active keep-awake session. Pure: the deadline is derived, never
/// tracked by a ticking timer, so a throttled or suspended app can always
/// recompute the truth from `startedAt`.
public struct KeepAwakeSession: Sendable, Equatable {
    public let mode: KeepAwakeMode
    public let duration: KeepAwakeDuration
    public let startedAt: Date

    public init(mode: KeepAwakeMode, duration: KeepAwakeDuration, startedAt: Date) {
        self.mode = mode
        self.duration = duration
        self.startedAt = startedAt
    }

    public var deadline: Date? {
        duration.minutes.map { startedAt.addingTimeInterval(TimeInterval($0) * 60) }
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
