#!/usr/bin/env python3
"""Extract a relightable cloud layer from the 人里 skybox panorama.

WHY: the concept skybox is a 2:1 equirectangular painting baked at one hour of
one afternoon. The project has a real day-night cycle, so the painting cannot
be used as-is: at night it would still be afternoon. Option A (the user's pick)
keeps the painted CLOUD SHAPES but lets sky_daynight.gdshader compute the sky
colour and relight the clouds by sun position.

Output: one RGBA PNG, still 2:1 equirect so the shader can sample it by view
direction.
  R = cloud coverage 0..1 (how much cloud vs clear sky at this pixel)
  G = cloud brightness 0..1 (the painted lit/shadow shading, normalised)
  B = unused
  A = 1 above the horizon, 0 below -- the bottom half is mountains and forest
      and must never be treated as cloud.

Mask logic: painted clouds are neutral (low saturation, high value) while sky is
saturated blue. Saturation alone is not enough near the horizon where haze is
also grey, so we require both low saturation AND brightness above the local
sky brightness. The source file is not modified.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

SRC = Path(r"C:/Users/B365/Downloads/參考圖概念圖/參考圖文理/SKYBOX/人里skybox.png")
DST = Path(r"D:/神社/shrine/godot/assets/sky/人里_clouds.png")
# Row (0..1) where the painting's horizon sits. Measured by eye on this file:
# mountain ridgeline ~0.49, haze band above it. Everything below is masked.
HORIZON_V = 0.47


def main() -> int:
    im = Image.open(SRC).convert("RGB")
    w, h = im.size
    assert abs(w / h - 2.0) < 0.05, f"expected 2:1 equirect, got {w}x{h}"

    rgb = np.asarray(im).astype(np.float32) / 255.0
    hsv = np.asarray(im.convert("HSV")).astype(np.float32) / 255.0
    sat, val = hsv[..., 1], hsv[..., 2]

    # Per-row sky reference: the 20th percentile of value in each row is the
    # clear blue between clouds. Clouds are what rises above that.
    row_sky = np.percentile(val, 20, axis=1, keepdims=True)
    lift = np.clip((val - row_sky) / 0.30, 0.0, 1.0)

    # Clouds are desaturated; sky is not. Soft threshold so wisps survive.
    desat = np.clip((0.42 - sat) / 0.30, 0.0, 1.0)

    coverage = np.clip(lift * desat, 0.0, 1.0)

    # Painted shading of the cloud itself, normalised so the brightest cloud
    # is 1.0. The shader multiplies this by the time-of-day cloud colour.
    brightness = np.clip(val / max(val.max(), 1e-3), 0.0, 1.0)

    rows = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None]
    # Fade coverage out over the 6% of height above the horizon so the layer
    # ends softly instead of with a hard cut at the ridge.
    above = np.clip((HORIZON_V - rows) / 0.06, 0.0, 1.0)
    alpha = np.broadcast_to(above, (h, w))
    coverage = coverage * alpha

    out = np.zeros((h, w, 4), dtype=np.float32)
    out[..., 0] = coverage
    out[..., 1] = brightness
    out[..., 3] = alpha
    DST.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray((out * 255).round().astype(np.uint8), "RGBA").save(DST)

    cov_above = coverage[rows[:, 0] < HORIZON_V]
    print(f"[clouds] {w}x{h} -> {DST}")
    print(f"[clouds] 天空區平均雲量 {cov_above.mean():.2f}，"
          f"雲像素比例 {(cov_above > 0.5).mean() * 100:.1f}%")
    return 0


if __name__ == "__main__":
    sys.exit(main())
