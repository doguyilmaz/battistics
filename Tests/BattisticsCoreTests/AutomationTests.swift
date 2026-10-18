import Darwin
import Foundation
import Testing
@testable import BattisticsCore

@Suite("Bounded local automation")
struct AutomationTests {
    @Test func requestsRejectUnboundedDurationsAndInvisibleNames() {
        for duration in [0, -1, 1, 16, 721, Int.max] {
            #expect(AutomationRequest(.start, name: "Build", durationMinutes: duration).validatedStart() == nil)
        }
        for name in ["", "   ", "\nBuild", "Build\u{0}", String(repeating: "a", count: 81)] {
            #expect(AutomationRequest(.start, name: name, durationMinutes: 15).validatedStart() == nil)
        }
        for duration in [15, 30, 60, 120, 240, 360, 720] {
            let args = AutomationRequest(.start, name: " Derle ", durationMinutes: duration).validatedStart()
            #expect(args?.name == "Derle")
            #expect(args?.mode == .displayMaySleep)
        }
        #expect(AutomationRequest(.start, name: "Build", mode: "shutdown", durationMinutes: 15).validatedStart() == nil)
        var request = AutomationRequest(.start, name: "Build", durationMinutes: 15)
        request.version = 2
        #expect(request.validatedStart() == nil)
    }

    @Test func renewalCannotStealReviveOrExtendAbsoluteDeadline() {
        let now = Date(timeIntervalSince1970: 1_000)
        let id = UUID(), owner = UUID()
        var lease = AutomationLease(id: id, owner: owner, name: "Build", deadline: now.addingTimeInterval(60), now: now)
        let wrongSession = lease.renew(id: UUID(), owner: owner, now: now)
        let wrongOwner = lease.renew(id: id, owner: UUID(), now: now)
        #expect(!wrongSession && !wrongOwner)
        #expect(lease.heartbeatDeadline == now.addingTimeInterval(45))
        let renewed = lease.renew(id: id, owner: owner, now: now.addingTimeInterval(30))
        #expect(renewed)
        #expect(lease.heartbeatDeadline == now.addingTimeInterval(60))
        let pastDeadline = lease.renew(id: id, owner: owner, now: now.addingTimeInterval(60))
        #expect(!pastDeadline)
        #expect(lease.isExpired(at: now.addingTimeInterval(60)))
        var stalled = AutomationLease(id: id, owner: owner, name: "Build", deadline: now.addingTimeInterval(900), now: now)
        let pastHeartbeat = stalled.renew(id: id, owner: owner, now: now.addingTimeInterval(45))
        #expect(!pastHeartbeat)
    }

    @MainActor
    @Test func persistentConnectionsHaveDistinctOwnersAndReportDisconnect() async throws {
        let endpoint = uniqueEndpoint()
        var connected: Set<UUID> = []
        var seen: [UUID] = []
        let server = LocalAutomationServer(endpoint: endpoint,
            connected: { connected.insert($0) }, disconnected: { connected.remove($0) },
            handler: { id, _ in
                #expect(connected.contains(id))
                seen.append(id)
                return .init(status: AutomationStatus())
            })
        try await server.start()
        let first = LocalAutomationClient(endpoint: endpoint), second = LocalAutomationClient(endpoint: endpoint)
        #expect(try await first.request(.init(.status)).status?.active == false)
        _ = try await first.request(.init(.status))
        _ = try await second.request(.init(.status))
        #expect(seen.count == 3 && seen[0] == seen[1] && seen[1] != seen[2])
        #expect(connected.count == 2)
        var info = stat()
        #expect(lstat(endpoint.socketPath, &info) == 0 && info.st_mode & 0o777 == 0o600)
        await first.close()
        try await eventually { connected.count == 1 }
        await second.close()
        try await eventually { connected.isEmpty }
        await server.stop()
        #expect(!FileManager.default.fileExists(atPath: endpoint.socketPath))
        try FileManager.default.removeItem(atPath: endpoint.directory)
    }

    @MainActor
    @Test func secondAppCannotTakeOverAndEndpointCanRestart() async throws {
        let endpoint = uniqueEndpoint()
        let make = { LocalAutomationServer(endpoint: endpoint, connected: { _ in }, disconnected: { _ in }, handler: { _, _ in .init(status: AutomationStatus()) }) }
        let first = make(), second = make()
        try await first.start()
        await #expect(throws: (any Error).self) { try await second.start() }
        let client = LocalAutomationClient(endpoint: endpoint)
        #expect(try await client.request(.init(.status)).error == nil)
        await client.close()
        await first.stop()
        try await second.start()
        #expect(try await client.request(.init(.status)).error == nil)
        await client.close()
        await second.stop()
        try FileManager.default.removeItem(atPath: endpoint.directory)
    }

