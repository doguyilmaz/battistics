import Darwin
import Foundation

public struct LocalAutomationEndpoint: Sendable {
    public static var standard: Self { .init(directory: "/private/tmp/battistics-\(geteuid())") }
    public let directory: String
    public var socketPath: String { directory + "/control.sock" }
    var lockPath: String { directory + "/control.lock" }
    public init(directory: String) { self.directory = directory }

    func validateDirectory(create: Bool) throws {
        if create, mkdir(directory, 0o700) != 0, errno != EEXIST { throw POSIXError(.EACCES) }
        var info = stat()
        guard lstat(directory, &info) == 0, info.st_uid == geteuid(),
              info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o077 == 0 else {
            throw POSIXError(.EACCES)
        }
    }

    func address() throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(socketPath.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw POSIXError(.ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in buffer.copyBytes(from: bytes) }
        return address
    }

    static func verifyPeer(_ fd: Int32) throws {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == geteuid() else { throw POSIXError(.EACCES) }
    }

    static func configure(_ fd: Int32, nonblocking: Bool) throws {
        guard fcntl(fd, F_SETFD, FD_CLOEXEC) != -1 else { throw POSIXError(.EIO) }
        if nonblocking, fcntl(fd, F_SETFL, O_NONBLOCK) == -1 { throw POSIXError(.EIO) }
        var one: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one))) == 0
        else { throw POSIXError(.EIO) }
    }
}
