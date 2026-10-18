import Foundation

/// Private, versioned IPC between the app and its bundled MCP executable.
public struct AutomationRequest: Codable, Sendable {
    public enum Operation: String, Codable, Sendable { case status, start, stop, heartbeat }
    public var version = 1
    public var operation: Operation
    public var name: String?
    public var mode: String?
    public var durationMinutes: Int?
    public var sessionID: UUID?

    public init(_ operation: Operation, name: String? = nil, mode: String? = nil,
                durationMinutes: Int? = nil, sessionID: UUID? = nil) {
        self.operation = operation
        self.name = name
        self.mode = mode
        self.durationMinutes = durationMinutes
        self.sessionID = sessionID
    }

    public func validatedStart() -> (name: String, mode: KeepAwakeMode, duration: KeepAwakeDuration)? {
        guard version == 1, operation == .start, let name,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 80, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let durationMinutes, durationMinutes > 0,
              let duration = KeepAwakeDuration(rawValue: durationMinutes),
              let mode = KeepAwakeMode(rawValue: mode ?? KeepAwakeMode.displayMaySleep.rawValue)
        else { return nil }
        return (name.trimmingCharacters(in: .whitespaces), mode, duration)
    }
}
