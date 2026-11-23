# Platform limits (honest list)

Things macOS's public APIs don't let Noelify do perfectly. Each item says what Noelify
does about it. Items marked *unverified* still need testing on real hardware.

## Wallpaper

| Situation | What happens |
|---|---|
| **Multiple Spaces** | `NSWorkspace` reads and sets the wallpaper of the *current* Space on each display. Noelify changes and restores the Space that is active at that moment. If you use different wallpapers per Space and switch Spaces while Christmas Mode is on, other Spaces may keep their own wallpaper (fine) — but restore happens on whichever Space is active when you turn it off. *Unverified across macOS 13/14/15/26; to be tested in Phase 6.* |
| **Dynamic (.heic) wallpapers** | The `.heic` file URL is backed up and restored; macOS should resume the dynamic behaviour. *Unverified.* |
| **Aerial / Landscape / "Shuffle" / photo-album rotation** (macOS 14+) | These aren't exposed as a file by the public API. macOS reports a still image, and that still image is what Noelify can restore. Rotation/aerial settings may need to be re-selected in System Settings › Wallpaper. |
| **Original file deleted/moved or on an unmounted drive** | Reported as "could not be restored" — never as success. |
| **Display disconnected while Christmas Mode is on** | Its original stays in the backup and is restored once it's reconnected (choose Restore). |
| **Display connected while Christmas Mode is on** | Its current wallpaper is backed up, then the Christmas wallpaper is applied (about 1 s after macOS reports the change). |
| **Running from Xcode / `swift run`** | No `.app` bundle → no bundled wallpapers. Build with `scripts/build-app.sh`. |

## Not yet applicable (later phases)

Overlay behaviour in fullscreen apps, Stage Manager, Mission Control and multiple Spaces
is investigated in Phases 2–4 and will be documented here with test results.
