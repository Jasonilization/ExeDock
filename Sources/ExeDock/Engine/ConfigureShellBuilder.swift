import Foundation

/// Gives one of Playdock's own bottles (`.owned` - the shared bottle every custom game and Steam
/// land in) the same reliable, Configure-driven launch path a Sikarugir Creator wrapper already has
/// - entirely automatically, with no manual setup step for anyone: this only ever runs as a side
/// effect of a normal launch.
///
/// Real, verified evidence for why this works (not guessed): a genuine Sikarugir wrapper's own
/// Configure app resolves which bottle to drive purely from *where it itself sits on disk* - its own
/// binary's strings show the literal template `%@/Contents/SharedSupport/prefix/` (confirmed
/// against both a real, already-built wrapper on this Mac and a freshly downloaded copy of
/// Sikarugir's own public Template release), and the already-shipped `SikarugirConfigureLauncher`
/// launches Configure by its own path with zero extra arguments and already works reliably - meaning
/// Configure has no other way to know which bottle it's pointed at.
///
/// So: build a small, disposable "shell" app with that exact same shape -
/// `<Shell>.app/Contents/Configure.app`, `<Shell>.app/Contents/SharedSupport/prefix`, and
/// `<Shell>.app/Contents/SharedSupport/wine` - except `prefix` and `wine` are *symlinks* to
/// Playdock's own already-existing bottle directory and already-extracted engine, never copies,
/// never moves. (The engine symlink matters just as much as the prefix one: Configure's own binary
/// strings show it looks for wine at that same bundle-relative `SharedSupport/wine` path too, and
/// Playdock's own extracted engine directory already has the matching internal shape - `bin/wine` -
/// confirmed against `SikarugirEngine.wineBinaryPath`'s own real result.) Configure launched from
/// inside that shell resolves its own bundle path to the shell, follows both symlinks like any other
/// program would, and drives the real bottle with the real engine - while neither the bottle's own
/// files (everything `BottleManager` owns) nor the engine's own extracted files ever move or are
/// touched by this at all. If a shell can't be built for any reason, the caller just falls back to
/// the existing CLI/direct-wine launch path exactly as if this type didn't exist - purely additive,
/// zero regression risk to a launch that already worked.
enum ConfigureShellBuilder {
    /// Where a given owned bottle's shell lives - a sibling of the bottle's own prefix directory,
    /// never inside it, so nothing here is ever mistaken for part of the bottle's own C: drive.
    private static func shellAppPath(for bottle: Bottle) -> String {
        let parent = (bottle.prefixPath as NSString).deletingLastPathComponent
        let safeName = bottle.name.replacingOccurrences(of: "/", with: "-")
        return (parent as NSString).appendingPathComponent("\(safeName).shell.app")
    }

    /// Builds (or reuses an already-built) shell for `bottle` targeting `wineBinaryPath` (the exact
    /// binary this same launch already resolved to use - whatever engine/wrapper-borrowing logic
    /// picked it, this just needs to know where it lives), returning the shell's own root path -
    /// deliberately the *shell*, not its nested Configure.app, so this plugs directly into
    /// `SikarugirConfigureLauncher.launch(wrapperAppPath:)` exactly like a real wrapper's own app
    /// path already does, with zero changes needed to that already-proven function. Returns `nil` if
    /// a shell genuinely can't be built yet (no cached Configure template - e.g. offline on a fresh
    /// install before first-launch setup finished downloading it - or a real filesystem error, or
    /// `wineBinaryPath` doesn't have the expected `.../bin/wine` shape). Safe to call on every
    /// launch; the common-case path after the first one just confirms both symlinks still point at
    /// the right place and returns immediately.
    static func shellAppPath(forLaunching bottle: Bottle, wineBinaryPath: String) -> String? {
        guard !bottle.isReadOnly else { return nil } // a real wrapper already has its own, unrelated to this
        // ".../bin/wine" -> the engine root two levels up, matching the "<root>/bin/wine" shape
        // every engine this app can resolve to actually has (its own extracted engine, or a
        // borrowed wrapper's). Bails rather than building a shell pointed at a nonsense path if
        // `wineBinaryPath` doesn't actually have that shape for some unforeseen reason.
        guard wineBinaryPath.hasSuffix("/bin/wine") else { return nil }
        let engineDir = ((wineBinaryPath as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent

        let fm = FileManager.default
        let shellPath = shellAppPath(for: bottle)
        let configurePath = shellPath + "/Contents/Configure.app"
        let prefixLinkPath = shellPath + "/Contents/SharedSupport/prefix"
        let wineLinkPath = shellPath + "/Contents/SharedSupport/wine"

        if fm.fileExists(atPath: configurePath),
           (try? fm.destinationOfSymbolicLink(atPath: prefixLinkPath)) == bottle.prefixPath,
           (try? fm.destinationOfSymbolicLink(atPath: wineLinkPath)) == engineDir {
            return shellPath
        }

        guard fm.fileExists(atPath: SikarugirEngine.exeDockConfigureTemplatePath) else { return nil }

        do {
            try? fm.removeItem(atPath: shellPath)
            try fm.createDirectory(atPath: shellPath + "/Contents/SharedSupport", withIntermediateDirectories: true)
            try fm.copyItem(atPath: SikarugirEngine.exeDockConfigureTemplatePath, toPath: configurePath)
            try fm.createSymbolicLink(atPath: prefixLinkPath, withDestinationPath: bottle.prefixPath)
            try fm.createSymbolicLink(atPath: wineLinkPath, withDestinationPath: engineDir)
            DiagnosticsLog.log("ConfigureShellBuilder: built a Configure shell for \(bottle.name)")
            return shellPath
        } catch {
            DiagnosticsLog.log("ConfigureShellBuilder: couldn't build a shell for \(bottle.name) - \(error.localizedDescription)")
            try? fm.removeItem(atPath: shellPath)
            return nil
        }
    }
}
