# Playdock

A Mac dashboard for the Windows games (and programs) you're already running through Wine - built
on top of the Sikarugir engine, not instead of it.

Steam is the front door: install it once, and Playdock shows your library as a proper grid -
box art, a short description, your account's name and avatar - with a big icon you double-click to
open Steam itself, same as you would on the desktop. Drag-and-drop `.exe` support is still in here
too, tucked under "Exe Loader" in the sidebar for when you just need to run something once.

## Installing

**Homebrew:**

```sh
brew install --cask jasonilization/playdock/playdock
```

**Manual:** grab the `.dmg` from [Releases](../../releases) and drag the app into `/Applications`.

Either way, it's signed with a free Apple Development identity rather than a paid Developer ID, so
it's not notarized - Gatekeeper will call it out as being from an unidentified developer on first
launch. Right-click the app → **Open**, or:

```sh
xattr -dr com.apple.quarantine "/Applications/Playdock.app"
```

Requires Sikarugir Creator to already be installed, with at least one Wine engine downloaded
(`~/Library/Application Support/Sikarugir/Engines/`) - that's the engine this app reuses.

## Contact & Support

**thesuperjasonprocoolisplay@hotmail.com**

Found a bug or want a feature? Open an [issue](../../issues) - that's the fastest way to get it
seen and tracked.

## Why this exists

Wine wrapper tools are great once you've built a wrapper. But "I just installed a game in Steam,
why do I need to build anything" is a real gap, and that's what this fills - point it at a Steam
bottle and it just works, no per-game setup.

## How it fits with Sikarugir

Playdock doesn't reimplement Windows compatibility - it reuses whatever Wine engine Sikarugir
Creator has already downloaded to `~/Library/Application Support/Sikarugir/Engines/`, extracting
its own private copy of it. Everything Playdock touches under `~/Library/Application
Support/ExeDock/` is its own - a separate bottle for Steam, a separate default bottle for
everything else - so it never writes to, or otherwise disturbs, Sikarugir Creator or any wrapper
app it's already built. (Yes, the folder's still called `ExeDock` internally - that's what this
project used to be called before the Steam-first rework, and renaming it on disk would silently
orphan anyone's existing bottles. Not worth it for a folder name nobody sees.)

If you need per-app engine builds, a specific DXVK/MoltenVK combo, or want to hand someone a
distributable wrapper for one program, that's still Sikarugir Creator's job - Playdock is the
"just let me play my games" layer on top, not a replacement for it.

Sikarugir Creator itself has to be installed by you - there's no real download URL for it baked
into this app on purpose. Guessing at one and silently fetching it felt like a bad idea, so if it's
missing, Playdock just tells you and waits.

## What it does

- **Steam dashboard** - your installed games as cards (art + description pulled from Steam's public
  store API, cached locally), your account name/avatar read straight out of Steam's own local
  config, double-click the Steam icon to launch it. Games installed through the real, separate
  macOS Steam client show up right alongside your Windows-via-Wine library too.
- **Custom Game Library** - import any Windows game folder (or a lone `.exe`) that isn't on Steam.
  Import moves it into Playdock's own managed bottle automatically, so it launches through the same
  engine as everything else - no per-game setup.
- **Advanced Mode** (off by default) - per-game engine/graphics/sync overrides, for the handful of
  games that actually need something different from your defaults.
- **Exe Loader** - drag an `.exe` onto the window, browse any bottle's C: drive Finder-style, or
  search everything Playdock's already found across your bottles.
- **Controller support** - a full D-pad/A/B focus loop across the dashboard, detail pages, and a
  dedicated Controller Mode carousel - not just one screen.
- **Setup that gets out of your way** - on first launch it finds/extracts an engine and sets up its
  own bottle automatically; if Sikarugir Creator has more than one engine downloaded, it asks which
  one to use (with a recommended pick) instead of silently guessing.

## Building from source

No Xcode required, just Swift + Command Line Tools:

```sh
./Scripts/build_app.sh        # swift build -c release, assemble Playdock.app, codesign
./Scripts/make_dmg.sh 1.2.0   # package dist/Playdock-1.2.0.dmg
```

## What's new

**Custom Game Library + native macOS Steam games (1.1.0)** - a Custom Game Library for anything
that isn't on Steam, native macOS Steam games showing up alongside your Wine library, a visible
"launching…" screen for every game (not just Steam ones), and full controller navigation across
the whole app.

**Steam-first rework** - the app used to be a generic exe launcher first, with Steam bolted on as
one feature (back when it was still called ExeDock). This flips that: Steam's dashboard is now the
default screen, with real account/game data pulled locally, per-game settings for anyone who wants
them, and a launch flow that no longer occasionally starts Steam twice (a real bug from an earlier
build - a retry heuristic was misreading Steam's normal "already running, handing off" exit as a
failure and launching a second copy on top of it).
