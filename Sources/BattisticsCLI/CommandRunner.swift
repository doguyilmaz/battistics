import BattisticsCore
import Darwin
import Foundation

@MainActor
final class CommandRunner {
    private let client: LocalAutomationClient
    private var process: CommandProcess?
    private var signals: [DispatchSourceSignal] = []
    private var receivedSignal: Int32?
    private var heartbeat: Task<Void, Never>?
    private var ownsSession = false
    private var childSignal: Int32?

    init(client: LocalAutomationClient = .init()) { self.client = client }

    func run(_ options: RunOptions) async -> Int32 {
        installSignals()
        defer { signals.forEach { $0.cancel() } }
        let reply: AutomationReply
        do { reply = try await client.request(options.request) }
        catch {
            report("Cannot connect. Open Battistics and enable Local automation in Power.")
            await client.close()
            return receivedSignal.map { 128 + $0 } ?? 69
        }
        guard receivedSignal == nil else {
            await client.close()
            return 128 + (receivedSignal ?? SIGINT)
        }
        guard let status = reply.status, status.active, let id = status.sessionID else {
            report(reply.error?.message ?? "Keep Awake could not start; command not launched.")
            await client.close()
            return 69
        }
        ownsSession = true
        let code: Int32
        do {
            let child = try CommandProcess(command: options.command)
            process = child
            report("Keep Awake started; maximum \(options.request.durationMinutes ?? 720) minutes.")
            startHeartbeat(id: id)
            (code, childSignal) = await child.waitForExit()
            process = nil
        } catch {
            report("Could not launch command: \(error.localizedDescription)")
            code = (error as? POSIXError)?.code == .ENOENT ? 127 : 126
        }
        heartbeat?.cancel()
        await heartbeat?.value
        if ownsSession { _ = try? await client.request(.init(.stop, sessionID: id)) }
        await client.close()
        return code
    }

    /// Dies from the command's signal when it had one, so a shell loop
    /// around `battistics run` stops on Ctrl-C as it would without it.
    func finish(_ code: Int32) -> Never {
        if let childSignal {
            signal(childSignal, SIG_DFL)
            kill(getpid(), childSignal)
        }
        exit(code)
    }

    private func startHeartbeat(id: UUID) {
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(AutomationLease.heartbeatInterval)) }
                catch { return }
                guard let self, !Task.isCancelled else { return }
                do {
                    let reply = try await self.client.request(.init(.heartbeat, sessionID: id))
                    if reply.status?.active == true, reply.status?.sessionID == id { continue }
                } catch {}
                self.ownsSession = false
                guard !Task.isCancelled else { return }
                self.report("Keep Awake ended. The command is still running; normal sleep is now allowed.")
                await self.client.close()
                return
            }
        }
    }

    private func installSignals() {
        for number in [SIGINT, SIGTERM, SIGHUP] {
            // A caught handler resets on exec; SIG_IGN would survive into the child.
            signal(number) { _ in }
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                self.receivedSignal = number
                // The child shares our process group: when we are in the
                // terminal's foreground, Ctrl-C and hangup already reached it.
                let fromTerminal = number != SIGTERM && tcgetpgrp(STDIN_FILENO) == getpgrp()
                if let process = self.process, !fromTerminal { kill(process.identifier, number) }
            }
            source.resume()
            signals.append(source)
        }
    }

    private func report(_ message: String) {
        FileHandle.standardError.write(Data(("battistics: " + message + "\n").utf8))
    }
}
