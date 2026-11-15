import Foundation

@MainActor
protocol NearbyLink: AnyObject {
    var id: UUID { get }
    var kind: RemoteRoute.Kind { get }
    var onData: ((Data) -> Void)? { get set }
    var onClose: (() -> Void)? { get set }
    func send(_ data: Data) throws
    func close()
}
