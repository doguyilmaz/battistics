import Darwin
import Foundation

@main
struct BattisticsCLI {
    @MainActor static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] || arguments == ["run", "--help"] {
            print(RunOptions.usage)
            return
        }
        do {
            let options = try RunOptions(arguments: arguments)
            let runner = CommandRunner()
            exit(await runner.run(options))
        } catch {
            FileHandle.standardError.write(Data((RunOptions.usage + "\n").utf8))
            exit(64)
        }
    }
}
