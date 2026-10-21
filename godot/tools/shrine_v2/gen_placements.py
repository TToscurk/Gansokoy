"""博麗神社 r3 擺放規劃（樹、灌木、岩石、石板參道、踏石）。純規劃，不碰 Godot：
    python godot/tools/shrine_v2/gen_placements.py
讀 gen_terrain 的輸出（height.f32 / vista_a.f32）與 layout.py，寫 maps/shrine_v2/gen/placements.json。
build_scene.gd 讀這份 JSON 實例化節點（每個物件一個可單獨選取的節點，不用 MultiMesh）。
樹種只用 assets/village_v2/veg_kit/trees（使用者 2026-10-22：不採用 D:\\資產glb 內的樹）。
"""
from __future__ import annotations

import json
import math
import os
import random
import sys

import numpy as np
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
import layout as L  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GEN = os.path.join(ROOT, "maps", "shrine_v2", "gen")
rng = random.Random(L.SEED + 99)

T = L.TERRAIN
NX = int(round((T["x1"] - T["x0"]) / T["step"])) + 1
NZ = int(round((T["z1"] - T["z0"]) / T["step"])) + 1
H = np.fromfile(os.path.join(GEN, "height.f32"), dtype=np.float32).reshape(NZ, NX).astype(np.float64)
VA = np.fromfile(os.path.join(GEN, "vista_a.f32"), dtype=np.float32)
VN = int(round(math.sqrt(VA.size)))
VA = VA.reshape(VN, VN).astype(np.float64)
VHALF, VSTEP = 260.0, 4.0


def hnear(x, z):
    fx, fz = (x - T["x0"]) / T["step"], (z - T["z0"]) / T["step"]
    i, j = int(math.floor(fx)), int(math.floor(fz))
    if i < 0 or j < 0 or i >= NX - 1 or j >= NZ - 1:
        return None
    tx, tz = fx - i, fz - j
    return float((H[j, i] * (1 - tx) + H[j, i + 1] * tx) * (1 - tz) + (H[j + 1, i] * (1 - tx) + H[j + 1, i + 1] * tx) * tz)


def hfar(x, z):
    fx, fz = (x + VHALF) / VSTEP, (z + VHALF) / VSTEP
    i, j = int(np.clip(math.floor(fx), 0, VN - 2)), int(np.clip(math.floor(fz), 0, VN - 2))
    tx, tz = fx - i, fz - j
    return float((VA[j, i] * (1 - tx) + VA[j, i + 1] * tx) * (1 - tz) + (VA[j + 1, i] * (1 - tx) + VA[j + 1, i + 1] * tx) * tz)


def hat(x, z):
    h = hnear(x, z)
    return h if h is not None else hfar(x, z)


# ── 格網分析：平坦區、離平坦區距離、坡度 ──
flat = np.abs(H - L.Y_C) < 0.04
dist_flat = ndimage.distance_transform_edt(~flat) * T["step"]
gz, gx = np.gradient(H, T["step"], T["step"])
slope_deg = np.degrees(np.arctan(np.hypot(gx, gz)))


def grid(a, x, z):
    i = int(np.clip(round((x - T["x0"]) / T["step"]), 0, NX - 1))
    j = int(np.clip(round((z - T["z0"]) / T["step"]), 0, NZ - 1))
    return float(a[j, i])


def d_flat(x, z):
    if not (T["x0"] < x < T["x1"] and T["z0"] < z < T["z1"]):
        return 99.0
    return grid(dist_flat, x, z)


def slope_at(x, z):
    if not (T["x0"] < x < T["x1"] and T["z0"] < z < T["z1"]):
        return 20.0
    return grid(slope_deg, x, z)


# ── 避讓區 ──
path_pts = L.catmull_rom(L.APPROACH, 0.5)
trail_pts = L.catmull_rom(L.TRAIL, 0.5)


def dist_polyline(x, z, pts):
    d = np.hypot(pts[:, 0] - x, pts[:, 1] - z)
    return float(d.min())


def rect_hit(x, z, fp, margin):
    cx, cz, hx, hz = fp
    return abs(x - cx) < hx + margin and abs(z - cz) < hz + margin


