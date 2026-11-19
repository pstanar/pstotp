import Foundation

/// The device list as the Devices screen shows it (the web client's grouping; Android's order within it).
public struct DeviceGroups: Equatable, Sendable {
    public var pending: [DeviceInfoDto]
    public var approved: [DeviceInfoDto]
    public var revoked: [DeviceInfoDto]

    public init(pending: [DeviceInfoDto] = [], approved: [DeviceInfoDto] = [], revoked: [DeviceInfoDto] = []) {
        self.pending = pending
        self.approved = approved
        self.revoked = revoked
    }

    public var isEmpty: Bool { pending.isEmpty && approved.isEmpty && revoked.isEmpty }
}

public enum DeviceListing {
    /// Pending first (they need a decision), then approved (newest approval first), then revoked
    /// (newest revocation first). ISO 8601 strings sort lexicographically in time order; an unknown
    /// status counts as revoked, like Android.
    public static func group(_ devices: [DeviceInfoDto]) -> DeviceGroups {
        func newestFirst(_ list: [DeviceInfoDto], _ key: (DeviceInfoDto) -> String?) -> [DeviceInfoDto] {
            list.enumerated().sorted { a, b in
                let (ka, kb) = (key(a.element) ?? "", key(b.element) ?? "")
                return ka != kb ? ka > kb : a.offset < b.offset
            }.map(\.element)
        }
        return DeviceGroups(
            pending: devices.filter { $0.status == "pending" },
            approved: newestFirst(devices.filter { $0.status == "approved" }, \.approvedAt),
            revoked: newestFirst(devices.filter { $0.status != "pending" && $0.status != "approved" }) {
                $0.revokedAt ?? $0.approvedAt
            })
    }
}

public enum DeviceApprovalError: Error, Equatable, LocalizedError {
    /// The pending device never sent (or sent an unusable) public key.
    case missingPublicKey

    public var errorDescription: String? { "This device didn't provide a key, so it can't be approved." }
}

public enum DeviceApproval {
    /// Wraps the vault key for the pending device's public key — what approving it hands over.
    public static func envelope(for device: DeviceInfoDto, vaultKey: Data) throws -> Envelope {
        guard let keyB64 = device.devicePublicKey, let bytes = Data(base64Encoded: keyB64),
              let key = try? Ecdh.importPublicKey(bytes) else { throw DeviceApprovalError.missingPublicKey }
        return try Ecdh.packDeviceEnvelope(vaultKey: vaultKey, recipientPublicKey: key)
    }

    /// The id the server expects with an approval (it uses the device id when the list has no request id).
    public static func approvalRequestId(for device: DeviceInfoDto) -> String {
        device.approvalRequestId ?? device.deviceId
    }
}
