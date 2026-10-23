"""hf_blender_place.py — 丘腳林地（TASK E FINAL）：社寺取消後の原境內に自然林を配置（街區管線 HF）。Blender 側。

隔離した背景 Blender で走らせる（使用者の GUI Blender・Blender MCP 9876 には触れない）：

    D:/Blender/blender-5.2.1-windows-x64/blender.exe -b --factory-startup --python godot/tools/p13/w9/e2/hf_blender_place.py

前提：work/district/HF/{context.json,context.glb,assets.json,assets.glb}（district_context.gd --district=HF が書いた参考資料；社寺 Hero 撤去後に取り直す）。
出力：godot/data/district/HF.json（街區 manifest・Godot 世界座標・source of truth）＋ work/district/HF/HF.blend（作業コピー）。
林の範囲・道路からの離隔・小空地は godot/data/district/HF_design.json（verify_hf_precinct.gd と共通）。
決定的：random.Random(SEED)。同じ context・設計なら同じ manifest。E2 版（参道・踏石・前庭）は git 履歴（b9000b7）。

方針（使用者 2026-10-18 TASK E FINAL）：
  · 社寺は取消。参道・踏石・前庭・鳥居・燈籠など社寺に関わるものは一切置かない（石は林床の景石だけ）。
  · 高さの違う樹（大樹 11–18 m／若木 5–7 m）を群れで不規則に。均等植えにしない・林中に小空地を残す。
  · 下層（笹・羊歯・低木）は疎ら。丘腳街と周りの建物は保つ（道路から樹幹 ≥ 4.2 m）。
  · 新しい形・材質は作らない：district assets.json に載る登録資産（veg_kit／garden_kit）のみ。
"""
import json
import math
import os
import random
import sys

import bpy

REPO = os.environ.get("HF_REPO", r"D:/神社/shrine").replace("\\", "/")
SEED = 20261018
TOOLS = REPO + "/godot/tools/district/district_blender.py"
DESIGN = REPO + "/godot/data/district/HF_design.json"

ns = {}
with open(TOOLS, encoding="utf-8") as f:
    exec(compile(f.read(), TOOLS, "exec"), ns)
D = ns["District"]("HF")
D.load_all()
DS = json.load(open(DESIGN, encoding="utf-8"))
rng = random.Random(SEED)

WOOD = [tuple(p) for p in DS["woodland"]]
CLR = DS["road_clear"]
GLADES = [((g[0][0], g[0][1]), g[1]) for g in DS["glades"]]
STREET = [(204.0, -148.2), (228.0, -149.1), (250.0, -150.0), (300.0, -130.0)]
STREET_HW = 3.0


def pip(poly, x, z):
    inside = False
    n = len(poly)
    for i in range(n):
        x0, z0 = poly[i]
        x1, z1 = poly[(i + 1) % n]
        if (z0 > z) != (z1 > z) and x < (x1 - x0) * (z - z0) / (z1 - z0) + x0:
            inside = not inside
    return inside


def seg_dist(px, pz, a, b):
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    L2 = dx * dx + dz * dz
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / L2))
    return math.hypot(px - (ax + t * dx), pz - (az + t * dz))


def road_d(x, z):
    """丘腳街の路肩（中心線−半幅）までの距離"""
    return min(seg_dist(x, z, STREET[i], STREET[i + 1]) for i in range(len(STREET) - 1)) - STREET_HW


placed = []        # (x, z, r, vid)


def free_of_others(x, z, r, gap):
    for (px, pz, pr, _v) in placed:
        if math.hypot(px - x, pz - z) < r + pr + gap:
            return False
    return True


def tier(asset):
    k = D.assets[asset]["kind"]
    if k == "tree":
        return "tree"
    if asset.startswith("young") or asset == "niwamatsu_a":
        return "young"
    return "under"


def footprint_r(asset, s):
    t = tier(asset)
    if t == "tree":
        return 0.6 * s + 1.6
    if t == "young":
        return 0.3 * s + 0.9
    k = D.assets[asset]["kind"]
    if k in ("veg", "shrub"):
        return 0.4 * s + 0.4
    d = D.assets[asset]["foot"]
    return 0.5 * max(abs(d[3] - d[0]), abs(d[5] - d[2])) * s


def zone_ok(asset, x, z):
    if not pip(WOOD, x, z):
        return False
    t = tier(asset)
    if road_d(x, z) < CLR[t]:
        return False
    if t != "under":
        for (c, r) in GLADES:
            if math.hypot(x - c[0], z - c[1]) < r:
                return False
    return True


def spot_ok(asset, x, z, yaw, s):
    soft = D.assets[asset]["kind"] in ("veg", "tree", "bamboo", "shrub")
    fp = D.foot(asset, x, z, yaw, s, s, soft)
    return all(D.reason(px, pz, soft) in ("ok", "outside") for (px, pz) in fp + [(x, z)])


