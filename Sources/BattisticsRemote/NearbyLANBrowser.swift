import Foundation
import Network

@MainActor
final class NearbyLANBrowser {
    var onEndpoints: (([String: NWEndpoint]) -> Void)?
    var onState: ((NearbyLocalNetworkState) -> Void)?
    private(set) var accessState = NearbyLocalNetworkState.inactive
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
            Task { @MainActor in
                guard let self, self.browser === browser else { return }
                self.onEndpoints?(endpoints)
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.browser === browser else { return }
                switch state {
                case .ready: self.report(.discovering)
                case .waiting(let error): self.report(.failure(error))
                case .failed(let error):
                    self.stop()
                    self.report(.failure(error))
                default: break
                }
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
        report(.inactive)
    }

    private func report(_ state: NearbyLocalNetworkState) {
        accessState = state
        onState?(state)
    }
}
