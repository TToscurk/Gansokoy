"""P13 W4B：黒の出どころの切り分け（exp 撮影の解析）。
  uv run --no-project --with pillow --with numpy python tools/p13/analyze_w4b_black.py <exp_dir> [out.txt]
各視点で ROI＝「試作と r8 が違う画素」（base と r8 の差 > 24/765）。ROI の中で、変種ごとに暗部（輝度 < 0.06／0.10／0.15）の割合と平均輝度を出す。
暗部割合が base より大きく下がる変種＝その要素が黒の主因。
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

d = Path(sys.argv[1])
out_path = Path(sys.argv[2]) if len(sys.argv) > 2 else None
VIEWS = ["up_s43", "up_s61", "cl_treads_s40", "cl_land2"]
VARS = ["r8", "base", "no_decals", "r0", "bed_up", "no_vcol", "no_shadow", "no_selfshadow", "all_off"]
LABEL = {"r8": "r8（現行・Before）", "base": "試作（base＝その時点の最新）", "no_decals": "貼り物なし（苔・落葉・目地）", "r0": "面取りなし（V 溝なし）", "bed_up": "土の床を石の高さへ（溝が浅い）",
         "no_vcol": "頂点色の暗化なし", "no_shadow": "太陽の影なし（樹冠の影も消える）", "no_selfshadow": "階段自身の投影なし（樹冠の影は残る）", "all_off": "貼り物＋V 溝＋床＋頂点色 すべてなし"}


def load(p):
    return np.asarray(Image.open(p).convert("RGB")).astype(np.float32) / 255.0


def luma(im):
    return 0.2126 * im[..., 0] + 0.7152 * im[..., 1] + 0.0722 * im[..., 2]


def dark_lines(L, sigma=5.0, thr=0.08):
    """周囲より thr 以上暗い細い線の画素＝目地・影の線（面積の暗部ではなく『線の黒さ』を測る）"""
    img = Image.fromarray(np.clip(L * 255.0, 0, 255).astype(np.uint8))
    bl = np.asarray(img.filter(ImageFilter.GaussianBlur(sigma))).astype(np.float32) / 255.0
    return (L - bl) < -thr


lines = []
for v in VIEWS:
    base = load(d / f"exp_base__{v}.png")
    r8 = load(d / f"exp_r8__{v}.png")
    roi = (np.abs(base - r8).sum(axis=2) * 3.0 > 24.0 / 255.0 * 3.0 * 3.0)   # 差 > 24/765 相当
    # ↑ 255 スケールでの和が 24 を超える画素
    roi = (np.abs(base - r8).sum(axis=2) * 255.0 > 24.0)
    n = int(roi.sum())
    lines.append(f"## {v}　ROI（試作と r8 が違う画素）{n} 画素＝画面の {100.0 * n / roi.size:.1f} %")
    lines.append(f"{'変種':34s} {'平均輝度':>8s} {'<0.06':>8s} {'<0.10':>8s} {'<0.15':>8s} {'暗い細線':>8s}   base 比（暗い細線）")
    ref10 = None
    refdl = None
    for name in VARS:
        p = d / f"exp_{name}__{v}.png"
        if not p.exists():
            continue
        im = load(p)
        Lfull = luma(im)
        L = Lfull[roi]
        dl = 100.0 * float(dark_lines(Lfull)[roi].mean())
        f06 = 100.0 * float((L < 0.06).mean())
        f10 = 100.0 * float((L < 0.10).mean())
        f15 = 100.0 * float((L < 0.15).mean())
        if name == "base":
            ref10 = f10
            refdl = dl
        rel = "" if (refdl is None or name == "r8") else f"{dl - refdl:+6.1f} pt"
        lines.append(f"{LABEL[name]:34s} {float(L.mean()):8.3f} {f06:7.1f}% {f10:7.1f}% {f15:7.1f}% {dl:7.1f}%   {rel}")
    lines.append("")
txt = "\n".join(lines)
print(txt)
if out_path:
    out_path.write_text(txt, encoding="utf-8")
