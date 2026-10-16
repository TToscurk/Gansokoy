"""B8P 平面図（PIL・作業用）：理由表・建物 footprint／戸口・道路・腕の検査線・manifest の item 足跡。
python plan_map.py <context.json> <assets.json> <out.png> [manifest.json ...]   （座標は Godot 世界 x, z。上＝-z＝北）"""
import json, math, sys
from PIL import Image, ImageDraw, ImageFont

ctx = json.load(open(sys.argv[1], encoding="utf-8"))
assets = json.load(open(sys.argv[2], encoding="utf-8"))["assets"]
out = sys.argv[3]
mans = sys.argv[4:]
R = ctx["rect"]
PAD = 3.0
X0, Z0, X1, Z1 = R[0] - PAD, R[1] - PAD, R[0] + R[2] + PAD, R[1] + R[3] + PAD
S = 26  # px / m
W, H = int((X1 - X0) * S), int((Z1 - Z0) * S)
img = Image.new("RGB", (W + 60, H + 40), (255, 255, 255))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("C:/Windows/Fonts/msgothic.ttc", 11)
    fontb = ImageFont.truetype("C:/Windows/Fonts/msgothic.ttc", 14)
except Exception:
    font = fontb = ImageFont.load_default()


def P(x, z):
    return (40 + (x - X0) * S, 20 + (z - Z0) * S)


COL = {"ok": (236, 244, 228), "building": (170, 170, 170), "road": (214, 190, 150), "road_pad": (232, 214, 186), "frontage": (246, 232, 150),
       "backdoor": (250, 180, 120), "r4": (200, 170, 230), "hero": (240, 140, 140), "sealed": (230, 120, 200), "env": (180, 220, 240), "trunk": (120, 90, 60)}
Rz = ctx["reasons"]
leg = Rz["legend"]
for j in range(Rz["nz"]):
    for i in range(Rz["nx"]):
        x = Rz["origin"][0] + i * Rz["step"]
        z = Rz["origin"][1] + j * Rz["step"]
        k = leg[Rz["ground"][j * Rz["nx"] + i]]
        c = COL.get(k, (255, 0, 255))
        a, b = P(x - 0.5, z - 0.5), P(x + 0.5, z + 0.5)
        d.rectangle([a, b], fill=c)
for gx in range(int(math.floor(X0)), int(math.ceil(X1)) + 1):
    col = (150, 150, 150) if gx % 5 == 0 else (225, 225, 225)
    d.line([P(gx, Z0), P(gx, Z1)], fill=col, width=1)
    if gx % 5 == 0:
        d.text((P(gx, Z0)[0] - 8, 4), str(gx), fill=(0, 0, 0), font=font)
for gz in range(int(math.floor(Z0)), int(math.ceil(Z1)) + 1):
    col = (150, 150, 150) if gz % 5 == 0 else (225, 225, 225)
    d.line([P(X0, gz), P(X1, gz)], fill=col, width=1)
    if gz % 5 == 0:
        d.text((2, P(X0, gz)[1] - 6), str(gz), fill=(0, 0, 0), font=font)
for r in ctx["roads"]:
    pts = [P(x, z) for x, z in r["pts"]]
    d.line(pts, fill=(150, 110, 60), width=2)
for b in ctx["buildings"]:
    fp = [P(x, z) for x, z in b["footprint"]]
    d.polygon(fp, outline=(40, 40, 40))
    dp = [P(x, z) for x, z in b["door"]]
    d.polygon(dp, outline=(0, 0, 255), fill=(150, 170, 255))
    cx, cz = b["o"]
    d.text(P(cx - 1.5, cz), b["name"].replace("B_P_", ""), fill=(0, 0, 0), font=fontb)
for ln, pts in ctx.get("arm_lanes", {}).items():
    q = [P(x, z) for x, z in pts]
    for k in range(len(q) - 1):
        d.line([q[k], q[k + 1]], fill=(255, 0, 0), width=1)
    d.text(q[0], ln, fill=(255, 0, 0), font=font)


def foot(e):
    a = assets[e["asset"]]
    yaw = e["yaw"]
    sx, sy, sz = e["scale"]
    x, _, z = e["pos"]
    ex = (math.cos(yaw), -math.sin(yaw))
    ez = (math.sin(yaw), math.cos(yaw))
    if "soft" in e.get("flags", []) and a["kind"] in ("veg",):
        r = (0.3 if e["asset"].startswith("young") else 0.35) * max(sx, sz)
        x0, x1, z0, z1 = -r, r, -r, r
    else:
        f = a["foot"]
        x0, x1 = sorted((f[0] * sx, f[3] * sx))
        z0, z1 = f[2] * sz, f[5] * sz
    return [(x + ex[0] * u + ez[0] * w, z + ex[1] * u + ez[1] * w) for (u, w) in ((x0, z0), (x1, z0), (x1, z1), (x0, z1))]


colors = [(20, 120, 20), (200, 0, 0), (0, 0, 180)]
for mi, mp in enumerate(mans):
    M = json.load(open(mp, encoding="utf-8"))
    for e in M["items"]:
        new = not e.get("src")
        c = (200, 0, 0) if new else (20, 110, 20)
        poly = [P(x, z) for x, z in foot(e)]
        d.polygon(poly, outline=c)
        x, _, z = e["pos"]
        d.ellipse([P(x - 0.08, z - 0.08), P(x + 0.08, z + 0.08)], fill=c)
        d.text((P(x, z)[0] + 3, P(x, z)[1] - 5), e["vid"].split("_")[-1] + ":" + e["asset"].replace("w9_", "").replace("_a", ""), fill=c, font=font)
img.save(out)
print("saved", out, img.size)
