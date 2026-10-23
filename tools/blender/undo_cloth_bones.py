"""還原：清除本次加入的布料骨、權重、約束與測試動畫。

把場景恢復到加布料骨之前的狀態（AccuRIG 綁定 + 耳飾貼圖保留）。
"""
import json

import bpy

ARM = "Armature"
PREFIX = "Cloth_"
CLOTH_MESHES = ["tripo_03c0a423_518b_49ea_bd02_3897f141564e",   # 羽織
                "tripo_mesh_9c098702"]                          # 袴


def log(*a):
    print("UNDO", *a)


def main():
    out = {}
    arm = bpy.data.objects.get(ARM)
    if arm is None:
        print("UNDODONE" + json.dumps({"error": "no armature"}) + "UNDOEND")
        return

    bpy.context.view_layer.objects.active = arm
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    # 1) 清 pose 約束 + 重設姿勢
    ncon = 0
    for pb in arm.pose.bones:
        for c in list(pb.constraints):
            if pb.name.startswith(PREFIX):
                pb.constraints.remove(c)
                ncon += 1
        if pb.name.startswith(PREFIX):
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.location = (0, 0, 0)
            pb.scale = (1, 1, 1)
    out["constraints_removed"] = ncon

    # 2) 刪布料骨
    bpy.ops.object.mode_set(mode="EDIT")
    nb = 0
    for b in list(arm.data.edit_bones):
        if b.name.startswith(PREFIX):
            arm.data.edit_bones.remove(b)
            nb += 1
    bpy.ops.object.mode_set(mode="OBJECT")
    out["bones_removed"] = nb

    # 3) 刪目標空物件
    nt = 0
    for o in list(bpy.data.objects):
        if o.name.startswith("ClothTgt_"):
            bpy.data.objects.remove(o, do_unlink=True)
            nt += 1
    out["targets_removed"] = nt

    # 4) 刪布料頂點群組並重新正規化權重
    renorm = {}
    for key in CLOTH_MESHES:
        o = bpy.data.objects.get(key)
        if not o:
            continue
        ng = 0
        for g in list(o.vertex_groups):
            if g.name.startswith(PREFIX):
                o.vertex_groups.remove(g)
                ng += 1
        n = 0
        for v in o.data.vertices:
            gs = [g for g in v.groups if g.weight > 1e-6]
            s = sum(g.weight for g in gs)
            if not gs or abs(s - 1.0) < 1e-4:
                continue
            for g in gs:
                o.vertex_groups[g.group].add([v.index], g.weight / s, "REPLACE")
            n += 1
        renorm[key] = {"groups_removed": ng, "verts_renormalized": n}
    out["meshes"] = renorm

    # 5) 移除我建立的測試動畫
    nact = []
    if arm.animation_data and arm.animation_data.action:
        a = arm.animation_data.action
        if a.name.startswith("ClothTest"):
            arm.animation_data.action = None
            nact.append(a.name)
    for a in list(bpy.data.actions):
        if a.name.startswith("ClothTest") and a.users == 0:
            bpy.data.actions.remove(a)
    out["actions_removed"] = nact

    # 6) 確認殘留
    out["remaining_cloth_bones"] = [b.name for b in arm.data.bones
                                    if b.name.startswith(PREFIX)]
    out["remaining_targets"] = [o.name for o in bpy.data.objects
                                if o.name.startswith("ClothTgt_")]
    out["armature_bone_count"] = len(arm.data.bones)
    print("UNDODONE" + json.dumps(out, ensure_ascii=False) + "UNDOEND")


main()
