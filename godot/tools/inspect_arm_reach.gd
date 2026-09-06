extends SceneTree

func _meas_bone_global(skel: Skeleton3D, bone_idx: int) -> Transform3D:
	var t := skel.get_bone_pose(bone_idx)
	var p := skel.get_bone_parent(bone_idx)
	while p >= 0:
		t = skel.get_bone_pose(p) * t
		p = skel.get_bone_parent(p)
	return t

func _init():
	var ps := load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene
	var player := ps.instantiate() as CharacterBody3D
	root.add_child(player)
	for t in player.find_children("*", "AnimationTree", true, false):
		(t as AnimationTree).active = false
	var ap: AnimationPlayer = player.find_children("*", "AnimationPlayer", true, false)[0]
	var anim: Animation = load("res://characters/yoriichi/animations/yoriichi_attack_continuous_spin.res")
	var lib := ap.get_animation_library(ap.get_animation_library_list()[0])
	lib.add_animation("spin_new", anim)
	ap.play("spin_new")
	
	var skel: Skeleton3D = player.find_children("*", "Skeleton3D", true, false)[0]
	var rh_idx := skel.find_bone("RightHand")
	
	var min_r := 1e9
	var max_r := -1e9
	var sum_r := 0.0
	var samples := 40
	for i in samples:
		var time := (float(i) / float(samples)) * anim.length
		ap.seek(time, true)
		var h_pose := _meas_bone_global(skel, 0)
		var rh_pose := _meas_bone_global(skel, rh_idx)
		var diff := rh_pose.origin - h_pose.origin
		var r := Vector2(diff.x, diff.y).length()
		min_r = minf(min_r, r)
		max_r = maxf(max_r, r)
		sum_r += r
	print("NEW EXTENDED ANIM: Hand horizontal radius min=%.3fm, max=%.3fm, avg=%.3fm" % [
		min_r, max_r, sum_r / samples
	])
	
	player.free()
	quit(0)
