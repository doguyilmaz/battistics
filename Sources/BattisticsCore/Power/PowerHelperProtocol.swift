import Foundation

/// Mach service the privileged helper vends, and the LaunchDaemon's label.
public let powerHelperMachServiceName = "com.doguyilmaz.Battistics.PowerHelper"

/// Everything the root helper is able to do.
///
/// The interface is deliberately *semantic*: every parameter is a code for an
/// enumerated case, never a command, a path, or a free-form number. The helper
/// builds the argument vector itself from those cases, so the set of
/// operations a caller can request is fixed at compile time and fully
/// enumerable — 106 of them, all of which change a macOS power setting.
///
/// A client that has been completely compromised gains exactly that
/// vocabulary and nothing else. This is the whole security argument, and it
/// only holds while the interface stays semantic: adding a method that takes
/// a string or an unbounded integer would quietly turn this into a root
/// shell.
@objc public protocol PowerHelperProtocol {
    func setLowPowerMode(_ code: Int, reply: @escaping (Int32) -> Void)
    func setEnergyMode(_ code: Int, reply: @escaping (Int32) -> Void)
    func setSleepTimer(_ timer: Int, minutes: Int, source: Int, reply: @escaping (Int32) -> Void)
    /// So the app can tell a stale daemon from a current one after an update.
    func version(reply: @escaping (String) -> Void)
}

/// Stable numeric codes for the wire.
///
/// Explicit rather than derived from `allCases` order: a reordering of the
/// enum must not silently change what an existing installed daemon does with
/// a given code.
extension LowPowerModeSetting {
    public var wireCode: Int {
        switch self {
        case .never: 0
        case .always: 1
        case .onlyOnBattery: 2
        case .onlyOnPowerAdapter: 3
        }
    }

    public init?(wireCode: Int) {
        switch wireCode {
        case 0: self = .never
        case 1: self = .always
        case 2: self = .onlyOnBattery
        case 3: self = .onlyOnPowerAdapter
        default: return nil
        }
    }
}

extension SleepTimer {
    public var wireCode: Int {
        switch self {
        case .display: 0
        case .system: 1
        case .disk: 2
        }
    }

    public init?(wireCode: Int) {
        switch wireCode {
        case 0: self = .display
        case 1: self = .system
        case 2: self = .disk
        default: return nil
        }
    }
}

extension PowerSource {
    public var wireCode: Int {
        switch self {
        case .battery: 0
        case .ac: 1
        case .all: 2
        }
    }

    public init?(wireCode: Int) {
        switch wireCode {
        case 0: self = .battery
        case 1: self = .ac
        case 2: self = .all
        default: return nil
        }
    }
}
