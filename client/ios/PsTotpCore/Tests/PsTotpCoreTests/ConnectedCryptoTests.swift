import CryptoKit
import Foundation
import Testing
@testable import PsTotpCore

@Suite("Connected-mode crypto (Node known-answer vectors)")
struct ConnectedCryptoTests {
    let v = Vectors.shared

    @Test func guidBytesAreMixedEndian() throws {
        #expect(try GuidBytes.toBytes(v.clientProof.loginSessionId).hex == v.clientProof.guidBytesHex)
        #expect(try GuidBytes.toBytes("00112233-4455-6677-8899-AABBCCDDEEFF").hex == "33221100554477668899aabbccddeeff")
        for bad in ["", "not-a-guid", "0f8fad5b-d9cb-469f-a165-70867728950", "zf8fad5b-d9cb-469f-a165-70867728950e"] {
            #expect(throws: CryptoError.invalidGuid(bad)) { _ = try GuidBytes.toBytes(bad) }
        }
    }

    @Test func clientProofMatchesWeb() throws {
        let p = v.clientProof
        let proof = try ClientProof.compute(verifier: Data(hex: p.verifierHex), nonce: Data(hex: p.nonceHex), loginSessionId: p.loginSessionId)
        #expect(proof.hex == p.proofHex)
        // Case of the GUID text must not matter.
        let upper = try ClientProof.compute(verifier: Data(hex: p.verifierHex), nonce: Data(hex: p.nonceHex), loginSessionId: p.loginSessionId.uppercased())
        #expect(upper == proof)
    }

    @Test func passwordEnvelopeDecryptsNodeOutput() throws {
        let e = v.envelope
        let envelope = Envelope(ciphertext: e.envelope.ciphertext, nonce: e.envelope.nonce, version: e.envelope.version)
        #expect(try EnvelopeHelper.decrypt(key: Data(hex: e.keyHex), envelope: envelope).hex == e.plaintextHex)
        #expect(try EnvelopeHelper.toRaw(envelope).count == 12 + 32 + 16)
    }

    @Test func envelopeRoundTripAndErrors() throws {
        let key = KeyDerivation.randomBytes(32), plain = KeyDerivation.randomBytes(32)
        let a = try EnvelopeHelper.encrypt(key: key, plaintext: plain)
        let b = try EnvelopeHelper.encrypt(key: key, plaintext: plain)
        #expect(a.nonce != b.nonce && a.version == 1)
        #expect(try EnvelopeHelper.decrypt(key: key, envelope: a) == plain)
        #expect(throws: CryptoError.decryptionFailed) { _ = try EnvelopeHelper.decrypt(key: KeyDerivation.randomBytes(32), envelope: a) }
        #expect(throws: CryptoError.invalidEncoding) {
            _ = try EnvelopeHelper.decrypt(key: key, envelope: Envelope(ciphertext: "***", nonce: a.nonce))
        }
    }

    private func recipientKey() throws -> Ecdh.PrivateKey {
        try Ecdh.PrivateKey(rawRepresentation: Data(hex: v.ecdh.recipientPrivateHex))
    }

    @Test func publicKeyExportMatchesNodeAndImports() throws {
        let key = try recipientKey()
        #expect(Ecdh.exportPublicKey(key.publicKey).hex == v.ecdh.recipientPublicHex)
        let imported = try Ecdh.importPublicKey(Data(hex: v.ecdh.recipientPublicHex))
        #expect(Ecdh.exportPublicKey(imported).hex == v.ecdh.recipientPublicHex)
        #expect(throws: CryptoError.invalidPublicKey) { _ = try Ecdh.importPublicKey(Data(repeating: 4, count: 65)) }   // not on curve
        #expect(throws: CryptoError.invalidPublicKey) { _ = try Ecdh.importPublicKey(Data(hex: v.ecdh.recipientPublicHex).dropFirst()) }
    }

    @Test func wrappingKeyMatchesNodeFromBothSides() throws {
        let ephemeral = try Ecdh.PrivateKey(rawRepresentation: Data(hex: v.ecdh.ephemeralPrivateHex))
        let a = try Ecdh.deriveWrappingKey(privateKey: ephemeral, publicKey: try recipientKey().publicKey)
        let b = try Ecdh.deriveWrappingKey(privateKey: try recipientKey(), publicKey: ephemeral.publicKey)
        #expect(a.hex == v.ecdh.wrappingKeyHex && b == a)
    }

    @Test func unpacksAnEnvelopeBuiltByNode() throws {
        let e = v.ecdh.envelope
        let vaultKey = try Ecdh.unpackDeviceEnvelope(
            Envelope(ciphertext: e.ciphertext, nonce: e.nonce, version: e.version), devicePrivateKey: try recipientKey())
        #expect(vaultKey.hex == v.ecdh.vaultKeyHex)
    }

    @Test func packThenUnpackRoundTripsThroughDerStorage() throws {
        let device = Ecdh.generateKeyPair()
        let stored = try Ecdh.importPrivateKey(Ecdh.exportPrivateKey(device))   // as persisted on the device
        let vaultKey = KeyDerivation.generateVaultKey()
        let envelope = try Ecdh.packDeviceEnvelope(vaultKey: vaultKey, recipientPublicKey: device.publicKey)
        #expect(envelope.version == 1)
        #expect(try Ecdh.unpackDeviceEnvelope(envelope, devicePrivateKey: stored) == vaultKey)
        // Wire layout: 65-byte ephemeral key + 32-byte key + 16-byte tag.
        #expect(Data(base64Encoded: envelope.ciphertext)?.count == 65 + 32 + 16)
        #expect(throws: CryptoError.decryptionFailed) {
            _ = try Ecdh.unpackDeviceEnvelope(envelope, devicePrivateKey: Ecdh.generateKeyPair())
        }
        #expect(throws: CryptoError.payloadTooShort) {
            _ = try Ecdh.unpackDeviceEnvelope(Envelope(ciphertext: Data(count: 65).base64EncodedString(), nonce: envelope.nonce), devicePrivateKey: device)
        }
        #expect(throws: CryptoError.invalidPrivateKey) { _ = try Ecdh.importPrivateKey(Data([1, 2, 3])) }
    }
}
