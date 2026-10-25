import Foundation

extension Data {
    init(hex: String) {
        precondition(hex.count % 2 == 0)
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }

    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

struct Vectors: Decodable {
    struct Hkdf: Decodable { let ikmHex: String; let info: String; let length: Int; let okmHex: String }
    struct Hmac: Decodable { let keyHex: String; let messageHex: String; let macHex: String }
    struct Sha: Decodable { let inputHex: String; let digestHex: String }
    struct Argon: Decodable {
        let password: String; let saltHex: String
        let memoryKb: Int; let iterations: Int; let parallelism: Int; let hashHex: String
    }
    struct KeyDeriv: Decodable {
        let password: String; let saltHex: String; let authKeyHex: String
        let verifierHex: String; let envelopeKeyHex: String; let recoveryUnlockKeyHex: String
    }
    struct Totp: Decodable {
        let secretBase32: String; let algorithm: String
        let digits: Int; let period: Int; let timestamp: Int64; let code: String
    }
    struct B32: Decodable { let inputHex: String; let encoded: String }

    struct Entry: Decodable {
        let issuer: String; let accountName: String; let secret: String
        let algorithm: String; let digits: Int; let period: Int; let icon: String?
    }
    struct EncryptedExport: Decodable {
        let version: Int; let format: String; let salt: String; let ciphertext: String; let nonce: String
    }
    struct ExportFixtures: Decodable {
        let entries: [Entry]; let password: String
        let encryptedExport: EncryptedExport; let googleMigrationUri: String
    }

    let hkdf: [Hkdf]
    let hmacSha256: [Hmac]
    let sha256: [Sha]
    let argon2id: [Argon]
    let keyDerivation: KeyDeriv
    let totp: [Totp]
    let base32: [B32]
    let exportFixtures: ExportFixtures

    static let shared: Vectors = {
        let url = Bundle.module.url(forResource: "crypto-vectors", withExtension: "json", subdirectory: "Vectors")!
        return try! JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url))
    }()
}
