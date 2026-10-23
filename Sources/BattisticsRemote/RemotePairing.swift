import CryptoKit
import Foundation

/// What the Mac's QR code carries. The phone keeps it in its Keychain; the Mac
/// keeps only the token's hash.
public struct RemotePairing: Codable, Sendable, Equatable, Identifiable {
    public var id: String { token }
    public var name: String
    public var host: String
    public var port: UInt16
    public var token: String

    public init(name: String, host: String, port: UInt16, token: String) {
        self.name = name
        self.host = host
        self.port = port
        self.token = token
    }

    public static let scheme = "battistics-remote"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "pair"
        components.queryItems = [
            .init(name: "n", value: name), .init(name: "h", value: host),
            .init(name: "p", value: String(port)), .init(name: "t", value: token),
        ]
        return components.url!
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme, url.host == "pair",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let name = value("n"), (1...64).contains(name.count),
              let host = value("h"), Self.isValidHost(host),
              let port = value("p").flatMap(UInt16.init), port > 0,
              let token = value("t"), Self.isValidToken(token) else { return nil }
        self.init(name: name, host: host, port: port, token: token)
    }

    /// 32 random bytes, base64url without padding.
    public static func makeToken() -> String {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0) }.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Compares every byte so the time taken does not reveal a matching prefix.
    public static func matches(_ token: String, hash expected: String) -> Bool {
        let actual = Array(hash(token).utf8), wanted = Array(expected.utf8)
        guard actual.count == wanted.count else { return false }
        return zip(actual, wanted).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    static func isValidToken(_ token: String) -> Bool {
        token.count == 43 && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// A Tailscale address or MagicDNS name. Anything else did not come from
    /// a Mac's pairing screen and deserves a warning.
    public var isTailscaleHost: Bool {
        if host.hasSuffix(".ts.net") { return true }
        let parts = host.split(separator: ".").compactMap { UInt8($0) }
        return parts.count == 4 && parts[0] == 100 && (64...127).contains(parts[1])
    }

    static func isValidHost(_ host: String) -> Bool {
        (1...253).contains(host.count) && host.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".-:".contains($0)) }
    }
}
