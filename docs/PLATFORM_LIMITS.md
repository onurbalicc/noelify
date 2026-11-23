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

## Snow overlay

| Situation | What happens |
|---|---|
| **Menu bar, Dock, menus, notifications, Control Center** | These stay in front of the snow (they use higher window levels). |
| **Spaces** | The overlay asks to join every Space. *Needs checking by eye.* |
| **Mission Control** | The overlay is marked stationary. Whether snow keeps falling over the thumbnails is decided by macOS. *Needs checking by eye.* |
| **Fullscreen apps** | The overlay may join fullscreen Spaces, so snow can appear over fullscreen video. Apps that take over the display directly (some games) can hide it. *Needs checking by eye.* |
| **Lock screen, login window, screen saver, password prompts** | macOS draws these above every app; snow isn't shown there. |
| **Other always-on-top windows** | Share the same level; whichever came forward last is in front. |
| **Screenshots, recordings, screen sharing** | Include the snow, like any other window. Turn Christmas Mode off first if you don't want it. |
| **Window server load** | Any full-screen animated overlay makes macOS redraw the whole display every frame. That work shows up under `WindowServer`, not Noelify. Gentle snow is capped at 30 fps for this reason. |
| **Reduce Motion** | Not consulted yet: snow only starts when you turn it on. |
| **Multiple displays** | One overlay per display, added and removed as displays change. *Untested on hardware.* |

## Later phases

Stage Manager and window snow are investigated in Phase 4.
