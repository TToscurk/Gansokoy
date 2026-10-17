"""hf_blender_place.py — 丘腳社寺 E2：境內植栽・踏石の配置（街區管線 HF）。Blender 側。

隔離した背景 Blender で走らせる（使用者の GUI Blender・Blender MCP 9876 には触れない）：

    D:/Blender/blender-5.2.1-windows-x64/blender.exe -b --factory-startup --python godot/tools/p13/w9/e2/hf_blender_place.py

前提：work/district/HF/{context.json,context.glb,assets.json,assets.glb}（district_context.gd --district=HF が書いた参考資料）。
出力：godot/data/district/HF.json（街區 manifest・Godot 世界座標・source of truth）＋ work/district/HF/HF.blend（作業コピー）。
設計の幾何（前庭・参道・兩側の踏み跡）は godot/data/district/HF_design.json（Godot 側の地面権重・抑制・verify と共通）。
決定的：random.Random(SEED)。同じ context・設計なら同じ manifest。

置き方の方針（使用者 2026-10-17 E2）：
  · 前庭（整地面）の中は開ける。植栽は境界（外縁）に集める。参道と石段の正面 ±(幅+1.8 m) は植栽禁止。
  · 参道＝踏石（gk_tobi）を不規則に。石段前に敷石（gk_nobe）を 3 枚だけ。前庭の小石は疎らに。
  · 新しい形は作らない：既存 kit／veg_kit の資産のみ（district assets.json に載る登録資産）。
"""
import json
import math
import os
import random
import sys

import bpy

REPO = os.environ.get("HF_REPO", r"D:/神社/shrine").replace("\\", "/")
SEED = 20261017
TOOLS = REPO + "/godot/tools/district/district_blender.py"
DESIGN = REPO + "/godot/data/district/HF_design.json"

ns = {}
with open(TOOLS, encoding="utf-8") as f:
    exec(compile(f.read(), TOOLS, "exec"), ns)
D = ns["District"]("HF")
D.load_all()          # 地面（高さ表・置けない所の色）＋ context.glb（参考）＋ 資産ライブラリ（assets.glb）
DS = json.load(open(DESIGN, encoding="utf-8"))
rng = random.Random(SEED)

COURT = [tuple(p) for p in DS["court"]]
APP = [tuple(p) for p in DS["approach"]["pts"]]
APP_HW = DS["approach"]["half_w"]
CLEAR = DS["approach"]["clear_margin"]
STAIR = tuple(DS["stair_foot"])


# ─────────────────────────── 幾何 ───────────────────────────
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
    return math.hypot(px - (ax + t * dx), pz - (az + t * dz)), t


def poly_dist(poly, x, z):
    """多角形の輪郭までの距離（内外問わず）"""
    return min(seg_dist(x, z, poly[i], poly[(i + 1) % len(poly)])[0] for i in range(len(poly)))


def sd_court(x, z):
    d = poly_dist(COURT, x, z)
    return d if pip(COURT, x, z) else -d


def app_info(x, z):
    """参道中心線までの距離・弧長 s・その s での半幅"""
    best = (1e9, 0.0)
    acc = 0.0
    for i in range(len(APP) - 1):
        d, t = seg_dist(x, z, APP[i], APP[i + 1])
        L = math.hypot(APP[i + 1][0] - APP[i][0], APP[i + 1][1] - APP[i][1])
        if d < best[0]:
            best = (d, acc + t * L)
        acc += L
    s = best[1]
    hw = APP_HW[-1][1]
    for i in range(len(APP_HW) - 1):
        if APP_HW[i][0] <= s <= APP_HW[i + 1][0]:
            u = (s - APP_HW[i][0]) / (APP_HW[i + 1][0] - APP_HW[i][0])
            hw = APP_HW[i][1] * (1 - u) + APP_HW[i + 1][1] * u
            break
    return best[0], s, hw


def app_point(s):
    acc = 0.0
    for i in range(len(APP) - 1):
        L = math.hypot(APP[i + 1][0] - APP[i][0], APP[i + 1][1] - APP[i][1])
        if acc + L >= s:
            t = (s - acc) / L
            return (APP[i][0] + t * (APP[i + 1][0] - APP[i][0]), APP[i][1] + t * (APP[i + 1][1] - APP[i][1])), (
                (APP[i + 1][0] - APP[i][0]) / L, (APP[i + 1][1] - APP[i][1]) / L)
        acc += L
    return APP[-1], (0.0, 1.0)


