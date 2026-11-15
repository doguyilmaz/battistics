import Foundation

public struct RemoteRoute: Sendable {
    public enum Kind: Sendable { case lan, bluetooth }
    public let kind: Kind
    public let execute: @Sendable (RemoteRequest, ContinuousClock.Instant) async throws -> RemoteStatus

    public init(kind: Kind, execute: @escaping @Sendable (RemoteRequest, ContinuousClock.Instant) async throws -> RemoteStatus) {
        self.kind = kind
        self.execute = execute
    }
}
