import Darwin
import Foundation

public enum TailscaleAddress {
    /// IPv4 addresses in Tailscale's 100.64.0.0/10 range on tunnel interfaces.
    public static func current() -> Set<String> {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [] }
        defer { freeifaddrs(first) }
        var result: Set<String> = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: entry.ifa_name).hasPrefix("utun") else { continue }
            let ipv4 = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            let value = UInt32(bigEndian: ipv4.s_addr)
            guard value & 0xFFC0_0000 == 0x6440_0000 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var copy = ipv4
            guard inet_ntop(AF_INET, &copy, &buffer, socklen_t(buffer.count)) != nil else { continue }
            result.insert(String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
        }
        return result
    }
}
