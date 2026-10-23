extends SceneTree
## R7 P5 REF01 右鍵分支素材（Sword And Shield High Attack，重定向後 r01_ss_high_atk.res）骨盆世界朝向逐格量測（唯讀）。
## AnimationTree 停用、控制器物理停用；AnimationPlayer 逐格 seek（30 fps 來源格），在 Skeleton3D.skeleton_updated 後取樣
## mixamorig_Hips 的世界變換：朝向＝骨盆「rest 前方」(骨盆 rest 基底下的 +Z → 角色前方) 經當格世界旋轉後的水平投影。
## 角度定義：相對角色 visual 前方（+Z of _visual），由上往下看逆時針為正（繞 +Y 右手定則）；逐格 unwrap。
##   godot --headless --path godot -s res://tools/yoriichi_r7/probe_r7_ref01_rmb_src.gd -- <out_json_abs>
const PLAYER := "res://characters/yoriichi/player_yoriichi_r7k.tscn"
const SRC := "res://characters/yoriichi/v24_r7/ref01_rmb_mx/r01_ss_high_atk.res"
var _sk: Skeleton3D
var _got := false

func _initialize() -> void:
	call_deferred("_run")

func _on_sk() -> void:
	_got = true

func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var p: CharacterBody3D = (load(PLAYER) as PackedScene).instantiate()
	p.set("r7_vfx_enabled", false)
	root.add_child(p)
	await process_frame
	await process_frame
	p.set_physics_process(false)
	p.set_process_unhandled_input(false)
	var anim: AnimationPlayer = p.get("_anim")
	var tree: AnimationTree = p.get("_tree")
	tree.active = false
	var ik = p.get("_r62_ik")
	if ik != null:
		ik.set("right_weight", 0.0)
		ik.set("left_enabled", false)
	var a := load(SRC) as Animation
	var lib := anim.get_animation_library(anim.get_animation_library_list()[0])
	lib.add_animation(&"RMB_SRC", a)
	_sk = (p.get("_visual") as Node).find_children("*", "Skeleton3D", true, false)[0]
	_sk.skeleton_updated.connect(_on_sk)
	var vis: Node3D = p.get("_visual")
	var hb := _sk.find_bone("mixamorig_Hips")
	var rest_g := _sk.get_bone_global_rest(hb)
	# 骨盆 rest 時的「角色前方」在骨盆局部座標的表示（rest 姿勢下骨盆前方＝visual 前方）
	var fwd_vis := vis.global_basis.z.normalized()
	var fwd_loc := (_sk.global_basis * rest_g.basis).inverse() * fwd_vis
	anim.play(&"RMB_SRC")
	anim.pause()
	var n := int(round(a.length * 30.0)) + 1
	var rows := []
	var un := 0.0
	var prev := 0.0
	for f in n:
		_got = false
		anim.seek(minf(f / 30.0, a.length), true)
		var guard := 0
		while not _got and guard < 6:
			await process_frame
			guard += 1
		var g := _sk.global_transform * _sk.get_bone_global_pose(hb)
		var d := (g.basis * fwd_loc)
		var y := rad_to_deg(atan2(d.cross(fwd_vis).y * -1.0, d.dot(fwd_vis)))
		# 上式：d 相對 fwd_vis 繞 +Y 的有號角
		var s := fwd_vis.cross(d).y
		var c := fwd_vis.dot(Vector3(d.x, 0, d.z).normalized())
		y = rad_to_deg(atan2(s, c))
		if f == 0:
			un = y
		else:
			un += fposmod(y - prev + 180.0, 360.0) - 180.0
		prev = y
		var lp := vis.global_transform.affine_inverse() * g.origin
		rows.append({"f": f, "yaw_raw": snappedf(y, 0.1), "yaw_unwrap": snappedf(un, 0.1),
			"hips_vis_local": [snappedf(lp.x, 0.001), snappedf(lp.y, 0.001), snappedf(lp.z, 0.001)], "sampled_after_skeleton_updated": _got})
	var fo := FileAccess.open(out, FileAccess.WRITE)
	fo.store_string(JSON.stringify({"src": SRC, "n": n, "fps": 30, "vis_fwd_world": [fwd_vis.x, fwd_vis.y, fwd_vis.z],
		"angle_def": "pelvis forward vs visual +Z, CCW from above (+Y right-hand) positive", "rows": rows}, " "))
	fo.close()
	print("RMB_YAW n=", n, " first=", rows[0].yaw_unwrap, " last=", rows[n - 1].yaw_unwrap)
	quit(0)
