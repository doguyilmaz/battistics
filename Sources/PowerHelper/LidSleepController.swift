import BattisticsCore
import Foundation

/// All lease state, file I/O and pmset calls belong to this serial queue.
final class LidSleepController: @unchecked Sendable {
    static let shared = LidSleepController()
    private let queue = DispatchQueue(label: "Battistics.lid-sleep")
    private let journal = URL(fileURLWithPath: "/var/db/com.doguyilmaz.Battistics.lid-sleep")
    private var lease: LidSleepLease!
    private var timer: DispatchSourceTimer?
    private var recoveryFailed = false

    private init() {
        queue.async { [self] in
            lease = LidSleepLease(
                read: {
                    let output = try Self.pmset(["-g"])
                    guard output.contains("System-wide power settings:") else { throw CocoaError(.fileReadCorruptFile) }
                    for line in output.split(separator: "\n") {
                        let fields = line.split(whereSeparator: \.isWhitespace)
                        if fields.first == "SleepDisabled" {
                            guard fields.count == 2, fields[1] == "0" || fields[1] == "1" else {
                                throw CocoaError(.fileReadCorruptFile)
                            }
                            return fields[1] == "1"
                        }
                    }
                    return false
                },
                write: { _ = try Self.pmset(["-a", "disablesleep", $0 ? "1" : "0"]) },
                save: { [journal] original in
                    try Data((original ? "1" : "0").utf8).write(to: journal, options: .atomic)
                },
                clear: { [journal] in try FileManager.default.removeItem(at: journal) })
            if FileManager.default.fileExists(atPath: journal.path) {
                do {
                    let saved = try String(contentsOf: journal, encoding: .utf8)
                    guard saved == "0" || saved == "1" else { throw CocoaError(.fileReadCorruptFile) }
                    try lease.recover(original: saved == "1")
                } catch { recoveryFailed = true }
            }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 5, repeating: 5)
            timer.setEventHandler { [weak self] in try? self?.lease.expire() }
            timer.resume()
            self.timer = timer
        }
    }

    func set(enabled: Bool, owner: UUID, reply: @escaping @Sendable (Int32) -> Void) {
        queue.async { [self] in
            guard !recoveryFailed else { reply(EIO); return }
            do {
                if enabled { try lease.renew(owner: owner) }
                else { try lease.release(owner: owner) }
                reply(0)
            } catch { reply(EIO) }
        }
    }

    func disconnected(owner: UUID) {
        queue.async { [self] in try? lease.release(owner: owner) }
    }

    private static func pmset(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.executableRuntimeMismatch) }
        return String(decoding: data, as: UTF8.self)
    }
}
