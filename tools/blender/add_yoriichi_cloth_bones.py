"""為緣一（AccuRIG / CC_Base 骨架）加布料骨鏈並轉移權重。

全解析度跑布料會死：袴 92,070 面、羽織 52,912 面。本腳本改走遊戲標準做法
    高模只被骨帶動，物理只算骨。

建立的骨鏈（皆為 jiggle/wiggle 可驅動的自由鏈）：
    Cloth_Haori_F/B/L/R   羽織下襬四向，各 4 節（自 Hip 垂到 z≈0.32）
    Cloth_Sleeve_L/R      左右大袖，各 4 節（自肘外側垂到 z≈0.35）
    Cloth_Hakama_xN       袴下襬 6 向，各 3 節（自 Thigh 垂到 z≈0.18）
共約 26 根骨，物理解算量與 15 萬頂點無關。

權重策略：沿骨鏈以距離場指派，且與原身體骨做「高度過渡」——腰部仍 100%
跟身體，越往下襬越由布料骨主導。不碰上衣與腰帶（貼身，不需飄動）。
"""
import json
import math

import bpy
import numpy as np
from mathutils import Vector

HAORI = "tripo_03c0a423_518b_49ea_bd02_3897f141564e"
HAKAMA = "tripo_mesh_9c098702"
ARM = "Armature"

# (骨鏈名, 起點骨, 起點世界座標, 終點世界座標, 節數)
# 座標取自實測：羽織下襬 z 0.317-0.60、袴下襬 z≈0.18、袖垂到 z≈0.32
CHAINS = []

# --- 羽織下襬：以髖為根，四個方向 ---
_HAORI_Z0, _HAORI_Z1 = 0.96, 0.33
for _tag, _ang in (("F", -90.0), ("B", 90.0), ("L", 0.0), ("R", 180.0)):
    _a = math.radians(_ang)
    _r0, _r1 = 0.17, 0.46
    CHAINS.append({
        "name": f"Cloth_Haori_{_tag}",
        "parent": "CC_Base_Hip",
        "start": [math.cos(_a) * _r0, math.sin(_a) * _r0, _HAORI_Z0],
        "end": [math.cos(_a) * _r1, math.sin(_a) * _r1, _HAORI_Z1],
        "n": 4,
        "mesh": HAORI,
        "influence_z": [_HAORI_Z1, _HAORI_Z0],
        "radius": 0.34,
    })

# --- 大袖：自上臂外側垂下（實測袖垂到 z≈0.32，長度約 1.2 m）---
for _tag, _sg in (("L", 1.0), ("R", -1.0)):
    CHAINS.append({
        "name": f"Cloth_Sleeve_{_tag}",
        "parent": f"CC_Base_{_tag}_Forearm",
        "start": [_sg * 0.36, -0.02, 1.46],
        "end": [_sg * 0.46, -0.02, 0.36],
        "n": 4,
        "mesh": HAORI,
        "influence_z": [0.32, 1.46],
        "radius": 0.30,
        "side": _sg,
    })

# --- 袴下襬：以左右大腿為根，各三向 ---
for _tag, _sg, _parent in (("L", 1.0, "CC_Base_L_Thigh"),
                           ("R", -1.0, "CC_Base_R_Thigh")):
    for _sub, _ang in (("F", -70.0), ("S", 0.0), ("B", 70.0)):
        _a = math.radians(_ang)
        _cx = _sg * 0.11
        CHAINS.append({
            "name": f"Cloth_Hakama_{_tag}{_sub}",
            "parent": _parent,
            "start": [_cx, 0.0, 0.62],
            "end": [_cx + _sg * abs(math.cos(_a)) * 0.13 + 0.0,
                    math.sin(_a) * 0.24, 0.19],
            "n": 3,
            "mesh": HAKAMA,
            "influence_z": [0.18, 0.62],
            "radius": 0.26,
            # 左右腿各管自己那側，否則同一批頂點會被兩腿重複指派
            # （實測六條鏈都吃到 1463/1461 個相同頂點）
            "half": _sg,
        })


def log(*a):
    print("CLOTH", *a)


def build_bones(arm):
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    # AccuRIG 骨架物件帶 0.01 縮放（公分單位）。edit_bones 吃的是 armature
    # 局部座標，直接塞世界座標會讓整條鏈縮到腳底（實測 z 0.96 -> 0.0096）。
    inv = arm.matrix_world.inverted()
    made = {}
    for c in CHAINS:
        s = np.array(inv @ Vector(c["start"]), dtype=float)
        e = np.array(inv @ Vector(c["end"]), dtype=float)
        parent = eb.get(c["parent"])
        prev = parent
        names = []
        for i in range(c["n"]):
            t0 = i / c["n"]
            t1 = (i + 1) / c["n"]
            nm = f'{c["name"]}_{i + 1}'
            if nm in eb:
                eb.remove(eb[nm])
            b = eb.new(nm)
            b.head = Vector(s + (e - s) * t0)
            b.tail = Vector(s + (e - s) * t1)
            b.parent = prev
            b.use_connect = (i > 0)
            b.use_deform = True
            prev = b
            names.append(nm)
        made[c["name"]] = names
    bpy.ops.object.mode_set(mode="OBJECT")
    return made


