import Foundation

/// Length-prefixed framing shared by TCP and fragmented GATT writes/notifications.
public struct NearbyFrameBuffer: Sendable {
    public static let maximumPayload = 128 * 1024
    private var bytes = Data()

    public init() {}

    public static func frame(_ payload: Data) throws -> Data {
        guard !payload.isEmpty, payload.count <= maximumPayload else { throw NearbyError.malformedFrame }
        var length = UInt32(payload.count).bigEndian
        return withUnsafeBytes(of: &length) { Data($0) } + payload
    }

    public mutating func append(_ data: Data) throws -> [Data] {
        guard data.count <= Self.maximumPayload + 4, bytes.count + data.count <= 2 * (Self.maximumPayload + 4) else {
            throw NearbyError.capacity
        }
        bytes.append(data)
        var frames: [Data] = []
        while bytes.count >= 4 {
            let length = bytes.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard length > 0, length <= Self.maximumPayload else { throw NearbyError.malformedFrame }
            guard bytes.count >= length + 4 else { break }
            frames.append(Data(bytes.dropFirst(4).prefix(length)))
            bytes = Data(bytes.dropFirst(length + 4))
        }
        return frames
    }
}