# 同じ群れの大樹は幹 3 m 前後まで寄せる（株立ち・寄り合い）。群れ同士の間は空く → 最近傍距離がばらつく（等間隔植えにしない）
GAP = {"tree": -1.3, "young": -0.5, "under": -0.35}
n_fail = 0


def try_place(asset, cx, cz, rad, cluster, who, why, scale=(0.9, 1.15), tries=120):
    global n_fail
    t = tier(asset)
    for _ in range(tries):
        ang = rng.uniform(0, math.tau)
        rr = rad * math.sqrt(rng.random())
        x, z = cx + rr * math.cos(ang), cz + rr * math.sin(ang)
        s = rng.uniform(*scale)
        r = footprint_r(asset, s)
        if not zone_ok(asset, x, z):
            continue
        yaw = rng.uniform(-math.pi, math.pi)
        soft = D.assets[asset]["kind"] in ("veg", "tree", "bamboo", "shrub")
        # 石（kit）は植物と違って重ねない：district.check／verify M7 と同じく離す
        if not spot_ok(asset, x, z, yaw, s) or not free_of_others(x, z, r, GAP[t] if soft else 0.3):
            continue
        ob = D.place(asset, x, z, yaw=yaw, s=s, cluster=cluster, who=who, why=why, kind="reuse",
                     flags=(("nov",) if soft else ()))
        placed.append((x, z, r, ob.name))
        return ob
    n_fail += 1
    print("[hf_wood] 置けなかった：%s @(%.1f,%.1f) r=%.1f %s" % (asset, cx, cz, rad, cluster))
    return None


