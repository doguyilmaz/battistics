#if DEBUG
import BattisticsRemote
import Foundation

/// Sample Macs for Simulator and UI checks, enabled with the `-demo` launch argument.
enum DemoData {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-demo")

    static var readings: [String: MacStore.Reading] {
        let now = Date()
        let history = (0..<48).map { index in
            RemoteStatus.ChargePoint(at: now.addingTimeInterval(Double(index - 47) * 1800),
                                     percent: 40 + 50 * abs(sin(Double(index) / 9)))
        }
        var desk = RemoteStatus(
            machineName: "MacBook Pro", readAt: now.addingTimeInterval(-40),
            battery: .init(percent: 82, isCharging: true, onAdapter: true, minutesRemaining: 35, healthPercent: 91,
                           lowPowerMode: false, lowPowerPolicy: .onlyOnBattery, watts: 41.6, adapterWatts: 96,
                           temperatureC: 33.4, cycleCount: 212, designCycleCount: 1000, currentCapacityMah: 5240,
                           maxCapacityMah: 6390, designCapacityMah: 6249, voltageMV: 12_870, amperageMA: 3240),
            network: .wifi, networkName: "Home", lidClosed: false,
            protection: .init(stopAtPercent: 10, warnAtPercent: 20, closedLidAllowed: true),
            macModel: "MacBook Pro 14\" (Mac15,6)", osVersion: "macOS 26.1",
            heartbeatSeconds: RemoteStatus.heartbeat)
        desk.chargeHistory = history
        desk.extras = .init(sampledAt: now.addingTimeInterval(-300),
                            accessories: [.init(name: "Magic Mouse", percent: 64),
                                          .init(name: "AirPods Pro", percent: 12, detail: "Left")],
                            apps: [.init(name: "Xcode", cpuPercent: 48.2), .init(name: "Safari", cpuPercent: 9.6)])
        let bag = RemoteStatus(
            machineName: "MacBook Air", readAt: now.addingTimeInterval(-90),
            battery: .init(percent: 57, isCharging: false, onAdapter: false, minutesRemaining: 260, healthPercent: 96,
                           lowPowerMode: true, lowPowerPolicy: .onlyOnBattery, watts: -6.2, temperatureC: 30.1, cycleCount: 88),
            session: .init(mode: .lidClosed, origin: .phone, name: "iPhone", startedAt: now.addingTimeInterval(-1500),
                           deadline: now.addingTimeInterval(3900)),
            network: .hotspot, networkName: "Ada’s iPhone", lidClosed: true,
            protection: .init(warnAtPercent: 20, closedLidAllowed: true),
            heartbeatSeconds: RemoteStatus.sessionHeartbeat)
        return ["demo-desk": .init(status: desk, reachable: true), "demo-bag": .init(status: bag, reachable: true)]
    }

    /// Plays a command against the sample Mac, as the real one would answer it.
    static func apply(_ request: RemoteRequest, to status: inout RemoteStatus) {
        let now = Date()
        status.readAt = now
        switch request.operation {
        case .start:
            let minutes = request.durationMinutes ?? 0
            status.session = .init(mode: request.mode ?? .displayMaySleep, origin: .phone, name: request.deviceName,
                                   startedAt: now, deadline: minutes > 0 ? now.addingTimeInterval(Double(minutes) * 60) : nil)
        case .stop:
            status.session = nil
            status.lastEnd = .init(reason: .phone, at: now)
        case .setLowPower:
            status.battery?.lowPowerPolicy = request.lowPowerPolicy
        case .inspect:
            status.extras = .init(sampledAt: now, accessories: [.init(name: "Magic Keyboard", percent: 88)],
                                  apps: [.init(name: "Final Cut Pro", cpuPercent: 63.4), .init(name: "Mail", cpuPercent: 2.1)])
        case .sleepDisplay, .unknown:
            break
        }
        status.lastCommand = .init(id: request.id, failure: nil)
    }
}
#endif
