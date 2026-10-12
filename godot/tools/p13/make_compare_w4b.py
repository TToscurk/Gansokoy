"""P13 Wave 4B：最終 Before(r8)／After(W4B r13) の三組を docs/art_review/village_v2_p13/wave4b/{shots,compare} へ整理する。
  uv run --no-project --with pillow python tools/p13/make_compare_w4b.py <scratch_dir_r8> <scratch_dir_w4>
原寸は JPEG(q90) で保存。比較画像は縦に Before／After を積む（各 1280×720、ラベル付き）。
組：
  S1 最下段の石階と石縫（TPS ＋ 近接）
  S2 第二平台と両側の石垣（TPS ＋ 近接 3）
  S3 通常 TPS 視点の参道全体（上り 2・下り 1・高視角 1）
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

r8_dir = Path(sys.argv[1])
w4_dir = Path(sys.argv[2])
out = Path(__file__).resolve().parents[3] / "docs" / "art_review" / "village_v2_p13" / "wave4b"
for sub in ("shots/before", "shots/after", "compare"):
    (out / sub).mkdir(parents=True, exist_ok=True)

SETS = [
    ("S1-1", "up_s43", "S1 最下段の石階と石縫・TPS 上り s=43"),
    ("S1-2", "cl_treads_s40", "S1 最下段の石階と石縫・近接（s=40、地面から 2.4 m）"),
    ("S2-1", "up_s61", "S2 第二平台と両側の石垣・TPS 上り s=61（第 2 踊り場の直下）"),
    ("S2-2", "cl_land2", "S2 第二平台・近接（上から）"),
    ("S2-3", "cl_wallR_s60", "S2 右の石垣・近接（s=60）"),
    ("S2-4", "cl_wallL_s46", "S2 左の笠石・近接（s=46）"),
    ("S3-1", "up_s47", "S3 通常 TPS・上り s=47"),
    ("S3-2", "up_s56", "S3 通常 TPS・上り s=56"),
    ("S3-3", "walk_down_s56", "S3 通常 TPS・下り歩行 s=56"),
    ("S3-4", "high_a", "S3 高視角（参道全体・村側から）"),
]

try:
    font = ImageFont.truetype("C:/Windows/Fonts/YuGothB.ttc", 26)
except Exception:
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msgothic.ttc", 26)
    except Exception:
        font = ImageFont.load_default()

done = 0
for tag, key, label in SETS:
    a = r8_dir / f"{key}.png"
    b = w4_dir / f"{key}.png"
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
    for txt, y in ((f"BEFORE（r8 現行）  {label}", 8), (f"AFTER（W4B r13）  {label}", H + 16)):
        d.rectangle((6, y - 2, 6 + len(txt) * 27, y + 34), fill=(0, 0, 0))
        d.text((12, y), txt, font=font, fill=(255, 255, 255))
    canvas.save(out / "compare" / f"{tag}_{key}_before_after.jpg", quality=90)
    done += 1
print("done", done)
