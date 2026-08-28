import Foundation

/// What one compatibility report says about a game's Wine settings. Each actionable field mirrors
/// a real `GameModeConfig` toggle: `nil` means "not mentioned," `true`/`false` means "reported
/// working/recommended" vs. "reported broken/to avoid." The informational fields below have no
/// `GameModeConfig` equivalent (Playdock has no VKD3D or Fsync setting) - they're still detected
/// and shown as evidence text, but can never end up in an applied configuration.
struct DetectedSettings: Equatable, Codable {
    var d3dMetal: Bool?
    var dxvk: Bool?
    var dxmt: Bool?
    var moltenVKCX: Bool?
    var wineESync: Bool?
    var wineMSync: Bool?

    // Informational only - no ExeDock/Sikarugir setting to apply these to.
    var mentionsVKD3D = false
    var mentionsFsync = false
    var wineVersion: String?
    var launchArguments: [String] = []
    var knownIssues: [String] = []

    var isEmpty: Bool {
        d3dMetal == nil && dxvk == nil && dxmt == nil && moltenVKCX == nil && wineESync == nil && wineMSync == nil
            && !mentionsVKD3D && !mentionsFsync && wineVersion == nil && launchArguments.isEmpty && knownIssues.isEmpty
    }
}
