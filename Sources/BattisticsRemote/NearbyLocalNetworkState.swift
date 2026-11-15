import Network

/// Bonjour observations, not a general Local Network permission query.
public enum NearbyLocalNetworkState: Sendable {
    case inactive, discovering, denied, unavailable

    static func failure(_ error: NWError) -> Self {
        // DNS-SD kDNSServiceErr_PolicyDenied, as documented in Apple TN3179.
        if case .dns(-65570) = error { return .denied }
        return .unavailable
    }
}
