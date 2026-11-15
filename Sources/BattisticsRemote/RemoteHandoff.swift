import Foundation

public enum RemoteHandoff {
    public static func execute(_ request: RemoteRequest, routes: [RemoteRoute], to macID: String,
                               cloud: RemoteCloud) async throws -> RemoteStatus {
        try await execute(request, routes: routes) { command, deadline in
            try await RemoteCommandExecutor.execute(command, to: macID, cloud: cloud, until: deadline)
        }
    }

    static func execute(_ request: RemoteRequest, routes: [RemoteRoute], timeout: Duration = .seconds(RemoteRequest.answerWait), localTimeout: Duration? = nil,
                        cloud: @escaping @Sendable (RemoteRequest, ContinuousClock.Instant) async throws -> RemoteStatus) async throws -> RemoteStatus {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        // Freeze identity, payload and sentAt across every attempt. A transport
        // failure can mean the Mac applied the command but its reply was lost.
        for route in routes {
            try Task.checkCancellation()
            let localDeadline = min(deadline, ContinuousClock.now.advanced(by: localTimeout ?? .seconds(request.operation == .inspect ? 8 : 3)))
            do {
                let answer = try await RemoteDeadline.perform(until: localDeadline) {
                    try await route.execute(request, localDeadline)
                }
                guard answer.lastCommand?.id == request.id else { throw NearbyError.unavailable }
                return answer
            } catch is CancellationError { throw CancellationError() }
            catch { try Task.checkCancellation() }
        }
        let answer = try await RemoteDeadline.perform(until: deadline) { try await cloud(request, deadline) }
        guard answer.lastCommand?.id == request.id else { throw NearbyError.unavailable }
        return answer
    }
}
