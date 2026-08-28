import Foundation

/// Pure, fully testable aggregation from raw evidence to a scored recommendation - no networking,
/// no I/O, just tallying `[CompatibilityReport]` into a `CompatibilityRecommendation`. This is the
/// one place "should we actually recommend this" gets decided, so every rule lives here in one
/// spot rather than being spread across each source.
enum CompatibilityAggregator {
    static func aggregate(reports: [CompatibilityReport]) -> CompatibilityRecommendation {
        guard !reports.isEmpty else { return .empty }

        var resolved = DetectedSettings()
        var appliedFieldCount = 0
        var independentSourceNames = Set<String>()
        var hadContradiction = false

        func resolve(_ keyPath: WritableKeyPath<DetectedSettings, Bool?>, _ extract: (DetectedSettings) -> Bool?) {
            var trueSources = Set<String>()
            var falseSources = Set<String>()
            for report in reports {
                guard let value = extract(report.settings) else { continue }
                if value {
                    trueSources.insert(report.sourceName)
                } else {
                    falseSources.insert(report.sourceName)
                }
            }
            guard !trueSources.isEmpty || !falseSources.isEmpty else { return }

            // Genuinely contradictory evidence on this specific field - too uncertain to set it at
            // all, but it still counts against overall confidence (see computeConfidence).
            guard trueSources.isEmpty || falseSources.isEmpty else {
                hadContradiction = true
                return
            }

            let winningSources = trueSources.isEmpty ? falseSources : trueSources
            resolved[keyPath: keyPath] = !trueSources.isEmpty
            appliedFieldCount += 1
            independentSourceNames.formUnion(winningSources)
        }

        resolve(\.d3dMetal) { $0.d3dMetal }
        resolve(\.dxvk) { $0.dxvk }
        resolve(\.dxmt) { $0.dxmt }
        resolve(\.moltenVKCX) { $0.moltenVKCX }
        resolve(\.wineESync) { $0.wineESync }
        resolve(\.wineMSync) { $0.wineMSync }

        let confidence = computeConfidence(
            appliedFieldCount: appliedFieldCount,
            independentSourceCount: independentSourceNames.count,
            hadContradiction: hadContradiction
        )
        let recommendedSettings = confidence >= .low ? resolved : nil

        return CompatibilityRecommendation(confidence: confidence, recommendedSettings: recommendedSettings, reports: reports, generatedAt: Date())
    }

    /// - `.high`: at least 2 independent sources agree, and nothing anywhere contradicted them.
    /// - `.medium`: real agreement, but either thinner independence (one source, possibly with
    ///   multiple internal mentions) or a contradiction existed on a *different* field.
    /// - `.low`: a single weak/sparse signal.
    /// - `.none`: nothing resolved at all - either no usable evidence, or the only evidence found
    ///   was a genuine, unresolved contradiction.
    private static func computeConfidence(appliedFieldCount: Int, independentSourceCount: Int, hadContradiction: Bool) -> CompatibilityConfidence {
        guard appliedFieldCount > 0 else { return .none }
        if hadContradiction {
            return independentSourceCount >= 2 ? .medium : .low
        }
        if independentSourceCount >= 2 { return .high }
        return independentSourceCount == 1 ? .medium : .low
    }
}
