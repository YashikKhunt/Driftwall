import Foundation

@main struct ValidateCommunityMedia {
    static func main() async {
        do {
            guard CommandLine.arguments.count == 2 else {
                throw CommunityCatalog.Invalid(message: "Usage: ValidateCommunityMedia <Community directory>")
            }
            let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            let wallpapers = try await CommunityCatalog.validatedCollection(from: root)
            print("PASS: \(wallpapers.count) community entries passed metadata, hash, and media validation")
        } catch {
            fputs("Community validation failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
