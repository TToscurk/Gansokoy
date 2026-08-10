extends RefCounted


static func build(
		lib,
		root: Node3D,
		landmarks: Array,
		seed_value: int,
		lm_rng: RandomNumberGenerator,
		reserved: Array,
		ground_under: Callable,
		bank_h: Callable,
		landmark_builder: Object,
		audit: Array[String]) -> void:
	var group: Node3D = lib.add(root, Node3D.new(), "地標佔位")
	var lm_body := StaticBody3D.new()
	lm_body.name = "地標碰撞"
	root.add_child(lm_body)
	lm_body.owner = root
	var wall_mat: Material = lib.flat_mat(
		"佔位牆", Color(0.575, 0.560, 0.520), 0.92)
	var roof_mat: Material = lib.flat_mat(
		"佔位瓦", Color(0.150, 0.163, 0.192), 0.88)
	lm_rng.seed = seed_value + 4177
	var stub_count := 0
	var real_count := 0
	for landmark in landmarks:
		reserved.append([
			Vector2(landmark.x, landmark.z), Vector2(1, 0), Vector2(0, 1),
			(landmark.w + 1.6) * 0.5, (landmark.d + 1.6) * 0.5, landmark.n])
		if landmark.has("build"):
			var real_group: Node3D = lib.add(group, Node3D.new(), landmark.n)
			var ground: Array = ground_under.call(
				landmark.x, landmark.z, landmark.w, landmark.d)
			real_group.position = Vector3(
				landmark.x, float(ground[0]), landmark.z)
			landmark_builder.call(
				String(landmark.build), real_group, float(ground[1]))
			real_count += 1
			continue
		stub_count += 1
		var y: float = bank_h.call(landmark.x, landmark.z)
		var width: float = float(landmark.get("bw", landmark.w))
		var depth: float = float(landmark.get("bd", landmark.d))
		var wall_h: float = maxf(landmark.h * 0.62, landmark.h - depth * 0.30)
		var stub_group: Node3D = lib.add(group, Node3D.new(), landmark.n)
		lib.box(stub_group, "屋身", Vector3(width, wall_h, depth), wall_mat,
			Vector3(landmark.x, y + wall_h * 0.5, landmark.z))
		lib.gable_roof(
			stub_group, y + wall_h, width + 1.6, depth + 1.6,
			atan2(landmark.h - wall_h, depth * 0.5), 0.22,
			roof_mat, roof_mat, Vector3(landmark.x, 0.0, landmark.z))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(width, wall_h, depth)
		shape.shape = box
		shape.position = Vector3(landmark.x, y + wall_h * 0.5, landmark.z)
		lm_body.add_child(shape)
		shape.owner = root
	audit.append("地標：真內容 %d 座、佔位 %d 座（佔位才有空殼碰撞箱）"
		% [real_count, stub_count])
