import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Applies an endpoint's `Preparation` to copies of the files in a temporary folder.
struct FilePreparer {
    var preparation: Preparation
    var endpointName: String
    let workFolder = FileManager.default.temporaryDirectory
        .appending(path: "ShareToAnything-\(UUID().uuidString)", directoryHint: .isDirectory)

    /// Returns the files to send: untouched originals where nothing applies, otherwise prepared copies.
    func prepare(_ files: [SharedFile]) throws -> [SharedFile] {
        guard preparation.isActive else { return files }
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
        return try files.map(prepare)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: workFolder)
    }

    private func prepare(_ file: SharedFile) throws -> SharedFile {
        var current = file
        if Self.isImage(file) {
            let limit = preparation.maxSizeMB > 0 ? Int(preparation.maxSizeMB * 1_048_576) : nil
            let isJPEG = ["jpg", "jpeg"].contains(file.ext.lowercased())
            let tooBig = limit.map { file.size > $0 } ?? false

            switch preparation.imageFormat {
            case .pdf:
                // Leave a little room for the PDF wrapper around the JPEG stream.
                let jpeg = try Self.jpegData(from: file, limit: limit.map { $0 - 4096 })
                current = try write(try Self.pdfData(fromJPEG: jpeg), named: "\(file.basename).pdf")
            case .jpeg where !isJPEG || tooBig, .original where tooBig:
                current = try write(try Self.jpegData(from: file, limit: limit), named: "\(file.basename).jpg")
            default:
                break
            }
        }

        if !preparation.rename.isEmpty {
            var name = Self.sanitize(Template(file: current, endpointName: endpointName).expand(preparation.rename))
            // Without an extension the file type is lost, so keep the current one.
            if !name.isEmpty, (name as NSString).pathExtension.isEmpty, !current.ext.isEmpty { name += ".\(current.ext)" }
            if !name.isEmpty, name != current.filename {
                let destination = Self.uniqueURL(for: name, in: workFolder)
                if current.url.path.hasPrefix(workFolder.path) {
                    try FileManager.default.moveItem(at: current.url, to: destination)
                } else {
                    try current.data().write(to: destination)
                }
                current = SharedFile(url: destination)
            }
        }
        return current
    }

    private func write(_ data: Data, named name: String) throws -> SharedFile {
        let url = Self.uniqueURL(for: name, in: workFolder)
        try data.write(to: url)
        return SharedFile(url: url)
    }

    // MARK: Images

    static func isImage(_ file: SharedFile) -> Bool {
        UTType(filenameExtension: file.ext)?.conforms(to: .image) ?? false
    }

    /// Re-encodes as JPEG (upright), scaling down until it fits `limit` bytes.
    static func jpegData(from file: SharedFile, limit: Int?) throws -> Data {
        let contents = try file.data()
        guard let source = CGImageSourceCreateWithData(contents as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw SendError("Couldn't read \(file.filename) as an image.")
        }

        var maxPixel = max(width, height)
        var quality = 0.85
        var best: Data?
        for _ in 0..<12 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { break }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { break }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { break }
            best = output as Data
            guard let limit, output.length > limit else { return output as Data }
            maxPixel = Int(Double(maxPixel) * 0.8)
            quality = max(0.6, quality - 0.05)
        }
        if let best, limit == nil { return best }
        throw SendError("Couldn't shrink \(file.filename) below the size limit.")
    }

    /// Wraps a JPEG in a single-page PDF sized to the image at 150 dpi.
    static func pdfData(fromJPEG jpeg: Data) throws -> Data {
        guard let provider = CGDataProvider(data: jpeg as CFData),
              let image = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            throw SendError("Couldn't create a PDF from the image.")
        }
        let scale = 72.0 / 150.0
        var box = CGRect(x: 0, y: 0, width: Double(image.width) * scale, height: Double(image.height) * scale)
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw SendError("Couldn't create a PDF from the image.")
        }
        context.beginPDFPage(nil)
        context.draw(image, in: box)
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }

    // MARK: Names

    static func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `name`, or "name 2", "name 3"… if something with that name already exists in `folder`.
    static func uniqueURL(for name: String, in folder: URL) -> URL {
        var candidate = folder.appending(path: name)
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}
