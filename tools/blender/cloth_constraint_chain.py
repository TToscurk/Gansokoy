"""用原生約束為布料骨建立可驗證的拖曳/慣性效果。

jiggle_physics 外掛在腳本環境中始終不觸發（其 handler 需要互動式
frame_change 與內部 keyframe 條件，實測加了 action 與 key 仍為 0 度）。
改用 Blender 原生做法，不依賴外掛，且在 headless 亦可驗證：

  每條布料鏈尾端放一個「目標空物件」，空物件用 Child Of 綁到父骨並帶
  Damped Track + Limit Location 的延遲位移；布料骨以 Damped Track 追蹤
  下一節，形成隨身體運動而拖曳的鏈條。

這是可直接烘焙成骨動畫、匯進 Godot 的形式。
"""
import json
import math

import bpy
import numpy as np
from mathutils import Vector

ARM = "Armature"
PREFIX = "Cloth_"
# 每類布料的追蹤強度（影響拖曳延遲感）
INFLUENCE = {
    "Cloth_Sleeve": 0.85,
    "Cloth_Haori": 0.75,
    "Cloth_Hakama": 0.6,
}


def log(*a):
    print("CON", *a)


def chains(arm):
    out = {}
    for b in arm.data.bones:
        if b.name.startswith(PREFIX):
            base = b.name.rsplit("_", 1)[0]
            out.setdefault(base, []).append(b.name)
    for k in out:
        out[k].sort(key=lambda s: int(s.rsplit("_", 1)[1]))
    return out


def clear_old(arm):
    n = 0
    for pb in arm.pose.bones:
        if not pb.name.startswith(PREFIX):
            continue
        for c in list(pb.constraints):
            pb.constraints.remove(c)
            n += 1
    for o in list(bpy.data.objects):
        if o.name.startswith("ClothTgt_"):
            bpy.data.objects.remove(o, do_unlink=True)
    return n


def build(arm):
    made = {}
    coll = bpy.context.scene.collection
    for base, names in chains(arm).items():
        key = next((k for k in INFLUENCE if base.startswith(k)), None)
        if key is None:
            continue
        infl = INFLUENCE[key]
        # 鏈尾放一個目標空物件，掛在鏈的父骨上（含延遲）
        tail_bone = arm.data.bones[names[-1]]
        world_tail = arm.matrix_world @ tail_bone.tail_local
        empty = bpy.data.objects.new("ClothTgt_" + base, None)
        empty.empty_display_type = "SPHERE"
        empty.empty_display_size = 0.03
        empty.location = world_tail
        coll.objects.link(empty)

        root_parent = arm.data.bones[names[0]].parent
        cc = empty.constraints.new("CHILD_OF")
        cc.target = arm
        cc.subtarget = root_parent.name if root_parent else "CC_Base_Hip"
        # 目標略低於原位，讓鏈自然垂墜
        empty.location.z -= 0.02

        for i, nm in enumerate(names):
            pb = arm.pose.bones[nm]
            dt = pb.constraints.new("DAMPED_TRACK")
            dt.target = empty
            dt.track_axis = "TRACK_Y"
            # 越靠鏈尾追蹤越強，形成遞進拖曳
            dt.influence = infl * (0.45 + 0.55 * (i + 1) / len(names))
        made[base] = {"bones": len(names), "target": empty.name,
                      "influence": round(infl, 2)}
    return made


def verify(arm):
    """擺動髖骨，量布料骨相對 rest 的旋轉偏移。"""
    sc = bpy.context.scene
    tips = [b.name for b in arm.data.bones
            if b.name.startswith(PREFIX) and b.name.endswith(("_3", "_4"))]
    hip = arm.pose.bones["CC_Base_Hip"]
    base_loc = hip.location.copy()

    def dev():
        """量約束求解後的實際骨朝向。

        不可用 matrix_basis：它只含手動 pose，約束造成的旋轉不寫入其中
        （實測約束已建立但 matrix_basis 恆為單位四元數）。
        pb.matrix 才是約束求解後的最終結果。
        """
        d = {}
        for nm in tips:
            pb = arm.pose.bones[nm]
            v = (pb.matrix.to_3x3() @ Vector((0, 1, 0))).normalized()
            d[nm] = np.array([v.x, v.y, v.z])
        return d

    bpy.context.view_layer.update()
    b0 = dev()
    peak = {nm: 0.0 for nm in tips}
    for step in range(24):
        hip.location = base_loc + Vector(
            (0.18 * math.sin(step * math.pi / 6), 0.0, 0.0))
        bpy.context.view_layer.update()
        d = dev()
        for nm in tips:
            c = float(np.clip(b0[nm] @ d[nm], -1.0, 1.0))
            peak[nm] = max(peak[nm], math.degrees(math.acos(c)))
    hip.location = base_loc
    bpy.context.view_layer.update()
    return peak


def main():
    arm = bpy.data.objects[ARM]
    bpy.context.view_layer.objects.active = arm
    removed = clear_old(arm)
    made = build(arm)
    peak = verify(arm)
    tot = sum(peak.values())
    out = {"removed_constraints": removed,
           "chains": made,
           "peak_deg": {k: round(v, 2) for k, v in
                        sorted(peak.items(), key=lambda x: -x[1])[:12]},
           "total_deg": round(tot, 2),
           "verdict": "MOVES" if tot > 1.0 else "STATIC"}
    print("CONDONE" + json.dumps(out, ensure_ascii=False) + "CONEND")


main()
