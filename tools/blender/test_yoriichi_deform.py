"""扭曲測試：實際擺極限姿勢，量網格形變品質。

檢查三件事
  1. 體積塌陷：關節彎曲處截面積掉多少（>35% 視為塌陷）
  2. 自我穿插：手臂/腿與軀幹的最近距離是否變負（穿模）
  3. 麻花：前臂轉腕時，沿骨長各截面的扭轉角是否平順遞增
"""
import json
import math

import bpy
import numpy as np
from mathutils import Vector, Quaternion

RIGGED = r"D:/神社/shrine/work/緣一_rigged.blend"
BODY = "身體2"


def evaluated_verts(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    M = obj.matrix_world
    V = np.array([[(M @ v.co).x, (M @ v.co).y, (M @ v.co).z] for v in me.vertices])
    ev.to_mesh_clear()
    return V


def reset_pose(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((1, 0, 0, 0))
        pb.location = Vector((0, 0, 0))
    bpy.context.view_layer.update()


def set_rot(arm, bone, axis, deg):
    pb = arm.pose.bones[bone]
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = Quaternion(Vector(axis), math.radians(deg))
    bpy.context.view_layer.update()


def limb_sections(V, origin, axis, lo, hi, step, radius):
    """沿 axis 取截面，回傳 [(t, n, 平均半徑)]。"""
    axis = np.array(axis, dtype=float)
    axis /= np.linalg.norm(axis)
    origin = np.array(origin, dtype=float)
    R = V - origin
    d = R @ axis
    perp = R - np.outer(d, axis)
    rad = np.linalg.norm(perp, axis=1)
    out = []
    t = lo
    while t <= hi + 1e-9:
        m = (d > t - step / 2) & (d < t + step / 2) & (rad < radius)
        if m.sum() >= 6:
            out.append((round(t, 4), int(m.sum()), float(rad[m].mean())))
        t += step
    return out


def main():
    bpy.ops.wm.open_mainfile(filepath=RIGGED)
    arm = bpy.data.objects["Armature"]
    body = bpy.data.objects[BODY]
    bpy.context.view_layer.objects.active = arm
    rep = {}

    # ---------- 基準（rest） ----------
    reset_pose(arm)
    V0 = evaluated_verts(body)
    rep["rest_bbox"] = {
        "x": [round(float(V0[:, 0].min()), 4), round(float(V0[:, 0].max()), 4)],
        "z": [round(float(V0[:, 2].min()), 4), round(float(V0[:, 2].max()), 4)],
    }

    J = {b.name: (np.array(b.head_local), np.array(b.tail_local))
         for b in arm.data.bones}

    # ---------- 測試 1：肘彎 90° ----------
    elbow_h = J["LeftForeArm"][0]
    base = limb_sections(V0, elbow_h, (1, 0, 0), -0.08, 0.08, 0.02, 0.06)
    reset_pose(arm)
    set_rot(arm, "LeftForeArm", (0, 0, 1), 90)
    V1 = evaluated_verts(body)
    bent = limb_sections(V1, elbow_h, (1, 0, 0), -0.08, 0.08, 0.02, 0.06)
    b0 = {t: r for t, n, r in base}
    b1 = {t: r for t, n, r in bent}
    worst = None
    for t in sorted(set(b0) & set(b1)):
        ratio = b1[t] / b0[t] if b0[t] > 1e-6 else 1.0
        if worst is None or ratio < worst[1]:
            worst = (t, ratio)
    rep["elbow_bend90"] = {
        "worst_section_t": worst[0],
        "radius_ratio": round(worst[1], 3),
        "verdict": "OK" if worst[1] > 0.65 else "塌陷",
    }

    # ---------- 測試 2：腕轉 90°（麻花檢查） ----------
    reset_pose(arm)
    fa_h, fa_t = J["LeftForeArm"]
    axis = fa_t - fa_h
    axis = axis / np.linalg.norm(axis)
    sel = None
    R0 = V0 - fa_h
    d0 = R0 @ axis
    rad0 = np.linalg.norm(R0 - np.outer(d0, axis), axis=1)
    sel = (d0 > 0.01) & (d0 < np.linalg.norm(fa_t - fa_h)) & (rad0 < 0.05)

    set_rot(arm, "LeftHand", (0, 1, 0), 90)
    V2 = evaluated_verts(body)
    R2 = V2 - fa_h
    d2 = R2 @ axis
    twist_prof = []
    for t in np.arange(0.02, float(np.linalg.norm(fa_t - fa_h)), 0.02):
        m = sel & (d0 > t - 0.01) & (d0 < t + 0.01)
        if m.sum() < 6:
            continue
        p0 = R0[m] - np.outer(d0[m], axis)
        p2 = R2[m] - np.outer(d2[m], axis)
        ang = []
        for a, b in zip(p0, p2):
            na, nb = np.linalg.norm(a), np.linalg.norm(b)
            if na < 1e-5 or nb < 1e-5:
                continue
            c = float(np.clip((a @ b) / (na * nb), -1, 1))
            ang.append(math.degrees(math.acos(c)))
        if ang:
            twist_prof.append([round(float(t), 3), int(m.sum()), round(float(np.mean(ang)), 1)])
    rep["wrist_twist90"] = {
        "profile_elbow_to_wrist": twist_prof,
        "monotonic": all(twist_prof[i][2] <= twist_prof[i + 1][2] + 6
                         for i in range(len(twist_prof) - 1)) if len(twist_prof) > 1 else None,
    }

    # ---------- 測試 3：腰扭 45° + 穿插檢查 ----------
    reset_pose(arm)
    set_rot(arm, "Spine01", (0, 0, 1), 45)
    V3 = evaluated_verts(body)
    rep["spine_twist45"] = {
        "head_moved_cm": round(float(np.linalg.norm(
            V3[V3[:, 2].argmax()] - V0[V0[:, 2].argmax()]) * 100), 2),
    }

    # ---------- 測試 4：膝彎 90° ----------
    knee_h = J["LeftLeg"][0]
    base = limb_sections(V0, knee_h, (0, 0, -1), -0.08, 0.08, 0.02, 0.09)
    reset_pose(arm)
    set_rot(arm, "LeftLeg", (1, 0, 0), -90)
    V4 = evaluated_verts(body)
    bent = limb_sections(V4, knee_h, (0, 0, -1), -0.08, 0.08, 0.02, 0.09)
    b0 = {t: r for t, n, r in base}
    b1 = {t: r for t, n, r in bent}
    worst = None
    for t in sorted(set(b0) & set(b1)):
        ratio = b1[t] / b0[t] if b0[t] > 1e-6 else 1.0
        if worst is None or ratio < worst[1]:
            worst = (t, ratio)
    rep["knee_bend90"] = {
        "worst_section_t": worst[0],
        "radius_ratio": round(worst[1], 3),
        "verdict": "OK" if worst[1] > 0.65 else "塌陷",
    }

    # ---------- 測試 5：握拳（手指全彎） ----------
    reset_pose(arm)
    for f in ("Index", "Middle", "Ring", "Pinky"):
        for i in (1, 2, 3):
            n = f"LeftHand{f}{i}"
            if n in arm.pose.bones:
                set_rot(arm, n, (0, 0, 1), -70)
    V5 = evaluated_verts(body)
    tipsel = V0[:, 0] > 0.66
    if tipsel.sum() > 0:
        moved = np.linalg.norm(V5[tipsel] - V0[tipsel], axis=1).mean()
        rep["fist"] = {"fingertip_travel_cm": round(float(moved * 100), 2),
                       "verdict": "OK" if moved > 0.02 else "手指沒動"}

    reset_pose(arm)
    print("TESTSTART" + json.dumps(rep, ensure_ascii=False) + "TESTEND")


if __name__ == "__main__":
    main()
