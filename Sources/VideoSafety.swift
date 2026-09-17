import AVFoundation
import Foundation

enum VideoSafety {
    static let maximumFileSize: Int64 = 200 * 1024 * 1024
    static let maximumDuration: Double = 120
    static let maximumFrameRate: Float = 60
    static let maximumLibraryEntries = 500
    static let maximumLibraryBytes: Int64 = 2 * 1024 * 1024 * 1024
    static let maximumManifestBytes = 1 * 1024 * 1024

    enum Error: LocalizedError {
        case unsafeFilename
        case unsafeDirectory
        case unsafeFile
        case unsupportedFormat
        case fileTooLarge
        case invalidVideo(String)

        var errorDescription: String? {
            switch self {
            case .unsafeFilename: return "The video filename is not safe."
            case .unsafeDirectory: return "The video library location is not safe."
            case .unsafeFile: return "The selected item must be a regular, non-symlink file."
            case .unsupportedFormat: return "Only MP4 and MOV videos are supported."
            case .fileTooLarge: return "Videos must be 200 MiB or smaller."
            case .invalidVideo(let message): return message
            }
        }
    }

    static func isSafeFilename(_ filename: String) -> Bool {
        guard filename == URL(fileURLWithPath: filename).lastPathComponent,
              !filename.isEmpty, filename.utf8.count <= 160,
              !filename.contains("/"), !filename.contains("\\"),
              filename.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*\\.(?i:mp4|mov)$", options: .regularExpression) != nil
        else { return false }
        return true
    }

    static func validatedURL(filename: String, directory: URL) throws -> URL {
        guard isSafeFilename(filename) else { throw Error.unsafeFilename }
        let safeDirectory = try validatedDirectory(directory)
        let candidate = safeDirectory.appendingPathComponent(filename, isDirectory: false).standardizedFileURL
        guard candidate.path.hasPrefix(safeDirectory.path + "/") else { throw Error.unsafeFilename }
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedCandidate.path.hasPrefix(safeDirectory.path + "/"), resolvedCandidate == candidate else { throw Error.unsafeFile }
        try validateRegularFile(at: candidate)
        return candidate
    }

    static func validateRegularFile(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? 0) > 0 else { throw Error.unsafeFile }
        guard Int64(values.fileSize ?? 0) <= maximumFileSize else { throw Error.fileTooLarge }
    }

    static func restrictedAsset(at url: URL) -> AVURLAsset {
        AVURLAsset(url: url, options: [
            AVURLAssetReferenceRestrictionsKey: NSNumber(value: AVAssetReferenceRestrictions.forbidAll.rawValue),
            AVURLAssetShouldSupportAliasDataReferencesKey: false
        ])
    }

    static func validateVideo(at url: URL) async throws {
        try validateRegularFile(at: url)
        let extensionName = url.pathExtension.lowercased()
        guard extensionName == "mp4" || extensionName == "mov" else { throw Error.unsupportedFormat }
        try validateContainerHeader(at: url)

        let asset = restrictedAsset(at: url)
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard playable, tracks.count == 1,
              duration.isValid, duration.seconds.isFinite, duration.seconds > 0,
              duration.seconds <= maximumDuration
        else { throw Error.invalidVideo("The file is not a playable MP4 or MOV video.") }

        for track in tracks {
            let frameRate = try await track.load(.nominalFrameRate)
            let naturalSize = try await track.load(.naturalSize)
            let descriptions = try await track.load(.formatDescriptions)
            guard frameRate.isFinite, frameRate > 0, frameRate <= maximumFrameRate else {
                throw Error.invalidVideo("Video frame rate must be between 0 and 60 fps.")
            }
            let width = abs(naturalSize.width)
            let height = abs(naturalSize.height)
            let longEdge = max(width, height)
            let shortEdge = min(width, height)
            guard width.isFinite, height.isFinite, longEdge > 0, shortEdge > 0,
                  longEdge <= 4096, shortEdge <= 2160 else {
                throw Error.invalidVideo("Video dimensions exceed the 4096 × 2160 limit.")
            }
            guard !descriptions.isEmpty, descriptions.allSatisfy({ description in
                let codec = CMFormatDescriptionGetMediaSubType(description)
                return [kCMVideoCodecType_H264, kCMVideoCodecType_HEVC, fourCC("avc3"), fourCC("hev1")].contains(codec)
            }) else {
                throw Error.invalidVideo("Only H.264 and HEVC video is supported.")
            }
        }
        try await decodeSampleFrames(asset: asset, duration: duration)
    }

    private static func validateContainerHeader(at url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 4 * 1024) ?? Data()
        guard data.count >= 16, data[4...7] == Data("ftyp".utf8) else {
            throw Error.invalidVideo("The file does not have a valid MP4 or MOV container header.")
        }
        let size = data[0...3].reduce(0) { ($0 << 8) | Int($1) }
        guard size >= 16, size <= data.count, (size - 16).isMultiple(of: 4) else {
            throw Error.invalidVideo("The file has an invalid MP4 or MOV container header.")
        }
        let knownBrands = Set(["qt  ", "isom", "iso2", "iso3", "iso4", "iso5", "iso6", "mp41", "mp42", "avc1", "hev1", "hvc1", "M4V "] .map { Data($0.utf8) })
        let brands = [Data(data[8..<12])] + stride(from: 16, to: size, by: 4).map { Data(data[$0..<$0 + 4]) }
        guard brands.contains(where: knownBrands.contains) else {
            throw Error.invalidVideo("The file is not an ISO Base Media or QuickTime container.")
        }
    }

    private static func decodeSampleFrames(asset: AVURLAsset, duration: CMTime) async throws {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 64, height: 64)
        for fraction in [0.0, 0.5, 0.95] {
            let time = CMTimeMultiplyByFloat64(duration, multiplier: fraction)
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Swift.Error>) in
                generator.generateCGImageAsynchronously(for: time) { image, _, error in
                    if let image { continuation.resume(returning: image) }
                    else { continuation.resume(throwing: error ?? Error.invalidVideo("The video could not be decoded.")) }
                }
            }
        }
    }

    static func validateLibraryEntries(_ entries: [(id: String, filename: String)]) throws {
        guard entries.count <= maximumLibraryEntries else {
            throw Error.invalidVideo("The video library contains too many entries.")
        }
        var ids = Set<UUID>()
        var filenames = Set<String>()
        for entry in entries {
            guard let id = UUID(uuidString: entry.id), ids.insert(id).inserted,
                  isSafeFilename(entry.filename), filenames.insert(entry.filename.lowercased()).inserted else {
                throw Error.invalidVideo("The video library contains an unsafe entry.")
            }
        }
    }

    static func libraryBytes(filenames: [String], directory: URL) throws -> Int64 {
        try filenames.reduce(into: Int64(0)) { total, filename in
            let url = try validatedURL(filename: filename, directory: directory)
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let (newTotal, overflow) = total.addingReportingOverflow(Int64(size))
            guard !overflow, newTotal <= maximumLibraryBytes else { throw Error.fileTooLarge }
            total = newTotal
        }
    }

    private static func validatedDirectory(_ directory: URL) throws -> URL {
        let standard = directory.standardizedFileURL
        let resolved = standard.resolvingSymlinksInPath().standardizedFileURL
        let values = try standard.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true, standard == resolved else { throw Error.unsafeDirectory }
        return standard
    }

    private static func fourCC(_ value: String) -> FourCharCode {
        value.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }
}
