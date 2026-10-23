"""為緣一布料骨掛上 jiggle 物理，並實測是否真的會晃。

屬性名由實際掃描取得（jiggle_physics 外掛）：
    jiggle_angle_elasticity / jiggle_length_elasticity / jiggle_air_drag
    jiggle_gravity / jiggle_friction / jiggle_blend / jiggle_root_elasticity
    jiggle_elasticity_soften / jiggle_collision_radius

手感取向：袖最飄（彈性低、阻力小），羽織中等，袴最沉（走路才不會亂甩）。
驗證方式：把骨架整體平移再回位，逐幀推進物理，量布料骨末端的位移量。
"""
import json

import bpy
import numpy as np
from mathutils import Vector

ARM = "Armature"

TUNING = {
    "Cloth_Sleeve": dict(angle=0.12, length=0.85, drag=0.38,
                         grav=0.9, soften=0.55, blend=1.0),
    "Cloth_Haori": dict(angle=0.20, length=0.88, drag=0.30,
                        grav=1.0, soften=0.45, blend=1.0),
    "Cloth_Hakama": dict(angle=0.32, length=0.92, drag=0.24,
                         grav=1.0, soften=0.35, blend=1.0),
}


def log(*a):
    print("JIG", *a)


def apply_tuning(arm):
    """設定布料骨的 jiggle 參數。

    mode 合法值為 none/root/solo/merge/normal/tip（沒有 chain）。骨鏈標準設法：
    第一節 root 當錨點、中間 normal、末節 tip。
    """
    n = 0
    per = {}
    chains = {}
    for b in arm.data.bones:
        if not b.name.startswith("Cloth_"):
            continue
        base = b.name.rsplit("_", 1)[0]
        chains.setdefault(base, []).append(b.name)
    for base, names in chains.items():
        names.sort(key=lambda s: int(s.rsplit("_", 1)[1]))
        key = next((k for k in TUNING if base.startswith(k)), None)
        if key is None:
            continue
        t = TUNING[key]
        for i, nm in enumerate(names):
            pb = arm.pose.bones[nm]
            # 真正的開關在巢狀群組 pb.jiggle.enable。
            # pb.wiggle_enable 是另一個外掛（wiggle_2）的屬性，對 jiggle 無效。
            pb.jiggle.enable = True
            if i == 0:
                pb.jiggle.mode = "root"
            elif i == len(names) - 1:
                pb.jiggle.mode = "tip"
            else:
                pb.jiggle.mode = "normal"
            pb.jiggle_angle_elasticity = t["angle"]
            pb.jiggle_length_elasticity = t["length"]
            pb.jiggle_air_drag = t["drag"]
            pb.jiggle_gravity = t["grav"]
            pb.jiggle_elasticity_soften = t["soften"]
            pb.jiggle_blend = t["blend"]
            pb.jiggle_collision_radius = 0.0
            n += 1
        per[key] = per.get(key, 0) + len(names)
    return n, per


def tip_positions(arm, names):
    return {nm: np.array(arm.matrix_world @ arm.pose.bones[nm].tail)
            for nm in names}


def main():
    arm = bpy.data.objects[ARM]
    bpy.context.view_layer.objects.active = arm
    sc = bpy.context.scene

    out = {}
    # 啟用場景層級 jiggle
    try:
        sc.jiggle.enable = True
        out["scene_enable"] = True
    except Exception as e:
        out["scene_enable_err"] = str(e)

    try:
        arm.jiggle.enable = True
        out["obj_enable"] = True
    except Exception as e:
        out["obj_enable_err"] = str(e)

    n, per = apply_tuning(arm)
    out["tuned_bones"] = n
    out["per_group"] = per

    # --- 實測：量「相對父骨」的偏移，而非世界位移 ---
    # 量世界座標會把整體平移算進去（實測全部剛好等於平移量 22 cm），
    # 那是跟著走不是慣性。jiggle 生效時 pose bone 的 local matrix 會偏離單位矩陣。
    tips = [b.name for b in arm.data.bones
            if b.name.startswith("Cloth_") and b.name.endswith(("_3", "_4"))]
    out["measured_tips"] = len(tips)

    def local_dev():
        """各布料骨 pose 相對 rest 的旋轉偏移量（度）。"""
        dev = {}
        for nm in tips:
            pb = arm.pose.bones[nm]
            q = pb.matrix_basis.to_quaternion()
            ang = 2.0 * np.degrees(np.arccos(min(1.0, abs(q.w))))
            dev[nm] = float(ang)
        return dev

    sc.frame_set(1)
    bpy.context.view_layer.update()
    base_dev = local_dev()
    start_loc = arm.location.copy()

    peak = {nm: 0.0 for nm in tips}
    for f in range(2, 46):
        arm.location = start_loc + Vector((0.22 if (f // 6) % 2 == 0 else -0.22,
                                           0.0, 0.0))
        sc.frame_set(f)
        bpy.context.view_layer.update()
        d = local_dev()
        for nm in tips:
            peak[nm] = max(peak[nm], abs(d[nm] - base_dev[nm]))

    arm.location = start_loc
    sc.frame_set(1)
    bpy.context.view_layer.update()

    out["tip_swing_deg"] = {k: round(v, 3) for k, v in peak.items()}
    tot = sum(peak.values())
    out["total_swing_deg"] = round(tot, 2)
    out["verdict"] = "MOVES" if tot > 1.0 else "STATIC"

    print("JIGDONE" + json.dumps(out, ensure_ascii=False) + "JIGEND")


main()
