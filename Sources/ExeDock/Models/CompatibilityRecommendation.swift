import Foundation

enum CompatibilityConfidence: String, Codable, Comparable {
    case none, low, medium, high

    private var rank: Int {
        switch self {
        case .none: return 0
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    static func < (lhs: CompatibilityConfidence, rhs: CompatibilityConfidence) -> Bool {
        lhs.rank < rhs.rank
    }

    var label: String {
        switch self {
        case .none: return "No reliable configuration found"
        case .low: return "Low confidence"
        case .medium: return "Medium confidence"
        case .high: return "High confidence"
        }
    }

    var indicator: String {
        switch self {
        case .none: return "⚪"
        case .low, .medium: return "🟡"
        case .high: return "🟢"
        }
    }
}

/// The aggregated output of `CompatibilityAggregator.aggregate(reports:)` - see that type for how
/// `confidence` and `recommendedSettings` are derived. `recommendedSettings` is only non-nil at
/// `.low` confidence or above; at `.none` it's always nil, meaning "nothing to apply."
///
/// `recommendedSettings` is deliberately a *partial* `DetectedSettings` (only the fields evidence
/// actually resolved), not a full `GameModeConfig` - a full config built from bare defaults would
/// silently reset every unevidenced field (e.g. an already-set `dxvk` override) back to its default
/// the moment someone hit Apply. `applied(onto:)` is the only place that ever turns this into a
/// real `GameModeConfig`, by merging just the resolved fields onto the game's current settings.
struct CompatibilityRecommendation: Codable, Equatable {
    let confidence: CompatibilityConfidence
    let recommendedSettings: DetectedSettings?
    let reports: [CompatibilityReport]
    let generatedAt: Date

    static let empty = CompatibilityRecommendation(confidence: .none, recommendedSettings: nil, reports: [], generatedAt: .distantPast)

    func applied(onto base: GameModeConfig) -> GameModeConfig {
        guard let settings = recommendedSettings else { return base }
        var config = base
        if let value = settings.d3dMetal { config.d3dMetal = value }
        if let value = settings.dxvk { config.dxvk = value }
        if let value = settings.dxmt { config.dxmt = value }
        if let value = settings.moltenVKCX { config.moltenVKCX = value }
        if let value = settings.wineESync { config.wineESync = value }
        if let value = settings.wineMSync { config.wineMSync = value }
        return config
    }
}
