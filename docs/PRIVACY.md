# Privacy & permissions

Noelify is built to be trustworthy enough to install without reading its source — but
the source is here if you want to.

## What Noelify never does

- No telemetry, analytics, crash reporters, ads or trackers.
- No network requests of any kind. (The app links no networking code of its own; you
  can verify with Little Snitch / LuLu.)
- No root/sudo, no privileged helpers, no changes to Gatekeeper or SIP.
- No Login Items or background agents unless you explicitly add one (not offered yet).
- Never reads document contents, window titles, typed text, passwords or screen contents.
- Never deletes, moves or overwrites your wallpaper files.

## Files Noelify writes

All inside `~/Library/Application Support/Noelify/`, plus its preferences domain:

| Path | Contents | When |
|---|---|---|
| `wallpaper-backup.json` | URL + display options of each display's original wallpaper, display UUID and name | Before the first wallpaper change; deleted after a full restore |
| `Wallpapers/` | Copies of Noelify's own bundled wallpapers | When a Christmas wallpaper is applied |
| `~/Library/Preferences/app.noelify.Noelify.plist` | Your Noelify settings | When you change a setting |

To remove Noelify completely: quit it (this restores your wallpaper), delete the app, then
delete the folder and plist above.

## Permissions by feature

| Feature | Permission | Status |
|---|---|---|
| Christmas Mode, wallpaper change/restore | None (public `NSWorkspace` API) | Phase 1 |
| Snowfall overlay | None. Draws its own window; reads no screen or window content. Power source and Low Power Mode are read to save battery. | Phase 2 |
| Window snow (snow on window tops) | **Accessibility** — requested only when you enable Window Snow, after an explanation. Used solely to read window *frames* (position/size). | Phase 4 |
| Ambient sounds | None (bundled audio, off by default) | Phase 5 |

This document describes intended behaviour and is kept in sync with the code. It is
not an independent security audit.
