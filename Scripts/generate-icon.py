#!/usr/bin/env python3
"""Build Resources/AppIcon.icns from Resources/AppIcon.png.

The master art is a full-bleed square. macOS app icons are not: they sit on a
squircle that occupies 824 of a 1024 canvas, and skipping that makes an icon
that looks oversized and wrongly shaped next to everything else in the Dock.
"""

from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "Resources" / "AppIcon.png"
OUT_ICNS = ROOT / "Resources" / "AppIcon.icns"

# Apple's macOS icon grid: 824x824 of artwork inside a 1024x1024 canvas.
ART_RATIO = 824 / 1024
# The corner is a superellipse, not a circular arc. Exponent 5 is the standard
# approximation of the shape Apple uses; a plain rounded rectangle reads as
# visibly too round at large sizes.
SQUIRCLE_EXPONENT = 5.0
SUPERSAMPLE = 4

# (size, scale) pairs iconutil expects in an .iconset.
VARIANTS = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]


def squircle_mask(size: int) -> Image.Image:
    """Anti-aliased superellipse mask, rendered supersampled then downscaled."""
    hi = size * SUPERSAMPLE
    axis = np.linspace(-1.0, 1.0, hi, endpoint=True)
    x = np.abs(axis)[None, :] ** SQUIRCLE_EXPONENT
    y = np.abs(axis)[:, None] ** SQUIRCLE_EXPONENT
    inside = (x + y) <= 1.0
    mask = Image.fromarray((inside * 255).astype(np.uint8), mode="L")
    return mask.resize((size, size), Image.LANCZOS)


def icon_canvas(master: Image.Image, canvas: int) -> Image.Image:
    art = max(1, round(canvas * ART_RATIO))
    shaped = master.resize((art, art), Image.LANCZOS).convert("RGBA")
    shaped.putalpha(squircle_mask(art))

    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    offset = (canvas - art) // 2
    out.paste(shaped, (offset, offset), shaped)
    return out


def main() -> None:
    if not MASTER.exists():
        raise SystemExit(f"missing master art: {MASTER}")

    master = Image.open(MASTER).convert("RGBA")
    if master.width != master.height:
        raise SystemExit(f"master art must be square, got {master.width}x{master.height}")

    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for size, scale in VARIANTS:
            suffix = "" if scale == 1 else f"@{scale}x"
            icon_canvas(master, size * scale).save(iconset / f"icon_{size}x{size}{suffix}.png")
        subprocess.run(
            ["iconutil", "--convert", "icns", str(iconset), "--output", str(OUT_ICNS)],
            check=True,
        )

    print(f"→ {OUT_ICNS.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
