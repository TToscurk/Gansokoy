extends SceneTree
## R7 P4 十三型審計（唯讀）：關閉 AnimationTree，逐 authored 格 seek AnimationPlayer，等兩個 process frame 後讀骨架。
## 輸出 user://r7p4_form13_poses.json：每型每格（visual 本地）雙手、雙腳、骨盆、頭、胸、刀尖、刀根；另含 metadata。
const PLAYER := "res://characters/yoriichi/player_yoriichi_r7k.tscn"
const ORDER := [1, 2, 3, 11, 10, 4, 8, 6, 5, 7, 9, 12]
const BONES := ["mixamorig_Hips", "mixamorig_Head", "mixamorig_LeftHand", "mixamorig_RightHand", "mixamorig_LeftFoot", "mixamorig_RightFoot", "mixamorig_Spine2"]

func _initialize() -> void:
	call_deferred("_run")

func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]

func _run() -> void:
	var w := Node3D.new()
	root.add_child(w)
	var p: CharacterBody3D = (load(PLAYER) as PackedScene).instantiate()
	p.set("r7_vfx_enabled", false)
	w.add_child(p)
	p.set_physics_process(false)
	await process_frame
	print("ref09_variant=", p.get("r7_ref09_variant"), " env=[", OS.get_environment("R7_REF09_VARIANT"), "]")
	var tree: AnimationTree = p.get("_tree")
	tree.active = false
	var anim: AnimationPlayer = p.get("_anim")
	var forms: Dictionary = p.get("R7_FORMS")
	var vis: Node3D = p.get("_visual")
	var sk: Skeleton3D = vis.find_children("*", "Skeleton3D", true, false)[0]
	var tip: Node3D = p.get("_blade_tip")
	var base: Node3D = p.get("_blade_base")
	var out := {}
	for id in ORDER:
		var d: Dictionary = forms[id]
		var a: Animation = anim.get_animation(d.anim)
		var n := int(round(a.length * 30.0))
		var frames := []
		anim.play(d.anim)
		anim.speed_scale = 0.0
		for f in n + 1:
			anim.seek(minf(f / 30.0, a.length), true)
			await process_frame
			await process_frame
			var inv := vis.global_transform.affine_inverse()
			var row := {}
			for bn in BONES:
				row[bn.trim_prefix("mixamorig_")] = _v(inv * (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bn)).origin))
			var hb := sk.get_bone_global_pose(sk.find_bone("mixamorig_Hips")).basis
			row.hips_fwd = _v((inv.basis * (sk.global_transform.basis * hb)).z.normalized())
			if tip != null and base != null:
				row.tip = _v(inv * tip.global_position)
				row.base = _v(inv * base.global_position)
			frames.append(row)
		out[str(id)] = {"ref": d.ref, "anim": d.anim, "frames": n, "cancel_ratio": d.cancel, "fade": d.fade, "air": d.get("air", false),
			"hits": a.get_meta("r7_hit_windows", [a.get_meta("r7_hit_window", [-1, -1])]),
			"contact": a.get_meta("r7_contact_frame", -1), "takeoff": a.get_meta("r7_takeoff_frame", -1), "poses": frames}
		print(d.ref, " ", d.anim, " n=", n, " f0 tip=", frames[0].get("tip"), " end tip=", frames[-1].get("tip"))
	var fo := FileAccess.open("user://r7p4_form13_poses.json", FileAccess.WRITE)
	fo.store_string(JSON.stringify(out))
	fo.close()
	print("WROTE ", ProjectSettings.globalize_path("user://r7p4_form13_poses.json"))
	quit(0)
