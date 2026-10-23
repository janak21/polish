#!/usr/bin/env python3
"""Builds Resources/AppIcon.icns from art/menubar-icon-source.png: the pen glyph in white on a gradient rounded square.

Run from the repo root: python3 art/make-app-icon.py (needs Pillow + numpy; iconutil ships with macOS).
"""
import os
import subprocess
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 1024
TILE, RADIUS = 824, 185  # macOS icon grid: 824 px rounded square centered on a 1024 canvas
TOP, BOTTOM = (79, 107, 255), (155, 77, 255)  # blue → purple, diagonal

# The source has a painted checkerboard (≈246–254 luminance), not transparency: turn darkness into alpha.
lum = np.asarray(Image.open("art/menubar-icon-source.png").convert("L"), dtype=float)
alpha = np.clip((235 - lum) / 225, 0, 1)
ys, xs = np.nonzero(alpha > 0.5)
alpha = alpha[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
glyph = Image.new("RGBA", (alpha.shape[1], alpha.shape[0]), "white")
glyph.putalpha(Image.fromarray((alpha * 255).astype(np.uint8)))
glyph.thumbnail((int(TILE * 0.62),) * 2, Image.LANCZOS)

# Rounded-square mask, drawn at 4x and scaled down for smooth edges.
big = Image.new("L", (S * 4, S * 4))
o = (S - TILE) // 2 * 4
ImageDraw.Draw(big).rounded_rectangle((o, o, o + TILE * 4, o + TILE * 4), RADIUS * 4, fill=255)
mask = big.resize((S, S), Image.LANCZOS)

t = (np.add.outer(np.arange(S), np.arange(S)) / (2 * (S - 1)))[..., None]
gradient = Image.fromarray((np.array(TOP) * (1 - t) + np.array(BOTTOM) * t).astype(np.uint8), "RGB").convert("RGBA")

icon = Image.new("RGBA", (S, S))
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 255))
shadow.putalpha(mask.point(lambda v: v * 0.3).filter(ImageFilter.GaussianBlur(14)))
icon.alpha_composite(shadow, (0, 10))
icon.paste(gradient, (0, 0), mask)
icon.alpha_composite(glyph, ((S - glyph.width) // 2, (S - glyph.height) // 2))

with tempfile.TemporaryDirectory() as tmp:
    iconset = os.path.join(tmp, "AppIcon.iconset")
    os.mkdir(iconset)
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
            icon.resize((size * scale,) * 2, Image.LANCZOS).save(os.path.join(iconset, name))
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", "Resources/AppIcon.icns"], check=True)
icon.save(os.environ.get("PREVIEW", os.path.join(tempfile.gettempdir(), "AppIcon-preview.png")))
print("wrote Resources/AppIcon.icns")
