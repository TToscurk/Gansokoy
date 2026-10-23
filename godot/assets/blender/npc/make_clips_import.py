"""Write the Godot .import for a clips GLB built by build_mixamo65_clips_glb.py (same settings as akyuu_mixamo_clips.glb.import).
python make_clips_import.py <res-dir e.g. res://characters/npc/_shared/anim/talk> <glb filename> <res_suffix e.g. _mx> <clip> [<clip> ...]
Each clip is saved to <res-dir>/<clip><suffix>.res (loop_mode linear; the actors set loop per use).
"""
import sys, os
resdir, glb, suffix, clips = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
proj = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))  # godot/
path = os.path.join(proj, resdir.replace('res://', ''), glb + '.import')
anims = ',\n'.join('"%s": {\n"save_to_file/enabled": true,\n"save_to_file/fallback_path": "%s/%s%s.res",\n"save_to_file/keep_custom_tracks": false,\n"save_to_file/path": "%s/%s%s.res",\n"settings/loop_mode": 1,\n"slices/amount": 0\n}' % (c, resdir, c, suffix, resdir, c, suffix) for c in clips)
txt = '''[remap]

importer="scene"
importer_version=1
type="PackedScene"

[deps]

source_file="%s/%s"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/root_script=null
mesh_library/use_node_names_as_mesh_names=false
array_mesh/deduplicate_surfaces=true
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=true
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path=""
materials/extract=0
materials/extract_format=0
materials/extract_path=""
_subresources={
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
}
gltf/naming_version=2
gltf/embedded_image_handling=1
gltf/texture_map_mode=1
''' % (resdir, glb, anims)
open(path, 'w', encoding='utf-8', newline='\n').write(txt)
print('WROTE', path, len(clips))