APP_LEN = sum(math.hypot(APP[i + 1][0] - APP[i][0], APP[i + 1][1] - APP[i][1]) for i in range(len(APP) - 1))
placed = []        # (x, z, r, vid)


def free_of_others(x, z, r, gap=0.25):
    for (px, pz, pr, _v) in placed:
        if math.hypot(px - x, pz - z) < r + pr + gap:
            return False
    return True


def footprint_r(asset, s):
    """間隔判定用の半径（円）。植物は W9.foot(soft) に合わせた足元＋余裕、木は幹＋樹間、kit は足跡の半分"""
    a = D.assets[asset]
    k = a["kind"]
    if k == "veg":
        return (0.3 if asset.startswith("young") else 0.35) * s + (0.9 if asset.startswith("young") else 0.55)
    if k == "shrub":
        return 0.45 * s + 0.35
    if k == "tree":
        return 0.6 * s + 1.6
    d = a["foot"]
    return 0.5 * max(abs(d[3] - d[0]), abs(d[5] - d[2])) * s


def spot_ok(asset, x, z, yaw, s):
    """district.check と同じ足元（四隅）＋中心がすべて ok か"""
    soft = D.assets[asset]["kind"] in ("veg", "tree", "bamboo", "shrub")
    fp = D.foot(asset, x, z, yaw, s, s, soft)
    if not all(D.reason(px, pz, soft) in ("ok", "outside") for (px, pz) in fp + [(x, z)]):
        return False
    if asset.startswith("gk_tobi") or asset == "gk_kei_flat":
        # 平たい石（外に出るのは 4〜7 cm）は、足元の地形高低差が小さい所にだけ置く：
        # 坂では W9.ground_y（足元の最小）に座るので上手側が埋まり、『半透明の貼り紙』に見える（TASK E2 r2 の実測）
        hs = [D.height(px, pz) for (px, pz) in fp + [(x, z)]]
        hs = [h for h in hs if h == h]
        if hs and (max(hs) - min(hs)) > 0.03:
            return False
    return True


def plant_zone_ok(x, z, tree=False):
    """植栽・大石の禁止域：前庭（+1.2 m）・参道廊下・石段の正面"""
    if sd_court(x, z) > -1.2:
        return False
    d, s, hw = app_info(x, z)
    if d < hw + CLEAR:
        return False
    if math.hypot(x - STAIR[0], z - STAIR[1]) < 7.5:
        return False
    return True


def try_place(asset, cx, cz, rad, cluster, who, why, scale=(0.9, 1.15), tries=80, tree=False, kind="reuse", zone_rule=True, mode=None, flags=()):
    for _ in range(tries):
        ang = rng.uniform(0, math.tau)
        rr = rad * math.sqrt(rng.random())
        x, z = cx + rr * math.cos(ang), cz + rr * math.sin(ang)
        s = rng.uniform(*scale)
        r = footprint_r(asset, s)
        if zone_rule and not plant_zone_ok(x, z, tree):
            continue
        soft = D.assets[asset]["kind"] in ("veg", "tree", "bamboo", "shrub")
        yaw0 = rng.uniform(-math.pi, math.pi)
        ok = spot_ok(asset, x, z, yaw0, s)                   # district.check と同じ足元（四隅）＋平たい石は足元の高低差も見る
        # 植物は樹冠が重なって群れになる（間隔を詰める）。石・kit は離す
        gap = -0.45 if soft else 0.25
        if not ok or not free_of_others(x, z, r, gap):
            continue
        yaw = yaw0
        fl = tuple(flags) + (("nov",) if soft else ())       # 樹冠の重なりは群れの自然な姿（W9 の宅間の庭木と同じ nov）
        ob = D.place(asset, x, z, yaw=yaw, s=s, cluster=cluster, who=who, why=why, kind=kind, mode=mode, flags=fl)
        placed.append((x, z, r, ob.name))
        return ob
    print("[hf_place] 置けなかった：%s @(%.1f,%.1f) r=%.1f %s" % (asset, cx, cz, rad, cluster))
    return None


