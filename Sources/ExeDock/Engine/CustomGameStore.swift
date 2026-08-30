import Foundation

/// JSON-on-disk CRUD for custom (manually-imported) games - same pattern as
/// `GameSettingsStore`/`CompatibilityCache`. Stores only the `CustomGame` records themselves
/// (metadata, the exe path as a reference); never touches the actual game files.
enum CustomGameStore {
    private static let path = ("~/Library/Application Support/ExeDock/CustomGames.json" as NSString).expandingTildeInPath

    static func loadAll() -> [CustomGame] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [] }
        return (try? JSONDecoder().decode([CustomGame].self, from: data)) ?? []
    }

    static func add(_ game: CustomGame) {
        var games = loadAll()
        games.append(game)
        save(games)
    }

    static func update(_ game: CustomGame) {
        var games = loadAll()
        guard let index = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[index] = game
        save(games)
    }

    /// Only removes the library record - the referenced exe/folder on disk is never touched.
    static func remove(id: String) {
        var games = loadAll()
        games.removeAll { $0.id == id }
        save(games)
    }

    private static func save(_ games: [CustomGame]) {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(games) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
