"""P13 W9 Phase 8：村落全域の注記地図（俯瞰の資料図。審圖の證據ではない）。
uv run --quiet --with pillow python map8.py <out.png>
資料：layout_v2.json（道路・水・地區）、gen/greybox.json（建物 footprint）、inventory.json（overlay 所屬）、views.json（調查視點）。
"""
import json
import math
import sys

from PIL import Image, ImageDraw, ImageFont

G = "D:/神社/shrine/godot/"
SC = "C:/Users/B365/AppData/Local/hermes/cache/scratch/p8/"
L = json.load(open(G + "maps/village_v2/layout_v2.json", encoding="utf-8"))
GB = json.load(open(G + "maps/village_v2/gen/greybox.json", encoding="utf-8"))["buildings"]
INV = json.load(open(SC + "inventory.json", encoding="utf-8"))
VIEWS = json.load(open(SC + "views.json", encoding="utf-8"))
X0, X1, Z0, Z1, K = 60.0, 560.0, -280.0, 225.0, 3.0
W, H = int((X1 - X0) * K), int((Z1 - Z0) * K)
LEG_W = 560
im = Image.new("RGB", (W + LEG_W, H), (238, 235, 224))
dr = ImageDraw.Draw(im, "RGBA")
F = lambda s: ImageFont.truetype("C:/Windows/Fonts/msjh.ttc", s)  # noqa: E731
f14, f18, f22, f28, f40 = F(14), F(18), F(22), F(28), F(40)


def P(x, z):
    return ((x - X0) * K, (z - Z0) * K)


def poly(pts, fill=None, outline=None, width=1):
    dr.polygon([P(*p) for p in pts], fill=fill, outline=outline, width=width)


def line(pts, col, w):
    dr.line([P(*p) for p in pts], fill=col, width=max(1, int(w)), joint="curve")


# 地區
DCOL = {"Market": (230, 196, 150, 70), "MixedCommercial": (170, 175, 210, 70), "ResidentialWest": (175, 200, 150, 70), "ResidentialNE": (175, 200, 150, 70),
        "MansionEstate": (225, 205, 160, 90), "SouthGate": (215, 190, 150, 70), "Farmland": (170, 205, 130, 80)}
for k, d in L["districts"].items():
    pl = d.get("poly")
    if isinstance(pl, list) and len(pl) >= 3:
        poly([tuple(p) for p in pl], fill=DCOL.get(k, (200, 200, 200, 60)))
# 水
w = L["water"]
line([tuple(p) for p in w["MainRiver"]["pts"]], (110, 160, 205), 2 * 11 * K)
line([tuple(p) for p in w["Canal"]["pts"]], (110, 160, 205), 2 * w["Canal"]["half_w"] * K)
for s in w["Streams"]:
    line([tuple(p) for p in s["pts"]], (120, 170, 210), 2 * s["half_w"] * K)
# 道路
for r in L["roads"] + L["lanes"]:
    col = (196, 178, 140) if r.get("class") in ("main", "secondary") else (205, 190, 158)
    line([tuple(p) for p in r["pts"]], col, 2 * r["half_w"] * K)
# 建物
ov = {b["name"]: b["overlay"] for b in INV["buildings"]}
REVIEW = {"B_P_MKT_019", "B_P_MKT_021", "B_P_MKT_022", "B_P_MKT_003", "B_P_MKT_017", "B_P_MKT_018"}
for b in GB:
    fp = [tuple(p) for p in b["footprint"]]
    if b["id"] in REVIEW:
        fill = (232, 150, 60)
    elif ov.get(b["id"], "") == "ArchW9R2P13":
        fill = (110, 160, 95)
    elif b.get("kind") == "machiya":
        fill = (150, 145, 140)
    else:
        fill = (165, 135, 105)
    poly(fp, fill=fill, outline=(70, 70, 70))
# 地標
for lm in L["landmarks"]:
    x, z = lm["at"]
    if lm["id"] == "LANDMARK_HILLFOOT_TEMPLE":
        poly([(x - 9, z - 6), (x + 9, z - 6), (x + 9, z + 6), (x - 9, z + 6)], fill=(210, 40, 40, 150), outline=(150, 0, 0), width=3)
        for t in range(-9, 10, 3):
            dr.line([P(x + t, z - 6), P(min(x + 9, x + t + 12), z + 6)], fill=(150, 0, 0), width=1)
    else:
        a, b2 = P(x, z)
        dr.rectangle([a - 5, b2 - 5, a + 5, b2 + 5], fill=(120, 80, 40))
        dr.text((a + 7, b2 - 9), lm["label"].split("（")[0], fill=(90, 50, 20), font=f14)
# 佔位：B7／F7、任務錨點的圓柱
for wf in w["Waterfalls"]:
    a, b2 = P(*wf["at"])
    dr.ellipse([a - 9, b2 - 9, a + 9, b2 + 9], outline=(210, 0, 0), width=4)
    dr.text((a + 11, b2 - 10), wf["name"][-2:] + " 佔位圓柱", fill=(180, 0, 0), font=f14)
for q in L["quest_anchors"]:
    a, b2 = P(*q["at"])
    dr.polygon([(a, b2 - 9), (a - 7, b2 + 5), (a + 7, b2 + 5)], fill=(220, 30, 30), outline=(90, 0, 0))
# portal
for pt in L["portals"]:
    a, b2 = P(*pt["at"])
    dr.ellipse([a - 7, b2 - 7, a + 7, b2 + 7], fill=(60, 60, 200), outline=(20, 20, 90))
    dr.text((a + 9, b2 + 2), pt["label"], fill=(30, 30, 140), font=f14)
