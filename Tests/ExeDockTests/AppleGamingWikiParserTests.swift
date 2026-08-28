import Testing
@testable import ExeDock

// XCTest isn't available in this environment (Command Line Tools only, no Xcode.app - it doesn't
// bundle XCTest.framework). Swift Testing (`import Testing`) ships with the toolchain itself and
// works here, so that's what these use instead.
@Suite("AppleGamingWikiParser")
struct AppleGamingWikiParserTests {
    @Test func detectsD3DMetalAndESyncFromNotes() {
        let wikitext = """
        {{Compatibility/macOS
        |crossover            = perfect
        |crossover notes      = Works great with D3DMetal enabled and ESync on. No issues found.
        |wine                 = unknown
        |wine notes           =
        }}
        """
        let report = AppleGamingWikiParser.parse(wikitext: wikitext, pageURL: "https://www.applegamingwiki.com/wiki/Test_Game")
        #expect(report?.settings.d3dMetal == true)
        #expect(report?.settings.wineESync == true)
        #expect(report?.sourceName == "AppleGamingWiki")
    }

    @Test func detectsNegativePolarityFromExplicitNegation() {
        let wikitext = """
        {{Compatibility/macOS
        |crossover notes = DXVK is broken on this title, avoid enabling it. D3DMetal works fine instead.
        }}
        """
        let report = AppleGamingWikiParser.parse(wikitext: wikitext, pageURL: "https://example.com")
        #expect(report?.settings.dxvk == false)
        #expect(report?.settings.d3dMetal == true)
    }

    @Test func vkd3dIsInformationalOnlyAndNeverPopulatesAnActionableField() {
        let wikitext = "{{Compatibility/macOS\n|crossover notes = Requires VKD3D for DX12 support.\n}}"
        let report = AppleGamingWikiParser.parse(wikitext: wikitext, pageURL: "https://example.com")
        #expect(report?.settings.mentionsVKD3D == true)
        #expect(report?.settings.d3dMetal == nil)
        #expect(report?.settings.dxvk == nil)
    }

    @Test func fsyncIsInformationalOnlyAndNeverPopulatesAnActionableField() {
        let wikitext = "{{Compatibility/macOS\n|wine notes = Best results seen with FSync on recent kernels.\n}}"
        let report = AppleGamingWikiParser.parse(wikitext: wikitext, pageURL: "https://example.com")
        #expect(report?.settings.mentionsFsync == true)
        #expect(report?.settings.wineESync == nil)
        #expect(report?.settings.wineMSync == nil)
    }

    @Test func returnsNilWhenNothingUsableIsFound() {
        let wikitext = "{{Compatibility/macOS\n|crossover = perfect\n|crossover notes = Runs great, no special settings needed.\n}}"
        #expect(AppleGamingWikiParser.parse(wikitext: wikitext, pageURL: "https://example.com") == nil)
    }

    @Test func returnsNilForEmptyInput() {
        #expect(AppleGamingWikiParser.parse(wikitext: "", pageURL: "https://example.com") == nil)
    }

    /// A trimmed, real excerpt captured live from the RDR2 AppleGamingWiki page while designing
    /// this feature (via its public MediaWiki API) - messy, multi-sentence community-written prose
    /// is exactly what production evidence actually looks like, not tidy fixture text.
    @Test func handlesRealCapturedWikitextWithoutCrashing() {
        let realExcerpt = """
        |crossover notes =  only problem is shadows do no render correctly every time, especially in \
        snowy mountains. in crossover D3DMetal and ESync is turned on. In game VSYNC half, FXAA on, \
        TAA medium, Texture medium. I tested switching between MSync and ESync for 13 hours with \
        various settings.
        """
        let report = AppleGamingWikiParser.parse(wikitext: realExcerpt, pageURL: "https://www.applegamingwiki.com/wiki/Red_Dead_Redemption_2")
        #expect(report != nil, "Real-world evidence text should yield at least one detected keyword")
        #expect(report?.settings.d3dMetal == true)
    }
}
