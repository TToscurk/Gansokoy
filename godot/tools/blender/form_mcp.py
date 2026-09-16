"""日之呼吸四型 —— Blender MCP 手調工作庫（在開著的 Blender 裡 exec，接在 react_lib 之後）。

exec(open(r'D:/神社/shrine/godot/tools/blender/form_mcp.py', encoding='utf-8').read(), globals())

做法：身體（軀幹／腿／髖）沿用 make_form_clips.py 的姿勢表；**手臂改用 IK 對刀尖**——
右手 IK 到指定世界座標、刀向用 aim_sword 搜尋、左手貼柄，再 bake 成 FK 存 pose。
每個 key 一個 pose tag（存在骨架 custom props），最後 author_clip + export_react_glb。
座標：骨架空間 -Y 前、+Z 上、+X 角色左手側，單位公尺。
"""
import bpy, os, math
from mathutils import Vector, Quaternion

_HERE = r"D:/神社/shrine/godot/tools/blender"
_src = open(os.path.join(_HERE, "make_form_clips.py"), encoding="utf-8").read().split("rc.main(")[0]
FORM_NS = {"__file__": os.path.join(_HERE, "make_form_clips.py")}
exec(_src, FORM_NS)
ARM_BONES = ("RightShoulder", "RightArm", "RightForeArm", "RightHand", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand")


def _interp(entries, f):
    pts = [(ff, d) for ff, _, d in entries]
    if f <= pts[0][0]:
        return pts[0][1]
    if f >= pts[-1][0]:
        return pts[-1][1]
    for (f0, d0), (f1, d1) in zip(pts, pts[1:]):
        if f0 <= f <= f1:
            t = (f - f0) / max(f1 - f0, 1)
            t = t * t * (3 - 2 * t)
            return d0 + (d1 - d0) * t


def apply_body(poses, hips_z, f, skip_arms=True):
    """姿勢表 → 目前 pose（可略過手臂，留給 IK）。"""
    reset_to_base()
    per = {}
    for key, entries in poses.items():
        per.setdefault(key.split(".")[0], []).append(entries)
    for bone, lists in per.items():
        if skip_arms and bone in ARM_BONES:
            continue
        q = BASE[bone][0].copy()
        for entries in lists:
            q = q @ Quaternion(Vector(entries[0][1]).normalized(), math.radians(_interp(entries, f)))
        P[bone].rotation_quaternion = q
    dz = hips_z[0][1]
    for (f0, d0), (f1, d1) in zip(hips_z, hips_z[1:]):
        if f0 <= f <= f1:
            dz = d0 + (d1 - d0) * (f - f0) / max(f1 - f0, 1)
    if f >= hips_z[-1][0]:
        dz = hips_z[-1][1]
    set_hips_dz(dz)
    bpy.context.view_layer.update()


def apply_table_bones(poses, f, bones):
    """只把姿勢表裡指定骨頭的旋轉套上（給 IK 搆不到柄的左臂用）。"""
    per = {}
    for key, entries in poses.items():
        b = key.split(".")[0]
        if b in bones:
            per.setdefault(b, []).append(entries)
    for bone, lists in per.items():
        q = BASE[bone][0].copy()
        for entries in lists:
            q = q @ Quaternion(Vector(entries[0][1]).normalized(), math.radians(_interp(entries, f)))
        P[bone].rotation_quaternion = q
    bpy.context.view_layer.update()


def pose_key(tag, poses, hips_z, f, rh=None, sword_dir=None, left_on_hilt=True, extra=None):
    """一個關鍵姿：身體照表、右手 IK 到 rh（公尺，骨架空間）、刀向 sword_dir、左手貼柄，bake → save_pose(tag)。
    rh=None 表示手臂也照表（例如首尾 Idle 幀）。extra = [(bone, axis, deg)] 額外疊加。"""
    ensure_ik()
    ik_mute(True)
    apply_body(poses, hips_z, f, skip_arms=rh is not None)
    for b, ax, dg in (extra or []):
        rot(b, ax, dg)
    if rh is not None:
        ik_mute(False)
        ik_to("IK_R", Vector(rh))
        ik_to("IK_L", W(P["LeftHand"].head))
        bpy.context.view_layer.update()
        if sword_dir is not None:
            aim_sword(sword_dir)
        if left_on_hilt:
            left_hand_on_hilt()
            align_left_wrist_to_right()
        bake_ik_to_fk()
    save_pose(tag)
    return report(tag)


def build_and_export(clip_name, keys, last, glb_out):
    """keys = {frame: tag}。回傳 GLB 路徑。多個 clip 時分次呼叫 author_clip，最後一次 export。"""
    author_clip(clip_name, keys, last)
    return clip_name


def form_table(name):
    for n, poses, hz, last in FORM_NS["CLIPS"]:
        if n == name:
            return poses, hz, last
    raise KeyError(name)


print("form_mcp ready; clips", [c[0] for c in FORM_NS["CLIPS"]])
