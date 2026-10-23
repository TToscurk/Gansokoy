"""用 solve_yoriichi_joints.py 解出的骨位，建立緣一骨架並綁定權重。

重點在權重品質：
  * 前臂加 twist 骨，避免拔刀轉腕時網格擰成麻花
  * 身體用 heat map 自動權重
  * 衣服（羽織/上衣/袴/腰帶）用 Data Transfer 從身體繼承，不各自亂飄
  * 頭髮剛性綁 Head

輸出 緣一_rigged.blend，原檔不動。
"""
import json
import math

import bpy
import numpy as np
from mathutils import Vector

SRC_BLEND = r"D:/神社/shrine/work/緣一.blend"
OUT_BLEND = r"D:/神社/shrine/work/緣一_rigged.blend"
JOINTS = r"D:/神社/shrine/work/yoriichi_rig/_solved_joints.json"

BODY = "身體2"
CLOTHES = ["上衣", "羽織", "袴", "腰帶"]
HAIR = "頭髮"

# 每側前臂 twist 骨數量：拔刀動作前臂需轉近 180°
TWIST_N = 2


def log(*a):
    print("RIG", *a)


def reset_scene():
    bpy.ops.wm.open_mainfile(filepath=SRC_BLEND)
    # 清掉非必要物件
    for o in list(bpy.data.objects):
        if o.type not in {"MESH"}:
            bpy.data.objects.remove(o, do_unlink=True)
    # 套用所有物件變換，讓網格座標 = 世界座標（骨位是世界座標解出來的）
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    log("meshes", [o.name for o in meshes])
    return meshes


