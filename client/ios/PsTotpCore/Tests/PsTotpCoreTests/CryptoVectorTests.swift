import Foundation
import Testing
@testable import PsTotpCore

@Suite("Crypto known-answer vectors")
struct CryptoVectorTests {
    let v = Vectors.shared

    @Test func hkdf() {
        for e in v.hkdf {
            let okm = Hkdf.derive(ikm: Data(hex: e.ikmHex), info: e.info, length: e.length)
            #expect(okm.hex == e.okmHex, "info=\(e.info)")
        }
    }

    @Test func hmacSha256() {
        for e in v.hmacSha256 {
            #expect(Hkdf.hmacSha256(key: Data(hex: e.keyHex), data: Data(hex: e.messageHex)).hex == e.macHex)
        }
    }

    @Test func sha256Hex() {
        for e in v.sha256 {
            #expect(Hash.sha256Hex(Data(hex: e.inputHex)) == e.digestHex)
        }
    }

    @Test func base32Encode() throws {
        for e in v.base32 {
            #expect(Base32.encode(Data(hex: e.inputHex)) == e.encoded)
            #expect(try Base32.decode(e.encoded).hex == e.inputHex)
        }
    }

    @Test func totp() throws {
        for e in v.totp {
            let code = try TotpGenerator.generate(
                secret: e.secretBase32, algorithm: e.algorithm,
                digits: e.digits, period: e.period, timestampSeconds: e.timestamp)
            #expect(code == e.code, "\(e.algorithm) t=\(e.timestamp) period=\(e.period)")
        }
    }

    @Test func argon2idMatchesReference() throws {
        for e in v.argon2id {
            let h: Data
            if e.memoryKb == 65536 && e.iterations == 3 && e.parallelism == 4 {
                h = try Argon2.hash(password: e.password, salt: Data(hex: e.saltHex))
            } else {
                h = try Argon2.hash(password: e.password, salt: Data(hex: e.saltHex),
                                    memoryMb: e.memoryKb / 1024, iterations: e.iterations, parallelism: e.parallelism)
            }
            #expect(h.hex == e.hashHex, "password=\(e.password)")
        }
    }

    @Test func keyDerivationChain() throws {
        let k = v.keyDerivation
        let authKey = try KeyDerivation.derivePasswordAuthKey(password: k.password, salt: Data(hex: k.saltHex))
        #expect(authKey.hex == k.authKeyHex)
        #expect(KeyDerivation.deriveVerifier(authKey: authKey).hex == k.verifierHex)
        #expect(KeyDerivation.deriveEnvelopeKey(authKey: authKey).hex == k.envelopeKeyHex)
        #expect(KeyDerivation.deriveRecoveryUnlockKey(recoverySeed: authKey).hex == k.recoveryUnlockKeyHex)
    }
}
