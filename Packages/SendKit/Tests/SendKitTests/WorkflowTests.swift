import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SendKit

private func tempFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "STA-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A noisy (incompressible) PNG, so size limits actually bite.
private func noisyPNG(named name: String, side: Int) throws -> SharedFile {
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    for index in pixels.indices { pixels[index] = UInt8.random(in: 0...255) }
    let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let url = try tempFolder().appending(path: name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    #expect(CGImageDestinationFinalize(destination))
    return SharedFile(url: url)
}

@Suite struct CompatibilityTests {
    @Test func decodesEndpointsSavedByVersion1() throws {
        let json = #"""
        {"endpoints": [
          {"id": "11111111-1111-1111-1111-111111111111", "name": "Old HTTP", "symbol": "network",
           "kind": {"http": {"_0": {"url": "https://x", "method": "POST", "headers": [], "bodyMode": "multipart",
                                    "fileField": "file", "formFields": [], "jsonTemplate": ""}}}},
          {"id": "22222222-2222-2222-2222-222222222222", "name": "From the future", "symbol": "sparkles",
           "kind": {"teleport": {"_0": {}}}}
        ], "modified": 0}
        """#
        let list = try JSONDecoder().decode(EndpointList.self, from: Data(json.utf8))
        #expect(list.endpoints.map(\.name) == ["Old HTTP"])
        #expect(list.endpoints[0].prepare == Preparation())
        #expect(list.endpoints[0].fileTypes == "")
    }

    @Test func presetsAreValidAndIndependent() throws {
        #expect(Set(EndpointPreset.all.map(\.id)).count == EndpointPreset.all.count)
        for preset in EndpointPreset.all {
            let first = preset.make(), second = preset.make()
            #expect(first.id != second.id)
            let imported = try Endpoint.importing(first.exportData())
            #expect(imported.id != first.id)
            #expect(imported.name == first.name)
            #expect(imported.kindLabel == first.kindLabel)
        }
        #expect(throws: SendError.self) { try Endpoint.importing(Data("{}".utf8)) }
    }
}

@Suite struct DuplicateTests {
    @Test func missingJSONTemplateGetsTheDefault() throws {
        let json = #"{"url": "https://example.com", "method": "POST", "bodyMode": "json"}"#
        let config = try JSONDecoder().decode(HTTPConfig.self, from: Data(json.utf8))
        #expect(config.jsonTemplate == HTTPConfig().jsonTemplate)
    }

    @Test func secretKeysLineUpWithTheCopy() {
        var config = HTTPConfig()
        config.headers = [Header(name: "X-Token", value: "", isSecret: true), Header(name: "Accept", value: "*/*", isSecret: false)]
        let endpoint = Endpoint(name: "Hook", symbol: "network", kind: .http(config))
        let copy = endpoint.withFreshIdentifiers()
        #expect(endpoint.secretKeys.count == 2)
        #expect(copy.secretKeys.count == 2)
        #expect(Set(endpoint.secretKeys).isDisjoint(with: copy.secretKeys))
    }
}

@Suite struct FilterTests {
    @Test func fileTypeFilter() {
        var endpoint = Endpoint.newHTTP()
        #expect(endpoint.isOffered(for: [URL(fileURLWithPath: "/a.zip")]))
        endpoint.fileTypes = "PDF, .jpg"
        #expect(endpoint.isOffered(for: [URL(fileURLWithPath: "/a.pdf"), URL(fileURLWithPath: "/b.JPG")]))
        #expect(!endpoint.isOffered(for: [URL(fileURLWithPath: "/a.pdf"), URL(fileURLWithPath: "/b.zip")]))

        let dinero = Endpoint.newDinero()
        #expect(dinero.isOffered(for: [URL(fileURLWithPath: "/scan.heic")]))
        #expect(!dinero.isOffered(for: [URL(fileURLWithPath: "/notes.docx")]))
    }

    @Test func urlExpansionEncodesValues() {
        let template = Template(values: ["filename": "Kvittering #1 æ?.pdf", "secret": "123:ABC"])
        #expect(template.expandURL("https://h/dav/{filename}") == "https://h/dav/Kvittering%20%231%20%C3%A6%3F.pdf")
        #expect(template.expandURL("https://api.telegram.org/bot{secret}/sendDocument") == "https://api.telegram.org/bot123:ABC/sendDocument")
    }

    @Test func basicAuthAndRawPut() throws {
        var config = HTTPConfig()
        config.method = .PUT
        config.bodyMode = .raw
        config.url = "https://cloud.example.com/dav/{filename}"
        config.username = "magnus"
        let endpoint = Endpoint(name: "DAV", symbol: "cloud", kind: .http(config))
        let file = SharedFile(url: try tempFolder().appending(path: "a b.pdf"))
        try Data("PDF".utf8).write(to: file.url)
        let request = try HTTPSender(endpoint: endpoint, config: config, secrets: SecretStore(accessGroup: nil), session: .shared).makeRequest(for: file)
        #expect(request.url?.absoluteString == "https://cloud.example.com/dav/a%20b.pdf")
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic \(Data("magnus:".utf8).base64EncodedString())")
        #expect(request.httpBody == Data("PDF".utf8))
    }
}

@Suite struct PreparationTests {
    @Test func shrinksImagesToTheLimit() throws {
        let png = try noisyPNG(named: "Photo.png", side: 1400)
        #expect(png.size > 1_000_000)
        var preparation = Preparation()
        preparation.maxSizeMB = 0.3
        let preparer = FilePreparer(preparation: preparation, endpointName: "E")
        let result = try preparer.prepare([png])
        #expect(result[0].filename == "Photo.jpg")
        #expect(result[0].size <= 314_573)
        #expect(FileManager.default.fileExists(atPath: png.url.path), "original must be untouched")
        preparer.cleanUp()
        #expect(!FileManager.default.fileExists(atPath: result[0].url.path))
    }

    @Test func convertsToPDFAndRenames() throws {
        let png = try noisyPNG(named: "Receipt.png", side: 200)
        var preparation = Preparation()
        preparation.imageFormat = .pdf
        preparation.rename = "Bilag {basename}.{ext}"
        let result = try FilePreparer(preparation: preparation, endpointName: "E").prepare([png])
        #expect(result[0].filename == "Bilag Receipt.pdf")
        #expect(try result[0].data().prefix(4) == Data("%PDF".utf8))
    }

    @Test func renameKeepsTheExtension() throws {
        let pdf = try SampleFile.make()
        var preparation = Preparation()
        preparation.rename = "Bilag {date}"
        let result = try FilePreparer(preparation: preparation, endpointName: "E").prepare([pdf])
        #expect(result[0].ext == "pdf")
    }

    @Test func leavesOtherFilesAlone() throws {
        let pdf = try SampleFile.make()
        #expect(try pdf.data().prefix(4) == Data("%PDF".utf8))
        var preparation = Preparation()
        preparation.imageFormat = .jpeg
        preparation.maxSizeMB = 0.001
        #expect(try FilePreparer(preparation: preparation, endpointName: "E").prepare([pdf]) == [pdf])
    }
}

@Suite struct LocalActionTests {
    @Test func folderEndpointCopiesRenamesTagsAndArchives() async throws {
        let inbox = try tempFolder(), destination = try tempFolder(), archive = try tempFolder()
        let original = SharedFile(url: inbox.appending(path: "Kvittering.pdf"))
        try FileManager.default.copyItem(at: try SampleFile.make().url, to: original.url)

        var endpoint = Endpoint(name: "Filing", symbol: "folder", kind: .folder(FolderConfig(path: destination.path)))
        endpoint.prepare.rename = "2026 {basename}.{ext}"
        endpoint.afterSend.tag = "Sent"
        endpoint.afterSend.moveTo = archive.path

        let sender = Sender(secrets: SecretStore(accessGroup: nil))
        guard case .sent(let message) = try await sender.send([original], to: endpoint) else {
            Issue.record("expected .sent"); return
        }
        #expect(message.hasPrefix("Copied Kvittering.pdf") || message.hasPrefix("Copied 2026 Kvittering.pdf"), "\(message)")
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "2026 Kvittering.pdf").path))

        // The original was tagged, then archived.
        let archived = archive.appending(path: "Kvittering.pdf")
        #expect(!FileManager.default.fileExists(atPath: original.url.path))
        #expect(try archived.resourceValues(forKeys: [.tagNamesKey]).tagNames == ["Sent"])

        // A second file with the same name doesn't overwrite the first.
        try FileManager.default.copyItem(at: archived, to: original.url)
        _ = try await sender.send([original], to: endpoint)
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "2026 Kvittering 2.pdf").path))
    }

    @Test func moveRemovesTheOriginal() async throws {
        let inbox = try tempFolder(), destination = try tempFolder()
        let original = SharedFile(url: inbox.appending(path: "a.pdf"))
        try Data("x".utf8).write(to: original.url)
        let endpoint = Endpoint(name: "Move", symbol: "folder", kind: .folder(FolderConfig(path: destination.path, move: true)))
        _ = try await Sender(secrets: SecretStore(accessGroup: nil)).send([original], to: endpoint)
        #expect(!FileManager.default.fileExists(atPath: original.url.path))
        #expect(FileManager.default.fileExists(atPath: destination.appending(path: "a.pdf").path))
    }

    @Test func rejectsFilesOutsideTheFilter() async throws {
        var endpoint = Endpoint(name: "PDF only", symbol: "folder", kind: .folder(FolderConfig(path: try tempFolder().path)))
        endpoint.fileTypes = "pdf"
        let file = SharedFile(url: try tempFolder().appending(path: "a.zip"))
        try Data("x".utf8).write(to: file.url)
        await #expect(throws: SendError.self) { try await Sender(secrets: SecretStore(accessGroup: nil)).send([file], to: endpoint) }
    }
}