def pond_r(x, z):
    p = L.POND
    th = math.radians(p["rot_deg"])
    dx, dz = x - p["cx"], z - p["cz"]
    u = (dx * math.cos(th) + dz * math.sin(th)) / p["rx"]
    v = (-dx * math.sin(th) + dz * math.cos(th)) / p["rz"]
    return math.hypot(u, v)


def blocked(x, z, tree=True):
    """True=不可放大型植物。"""
    for k, fp in L.FOOTPRINT.items():
        if rect_hit(x, z, fp, 3.2 if tree else 1.2):
            return True
    if pond_r(x, z) < (1.25 if tree else 1.40):
        return True
    # 池塘南岸視線帶：庭院→池畔不放樹與灌木，讓水面一眼可見（審圖：池塘被灌木與花片遮住讀不出來）
    if 3.0 < x < 16.0 and -35.5 < z < -25.0:
        return True
    # 林間步道：兩側不放樹／灌木
    if dist_polyline(x, z, trail_pts[:, :2]) < (3.0 if tree else 2.6):
        return True
    # 中央視線：鳥居→境內→拜殿，寬 11 m 不放樹
    if -26.0 < z < 5.0 and abs(x) < 5.5:
        return True
    # 石階廊與參道
    if z >= 4.0 and z <= L.Z_FOOT + 1.0 and abs(x) < (6.5 if tree else 3.6):
        return True
    if z > L.Z_FOOT - 1.0 and dist_polyline(x, z, path_pts[:, :2]) < (5.2 if tree else 3.0):
        return True
    return False


