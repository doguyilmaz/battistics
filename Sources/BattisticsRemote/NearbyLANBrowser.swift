import Foundation
import Network

@MainActor
final class NearbyLANBrowser {
    var onEndpoints: (([String: NWEndpoint]) -> Void)?
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: NearbyTLS.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let endpoints = results.reduce(into: [String: NWEndpoint]()) { endpoints, result in
                if case .service(let name, _, _, _) = result.endpoint { endpoints[name] = result.endpoint }
            }
            Task { @MainActor in self?.onEndpoints?(endpoints) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor in if self?.browser === browser { self?.stop() } }
            }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    func stop() {
        browser?.stateUpdateHandler = nil
        browser?.browseResultsChangedHandler = nil
        browser?.cancel()
        browser = nil
        onEndpoints?([:])
    }
}
