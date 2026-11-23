# Testing & performance

## Automatic

- `swift test` — 59 unit tests (34 for snow): settings, power budget, simulation, module lifecycle.
- `Noelify.app/Contents/MacOS/Noelify --snow-diagnostics <folder> --checks-only` — drives the
  real overlay: 60 rapid toggles, 25 restarts, click-through (asks the window server who
  would receive a click at 384 points, with a control), focus, window level, pause/resume,
  every setting. Uses its own preferences domain and never touches the wallpaper.
  **Snow appears and disappears repeatedly while it runs**, so CI is the best place for it.
- `... --benchmark-only [--power pluggedIn|battery|constrained] [--seconds 8]` — CPU, memory, fps.
- CI also photographs the composited desktop: snow must move, must never change more than a
  small part of the screen during on/off cycles (flash check), and must leave nothing behind.

## By eye (about two minutes)

Automatic checks can't judge beauty or every system state. Screenshots: ⌘⇧3.

1. Turn on Christmas Mode › **Effects Only**. Snow fades in with no flash.
2. Click, scroll, drag and type in Finder, Safari and Terminal through the snow. Use the menu bar and Dock.
3. Screenshot over a dark window and over a white web page. Snow should be visible but calm on both.
4. Try each Intensity, Wind, Size and Style. Each must look clearly different.
5. Open Mission Control, switch Spaces, enter and leave a fullscreen app.
6. Change the display scale in System Settings › Displays. Snow still fills the display.
7. Unplug the charger: the snow thins out. Plug it back in.
8. Toggle Christmas Mode off and quit: nothing remains, the desktop is as before.

## Performance

MacBook Air (M3, 8 GPU cores), macOS 26.6.1, 1280 × 832 pt @2x, v0.2.0 local `swiftc -O` build,
8 s per row after a 3 s settle. CPU is percent of **one** core; memory is the physical
footprint Activity Monitor shows. Other apps were running.

| Snow | Plugged in: CPU · memory · fps · flakes | Battery profile: CPU · memory · fps · flakes |
|---|---|---|
| Light (default) | 6.2 % · 90 MB · 30 · 66 | 5.8 % · 82 MB · 30 · 43 |
| Medium | 4.7 % · 91 MB · 30 · 140 | 5.8 % · 82 MB · 30 · 91 |
| Heavy | 4.6 % · 91 MB · 30 · 271 | 5.8 % · 82 MB · 30 · 176 |
| Blizzard | 11.4 % · 98 MB · 58 · 526 | 7.1 % · 83 MB · 30 · 342 |
| Medium, Soft | 5.5 % · 98 MB · 30 · 140 | 5.7 % · 83 MB · 30 · 91 |
| Medium, Magical | 5.2 % · 98 MB · 30 · 140 | 5.4 % · 83 MB · 30 · 91 |
| Medium, Pixel | 7.8 % · 84 MB · 30 · 140 | 5.3 % · 83 MB · 29 · 91 |
| Snow off / Christmas Mode off | 0.0 % · 17 MB · 0 · 0 | 0.0 % · 23 MB · 0 · 0 |

- The battery profile was simulated (`--power battery`) with the charger connected.
- CPU varied between runs: at 30 fps from 1 % to 8 %, depending on what else was running.
  The flake count hardly matters; the frame rate does.
- About 50 MB is Metal's fixed cost, returned when the snow stops.
- `WindowServer` varied from 3 % to 43 % of a core across the runs, depending on other apps;
  the snow's share couldn't be isolated reliably. GPU utilisation likewise.
- Energy in watts wasn't measured: `powermetrics` needs administrator rights.
- Figures predate the fade-in added last, which only runs during the first half second.
