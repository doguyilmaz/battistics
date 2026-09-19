import Darwin
import Foundation

public struct ProcessEnergySample: Sendable, Equatable, Identifiable {
    public let pid: Int32
    public let name: String
    public let cpuPercent: Double
    /// Share of the total energy consumed across sampled processes during
    /// the window, 0...1, when the kernel reports per-process energy.
    public let energyShare: Double?

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, cpuPercent: Double, energyShare: Double?) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.energyShare = energyShare
    }
}

/// Samples per-process CPU time and billed energy over a short window.
/// Runs ONLY on demand (the Energy pane keeps it alive while visible);
/// nothing here ever runs in the background.
public enum ProcessEnergySampler {
    private struct Reading {
        let startedAt: UInt64
        let cpuNanoseconds: UInt64
        let energy: UInt64
    }

    public static func sample(over duration: Duration = .seconds(3), limit: Int = 8) async -> [ProcessEnergySample] {
        await Session().sample(over: duration, limit: limit)
    }

    /// Reuses the previous census when a visible pane requests successive
    /// windows. After the initial baseline, only one census is needed per tick.
    public actor Session {
        private var previous: [Int32: Reading]?
        private var previousInstant: ContinuousClock.Instant?
        private var sampling = false

        public init() {}

        public func sample(over duration: Duration = .seconds(3), limit: Int = 8) async -> [ProcessEnergySample] {
            guard !Task.isCancelled, duration > .zero, limit > 0, !sampling else { return [] }
            sampling = true
            defer { sampling = false }
            let clock = ContinuousClock()
            if previous == nil {
                previous = ProcessEnergySampler.snapshot()
                previousInstant = clock.now
            }
            do { try await Task.sleep(for: duration) }
            catch {
                previous = nil
                previousInstant = nil
                return []
            }
            guard !Task.isCancelled else {
                previous = nil
                previousInstant = nil
                return []
            }
            let after = ProcessEnergySampler.snapshot()
            guard !Task.isCancelled else {
                previous = nil
                previousInstant = nil
                return []
            }
            guard let before = previous, let startedAt = previousInstant else { return [] }
            let now = clock.now
            previous = after
            previousInstant = now
            return ProcessEnergySampler.rank(before: before, after: after,
                                             elapsed: startedAt.duration(to: now), limit: limit)
        }
    }

    private static func rank(before: [Int32: Reading], after: [Int32: Reading],
                             elapsed: Duration, limit: Int) -> [ProcessEnergySample] {
        // Use the observed monotonic interval, including scheduling delays.
        let intervalNs = Double(elapsed.components.seconds) * 1e9
            + Double(elapsed.components.attoseconds) / 1e9
        guard intervalNs > 0 else { return [] }

        var deltas: [(pid: Int32, cpu: Double, energy: UInt64)] = []
        var totalEnergyDelta: Double = 0
        for (pid, current) in after {
            guard let previous = before[pid], previous.startedAt == current.startedAt else { continue }
            let cpuDelta = current.cpuNanoseconds >= previous.cpuNanoseconds
                ? current.cpuNanoseconds - previous.cpuNanoseconds : 0
            let energyDelta = current.energy >= previous.energy
                ? current.energy - previous.energy : 0
            guard cpuDelta > 0 || energyDelta > 0 else { continue }
            totalEnergyDelta += Double(energyDelta)
            deltas.append((pid, Double(cpuDelta) / intervalNs * 100, energyDelta))
        }

        let ranked = deltas.sorted {
            if $0.energy != $1.energy { return $0.energy > $1.energy }
            return $0.cpu > $1.cpu
        }

        return ranked.prefix(limit).compactMap { delta in
            guard delta.cpu >= 0.1 || delta.energy > 0 else { return nil }
            let share: Double? = totalEnergyDelta > 0 ? Double(delta.energy) / totalEnergyDelta : nil
            return ProcessEnergySample(
                pid: delta.pid,
                name: processName(for: delta.pid),
                cpuPercent: delta.cpu,
                energyShare: share
            )
        }
    }

    private static func snapshot() -> [Int32: Reading] {
        guard !Task.isCancelled else { return [:] }
        var readings: [Int32: Reading] = [:]
        for pid in allPids() where pid > 0 {
            guard !Task.isCancelled else { return [:] }
            guard let usage = usage(for: pid) else { continue }
            readings[pid] = usage
        }
        return readings
    }

    private static func allPids() -> [Int32] {
        let expected = proc_listallpids(nil, 0)
        guard expected > 0 else { return [] }
        var buffer = [Int32](repeating: 0, count: Int(expected) * 2)
        let filled = buffer.withUnsafeMutableBufferPointer { pointer in
            proc_listallpids(pointer.baseAddress, Int32(pointer.count * MemoryLayout<Int32>.size))
        }
        guard filled > 0 else { return [] }
        return Array(buffer.prefix(Int(filled)))
    }

    private static func usage(for pid: Int32) -> Reading? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
            }
        }
        guard result == 0 else { return nil }
        let ticks = info.ri_user_time &+ info.ri_system_time
        return Reading(startedAt: info.ri_proc_start_abstime,
                       cpuNanoseconds: machTicksToNanoseconds(ticks), energy: info.ri_billed_energy)
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func machTicksToNanoseconds(_ ticks: UInt64) -> UInt64 {
        guard timebase.denom != 0 else { return ticks }
        return ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    private static func processName(for pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        if let path = string(from: buffer, length: length) {
            let name = URL(fileURLWithPath: path).lastPathComponent
            if !name.isEmpty { return name }
        }
        var nameBuffer = [CChar](repeating: 0, count: 64)
        let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        if let name = string(from: nameBuffer, length: nameLength) {
            return name
        }
        return "pid \(pid)"
    }

    private static func string(from buffer: [CChar], length: Int32) -> String? {
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).map(UInt8.init(bitPattern:))
        let text = String(decoding: bytes, as: UTF8.self)
        return text.isEmpty ? nil : text
    }
}
