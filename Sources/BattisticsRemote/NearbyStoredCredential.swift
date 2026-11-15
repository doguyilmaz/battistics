import Foundation

/// The account binding is local Keychain metadata, never an advertised identity.
struct NearbyStoredCredential: Codable {
    let accountID: String
    let credential: NearbyCredential
}
