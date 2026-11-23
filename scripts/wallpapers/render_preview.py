#!/usr/bin/env python3
"""Renders Noelify's development preview wallpaper ("Winter Night").

Procedural, original artwork: every pixel comes from this script, so there are no
third-party licensing questions. This is a development-time tool only — the app
itself has no Python dependency.

    python3 scripts/wallpapers/render_preview.py [--width 5120 --height 2880] [--out PATH]

Requires numpy and Pillow.
"""
import argparse
import math
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def lerp(a, b, t):
    return a + (b - a) * t


def hex_rgb(h):
    return np.array([(h >> 16) & 255, (h >> 8) & 255, h & 255], dtype=np.float32)


def vertical_gradient(w, h, stops):
    """stops: list of (position 0..1, 0xRRGGBB)."""
    y = np.linspace(0, 1, h, dtype=np.float32)[:, None]
    out = np.zeros((h, 1, 3), dtype=np.float32)
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        m = ((y >= p0) & (y <= p1)).astype(np.float32)
        t = np.clip((y - p0) / max(p1 - p0, 1e-6), 0, 1)
        t = t * t * (3 - 2 * t)  # smoothstep
        col = hex_rgb(c0)[None, None, :] * (1 - t[..., None]) + hex_rgb(c1)[None, None, :] * t[..., None]
        out = np.where(m[..., None] > 0, col, out)
    return np.repeat(out, w, axis=1)


def composite(base, color, mask):
    """Alpha-blend a flat colour (or colour image) through a 0..1 mask."""
    if mask.ndim == 2:
        mask = mask[..., None]
    return base * (1 - mask) + color * mask


def ridge(w, rng, base, amp, octaves, seed_phase, peaked=False):
    """A 1-D mountain/hill profile (y in pixels) built from layered sines + noise.

    peaked=True uses ridged (|sin|) octaves, which gives sharp summits."""
    x = np.arange(w, dtype=np.float32) / w
    y = np.full(w, base, dtype=np.float32)
    for i in range(octaves):
        f = (i + 1) ** 1.7
        wave = np.sin(2 * math.pi * f * x * 1.3 + seed_phase * (i + 1) + rng.random() * 6)
        if peaked:
            wave = 1.0 - 2.0 * np.abs(wave)  # sharp crests pointing up (negative y = higher)
            wave = -wave
        y += amp / (i + 1) ** 1.25 * wave
    # small jagged detail
    noise = np.cumsum(rng.normal(0, amp * 0.0015 * (5120 / w) ** 0.5, w)).astype(np.float32)
    noise -= np.linspace(noise[0], noise[-1], w)
    return y + noise


def profile_mask(w, h, profile, blur):
    yy = np.arange(h, dtype=np.float32)[:, None]
    m = np.clip(yy - profile[None, :] + 0.5, 0, 1)
    img = Image.fromarray((m * 255).astype(np.uint8))
    if blur:
        img = img.filter(ImageFilter.GaussianBlur(blur))
    return np.asarray(img, dtype=np.float32) / 255


def pine(draw, x, ground, height, color, snow, scale):
    """A layered pine silhouette with snow on each tier."""
    tiers = 5
    trunk_w = height * 0.05
    draw.rectangle([x - trunk_w / 2, ground - height * 0.12, x + trunk_w / 2, ground], fill=color)
    for i in range(tiers):
        t = i / (tiers - 1)
        top = ground - height * (1.0 - 0.17 * i)
        bottom = ground - height * (0.62 - 0.14 * i) + height * 0.02
        half = height * lerp(0.13, 0.36, t)
        draw.polygon([(x, top), (x - half, bottom), (x + half, bottom)], fill=color)
        # snow cap on the tier: a lighter sliver on the upper edge
        sh = (bottom - top) * 0.28
        draw.polygon(
            [(x, top + sh * 0.1), (x - half * 0.55, top + sh * 1.6), (x - half * 0.15, top + sh * 1.25),
             (x + half * 0.2, top + sh * 1.55), (x + half * 0.5, top + sh * 1.3)],
            fill=snow,
        )


