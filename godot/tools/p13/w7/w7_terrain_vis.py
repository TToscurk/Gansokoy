"""P13 W7 診断：w7_dump_terrain.gd の JSON から FarmlandTerrain の頂点重みを三角形補間で画像にする（GPU の補間と同じ）。
  uv run --quiet --with pillow --with numpy python w7_terrain_vis.py <dump.json> <out.png> [now|orig] [x0 z0 x1 z1] [ch=r,g,b,a,fx,fy,wx,wy]
各チャンネルを灰階で 1 パネル、並べて 1 枚（1 m = 8 px）。頂点を小さい点で、2 m 格子線を薄く重ねる。
"""
import json
import sys

import numpy as np
from PIL import Image, ImageDraw

CH = {"r": 3, "g": 4, "b": 5, "a": 6, "fx": 7, "fy": 8, "wx": 9, "wy": 10}


def raster(verts, tris, ch, x0, z0, x1, z1, ppm):
    W = int((x1 - x0) * ppm)
    H = int((z1 - z0) * ppm)
    img = np.full((H, W), np.nan, dtype=np.float32)
    ci = CH[ch]
    for t in tris:
        p = verts[t]
        px = (p[:, 0] - x0) * ppm
        pz = (p[:, 2] - z0) * ppm
        xmin = max(int(np.floor(px.min())), 0)
        xmax = min(int(np.ceil(px.max())), W - 1)
        zmin = max(int(np.floor(pz.min())), 0)
        zmax = min(int(np.ceil(pz.max())), H - 1)
        if xmin > xmax or zmin > zmax:
            continue
        den = (pz[1] - pz[2]) * (px[0] - px[2]) + (px[2] - px[1]) * (pz[0] - pz[2])
        if abs(den) < 1e-9:
            continue
        gx, gz = np.meshgrid(np.arange(xmin, xmax + 1) + 0.5, np.arange(zmin, zmax + 1) + 0.5)
        l0 = ((pz[1] - pz[2]) * (gx - px[2]) + (px[2] - px[1]) * (gz - pz[2])) / den
        l1 = ((pz[2] - pz[0]) * (gx - px[2]) + (px[0] - px[2]) * (gz - pz[2])) / den
        l2 = 1.0 - l0 - l1
        m = (l0 >= -1e-6) & (l1 >= -1e-6) & (l2 >= -1e-6)
        val = l0 * p[0, ci] + l1 * p[1, ci] + l2 * p[2, ci]
        sub = img[zmin:zmax + 1, xmin:xmax + 1]
        sub[m] = val[m]
    return img


def main():
    dump = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    which = sys.argv[3] if len(sys.argv) > 3 else "now"
    box = [float(v) for v in sys.argv[4:8]] if len(sys.argv) >= 8 else None
    chans = sys.argv[8].split(",") if len(sys.argv) > 8 else ["r", "g", "b", "a"]
    d = dump[which]
    verts = np.array(d["verts"], dtype=np.float64)
    tris = np.array(d["tris"], dtype=np.int64)
    if box is None:
        box = [verts[:, 0].min(), verts[:, 2].min(), verts[:, 0].max(), verts[:, 2].max()]
    x0, z0, x1, z1 = box
    ppm = 8
    panels = []
    for ch in chans:
        img = raster(verts, tris, ch, x0, z0, x1, z1, ppm)
        g = np.nan_to_num(img, nan=0.0)
        rgb = np.stack([g, g, g], axis=-1)
        rgb = (np.clip(rgb, 0, 1) * 255).astype(np.uint8)
        rgb[np.isnan(img)] = (60, 0, 60)
        im = Image.fromarray(rgb)
        dr = ImageDraw.Draw(im)
        # 2 m 格子線（薄く）
        for gx in np.arange(np.ceil(x0 / 2) * 2, x1, 2.0):
            dr.line([((gx - x0) * ppm, 0), ((gx - x0) * ppm, im.height)], fill=(0, 90, 160), width=1)
        for gz in np.arange(np.ceil(z0 / 2) * 2, z1, 2.0):
            dr.line([(0, (gz - z0) * ppm), (im.width, (gz - z0) * ppm)], fill=(0, 90, 160), width=1)
        dr.text((4, 4), f"{which} ch={ch}  x[{x0:.0f},{x1:.0f}] z[{z0:.0f},{z1:.0f}]", fill=(255, 220, 0))
        panels.append(im)
    cols = 2 if len(panels) > 1 else 1
    rows = (len(panels) + cols - 1) // cols
    sheet = Image.new("RGB", (panels[0].width * cols + 4 * (cols - 1), panels[0].height * rows + 4 * (rows - 1)), (255, 0, 255))
    for i, p in enumerate(panels):
        sheet.paste(p, ((i % cols) * (p.width + 4), (i // cols) * (p.height + 4)))
    sheet.save(out)
    print("saved", out, sheet.size)


main()
