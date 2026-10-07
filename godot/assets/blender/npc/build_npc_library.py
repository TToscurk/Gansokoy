"""P10 NPC Asset Library：roster の全 NPC を build_npc_tripo.py で GLB 化し、Godot 用ファイルを書く（再現可能）。
python build_npc_library.py [--godot-only] [id ...]
出力：godot/characters/npc/<id>/{<id>.glb, <id>.glb.import の _subresources, m_body.tres, (m_hair.tres), tex/, src/build_report.json}
  - 原 basecolor は形式を中身で判定してコピー（拡張子と中身が違う原画像あり：菜販人の .jpg は PNG）
  - Body と Hair が同じ atlas なら 1 枚だけ置き、両材質で共有
  - 骨格 family（npc_skeleton_maps.json）→ BoneMap（GeneralSkeleton＝SkeletonProfileHumanoid へ retarget）
"""
import hashlib, json, os, re, shutil, subprocess, sys
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
BLENDER = 'D:/Blender/blender-5.2.1-windows-x64/blender.exe'
roster = json.load(open(os.path.join(GODOT, 'characters/npc/npc_roster.json'), encoding='utf-8'))
maps = json.load(open(os.path.join(GODOT, 'characters/npc/_shared/npc_skeleton_maps.json'), encoding='utf-8'))
args = [a for a in sys.argv[1:] if not a.startswith('--')]
GODOT_ONLY = '--godot-only' in sys.argv
AUDIT_TEX = '--audit-tex' in sys.argv   # 骨架 ZIP の再ベイク貼圖を原版と比較（orig_blend がある NPC）；壊れていて uv_from 未設定なら FAIL
only = set(args)
fails = 0
if AUDIT_TEX:
    for n in roster['npcs']:
        if (only and n['id'] not in only) or not n.get('orig_blend'):
            continue
        outp = os.path.join(GODOT, 'characters/npc', n['id'], 'src', 'rig_texture_audit.json')
        os.makedirs(os.path.dirname(outp), exist_ok=True)
        subprocess.run([BLENDER, '-b', os.path.join(roster['src_root'], n['orig_blend']), '-P', os.path.join(HERE, 'npc_rig_texture_audit.py'), '--',
                        os.path.join(roster['src_root'], n['src']), outp], capture_output=True, text=True, encoding='utf-8', errors='replace')
        if not os.path.exists(outp):
            print('FAIL', n['id'], 'rig texture audit が結果を書かなかった')
            fails += 1
            continue
        a = json.load(open(outp, encoding='utf-8'))
        handled = bool(n.get('uv_from')) and '--ignore-uv-from' not in sys.argv   # 反向確認用
        bad = a['verdict'] != 'OK' and not handled
        fails += int(bad)
        print('%s %-13s rig texture %s%s  %s' % ('FAIL' if bad else 'OK  ', n['id'], a['verdict'], '（uv_from で原版を使用）' if handled and a['verdict'] != 'OK' else '',
              {k[:14]: (v.get('orig_rgb'), v.get('rig_rgb')) for k, v in a['parts'].items()}))
    sys.exit(1 if fails else 0)