    @MainActor
    @Test func rejectsInsecureOrSymlinkedDirectoryWithoutReplacingFiles() async throws {
        let endpoint = uniqueEndpoint()
        #expect(mkdir(endpoint.directory, 0o755) == 0)
        #expect(chmod(endpoint.directory, 0o755) == 0)
        let server = LocalAutomationServer(endpoint: endpoint, connected: { _ in }, disconnected: { _ in }, handler: { _, _ in .init(status: AutomationStatus()) })
        await #expect(throws: (any Error).self) { try await server.start() }
        try FileManager.default.removeItem(atPath: endpoint.directory)
        #expect(symlink("/private/tmp", endpoint.directory) == 0)
        await #expect(throws: (any Error).self) { try await server.start() }
        try FileManager.default.removeItem(atPath: endpoint.directory)
        #expect(mkdir(endpoint.directory, 0o700) == 0)
        try Data("do not replace".utf8).write(to: URL(fileURLWithPath: endpoint.socketPath))
        await #expect(throws: (any Error).self) { try await server.start() }
        #expect(try String(contentsOfFile: endpoint.socketPath, encoding: .utf8) == "do not replace")
        try FileManager.default.removeItem(atPath: endpoint.directory)
    }

    @MainActor
    @Test func malformedAndOversizedFramesDisconnectWithoutDispatch() async throws {
        let endpoint = uniqueEndpoint()
        var connected: Set<UUID> = []
        var disconnections = 0
        var requests = 0
        let server = LocalAutomationServer(endpoint: endpoint, connected: { connected.insert($0) },
            disconnected: { connected.remove($0); disconnections += 1 },
            handler: { _, _ in requests += 1; return .init(status: AutomationStatus()) })
        try await server.start()
        for payload in ["not json\n", String(repeating: "x", count: 17_000), "{}\n{}\n"] {
            let previous = disconnections
            let fd = try rawConnection(endpoint)
            let bytes = Array(payload.utf8)
            _ = bytes.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
            try await eventually { disconnections > previous }
            Darwin.close(fd)
        }
        #expect(requests == 0)
        #expect(connected.isEmpty)
        await server.stop()
        try FileManager.default.removeItem(atPath: endpoint.directory)
    }

    @MainActor
    @Test func disconnectIsObservedWhileARequestIsSuspended() async throws {
        let endpoint = uniqueEndpoint()
        var connected: Set<UUID> = []
        var started = false
        var finishedAfterDisconnect = false
        let server = LocalAutomationServer(endpoint: endpoint, connected: { connected.insert($0) },
            disconnected: { connected.remove($0) }, handler: { id, _ in
                started = true
                try? await Task.sleep(for: .milliseconds(100))
                finishedAfterDisconnect = !connected.contains(id)
                return .init(status: AutomationStatus())
            })
        try await server.start()
        let fd = try rawConnection(endpoint)
        let data = try JSONEncoder().encode(AutomationRequest(.status)) + Data([10])
        _ = data.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        try await eventually { started }
        Darwin.close(fd)
        try await eventually { finishedAfterDisconnect }
        await server.stop()
        try FileManager.default.removeItem(atPath: endpoint.directory)
    }

    private func uniqueEndpoint() -> LocalAutomationEndpoint {
        .init(directory: "/private/tmp/battistics-test-\(UUID().uuidString)")
    }

    @MainActor
    @Test func stalledReplyTimesOutAndClosesItsConnection() async throws {
        let endpoint = uniqueEndpoint()
        var disconnected = false
        let server = LocalAutomationServer(endpoint: endpoint, connected: { _ in },
            disconnected: { _ in disconnected = true }, handler: { _, _ in
                try? await Task.sleep(for: .seconds(6))
                return .init(status: AutomationStatus())
            })
        try await server.start()
        let client = LocalAutomationClient(endpoint: endpoint)
        let start = ContinuousClock.now
        await #expect(throws: (any Error).self) { try await client.request(.init(.status)) }
        #expect(start.duration(to: .now) < .seconds(6))
        try await eventually { disconnected }
        await server.stop()
        try FileManager.default.removeItem(atPath: endpoint.directory)
    }

    private func rawConnection(_ endpoint: LocalAutomationEndpoint) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EMFILE) }
        do {
            try LocalAutomationEndpoint.configure(fd, nonblocking: false)
            var address = try endpoint.address()
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard result == 0 else { throw POSIXError(.ECONNREFUSED) }
            return fd
        } catch { Darwin.close(fd); throw error }
    }

    @MainActor private func eventually(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(predicate(), "Expected socket lifecycle event within one second")
    }
}
