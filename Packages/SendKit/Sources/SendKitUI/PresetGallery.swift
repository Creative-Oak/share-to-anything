import SendKit
import SwiftUI
import UniformTypeIdentifiers

/// "Add Endpoint": pick a ready-made template or import one from a file.
struct PresetGallery: View {
    var onAdd: (Endpoint) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(EndpointPreset.Category.allCases, id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(EndpointPreset.all.filter { $0.category == category && $0.isAvailable }) { preset in
                            Button {
                                onAdd(preset.make())
                                dismiss()
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.name)
                                        Text(preset.summary).font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: preset.symbol)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Add Endpoint")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Import…", systemImage: "square.and.arrow.down") { isImporting = true }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    onAdd(try Endpoint.importing(Data(contentsOf: url)))
                    dismiss()
                } catch {
                    importError = error.localizedDescription
                }
            }
            .alert("Couldn't import", isPresented: .constant(importError != nil)) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 600)
        #endif
    }
}

/// An endpoint as a JSON file, for the export panel.
struct EndpointDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(_ endpoint: Endpoint) {
        data = (try? endpoint.exportData()) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
