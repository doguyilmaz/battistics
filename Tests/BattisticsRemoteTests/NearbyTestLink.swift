import Foundation
@testable import BattisticsRemote

/// A fragmented, bidirectional stream without a radio or a listening port.
@MainActor
final class NearbyTestLink: NearbyLink {
    let id = UUID()
    let kind = RemoteRoute.Kind.bluetooth
    var onData: ((Data) -> Void)?
    var onClose: (() -> Void)?
    weak var remote: NearbyTestLink?
    private var closed = false

    func send(_ data: Data) throws {
        guard !closed, let remote, !remote.closed else { throw NearbyError.unavailable }
        var offset = 0
        while offset < data.count {
            let end = min(offset + 23, data.count)
            remote.onData?(data.subdata(in: offset..<end))
            offset = end
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        onClose?()
        remote?.close()
    }
}
