"""P10 R3a NPC：Mixamo の動作 FBX（NPC 本体を上傳して書き出した＝同じ骨格・同じ rest）を、
NPC の glTF 骨格へ「骨ごとの世界姿勢」で写して bake し、骨格＋動作だけの GLB にまとめる。
Mixamo FBX は root の移動・回転を Armature オブジェクトのトラックに載せてくるため（Godot では Hips 位置トラックが無くなる）、
世界姿勢で写すことで Hips の移動に変換する。手修正はしない。
blender -b -P build_npc_mixamo_anim.py -- <chonin_m01.glb> <out.glb> <name>=<clip.fbx> [<name>=<clip.fbx> ...]
"""
import bpy, sys
argv = sys.argv[sys.argv.index('--') + 1:]
RIG, OUT, PAIRS = argv[0], argv[1], [a.split('=', 1) for a in argv[2:]]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=RIG)
for o in list(bpy.data.objects):
    if o.type != 'ARMATURE':
        bpy.data.objects.remove(o, do_unlink=True)
tgt = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
tgt.name = 'Armature'
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
tgt.animation_data_create()
baked = []
for name, path in PAIRS:
    before_o, before_a = set(bpy.data.objects), set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=path)
    new_o = [o for o in bpy.data.objects if o not in before_o]
    src = next(o for o in new_o if o.type == 'ARMATURE')
    act = max([a for a in bpy.data.actions if a not in before_a], key=lambda a: a.frame_range[1] - a.frame_range[0])
    src.animation_data_create()
    src.animation_data.action = act
    try:
        src.animation_data.action_slot = act.slots[0]
    except Exception:
        pass
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    bpy.ops.object.select_all(action='DESELECT')
    tgt.select_set(True)
    bpy.context.view_layer.objects.active = tgt
    bpy.ops.object.mode_set(mode='POSE')
    for pb in tgt.pose.bones:
        pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.scale = (1, 1, 1)
        if pb.name in src.pose.bones and pb.name != 'BoneRoot':   # BoneRoot は床に固定（root の移動は Hip が世界姿勢で受ける）
            c = pb.constraints.new('COPY_TRANSFORMS')
            c.target = src
            c.subtarget = pb.name
            c.target_space = 'WORLD'
            c.owner_space = 'WORLD'
    tgt.animation_data.action = None
    bpy.ops.pose.select_all(action='SELECT')
    bpy.ops.nla.bake(frame_start=f0, frame_end=f1, only_selected=False, visual_keying=True, clear_constraints=True,
                     use_current_action=False, bake_types={'POSE'})
    bpy.ops.object.mode_set(mode='OBJECT')
    out_act = tgt.animation_data.action
    out_act.name = name
    out_act.use_fake_user = True
    tgt.animation_data.action = None
    for o in new_o:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.actions.remove(act)
    for a in [a for a in bpy.data.actions if a not in before_a and a.name != name]:
        bpy.data.actions.remove(a)
    baked.append((name, f0, f1))
    print('BAKED', name, f0, f1)
tgt.animation_data.action = bpy.data.actions.get(baked[0][0])
bpy.ops.object.select_all(action='DESELECT')
tgt.select_set(True)
bpy.context.scene.render.fps = 30
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_animations=True,
                          export_animation_mode='ACTIONS', export_yup=True, export_force_sampling=True)
print('DONE', baked)
