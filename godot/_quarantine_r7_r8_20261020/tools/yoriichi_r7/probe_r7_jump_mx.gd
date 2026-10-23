extends SceneTree
## R7 P5 跳躍素材逐格量測：骨盆高度、左右腳趾高度（相對 rest 地面）。只讀不寫。
##   godot --headless --path godot -s res://tools/yoriichi_r7/probe_r7_jump_mx.gd -- <anim_res>
const PLAYER := "res://characters/yoriichi/player_yoriichi_r7k.tscn"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var p: CharacterBody3D = (load(PLAYER) as PackedScene).instantiate()
	p.set("r7_vfx_enabled", false)
	root.add_child(p)
	await process_frame
	await process_frame
	p.set_physics_process(false)
	var anim: AnimationPlayer = p.get("_anim")
	var tree: AnimationTree = p.get("_tree")
	tree.active = false
	var sk := p.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var lib := anim.get_animation_library(anim.get_animation_library_list()[0])
	for path in args:
		var a := load(path) as Animation
		lib.add_animation(&"PROBE", a)
		anim.play(&"PROBE")
		anim.pause()
		var hb := sk.find_bone("mixamorig_Hips")
		var lt := sk.find_bone("mixamorig_LeftToeBase")
		var rt := sk.find_bone("mixamorig_RightToeBase")
		var lf := sk.find_bone("mixamorig_LeftFoot")
		var rf := sk.find_bone("mixamorig_RightFoot")
		print("PROBE ", path, " len=", a.length)
		var n := int(round(a.length * 30.0))
		for i in n + 1:
			anim.seek(minf(i / 30.0, a.length), true)
			var g := func(b): return sk.global_transform * sk.get_bone_global_pose(b).origin
			var h: Vector3 = g.call(hb)
			var L: Vector3 = g.call(lt)
			var R: Vector3 = g.call(rt)
			print("  f%02d hips=(%.3f,%.3f,%.3f) Ltoe=(%.3f,%.3f,%.3f) Rtoe=(%.3f,%.3f,%.3f)" % [i, h.x, h.y, h.z, L.x, L.y, L.z, R.x, R.y, R.z])
		lib.remove_animation(&"PROBE")
	print("PROBE ref sk_y=", sk.global_position.y)
	quit()
