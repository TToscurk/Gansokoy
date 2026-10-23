extends SceneTree
## R7 REF09 MX：把重定向後的 twist_flip（目標骨架上）逐格（30 fps）輸出成骨架空間全域變換 JSON，供 Blender 作者腳本讀取。
## 只讀資源，不寫任何 .res/.tscn。
##   godot --headless --path godot -s res://tools/yoriichi_r7/dump_ref09_mx_src.gd -- <anim_res> <out_json_abs>
const PLAYER := "res://characters/yoriichi/player_yoriichi_r7k.tscn"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var a := load(args[0]) as Animation
	var p: Node = (load(PLAYER) as PackedScene).instantiate()
	root.add_child(p)
	await process_frame
	var sk := p.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bones := []
	for i in sk.get_bone_count():
		if sk.get_bone_name(i).begins_with("mixamorig_"):
			bones.append(i)
	var rest := {}
	for i in sk.get_bone_count():
		var pi := sk.get_bone_parent(i)
		rest[i] = (rest[pi] as Transform3D) * sk.get_bone_rest(i) if pi >= 0 else sk.get_bone_rest(i)
	var tracks := {}
	for t in a.get_track_count():
		var path := str(a.track_get_path(t))
		var c := path.rfind(":")
		var bi := sk.find_bone(path.substr(c + 1))
		if bi >= 0:
			tracks[[bi, a.track_get_type(t)]] = t
	var n := int(round(a.length * 30.0)) + 1
	var frames := []
	for f in n:
		var tt := minf(f / 30.0, a.length)
		var g := {}
		for i in sk.get_bone_count():
			var loc: Transform3D = sk.get_bone_rest(i)
			if tracks.has([i, Animation.TYPE_ROTATION_3D]):
				loc.basis = Basis(a.rotation_track_interpolate(tracks[[i, Animation.TYPE_ROTATION_3D]], tt)).scaled(loc.basis.get_scale())
			if tracks.has([i, Animation.TYPE_POSITION_3D]):
				loc.origin = a.position_track_interpolate(tracks[[i, Animation.TYPE_POSITION_3D]], tt)
			var pi := sk.get_bone_parent(i)
			g[i] = (g[pi] as Transform3D) * loc if pi >= 0 else loc
		var row := {}
		for i in bones:
			var x: Transform3D = g[i]
			var q := x.basis.orthonormalized().get_rotation_quaternion()
			row[sk.get_bone_name(i).trim_prefix("mixamorig_")] = [x.origin.x, x.origin.y, x.origin.z, q.x, q.y, q.z, q.w]
		frames.append(row)
	var rrow := {}
	for i in bones:
		var x: Transform3D = rest[i]
		var q := x.basis.orthonormalized().get_rotation_quaternion()
		rrow[sk.get_bone_name(i).trim_prefix("mixamorig_")] = [x.origin.x, x.origin.y, x.origin.z, q.x, q.y, q.z, q.w]
	var skx := sk.global_transform
	var f := FileAccess.open(args[1], FileAccess.WRITE)
	f.store_string(JSON.stringify({"fps": 30, "n": n, "length": a.length, "rest": rrow, "frames": frames,
		"sk_basis": [skx.basis.x.x, skx.basis.x.y, skx.basis.x.z, skx.basis.y.x, skx.basis.y.y, skx.basis.y.z, skx.basis.z.x, skx.basis.z.y, skx.basis.z.z],
		"sk_origin": [skx.origin.x, skx.origin.y, skx.origin.z]}))
	f.close()
	print("DUMP_OK n=", n, " bones=", bones.size())
	quit()
