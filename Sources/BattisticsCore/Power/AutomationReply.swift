import Foundation

public struct AutomationReply: Codable, Sendable {
    public struct Failure: Codable, Sendable {
        public let code: String
        public let message: String
    }
    public let status: AutomationStatus?
    public let error: Failure?

    public init(status: AutomationStatus) {
        self.status = status
        error = nil
    }

    public init(code: String, message: String) {
        status = nil
        error = Failure(code: code, message: message)
    }
}
