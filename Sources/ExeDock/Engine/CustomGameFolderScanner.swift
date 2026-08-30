import Foundation

/// One candidate executable found while scanning a folder for a manually-imported custom game -
/// `isBestGuess` marks the one `AddGameSheet` should pre-select (largest file, same heuristic
/// `ExecutableHeuristics` uses everywhere else).
struct CandidateExecutable: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let sizeBytes: Int
    let isBestGuess: Bool

    var displayName: String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}

/// Turns a folder someone dropped/picked for "+ Add Game" into a list of plausible executables to
/// launch - depth-limited, same shape as `SteamLibrary`'s own icon-exe lookup, just returning every
/// real-looking candidate instead of picking just one. When there's exactly one, `AddGameSheet` can
/// skip the picker entirely; when there's more than one, it shows "Which executable launches the
/// game?" with the largest (starred) pre-selected.
enum CustomGameFolderScanner {
    static func scan(folder: String, maxDepth: Int = 5) -> [CandidateExecutable] {
        let candidates = ExecutableHeuristics.candidateExecutables(inFolder: folder, maxDepth: maxDepth)
        return candidates.enumerated().map { index, candidate in
            CandidateExecutable(path: candidate.path, sizeBytes: candidate.size, isBestGuess: index == 0)
        }
    }
}
