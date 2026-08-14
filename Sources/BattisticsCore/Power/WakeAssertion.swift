import Foundation
import IOKit.pwr_mgt

/// Holds a single IOKit power assertion.
///
/// Mechanics only: every decision about modes, durations and expiry lives in
/// `KeepAwakeSession`, which is pure and tested. An assertion's type is fixed
/// at creation, so changing mode means releasing and taking a new one.
///
/// Not `Sendable` on purpose; callers keep it on one actor.
public final class WakeAssertion {
    private var identifier: IOPMAssertionID = IOPMAssertionID(0)
    private var isHeld = false

    public init() {}

    public var isActive: Bool { isHeld }

    /// Takes an assertion for `mode`, replacing any current one. When
    /// `deadline` is set the kernel is given the timeout too, so the
    /// assertion cannot outlive it even if this process is suspended and
    /// never gets to release it itself.
    @discardableResult
    public func take(mode: KeepAwakeMode, until deadline: Date?, now: Date = Date()) -> Bool {
        release()

        var properties: [String: Any] = [
            kIOPMAssertionTypeKey as String: mode.assertionType,
            kIOPMAssertionNameKey as String: "Battistics Keep Awake",
            kIOPMAssertionLevelKey as String: kIOPMAssertionLevelOn,
        ]
        if let deadline {
            let seconds = max(deadline.timeIntervalSince(now), 1)
            properties[kIOPMAssertionTimeoutKey as String] = seconds as CFNumber
            properties[kIOPMAssertionTimeoutActionKey as String] =
                kIOPMAssertionTimeoutActionRelease
        }

        var newIdentifier = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithProperties(
            properties as CFDictionary, &newIdentifier)
        guard result == kIOReturnSuccess else { return false }
        identifier = newIdentifier
        isHeld = true
        return true
    }

    public func release() {
        guard isHeld else { return }
        IOPMAssertionRelease(identifier)
        isHeld = false
        identifier = IOPMAssertionID(0)
    }

    // Assertions are owned by the process and the kernel drops them when it
    // exits, so this only matters for a controller released mid-run.
    deinit {
        if isHeld { IOPMAssertionRelease(identifier) }
    }
}
