import Foundation

public struct AutomationStatus: Codable, Sendable {
    public enum Owner: String, Codable, Sendable { case manual, thisClient = "this_client", anotherClient = "another_client" }
    public var active = false
    public var owner: Owner?
    /// Disclosed only to the connection that owns the session.
    public var sessionID: UUID?
    public var taskName: String?
    public var mode: String?
    public var deadline: Date?
    public var batteryPercent: Int?
    public var powerSource: String?
    public var stopAtBatteryPercent: Int?
    public var batteryWarningPercent: Int?
    public var stopOnThermalPressure = false
    public var closedLidAllowed = false
    public init() {}
}
