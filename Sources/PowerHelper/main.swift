import BattisticsCore
import Foundation
import Security

/// Battistics' privileged helper. Runs as root under launchd and does exactly
/// enumerated power settings and renewable closed-lid sleep leases.
///
/// Kept deliberately tiny. The whole file is meant to be auditable in one
/// sitting, because a root daemon's risk scales with how much of it there is.
/// The lid-sleep controller journals its previous setting in a fixed root-owned
/// file. No client-provided path or command is accepted.
final class PowerHelper: NSObject, NSXPCListenerDelegate, PowerHelperProtocol {
    /// Only a copy of Battistics signed by this team may connect. Without
    /// this, every process running as the user could call the daemon and get
    /// its capabilities for free — privilege escalation by proxy, which is
    /// the classic way helpers like this go wrong.
    private static let clientRequirement = """
        identifier "com.doguyilmaz.Battistics" \
        and anchor apple generic \
        and certificate leaf[subject.OU] = "5MYT4VYJFC"
        """

    private static let build = "3"
    private let owner = UUID()

    /// `setCodeSigningRequirement` returns void — it cannot report that the
    /// requirement was malformed, and a daemon that quietly failed to apply
    /// one would accept every caller. So the string is compiled here first;
    /// if it does not parse, the helper serves nobody rather than everybody.
    private static let requirementIsValid: Bool = {
        var requirement: SecRequirement?
        return SecRequirementCreateWithString(clientRequirement as CFString, [], &requirement)
            == errSecSuccess
    }()

    // MARK: - Connections

    func listener(
        _ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        guard Self.requirementIsValid else { return false }
        connection.setCodeSigningRequirement(Self.clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: PowerHelperProtocol.self)
        let endpoint = PowerHelper()
        let owner = endpoint.owner
        connection.exportedObject = endpoint
        connection.invalidationHandler = { LidSleepController.shared.disconnected(owner: owner) }
        connection.interruptionHandler = { LidSleepController.shared.disconnected(owner: owner) }
        connection.resume()
        return true
    }

    // MARK: - Operations

    func acquireLidSleepLease(_ sessionID: String, reply: @escaping @Sendable (Int32) -> Void) {
        guard let session = UUID(uuidString: sessionID) else {
            reply(LidSleepLeaseResult.rejected.rawValue); return
        }
        LidSleepController.shared.acquire(owner: owner, session: session, reply: reply)
    }

    func renewLidSleepLease(_ sessionID: String, reply: @escaping @Sendable (Int32) -> Void) {
        guard let session = UUID(uuidString: sessionID) else {
            reply(LidSleepLeaseResult.rejected.rawValue); return
        }
        LidSleepController.shared.renew(owner: owner, session: session, reply: reply)
    }

    func releaseLidSleepLease(_ sessionID: String, reply: @escaping @Sendable (Int32) -> Void) {
        guard let session = UUID(uuidString: sessionID) else {
            reply(LidSleepLeaseResult.rejected.rawValue); return
        }
        LidSleepController.shared.release(owner: owner, session: session, reply: reply)
    }

    func setLowPowerMode(_ code: Int, reply: @escaping (Int32) -> Void) {
        guard let setting = LowPowerModeSetting(wireCode: code) else {
            return reply(EINVAL)
        }
        reply(run(PowerSettingsWriter.arguments(for: setting)))
    }

    func setEnergyMode(_ code: Int, reply: @escaping (Int32) -> Void) {
        guard let mode = EnergyMode(rawValue: code) else {
            return reply(EINVAL)
        }
        reply(run(PowerSettingsWriter.arguments(for: mode)))
    }

    func setSleepTimer(
        _ timer: Int, minutes: Int, source: Int, reply: @escaping (Int32) -> Void
    ) {
        // Each value must decode to a real case. `minutes` is not accepted as
        // a number: only the enumerated stops exist, so nothing that could be
        // read by pmset as an option can reach it.
        guard let timer = SleepTimer(wireCode: timer),
            let interval = SleepInterval(rawValue: minutes),
            let source = PowerSource(wireCode: source)
        else {
            return reply(EINVAL)
        }
        reply(run(PowerSettingsWriter.arguments(for: timer, interval: interval, source: source)))
    }

    func version(reply: @escaping (String) -> Void) {
        reply(Self.build)
    }

    // MARK: - Execution

    /// No shell anywhere: an absolute executable path and an argument array,
    /// so there is no command line for anything to be spliced into.
    private func run(_ arguments: [String]) -> Int32 {
        do {
            _ = try BoundedCommand.runSynchronously(
                executable: PowerSettingsWriter.executable, arguments: arguments,
                timeout: 5, maximumOutputBytes: 16_384)
            return 0
        } catch BoundedCommand.Failure.unsuccessfulExit(let status) {
            return status
        } catch BoundedCommand.Failure.timedOut {
            return Int32(ETIMEDOUT)
        } catch {
            return Int32(EIO)
        }
    }
}

let lidSleepController = LidSleepController.shared
let helper = PowerHelper()
let listener = NSXPCListener(machServiceName: powerHelperMachServiceName)
listener.delegate = helper
listener.resume()
RunLoop.main.run()
