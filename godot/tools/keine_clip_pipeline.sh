#!/usr/bin/env bash
# 慧音 Mixamo clip 全流程（r3）：src/*.fbx → FBX 連同自己的骨架轉 keine_mixamo_clips.glb（不 bake 到 keine.glb：rest 不同會讓腿相對骨盆轉 90°）
# → Godot import(retarget+save_to_file <clip>_mx.res) → 平滑接地 <clip>_final.res；walk 實際用茶屋來源 FemWalk2（同一動作、量測較佳）
# 注意：tools 會載入 keine.tscn，跑之前 tscn 指向的 clip 必須存在（缺檔時先指到 *_mx.res）
# 用法：bash godot/tools/keine_clip_pipeline.sh   （在 repo 根目錄或任意處）
set -e
# 參數 1＝角色 id（預設 keine；akyuu 等同 mixamo65 family 的角色共用：characters/<id>/anim/src/*.fbx → <id>_mixamo_clips.glb → <clip>_final.res）
CH="${1:-keine}"
G="D:/神社/shrine/godot"
GD="D:/Godot/Godot_v4.7.2-stable_win64_console.exe"
BL="D:/Blender/blender-5.2.1-windows-x64/blender.exe"
A="$G/characters/$CH/anim"
cd "$G"
PAIRS=()
CLIPS=()
for f in "$A"/src/*.fbx; do n=$(basename "$f" .fbx); PAIRS+=("$n=$f"); CLIPS+=("$n"); done
"$BL" -b -P assets/blender/keine/export_keine_mixamo_clips.py -- "$A/${CH}_mixamo_clips.glb" "${PAIRS[@]}" > "$TMPDIR/${CH}_clips.log" 2>&1
grep -o "DONE.*" "$TMPDIR/${CH}_clips.log" | cut -c1-300
timeout 500 "$GD" --headless --path . --import > /dev/null 2>&1 || true
python - "$A/${CH}_mixamo_clips.glb.import" "$CH" "${CLIPS[@]}" <<'PY'
import re, sys
imp, ch, clips = sys.argv[1], sys.argv[2], sys.argv[3:]
s = open(imp, encoding='utf-8').read()
anims = ',\n'.join('"%s": {"settings/loop_mode": 1, "save_to_file/enabled": true, "save_to_file/keep_custom_tracks": false, "save_to_file/path": "res://characters/%s/anim/%s_mx.res"}' % (c, ch, c) for c in clips)
sub = '''_subresources={
"animations": {
%s
},
"nodes": {
"PATH:Armature/Skeleton3D": {
"retarget/bone_map": Resource("res://characters/npc/_shared/npc_tripo_65_map.tres"),
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
}''' % anims
s2, k = re.subn(r'_subresources=\{.*?\n\}(?=\n[a-z_/]+=|\s*$)', lambda m: sub, s, flags=re.S)
if k == 0:
    s2, k = re.subn(r'_subresources=\{\}', lambda m: sub, s)
assert k == 1, 'subresources replace failed'
open(imp, 'w', encoding='utf-8', newline='\n').write(s2)
print('IMPORTCFG', len(clips))
PY
timeout 500 "$GD" --headless --path . --import > /dev/null 2>&1 || true
for c in "${CLIPS[@]}"; do
  case "$c" in walk_*) SG="--sigma=0.06 --tol=0.008 --resmooth=0.05" ;;
    # 跪姿：腳背平貼地，腳骨不能當接地基準 → 用 Godot 網格最低點量得的固定抬高（阿求 2026-10-19：身體／鞋最低 −1.9／−1.3 cm）
    kneel_idle_*) SG="--fixed=0.019" ;; kneel_pray_*) SG="--fixed=0.013" ;;
    *) SG="--sigma=0.05" ;; esac
  timeout 120 "$GD" --headless --path . --script res://tools/build_keine_anim_grounded.gd -- --npc=res://characters/$CH/$CH.tscn --clip=res://characters/$CH/anim/${c}_mx.res --out=res://characters/$CH/anim/${c}_final.res $SG 2>&1 | grep -o "KGROUND.*m save [0-9]"
done
if [ "$CH" = keine ]; then
cp characters/npc/chaya_f01/anim/walk_femwalk2_a030.res "$A/walk_femwalk2_a030.res"
timeout 120 "$GD" --headless --path . --script res://tools/build_keine_anim_grounded.gd -- --clip=res://characters/keine/anim/walk_femwalk2_a030.res --out=res://characters/keine/anim/walk_femwalk2_a030_final.res --sigma=0.06 --tol=0.008 --resmooth=0.05 2>&1 | grep -o "KGROUND.*m save [0-9]"
fi
