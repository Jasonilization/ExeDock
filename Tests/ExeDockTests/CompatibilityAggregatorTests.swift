import Testing
@testable import ExeDock

@Suite("CompatibilityAggregator")
struct CompatibilityAggregatorTests {
    private func report(source: String, d3dMetal: Bool? = nil, dxvk: Bool? = nil, dxmt: Bool? = nil) -> CompatibilityReport {
        var settings = DetectedSettings()
        settings.d3dMetal = d3dMetal
        settings.dxvk = dxvk
        settings.dxmt = dxmt
        return CompatibilityReport(sourceName: source, sourceURL: "https://example.com/\(source)", excerpt: "test", settings: settings)
    }

    @Test func emptyEvidenceYieldsNoRecommendation() {
        let result = CompatibilityAggregator.aggregate(reports: [])
        #expect(result.confidence == .none)
        #expect(result.recommendedSettings == nil)
    }

    @Test func twoIndependentAgreeingSourcesYieldHighConfidence() {
        let reports = [
            report(source: "AppleGamingWiki", d3dMetal: true),
            report(source: "GitHub", d3dMetal: true),
        ]
        let result = CompatibilityAggregator.aggregate(reports: reports)
        #expect(result.confidence == .high)
        #expect(result.recommendedSettings?.d3dMetal == true)
    }

    @Test func singleSourceYieldsAtMostMediumConfidence() {
        let result = CompatibilityAggregator.aggregate(reports: [report(source: "AppleGamingWiki", d3dMetal: true)])
        #expect(result.confidence < .high)
        #expect(result.recommendedSettings?.d3dMetal == true)
    }

    @Test func multipleMentionsFromTheSameSourceAreNotDoubleCountedAsIndependent() {
        // Same sourceName twice (e.g. two keyword hits on one page) must not be treated as 2
        // independent sources - independence is about distinct sources, not report count.
        let reports = [
            report(source: "AppleGamingWiki", d3dMetal: true),
            report(source: "AppleGamingWiki", dxvk: true),
        ]
        let result = CompatibilityAggregator.aggregate(reports: reports)
        #expect(result.confidence != .high)
    }

    @Test func contradictoryReportsWithNothingElseYieldNoRecommendation() {
        let reports = [
            report(source: "AppleGamingWiki", d3dMetal: true),
            report(source: "GitHub", d3dMetal: false),
        ]
        let result = CompatibilityAggregator.aggregate(reports: reports)
        #expect(result.recommendedSettings == nil)
        #expect(result.confidence == .none)
    }

    @Test func contradictionOnOneFieldDoesNotBlockAnUnrelatedAgreeingField() {
        let reports = [
            report(source: "AppleGamingWiki", d3dMetal: true, dxvk: true),
            report(source: "GitHub", d3dMetal: false, dxvk: true),
        ]
        let result = CompatibilityAggregator.aggregate(reports: reports)
        #expect(result.recommendedSettings?.dxvk == true, "dxvk agreed across both sources and should still be recommended")
        #expect(result.confidence != .high, "a contradiction anywhere should prevent .high overall confidence")
    }

    @Test func unsupportedSettingAloneYieldsNoRecommendationButKeepsEvidenceVisible() {
        var settings = DetectedSettings()
        settings.mentionsVKD3D = true
        let onlyVKD3D = CompatibilityReport(sourceName: "GitHub", sourceURL: "https://example.com", excerpt: "mentions VKD3D", settings: settings)

        let result = CompatibilityAggregator.aggregate(reports: [onlyVKD3D])
        #expect(result.confidence == .none)
        #expect(result.recommendedSettings == nil)
        #expect(result.reports.count == 1, "evidence should still be visible even when nothing was recommended")
    }

    @Test func appliedOntoPreservesUnevidencedFieldsInsteadOfResettingToDefaults() {
        // Regression coverage for a real bug caught during design: recommendedSettings must be a
        // *partial* delta, merged onto the game's current config - not a full GameModeConfig built
        // from bare defaults, which would silently reset every field evidence never mentioned.
        var current = GameModeConfig()
        current.dxvk = true
        current.engineName = "Custom-Engine"

        let result = CompatibilityAggregator.aggregate(reports: [report(source: "AppleGamingWiki", d3dMetal: true)])
        let applied = result.applied(onto: current)

        #expect(applied.d3dMetal == true, "the evidenced field should be applied")
        #expect(applied.dxvk == true, "a field evidence never mentioned must keep the caller's existing value")
        #expect(applied.engineName == "Custom-Engine", "fields with no GameModeConfig-default equivalent in DetectedSettings must be untouched")
    }

    @Test func weakSparseSingleMentionYieldsLowOrMediumNeverHigh() {
        var settings = DetectedSettings()
        settings.dxmt = true
        let result = CompatibilityAggregator.aggregate(reports: [
            CompatibilityReport(sourceName: "This Mac's launch history", sourceURL: "", excerpt: "1 launch", settings: settings),
        ])
        #expect(result.confidence != .high)
        #expect(result.confidence > .none)
    }
}
