import Foundation

/// .NET's mixed-endian GUID byte layout, as the web client's `guidToBytes` and Android's `GuidBytes`.
enum GuidBytes {
    static func toBytes(_ guid: String) throws -> Data {
        let hex = guid.replacingOccurrences(of: "-", with: "")
        guard hex.count == 32, hex.allSatisfy(\.isHexDigit), hex.allSatisfy(\.isASCII) else {
            throw CryptoError.invalidGuid(guid)
        }
        let raw = Array(Data(hexString: hex))
        // First three groups little-endian, last two big-endian.
        return Data([raw[3], raw[2], raw[1], raw[0], raw[5], raw[4], raw[7], raw[6]] + raw[8..<16])
    }
}

private extension Data {
    init(hexString: String) {
        var bytes = [UInt8]()
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            bytes.append(UInt8(hexString[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }
}

/// Client proof for password login: proves knowledge of the verifier without sending it.
/// Must match the web client's `computeClientProof`.
public enum ClientProof {
    /// HMAC-SHA256(key = verifier, message = nonce || guidToBytes(loginSessionId)).
    public static func compute(verifier: Data, nonce: Data, loginSessionId: String) throws -> Data {
        Hkdf.hmacSha256(key: verifier, data: nonce + (try GuidBytes.toBytes(loginSessionId)))
    }
}
