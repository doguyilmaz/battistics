import Darwin
import Foundation

public enum TailscaleAddress {
    /// Whether `host` is a dotted IPv4 address in 100.64.0.0/10.
    public static func contains(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false).map { UInt8($0) }
        guard parts.count == 4, let first = parts[0], let second = parts[1], parts.allSatisfy({ $0 != nil }) else { return false }
        return first == 100 && (64...127).contains(second)
    }

    /// IPv4 addresses in 100.64.0.0/10 on tunnel interfaces. Other VPNs use
    /// that range too, so when a tunnel also carries Tailscale's IPv6 prefix
    /// (fd7a:115c:a1e0::/48), only that tunnel counts.
    public static func current() -> Set<String> {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [] }
        defer { freeifaddrs(first) }
        var candidates: [String: Set<String>] = [:]
        var tailscaleInterfaces: Set<String> = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            let name = String(decoding: Array(UnsafeBufferPointer(start: entry.ifa_name, count: strlen(entry.ifa_name)))
                .map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard name.hasPrefix("utun"), let address = entry.ifa_addr else { continue }
            switch Int32(address.pointee.sa_family) {
            case AF_INET:
                var ipv4 = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                if let text = format(AF_INET, &ipv4, length: INET_ADDRSTRLEN), contains(text) {
                    candidates[name, default: []].insert(text)
                }
            case AF_INET6:
                var ipv6 = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                if format(AF_INET6, &ipv6, length: INET6_ADDRSTRLEN)?.hasPrefix("fd7a:115c:a1e0:") == true {
                    tailscaleInterfaces.insert(name)
                }
            default: break
            }
        }
        let chosen = tailscaleInterfaces.isEmpty ? candidates : candidates.filter { tailscaleInterfaces.contains($0.key) }
        return chosen.values.reduce(into: []) { $0.formUnion($1) }
    }

    private static func format<Address>(_ family: Int32, _ address: inout Address, length: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(length))
        guard inet_ntop(family, &address, &buffer, socklen_t(buffer.count)) != nil else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
