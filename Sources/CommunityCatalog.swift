import Foundation
import CoreFoundation
import CryptoKit

struct CommunityWallpaper: Identifiable {
    let id: String
    let title: String
    let description: String
    let artist: String
    let profileURL: URL?
    let license: String
    let category: String
    let filename: String
    let sha256: String
}

enum CommunityCatalog {
    static let maxCatalogBytes = 1_048_576
    static let maxAssetBytes = 200 * 1_024 * 1_024
    static let maxTotalBytes = 500 * 1_024 * 1_024
    static let categories = ["Nature", "Ocean", "Space", "Abstract", "Minimal"]

    struct Invalid: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func load(from directory: URL) throws -> [CommunityWallpaper] {
        let rootInfo = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootInfo.isDirectory == true, rootInfo.isSymbolicLink != true else {
            throw Invalid(message: "The community catalog directory is invalid.")
        }
        let manifest = directory.appendingPathComponent("catalog.json")
        let info = try manifest.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true,
              let size = info.fileSize, size > 0, size <= Int64(maxCatalogBytes) else {
            throw Invalid(message: "The community catalog is missing or too large.")
        }
        let data = try Data(contentsOf: manifest)
        guard data.count <= maxCatalogBytes,
              try !hasDuplicateJSONKeys(data),
              let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(document.keys) == ["schemaVersion", "wallpapers"],
              let version = document["schemaVersion"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version == 1,
              !["f", "d"].contains(String(cString: version.objCType)),
              let entries = document["wallpapers"] as? [[String: Any]], entries.count <= 100 else {
            throw Invalid(message: "The community catalog format is unsupported.")
        }
        var ids = Set<String>()
        var filenames = Set<String>()
        var total = 0
        let assets = directory.appendingPathComponent("Assets", isDirectory: true)
        let assetsInfo = try assets.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard assetsInfo.isDirectory == true, assetsInfo.isSymbolicLink != true else {
            throw Invalid(message: "The community media directory is invalid.")
        }
        let wallpapers = try entries.map { entry -> CommunityWallpaper in
            let required: Set<String> = ["id", "title", "description", "artist", "license", "category", "filename", "sha256"]
            guard Set(entry.keys).isSuperset(of: required),
                  Set(entry.keys).isSubset(of: required.union(["profileURL"])) else {
                throw Invalid(message: "A community entry contains missing or unknown fields.")
            }
            let id = try text(entry, "id", limit: 80)
            let title = try text(entry, "title", limit: 80)
            let description = try text(entry, "description", limit: 280)
            let artist = try text(entry, "artist", limit: 80)
            let license = try text(entry, "license", limit: 20)
            let category = try text(entry, "category", limit: 20)
            let filename = try text(entry, "filename", limit: 160)
            let digest = try text(entry, "sha256", limit: 64)
            guard matches(id, "^community-[a-z0-9]+(?:-[a-z0-9]+)*$"),
                  matches(filename, "^[a-z0-9][a-z0-9._-]*\\.(mp4|mov)$"),
                  matches(digest, "^[a-f0-9]{64}$"),
                  ["CC0-1.0", "CC-BY-4.0"].contains(license), categories.contains(category),
                  ids.insert(id).inserted, filenames.insert(filename).inserted else {
                throw Invalid(message: "A community entry has invalid or duplicate metadata.")
            }
            var profileURL: URL?
            if entry["profileURL"] != nil {
                let value = try text(entry, "profileURL", limit: 300)
                guard !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }) else {
                    throw Invalid(message: "Artist profile links must be plain HTTPS links.")
                }
                guard let components = URLComponents(string: value), components.scheme == "https",
                      let host = components.host, !host.isEmpty,
                      components.user == nil, components.password == nil,
                      components.port == nil, components.query == nil, components.fragment == nil,
                      let url = components.url else {
                    throw Invalid(message: "Artist profile links must be plain HTTPS links.")
                }
                profileURL = url
            }
            let url = try VideoSafety.validatedURL(filename: filename, directory: assets)
            let bytes = Int(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            guard bytes > 0, bytes <= maxAssetBytes, bytes <= maxTotalBytes - total else {
                throw Invalid(message: "Community media exceeds the collection size limit.")
            }
            total += bytes
            guard try sha256(of: url) == digest else {
                throw Invalid(message: "Community media failed its integrity check.")
            }
            return CommunityWallpaper(id: id, title: title, description: description, artist: artist,
                                      profileURL: profileURL, license: license, category: category,
                                      filename: filename, sha256: digest)
        }
        for url in try FileManager.default.contentsOfDirectory(at: assets, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]) {
            let info = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
            guard info.isSymbolicLink != true, info.isRegularFile == true else {
                throw Invalid(message: "The community media folder contains an unexpected file.")
            }
            if url.lastPathComponent == ".gitkeep" {
                guard (info.fileSize ?? -1) == 0 else {
                    throw Invalid(message: "The community media folder contains an unexpected file.")
                }
                continue
            }
            guard filenames.contains(url.lastPathComponent) else {
                throw Invalid(message: "The community media folder contains an unexpected file.")
            }
        }
        return wallpapers
    }

    static func validatedCollection(from directory: URL) async throws -> [CommunityWallpaper] {
        let wallpapers = try load(from: directory)
        for wallpaper in wallpapers {
            let url = try VideoSafety.validatedURL(filename: wallpaper.filename,
                                                   directory: directory.appendingPathComponent("Assets"))
            try await VideoSafety.validateVideo(at: url)
        }
        return wallpapers
    }

    private static func text(_ entry: [String: Any], _ key: String, limit: Int) throws -> String {
        guard let value = entry[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.count <= limit, value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.properties.generalCategory != .format }) else {
            throw Invalid(message: "Community metadata field \(key) is invalid.")
        }
        return value
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func hasDuplicateJSONKeys(_ data: Data) throws -> Bool {
        var scanner = try JSONKeyScanner(data: data)
        return try scanner.hasDuplicateKeys()
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        var bytes = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            bytes += chunk.count
            guard bytes <= maxAssetBytes else { throw Invalid(message: "Community media is too large.") }
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private struct JSONKeyScanner {
    private let scalars: [UnicodeScalar]
    private var index = 0

    init(data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CommunityCatalog.Invalid(message: "The community catalog format is unsupported.")
        }
        self.scalars = Array(text.unicodeScalars)
    }

    mutating func hasDuplicateKeys() throws -> Bool {
        skipWhitespace()
        let hasDuplicates = try parseValue()
        skipWhitespace()
        guard index == scalars.count else {
            throw CommunityCatalog.Invalid(message: "The community catalog format is unsupported.")
        }
        return hasDuplicates
    }

    private mutating func parseValue() throws -> Bool {
        guard let scalar = peek else {
            throw CommunityCatalog.Invalid(message: "The community catalog format is unsupported.")
        }
        switch scalar {
        case "{": return try parseObject()
        case "[": return try parseArray()
        case "\"":
            _ = try parseString()
            return false
        case "t": try parseLiteral("true"); return false
        case "f": try parseLiteral("false"); return false
        case "n": try parseLiteral("null"); return false
        default:
            if scalar == "-" || CharacterSet.decimalDigits.contains(scalar) {
                try parseNumber()
                return false
            }
            throw CommunityCatalog.Invalid(message: "The community catalog format is unsupported.")
        }
    }

    private mutating func parseObject() throws -> Bool {
        try consume("{")
        skipWhitespace()
        if try consumeIf("}") { return false }
        var keys = Set<String>()
        while true {
            let key = try parseString()
            guard keys.insert(key).inserted else { return true }
            skipWhitespace()
            try consume(":")
            skipWhitespace()
            if try parseValue() { return true }
            skipWhitespace()
            if try consumeIf("}") { return false }
            try consume(",")
            skipWhitespace()
        }
    }

    private mutating func parseArray() throws -> Bool {
        try consume("[")
        skipWhitespace()
        if try consumeIf("]") { return false }
        while true {
            if try parseValue() { return true }
            skipWhitespace()
            if try consumeIf("]") { return false }
            try consume(",")
            skipWhitespace()
        }
    }

    private mutating func parseString() throws -> String {
        try consume("\"")
        var output = String.UnicodeScalarView()
        while let scalar = peek {
            advance()
            if scalar == "\"" { return String(output) }
            if scalar == "\\" {
                guard let escaped = peek else {
                    throw CommunityCatalog.Invalid(message: "The community catalog format is unsupported.")
                }
                advance()
                switch escaped {
                case "\"", "\\", "/": output.append(escaped)
                case "b": output.append("\u{08}")
                case "f": output.append("\u{0c}")
                case "n": output.append("\n")
                case "r": output.append("\r")
                case "t": output.append("\t")
                case "u": output.append(try parseUnicodeEscape())
                default:
                    throw CommunityCatalog.Invalid(message: "The community catalog format is unsupported.")
                }
                continue
            }
            guard !CharacterSet.controlCharacters.contains(scalar) else {
                throw CommunityCatalog.Invalid(message: "The community catalog format is unsupported.")
            }
            output.append(scalar)
        }
        throw CommunityCatalog.Invalid(message: "The community catalog format is unsupported.")
    }

    private mutating func parseUnicodeEscape() throws -> UnicodeScalar {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let scalar = peek else {
                throw CommunityCatalog.Invalid(message: "The community catalog format is unsupported.")
            }
            let hex: UInt32
            switch scalar.value {
            case 48...57: hex = scalar.value - 48
            case 65...70: hex = scalar.value - 65 + 10
            case 97...102: hex = scalar.value - 97 + 10
            default:
                throw CommunityCatalog.Invalid(message: "The community catalog format is unsupported.")
            }
            advance()
            value = (value << 4) | hex
        }
        guard let unicode = UnicodeScalar(value) else {
            throw CommunityCatalog.Invalid(message: "The community catalog format is unsupported.")
        }
        return unicode
    }

    private mutating func parseNumber() throws {
        if try consumeIf("-") {}
        try parseDigits()
        if try consumeIf(".") {
            try parseDigits()
        }
        if try consumeIf("e") || consumeIfUnchecked("E") {
            if try consumeIf("+") || consumeIfUnchecked("-") {}
            try parseDigits()
        }
    }

    private mutating func parseDigits() throws {
        guard let scalar = peek, CharacterSet.decimalDigits.contains(scalar) else {
            throw CommunityCatalog.Invalid(message: "The community catalog format is unsupported.")
        }
        while let scalar = peek, CharacterSet.decimalDigits.contains(scalar) {
            advance()
        }
    }

    private mutating func parseLiteral(_ literal: String) throws {
        for scalar in literal.unicodeScalars {
            try consume(scalar)
        }
    }

    private mutating func skipWhitespace() {
        while let scalar = peek, CharacterSet.whitespacesAndNewlines.contains(scalar) {
            advance()
        }
    }

    private var peek: UnicodeScalar? {
        guard index < scalars.count else { return nil }
        return scalars[index]
    }

    private mutating func advance() {
        index += 1
    }

    private mutating func consume(_ expected: UnicodeScalar) throws {
        guard try consumeIf(expected) else {
            throw CommunityCatalog.Invalid(message: "The community catalog format is unsupported.")
        }
    }

    private mutating func consumeIf(_ scalar: UnicodeScalar) throws -> Bool {
        if peek == scalar {
            advance()
            return true
        }
        return false
    }

    private mutating func consumeIfUnchecked(_ scalar: UnicodeScalar) -> Bool {
        if peek == scalar {
            advance()
            return true
        }
        return false
    }
}
