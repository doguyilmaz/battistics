import Foundation

/// App versions and the peer version required for this build's nearby protocol.
public struct RemoteAppInfo: Codable, Equatable, Sendable {
    public var version: String
    public var build: String
    public var minimumPeerVersion: String
    public var nearbyProtocol: Int?

    public init(version: String, build: String, minimumPeerVersion: String, nearbyProtocol: Int? = 1) {
        self.version = version
        self.build = build
        self.minimumPeerVersion = minimumPeerVersion
        self.nearbyProtocol = nearbyProtocol
    }

    public static func current(minimumPeerVersion: String, bundle: Bundle = .main) -> Self? {
        guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String else { return nil }
        return Self(version: version, build: build, minimumPeerVersion: minimumPeerVersion)
    }

    public var displayVersion: String { "\(version) (\(build))" }

    /// Nil means the peer did not supply a recognizable SemVer, not outdated.
    public func needsUpdate(for minimum: String) -> Bool? {
        guard let installed = Self.components(version), let required = Self.components(minimum) else { return nil }
        return installed.lexicographicallyPrecedes(required)
    }

    public var isValid: Bool {
        Self.components(version) != nil && Self.components(minimumPeerVersion) != nil &&
        !build.isEmpty && build.count <= 20 && build.allSatisfy(\.isNumber)
    }

    private static func components(_ value: String) -> [Int]? {
        guard value.count <= 32 else { return nil }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == 3 ? numbers : nil
    }
}
