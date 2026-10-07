"""P10 NPC Asset Library：Mixamo 動作 FBX（各 NPC を Mixamo に上傳して書き出し＝各自の骨格）→ NPC ごとの anim GLB → Godot 取り込み設定。
python build_npc_library_anim.py bake [id ...]      Blender で world 姿勢 bake → characters/npc/<id>/anim/<id>_anim.glb
python build_npc_library_anim.py import [id ...]    <id>_anim.glb.import の _subresources（retarget＋save_to_file）を書く（godot --import 後に実行）
FBX：characters/npc/<id>/anim/src/<clip>.fbx（.gdignore）、clip＝idle_neutral_a015 … walk_standard_a045
"""
import json, os, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
BLENDER = 'D:/Blender/blender-5.2.1-windows-x64/blender.exe'
roster = json.load(open(os.path.join(GODOT, 'characters/npc/npc_roster.json'), encoding='utf-8'))
maps = json.load(open(os.path.join(GODOT, 'characters/npc/_shared/npc_skeleton_maps.json'), encoding='utf-8'))
mode = sys.argv[1]
only = set(sys.argv[2:])
# CLIPS はキャラごとに src/ から決める
fails = 0
for n in roster['npcs']:
    cid = n['id']
    if only and cid not in only:
        continue
    d = os.path.join(GODOT, 'characters/npc', cid, 'anim')
    fam = next(f for f in maps['families'].values() if cid in f['members'])
    # 取り込む clip＝src/ にある Mixamo FBX 全部（基準 6 本＋必要に応じた代替 walk・中間 arm-space）
    CLIPS = sorted(os.path.splitext(f)[0] for f in os.listdir(os.path.join(d, 'src')) if f.endswith('.fbx'))
    if mode == 'bake':
        pairs = ['%s=%s' % (c, os.path.join(d, 'src', c + '.fbx')) for c in CLIPS]
        if len(pairs) < 6:
            print('FAIL', cid, 'FBX が揃っていない', len(pairs))
            fails += 1
            continue
        r = subprocess.run([BLENDER, '-b', '-P', os.path.join(HERE, 'build_npc_mixamo_anim.py'), '--',
                            os.path.join(GODOT, 'characters/npc', cid, cid + '.glb'), os.path.join(d, cid + '_anim.glb')] + pairs,
                           capture_output=True, text=True, encoding='utf-8', errors='replace')
        done = [l for l in r.stdout.splitlines() if l.startswith('DONE')]
        if r.returncode != 0 or not done:
            print('FAIL', cid, r.stdout[-1200:], r.stderr[-800:])
            fails += 1
            continue
        print('BAKED', cid, done[0][:160])
    elif mode == 'tscn':
        # roster の選定（idle_clip／walk_clip）で <id>.tscn を書く（npc_visual.gd＋glb）
        if not n.get('idle_clip') or not n.get('walk_clip'):
            print('FAIL', cid, 'roster に idle_clip／walk_clip が無い')
            fails += 1
            continue
        node = ''.join(w.capitalize() for w in cid.split('_'))
        tscn = '''[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://characters/npc/npc_visual.gd" id="1_vis"]
[ext_resource type="PackedScene" path="res://characters/npc/%s/%s.glb" id="2_glb"]

[node name="NPC_%s" type="Node3D"]
script = ExtResource("1_vis")
idle_clip = "%s"
walk_clip = "%s"

[node name="Model" parent="." instance=ExtResource("2_glb")]
''' % (cid, cid, node, n['idle_clip'], n['walk_clip'])
        open(os.path.join(GODOT, 'characters/npc', cid, cid + '.tscn'), 'w', encoding='utf-8', newline='\n').write(tscn)
        print('TSCN', cid, os.path.basename(n['idle_clip']), os.path.basename(n['walk_clip']))
    elif mode == 'import':
        imp = os.path.join(d, cid + '_anim.glb.import')
        if not os.path.exists(imp):
            print('FAIL', cid, '.import 未生成')
            fails += 1
            continue
        anims = ',\n'.join('"%s": {"settings/loop_mode": 1, "save_to_file/enabled": true, "save_to_file/keep_custom_tracks": false, "save_to_file/path": "res://characters/npc/%s/anim/%s.res"}' % (c, cid, c) for c in CLIPS)
        sub = '''_subresources={
"animations": {
%s
},
"nodes": {
"PATH:Armature/Skeleton3D": {
"retarget/bone_map": Resource("res://characters/npc/_shared/%s.tres"),
"retarget/bone_renamer/rename_bones": true,
"retarget/bone_renamer/unique_node/make_unique": true,
"retarget/bone_renamer/unique_node/skeleton_name": "GeneralSkeleton",
"retarget/remove_tracks/except_bone_transform": false,
"retarget/remove_tracks/unimportant_positions": true,
"retarget/remove_tracks/unmapped_bones": true,
"retarget/rest_fixer/apply_node_transforms": true,
"retarget/rest_fixer/fix_silhouette/enable": false,
"retarget/rest_fixer/normalize_position_tracks": true,
"retarget/rest_fixer/overwrite_axis": true
}
}
}''' % (anims, fam['bone_map'])
        s = open(imp, encoding='utf-8').read()
        s2, k = re.subn(r'_subresources=\{.*?\n\}(?=\n[a-z_/]+=|\s*$)', lambda m: sub, s, flags=re.S)
        if k == 0:
            s2, k = re.subn(r'_subresources=\{\}', lambda m: sub, s)
        if k != 1:
            print('FAIL', cid, '_subresources 置換不可')
            fails += 1
            continue
        open(imp, 'w', encoding='utf-8', newline='\n').write(s2)
        print('IMPORTCFG', cid, fam['bone_map'])
sys.exit(1 if fails else 0)
