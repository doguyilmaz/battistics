import BattisticsCore
import Foundation
import MCP
import Testing
@testable import BattisticsMCP

@Suite("MCP tool contract")
struct MCPBridgeTests {
    @Test func rejectsInvalidArgumentsBeforeOpeningAnAppConnection() async throws {
        let bridge = MCPAutomationBridge(client: .init(endpoint: .init(directory: "/private/tmp/missing-\(UUID())")))
        let cases: [CallTool.Parameters] = [
            .init(name: "unknown"),
            .init(name: "battistics_status", arguments: ["extra": true]),
            .init(name: "battistics_start", arguments: ["name": "Build", "duration_minutes": 0]),
            .init(name: "battistics_start", arguments: ["name": "Build", "duration_minutes": "15"]),
            .init(name: "battistics_start", arguments: ["name": "Build", "duration_minutes": 15, "mode": true]),
            .init(name: "battistics_start", arguments: ["name": "Build", "duration_minutes": 15, "disable_protection": true]),
            .init(name: "battistics_stop", arguments: ["session_id": "not-a-uuid"]),
        ]
        for parameters in cases {
            let result = await bridge.call(parameters)
            #expect(result.isError == true)
            #expect(try body(result)["error"]? ["code"] as? String == "invalid_request")
        }
        let missingApp = await bridge.call(.init(name: "battistics_status"))
        #expect(try body(missingApp)["error"]? ["code"] as? String == "unavailable")
        await bridge.close()
    }

    @MainActor
    @Test func toolRoundTripPreservesOwnerAndDisconnectsOnClose() async throws {
        let endpoint = LocalAutomationEndpoint(directory: "/private/tmp/battistics-mcp-test-\(UUID())")
        let id = UUID()
        var requests: [AutomationRequest.Operation] = []
        var owners: Set<UUID> = []
        var disconnected = false
        let server = LocalAutomationServer(endpoint: endpoint, connected: { _ in }, disconnected: { _ in disconnected = true }, handler: { owner, request in
            owners.insert(owner)
            requests.append(request.operation)
            var status = AutomationStatus()
            if request.operation == .start {
                status.active = true
                status.sessionID = id
                status.owner = .thisClient
                status.deadline = Date(timeIntervalSince1970: 1_800_000_000)
            }
            if request.operation == .stop { #expect(request.sessionID == id) }
            return .init(status: status)
        })
        try await server.start()
        let bridge = MCPAutomationBridge(client: .init(endpoint: endpoint))
        let start = await bridge.call(.init(name: "battistics_start", arguments: ["name": "Build", "duration_minutes": 15]))
        #expect(start.isError == false)
        let status = try #require(body(start)["status"])
        #expect(status["session_id"] as? String == id.uuidString)
        #expect(status["owner"] as? String == "this_client")
        #expect(status["deadline"] is String)
        let stop = await bridge.call(.init(name: "battistics_stop", arguments: ["session_id": .string(id.uuidString)]))
        #expect(stop.isError == false)
        #expect(requests == [.start, .stop])
        #expect(owners.count == 1)
        await bridge.close()
        for _ in 0..<100 where !disconnected { try await Task.sleep(for: .milliseconds(10)) }
        #expect(disconnected)
        #expect(await bridge.call(.init(name: "battistics_status")).isError == true)
        await server.stop()
        try FileManager.default.removeItem(atPath: endpoint.directory)
    }

    private func body(_ result: CallTool.Result) throws -> [String: [String: Any]] {
        guard case .text(let text, _, _) = result.content.first else { throw CocoaError(.coderValueNotFound) }
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: [String: Any]])
    }
}
