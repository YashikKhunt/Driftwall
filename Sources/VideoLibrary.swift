import Foundation
import Darwin

struct Video: Identifiable, Codable {
    var id: String
    var name: String
    var filename: String
}

enum VideoLibrary {
    static func validateDirectory(_ url: URL) throws {
        let standard = url.standardizedFileURL
        let values = try standard.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true,
              standard == standard.resolvingSymlinksInPath().standardizedFileURL else {
            throw VideoSafety.Error.unsafeDirectory
        }
    }

    static func decode(_ data: Data) throws -> [Video] {
        guard data.count <= VideoSafety.maximumManifestBytes else { throw VideoSafety.Error.unsafeFile }
        let videos = try JSONDecoder().decode([Video].self, from: data)
        guard videos.count <= VideoSafety.maximumLibraryEntries else {
            throw VideoSafety.Error.invalidVideo("The video library contains too many entries.")
        }
        var ids = Set<UUID>()
        var names = Set<String>()
        for video in videos {
            guard let id = UUID(uuidString: video.id), ids.insert(id).inserted,
                  VideoSafety.isSafeFilename(video.filename), names.insert(video.filename.lowercased()).inserted,
                  UUID(uuidString: (video.filename as NSString).deletingPathExtension) == id,
                  !video.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, video.name.count <= 256,
                  video.name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.properties.generalCategory != .format }) else {
                throw VideoSafety.Error.invalidVideo("The video library contains an unsafe entry.")
            }
        }
        return videos
    }

    static func load(from directory: URL) throws -> [Video] {
        try validateDirectory(directory)
        let manifest = directory.appendingPathComponent("library.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return [] }
        let values = try manifest.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= VideoSafety.maximumManifestBytes else { throw VideoSafety.Error.unsafeFile }
        return try decode(Data(contentsOf: manifest))
    }

    static func save(_ videos: [Video], to directory: URL) throws {
        try validateDirectory(directory)
        let data = try JSONEncoder().encode(videos)
        _ = try decode(data)
        try data.write(to: directory.appendingPathComponent("library.json"), options: .atomic)
    }

    // Open the source without following a final symlink, create the destination
    // exclusively, and enforce the byte limit while copying (not just before it).
    static func copyForImport(from source: URL, to destination: URL) throws {
        try validateDirectory(destination.deletingLastPathComponent())
        guard VideoSafety.isSafeFilename(destination.lastPathComponent) else { throw VideoSafety.Error.unsafeFilename }
        let input = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard input >= 0 else { throw VideoSafety.Error.unsafeFile }
        defer { close(input) }
        var info = stat()
        guard fstat(input, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size > 0,
              info.st_size <= VideoSafety.maximumFileSize else { throw VideoSafety.Error.unsafeFile }
        let output = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard output >= 0 else { throw VideoSafety.Error.unsafeFile }
        var succeeded = false
        defer {
            close(output)
            if !succeeded { unlink(destination.path) }
        }
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        var total: Int64 = 0
        while true {
            let count = read(input, &buffer, buffer.count)
            if count < 0 { if errno == EINTR { continue }; throw VideoSafety.Error.unsafeFile }
            if count == 0 { break }
            total += Int64(count)
            guard total <= VideoSafety.maximumFileSize else { throw VideoSafety.Error.fileTooLarge }
            try buffer.withUnsafeBytes { bytes in
                var offset = 0
                while offset < count {
                    let written = write(output, bytes.baseAddress!.advanced(by: offset), count - offset)
                    if written < 0 && errno == EINTR { continue }
                    guard written > 0 else { throw VideoSafety.Error.unsafeFile }
                    offset += written
                }
            }
        }
        guard total > 0 else { throw VideoSafety.Error.unsafeFile }
        succeeded = true
    }
}
