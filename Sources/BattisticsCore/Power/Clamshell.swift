import IOKit

/// The lid as the power manager sees it; readable without privileges.
public enum Clamshell {
    public struct State: Sendable, Equatable {
        public let isClosed: Bool
        /// False in clamshell mode with an external display and power.
        public let closingSleeps: Bool
    }

    public static func read() -> State? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(root) }
        func flag(_ key: String) -> Bool? {
            IORegistryEntryCreateCFProperty(root, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Bool
        }
        guard let closed = flag("AppleClamshellState") else { return nil }
        return State(isClosed: closed, closingSleeps: flag("AppleClamshellCausesSleep") ?? false)
    }
}
