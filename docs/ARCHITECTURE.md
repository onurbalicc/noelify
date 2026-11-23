# Architecture

```
┌──────────────────────────── Noelify (macOS app target) ───────────────────────────┐
│  NoelifyApp (MenuBarExtra .window)  ─►  ControlCenterView (SwiftUI)                │
│              │                                  │ user intents                     │
│              ▼                                  ▼                                  │
│        AppDelegate ──────────────────────►  AppModel (@MainActor ObservableObject) │
│   (quit → restore, screen changes)             │  banners, consent, recovery       │
│                                                │                                   │
│  MacWallpaperBackend (NSWorkspace)  BundledWallpaperProvider (App Support copies)  │
└───────────────┬────────────────────────────────┼───────────────────────────────────┘
                │ implements                      │ owns
┌───────────────▼──────────── NoelifyCore (Foundation only) ────────────────────────┐
│  ChristmasModeCoordinator ── activate / deactivate / update(settings)              │
│     ├─ WallpaperManager ── backup-before-change, restore, per-display outcomes     │
│     │     └─ WallpaperBackupStore (atomic JSON, doubles as crash marker)           │
│     └─ [EffectModule]  ← Snow, WindowSnow, Lights, Decorations, Audio (phases 2–5) │
│  NoelifySettings + SettingsStore (tolerant Codable, UserDefaults)                  │
└───────────────────────────────────────────────────────────────────────────────────┘
```

## Principles

- **Core is platform-free.** Everything that decides *what* happens lives in
  `NoelifyCore` and is unit-tested (it even builds on Linux CI). The app target is a thin
  AppKit/SwiftUI shell.
- **Effects are modules.** Each later engine implements `EffectModule`
  (`start` / `update` / `stop`) and is registered with the coordinator. Off means
  *stopped and released*: no timers, windows or audio left running.
- **Safety over cleverness.** No private APIs, no window injection. Visual effects will
  use transparent, click-through, non-activating overlay windows (Phase 2).
- **Honest reporting.** Every operation returns a report; the UI shows partial results
  as partial.

## Snow engine

```
SnowEffectModule (core) ── settings + PowerMonitor ─► SnowRenderConfiguration
      │ show / hide                                    flakes · fps · render scale
      ▼
SnowOverlayController ── one SnowOverlayWindow per display
      └─ SnowPanel › SnowContainerView › SKView › SnowScene ── SnowField (core)
```

- **`SnowField`** is a pure, seeded simulation: three parallax layers, per-flake sway from
  unrelated frequencies, and gusts from non-repeating noise that travel across the display.
  Flakes leaving one edge re-enter upwind with new properties, so density stays even and
  nothing is allocated per frame.
- **`SnowScene`** mirrors flakes to sprites that share one generated atlas (256 × 256 px;
  32 × 8 px for pixel art). A faint cool edge keeps white snow visible on white windows.
- **`SnowPanel`** is borderless, non-activating, ignores the mouse, can't become key or
  main, and sits at `.floating`: above app windows, below the Dock (20) and menu bar (24).
- **Render scale.** `SKView` draws at 0.5–0.6 of Retina resolution and Core Animation
  enlarges it, because frame buffers are the largest memory cost.
- **No flashes.** The content is transparent until SpriteKit has drawn four frames, then
  fades in; on close the panel leaves the screen before the scene is torn down.
- **Off means off.** Intensity Off or Christmas Mode Off closes the panels and releases the
  scene. Rendering also pauses when displays sleep, another user is active, or the overlay
  is fully occluded.
- **Health check.** SpriteKit's display link was twice observed not to start in a fresh
  process. Two seconds after showing or waking, an overlay that has produced no frames is
  replaced (at most three times).
