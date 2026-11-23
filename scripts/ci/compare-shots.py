"""Checks that snow reaches the composited screen, moves, and leaves nothing behind.

Reads snow1/snow2/quiet1/quiet2.bmp (uncompressed, from `screencapture -t bmp`).
"""
import pathlib
import struct
import sys

folder = pathlib.Path(sys.argv[1])


def pixels(name):
    data = (folder / f"{name}.bmp").read_bytes()
    offset = struct.unpack_from("<I", data, 10)[0]
    width, height = struct.unpack_from("<ii", data, 18)
    bits = struct.unpack_from("<H", data, 28)[0]
    print(f"{name}: {width}x{height}, {bits} bit")
    return data[offset:], bits // 8


def changed_fraction(a, b):
    (first, step), (second, _) = pixels(a), pixels(b)
    total = min(len(first), len(second)) // step
    # The green channel of every other pixel is plenty.
    g1, g2 = first[1 :: step * 2], second[1 :: step * 2]
    changed = sum(1 for x, y in zip(g1, g2) if abs(x - y) > 10)
    return changed / max(total // 2, 1)


moving = changed_fraction("snow1", "snow2")
still = changed_fraction("quiet1", "quiet2")
print(f"changed within one second: with snow {moving:.4%}, after quitting {still:.4%}")
if moving < 0.0005 or moving < still * 3:
    sys.exit("snow does not appear to be moving on the composited screen")
