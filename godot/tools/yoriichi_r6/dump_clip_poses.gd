extends SceneTree
## R6：把正式 Animation 資源逐格取樣到 v2.4 骨架上，輸出骨架空間全骨 global pose（格式同 capture_r6.gd 的 poses.json），
## 供 Blender 端改手臂（左手按鞘）後重新匯出。只讀資源，不改任何正式檔。
##   godot --headless --path . -s res://tools/yoriichi_r6/dump_clip_poses.gd -- res://...jump_up.res,res://...fall.res  <out_dir>
const GLB := "res://characters/yoriichi/v24/yoriichi_v24.glb"

func _xf12(t: Transform3D) -> Array:
	var b := t.basis
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, t.origin.x, t.origin.y, t.origin.z]

func _glob(sk: Skeleton3D, bi: int, cache: Dictionary) -> Transform3D:
	if cache.has(bi):
		return cache[bi]
	var local := Transform3D(Basis(sk.get_bone_pose_rotation(bi)).scaled(sk.get_bone_pose_scale(bi)), sk.get_bone_pose_position(bi))
	var p := sk.get_bone_parent(bi)
	var g := local if p < 0 else _glob(sk, p, cache) * local
	cache[bi] = g
	return g

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var clips: PackedStringArray = args[0].split(",")
	var out_dir: String = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var inst: Node3D = (load(GLB) as PackedScene).instantiate()
	root.add_child(inst)
	var sk := inst.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for c in clips:
		var a: Animation = load(c)
		var nm := c.get_file().get_basename()
		var fps := 30.0
		var n := int(round(a.length * fps)) + 1
		var frames: Array = []
		for i in n:
			var t := minf(float(i) / fps, a.length)
			# 直接內插軌道（不經 AnimationPlayer，headless 下確定性取樣）
			for bi in sk.get_bone_count():
				sk.set_bone_pose_rotation(bi, sk.get_bone_rest(bi).basis.get_rotation_quaternion())
				sk.set_bone_pose_position(bi, sk.get_bone_rest(bi).origin)
			for ti in a.get_track_count():
				var bn := str(a.track_get_path(ti)).get_slice(":", 1)
				var bi := sk.find_bone(bn)
				if bi < 0:
					continue
				var ty := a.track_get_type(ti)
				if ty == Animation.TYPE_ROTATION_3D:
					sk.set_bone_pose_rotation(bi, a.rotation_track_interpolate(ti, t))
				elif ty == Animation.TYPE_POSITION_3D:
					sk.set_bone_pose_position(bi, a.position_track_interpolate(ti, t))
			sk.force_update_all_bone_transforms()
			# global pose 自己由 local pose 累乘（headless 下 Skeleton3D 的 global 快取不會重算）
			var glob := {}
			var bones := {}
			for bi in sk.get_bone_count():
				bones[sk.get_bone_name(bi)] = _xf12(_glob(sk, bi, glob))
			frames.append({"t": t, "st": {"floor": true, "loco": nm, "full": ""}, "bones": bones})
		var f := FileAccess.open(out_dir.path_join(nm + ".json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(frames))
		f.close()
		print("R6_DUMP ", nm, " frames=", n, " len=", a.length, " loop=", a.loop_mode)
	quit()
