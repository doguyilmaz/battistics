import Foundation
import os

/// A command has one deadline covering its write and every answer read. It
/// never joins discovery's read queue and never automatically resends a change.
public enum RemoteCommandExecutor {
    private static let logger = Logger(subsystem: "com.doguyilmaz.Battistics.Remote", category: "Commands")

    public static func execute(_ request: RemoteRequest, to macID: String, cloud: RemoteCloud) async throws -> RemoteStatus {
        try await execute(request, macID: macID, timeout: .seconds(RemoteRequest.answerWait), pollInterval: .seconds(1.5),
                          write: { request, deadline in try await cloud.send(request, to: macID, until: deadline) },
                          read: { deadline in try await cloud.status(macID: macID, until: deadline) },
                          cleanup: { _ in
                              try? await cloud.delete([RemoteCloud.commandRecordName(for: macID)], until: .now.advanced(by: .seconds(5)))
                          })
    }

    static func execute(
        _ request: RemoteRequest, macID: String, timeout: Duration, pollInterval: Duration,
        write: @escaping @Sendable (RemoteRequest, ContinuousClock.Instant) async throws -> Void,
        read: @escaping @Sendable (ContinuousClock.Instant) async throws -> RemoteStatus?,
        cleanup: @escaping @Sendable (String) async -> Void
    ) async throws -> RemoteStatus {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var request = request
        request.sentAt = .now
        let command = request
        let started = ContinuousClock.now
        logger.notice("Command \(command.id, privacy: .public) \(command.operation.rawValue, privacy: .public) started for \(macID, privacy: .private(mask: .hash))")
        do {
            let answer = try await RemoteDeadline.perform(until: deadline) {
                try await write(command, deadline)
                logger.info("Command \(command.id, privacy: .public) saved; waiting for acknowledgement")
                while true {
                    try Task.checkCancellation()
                    if let status = try await read(deadline), status.lastCommand?.id == command.id { return status }
                    try await Task.sleep(until: min(ContinuousClock.now.advanced(by: pollInterval), deadline), clock: .continuous)
                }
            }
            logger.notice("Command \(command.id, privacy: .public) acknowledged in \(String(describing: started.duration(to: .now)), privacy: .public)")
            return answer
        } catch {
            logger.error("Command \(command.id, privacy: .public) ended without acknowledgement in \(String(describing: started.duration(to: .now)), privacy: .public)")
            // Cleanup must not keep a spinner running after its deadline.
            // The Mac also rejects old commands using RemoteRequest.lifetime.
            Task {
                try? await RemoteDeadline.perform(until: .now.advanced(by: .seconds(5))) {
                    await cleanup(command.id)
                }
            }
            throw error
        }
    }
}
