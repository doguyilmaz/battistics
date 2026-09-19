import Darwin
import Foundation

/// Runs a fixed executable and argument vector without a shell. Output and
/// runtime are bounded; unused stdin and stderr cannot block the child.
public enum BoundedCommand {
    public enum Failure: Error, Sendable, Equatable {
        case invalidLimits
        case timedOut
        case outputLimitExceeded
        case readFailed(Int32)
        case unsuccessfulExit(Int32)
    }

    public static func run(
        executable: String, arguments: [String],
        timeout: TimeInterval = 10, maximumOutputBytes: Int = 1_048_576
    ) async throws -> Data {
        try Task.checkCancellation()
        let operation = try Operation(
            executable: executable, arguments: arguments,
            timeout: timeout, maximumOutputBytes: maximumOutputBytes)
        let output = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operation.start { continuation.resume(with: $0) }
            }
        } onCancel: {
            operation.cancel()
        }
        try Task.checkCancellation()
        return output
    }

    /// For existing non-main worker queues, such as the privileged helper.
    /// Independent calls have independent queues and deadlines.
    public static func runSynchronously(
        executable: String, arguments: [String],
        timeout: TimeInterval = 10, maximumOutputBytes: Int = 1_048_576
    ) throws -> Data {
        try Operation(
            executable: executable, arguments: arguments,
            timeout: timeout, maximumOutputBytes: maximumOutputBytes
        ).waitForResult()
    }

    // Foundation Process and its pipe are confined to this operation's queue.
    // Cancellation crosses that boundary by enqueueing, never by accessing
    // the Process from the caller's executor.
    private final class Operation: @unchecked Sendable {
        private let queue = DispatchQueue(label: "app.battistics.command", qos: .utility)
        private let process = Process()
        private let pipe = Pipe()
        private let timeout: TimeInterval
        private let maximumOutputBytes: Int
        private var output = Data()
        private var readBuffer = [UInt8](repeating: 0, count: 16_384)
        private var reader: DispatchSourceRead?
        private var deadline: DispatchSourceTimer?
        private var terminationDeadline: DispatchSourceTimer?
        private var completion: (@Sendable (Result<Data, Error>) -> Void)?
        private var cancellationRequested = false
        private var started = false
        private var finished = false
        private var reachedEOF = false
        private var exitStatus: Int32?
        private var failure: Error?

        // Only waitForResult uses this field. Its semaphore publishes the
        // queue's write before the waiting worker reads it.
        private var synchronousResult: Result<Data, Error>?

        init(
            executable: String, arguments: [String],
            timeout: TimeInterval, maximumOutputBytes: Int
        ) throws {
            guard timeout.isFinite, timeout > 0, maximumOutputBytes >= 0 else {
                throw Failure.invalidLimits
            }
            self.timeout = timeout
            self.maximumOutputBytes = maximumOutputBytes
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
        }

        func start(_ completion: @escaping @Sendable (Result<Data, Error>) -> Void) {
            queue.async {
                self.completion = completion
                guard !self.cancellationRequested else {
                    self.finish(.failure(CancellationError()))
                    return
                }
                self.launch()
            }
        }

        func cancel() {
            queue.async {
                guard !self.finished else { return }
                self.cancellationRequested = true
                if self.started { self.stop(with: CancellationError()) }
            }
        }

        func waitForResult() throws -> Data {
            let completed = DispatchSemaphore(value: 0)
            start { result in
                self.synchronousResult = result
                completed.signal()
            }
            completed.wait()
            return try synchronousResult!.get()
        }

        private func launch() {
            let descriptor = pipe.fileHandleForReading.fileDescriptor
            let flags = fcntl(descriptor, F_GETFL)
            guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
                finish(.failure(Failure.readFailed(errno)))
                return
            }
            process.terminationHandler = { _ in
                self.queue.async { self.didExit() }
            }
            do {
                try process.run()
            } catch {
                finish(.failure(error))
                return
            }
            started = true
            try? pipe.fileHandleForWriting.close()

            let reader = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
            reader.setEventHandler { self.readAvailableOutput() }
            let handle = pipe.fileHandleForReading
            reader.setCancelHandler { try? handle.close() }
            self.reader = reader
            reader.resume()

            let deadline = DispatchSource.makeTimerSource(queue: queue)
            deadline.schedule(deadline: .now() + timeout)
            deadline.setEventHandler { self.stop(with: Failure.timedOut) }
            self.deadline = deadline
            deadline.resume()
        }

        private func readAvailableOutput() {
            guard !finished, failure == nil, !reachedEOF else { return }
            // Yield after 64 KiB so continuous output cannot starve the
            // cancellation or deadline events on this same serial queue.
            for _ in 0..<4 {
                let count = readBuffer.withUnsafeMutableBytes { buffer in
                    Darwin.read(pipe.fileHandleForReading.fileDescriptor, buffer.baseAddress, buffer.count)
                }
                if count > 0 {
                    guard count <= maximumOutputBytes - output.count else {
                        stop(with: Failure.outputLimitExceeded)
                        return
                    }
                    output.append(contentsOf: readBuffer.prefix(count))
                } else if count == 0 {
                    reachedEOF = true
                    closeReader()
                    finishIfComplete()
                    return
                } else if errno == EINTR {
                    continue
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    return
                } else {
                    stop(with: Failure.readFailed(errno))
                    return
                }
            }
        }

        private func didExit() {
            guard !finished else { return }
            exitStatus = process.terminationStatus
            if let failure {
                finish(.failure(failure))
            } else {
                finishIfComplete()
            }
        }

        private func finishIfComplete() {
            guard reachedEOF, let exitStatus else { return }
            finish(exitStatus == 0 ? .success(output) : .failure(Failure.unsuccessfulExit(exitStatus)))
        }

        private func stop(with error: Error) {
            guard !finished, failure == nil else { return }
            failure = error
            output.removeAll(keepingCapacity: false)
            closeReader()
            guard process.isRunning else {
                finish(.failure(error))
                return
            }
            process.terminate()
            // A wedged child may ignore SIGTERM. Do not let it retain the
            // process, pipes, or awaiting task indefinitely.
            let terminationDeadline = DispatchSource.makeTimerSource(queue: queue)
            terminationDeadline.schedule(deadline: .now() + .milliseconds(250))
            terminationDeadline.setEventHandler {
                guard !self.finished else { return }
                if self.process.isRunning {
                    kill(self.process.processIdentifier, SIGKILL)
                }
                self.finish(.failure(error))
            }
            self.terminationDeadline = terminationDeadline
            terminationDeadline.resume()
        }

        private func closeReader() {
            if let reader {
                reader.cancel()
                self.reader = nil
            } else if !started {
                try? pipe.fileHandleForReading.close()
            }
        }

        private func finish(_ result: Result<Data, Error>) {
            guard !finished else { return }
            finished = true
            deadline?.cancel()
            deadline = nil
            terminationDeadline?.cancel()
            terminationDeadline = nil
            closeReader()
            try? pipe.fileHandleForWriting.close()
            process.terminationHandler = nil
            output = Data()
            let completion = completion
            self.completion = nil
            completion?(result)
        }
    }
}