# 調查視點（正常 TPS 52）
for v in VIEWS:
    nm, x, z, tx, tz = v[0], v[1], v[2], v[3], v[4]
    d = math.hypot(tx - x, tz - z) or 1
    ex, ez = x + (tx - x) / d * 9, z + (tz - z) / d * 9
    dr.line([P(x, z), P(ex, ez)], fill=(30, 30, 30), width=2)
    a, b2 = P(x, z)
    dr.ellipse([a - 3, b2 - 3, a + 3, b2 + 3], fill=(30, 30, 30))
    dr.text((a + 4, b2 + 2), nm, fill=(40, 40, 40), font=f14)
# 本批區域
for pts, lab in (([(364, -54), (385, -54), (385, -9), (364, -9)], "A8"), ([(420, -252), (502, -252), (502, -176), (420, -176)], "B8")):
    poly(pts, outline=(0, 120, 200), width=4)
    a, b2 = P(*pts[0])
    dr.text((a + 4, b2 - 30), f"本批 {lab}", fill=(0, 90, 170), font=f22)
# 前五名
TOP = [(2, 211, -180), (3, 376, -32), (4, 456, -214), (5, 242, 47)]
for n, x, z in TOP:
    a, b2 = P(x, z)
    dr.ellipse([a - 20, b2 - 20, a + 20, b2 + 20], fill=(255, 255, 255, 220), outline=(200, 0, 0), width=4)
    dr.text((a - 8, b2 - 18), str(n), fill=(200, 0, 0), font=f28)
# 延後項目
DEF = [("D1", 225, 140), ("D2", 186, 80), ("D3", 440, 40), ("D4", 334, -45), ("D5", 196, 38)]
for nm, x, z in DEF:
    a, b2 = P(x, z)
    dr.rectangle([a - 16, b2 - 12, a + 16, b2 + 12], fill=(255, 255, 255, 210), outline=(110, 110, 110), width=2)
    dr.text((a - 13, b2 - 11), nm, fill=(80, 80, 80), font=f18)
# 方位・比例尺
a, b2 = W - 70, 80
dr.polygon([(a, b2 - 40), (a - 14, b2), (a + 14, b2)], fill=(30, 30, 30))
dr.text((a - 8, b2 + 2), "北", fill=(30, 30, 30), font=f22)
x0, y0 = 30, H - 40
dr.line([(x0, y0), (x0 + 100 * K, y0)], fill=(30, 30, 30), width=4)
dr.text((x0, y0 - 28), "100 m", fill=(30, 30, 30), font=f18)
# 圖例
lx = W + 20
y = 20
dr.text((lx, y), "人間之里 V2：村落完成度 注記地圖", fill=(20, 20, 20), font=f28)
y += 44
dr.text((lx, y), "P13 W9 Phase 8・2026-10-16・俯瞰資料圖（診斷用，非審圖證據）", fill=(60, 60, 60), font=f14)
y += 34
LEG = [((150, 145, 140), "町家 Kit（W9 未改建）"), ((110, 160, 95), "W9 改建（已核准・ArchW9R2P13）"), ((232, 150, 60), "W9 改建（ART_REVIEW：Phase 6／7）"),
       ((165, 135, 105), "納屋・土藏（Hero）"), ((210, 40, 40), "灰盒（丘腳社寺 18×12×9 m BoxMesh）"), ((220, 30, 30), "任務錨點圓柱（正式流程可見）"),
       ((60, 60, 200), "portal（獸道・稗田邸・香霖堂）")]
for col, t in LEG:
    dr.rectangle([lx, y + 2, lx + 22, y + 20], fill=col, outline=(60, 60, 60))
    dr.text((lx + 30, y), t, fill=(30, 30, 30), font=f18)
    y += 28
dr.ellipse([lx + 2, y + 2, lx + 20, y + 20], outline=(210, 0, 0), width=4)
dr.text((lx + 30, y), "B7／F7 跌水佔位圓柱（登記 #9・不改）", fill=(30, 30, 30), font=f18)
y += 28
dr.line([(lx, y + 11), (lx + 22, y + 11)], fill=(30, 30, 30), width=2)
dr.text((lx + 30, y), "正常 TPS 調查視點 52（名稱＝S_<名>）", fill=(30, 30, 30), font=f18)
y += 40
dr.text((lx, y), "改善機會 前五名", fill=(200, 0, 0), font=f22)
y += 32
for t in ["① 正式流程露出除錯層：浮空文字 39、區域輪廓線 7、", "    任務錨點圓柱 8（全村・需授權：main.gd 或生成器）",
          "② 丘腳社寺灰盒（需 TASK E 方向裁定）", "③ 稗田邸西側參道（本批 A8）", "④ 東北聚落・香霖堂口（本批 B8）",
          "⑤ 主街×南橫街路口・火見櫓前（需 P10／P9 範圍裁定）"]:
    dr.text((lx, y), t, fill=(40, 40, 40), font=f18)
    y += 26
y += 14
dr.text((lx, y), "延後項目（摘要）", fill=(90, 90, 90), font=f22)
y += 32
for t in ["D1 入口道路兩側（P9 封存林＋獸道過渡）", "D2 南巷內側空地（可見度低）", "D3 田埂路肩（P8 封存田・本即開闊）",
          "D4 水渠護岸石的重複感（封存層）", "D5 寺子屋南側（P9 R4-3 校庭・封存）", "其他：B7／F7（#9）、Kit 町家重複（建築批次）"]:
    dr.text((lx, y), t, fill=(70, 70, 70), font=f18)
    y += 26
im.save(sys.argv[1])
print(sys.argv[1], im.size)
