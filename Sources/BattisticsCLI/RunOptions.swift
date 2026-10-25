import BattisticsCore
import Foundation

struct RunOptions {
    let command: [String]
    let request: AutomationRequest

    enum Failure: Error { case usage }

    init(arguments: [String]) throws {
        guard arguments.first == "run", let separator = arguments.firstIndex(of: "--"),
              separator + 1 < arguments.count else { throw Failure.usage }
        var name: String?
        var mode = KeepAwakeMode.displayMaySleep.rawValue
        var minutes = 720
        var seen: Set<String> = []
        var index = 1
        while index < separator {
            let option = arguments[index]
            guard index + 1 < separator, seen.insert(option).inserted else { throw Failure.usage }
            let value = arguments[index + 1]
            switch option {
            case "--name": name = value
            case "--mode": mode = value
            case "--minutes":
                guard let number = Int(value) else { throw Failure.usage }
                minutes = number
            default: throw Failure.usage
            }
            index += 2
        }
        command = Array(arguments[(separator + 1)...])
        guard !command[0].isEmpty, !command.contains(where: { $0.utf8.contains(0) }) else { throw Failure.usage }
        request = AutomationRequest(.start, name: name ?? URL(fileURLWithPath: command[0]).lastPathComponent,
                                    mode: mode, durationMinutes: minutes, source: .command)
        guard request.validatedStart() != nil else { throw Failure.usage }
    }

    static let usage = """
    Usage: battistics run [--minutes N] [--name NAME] [--mode MODE] -- COMMAND [ARG...]
      N: \(KeepAwakeDuration.finite.map { String($0.rawValue) }.joined(separator: ", ")) (default: 720)
      MODE: displayMaySleep (default), displayOn, lidClosed
    Open Battistics and enable Local automation in Automation first.
    Keep Awake ends when the direct child exits, or earlier at the time limit,
    a protection stop, or disconnection. Stopping Keep Awake does not kill work.
    Interactive AI tasks should use MCP start/stop; an idle terminal is not task completion.
    Example: battistics run --name Build -- swift build
    """
}
