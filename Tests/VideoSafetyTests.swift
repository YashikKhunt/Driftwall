import Foundation

struct Video {
    var id: String
    var name: String
    var filename: String
}

@main
struct VideoSafetyTests {
    static func main() async throws {
        if CommandLine.arguments.count == 2 {
            try await VideoSafety.validateVideo(at: URL(fileURLWithPath: CommandLine.arguments[1]))
            print("PASS VideoSafety real fixture")
        }

        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("Driftwall-VideoSafety-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: directory) }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)

        let valid = directory.appendingPathComponent("clip.mp4")
        try Data([0]).write(to: valid)
        try expectThrows { try VideoSafety.validateRegularFile(at: directory.appendingPathComponent("empty.mp4")) }
        try expect(VideoSafety.validatedURL(filename: "clip.mp4", directory: directory) == valid, "safe regular file is accepted")
        try expectThrows { _ = try VideoSafety.validatedURL(filename: "../outside.mp4", directory: directory) }
        try expectThrows { _ = try VideoSafety.validatedURL(filename: "/tmp/outside.mp4", directory: directory) }
        try expectThrows { _ = try VideoSafety.validatedURL(filename: "folder\\clip.mp4", directory: directory) }
        try expectThrows { _ = try VideoSafety.validatedURL(filename: "clip.avi", directory: directory) }

        let nested = directory.appendingPathComponent("directory.mp4", isDirectory: true)
        try manager.createDirectory(at: nested, withIntermediateDirectories: true)
        try expectThrows { _ = try VideoSafety.validatedURL(filename: "directory.mp4", directory: directory) }

        let linkedDirectory = manager.temporaryDirectory.appendingPathComponent("Driftwall-LinkedLibrary-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: linkedDirectory) }
        try manager.createSymbolicLink(at: linkedDirectory, withDestinationURL: directory)
        try expectThrows { _ = try VideoSafety.validatedURL(filename: "clip.mp4", directory: linkedDirectory) }

        let symlink = directory.appendingPathComponent("linked.mp4")
        try manager.createSymbolicLink(at: symlink, withDestinationURL: valid)
        try expectThrows { _ = try VideoSafety.validatedURL(filename: "linked.mp4", directory: directory) }

        let oversized = directory.appendingPathComponent("oversized.mp4")
        manager.createFile(atPath: oversized.path, contents: Data())
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: UInt64(VideoSafety.maximumFileSize + 1))
        try handle.close()
        try expectThrows { _ = try VideoSafety.validatedURL(filename: "oversized.mp4", directory: directory) }
        let invalidContainer = directory.appendingPathComponent("invalid.mp4")
        try Data("not a movie".utf8).write(to: invalidContainer)
        try await expectThrowsAsync { try await VideoSafety.validateVideo(at: invalidContainer) }
        for (index, header) in [ftypHeader(size: 0), ftypHeader(size: 1), ftypHeader(size: 17), ftypHeader(size: 18), ftypHeader(size: 19), Data([0, 0, 0, 16, 0x66, 0x74, 0x79, 0x70])].enumerated() {
            let malformed = directory.appendingPathComponent("malformed-\(index).mp4")
            try header.write(to: malformed)
            try await expectThrowsAsync { try await VideoSafety.validateVideo(at: malformed) }
        }

        let validVideo = Video(id: UUID().uuidString, name: "Clip", filename: "clip.mp4")
        try VideoSafety.validateLibraryEntries([(id: validVideo.id, filename: validVideo.filename)])
        try expectThrows { try VideoSafety.validateLibraryEntries([(id: "not-a-uuid", filename: "clip.mp4")]) }
        try expectThrows { try VideoSafety.validateLibraryEntries([(id: validVideo.id, filename: validVideo.filename), (id: validVideo.id, filename: "other.mp4")]) }
        try expectThrows { try VideoSafety.validateLibraryEntries([(id: validVideo.id, filename: validVideo.filename), (id: UUID().uuidString, filename: "CLIP.mp4")]) }
        let videos = (0...VideoSafety.maximumLibraryEntries).map {
            Video(id: UUID().uuidString, name: "Clip", filename: "clip\($0).mp4")
        }
        try expectThrows { try VideoSafety.validateLibraryEntries(videos.map { (id: $0.id, filename: $0.filename) }) }
        print("PASS VideoSafety path, symlink, directory, size, and metadata guards")
    }

    static func ftypHeader(size: Int) -> Data {
        var header = Data([UInt8((size >> 24) & 0xff), UInt8((size >> 16) & 0xff), UInt8((size >> 8) & 0xff), UInt8(size & 0xff)])
        header.append(Data("ftypisom".utf8))
        header.append(contentsOf: [0, 0, 0, 0])
        header.append(Data("isom".utf8))
        return header
    }

    static func expectThrowsAsync(_ body: () async throws -> Void) async throws {
        do {
            try await body()
            throw NSError(domain: "VideoSafetyTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected rejection"])
        } catch let error as NSError where error.domain == "VideoSafetyTests" {
            throw error
        } catch { }
    }

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw NSError(domain: "VideoSafetyTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func expectThrows(_ body: () throws -> Void) throws {
        do {
            try body()
            throw NSError(domain: "VideoSafetyTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected rejection"])
        } catch let error as NSError where error.domain == "VideoSafetyTests" {
            throw error
        } catch { }
    }
}
