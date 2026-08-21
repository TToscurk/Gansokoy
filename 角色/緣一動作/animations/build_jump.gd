extends SceneTree
# Rebuild derived gameplay animations with the CORRECT axis convention.
# Skeleton space for this Meshy rig: Z = up (hips rest Z ~= 0.986), X/Y = horizontal.
# The previous build froze X/Z and left Y — leaving 6.47 units of horizontal root
# motion in Roll_Dodge (the snap-back bug). Here we freeze X and Y (horizontal)
# to the first key and keep Z (vertical bob), for roll + attacks.
# For Regular_Jump we additionally clamp Z to <= rest so the physics jump owns
# the rise while the crouch anticipation and the landing dip stay animated.

const JOBS := [
	{"src": "res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Roll_Dodge_1_withSkin.fbx", "out": "res://animations/yoriichi_roll_dodge.res", "clamp_z": false},
	{"src": "res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Weapon_Combo_withSkin.fbx", "out": "res://animations/yoriichi_attack_combo.res", "clamp_z": false},
	{"src": "res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Axe_Spin_Attack_withSkin.fbx", "out": "res://animations/yoriichi_attack_spin.res", "clamp_z": false},
	{"src": "res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Sword_Judgment_withSkin.fbx", "out": "res://animations/yoriichi_attack_judgment.res", "clamp_z": false},
	{"src": "res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Regular_Jump_withSkin.fbx", "out": "res://animations/yoriichi_jump.res", "clamp_z": true},
	{"src": "res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_Weapon_Combo_1_withSkin.fbx", "out": "res://animations/yoriichi_attack_combo_1.res", "clamp_z": false},
	{"src": "res://Meshy_AI_Yoriichi_atlas_mcp_ra_biped_Animation_360_Power_Spin_Jump_withSkin.fbx", "out": "res://animations/yoriichi_attack_spin_jump.res", "clamp_z": true},
]

func _anim_from_fbx(path: String) -> Animation:
	var ps: PackedScene = load(path)
	var tmp := ps.instantiate()
	var aps := tmp.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		push_error("no AnimationPlayer in " + path)
		tmp.free()
		return null
	var a: Animation = (aps[0] as AnimationPlayer).get_animation((aps[0] as AnimationPlayer).get_animation_list()[0]).duplicate()
	tmp.free()
	return a

func _hips_track(a: Animation) -> int:
	for i in a.get_track_count():
		if a.track_get_type(i) == Animation.TYPE_POSITION_3D and String(a.track_get_path(i)).ends_with("Hips"):
			return i
	return -1

func _init():
	for job in JOBS:
		var a := _anim_from_fbx(job.src)
		if a == null:
			continue
		var t := _hips_track(a)
		if t < 0:
			push_error("no hips position track in " + String(job.src))
			continue
		var n := a.track_get_key_count(t)
		var first: Vector3 = a.track_get_key_value(t, 0)
		var drift: Vector3 = a.track_get_key_value(t, n - 1) - first
		var z_min := 1e9
		var z_max := -1e9
		var takeoff := -1.0
		var land := -1.0
		for k in n:
			var v: Vector3 = a.track_get_key_value(t, k)
			z_min = minf(z_min, v.z)
			z_max = maxf(z_max, v.z)
			var nv := Vector3(first.x, first.y, v.z)
			if job.clamp_z:
				# Locate the animated air phase before clamping.
				var time := a.track_get_key_time(t, k)
				if v.z > first.z + 0.05:
					if takeoff < 0.0:
						takeoff = time
					land = time
				nv.z = minf(v.z, first.z)
			a.track_set_key_value(t, k, nv)
		a.loop_mode = Animation.LOOP_NONE
		var err := ResourceSaver.save(a, job.out)
		print("[%s] len=%.4f keys=%d drift_removed=(%.3f, %.3f) z_range=[%.3f, %.3f] rest_z=%.3f save=%d" % [
			String(job.out).get_file(), a.length, n, drift.x, drift.y, z_min, z_max, first.z, err])
		if job.clamp_z:
			print("  air_phase: takeoff=%.3fs land=%.3fs duration=%.3fs (of %.2fs clip)" % [takeoff, land, land - takeoff, a.length])
	quit()
