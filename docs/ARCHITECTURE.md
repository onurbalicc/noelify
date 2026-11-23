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

## Planned overlay design (Phase 2+)

One borderless `NSPanel` per display: `ignoresMouseEvents = true`, `canBecomeKey = false`,
level just above the desktop (snow) or `.floating`-adjacent where needed, collection
behaviour `[.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]`,
hosting an `SKView` with paused-when-hidden rendering and frame-rate caps per
Performance Mode.