# ─────────────────────────── 植栽（境界へ集める） ───────────────────────────
# (cluster, (cx, cz), radius, [(asset, n, scale範囲)], who, why)
CLUSTERS = [
    ("SW_sasa", (216.0, -160.4), 2.9, [("sasa_a", 3, (0.95, 1.2)), ("shrub_a", 2, (0.9, 1.15)), ("fern_a", 2, (0.9, 1.15)), ("gk_kei_low", 1, (0.9, 1.1))],
     "境内西南の窪み（地形が 0.5–0.7 m 凹む所）", "窪みを笹・低木・景石で受ける。前庭の縁を植物で締める"),
    ("SW_shrub", (219.6, -155.2), 1.6, [("tsutsuji_a", 1, (0.95, 1.1)), ("fern_a", 2, (0.9, 1.1))],
     "参道西側の路肩", "丘腳街から見て参道の左を低い躑躅・羊歯で縁取る（笹の暗い塊を街路際に置かない・正面は開ける）"),
    ("W_edge", (215.4, -170.0), 3.0, [("young_broad_a", 1, (0.9, 1.1)), ("shrub_a", 2, (0.9, 1.15)), ("tsutsuji_a", 2, (0.95, 1.2)), ("fern_a", 1, (0.9, 1.1))],
     "境内西縁（水溝へ落ちる肩）", "西の縁は低木と若い広葉樹。水溝側へ自然に落とす"),
    ("W_pine", (214.2, -176.2), 2.0, [("kuromatsu_a", 1, (0.9, 1.0)), ("sasa_a", 2, (0.9, 1.1))],
     "境内西北の一本松", "村の小さな社に一本の松。西側から社殿を囲う（前庭の上には掛からない）"),
    ("N_back1", (223.6, -183.4), 3.2, [("young_sugi", 2, (0.9, 1.1)), ("shrub_a", 2, (0.9, 1.1)), ("fern_a", 2, (0.9, 1.1))],
     "社殿背後（北）の杜", "社殿の背を若い杉と下草で受け、奥の森へつなぐ"),
    ("N_back2", (233.4, -184.4), 3.2, [("young_sugi", 1, (0.9, 1.05)), ("young_broad_b", 1, (0.9, 1.0)), ("sasa_a", 2, (0.9, 1.1)), ("fern_a", 2, (0.9, 1.1))],
     "社殿背後（北東）", "同上。杉と広葉樹を混ぜて単調にしない"),
    ("E_edge", (240.0, -170.8), 2.6, [("shrub_a", 2, (0.9, 1.15)), ("sasa_a", 2, (0.9, 1.15)), ("fern_a", 2, (0.9, 1.1)), ("tsutsuji_a", 1, (0.95, 1.1))],
     "境内東縁（丘腳の登り口）", "東は斜面の立ち上がり。既存の林縁の笹・低木につなぐ"),
    ("E_tree", (239.4, -165.4), 2.2, [("young_broad_a", 1, (1.0, 1.2)), ("tsutsuji_a", 2, (0.95, 1.15)), ("gk_kei_low", 1, (0.95, 1.1))],
     "境内東南の木", "若い広葉樹一本と低い景石。東南の角を締める（幹の碰撞は置かない：東の通行帯の SpringArm を縮めないため）"),
    ("SE_shrub", (236.2, -155.4), 1.7, [("shrub_a", 1, (0.9, 1.1)), ("fern_a", 1, (0.9, 1.1))],
     "参道東側の路肩", "西側と同じ種類だが量を変え、左右対称にしない"),
]
for (cl, (cx, cz), rad, members, who, why) in CLUSTERS:
    for (asset, n, sc) in members:
        for _ in range(n):
            try_place(asset, cx, cz, rad, cl, who, why, scale=sc, tree=D.assets[asset]["kind"] == "tree")

# ─────────────────────────── 参道の踏石（不規則） ───────────────────────────
# 石段正面は社殿の hero 占有（石段脚から約 0.8 m ＋検査の 0.6 m）に入れない → 石段前の平石は z ≥ −162.9 まで
# 先に平石（自然石 2 枚・不揃い。gk_nobe の規則的な矩形平石は『タイル』に見えるので使わない）。踏石は後から、重ならない所へ。
for (x, z, yaw, a, sc) in [(227.55, -162.3, -0.6, "gk_kei_flat", 0.95), (229.6, -161.7, 1.1, "gk_tobi_c", 1.1), (226.2, -161.6, 0.3, "gk_tobi_a", 1.0)]:
    r = footprint_r(a, sc)
    if D.reason(x, z, False) in ("ok", "outside"):
        ob = D.place(a, x, z, yaw=yaw, s=sc, cluster="approach_stones", mode="ground", who="石段の前の平石", why="石段の足元だけ自然石を 3 つ・不揃い（石畳の広場にしない）", kind="reuse")
        placed.append((x, z, r, ob.name))
    else:
        print("[hf_place] 平石 NG", a, x, z, D.reason(x, z, False))

