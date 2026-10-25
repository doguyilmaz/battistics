import BattisticsCore
import Foundation
import MCP

@main
struct BattisticsMCP {
    static func main() async throws {
        let bridge = MCPAutomationBridge()
        let server = Server(name: "battistics", version: "0.1.0", capabilities: .init(tools: .init()))
        await server.withMethodHandler(ListTools.self) { _ in .init(tools: MCPAutomationBridge.tools) }
        await server.withMethodHandler(CallTool.self) { parameters in await bridge.call(parameters) }
        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
        await bridge.close()
        await server.stop()
    }
}