class Hash:
    def __init__(self, cell=8.0):
        self.c = cell
        self.d = {}

    def near(self, x, z, r):
        i0, i1 = int((x - r) // self.c), int((x + r) // self.c)
        j0, j1 = int((z - r) // self.c), int((z + r) // self.c)
        for i in range(i0, i1 + 1):
            for j in range(j0, j1 + 1):
                for it in self.d.get((i, j), []):
                    yield it

    def add(self, x, z, r):
        self.d.setdefault((int(x // self.c), int(z // self.c)), []).append((x, z, r))

    def ok(self, x, z, r, k):
        for (ox, oz, orad) in self.near(x, z, r + 14.0):
            if math.hypot(x - ox, z - oz) < k * (r + orad):
                return False
        return True


# 樹的原尺寸 (寬=x/z 平均, 高)
SZ = {
    "sakura_somei": (13.6, 9.2), "sakura_yama": (11.3, 14.0), "sakura_shidare": (8.3, 10.9),
    "momiji_a": (7.5, 6.8), "momiji_b": (9.9, 9.8), "momiji_c": (7.8, 7.8),
    "konara_a": (12.7, 15.3), "konara_b": (8.8, 11.3), "keyaki_a": (13.9, 18.8), "keyaki_hero": (21.2, 24.9),
    "shii_a": (15.3, 14.6), "hinoki_a": (7.1, 18.6), "hinoki_b": (9.2, 21.5),
    "sugi_a": (8.1, 25.0), "sugi_b": (9.9, 18.0), "sugi_c": (5.8, 17.9), "sugi_hero": (11.6, 28.4),
    "akamatsu_a": (11.8, 17.3), "akamatsu_b": (10.9, 17.4), "young_sugi": (5.5, 7.9),
    "young_broad_a": (4.6, 6.1), "young_broad_b": (6.1, 5.7), "kusu_hero": (21.9, 21.8),
    "kuromatsu_a": (10.9, 12.8), "enoki_a": (14.5, 13.0),
}

trees: list[dict] = []
hashgrid = Hash(8.0)


def crown_ok(x, z, w):
    """樹冠與建築腳印（含屋簷）的水平間距：樹幹離腳印 ≥ 1.2 + 0.44·冠寬（冠半徑約 0.5·w，留 ≈1.2 m 空隙）。
    2026-10-22 審圖：4 棵冠切進拜殿／倉庫／手水舍屋面 → 改用冠寬相依的距離（原本固定 3.2 m）；再抓到垂枝櫻貼拜殿後角 → 係數 0.36→0.44。"""
    for fp in L.FOOTPRINT.values():
        cx, cz, hx, hz = fp
        dx = max(abs(x - cx) - hx, 0.0)
        dz = max(abs(z - cz) - hz, 0.0)
        if math.hypot(dx, dz) < 1.5 + 0.48 * w:        # PV 以建築 AABB（含屋簷）和冠 AABB 80% 檢查，留比腳印更多的餘裕
            return False
    return True


def add_tree(sp, x, z, s, grp, yaw=None, k=0.7, force=False):
    w = SZ[sp][0] * s
    r = w * 0.5 * 0.85
    if not force and not crown_ok(x, z, w):
        return False
    if not force and not hashgrid.ok(x, z, r, k):
        return False
    hashgrid.add(x, z, r)
    trees.append(dict(id=sp, x=round(x, 3), z=round(z, 3), y=round(hat(x, z), 3),
                      yaw=round(rng.uniform(0, 2 * math.pi) if yaw is None else yaw, 3), s=round(s, 3), g=grp))
    return True


# ── 1) 主角樹（Zone A：1–3 棵具構圖作用的大樹，不遮拜殿正面）──
add_tree("keyaki_hero", 19.5, -10.5, 0.64, "hero", yaw=2.1, force=True)
add_tree("sugi_hero", -18.0, -19.5, 0.52, "hero", yaw=0.7, force=True)
add_tree("momiji_b", -18.6, -8.2, 0.95, "edge", yaw=4.0, force=True)

# ── 2) 櫻花林（後方與側後方）──
GROVE = [("sakura_somei", 0.52), ("sakura_yama", 0.40), ("sakura_shidare", 0.08)]
MIX = [("momiji_a", 0.10), ("momiji_c", 0.05), ("konara_b", 0.45), ("young_broad_b", 0.25), ("shii_a", 0.15)]
tries = 0
n_grove = 0
# 西側山腹（平台外 10–14 m、高出庭院 4–5 m、坡 12–19°）：庭院往西看的櫻花背景。三棵、彼此 ≥9 m，與步道距離 ≥6 m
# （隨機櫻花林在西側太近平台、被步道避讓規則排除，導致兩翼不對稱）。
W_STAND = [("sakura_yama", -31.0, -20.0, 0.95), ("sakura_somei", -33.5, -29.0, 0.82), ("sakura_yama", -31.0, -38.0, 0.92)]

n_shidare = 0
n_sak_near = 0
sak_pos: list = []


def pick_mix():
    r2, acc = rng.random(), 0.0
    for name, w in MIX:
        acc += w
        if r2 < acc:
            return name
    return MIX[0][0]


for _sp, _x, _z, _s in W_STAND:
    if add_tree(_sp, _x, _z, _s, "grove", k=0.74):
        sak_pos.append((_x, _z))
        n_grove += 1
while n_grove < 44 and tries < 9000:
    tries += 1
    x, z = rng.uniform(-27, 29), rng.uniform(-58, -6)
    if d_flat(x, z) > 7.5:
        continue
    if blocked(x, z):
        continue
    # 拜殿前方兩翼才可放（z>-24 時要離中軸 ≥ 13.5）
    if z > -24.0 and abs(x) < 13.5:
        continue
    if z > -9.0:        # 靠鳥居的前段不種大樹，保天空與視野
        continue
    near_pond = pond_r(x, z) < 2.6
    behind_haiden = abs(x) < 9.0 and z < -32.0   # 拜殿背後改種常綠闊葉：櫻花不連成粉白背景牆（2026-10-22 審圖）
    r = rng.random()
    if near_pond and r < 0.30 and n_shidare < 4:
        sp = "sakura_shidare"
        n_shidare += 1
    else:
        acc = 0.0
        sp = GROVE[0][0]
        for name, w in GROVE:
            acc += w
            if r < acc:
                sp = name
                break
    if rng.random() < 0.18 or behind_haiden:
        sp = None
        r2, acc = rng.random(), 0.0
        for name, w in MIX:
            acc += w
            if r2 < acc:
                sp = name
                break
        sp = sp or MIX[0][0]
    # 櫻花彼此至少 7 m（審圖：兩翼櫻花連成橫向粉白帶）→ 太近的改闊葉混種
    if sp.startswith("sakura"):
        # 櫻花成「小林」而非「帶」：彼此 ≥7 m；14 m 內最多再 2 棵；離步道 ≥6.5 m（垂枝／花枝不橫在路上）；庭院東翼（x>18）最多 3 棵
        if (any(math.hypot(x - ax, z - az) < 7.0 for ax, az in sak_pos)
                or sum(1 for ax, az in sak_pos if math.hypot(x - ax, z - az) < 14.0) >= 3
                or dist_polyline(x, z, trail_pts[:, :2]) < 6.5
                or (x > 18.0 and -40.0 < z < -8.0 and sum(1 for ax, az in sak_pos if ax > 18.0 and -40.0 < az < -8.0) >= 3)):
            sp = pick_mix()
    # 拜殿周圍：櫻花離拜殿中心 ≥13.5 m（拜殿腳印半寬 5 m＋冠半徑 ≈5 m 後仍留 3 m 輪廓縫），20 m 內最多 2 棵
    if sp.startswith("sakura"):
        dh = math.hypot(x, z + 28.0)
        if dh < 13.5:
            continue
        if dh < 20.0:
            if n_sak_near >= 2:
                sp = "konara_b" if rng.random() < 0.6 else "shii_a"
            else:
                n_sak_near += 1
    s = (rng.uniform(0.62, 0.84) if sp == "sakura_shidare" else rng.uniform(0.72, 1.0)) if sp.startswith("sakura") else rng.uniform(0.85, 1.25)
    if add_tree(sp, x, z, s, "grove", k=0.74):
        n_grove += 1
        if sp.startswith("sakura"):
            sak_pos.append((x, z))

# ── 3) 外圍森林（Zone C）──
FOREST = [("hinoki_a", .17), ("hinoki_b", .09), ("sugi_a", .13), ("sugi_b", .10), ("sugi_c", .07),
          ("konara_a", .09), ("konara_b", .06), ("momiji_b", .012), ("keyaki_a", .07), ("shii_a", .07),
          ("akamatsu_a", .04), ("akamatsu_b", .04), ("young_sugi", .04), ("young_broad_a", .03)]
tot = sum(w for _, w in FOREST)
n_forest = 0
tries = 0
XMIN, XMAX, ZMIN, ZMAX = T["x0"] + 2, T["x1"] - 2, T["z0"] + 2, T["z1"] - 6
while n_forest < 700 and tries < 160000:
    tries += 1
    x, z = rng.uniform(XMIN, XMAX), rng.uniform(ZMIN, ZMAX)
    d = d_flat(x, z)
    if d < 1.6:
        continue
    if blocked(x, z):
        continue
    if slope_at(x, z) > 44:
        continue
    inplay = L.PLAY["x0"] < x < L.PLAY["x1"] and L.PLAY["z0"] < z < L.PLAY["z1"]
    # 密度：越遠越密；玩家範圍外略疏
    dens = 0.45 + 0.55 * min(1.0, d / 24.0)
    if not inplay:
        dens *= 0.95        # 玩家範圍外也要有林冠：與外圍林冠貼圖接得上（審圖：近景邊緣的褐黃光禿坡）
    # 近景地形外緣 24 m 內密度漸減到 25%：樹不在邊界處「突然截止」（審圖：深色立體森林在整齊邊界終止）
    edge_d = min(x - T["x0"], T["x1"] - x, z - T["z0"], T["z1"] - z)
    dens *= 0.25 + 0.75 * min(1.0, max(0.0, edge_d / 24.0))
    if rng.random() > dens:
        continue
    r = rng.random() * tot
    acc = 0.0
    sp = FOREST[0][0]
    for name, w in FOREST:
        acc += w
        if r < acc:
            sp = name
            break
    # 近庭院的樹壓低：不要在庭院邊壓頂
    if d < 14:
        s = rng.uniform(0.50, 0.72)
    elif d < 30:
        s = rng.uniform(0.7, 1.0)
    else:
        s = rng.uniform(0.85, 1.3)
    if sp in ("young_sugi", "young_broad_a"):
        s = rng.uniform(0.8, 1.3)
    if add_tree(sp, x, z, s, "forest", k=0.52):
        n_forest += 1

# ── 4) 下層植栽（叢）──
UNDER = [("shrub_a", .30, 0.9, 1.5), ("tsutsuji_a", .22, 0.9, 1.4), ("fern_a", .30, 1.0, 1.7), ("sasa_a", .18, 0.9, 1.4)]
under: list[dict] = []
uh = Hash(5.0)
tries = 0
centers = 0
while centers < 120 and tries < 30000:
    tries += 1
    x, z = rng.uniform(-30, 32), rng.uniform(-56, 76)
    d = d_flat(x, z)
    if not (0.5 < d < 9.0 or (rng.random() < 0.3 and d < 20)):
        continue
    if blocked(x, z, tree=False):
        continue
    if slope_at(x, z) > 38:
        continue
    if not uh.ok(x, z, 2.0, 1.0):
        continue
    uh.add(x, z, 2.0)
    centers += 1
    for _ in range(rng.randint(3, 6)):
        a, rr = rng.uniform(0, 2 * math.pi), rng.uniform(0.2, 2.0)
        px, pz = x + math.cos(a) * rr, z + math.sin(a) * rr
        if blocked(px, pz, tree=False) or slope_at(px, pz) > 42:
            continue
        r = rng.random() * sum(w for _, w, _, _ in UNDER)
        acc = 0.0
        for name, w, s0, s1 in UNDER:
            acc += w
            if r < acc:
                under.append(dict(id=name, x=round(px, 3), z=round(pz, 3), y=round(hat(px, pz), 3),
                                  yaw=round(rng.uniform(0, 2 * math.pi), 3), s=round(rng.uniform(s0, s1), 3)))
                break

# ── 5) 岩石 ──
rocks: list[dict] = []
# 5a 石階兩側土坡的擋土岩：沿石階廊，從階面外緣往外找「地形高於階面 ≥0.5 m」處
treads, landings, z_end = L.stair_plan()
bank_z = np.arange(z_end + 1.0, L.Z_FOOT - 1.0, 2.6)
kei = ["kei_low", "kei_flat", "kei_mid", "kei_low"]
for z in bank_z:
    ytop = float(np.interp(z, [t["zc"] for t in treads][::-1], [t["y_top"] for t in treads][::-1]))
    for side in (-1, 1):
        if rng.random() < 0.18:
            continue
        for off in np.arange(2.3, 7.0, 0.2):
            x = side * off
            if hat(x, z) - ytop >= 0.55:
                x = side * (off + rng.uniform(0.2, 0.9))
                kind = rng.choice(kei)
                rocks.append(dict(src=kind, x=round(x, 3), z=round(z + rng.uniform(-0.7, 0.7), 3),
                                  yaw=round(rng.uniform(0, 6.28), 3), s=round(rng.uniform(0.95, 1.6), 3), sink=0.3, g="bank"))
                break
# 5b 平台邊緣的岩層
rim: list[tuple] = []
tries = 0
rh = Hash(10.0)
while len(rim) < 16 and tries < 8000:
    tries += 1
    x, z = rng.uniform(-30, 32), rng.uniform(-56, 6)
    d = d_flat(x, z)
    if not (1.2 < d < 4.5):
        continue
    if not (18 < slope_at(x, z) < 42):
        continue
    if blocked(x, z, tree=False):
        continue
    if not rh.ok(x, z, 2.0, 2.2):
        continue
    rh.add(x, z, 2.0)
    rim.append((x, z))
    rocks.append(dict(src=rng.choice(["rock_medium_1", "rock_medium_2", "rock_medium_3"]), x=round(x, 3), z=round(z, 3),
                      yaw=round(rng.uniform(0, 6.28), 3), s=round(rng.uniform(0.38, 0.62), 3), sink=0.5, g="rim"))
# 5c 池岸石
for k in range(14):
    a = rng.uniform(0, 2 * math.pi)
    rr = rng.uniform(1.04, 1.16)
    p = L.POND
    th = math.radians(p["rot_deg"])
    ux, uz = rr * p["rx"] * math.cos(a), rr * p["rz"] * math.sin(a)
    x = p["cx"] + ux * math.cos(th) - uz * math.sin(th)
    z = p["cz"] + ux * math.sin(th) + uz * math.cos(th)
    rocks.append(dict(src=rng.choice(["kei_flat", "kei_low", "kei_low", "kei_mid"]), x=round(x, 3), z=round(z, 3),
                      yaw=round(rng.uniform(0, 6.28), 3), s=round(rng.uniform(0.7, 1.25), 3), sink=0.18, g="pond"))

# ── 6) 石板參道 ──
# 2026-10-22 審圖：v1＝2 列 1.37×1.17 m 大石板緊貼連鋪（寬 2.8 m、深色）→ 像黑色跑道；
# v2＝2 列同步成「一對一對」的薄石板，列間 0.35 m 空帶 → 讀成一組組積木。
# v3：兩列交錯（右列錯開半塊）、石縫 4–16 cm、單塊 0.9×1.0 m 左右 → 連續的石畳（v3 起不再缺塊）。
path: list[dict] = []
Z_START = 4.2
Z_END = -20.4
for sx in (-1, 1):
    z = Z_START - (0.55 if sx > 0 else 0.0)        # 右列錯開半塊
    while z > Z_END:
        t = (Z_START - z) / (Z_START - Z_END)      # 0 近鳥居 → 1 近拜殿
        irregular = 1.0 - 0.55 * t
        d_s = rng.uniform(0.78, 0.92)              # z 方向縮放 → 深 0.91–1.08 m
        depth = 1.17 * d_s
        zc = z - depth * 0.5
        # 不缺塊：整條連續（審圖：缺塊讀成「一組一組」）
        path.append(dict(src=rng.choice(["nobe_a", "nobe_c"]), x=round(sx * (0.50 + rng.uniform(-0.015, 0.015) * irregular), 3),
                         z=round(zc + rng.uniform(-0.03, 0.03), 3),
                         yaw=round(rng.choice([0.0, math.pi]) + rng.uniform(-0.07, 0.07) * irregular, 3),
                         s=1.0, sx=round(rng.uniform(0.61, 0.65), 3), sy=0.48, sz=round(d_s, 3)))
        z -= depth + rng.uniform(0.04, 0.16)
# 賽錢箱前的小石墊（2 排 × 3 塊）
for rzz in (-21.9, -23.0):
    for sx in (-1, 0, 1):
        path.append(dict(src=rng.choice(["nobe_a", "nobe_c"]), x=round(sx * 1.2 + rng.uniform(-0.04, 0.04), 3), z=round(rzz + rng.uniform(-0.03, 0.03), 3),
                         yaw=round(rng.choice([0.0, math.pi]), 3), s=1.0, sx=0.78, sy=0.6, sz=0.78))
# 支線飛石：手水舍、倉庫
tobi: list[dict] = []
x = -2.0
while x > -8.6:
    tobi.append(dict(src=rng.choice(["tobi_a", "tobi_b", "tobi_c", "tobi_d"]), x=round(x, 3), z=round(-3.0 + rng.uniform(-0.25, 0.25), 3),
                     yaw=round(rng.uniform(0, 6.28), 3), s=round(rng.uniform(1.0, 1.25), 3)))
    x -= rng.uniform(1.0, 1.35)
x = 2.2
zz = -19.6
while x < 13.2:
    tobi.append(dict(src=rng.choice(["tobi_a", "tobi_b", "tobi_c", "tobi_d"]), x=round(x, 3), z=round(zz + rng.uniform(-0.3, 0.3), 3),
                     yaw=round(rng.uniform(0, 6.28), 3), s=round(rng.uniform(1.0, 1.25), 3)))
    x += rng.uniform(1.0, 1.35)
    zz += 0.12

# ── 7) 地被 ──
# 落花不再用大片 Petal 網格（審圖：像大型高彩度花盤）→ 改成地形 shader 上的細碎花瓣點（petal_mask 控制密度），零幾何。
# 這裡只放低矮三葉草叢（綠色，無碰撞），位置在庭院邊緣、避開池畔與步道。
litter: list[dict] = []
FLORA = [("Clover_1", 0.5, 0.45, 0.70), ("Clover_2", 0.5, 0.45, 0.70)]
tries = 0
n_flora = 0
while n_flora < 22 and tries < 8000:      # 庭院邊緣：靠近平台外緣 0.8–5 m，成小群
    tries += 1
    x, z = rng.uniform(-24, 26), rng.uniform(-46, 4)
    d = d_flat(x, z)
    if not (0.6 < d < 5.0):
        continue
    if blocked(x, z, tree=False) or slope_at(x, z) > 28:
        continue
    r = rng.random() * sum(w for _, w, _, _ in FLORA)
    acc = 0.0
    for name, w, s0, s1 in FLORA:
        acc += w
        if r < acc:
            for _ in range(rng.randint(2, 3)):
                a, rr = rng.uniform(0, 2 * math.pi), rng.uniform(0.1, 0.8)
                fx, fz = x + math.cos(a) * rr, z + math.sin(a) * rr
                if blocked(fx, fz, tree=False) or slope_at(fx, fz) > 32:
                    continue
                litter.append(dict(src=name, x=round(fx, 3), z=round(fz, 3), yaw=round(rng.uniform(0, 6.28), 3),
                                   s=round(rng.uniform(s0, s1), 3), g="flora"))
            break
    n_flora += 1

# 花瓣密度圖（R8；世界矩形 PETAL_RECT；0.5 m / 像素）：櫻花樹下高斯衰減＋庭院零星飄落
PETAL_RECT = dict(x0=-45.0, z0=-60.0, w=90.0, d=75.0)
pw, ph = int(PETAL_RECT["w"] / 0.5), int(PETAL_RECT["d"] / 0.5)
pxs = PETAL_RECT["x0"] + (np.arange(pw) + 0.5) * 0.5
pzs = PETAL_RECT["z0"] + (np.arange(ph) + 0.5) * 0.5
PXG, PZG = np.meshgrid(pxs, pzs)
dens = np.zeros((ph, pw))
for t in trees:
    if not t["id"].startswith("sakura"):
        continue
    sg = 0.30 * SZ[t["id"]][0] * t["s"]
    dens = np.maximum(dens, np.exp(-(((PXG - t["x"]) ** 2 + (PZG - t["z"]) ** 2) / (sg * sg))))
for _ in range(7):                          # 庭院零星飄落（低密度大斑）
    bx, bz = rng.uniform(-13, 14), rng.uniform(-30, -4)
    br = rng.uniform(2.5, 4.5)
    dens = np.maximum(dens, 0.12 * np.exp(-(((PXG - bx) ** 2 + (PZG - bz) ** 2) / (br * br))))
# 石階廊、鳥居前、拜殿台階前不落（保持乾淨）
dens[(np.abs(PXG) < 2.4) & (PZG > 3.0)] = 0.0
from PIL import Image as _Image
_Image.fromarray((np.clip(dens, 0, 1) * 255 + 0.5).astype(np.uint8), "L").save(os.path.join(GEN, "petal_mask.png"))

out = dict(trees=trees, under=under, rocks=rocks, path=path, tobi=tobi, litter=litter, petal=PETAL_RECT)
with open(os.path.join(GEN, "placements.json"), "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False)
from collections import Counter
print("[PLACE] trees", len(trees), dict(Counter(t["g"] for t in trees)))
print("[PLACE] species", dict(Counter(t["id"] for t in trees)))
print("[PLACE] under", len(under), "rocks", len(rocks), dict(Counter(r["g"] for r in rocks)), "path", len(path), "tobi", len(tobi),
      "litter", len(litter), dict(Counter(l["g"] for l in litter)))
