extends SceneTree
## 把某支 clip 某一格的骨姿輸出成 JSON（給 Blender 布料模擬用）：每骨的 mixamorig 原名、骨架空間位置、
## 以及「世界旋轉差量」D = 姿勢全域旋轉 × 靜止全域旋轉⁻¹（與各骨本地軸無關，Blender 端可直接套到自己的 rest 上）。
## 單一時間：{bone: {...}}；多個時間（逗號分隔，或 all＝30 fps 全片）：{"times": [...], "frames": [{bone: {...}}, ...]}
## godot --headless --path . -s res://tools/akyuu/export_akyuu_pose_json.gd -- <clip.res> <t|t1,t2,…|all> <out.json>
func _initialize() -> void: _go.call_deferred()

func _go() -> void:
	var a := OS.get_cmdline_user_args()
	var m: Node3D = (load("res://characters/akyuu/akyuu.glb") as PackedScene).instantiate(); root.add_child(m)
	var sk: Skeleton3D = m.find_child("GeneralSkeleton", true, false)
	var ap := AnimationPlayer.new(); m.add_child(ap); ap.root_node = NodePath("../Armature")
	var clip: Animation = load(a[0])
	var lib := AnimationLibrary.new(); lib.add_animation(&"c", clip); ap.add_animation_library(&"", lib); ap.play(&"c"); ap.speed_scale = 0.0
	var bm: BoneMap = load("res://characters/npc/_shared/npc_tripo_65_map.tres")
	var times := []
	if a[1] == "all":
		var nf := int(round(clip.length * 30.0)) + 1
		for f in nf: times.append(minf(f / 30.0, clip.length))
	else:
		for s in a[1].split(","): times.append(float(s))
	var frames := []
	for t in times:
		ap.seek(t, true)
		await process_frame
		var out := {}
		for b in sk.get_bone_count():
			var n := sk.get_bone_name(b)
			var src := str(bm.get_skeleton_bone_name(StringName(n)))
			if src == "": src = n
			src = src.replace("mixamorig_", "mixamorig:")
			var gp := sk.get_bone_global_pose(b); var gr := sk.get_bone_global_rest(b)
			var D := gp.basis.orthonormalized() * gr.basis.orthonormalized().inverse()
			var q := D.get_rotation_quaternion()
			out[src] = {"godot": n, "pos": [gp.origin.x, gp.origin.y, gp.origin.z], "rest_pos": [gr.origin.x, gr.origin.y, gr.origin.z], "dq_xyzw": [q.x, q.y, q.z, q.w]}
		frames.append(out)
	var data = frames[0] if times.size() == 1 else {"times": times, "frames": frames}
	var fo := FileAccess.open(a[2], FileAccess.WRITE); fo.store_string(JSON.stringify(data)); fo.close()
	print("POSE bones ", frames[0].size(), " frames ", frames.size(), " → ", a[2])
	quit()