TOBI = ["gk_tobi_a", "gk_tobi_b", "gk_tobi_c", "gk_tobi_d"]
s = 0.9
n_tobi = 0
while s < APP_LEN - 3.2:
    step = rng.uniform(0.6, 1.1)
    (px, pz), (tx, tz) = app_point(s)
    nxv, nzv = -tz, tx
    # 時々だけ置く（連続した飛び石の列にしない）
    if rng.random() < 0.2:
        s += step
        continue
    a = rng.choice(TOBI)
    sc = rng.uniform(0.95, 1.35)
    r = footprint_r(a, sc)
    for _try in range(6):
        off = rng.choice([-1.0, 1.0]) * rng.uniform(0.1, 1.25)
        x, z = px + nxv * off, pz + nzv * off
        yaw = rng.uniform(-math.pi, math.pi)
        if spot_ok(a, x, z, yaw, sc) and free_of_others(x, z, r, 0.12):
            ob = D.place(a, x, z, yaw=yaw, s=sc, cluster="approach_stones", mode="ground",
                         who="参拝者の足が作った踏み跡", why="参道に不規則に置いた踏石（連続した石畳にしない）", kind="reuse")
            placed.append((x, z, r, ob.name))
            n_tobi += 1
            break
    s += step

# 前庭の小石（疎ら）：石段正面の廊下は空け、前庭の両翼と後院に少しだけ。建物脇の細い帯（x<221.4／x>234.6）は hero 占有なので置かない
SMALL = ["gk_tobi_d", "gk_tobi_c", "gk_tobi_a", "gk_kei_flat"]
for (cx, cz, rad) in [(222.4, -162.0, 1.3), (223.9, -160.0, 1.0), (233.9, -162.2, 1.3), (232.2, -160.0, 1.1), (225.0, -158.9, 1.0), (231.3, -158.7, 1.0), (225.0, -178.8, 1.5), (231.5, -179.0, 1.5), (228.0, -179.6, 1.2)]:
    a = rng.choice(SMALL)
    sc = rng.uniform(0.65, 1.1)
    r = footprint_r(a, sc)
    for _t in range(60):
        ang = rng.uniform(0, math.tau)
        rr = rad * math.sqrt(rng.random())
        x, z = cx + rr * math.cos(ang), cz + rr * math.sin(ang)
        yaw = rng.uniform(-math.pi, math.pi)
        if not spot_ok(a, x, z, yaw, sc) or not free_of_others(x, z, r, 0.3):
            continue
        ob = D.place(a, x, z, yaw=yaw, s=sc, cluster="court_stones", mode="ground",
                     who="境内の小石", why="疎らに落ちた小石（均等に散らさない）", kind="reuse")
        placed.append((x, z, r, ob.name))
        break

# 外縁の景石（境界の植栽際）
for (cx, cz, rad, a) in [(218.0, -166.0, 1.2, "gk_kei_low"), (239.4, -176.5, 1.4, "gk_kei_low"), (230.5, -181.2, 1.6, "gk_kei_flat"), (222.0, -179.8, 1.2, "gk_kei_low")]:
    try_place(a, cx, cz, rad, "boundary_stones", "境界の景石", "植栽際に半ば埋まった石（左右対称にしない）", scale=(0.9, 1.15))

print("[hf_place] 置いた数 %d（踏石 %d）" % (len(D.objects()), n_tobi))
issues = D.check(verbose=True)
for (vid, why) in issues:
    ob = bpy.data.objects.get(vid)
    st = D._state(ob) if ob else None
    print("   ->", vid, st["asset"] if st else "?", "(%.2f, %.2f)" % (st["x"], st["z"]) if st else "", why)
D.export_manifest()
try:
    print("[hf_place] blend ->", D.save_blend())
except Exception as e:      # 保存先が無い等
    print("[hf_place] save_blend skipped:", e)
sys.stdout.flush()
