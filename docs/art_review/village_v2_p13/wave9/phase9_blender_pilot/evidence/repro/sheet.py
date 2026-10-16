"""BEFORE／P8／PILOT の同鏡位比較シート＋PILOT の ID パスから DistrictB8P の画面占有率。
python sheet.py <shots_dir> <out.jpg> <coverage.json>"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

D = sys.argv[1]
OUT = sys.argv[2]
COV = sys.argv[3]
views = ["V1_lane_in", "V2_gap_kido", "V3_back_yard", "V4_row_back", "V5_row_lane", "E1_high"]
label = {"V1_lane_in": "V1 巷の進場（NELane 西から）", "V2_gap_kido": "V2 002/003 宅間の入口（木戸）", "V3_back_yard": "V3 裏の共有地 → 004 の菜園",
         "V4_row_back": "V4 住宅列の裏を沿って", "V5_row_lane": "V5 巷の東端から住宅列を振り返る", "E1_high": "E1 高位診断（自由相機・審美の根拠にしない）"}
cols = ["BEFORE", "P8", "PILOT"]
ctitle = {"BEFORE": "BEFORE（現行 village_v2）", "P8": "P8（DistrictB8＝前回の GDScript 配置）", "PILOT": "PILOT（DistrictB8P＝Blender 構成）"}
tw, th = 640, 360
font = ImageFont.truetype("C:/Windows/Fonts/msgothic.ttc", 18)
fs = ImageFont.truetype("C:/Windows/Fonts/msgothic.ttc", 15)

# ID パス：DistrictB8P の画素の割合
tab = json.load(open(os.path.join(D, "PILOT_idtable.json"), encoding="utf-8"))
bits = tab["bits"]
sp = 8 if bits == 5 else 4
mask = (1 << bits) - 1
own = {int(k) for k, p in tab["map"].items() if p.startswith("DistrictB8P")}
cov = {}
for v in views:
    p = os.path.join(D, "PILOT_%s_id.png" % v)
    if not os.path.exists(p):
        continue
    im = Image.open(p).convert("RGB")
    px = im.getdata()
    n = 0
    hit = 0
    for r, g, b in px:
        n += 1
        k = ((r // sp) << (2 * bits)) | ((g // sp) << bits) | (b // sp)
        if k in own:
            hit += 1
    cov[v] = round(100.0 * hit / n, 2)
json.dump({"pilot_screen_share_pct": cov, "method": "ID パス（w6_base.id_begin）：各画素の節点 id → DistrictB8P 配下の割合"}, open(COV, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("coverage", cov)

W = 30 + len(cols) * (tw + 10)
H = 40 + len(views) * (th + 34)
sheet = Image.new("RGB", (W, H), (24, 24, 24))
d = ImageDraw.Draw(sheet)
for ci, c in enumerate(cols):
    d.text((30 + ci * (tw + 10), 10), ctitle[c], fill=(255, 255, 255), font=font)
for ri, v in enumerate(views):
    y = 40 + ri * (th + 34)
    t = label[v] + ("　PILOT 画面占有 %.1f %%" % cov[v] if v in cov else "")
    d.text((30, y), t, fill=(255, 230, 150), font=fs)
    for ci, c in enumerate(cols):
        p = os.path.join(D, "%s_%s.png" % (c, v))
        if os.path.exists(p):
            im = Image.open(p).convert("RGB").resize((tw, th), Image.LANCZOS)
            sheet.paste(im, (30 + ci * (tw + 10), y + 22))
sheet.save(OUT, quality=88)
print("saved", OUT, sheet.size)
