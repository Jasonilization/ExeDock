# ExeDock

A lightweight drag-and-drop UI for running Windows `.exe` files on the Mac.

Select or drag an `.exe` and ExeDock just runs it - no wrapper-creation ceremony, no manual Wine
setup. It also autodetects Windows programs already installed on any bottle's "C: drive" and gives
you a Finder-style browser to poke around one directly, plus a one-click **Install & Run Steam**
button that unlocks **Game Mode**.

## Under the hood

ExeDock does not reimplement Windows compatibility. It runs on the **Sikarugir** engine already
installed on this Mac - the same Wine engine that powers [Sikarugir Creator](https://github.com)
and any wrapper apps it has built (this machine already has wrapper apps built with it). ExeDock:

- Reuses the Wine engine Sikarugir Creator already downloaded to
  `~/Library/Application Support/Sikarugir/Engines/`, extracting its own private working copy.
- Runs everything in its **own** bottles under `~/Library/Application Support/ExeDock/Bottles/`,
  completely separate from any Sikarugir wrapper app's bottle.
- Never writes to, edits, or otherwise modifies Sikarugir Creator or any wrapper app it created -
  every interaction with those is read-only (listing an engine folder, reading a `drive_c`).

If you need full control over engine versions, DXVK/MoltenVK tuning per-app, or want to build a
distributable wrapper for one specific program, use Sikarugir Creator directly - ExeDock's About
tab has a button that opens it. ExeDock is the "drag it, run it" shortcut on top.

## Features

- **Run anything**: drag an `.exe` onto the window, or use *Select EXE…*.
- **Library**: every program ExeDock has found (its own bottles + read-only from Sikarugir wrapper
  apps like the ones already on this machine) in one searchable list.
- **C: Drive browser**: a Finder-style view of any bottle's `drive_c` - navigate folders, run an
  `.exe` in place, or reveal any file in Finder. Pick which bottle to browse from the dropdown at
  the top.
- **Install & Run Steam**: downloads Valve's official Steam bootstrapper, silently installs it into
  a dedicated Steam bottle, and launches it.
- **Game Mode**: once Steam is installed, exposes the same engine/graphics toggles Sikarugir
  wrappers already support (D3DMETAL, DXVK, DXMT, MoltenVK CX, WINEESYNC/WINEMSYNC, engine choice)
  for that Steam/game bottle.

## Building from source

Full Xcode isn't required - only Swift + Command Line Tools:

```sh
./Scripts/build_app.sh        # swift build -c release, assemble ExeDock.app, codesign
./Scripts/make_dmg.sh 1.0.0   # package dist/ExeDock-1.0.0.dmg
```

## Installing

Download the `.dmg` from [Releases](../../releases), drag `ExeDock.app` to `/Applications`.

This build is signed with a free Apple Development identity, not a paid Developer ID, so it isn't
notarized. On first launch, Gatekeeper will say it's from an unidentified developer - right-click
`ExeDock.app` → **Open**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/ExeDock.app
```

## Requirements

Sikarugir Creator must be installed and have downloaded at least one Wine engine
(`~/Library/Application Support/Sikarugir/Engines/`) before ExeDock can run anything - that's the
engine ExeDock reuses.
