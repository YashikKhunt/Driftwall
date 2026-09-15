import Foundation

@main struct VideoLibraryTests {
    static func main() throws {
        let manager = FileManager.default
        let dir = manager.temporaryDirectory.appendingPathComponent("DriftwallLibraryTest-" + UUID().uuidString).resolvingSymlinksInPath()
        try manager.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: dir) }
        let id = UUID().uuidString
        let video = Video(id: id, name: "Original video", filename: id + ".MOV")
        try VideoLibrary.save([video], to: dir)
        let loaded = try VideoLibrary.load(from: dir)
        precondition(loaded.count == 1 && loaded[0].filename == video.filename)
        print("PASS: valid legacy uppercase MOV metadata round-trips")
        func reject(_ name: String, _ body: () throws -> Void) {
            do { try body(); fatalError("FAIL: \(name) accepted") }
            catch { print("PASS: rejects \(name)") }
        }
        reject("oversized manifest") { _ = try VideoLibrary.decode(Data(repeating: 32, count: VideoSafety.maximumManifestBytes + 1)) }
        reject("invalid JSON") { _ = try VideoLibrary.decode(Data("invalid".utf8)) }
        reject("duplicate IDs") { _ = try VideoLibrary.decode(JSONEncoder().encode([video, video])) }
        let tooMany = (0...VideoSafety.maximumLibraryEntries).map { _ -> Video in
            let id = UUID().uuidString
            return Video(id: id, name: "Video", filename: id + ".mov")
        }
        reject("too many manifest entries") { _ = try VideoLibrary.decode(JSONEncoder().encode(tooMany)) }
        for (name, entry) in [
            ("path traversal", Video(id: id, name: "Bad", filename: "../outside.mov")),
            ("different file ID", Video(id: id, name: "Bad", filename: UUID().uuidString + ".mov")),
            ("invalid ID", Video(id: "bad", name: "Bad", filename: "bad.mov")),
            ("control title", Video(id: id, name: "Bad\nline", filename: id + ".mov"))
        ] { reject(name) { _ = try VideoLibrary.decode(JSONEncoder().encode([entry])) } }
        let source = dir.appendingPathComponent("source.mov")
        let destination = dir.appendingPathComponent("copy.mov")
        let bytes = Data(repeating: 42, count: 2_000_000)
        try bytes.write(to: source)
        try VideoLibrary.copyForImport(from: source, to: destination)
        let copied = try Data(contentsOf: destination)
        precondition(copied == bytes)
        print("PASS: bounded copy preserves exact file bytes")
        reject("overwrite existing destination") { try VideoLibrary.copyForImport(from: source, to: destination) }
        let link = dir.appendingPathComponent("link.mov")
        try manager.createSymbolicLink(at: link, withDestinationURL: source)
        reject("symlink source") { try VideoLibrary.copyForImport(from: link, to: dir.appendingPathComponent("unsafe.mov")) }
        precondition(!manager.fileExists(atPath: dir.appendingPathComponent("unsafe.mov").path))
        let large = dir.appendingPathComponent("large.mov")
        _ = manager.createFile(atPath: large.path, contents: Data())
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(VideoSafety.maximumFileSize + 1)); try handle.close()
        reject("oversized copy") { try VideoLibrary.copyForImport(from: large, to: dir.appendingPathComponent("oversized.mov")) }
        precondition(!manager.fileExists(atPath: dir.appendingPathComponent("oversized.mov").path))
        let manifest = dir.appendingPathComponent("library.json")
        try manager.removeItem(at: manifest)
        try manager.createSymbolicLink(at: manifest, withDestinationURL: source)
        reject("symlink manifest") { _ = try VideoLibrary.load(from: dir) }
    }
}
