import PsTotpCore
import SwiftUI

/// The account's recent security events (Android's `AuditScreen`): what happened, when, and from
/// which address. Connected only.
struct AuditLogView: View {
    @Bindable var model: AppModel

    @State private var loaded = Loadable<[AuditEventDto]>()

    var body: some View {
        List {
            if let error = loaded.error {
                Section { AuthError(message: error).accessibilityIdentifier("audit.error") }
                    .listRowBackground(Color.clear)
            } else if loaded.isLoading {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
                    .listRowBackground(Color.clear)
            } else if (loaded.value ?? []).isEmpty {
                Section { Text("No audit events").foregroundStyle(Palette.onSurfaceVariant) }
                    .listRowBackground(Palette.surface)
                    .accessibilityIdentifier("audit.empty")
            } else {
                Section {
                    ForEach(loaded.value ?? [], id: \.id) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(AuditFormat.title(event.eventType))
                                Spacer()
                                Text(AuditFormat.timestamp(event.createdAt))
                                    .font(.footnote)
                                    .foregroundStyle(Palette.onSurfaceVariant)
                            }
                            if let ip = event.ipAddress {
                                Text(ip)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.onSurfaceVariant)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("audit.row.\(event.id)")
                    }
                }
                .listRowBackground(Palette.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("Audit Log")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        loaded.apply(await model.loadAuditEvents())
    }
}
