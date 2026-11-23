# 🎄 Noelify

**One Click. Christmas Everywhere.**
*Turn your Mac into a Winter Wonderland.*

Noelify is a native macOS menu bar app (Swift · SwiftUI · AppKit) that transforms your
desktop into a calm, beautiful Christmas world — and puts everything back exactly as it
was when you switch it off.

> **Status: Phase 2 — Living Snow Engine (v0.2.0, development build).**
> Working today: everything from Phase 1 (menu bar app, Control Center, Christmas Mode,
> consent-gated wallpaper change with backup & restore, crash recovery) plus animated
> snowfall over your apps with intensity, wind, size and style settings.
> Window snow, lights, decorations and the four final world wallpapers are **not** in
> this build (see [Roadmap](#roadmap)).

## Requirements

- macOS 13 Ventura or later (Apple Silicon first; Intel should work but is untested)
- Xcode 15 or later (or matching Command Line Tools) to build from source

## Build & run

```bash
git clone https://github.com/onurbalicc/noelify.git
cd noelify
swift test                 # run the unit tests
scripts/build-app.sh       # builds ./build/Noelify.app (ad-hoc signed, local use)
open build/Noelify.app
```

A ❄︎ snowflake appears in the menu bar. Click it to open the Control Center.

To work in Xcode, open the folder (or `Package.swift`) — Xcode opens Swift packages
directly. Run the `Noelify` scheme. Note: when launched from Xcode the app isn't inside
a `.app` bundle, so bundled wallpapers aren't found and Noelify will honestly report
"No wallpaper … yet". Use `scripts/build-app.sh` to test wallpapers.

The build is ad-hoc signed and **not notarized** — macOS may ask you to confirm the
first launch (right-click › Open). Notarization needs an Apple Developer account and is
planned for release builds.

## How the wallpaper change works (and why it's safe)

The first time you turn on Christmas Mode, Noelify asks before touching your wallpaper
(**Change Wallpaper** / **Effects Only**). Then:

1. Before changing anything it writes a backup of each display's current wallpaper URL
   and display options to `~/Library/Application Support/Noelify/wallpaper-backup.json`.
   If that write fails, nothing is changed.
2. The backup is never overwritten by later changes (switching worlds), so it always
   holds your real original.
3. Turning Christmas Mode off, or quitting Noelify, restores the originals.
   If a display is disconnected, its original is kept and restored later.
4. If Noelify crashes, the next launch offers **Restore Now**.
5. Your picture files are only referenced — never copied over, moved or deleted.
   Restores that don't fully succeed are reported as such, never as success.

See [docs/PLATFORM_LIMITS.md](docs/PLATFORM_LIMITS.md) for cases macOS doesn't let us
restore perfectly (Spaces, Aerial/Shuffle wallpapers).

## Snow

Turn on Christmas Mode and choose **Intensity** (Off · Light · Medium · Heavy · Blizzard),
**Wind** (Calm · Breeze · Windy), **Size** (Small · Mixed · Large) and **Style**
(Realistic · Soft · Magical · Pixel). Settings are saved. The snow never takes clicks or
keyboard focus, uses fewer flakes on battery, and is released completely when it's off.
Measurements: [docs/TESTING.md](docs/TESTING.md#performance).

## Privacy

No telemetry, no analytics, no network requests, no trackers, no login items, no admin
rights. Noelify needs **no special permissions** so far. Details: [docs/PRIVACY.md](docs/PRIVACY.md).

## Project layout

```
Package.swift                 Swift package (open in Xcode)
Sources/NoelifyCore/          Platform-independent logic (Foundation only, unit-tested)
  Settings/                   Worlds, settings model & persistence
  Wallpaper/                  Backup/restore engine
  Snow/                       Snow settings, power budget, simulation, effect module
  ChristmasMode/              Coordinator + EffectModule protocol for future engines
Sources/Noelify/              macOS app (SwiftUI + AppKit)
  App/                        Entry point, AppDelegate, AppModel
  UI/                         Control Center, components, design tokens
  SnowEngine/                 SpriteKit scene, generated textures, overlay windows
  WallpaperManager/           NSWorkspace backend, bundled wallpaper installer
Tests/NoelifyCoreTests/       XCTest suite
Resources/Wallpapers/         Bundled wallpapers (offline)
Support/Info.plist            App bundle metadata (LSUIElement menu bar app)
scripts/build-app.sh          Assembles + ad-hoc signs Noelify.app
scripts/wallpapers/           Procedural wallpaper generators (dev tools, Python)
docs/                         Architecture, privacy, platform limits, testing & performance
```

## Roadmap

| Phase | Scope | Status |
|---|---|---|
| 1 Foundation | Menu bar app, Control Center, Christmas Mode, Wallpaper Manager | ✅ runs on a real Mac |
| 2 Snow Engine | Click-through overlay, SpriteKit snow, intensity/wind/size/style | ✅ built and tested — see [docs/TESTING.md](docs/TESTING.md) for what still needs a human eye |
| 3 Christmas Worlds | Four final wallpapers, theme effects, transitions | ⏳ |
| 4 Living Desktop | Window snow, lights, snowman, Santa, shooting stars | ⏳ |
| 5 Premium | Onboarding, presets, ambient sound, multi-monitor, battery saver | ⏳ |
| 6 Polish & Release | Profiling, compatibility matrix, security review, release | ⏳ |

## Artwork

All artwork is original. The Phase 1 preview wallpaper (`Resources/Wallpapers/noelify-preview.jpg`)
is generated by `scripts/wallpapers/render_preview.py` and is a development placeholder
until each world's final wallpaper ships.

## License

MIT — see [LICENSE](LICENSE).
