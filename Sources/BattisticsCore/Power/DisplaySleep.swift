import Foundation

public enum DisplaySleep {
    /// Turns the display off now; needs no privileges.
    public static func now() async throws {
        _ = try await BoundedCommand.run(executable: PowerSettingsWriter.executable, arguments: ["displaysleepnow"],
                                         timeout: 5, maximumOutputBytes: 16_384)
    }
}
