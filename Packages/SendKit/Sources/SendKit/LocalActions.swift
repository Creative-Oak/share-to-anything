import CoreGraphics
import CoreText
import Foundation

extension FolderConfig {
    public var folderURL: URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Copies (or moves) each prepared file into the folder. `originals` are removed when moving.
    func deliver(_ files: [SharedFile], originals: [SharedFile], endpointName: String) throws {
        #if os(macOS)
        guard let folder = folderURL else { throw SendError("\(endpointName) has no folder set.") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files {
            let destination = FilePreparer.uniqueURL(for: file.filename, in: folder)
            try FileManager.default.copyItem(at: file.url, to: destination)
        }
        if move {
            for original in originals { try FileManager.default.removeItem(at: original.url) }
        }
        #else
        throw SendError("Folder endpoints only work on Mac.")
        #endif
    }
}

extension AfterSend {
    /// Tags and/or moves the originals. Never throws: a failed follow-up must not turn a
    /// successful send into an error. Returns a note to append to the result, if anything went wrong.
    func apply(to originals: [SharedFile]) -> String? {
        #if os(macOS)
        guard isActive else { return nil }
        var problems: [String] = []
        for file in originals where FileManager.default.fileExists(atPath: file.url.path) {
            if !tag.isEmpty {
                do {
                    let existing = try file.url.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
                    if !existing.contains(tag) {
                        try (file.url as NSURL).setResourceValue(existing + [tag], forKey: .tagNamesKey)
                    }
                } catch {
                    problems.append("couldn't tag \(file.filename)")
                }
            }
            if let folder = FolderConfig(path: moveTo).folderURL {
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.moveItem(at: file.url, to: FilePreparer.uniqueURL(for: file.filename, in: folder))
                } catch {
                    problems.append("couldn't move \(file.filename)")
                }
            }
        }
        return problems.isEmpty ? nil : problems.joined(separator: ", ")
        #else
        return nil
        #endif
    }
}

/// A tiny PDF for the "Send Test File" button.
public enum SampleFile {
    public static func make(now: Date = Date()) throws -> SharedFile {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ShareToAnything-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "Share to Anything test.pdf")

        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw SendError("Couldn't create the test file.")
        }
        context.beginPDFPage(nil)
        let lines = ["Share to Anything", "Test file sent \(now.formatted(date: .abbreviated, time: .shortened))"]
        for (index, text) in lines.enumerated() {
            let font = CTFontCreateWithName("Helvetica" as CFString, index == 0 ? 28 : 14, nil)
            let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            context.textPosition = CGPoint(x: 72, y: 742 - CGFloat(index) * 36)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        context.endPDFPage()
        context.closePDF()
        return SharedFile(url: url)
    }
}
