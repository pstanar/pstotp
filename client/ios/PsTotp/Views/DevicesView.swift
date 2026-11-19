import PsTotpCore
import SwiftUI

/// The account's devices (Android's `DevicesScreen`, grouped like the web client): approve or reject
/// devices waiting to join, revoke approved ones. Connected only.
struct DevicesView: View {
    @Bindable var model: AppModel

    @State private var groups = DeviceGroups(pending: [], approved: [], revoked: [])
    @State private var currentDeviceId: String?
    @State private var loading = true
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var working = false
    @State private var revoking: DeviceInfoDto?

    var body: some View {
        List {
            if let loadError {
                Section { AuthError(message: loadError).accessibilityIdentifier("devices.error") }
                    .listRowBackground(Color.clear)
            } else if loading && groups.isEmpty {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
                    .listRowBackground(Color.clear)
            } else if groups.isEmpty {
                Section { Text("No devices registered.").foregroundStyle(Palette.onSurfaceVariant) }
                    .listRowBackground(Palette.surface)
            }

            if let actionError {
                Section { AuthError(message: actionError).accessibilityIdentifier("devices.actionError") }
                    .listRowBackground(Color.clear)
            }

            if !groups.pending.isEmpty {
                Section("Pending approval") {
                    ForEach(groups.pending, id: \.deviceId) { device in
                        VStack(alignment: .leading, spacing: 10) {
                            DeviceRow(device: device, isCurrent: false)
                            HStack(spacing: 12) {
                                Button("Approve") { run { await model.approveDevice(device) } }
                                    .buttonStyle(.borderedProminent)
                                    .accessibilityIdentifier("devices.approve.\(device.deviceId)")
                                Button("Reject") { run { await model.rejectDevice(device) } }
                                    .buttonStyle(.bordered)
                                    .accessibilityIdentifier("devices.reject.\(device.deviceId)")
                            }
                            .disabled(working)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listRowBackground(Palette.surface)
            }

            if !groups.approved.isEmpty {
                Section("Approved") {
                    ForEach(groups.approved, id: \.deviceId) { device in
                        let isCurrent = device.deviceId == currentDeviceId
                        DeviceRow(device: device, isCurrent: isCurrent)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !isCurrent {
                                    Button("Revoke", role: .destructive) { revoking = device }
                                        .accessibilityIdentifier("devices.revoke.\(device.deviceId)")
                                }
                            }
                    }
                }
                .listRowBackground(Palette.surface)
            }

            if !groups.revoked.isEmpty {
                Section("Revoked") {
                    ForEach(groups.revoked, id: \.deviceId) { device in
                        DeviceRow(device: device, isCurrent: false).opacity(0.6)
                    }
                }
                .listRowBackground(Palette.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("Devices")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog(
            "Revoke \(revoking?.deviceName ?? "device")?", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
            titleVisibility: .visible
        ) {
            Button("Revoke", role: .destructive) {
                if let device = revoking { run { await model.revokeDevice(device) } }
                revoking = nil
            }
        } message: {
            Text("It will be signed out and can no longer unlock your vault.")
        }
    }

    private func load() async {
        switch await model.loadDevices() {
        case .success(let snapshot):
            groups = snapshot.groups
            currentDeviceId = snapshot.currentDeviceId
            loadError = nil
        case .failure(let failure):
            loadError = failure.message
        }
        loading = false
    }

    /// Runs a device action, then refreshes the list.
    private func run(_ action: @escaping () async -> String?) {
        working = true
        actionError = nil
        Task {
            actionError = await action()
            await load()
            working = false
        }
    }
}

private struct DeviceRow: View {
    let device: DeviceInfoDto
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ["ios", "android"].contains(device.platform.lowercased()) ? "iphone" : "desktopcomputer")
                .foregroundStyle(Palette.onSurfaceVariant)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.deviceName)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.onSurfaceVariant)
            }
            Spacer()
            if isCurrent {
                Text("This device")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.primary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("devices.row.\(device.deviceId)")
    }

    private var detail: String {
        switch device.status {
        case "pending": "Waiting for approval"
        case "approved": device.approvedAt.map { "Approved \(ServerTime.day($0))" } ?? "Approved"
        default: device.revokedAt.map { "Revoked \(ServerTime.day($0))" } ?? "Revoked"
        }
    }
}
