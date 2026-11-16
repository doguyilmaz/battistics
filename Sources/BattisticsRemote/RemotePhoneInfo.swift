import Foundation

/// Last observed app metadata; this is not a phone-online signal or a credential.
public struct RemotePhoneInfo: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var app: RemoteAppInfo
    public var seenAt: Date

    public init(id: String, name: String, app: RemoteAppInfo, seenAt: Date = .now) {
        self.id = id
        self.name = String(name.prefix(64))
        self.app = app
        self.seenAt = seenAt
    }

    public var isValid: Bool { UUID(uuidString: id) != nil && !name.isEmpty && name.count <= 64 && app.isValid }
}
