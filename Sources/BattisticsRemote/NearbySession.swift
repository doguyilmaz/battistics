import CryptoKit
import Foundation

/// A fresh challenge and directional keys bind every packet to one connection.
/// Sequence numbers reject replay/reflection before application dispatch.
struct NearbySession {
    private let credential: NearbyCredential
    private let server: Bool
    private var challenge: Data?
    private var sendingKey: SymmetricKey?
    private var receivingKey: SymmetricKey?
    private var sent: UInt64 = 0
    private var received: UInt64 = 0
    private(set) var authenticated = false

    init(credential: NearbyCredential, server: Bool) {
        self.credential = credential
        self.server = server
    }

    mutating func begin() throws -> Data {
        guard server, challenge == nil else { throw NearbyError.authentication }
        let nonce = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        challenge = nonce
        return try RemoteWire.encode(NearbyPacket.challenge(nonce))
    }

    mutating func receive(_ data: Data) throws -> (response: Data?, message: NearbyMessage?) {
        guard data.count <= NearbyFrameBuffer.maximumPayload, credential.isValid else { throw NearbyError.malformedFrame }
        switch try RemoteWire.decode(NearbyPacket.self, from: data) {
        case .challenge(let nonce):
            guard !server, challenge == nil, nonce.count == 32 else { throw NearbyError.authentication }
            challenge = nonce
            let client = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            let proof = HMAC<SHA256>.authenticationCode(for: transcript(client), using: SymmetricKey(data: credential.key))
            derive(client)
            return (try RemoteWire.encode(NearbyPacket.authenticate(nonce: client, proof: Data(proof))), nil)
        case .authenticate(let nonce, let proof):
            guard server, !authenticated, sendingKey == nil, challenge != nil, nonce.count == 32,
                  HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: transcript(nonce),
                                                       using: SymmetricKey(data: credential.key)) else { throw NearbyError.authentication }
            derive(nonce)
            authenticated = true
            return (try seal(.ready), nil)
        case .encrypted(let sequence, let body):
            guard let receivingKey, sequence == received, received < UInt64.max else { throw NearbyError.authentication }
            let plaintext = try ChaChaPoly.open(.init(combined: body), using: receivingKey, authenticating: aad(sequence))
            let message = try RemoteWire.decode(NearbyMessage.self, from: plaintext)
            received += 1
            if !authenticated {
                guard !server, case .ready = message else { throw NearbyError.authentication }
                authenticated = true
            }
            return (nil, message)
        }
    }

    mutating func seal(_ message: NearbyMessage) throws -> Data {
        guard authenticated, let sendingKey, sent < UInt64.max else { throw NearbyError.authentication }
        let encoded = try RemoteWire.encode(message)
        guard encoded.count < NearbyFrameBuffer.maximumPayload / 2 else { throw NearbyError.capacity }
        let box = try ChaChaPoly.seal(encoded, using: sendingKey, authenticating: aad(sent))
        let packet = try RemoteWire.encode(NearbyPacket.encrypted(sequence: sent, body: box.combined))
        sent += 1
        return packet
    }

    private func transcript(_ client: Data) -> Data {
        Data("Battistics nearby authentication v1".utf8) + Data(credential.macID.utf8) + (challenge ?? Data()) + client
    }

    private mutating func derive(_ client: Data) {
        let root = SymmetricKey(data: credential.key)
        let salt = (challenge ?? Data()) + client
        let c2s = HKDF<SHA256>.deriveKey(inputKeyMaterial: root, salt: salt,
                                        info: Data("Battistics nearby client v1".utf8), outputByteCount: 32)
        let s2c = HKDF<SHA256>.deriveKey(inputKeyMaterial: root, salt: salt,
                                        info: Data("Battistics nearby server v1".utf8), outputByteCount: 32)
        sendingKey = server ? s2c : c2s
        receivingKey = server ? c2s : s2c
    }

    private func aad(_ sequence: UInt64) -> Data {
        var sequence = sequence.bigEndian
        return Data("Battistics nearby packet v1".utf8) + withUnsafeBytes(of: &sequence) { Data($0) }
    }
}