def sha(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()


def family_of(cid):
    for fam, f in maps['families'].items():
        if cid in f['members']:
            return fam, f
    raise SystemExit('family 未登録: ' + cid)


MAT = '''[gd_resource type="StandardMaterial3D" load_steps=2 format=3]

[ext_resource type="Texture2D" path="res://{tex}" id="1_alb"]

[resource]
resource_name = "{name}"
albedo_texture = ExtResource("1_alb")
roughness = 1.0
metallic_specular = 0.25
'''

for n in roster['npcs']:
    cid = n['id']
    if only and cid not in only:
        continue
    d = os.path.join(GODOT, 'characters/npc', cid)
    for sub in ('tex', 'src'):
        os.makedirs(os.path.join(d, sub), exist_ok=True)
    src = os.path.join(roster['src_root'], n['src'])
    rep_p = os.path.join(d, 'src', 'build_report.json')
    if not GODOT_ONLY:
        extra = []
        if n.get('uv_from'):   # 骨架 ZIP の再ベイク atlas が壊れている NPC：原版 blend の UV＋原画像（build_npc_tripo.py が安全確認して STOP する）
            extra = ['--uv-from=' + os.path.join(roster['src_root'], n['uv_from'])]
        if n.get('apron_fix'):   # 前掛けの幾何クリアランス（roster に値を記録、build_npc_tripo.py → apron_fix.py）
            extra.append('--apron-fix=' + json.dumps(n['apron_fix']))
        r = subprocess.run([BLENDER, '-b', '-P', os.path.join(HERE, 'build_npc_tripo.py'), '--', src, str(n['height']),
                            os.path.join(d, cid + '.glb'), rep_p] + extra, capture_output=True, text=True, encoding='utf-8', errors='replace')
        if r.returncode != 0 or not os.path.exists(rep_p):
            print('FAIL', cid, r.stdout[-1500:], r.stderr[-1500:])
            fails += 1
            continue
    rep = json.load(open(rep_p, encoding='utf-8'))
    for f in os.listdir(os.path.join(d, 'tex')):
        if not f.endswith('.import'):
            os.remove(os.path.join(d, 'tex', f))
    copied = {}   # sha -> res path
    n_distinct = len(set(sha(p.get('texture_src') or p['texture']) for p in rep['parts'].values() if (p.get('texture_src') or p['texture']) and os.path.exists(p.get('texture_src') or p['texture'])))
    for part, p in rep['parts'].items():
        t = p.get('texture_src') or p['texture']
        if not t or not os.path.exists(t):
            fbm = os.path.splitext(src)[0] + '.fbm'
            cands = [os.path.join(fbm, f) for f in os.listdir(fbm)] if os.path.isdir(fbm) else []
            cands = [c for c in cands if any(k in os.path.basename(c).lower() for k in ('basecolor', 'rgb', 'image', 'diffuse'))]
            t = cands[0] if cands else None
        if not t:
            print('FAIL', cid, part, 'texture not found')
            fails += 1
            continue
        h = sha(t)
        if h not in copied:
            fmt = Image.open(t).format
            ext = {'JPEG': '.jpg', 'PNG': '.png'}[fmt]
            name = '%s_albedo%s' % (cid, ext) if n_distinct <= 1 else '%s_%s_albedo%s' % (cid, part.lower(), ext)
            shutil.copyfile(t, os.path.join(d, 'tex', name))
            copied[h] = 'characters/npc/%s/tex/%s' % (cid, name)
        p['texture_src'] = t
        p['texture_sha256'] = h
        p['texture_res'] = copied[h]
        p.pop('texture_copied', None)
        open(os.path.join(d, 'm_%s.tres' % part.lower()), 'w', encoding='utf-8', newline='\n').write(MAT.format(tex=copied[h], name='M_' + part))
    # 使われなくなった .import（旧ファイル名）を掃除
    live = set(os.path.basename(v) for v in copied.values())
    for f in os.listdir(os.path.join(d, 'tex')):
        if f.endswith('.import') and f[:-7] not in live:
            os.remove(os.path.join(d, 'tex', f))
    # runtime 解像度の上限（roster の texture_max_size；原画像はそのまま保持、Godot import の process/size_limit だけ）
    # ＋Godot が 3D 使用を検出して最終的に採る設定（GPU 圧縮 VRAM＋mipmap、detect_3d 済み）を最初から書く——封存状態を安定させる
    #   （使用者裁定 2026-10-06：審圖時の無圧縮・mipmap なしは暫定、正式は VRAM 圧縮＋mipmap）
    lim = int(n.get('texture_max_size', 0))
    for f in live:
        ip = os.path.join(d, 'tex', f + '.import')
        if os.path.exists(ip):
            s = open(ip, encoding='utf-8').read()
            s2 = re.sub(r'process/size_limit=\d+', 'process/size_limit=%d' % lim, s)
            s2 = re.sub(r'compress/mode=\d+', 'compress/mode=2', s2)
            s2 = re.sub(r'mipmaps/generate=\w+', 'mipmaps/generate=true', s2)
            s2 = re.sub(r'detect_3d/compress_to=\d+', 'detect_3d/compress_to=0', s2)
            if s2 != s:
                open(ip, 'w', encoding='utf-8', newline='\n').write(s2)
        elif lim:
            print('NOTE', cid, f, '.import 未生成（size_limit は godot --import 後に --godot-only で）')
    rep['texture_max_size'] = lim
    fam, f = family_of(cid)
    rep['skeleton_family'] = fam
    json.dump(rep, open(rep_p, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    # .glb.import：既存（Godot 生成）の _subresources だけ差し替え
    imp_p = os.path.join(d, cid + '.glb.import')
    mats = ',\n'.join('"M_%s": {\n"use_external/enabled": true,\n"use_external/fallback_path": "res://characters/npc/%s/m_%s.tres",\n"use_external/path": "res://characters/npc/%s/m_%s.tres"\n}' % (k, cid, k.lower(), cid, k.lower()) for k in sorted(rep['parts']))
    sub = '''_subresources={
"materials": {
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
}''' % (mats, f['bone_map'])
    if os.path.exists(imp_p):
        s = open(imp_p, encoding='utf-8').read()
        s2, k = re.subn(r'_subresources=\{.*?\n\}(?=\n[a-z_/]+=|\s*$)', lambda m: sub, s, flags=re.S)
        if k == 0:
            s2, k = re.subn(r'_subresources=\{\}', lambda m: sub, s)
        if k != 1:
            print('FAIL', cid, '.import の _subresources を置換できない')
            fails += 1
        else:
            open(imp_p, 'w', encoding='utf-8', newline='\n').write(s2)
    else:
        print('NOTE', cid, '.import 未生成（godot --import 後に --godot-only で再実行）')
    print('OK %-13s h %.3f feet %.4f tris %5d family %s parts %s tex %s' % (cid, rep['height_m'], rep['feet_z'], rep['total_tris'], fam,
          {k: v['tris'] for k, v in rep['parts'].items()}, list(copied.values())))
sys.exit(1 if fails else 0)
