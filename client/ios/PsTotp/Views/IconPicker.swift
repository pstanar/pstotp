import PhotosUI
import PsTotpCore
import SwiftUI

/// The "Icon" part of the Edit and manual-add forms (Android's `IconPicker`): preview with Upload /
/// Clear, fetch from a URL, "My icons" (tap to use, long-press to rename or delete) and common emoji.
/// Uploaded and fetched images are normalised to 64×64 and saved to My icons.
struct IconPicker: View {
    @Bindable var model: AppModel
    let issuer: String
    @Binding var icon: String?

    @State private var photo: PhotosPickerItem?
    @State private var urlText = ""
    @State private var fetching = false
    @State private var notice: String?
    @State private var renaming: LibraryIcon?
    @State private var renameText = ""

    static let emojis = [
        "🔒", "🔑", "📧", "💻", "☁️",
        "🏦", "🛒", "🎮", "📱", "🌐",
        "💳", "🎓", "⚙️", "🛡️", "🤖",
        "💬", "🎥", "🎵", "📚", "✈️",
    ]

    private let columns = [GridItem(.adaptive(minimum: 44, maximum: 52), spacing: 6)]

    var body: some View {
        Section("Icon") {
            HStack(spacing: 12) {
                ServiceIconView(issuer: issuer, icon: icon, size: 48)
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Upload", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("icon.upload")
                Spacer()
                if icon != nil {
                    Button(role: .destructive) { icon = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear icon")
                    .accessibilityIdentifier("icon.clear")
                }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                photo = nil
                upload(item)
            }

            HStack {
                TextField("Icon URL", text: $urlText, prompt: Text("https://example.com/favicon.ico"))
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .disabled(fetching)
                    .accessibilityIdentifier("icon.url")
                Button(fetching ? "…" : "Fetch", action: fetch)
                    .buttonStyle(.bordered)
                    .disabled(fetching || urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("icon.fetch")
            }

            if let notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(Palette.error)
                    .accessibilityIdentifier("icon.notice")
            }
        }
        .listRowBackground(Palette.surface)

        Section {
            if model.libraryIcons.isEmpty {
                Text("No custom icons yet. Upload an image or fetch one from a URL — it'll be saved here for reuse.")
                    .font(.footnote)
                    .foregroundStyle(Palette.onSurfaceVariant)
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(model.libraryIcons) { item in libraryTile(item) }
                }
            }
        } header: {
            Text(model.libraryIcons.isEmpty
                 ? "My icons" : "My icons (\(model.libraryIcons.count)/\(IconLibraryLimits.maxIcons))")
        }
        .listRowBackground(Palette.surface)
        .alert("Rename icon", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Label", text: $renameText)
            Button("Save") {
                if let target = renaming { Task { notice = await model.renameLibraryIcon(id: target.id, label: renameText) } }
            }
            Button("Cancel", role: .cancel) {}
        }

        Section {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Self.emojis, id: \.self) { emoji in
                    Button { icon = emoji } label: {
                        Text(emoji).font(.system(size: 26)).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .background(selectionBorder(icon == emoji))
                    .accessibilityLabel(emoji)
                    .accessibilityAddTraits(icon == emoji ? .isSelected : [])
                    .accessibilityIdentifier("icon.emoji.\(emoji)")
                }
            }
        }
        .listRowBackground(Palette.surface)
    }

    private func libraryTile(_ item: LibraryIcon) -> some View {
        Button { icon = item.data } label: {
            ServiceIconView(issuer: item.label, icon: item.data, size: 38)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .background(selectionBorder(icon == item.data))
        .contextMenu {
            Button("Rename") { renameText = item.label; renaming = item }
            Button("Delete", role: .destructive) { Task { notice = await model.removeLibraryIcon(id: item.id) } }
        }
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(icon == item.data ? .isSelected : [])
        .accessibilityIdentifier("icon.library.\(item.label)")
    }

    private func selectionBorder(_ selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(selected ? Palette.primary : .clear, lineWidth: 2)
    }

    // MARK: Adopting an icon

    /// Use the icon for this entry, then save it to My icons (which de-duplicates and enforces the caps).
    private func adopt(dataUrl: String, label: String, source: Data) async {
        icon = dataUrl
        notice = await model.addLibraryIcon(label: label, dataUrl: dataUrl, source: source)
    }

    private func upload(_ item: PhotosPickerItem) {
        notice = nil
        Task {
            guard let bytes = try? await item.loadTransferable(type: Data.self),
                  // Resizing a large photo is CPU work; keep it off the main actor.
                  let dataUrl = await Task.detached(priority: .userInitiated, operation: {
                      IconNormalizer.normalizedDataUrl(imageBytes: bytes)
                  }).value
            else {
                notice = "Could not read that image"
                return
            }
            await adopt(dataUrl: dataUrl, label: issuer.trimmingCharacters(in: .whitespacesAndNewlines), source: bytes)
        }
    }

    private func fetch() {
        let text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), IconNormalizer.isUrl(text) else {
            notice = "Could not fetch image"
            return
        }
        fetching = true
        notice = nil
        Task {
            defer { fetching = false }
            guard let fetched = await model.downloadIcon(from: url) else {
                notice = "Could not fetch image"
                return
            }
            let label = url.host().flatMap { $0.isEmpty ? nil : $0 }
                ?? (issuer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Icon" : issuer.trimmingCharacters(in: .whitespacesAndNewlines))
            await adopt(dataUrl: fetched.dataUrl, label: label, source: fetched.source)
            urlText = ""
        }
    }
}
