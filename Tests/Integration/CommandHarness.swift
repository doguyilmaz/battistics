import BattisticsCore
import Darwin
import Foundation

@main
struct CommandHarness {
    @MainActor static func main() async throws {
        let endpoint = LocalAutomationEndpoint(directory: CommandLine.arguments[1])
        let options = try RunOptions(arguments: Array(CommandLine.arguments.dropFirst(2)))
        let runner = CommandRunner(client: .init(endpoint: endpoint))
        runner.finish(await runner.run(options))
    }
}
