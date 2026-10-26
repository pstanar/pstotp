import Foundation
import Testing
@testable import PsTotpCore

@Suite("Crypto behaviour (ported from Kotlin tests)")
struct BehaviourTests {
    @Test func aesGcmRoundTripAndLayout() throws {
        let key = KeyDerivation.randomBytes(32)
        let plaintext = Data("hello vault".utf8)
        let payload = try AesGcm.encrypt(key: key, plaintext: plaintext)
        #expect(payload.count == 12 + plaintext.count + 16)
        #expect(try AesGcm.decrypt(key: key, payload: payload) == plaintext)
    }

    @Test func aesGcmAssociatedDataIsBound() throws {
        let key = KeyDerivation.randomBytes(32)
        let payload = try AesGcm.encrypt(key: key, plaintext: Data("x".utf8), associatedData: Data("entry-1".utf8))
        #expect(throws: CryptoError.decryptionFailed) {
            try AesGcm.decrypt(key: key, payload: payload, associatedData: Data("entry-2".utf8))
        }
        #expect(throws: CryptoError.decryptionFailed) {
            try AesGcm.decrypt(key: key, payload: payload)
        }
    }

    @Test func aesGcmRejectsTamperingWrongKeyAndBadSizes() throws {
        let key = KeyDerivation.randomBytes(32)
        var payload = try AesGcm.encrypt(key: key, plaintext: Data("secret".utf8))
        payload[payload.count - 1] ^= 0x01
        #expect(throws: CryptoError.decryptionFailed) { try AesGcm.decrypt(key: key, payload: payload) }
        #expect(throws: CryptoError.invalidKeyLength(expected: 32)) {
            try AesGcm.encrypt(key: Data(count: 16), plaintext: Data())
        }
        #expect(throws: CryptoError.payloadTooShort) {
            try AesGcm.decrypt(key: key, payload: Data(count: 12))
        }
    }

    @Test func kdfFloorsRejectDowngrade() {
        let salt = Data(count: 16)
        #expect(throws: CryptoError.self) { try Argon2.hash(password: "p", salt: salt, memoryMb: 16, iterations: 3, parallelism: 4) }
        #expect(throws: CryptoError.self) { try Argon2.hash(password: "p", salt: salt, memoryMb: 64, iterations: 1, parallelism: 4) }
        #expect(throws: CryptoError.self) { try Argon2.hash(password: "p", salt: salt, memoryMb: 64, iterations: 3, parallelism: 0) }
    }

    @Test func setupThenUnlock() throws {
        let setup = try KeyDerivation.setupPassword("hunter2-hunter2")
        let ok = try KeyDerivation.unlockVault(
            password: "hunter2-hunter2", salt: setup.salt,
            storedVerifier: setup.verifier, encryptedVaultKey: setup.encryptedVaultKey)
        #expect(ok == setup.vaultKey)
        let bad = try KeyDerivation.unlockVault(
            password: "wrong", salt: setup.salt,
            storedVerifier: setup.verifier, encryptedVaultKey: setup.encryptedVaultKey)
        #expect(bad == nil)
    }

    @Test func base32ToleratesPaddingSpacesAndRejectsGarbage() throws {
        let clean = try Base32.decode("JBSWY3DPEHPK3PXP")
        #expect(try Base32.decode("JBSWY3DPEHPK3PXP====") == clean)
        #expect(try Base32.decode("JBSW Y3DP EHPK 3PXP") == clean)
        #expect(throws: CryptoError.invalidBase32Character("1")) { try Base32.decode("JBSW1") }
    }

    @Test func timeRemainingInRange() {
        #expect((1...30).contains(TotpGenerator.timeRemaining()))
        #expect(TotpGenerator.timeRemaining(period: 30, now: 60) == 30)
        #expect(TotpGenerator.timeRemaining(period: 30, now: 89) == 1)
    }

    /// Imported or synced entries can carry any numbers; they must fail, not trap.
    @Test func generatorRejectsParametersThatWouldTrap() {
        let secret = "JBSWY3DPEHPK3PXP"
        #expect(throws: CryptoError.invalidTotpParameters) { try TotpGenerator.generate(secret: secret, period: 0) }
        #expect(throws: CryptoError.invalidTotpParameters) { try TotpGenerator.generate(secret: secret, period: -30) }
        #expect(throws: CryptoError.invalidTotpParameters) { try TotpGenerator.generate(secret: secret, digits: 0) }
        #expect(throws: CryptoError.invalidTotpParameters) { try TotpGenerator.generate(secret: secret, digits: 20) }
        #expect(TotpGenerator.timeRemaining(period: 0, now: 100) == 0)
        #expect(TotpGenerator.timeRemaining(period: -30, now: 100) == 0)
    }
}
