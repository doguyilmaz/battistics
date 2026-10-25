import Foundation

public struct AutomationReply: Codable, Sendable {
    public struct Failure: Codable, Sendable {
        public let code: Code
        public let message: String
    }

    /// Sent as these strings; CLI and MCP clients match on them.
    public enum Code: String, Codable, Sendable {
        case unavailable, disabled, busy, inactive
        case invalidRequest = "invalid_request"
        case closedLidNotAllowed = "closed_lid_not_allowed"
        case helperUnavailable = "helper_unavailable"
        case startFailed = "start_failed"
        case notOwner = "not_owner"
    }
    public let status: AutomationStatus?
    public let error: Failure?

    public init(status: AutomationStatus) {
        self.status = status
        error = nil
    }

    public init(code: Code, message: String) {
        status = nil
        error = Failure(code: code, message: message)
    }
}
