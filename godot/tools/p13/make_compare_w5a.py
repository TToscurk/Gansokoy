"""P13 Wave 5A：Before(W4B)／After(W5A) の三組を docs/art_review/village_v2_p13/wave5a/{shots,compare} へ整理し、数値指標〔差の画素率・輝度・暗部〕を evidence に書く。
  uv run --no-project --with pillow --with numpy python tools/p13/make_compare_w5a.py <scratch_dir>
<scratch_dir> には shot_w4.gd の `w5` 出力（w5_w4b__<view>.png／w5_w5a__<view>.png）。同じ build・同じ時刻・同じ renderer・同じ鏡位。
組：
  S1 石垣側面の近景〔底部と土坡の接合〕：w5_wallR・w5_wallL・w5_baseR
  S2 正常 TPS 上り：up_s53・up_s56・up_s58
  S3 やや高い視点〔新しい貼片・突兀な隆起がないか〕：w5_highR・w5_highL・w5_landR〔平台の端＝壁が山坡に収まる所〕
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

src = Path(sys.argv[1])
out = Path(__file__).resolve().parents[3] / "docs" / "art_review" / "village_v2_p13" / "wave5a"
for sub in ("shots/before", "shots/after", "compare", "evidence"):
    (out / sub).mkdir(parents=True, exist_ok=True)

SETS = [
    ("S1-1", "w5_wallR", "S1 石垣側面の近景・右側（s≈58–62 を外側から）"),
    ("S1-2", "w5_wallL", "S1 石垣側面の近景・左側（s≈58–62 を外側から）"),
    ("S1-3", "w5_baseR", "S1 石垣の根元〔底部と土坡の接合〕・右側"),
    ("S2-1", "up_s53", "S2 正常 TPS 上り・s=53（サンプルは前方）"),
    ("S2-2", "up_s56", "S2 正常 TPS 上り・s=56"),
    ("S2-3", "up_s58", "S2 正常 TPS 上り・s=58（サンプルの入口）"),
    ("S3-1", "w5_highR", "S3 やや高い視点・右側（第二平台の下）"),
    ("S3-2", "w5_highL", "S3 やや高い視点・左側"),
    ("S3-3", "w5_landR", "S3 平台の端〔壁が山坡に収まる所〕を上から"),
]
try:
    font = ImageFont.truetype("C:/Windows/Fonts/YuGothB.ttc", 26)
except Exception:
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msgothic.ttc", 26)
    except Exception:
        font = ImageFont.load_default()


def luma(im):
    return 0.2126 * im[..., 0] + 0.7152 * im[..., 1] + 0.0722 * im[..., 2]


lines = ["# W5A Before(W4B)／After(W5A) の数値指標（同じ build・時刻 10:00・Forward+・同鏡位）",
         "差の画素＝|Before−After| の RGB 和 > 30/765。輝度は 0–1。ROI＝差の画素。", "",
         f"{'視点':10s} {'差の画素':>8s} {'ROI 平均輝度 B→A':>20s} {'暗部<0.06 B→A':>16s} {'暗部<0.10 B→A':>16s}"]
done = 0
for tag, key, label in SETS:
    a = src / f"w5_w4b__{key}.png"
    b = src / f"w5_w5a__{key}.png"
    if not (a.exists() and b.exists()):
        print("skip", tag, key)
        continue
    ia = Image.open(a).convert("RGB")
    ib = Image.open(b).convert("RGB")
    ia.save(out / "shots/before" / f"{tag}_{key}.jpg", quality=90)
    ib.save(out / "shots/after" / f"{tag}_{key}.jpg", quality=90)
    W, H = 1280, 720
    canvas = Image.new("RGB", (W, H * 2 + 8), (20, 20, 20))
    canvas.paste(ia.resize((W, H), Image.LANCZOS), (0, 0))
    canvas.paste(ib.resize((W, H), Image.LANCZOS), (0, H + 8))
    d = ImageDraw.Draw(canvas)
    for txt, y in ((f"BEFORE（W4B・c2f73d2）  {label}", 8), (f"AFTER（W5A r7d）  {label}", H + 16)):
        d.rectangle((6, y - 2, 6 + len(txt) * 27, y + 34), fill=(0, 0, 0))
        d.text((12, y), txt, font=font, fill=(255, 255, 255))
    canvas.save(out / "compare" / f"{tag}_{key}_before_after.jpg", quality=90)
    fa = np.asarray(ia).astype(np.float32) / 255.0
    fb = np.asarray(ib).astype(np.float32) / 255.0
    roi = (np.abs(fa - fb).sum(axis=2) * 255.0) > 30.0
    la, lb = luma(fa)[roi], luma(fb)[roi]
    if roi.sum() > 0:
        lines.append(f"{key:10s} {100.0 * roi.mean():7.2f}% {la.mean():9.3f} → {lb.mean():.3f} {100 * (la < 0.06).mean():7.1f}% → {100 * (lb < 0.06).mean():.1f}% {100 * (la < 0.10).mean():7.1f}% → {100 * (lb < 0.10).mean():.1f}%")
    done += 1
(out / "evidence" / "before_after_metrics.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
print("\n".join(lines))
print("done", done)