def build_armature(J):
    arm_data = bpy.data.armatures.new("YoriichiArm")
    arm = bpy.data.objects.new("Armature", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    order = sorted(J, key=lambda k: _depth(J, k))
    for name in order:
        d = J[name]
        b = eb.new(name)
        b.head = Vector(d["head"])
        b.tail = Vector(d["tail"])
        if (b.tail - b.head).length < 1e-4:
            b.tail = b.head + Vector((0, 0, 0.01))
    for name in order:
        p = J[name]["parent"]
        if p:
            eb[name].parent = eb[p]
            eb[name].use_connect = (eb[name].head - eb[p].tail).length < 1e-4

    _add_twists(eb)

    # 統一骨滾轉：肢體對齊全域 +Z，手指亦然，避免旋轉軸亂掉
    bpy.ops.armature.select_all(action="SELECT")
    bpy.ops.armature.calculate_roll(type="GLOBAL_POS_Z")

    # root 不參與形變
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.data.bones["root"].use_deform = False
    log("bones", len(arm.data.bones))
    return arm


def _depth(J, k, n=0):
    p = J[k]["parent"]
    return 0 if not p else _depth(J, p, n + 1) + 1


def _add_twists(eb):
    """在前臂與上臂插入 twist 骨（不改變原骨階層，twist 為 ForeArm 子骨）。"""
    for side in ("Left", "Right"):
        fa = eb.get(f"{side}ForeArm")
        hand = eb.get(f"{side}Hand")
        if not fa or not hand:
            continue
        h, t = fa.head.copy(), fa.tail.copy()
        for i in range(1, TWIST_N + 1):
            f0 = (i - 1) / TWIST_N
            f1 = i / TWIST_N
            b = eb.new(f"{side}ForeArmTwist{i}")
            b.head = h.lerp(t, f0)
            b.tail = h.lerp(t, f1)
            b.parent = fa
            b.use_connect = False


def bind_body(arm, body):
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    log("body bound", body.name, "vgroups", len(body.vertex_groups))


def redistribute_twist(arm, body):
    """把 ForeArm 的權重沿骨長線性分給 twist 骨。

    heat map 會把整段前臂權重全給 ForeArm，手腕一轉就整段擰。改成靠近手腕
    的頂點由 twist 骨主導（twist 跟著手轉），靠近手肘的仍由 ForeArm 主導。
    """
    stats = {}
    for side in ("Left", "Right"):
        fa_name = f"{side}ForeArm"
        if fa_name not in body.vertex_groups:
            continue
        b = arm.data.bones[fa_name]
        h = np.array(b.head_local)
        t = np.array(b.tail_local)
        axis = t - h
        L2 = float(axis @ axis)
        fa_g = body.vertex_groups[fa_name]
        tw = [body.vertex_groups.get(f"{side}ForeArmTwist{i}")
              or body.vertex_groups.new(name=f"{side}ForeArmTwist{i}")
              for i in range(1, TWIST_N + 1)]
        idx = fa_g.index
        moved = 0
        for v in body.data.vertices:
            w = None
            for g in v.groups:
                if g.group == idx:
                    w = g.weight
                    break
            if not w:
                continue
            f = float((np.array(v.co) - h) @ axis / L2)
            f = min(max(f, 0.0), 1.0)
            # f=0 肘端全留 ForeArm；f=1 腕端全給最後一節 twist
            seg = f * TWIST_N
            k = min(int(seg), TWIST_N - 1)
            local = seg - k
            keep = (1.0 - f)
            give = w * (1.0 - keep)
            fa_g.add([v.index], w * keep, "REPLACE")
            if give > 1e-5:
                if k == 0:
                    tw[0].add([v.index], give, "REPLACE")
                else:
                    tw[k - 1].add([v.index], give * (1 - local), "REPLACE")
                    tw[k].add([v.index], give * local, "REPLACE")
                moved += 1
        stats[side] = moved
    log("twist redistributed", stats)


def add_twist_drivers(arm):
    """twist 骨跟隨手掌轉動：最後一節 100%，前面按比例遞減。"""
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    for side in ("Left", "Right"):
        for i in range(1, TWIST_N + 1):
            pb = arm.pose.bones.get(f"{side}ForeArmTwist{i}")
            if not pb:
                continue
            c = pb.constraints.new("COPY_ROTATION")
            c.target = arm
            c.subtarget = f"{side}Hand"
            c.use_x, c.use_y, c.use_z = False, True, False  # 只抄沿骨長軸的扭轉
            c.target_space = "LOCAL"
            c.owner_space = "LOCAL"
            c.influence = i / TWIST_N
    bpy.ops.object.mode_set(mode="OBJECT")
    log("twist drivers set")


def bind_clothes(arm, body, meshes):
    """衣服從身體繼承權重，避免各自 heat map 產生飄動。"""
    done = []
    for name in CLOTHES:
        o = bpy.data.objects.get(name)
        if not o:
            continue
        for vg in list(o.vertex_groups):
            o.vertex_groups.remove(vg)
        for b in arm.data.bones:
            if b.use_deform:
                o.vertex_groups.new(name=b.name)

        bpy.ops.object.select_all(action="DESELECT")
        body.select_set(True)
        o.select_set(True)
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.data_transfer(
            data_type="VGROUP_WEIGHTS",
            use_create=True,
            vert_mapping="POLYINTERP_NEAREST",
            layers_select_src="ALL",
            layers_select_dst="NAME",
            mix_mode="REPLACE",
        )
        o.modifiers.clear()
        m = o.modifiers.new("Armature", "ARMATURE")
        m.object = arm
        o.parent = arm
        o.matrix_parent_inverse = arm.matrix_world.inverted()
        done.append(name)
    log("clothes bound", done)


def bind_hair(arm):
    o = bpy.data.objects.get(HAIR)
    if not o:
        return
    for vg in list(o.vertex_groups):
        o.vertex_groups.remove(vg)
    g = o.vertex_groups.new(name="Head")
    g.add([v.index for v in o.data.vertices], 1.0, "REPLACE")
    o.modifiers.clear()
    m = o.modifiers.new("Armature", "ARMATURE")
    m.object = arm
    o.parent = arm
    o.matrix_parent_inverse = arm.matrix_world.inverted()
    log("hair bound rigid to Head")


def normalize_weights(body):
    """權重總和歸一。twist 重分配會留下捨入誤差，不歸一會讓形變縮放。"""
    fixed = 0
    for v in body.data.vertices:
        gs = [g for g in v.groups if g.weight > 1e-6]
        s = sum(g.weight for g in gs)
        if not gs or abs(s - 1.0) < 1e-4:
            continue
        for g in gs:
            body.vertex_groups[g.group].add([v.index], g.weight / s, "REPLACE")
        fixed += 1
    log("normalized", fixed)


def audit(arm, body):
    """權重健檢：無權重頂點、權重總和異常、單骨影響過廣。"""
    rep = {}
    n_no = 0
    bad_sum = 0
    for v in body.data.vertices:
        s = sum(g.weight for g in v.groups)
        if not v.groups or s < 1e-4:
            n_no += 1
        elif abs(s - 1.0) > 0.05:
            bad_sum += 1
    rep["unweighted_verts"] = n_no
    rep["weightsum_off"] = bad_sum
    counts = {}
    for v in body.data.vertices:
        for g in v.groups:
            if g.weight > 0.01:
                nm = body.vertex_groups[g.group].name
                counts[nm] = counts.get(nm, 0) + 1
    rep["per_bone"] = dict(sorted(counts.items()))
    rep["bones_with_zero"] = [b.name for b in arm.data.bones
                              if b.use_deform and counts.get(b.name, 0) == 0]
    return rep


def main():
    J = json.load(open(JOINTS, encoding="utf-8"))
    meshes = reset_scene()
    body = bpy.data.objects[BODY]
    arm = build_armature(J)
    bind_body(arm, body)
    redistribute_twist(arm, body)
    normalize_weights(body)
    add_twist_drivers(arm)
    bind_clothes(arm, body, meshes)
    bind_hair(arm)
    rep = audit(arm, body)
    print("AUDITSTART" + json.dumps(rep, ensure_ascii=False) + "AUDITEND")
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    log("saved", OUT_BLEND)


if __name__ == "__main__":
    main()
