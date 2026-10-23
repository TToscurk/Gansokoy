"""Mixamo 65 骨（mixamorig）動作 FBX → 只含骨架＋動作的 GLB（給 Godot 用 npc_tripo_65_map 重定向成 GeneralSkeleton）。
用途：用「上傳到 Mixamo 的 mixamorig 角色」（例：阿求 0e6afbff…）下載的 skin:false FBX，批次合成一個 GLB，
Godot 匯入設定照 characters/akyuu/anim/akyuu_mixamo_clips.glb.import（bone_map＝npc_tripo_65_map、save_to_file 每支 .res）。
blender -b -P build_mixamo65_clips_glb.py -- <out.glb> <name>=<clip.fbx> [<name>=<clip.fbx> ...]
不改骨架、不修動作；每支 action 只是改名後放進 NLA，glTF 以 ACTIONS 模式各自輸出。
"""
import bpy, sys
argv = sys.argv[sys.argv.index('--') + 1:]
OUT, PAIRS = argv[0], [a.split('=', 1) for a in argv[1:]]
bpy.ops.wm.read_factory_settings(use_empty=True)
base = None
acts = []
for name, path in PAIRS:
    before_o, before_a = set(bpy.data.objects), set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=path)
    new_o = [o for o in bpy.data.objects if o not in before_o]
    arm = next(o for o in new_o if o.type == 'ARMATURE')
    act = max([a for a in bpy.data.actions if a not in before_a], key=lambda a: a.frame_range[1] - a.frame_range[0])
    act.name = name
    act.use_fake_user = True
    acts.append(act)
    for a in [a for a in bpy.data.actions if a not in before_a and a is not act]:
        bpy.data.actions.remove(a)
    if base is None:
        base = arm
        base.name = 'Armature'
        assert abs(base.scale[0] - 1.0) < 1e-6, 'armature scale %s' % tuple(base.scale)
        for o in new_o:
            if o is not base:
                bpy.data.objects.remove(o, do_unlink=True)
    else:
        assert len(arm.data.bones) == len(base.data.bones), (name, len(arm.data.bones))
        for o in new_o:
            bpy.data.objects.remove(o, do_unlink=True)
ad = base.animation_data or base.animation_data_create()
ad.action = None
for tr in list(ad.nla_tracks):
    ad.nla_tracks.remove(tr)
for act in acts:
    tr = ad.nla_tracks.new(); tr.name = act.name; tr.mute = False
    st = tr.strips.new(act.name, int(act.frame_range[0]), act)
    try:
        st.action_slot = act.slots[0]
    except Exception:
        pass
bpy.context.view_layer.objects.active = base
base.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_animations=True,
                          export_animation_mode='ACTIONS', export_force_sampling=True, export_frame_step=1,
                          export_anim_single_armature=True, export_def_bones=False, export_yup=True, export_skins=True)
print('BUILT', OUT, [(a.name, tuple(a.frame_range)) for a in acts])
