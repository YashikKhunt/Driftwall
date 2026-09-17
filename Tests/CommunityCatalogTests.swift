import Foundation

@main struct CommunityCatalogTests {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Pass the generated MOV fixture") }
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("DriftwallCatalogTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let digest = try CommunityCatalog.sha256(of: fixture)
        let item: [String: Any] = ["id": "community-test", "title": "Test fixture", "description": "Generated test media",
            "artist": "Test author", "license": "CC0-1.0", "category": "Nature", "filename": "fixture.mov", "sha256": digest]
        func make(_ label: String, entries: [[String: Any]]? = nil, version: Any = 1) throws -> URL {
            let dir = temporary.appendingPathComponent(label)
            try FileManager.default.createDirectory(at: dir.appendingPathComponent("Assets"), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: fixture, to: dir.appendingPathComponent("Assets/fixture.mov"))
            let document: [String: Any] = ["schemaVersion": version, "wallpapers": entries ?? [item]]
            try JSONSerialization.data(withJSONObject: document).write(to: dir.appendingPathComponent("catalog.json"))
            return dir
        }
        func rejects(_ name: String, _ body: () throws -> Void) {
            do { try body(); fatalError("FAIL: \(name) was accepted") }
            catch { print("PASS: rejects \(name)") }
        }
        let valid = try make("valid")
        let result = try await CommunityCatalog.validatedCollection(from: valid)
        precondition(result.count == 1 && result[0].artist == "Test author")
        print("PASS: real H.264 fixture passes catalog hash, metadata and media validation")
        let empty = try make("empty", entries: [])
        try FileManager.default.removeItem(at: empty.appendingPathComponent("Assets/fixture.mov"))
        let emptyWallpapers = try CommunityCatalog.load(from: empty)
        precondition(emptyWallpapers.isEmpty)
        print("PASS: empty curated catalog")
        for (name, key, value) in [
            ("traversal", "filename", "../fixture.mov"),
            ("unsafe profile", "profileURL", "https://user:secret@example.com"),
            ("profile query", "profileURL", "https://example.com/?track=1"),
            ("script profile", "profileURL", "javascript:alert(1)"),
            ("empty author", "artist", "  "),
            ("control title", "title", "bad\nline"),
            ("bidi title", "title", "bad\u{202e}name"),
            ("unapproved license", "license", "unknown"),
            ("bad category", "category", "unknown"),
            ("bad ID", "id", "aurora"),
            ("bad digest", "sha256", String(repeating: "0", count: 64)),
            ("unknown key", "unexpected", "value")
        ] {
            var changed = item; changed[key] = value
            let dir = try make(name, entries: [changed])
            rejects(name) { _ = try CommunityCatalog.load(from: dir) }
        }
        let escaped = try make("escaped-unicode")
        let escapedManifest = escaped.appendingPathComponent("catalog.json")
        let originalJSON = try String(contentsOf: escapedManifest, encoding: .utf8)
        let escapedJSON = originalJSON.replacingOccurrences(of: "Test fixture", with: #"\u0054est fi\u0078ture"#)
        try Data(escapedJSON.utf8).write(to: escapedManifest)
        let escapedEntries = try CommunityCatalog.load(from: escaped)
        precondition(escapedEntries.first?.title == "Test fixture")
        print("PASS: decodes ASCII Unicode escapes in valid JSON")
        for (label, json) in [
            ("escaped duplicate keys", #"{"schemaVersion":1,"\u0073chemaVersion":1,"wallpapers":[]}"#),
            ("uppercase hex duplicate keys", #"{"schemaVersion":1,"wallpapers":[],"wa\u006Clpapers":[]}"#),
            ("invalid hex escape", #"{"schemaVersion":1,"\u00G0":1,"wallpapers":[]}"#),
            ("truncated Unicode escape", #"{"schemaVersion":1,"\u007":1,"wallpapers":[]}"#)
        ] {
            let directory = try make(label)
            try Data(json.utf8).write(to: directory.appendingPathComponent("catalog.json"))
            rejects(label) { _ = try CommunityCatalog.load(from: directory) }
        }
        let duplicate = try make("duplicate", entries: [item, item])
        rejects("duplicate entry") { _ = try CommunityCatalog.load(from: duplicate) }
        let boolean = try make("boolean", version: true)
        rejects("boolean schemaVersion") { _ = try CommunityCatalog.load(from: boolean) }
        let unsupported = try make("version", version: 2)
        rejects("unknown schemaVersion") { _ = try CommunityCatalog.load(from: unsupported) }
        let link = try make("symlink")
        let media = link.appendingPathComponent("Assets/fixture.mov")
        try FileManager.default.removeItem(at: media)
        try FileManager.default.createSymbolicLink(at: media, withDestinationURL: fixture)
        rejects("symlink media") { _ = try CommunityCatalog.load(from: link) }
        let missing = try make("missing")
        try FileManager.default.removeItem(at: missing.appendingPathComponent("Assets/fixture.mov"))
        rejects("missing media") { _ = try CommunityCatalog.load(from: missing) }
        let extra = try make("extra")
        try Data("unapproved".utf8).write(to: extra.appendingPathComponent("Assets/script.sh"))
        rejects("unexpected asset") { _ = try CommunityCatalog.load(from: extra) }
        let large = try make("large")
        try Data(repeating: 32, count: CommunityCatalog.maxCatalogBytes + 1).write(to: large.appendingPathComponent("catalog.json"))
        rejects("oversized catalog") { _ = try CommunityCatalog.load(from: large) }
        let malformed = try make("malformed")
        let badMedia = malformed.appendingPathComponent("Assets/fixture.mov")
        try Data("not a movie".utf8).write(to: badMedia)
        var badItem = item; badItem["sha256"] = try CommunityCatalog.sha256(of: badMedia)
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "wallpapers": [badItem]]).write(to: malformed.appendingPathComponent("catalog.json"))
        do {
            _ = try await CommunityCatalog.validatedCollection(from: malformed)
            fatalError("FAIL: malformed media accepted")
        } catch { print("PASS: rejects malformed media even with a matching hash") }
    }
}
