import Foundation
import Testing
@testable import PsTotpCore

@Suite("Devices")
struct DevicesTests {
    private func device(_ id: String, _ status: String, approved: String? = nil, revoked: String? = nil,
                        key: String? = nil, request: String? = nil) throws -> DeviceInfoDto {
        func q(_ s: String?) -> String { s.map { "\"\($0)\"" } ?? "null" }
        return try JSONDecoder().decode(DeviceInfoDto.self, from: Data("""
        {"deviceId":"\(id)","deviceName":"Dev \(id)","platform":"ios","status":"\(status)",
         "devicePublicKey":\(q(key)),"approvalRequestId":\(q(request)),"approvedAt":\(q(approved)),"revokedAt":\(q(revoked))}
        """.utf8))
    }

    @Test func groupsAndOrdersLikeTheClients() throws {
        let groups = DeviceListing.group([
            try device("a1", "approved", approved: "2026-01-01T00:00:00Z"),
            try device("r1", "revoked", approved: "2026-01-02T00:00:00Z", revoked: "2026-03-01T00:00:00Z"),
            try device("p1", "pending"),
            try device("a2", "approved", approved: "2026-05-01T00:00:00Z"),
            try device("r2", "revoked", approved: "2026-01-02T00:00:00Z", revoked: "2026-04-01T00:00:00Z"),
            try device("p2", "pending"),
            try device("a3", "approved", approved: "2026-05-01T00:00:00Z"),
            try device("x", "something-new", revoked: "2026-06-01T00:00:00Z"),
        ])
        #expect(groups.pending.map(\.deviceId) == ["p1", "p2"])
        #expect(groups.approved.map(\.deviceId) == ["a2", "a3", "a1"])     // newest first, ties keep server order
        #expect(groups.revoked.map(\.deviceId) == ["x", "r2", "r1"])       // newest revocation first
        #expect(!groups.isEmpty && DeviceListing.group([]).isEmpty)
    }

    @Test func revokedDevicesWithoutADateFallBackToTheApprovalDate() throws {
        let groups = DeviceListing.group([
            try device("old", "revoked", approved: "2026-01-01T00:00:00Z"),
            try device("new", "revoked", approved: "2026-02-01T00:00:00Z"),
        ])
        #expect(groups.revoked.map(\.deviceId) == ["new", "old"])
    }

    @Test func approvalWrapsTheVaultKeyForThePendingDevicesKey() throws {
        let theirKey = Ecdh.generateKeyPair()
        let pending = try device("p", "pending", key: Ecdh.exportPublicKey(theirKey.publicKey).base64EncodedString(), request: "req-1")
        let vaultKey = KeyDerivation.generateVaultKey()

        let envelope = try DeviceApproval.envelope(for: pending, vaultKey: vaultKey)
        #expect(try Ecdh.unpackDeviceEnvelope(envelope, devicePrivateKey: theirKey) == vaultKey)
        #expect(DeviceApproval.approvalRequestId(for: pending) == "req-1")
        #expect(DeviceApproval.approvalRequestId(for: try device("q", "pending")) == "q")
    }

    @Test func aPendingDeviceWithoutAUsableKeyCantBeApproved() throws {
        let vaultKey = KeyDerivation.generateVaultKey()
        for key in [nil, "", "not base64!!", Data(repeating: 4, count: 65).base64EncodedString(), Data(count: 10).base64EncodedString()] {
            #expect(throws: DeviceApprovalError.missingPublicKey) {
                _ = try DeviceApproval.envelope(for: try device("p", "pending", key: key), vaultKey: vaultKey)
            }
        }
    }
}