# (cluster, (cx, cz), radius, [(asset, n, scale)], who, why)
# 群れの大きさ・樹種・密度をわざと揃えない。原社寺の中心 (228,−170) は大樹の群れで埋め、整地面の矩形を樹冠と幹で崩す。
CLUSTERS = [
    ("core_big", (227.5, -169.0), 5.0, [("keyaki_a", 1, (0.85, 1.0)), ("shii_a", 1, (0.9, 1.1)), ("konara_a", 1, (0.8, 1.0)), ("konara_b", 1, (0.9, 1.05))],
     "原社寺の跡（整地面の中央）", "樹高の違う大樹 4 本の寄り合いで跡地の平らさと中軸を隠す"),
    ("core_s", (231.0, -162.8), 2.6, [("akamatsu_a", 1, (0.75, 0.9)), ("young_sugi", 1, (0.85, 1.0))],
     "旧石段の足元あたり", "赤松と若杉で旧参道の抜けを塞ぐ"),
    ("core_w", (222.8, -172.5), 2.4, [("young_broad_a", 1, (0.85, 1.0)), ("konara_b", 1, (0.8, 0.95))],
     "跡地の西半分", "低めの小楢と若木"),
    ("core_under", (227.0, -169.5), 6.5, [("fern_a", 4, (0.85, 1.15)), ("sasa_a", 3, (0.85, 1.1)), ("shrub_a", 2, (0.85, 1.05))],
     "大樹の根元・跡地の林床", "羊歯・笹・低木を疎らな塊で（均一な敷き詰めにしない）"),
    ("pad_n", (227.0, -177.0), 3.6, [("konara_b", 1, (0.85, 1.0)), ("young_broad_b", 1, (0.85, 1.0)), ("shii_a", 1, (0.75, 0.9))],
     "跡地の北半分（旧社殿の位置）", "社殿の跡に中高木の小群れ：跡地を林で埋める"),
    ("pad_e", (234.5, -174.0), 2.6, [("young_sugi", 1, (0.85, 1.0)), ("enoki_a", 1, (0.8, 0.95))],
     "跡地の東", "若杉と榎"),
    ("floor_c", (229.5, -172.0), 4.0, [("fern_a", 3, (0.85, 1.1)), ("sasa_a", 2, (0.9, 1.1)), ("shrub_a", 1, (0.85, 1.0))],
     "跡地中央の林床", "平らな跡地に下草の塊をもう一つ（敷き詰めない）"),
    ("floor_w", (222.0, -176.5), 3.0, [("sasa_a", 2, (0.9, 1.15)), ("fern_a", 2, (0.85, 1.1))],
     "跡地西北の林床", "笹の塊"),
    ("floor_sw", (225.8, -160.6), 1.8, [("fern_a", 2, (0.85, 1.05)), ("sasa_a", 1, (0.85, 1.0))],
     "跡地南西の林床（既存地被の礫斑の上）", "礫斑を下草でぼかす"),
    ("floor_s", (226.0, -160.5), 3.0, [("fern_a", 2, (0.85, 1.1)), ("sasa_a", 1, (0.9, 1.1)), ("shrub_a", 1, (0.85, 1.0))],
     "跡地の南（街寄り）の林床", "裸土の整地面を下草で崩す"),
    ("floor_n", (230.5, -177.0), 3.0, [("sasa_a", 2, (0.9, 1.1)), ("fern_a", 1, (0.9, 1.1))],
     "跡地の北の林床", "同上・量を変える"),
    ("nw_pine", (216.5, -180.5), 4.0, [("akamatsu_a", 2, (0.8, 1.0)), ("konara_b", 1, (0.9, 1.1)), ("young_sugi", 1, (0.9, 1.1))],
     "西北の肩", "赤松と小楢：水溝側の明るい林縁"),
    ("nw_under", (216.0, -178.0), 4.5, [("sasa_a", 2, (0.9, 1.15)), ("fern_a", 1, (0.9, 1.1))],
     "西北の林床", "笹の小さな塊"),
    ("n_back", (229.5, -183.5), 4.2, [("shii_a", 1, (0.8, 0.95)), ("konara_b", 1, (0.85, 1.05)), ("young_broad_b", 1, (0.9, 1.1))],
     "北の丘腳（既存林との継ぎ目）", "既存の丘の林へ高さを繋ぐ"),
    ("ne_mix", (239.0, -177.5), 4.0, [("konara_a", 1, (0.85, 1.0)), ("enoki_a", 1, (0.85, 1.0)), ("young_sugi", 1, (0.9, 1.05))],
     "東北の斜面の立ち上がり", "榎と小楢の混交"),
    ("ne_under", (239.0, -173.0), 4.0, [("shrub_a", 1, (0.9, 1.1)), ("fern_a", 2, (0.9, 1.1))],
     "東の林床", "疎らな下草"),
    ("e_edge", (241.5, -163.5), 3.0, [("konara_b", 1, (0.8, 0.95)), ("young_broad_a", 1, (0.9, 1.1)), ("tsutsuji_a", 1, (0.95, 1.1))],
     "東南の林縁（街から 10 m 余り）", "低めの小楢と若木で林縁を作る"),
    ("w_young", (215.0, -166.0), 3.6, [("young_broad_a", 1, (0.9, 1.1)), ("kuromatsu_a", 1, (0.75, 0.9)), ("shrub_a", 1, (0.9, 1.1))],
     "西縁（水溝の肩）", "若木と低い黒松：西の縁を軽く"),
    ("s_edge_w", (220.0, -160.5), 3.0, [("young_sugi", 1, (0.85, 1.0)), ("fern_a", 1, (0.9, 1.1)), ("sasa_a", 1, (0.9, 1.05))],
     "林の南縁（西寄り）", "街からの見えがかり：若木 1 本と下草だけ（大樹を街に寄せない）"),
    ("s_edge_e", (235.5, -159.5), 2.6, [("shrub_a", 1, (0.9, 1.1)), ("tsutsuji_a", 1, (0.95, 1.1))],
     "林の南縁（東寄り）", "西と量を変える（左右対称にしない）"),
    ("mid_e", (234.0, -168.5), 3.0, [("akamatsu_a", 1, (0.75, 0.9)), ("young_broad_b", 1, (0.85, 1.0))],
     "中東（小空地の東）", "空地の縁に赤松 1・若木 1"),
    ("glade", (220.6, -165.2), 2.0, [("fern_a", 1, (0.8, 1.0))],
     "小空地（西）", "空地は下草だけ"),
    ("stones", (223.0, -176.0), 6.0, [("gk_kei_low", 2, (0.9, 1.15)), ("gk_kei_mid", 1, (0.85, 1.0))],
     "林床の景石", "根元に半ば埋まった自然石（参道石・踏石ではない）"),
]
for (cl, (cx, cz), rad, members, who, why) in CLUSTERS:
    for (asset, n, sc) in members:
        for _ in range(n):
            try_place(asset, cx, cz, rad, cl, who, why, scale=sc)

cnt = {}
for (_x, _z, _r, vid) in placed:
    st = D._state(bpy.data.objects[vid])
    cnt[tier(st["asset"])] = cnt.get(tier(st["asset"]), 0) + 1
print("[hf_wood] 置いた数 %d %s・置けなかった %d" % (len(D.objects()), cnt, n_fail))
issues = D.check(verbose=True)
for (vid, why) in issues:
    ob = bpy.data.objects.get(vid)
    st = D._state(ob) if ob else None
    print("   ->", vid, st["asset"] if st else "?", "(%.2f, %.2f)" % (st["x"], st["z"]) if st else "", why)
D.export_manifest()
try:
    print("[hf_wood] blend ->", D.save_blend())
except Exception as e:
    print("[hf_wood] save_blend skipped:", e)
sys.stdout.flush()