def render(w, h, seed=24):
    rng = np.random.default_rng(seed)
    prng = random.Random(seed)
    s = w / 5120  # scale factor relative to 5K

    # --- Sky ---------------------------------------------------------------
    img = vertical_gradient(w, h, [
        (0.00, 0x050B1A), (0.30, 0x0D1B36), (0.55, 0x1C3561), (0.72, 0x37527F), (1.00, 0x4A5F86),
    ])

    # Soft aurora-like glow band (very subtle, keeps the preview calm)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    band_center = h * 0.30 + np.sin(xx / w * math.pi * 2.0 + 0.7) * h * 0.06
    band = np.exp(-((yy - band_center) / (h * 0.07)) ** 2) * (0.5 + 0.5 * np.sin(xx / w * math.pi * 3 + 1.1)) ** 2
    img = composite(img, hex_rgb(0x5FD3B5), band * 0.10)
    img = composite(img, hex_rgb(0x8A7BE0), np.exp(-((yy - band_center + h * 0.06) / (h * 0.09)) ** 2) * 0.05)

    # Moon with halo
    mx, my, mr = w * 0.76, h * 0.20, 70 * s
    d = np.sqrt((xx - mx) ** 2 + (yy - my) ** 2)
    img = composite(img, hex_rgb(0xBFD7F2), np.clip(np.exp(-(d / (mr * 6)) ** 2) * 0.22, 0, 1))
    img = composite(img, hex_rgb(0xDCE9FA), np.clip(np.exp(-(d / (mr * 2.2)) ** 2) * 0.35, 0, 1))
    moon = np.clip(mr - d + 1, 0, 1)
    img = composite(img, hex_rgb(0xF6F1E3), moon)
    # faint maria
    for ox, oy, r in [(-0.25, -0.15, 0.30), (0.20, 0.25, 0.22), (0.30, -0.30, 0.15)]:
        dd = np.sqrt((xx - (mx + ox * mr)) ** 2 + (yy - (my + oy * mr)) ** 2)
        img = composite(img, hex_rgb(0xD9D2C0), np.clip(r * mr - dd + 1, 0, 1) * moon * 0.55)
    del d, dd

    # Stars (denser at the top, a few with soft glow)
    star_layer = np.zeros((h, w), dtype=np.float32)
    n = int(1400 * s * s * 1.0 + 400)
    for _ in range(n):
        x = rng.integers(0, w)
        y = int(abs(rng.normal(0, 0.33)) * h * 0.85)
        if y >= h * 0.62:
            continue
        b = rng.random() ** 2.2
        star_layer[y, x] = max(star_layer[y, x], 0.25 + 0.75 * b)
    star_img = Image.fromarray((star_layer * 255).astype(np.uint8))
    core = np.asarray(star_img.filter(ImageFilter.GaussianBlur(0.9 * s + 0.3)), dtype=np.float32) / 255 * 3.0
    glow = np.asarray(star_img.filter(ImageFilter.GaussianBlur(5 * s)), dtype=np.float32) / 255 * 6.0
    img = composite(img, hex_rgb(0xFFFFFF), np.clip(core, 0, 1))
    img = composite(img, hex_rgb(0xBFD9FF), np.clip(glow, 0, 0.35))

    # --- Mountains (atmospheric perspective: far = lighter & bluer) ---------
    layers = [
        (h * 0.60, h * 0.075, 5, 0x2B4269, 0x6F8AB4, 1.2),
        (h * 0.665, h * 0.055, 4, 0x203655, 0x93A9CB, 1.0),
    ]
    for base, amp, octv, rock, snowcol, blur in layers:
        prof = ridge(w, rng, base, amp, octv, prng.random() * 6, peaked=True)
        m = profile_mask(w, h, prof, blur * s)
        # snowy upper slopes: bright cap near the ridge line fading into shadowed rock
        dist = np.clip((yy - prof[None, :]) / (h * 0.05), 0, 1) ** 0.7
        # moonlit (right-facing) slopes stay brighter
        k = max(3, int(w / 160)) | 1
        smooth = np.convolve(prof, np.ones(k) / k, mode="same")
        slope = np.gradient(smooth) / (h / 1080)
        dist = np.clip(dist + np.clip(-slope[None, :] * 0.10, -0.3, 0.3), 0, 1)
        # soften column-to-column variation so slopes read as smooth snowfields, not streaks
        dist_img = Image.fromarray((dist * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(9 * s))
        dist = np.asarray(dist_img, dtype=np.float32) / 255
        layer_col = hex_rgb(snowcol)[None, None, :] * (1 - dist[..., None]) + hex_rgb(rock)[None, None, :] * dist[..., None]
        img = composite(img, layer_col, m)

    # Low mist
    mist = np.exp(-((yy - h * 0.70) / (h * 0.05)) ** 2)
    img = composite(img, hex_rgb(0x9DB4D6), mist * 0.18)

    # --- Pine forest (two depths) -------------------------------------------
    def forest(ground_base, count, hmin, hmax, color, snow, jitter):
        layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        dr = ImageDraw.Draw(layer)
        xs = sorted(prng.uniform(-0.02, 1.02) * w for _ in range(count))
        for x in xs:
            g = ground_base + math.sin(x / w * math.pi * 2.3) * h * 0.012 + prng.uniform(-jitter, jitter)
            pine(dr, x, g, prng.uniform(hmin, hmax) * h, color, snow, s)
        return layer.filter(ImageFilter.GaussianBlur(0.7 * s))

    def paste(base_arr, layer):
        a = np.asarray(layer, dtype=np.float32)
        return composite(base_arr, a[..., :3], a[..., 3] / 255)

    img = paste(img, forest(h * 0.735, int(170 * 1), 0.035, 0.07, (31, 52, 84, 255), (120, 146, 182, 255), h * 0.006))

    # Mid snow field
    prof = ridge(w, rng, h * 0.76, h * 0.02, 3, prng.random() * 6)
    m = profile_mask(w, h, prof, 1.2 * s)
    field = vertical_gradient(w, h, [(0.0, 0xC9D8EE), (0.76, 0xC9D8EE), (0.90, 0x9FB4D4), (1.0, 0x8FA6CB)])
    img = composite(img, field, m)

    img = paste(img, forest(h * 0.80, 34, 0.08, 0.16, (17, 34, 56, 255), (196, 214, 236, 255), h * 0.01))

    # --- Warm lit cabin (a hint of coziness) --------------------------------
    cab = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dr = ImageDraw.Draw(cab)
    cx, cg = w * 0.30, h * 0.835
    cw, ch = 240 * s, 150 * s
    dr.rectangle([cx - cw / 2, cg - ch, cx + cw / 2, cg], fill=(42, 30, 34, 255))
    dr.polygon([(cx - cw * 0.62, cg - ch), (cx, cg - ch * 1.85), (cx + cw * 0.62, cg - ch)], fill=(34, 26, 32, 255))
    dr.polygon([(cx - cw * 0.66, cg - ch * 0.97), (cx, cg - ch * 1.92), (cx + cw * 0.66, cg - ch * 0.97),
                (cx + cw * 0.5, cg - ch * 1.12), (cx, cg - ch * 1.75), (cx - cw * 0.5, cg - ch * 1.12)],
               fill=(226, 236, 250, 255))
    for wx in (-0.25, 0.22):
        dr.rectangle([cx + wx * cw - 20 * s, cg - ch * 0.70, cx + wx * cw + 20 * s, cg - ch * 0.35], fill=(255, 196, 110, 255))
    dr.rectangle([cx + cw * 0.18, cg - ch * 1.62, cx + cw * 0.30, cg - ch * 1.25], fill=(34, 26, 32, 255))
    img = paste(img, cab.filter(ImageFilter.GaussianBlur(0.6 * s)))
    # window glow on snow
    d = np.sqrt(((xx - cx) / (1.6)) ** 2 + (yy - (cg - ch * 0.4)) ** 2)
    img = composite(img, hex_rgb(0xFFB866), np.clip(np.exp(-(d / (260 * s)) ** 2) * 0.28, 0, 1))

    # --- Foreground drift ----------------------------------------------------
    prof = ridge(w, rng, h * 0.90, h * 0.03, 3, prng.random() * 6)
    m = profile_mask(w, h, prof, 1.5 * s)
    fg = vertical_gradient(w, h, [(0.0, 0xE6EEF9), (0.88, 0xE6EEF9), (0.95, 0xC2D2E9), (1.0, 0xAFC2DF)])
    img = composite(img, fg, m)
    # moonlit sparkle on the drift
    sp = np.zeros((h, w), dtype=np.float32)
    for _ in range(int(900 * s * s + 200)):
        x = rng.integers(0, w)
        y = rng.integers(int(h * 0.86), h)
        sp[y, x] = rng.random()
    sp_img = Image.fromarray((sp * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8 * s))
    img = composite(img, hex_rgb(0xFFFFFF), (np.asarray(sp_img, dtype=np.float32) / 255 * 2.5 * m).clip(0, 0.8))

    # --- Gentle falling snow (static, the Snow Engine animates the real thing) ---
    flakes = Image.new("L", (w, h), 0)
    fd = ImageDraw.Draw(flakes)
    for _ in range(int(500 * s * s + 120)):
        x, y = prng.uniform(0, w), prng.uniform(0, h * 0.95)
        r = prng.uniform(1.0, 4.2) * s
        fd.ellipse([x - r, y - r, x + r, y + r], fill=int(prng.uniform(70, 190)))
    fl = np.asarray(flakes.filter(ImageFilter.GaussianBlur(1.1 * s)), dtype=np.float32) / 255
    img = composite(img, hex_rgb(0xF5F9FF), fl)

    # Vignette + fine grain (prevents banding on large displays)
    vig = ((xx / w - 0.5) ** 2 * 1.2 + (yy / h - 0.45) ** 2) * 0.55
    img *= (1 - np.clip(vig, 0, 0.35))[..., None]
    img += rng.normal(0, 1.4, img.shape).astype(np.float32)

    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--width", type=int, default=5120)
    ap.add_argument("--height", type=int, default=2880)
    ap.add_argument("--out", default="Resources/Wallpapers/noelify-preview.jpg")
    args = ap.parse_args()
    img = render(args.width, args.height)
    img.save(args.out, quality=92, subsampling=0, optimize=True)
    print(f"wrote {args.out} ({args.width}x{args.height})")


if __name__ == "__main__":
    main()