def transfer_weights(arm, made):
    """把下襬區的權重由身體骨轉給布料骨。

    過渡：influence_z[1] 以上完全不動（腰部仍跟身體），越往下襬布料骨占比
    越高，到 influence_z[0] 為 100%。原身體骨權重等比縮減，確保總和為 1。
    """
    report = {}
    for c in CHAINS:
        o = bpy.data.objects.get(c["mesh"])
        if not o:
            continue
        me = o.data
        M = o.matrix_world
        names = made[c["name"]]
        segs = []
        for nm in names:
            b = arm.data.bones[nm]
            segs.append((nm,
                         np.array(arm.matrix_world @ b.head_local),
                         np.array(arm.matrix_world @ b.tail_local)))
        groups = {}
        for nm in names:
            groups[nm] = o.vertex_groups.get(nm) or o.vertex_groups.new(name=nm)

        zlo, zhi = c["influence_z"]
        rad = c["radius"]
        side = c.get("side")
        half = c.get("half")
        chain_axis = segs[-1][2] - segs[0][1]
        chain_len = float(np.linalg.norm(chain_axis))
        touched = 0

        for v in me.vertices:
            w = M @ v.co
            p = np.array([w.x, w.y, w.z])
            if p[2] > zhi:
                continue
            if side is not None and p[0] * side < 0.18:
                continue
            if half is not None and p[0] * half < 0.0:
                continue
            # 到骨鏈的最近距離與所屬節
            best_j, best_d, best_t = None, 1e9, 0.0
            for j, (nm, a, b) in enumerate(segs):
                ab = b - a
                L2 = float(ab @ ab)
                t = 0.0 if L2 < 1e-12 else float(np.clip(((p - a) @ ab) / L2, 0, 1))
                proj = a + ab * t
                dd = float(np.linalg.norm(p - proj))
                if dd < best_d:
                    best_j, best_d, best_t = j, dd, t
            if best_d > rad:
                continue
            # 高度過渡 + 徑向衰減
            hz = float(np.clip((zhi - p[2]) / max(zhi - zlo, 1e-9), 0.0, 1.0))
            fall = float(np.clip(1.0 - best_d / rad, 0.0, 1.0)) ** 0.7
            infl = hz * fall
            if infl < 0.02:
                continue
            # 原有身體骨權重等比縮減
            for g in list(v.groups):
                gname = o.vertex_groups[g.group].name
                if gname in groups:
                    continue
                o.vertex_groups[g.group].add([v.index], g.weight * (1.0 - infl),
                                             "REPLACE")
            # 布料骨：主節 + 相鄰節混合，鏈上平順
            share = {best_j: 1.0}
            if best_t > 0.7 and best_j + 1 < len(segs):
                share = {best_j: 0.65, best_j + 1: 0.35}
            elif best_t < 0.3 and best_j > 0:
                share = {best_j: 0.65, best_j - 1: 0.35}
            for j, frac in share.items():
                groups[segs[j][0]].add([v.index], infl * frac, "REPLACE")
            touched += 1
        report[c["name"]] = touched
    return report


def normalize(names):
    fixed = {}
    for nm in names:
        o = bpy.data.objects.get(nm)
        if not o:
            continue
        n = 0
        for v in o.data.vertices:
            gs = [g for g in v.groups if g.weight > 1e-6]
            s = sum(g.weight for g in gs)
            if not gs or abs(s - 1.0) < 1e-4:
                continue
            for g in gs:
                o.vertex_groups[g.group].add([v.index], g.weight / s, "REPLACE")
            n += 1
        fixed[nm] = n
    return fixed


def main():
    arm = bpy.data.objects[ARM]
    made = build_bones(arm)
    log("bones", sum(len(v) for v in made.values()), "chains", len(made))
    rep = transfer_weights(arm, made)
    log("weights", json.dumps(rep, ensure_ascii=False))
    fx = normalize([HAORI, HAKAMA])
    log("normalized", json.dumps(fx, ensure_ascii=False))
    print("CLOTHDONE" + json.dumps(
        {"chains": {k: len(v) for k, v in made.items()},
         "weighted": rep, "normalized": fx}, ensure_ascii=False) + "CLOTHEND")


main()
