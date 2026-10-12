"""P13 Wave 4：Before(r8)／After(w4) の撮影（scratch）→ docs/art_review/village_v2_p13/wave4/{shots,compare} へ整理する。
  uv run --no-project --with pillow python tools/p13/make_compare_w4.py <scratch_dir_r8> <scratch_dir_w4>
原寸は JPEG(q90) に変換して保存、比較画像は 縦に Before／After を積む（各 1280×720、ラベル付き）。
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

r8_dir = Path(sys.argv[1])
w4_dir = Path(sys.argv[2])
out = Path(__file__).resolve().parents[3] / "docs" / "art_review" / "village_v2_p13" / "wave4"
for sub in ("shots/before", "shots/after", "compare"):
    (out / sub).mkdir(parents=True, exist_ok=True)

NAMES = {
    "up_s47": "A1 玩家視点・上り s=47（第 1 flight）",
    "up_s52": "A2 玩家視点・上り s=52（第 1 踊り場の直上〜第 2 flight）",
    "up_s56": "A3 玩家視点・上り s=56",
    "up_s61": "A4 玩家視点・上り s=61（第 2 踊り場の直下）",
    "up_s66": "A5 玩家視点・上り s=66（試作区間の外＝r8 のまま）",
    "walk_down_s64": "B  玩家視点・下り歩行 s=64（動的相機 pitch バイアス −0.341・腕長 8.5 m）",
    "high_a": "C  高視角（参道全体・村側から）",
    "high_b": "C' 高視角（横から）",
    "cl_wallR_s60": "D1 近接・右の石垣の外面（s=60）",
    "cl_wallL_s46": "D2 近接・左の笠石（s=46）",
    "cl_treads_s40": "D3 近接・最下段の踏面（s=40）",
    "cl_land2": "D4 近接・第 2 踊り場（上から）",
    "cl_toe_R_s56": "D5 近接・石垣の根元の土の裾（s=56）",
}

try:
    font = ImageFont.truetype("C:/Windows/Fonts/YuGothB.ttc", 26)
except Exception:
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/msgothic.ttc", 26)
    except Exception:
        font = ImageFont.load_default()

done = 0
for key, label in NAMES.items():
    a = r8_dir / f"{key}.png"
    b = w4_dir / f"{key}.png"
    if not (a.exists() and b.exists()):
        print("skip", key)
        continue
    ia = Image.open(a).convert("RGB")
    ib = Image.open(b).convert("RGB")
    ia.save(out / "shots/before" / f"{key}.jpg", quality=90)
    ib.save(out / "shots/after" / f"{key}.jpg", quality=90)
    W, H = 1280, 720
    ca = ia.resize((W, H), Image.LANCZOS)
    cb = ib.resize((W, H), Image.LANCZOS)
    canvas = Image.new("RGB", (W, H * 2 + 8), (20, 20, 20))
    canvas.paste(ca, (0, 0))
    canvas.paste(cb, (0, H + 8))
    d = ImageDraw.Draw(canvas)
    for (txt, y) in ((f"BEFORE（r8 現行）  {label}", 8), (f"AFTER（W4 試作）  {label}", H + 16)):
        d.rectangle((6, y - 2, 6 + len(txt) * 27, y + 34), fill=(0, 0, 0))
        d.text((10, y), txt, fill=(255, 255, 255), font=font)
    canvas.save(out / "compare" / f"{key}_before_after.jpg", quality=90)
    done += 1
print("done", done)
