import Foundation
import Security

public enum NearbyKeychain {
    public enum Owner: String, Sendable { case mac, phone }

    private static func query(_ owner: Owner, macID: String? = nil) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: "com.doguyilmaz.Battistics.Nearby.\(owner.rawValue)"]
        if let macID { query[kSecAttrAccount as String] = macID }
        return query
    }

    public static func load(_ owner: Owner, macID: String, accountID: String) throws -> NearbyCredential? {
        var query = query(owner, macID: macID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw NearbyError.authentication }
        let stored = try RemoteWire.decode(NearbyStoredCredential.self, from: data)
        guard stored.accountID == accountID else { return nil }
        let credential = stored.credential
        guard credential.isValid, credential.macID == macID else { throw NearbyError.authentication }
        return credential
    }

    public static func save(_ credential: NearbyCredential, owner: Owner, accountID: String) throws {
        guard credential.isValid else { throw NearbyError.authentication }
        let query = query(owner, macID: credential.macID)
        let stored = NearbyStoredCredential(accountID: accountID, credential: credential)
        let attributes: [String: Any] = [kSecValueData as String: try RemoteWire.encode(stored),
                                       kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NearbyError.authentication }
    }

    public static func remove(_ owner: Owner, macID: String? = nil) throws {
        let status = SecItemDelete(query(owner, macID: macID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw NearbyError.authentication }
    }
}
