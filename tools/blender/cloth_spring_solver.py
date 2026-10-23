"""自寫 spring-bone 慣性驅動：不依賴任何外掛，逐幀求解並寫入 action。

先前兩條路都失敗：
  * jiggle_physics 的 handler 在腳本環境不觸發（補了 action/keyframe 仍 0 度）
  * Damped Track 把目標綁在同一父骨，兩者同步移動，追蹤角差恆為 0（實測 0.13 度）

本模組直接做質點彈簧：
  每節布料骨的尖端視為質點，受重力 + 彈簧（拉回 rest 方向）+ 阻尼，
  父骨移動時質點因慣性落後，產生真正的拖曳。逐幀解算後把結果寫成
  骨旋轉 keyframe —— 可直接烘焙、匯出 Godot。

驗證方式：量「骨相對其父骨」的朝向變化，排除整體位移的假訊號。
"""
import json
import math

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

ARM = "Armature"
PREFIX = "Cloth_"

# 每類布料的手感：stiff 越大越硬、damp 越大越快停、grav 重力影響
TUNING = {
    "Cloth_Sleeve": dict(stiff=14.0, damp=3.2, grav=2.4, maxang=52.0),
    "Cloth_Haori": dict(stiff=20.0, damp=4.0, grav=2.0, maxang=40.0),
    "Cloth_Hakama": dict(stiff=28.0, damp=5.0, grav=1.6, maxang=30.0),
}
FPS = 30.0


def log(*a):
    print("SPR", *a)


def get_chains(arm):
    out = {}
    for b in arm.data.bones:
        if b.name.startswith(PREFIX):
            out.setdefault(b.name.rsplit("_", 1)[0], []).append(b.name)
    for k in out:
        out[k].sort(key=lambda s: int(s.rsplit("_", 1)[1]))
    return out


def clear_constraints(arm):
    n = 0
    for pb in arm.pose.bones:
        if pb.name.startswith(PREFIX):
            for c in list(pb.constraints):
                pb.constraints.remove(c)
                n += 1
    for o in list(bpy.data.objects):
        if o.name.startswith("ClothTgt_"):
            bpy.data.objects.remove(o, do_unlink=True)
    return n


def solve(arm, frames, motion_fn, write_keys=True):
    """逐幀求解彈簧並（可選）寫入旋轉 key。回傳每骨最大相對父骨偏角。"""
    chains = get_chains(arm)
    mw = arm.matrix_world
    sc = bpy.context.scene

    state = {}          # bone -> 質點世界位置 / 速度
    peak = {}
    for base, names in chains.items():
        for nm in names:
            pb = arm.pose.bones[nm]
            pb.rotation_mode = "QUATERNION"
            state[nm] = {"p": np.array(mw @ pb.tail), "v": np.zeros(3)}
            peak[nm] = 0.0

    dt = 1.0 / FPS
    grav_dir = np.array([0.0, 0.0, -9.81])

    for fi, f in enumerate(frames):
        motion_fn(arm, fi, f)
        bpy.context.view_layer.update()

        for base, names in chains.items():
            key = next((k for k in TUNING if base.startswith(k)), None)
            if key is None:
                continue
            t = TUNING[key]
            for nm in names:
                pb = arm.pose.bones[nm]
                # rest 目標：骨在「無慣性」時尖端應在的世界位置
                head = np.array(mw @ pb.head)
                rest_dir = np.array(
                    (pb.matrix.to_3x3() @ Vector((0, 1, 0))).normalized())
                blen = float(np.linalg.norm(np.array(mw @ pb.tail) - head))
                target = head + rest_dir * blen

                s = state[nm]
                # 彈簧 + 阻尼 + 重力
                acc = (target - s["p"]) * t["stiff"] \
                    - s["v"] * t["damp"] + grav_dir * t["grav"] * 0.02
                s["v"] += acc * dt
                s["p"] += s["v"] * dt
                # 約束到骨長（保持鏈不伸長）
                d = s["p"] - head
                L = np.linalg.norm(d)
                if L > 1e-6:
                    s["p"] = head + d / L * blen
                cur = (s["p"] - head) / max(np.linalg.norm(s["p"] - head), 1e-9)

                # 限制最大偏角
                c = float(np.clip(rest_dir @ cur, -1.0, 1.0))
                ang = math.degrees(math.acos(c))
                if ang > t["maxang"]:
                    axis = np.cross(rest_dir, cur)
                    if np.linalg.norm(axis) > 1e-9:
                        axis /= np.linalg.norm(axis)
                        q = Quaternion(Vector(axis), math.radians(t["maxang"]))
                        cur = np.array(q @ Vector(rest_dir))
                        s["p"] = head + cur * blen
                        ang = t["maxang"]

                peak[nm] = max(peak[nm], ang)

                if write_keys and ang > 0.01:
                    # 把 rest_dir -> cur 的旋轉寫進骨的 local basis
                    axis = np.cross(rest_dir, cur)
                    na = np.linalg.norm(axis)
                    if na > 1e-9:
                        q_world = Quaternion(Vector(axis / na),
                                             math.acos(c))
                        m_par = pb.parent.matrix.to_3x3() if pb.parent \
                            else Matrix.Identity(3)
                        local = (m_par.inverted()
                                 @ q_world.to_matrix()
                                 @ m_par)
                        pb.rotation_quaternion = local.to_quaternion()
                if write_keys:
                    pb.keyframe_insert(data_path="rotation_quaternion",
                                       frame=f)
    return peak


def main():
    arm = bpy.data.objects[ARM]
    bpy.context.view_layer.objects.active = arm
    if bpy.context.object.mode != "POSE":
        bpy.ops.object.mode_set(mode="POSE")

    removed = clear_constraints(arm)

    hip = arm.pose.bones["CC_Base_Hip"]
    hip.rotation_mode = "QUATERNION"
    base_loc = hip.location.copy()

    def motion(a, i, f):
        # 測試動作：髖左右擺（模擬走動），布料應落後拖曳
        hip.location = base_loc + Vector(
            (0.16 * math.sin(i * math.pi / 8), 0.0, 0.0))

    frames = list(range(1, 61))
    peak = solve(arm, frames, motion, write_keys=False)

    hip.location = base_loc
    bpy.context.view_layer.update()

    tot = sum(peak.values())
    top = sorted(peak.items(), key=lambda x: -x[1])[:12]
    out = {"removed_constraints": removed,
           "bones": len(peak),
           "peak_deg": {k: round(v, 2) for k, v in top},
           "total_deg": round(tot, 2),
           "verdict": "MOVES" if tot > 5.0 else "STATIC"}
    print("SPRDONE" + json.dumps(out, ensure_ascii=False) + "SPREND")


main()
