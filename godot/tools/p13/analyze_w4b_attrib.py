"""P13 W4B：黒の出どころの歸因（exp 撮影の 'base'〔通常光照〕と 'diag'〔面の種類ごとの純色・無照明〕を同じ鏡位で逐像素に対位）。
  uv run --no-project --with pillow --with numpy python tools/p13/analyze_w4b_attrib.py <exp_dir> [out.txt]
ROI＝試作と r8 が違う画素〔＝試作が描いている所〕。ROI の中で『通常光照で暗い』画素〔輝度 < 0.10、または周囲より 0.08 以上暗い細線〕が、
診斷圖でどの面に属するかを数える：頂面〔白〕／面取り〔緑〕／壁上半〔赤〕／壁下半〔青〕／縫の土填料〔黄〕／底〔桃〕／その他〔端のぼかし・他の物〕。
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

d = Path(sys.argv[1])
out_path = Path(sys.argv[2]) if len(sys.argv) > 2 else None
VIEWS = sys.argv[3].split(",") if len(sys.argv) > 3 else ["up_s43", "up_s61", "cl_treads_s40", "cl_land2"]
CLS = ["頂面", "面取り", "壁上半", "壁下半", "縫の土(黄)", "底", "その他"]


def load(p):
    return np.asarray(Image.open(p).convert("RGB")).astype(np.float32) / 255.0


def luma(im):
    return 0.2126 * im[..., 0] + 0.7152 * im[..., 1] + 0.0722 * im[..., 2]


def classify(im):
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    cls = np.full(r.shape, 6, np.int8)
    hi, lo = 0.55, 0.40
    white = (r > hi) & (g > hi) & (b > hi)
    green = (g > hi) & (r < lo) & (b < lo)
    red = (r > hi) & (g < lo) & (b < lo)
    blue = (b > hi) & (r < lo) & (g < lo)
    yellow = (r > hi) & (g > hi) & (b < lo)
    mag = (r > hi) & (b > hi) & (g < lo)
    cls[white] = 0
    cls[green] = 1
    cls[red] = 2
    cls[blue] = 3
    cls[yellow] = 4
    cls[mag] = 5
    return cls


def dark_lines(L, sigma=5.0, thr=0.08):
    img = Image.fromarray(np.clip(L * 255.0, 0, 255).astype(np.uint8))
    bl = np.asarray(img.filter(ImageFilter.GaussianBlur(sigma))).astype(np.float32) / 255.0
    return (L - bl) < -thr


lines = []
for v in VIEWS:
    base = load(d / f"exp_base__{v}.png")
    r8 = load(d / f"exp_r8__{v}.png")
    dg = load(d / f"exp_diag__{v}.png")
    roi = (np.abs(base - r8).sum(axis=2) * 255.0 > 24.0)
    cls = classify(dg)
    L = luma(base)
    dark_abs = (L < 0.10)
    dark_ln = dark_lines(L)
    n_roi = int(roi.sum())
    lines.append(f"## {v}　ROI {n_roi} 画素（試作と r8 が違う所）")
    lines.append(f"{'面の種類':12s} {'面積':>8s} {'面積比':>7s} | {'暗い(<0.10)':>11s} {'占有率':>7s} {'その面の中で暗い割合':>18s} | {'暗い細線':>8s} {'占有率':>7s}")
    tot_d = max(int((dark_abs & roi).sum()), 1)
    tot_l = max(int((dark_ln & roi).sum()), 1)
    for ci, cname in enumerate(CLS):
        m = roi & (cls == ci)
        a = int(m.sum())
        da = int((m & dark_abs).sum())
        dl = int((m & dark_ln).sum())
        lines.append(f"{cname:12s} {a:8d} {100.0 * a / max(n_roi, 1):6.1f}% | {da:11d} {100.0 * da / tot_d:6.1f}% {100.0 * da / max(a, 1):17.1f}% | {dl:8d} {100.0 * dl / tot_l:6.1f}%")
    lines.append("")
txt = "\n".join(lines)
print(txt)
if out_path:
    out_path.write_text(txt, encoding="utf-8")
