"""慧音：Mixamo FBX（Keine_Mixamo 上傳角色＝與 keine.glb 骨架 rest 不同）→ 帶「自己骨架」的動作 GLB。
不把動作 bake 到 keine.glb 上（build_npc_mixamo_anim.py 以世界姿勢複製，要求兩邊 rest 相同；
這裡 Hips rest 差 90°，結果腿相對骨盆轉 90°）。改由 Godot import 的 retarget（bone map＋rest fixer）對應到 GeneralSkeleton。
blender -b -P export_keine_mixamo_clips.py -- <out.glb> <name>=<clip.fbx> [...]
"""
import bpy, sys
argv = sys.argv[sys.argv.index('--') + 1:]
OUT, PAIRS = argv[0], [a.split('=', 1) for a in argv[1:]]
bpy.ops.wm.read_factory_settings(use_empty=True)
tgt = None
done = []
for name, path in PAIRS:
    before_o, before_a = set(bpy.data.objects), set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=False)
    new_o = [o for o in bpy.data.objects if o not in before_o]
    src = next(o for o in new_o if o.type == 'ARMATURE')
    acts = [a for a in bpy.data.actions if a not in before_a]
    act = max(acts, key=lambda a: a.frame_range[1] - a.frame_range[0])
    for a in acts:
        if a is not act:
            bpy.data.actions.remove(a)
    act.name = name
    act.use_fake_user = True
    if tgt is None:
        tgt = src
        tgt.name = 'Armature'
        for o in new_o:
            if o is not src:
                bpy.data.objects.remove(o, do_unlink=True)
    else:
        for o in new_o:
            bpy.data.objects.remove(o, do_unlink=True)
    done.append((name, int(act.frame_range[0]), int(act.frame_range[1])))
# 每個 action 一條 NLA track（glTF 匯出 ACTIONS 模式各自成為一支動畫）
tgt.animation_data_create()
tgt.animation_data.action = None
for name, f0, f1 in done:
    tr = tgt.animation_data.nla_tracks.new()
    tr.name = name
    st = tr.strips.new(name, f0, bpy.data.actions[name])
    st.name = name
for pb in tgt.pose.bones:
    pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.rotation_euler = (0, 0, 0); pb.scale = (1, 1, 1)
for o in list(bpy.data.objects):
    if o is not None and o.name in bpy.context.view_layer.objects:
        o.select_set(o is tgt)
bpy.context.view_layer.objects.active = tgt
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_animations=True,
                          export_animation_mode='ACTIONS', export_anim_single_armature=True, export_skins=True,
                          export_yup=True, export_force_sampling=True, export_frame_step=1)
print('DONE', done)
