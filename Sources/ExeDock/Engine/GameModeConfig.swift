import Foundation

/// The same Wine/engine toggles already present in the user's existing Sikarugir wrapper apps
/// (confirmed by inspecting Pragmata.app / Steam.app's Info.plist), surfaced for the Steam/game
/// bottle. These aren't new invented settings - they mirror what Sikarugir already exposes.
struct GameModeConfig: Equatable, Codable {
    var d3dMetal = true
    var dxvk = false
    var dxmt = false
    var moltenVKCX = true
    var wineESync = true
    var wineMSync = true
    var engineName: String? = SikarugirEngine.recommendedEngineName()

    var environment: [String: String] {
        [
            "D3DMETAL": d3dMetal ? "1" : "0",
            "DXVK": dxvk ? "1" : "0",
            "DXMT": dxmt ? "1" : "0",
            "MOLTENVKCX": moltenVKCX ? "1" : "0",
            "WINEESYNC": wineESync ? "1" : "0",
            "WINEMSYNC": wineMSync ? "1" : "0",
        ]
    }
}
