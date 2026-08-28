import Foundation

/// One piece of evidence from one source (a wiki page, a GitHub issue, this device's own launch
/// history) about how a game runs with which settings. `excerpt` is the actual text that justified
/// the detection - shown verbatim in "View Evidence" so the recommendation is never a black box.
struct CompatibilityReport: Equatable, Codable, Identifiable {
    let sourceName: String
    let sourceURL: String
    let excerpt: String
    let settings: DetectedSettings

    var id: String { "\(sourceURL)#\(excerpt.hashValue)" }
}
