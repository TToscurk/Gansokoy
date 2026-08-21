extends SceneTree
# Runtime pose probe: toe-bone global heights in Idle vs Walk contact phase
# (floating-feet measurement), and the sword mesh's local AABB (grip axis).

class Probe extends Node:
	var chr: CharacterBody3D

	func wait(s: float) -> void:
		await get_tree().create_timer(s).timeout

	func toe_y() -> Vector2:
		var sk: Skeleton3D = chr.find_children("*", "Skeleton3D", true, false)[0]
		var l := sk.get_bone_global_pose(sk.find_bone("LeftToeBase"))
		var r := sk.get_bone_global_pose(sk.find_bone("RightToeBase"))
		var gl := (sk.global_transform * l).origin.y
		var gr := (sk.global_transform * r).origin.y
		return Vector2(gl, gr)

	func foot_y() -> Vector2:
		var sk: Skeleton3D = chr.find_children("*", "Skeleton3D", true, false)[0]
		var l := sk.get_bone_global_pose(sk.find_bone("LeftFoot"))
		var r := sk.get_bone_global_pose(sk.find_bone("RightFoot"))
		return Vector2((sk.global_transform * l).origin.y, (sk.global_transform * r).origin.y)

	func _ready() -> void:
		run()

	func run() -> void:
		await wait(1.0)
		# Idle：取 1 秒平均
		var idle_toe := Vector2.ZERO
		var idle_foot := Vector2.ZERO
		var n := 0
		var t := 0.0
		while t < 1.0:
			idle_toe += toe_y()
			idle_foot += foot_y()
			n += 1
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		idle_toe /= n
		idle_foot /= n
		print("IDLE toe_avg=%s foot_avg=%s body_y=%.3f visual_y=%.3f" % [idle_toe, idle_foot, chr.global_position.y, chr._visual.position.y])
		# Walk：取 1.2 秒（一個以上步行週期）的最低點 = 接觸幀
		var ev := InputEventKey.new()
		ev.keycode = KEY_W
		ev.physical_keycode = KEY_W
		ev.pressed = true
		Input.parse_input_event(ev)
		await wait(0.4)
		var walk_toe_min := 1e9
		var walk_foot_min := 1e9
		t = 0.0
		while t < 1.2:
			var ty := toe_y()
			var fy := foot_y()
			walk_toe_min = minf(walk_toe_min, minf(ty.x, ty.y))
			walk_foot_min = minf(walk_foot_min, minf(fy.x, fy.y))
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		print("WALK toe_min=%.3f foot_min=%.3f" % [walk_toe_min, walk_foot_min])
		print("FLOAT_GAP toe=%.3f (idle_min_toe - walk_contact_toe)" % (minf(idle_toe.x, idle_toe.y) - walk_toe_min))
		# 也量 Run 接觸
		var ev2 := InputEventKey.new()
		ev2.keycode = KEY_SHIFT
		ev2.physical_keycode = KEY_SHIFT
		ev2.pressed = true
		Input.parse_input_event(ev2)
		await wait(0.4)
		var run_toe_min := 1e9
		t = 0.0
		while t < 1.0:
			var ty := toe_y()
			run_toe_min = minf(run_toe_min, minf(ty.x, ty.y))
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		print("RUN toe_min=%.3f" % run_toe_min)
		get_tree().quit()

func _initialize():
	# 刀 mesh 長軸
	var sword := (load("res://yoriichi_sword.glb") as PackedScene).instantiate()
	for mi in sword.find_children("*", "MeshInstance3D", true, false):
		var aabb: AABB = (mi as MeshInstance3D).mesh.get_aabb()
		print("SWORD mesh=%s aabb_pos=%s aabb_size=%s" % [mi.name, aabb.position, aabb.size])
	sword.free()
	var level = (load("res://yoriichi_test.tscn") as PackedScene).instantiate()
	root.add_child(level)
	var p := Probe.new()
	p.chr = level.get_node("Yoriichi")
	root.add_child(p)
