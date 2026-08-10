extends RefCounted


static func build_revetment(
		lib,
		root: Node3D,
		out_dir: String,
		river: PackedVector2Array,
		river_half: float,
		bridges: Array,
		riverside_diner_position: Vector2,
		plaza: Vector2,
		bank_h: Callable,
		audit: Array[String]) -> void:
	var transforms: Array = []
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 2.2, 4.2)
	for index in range(river.size() - 1):
		var start := river[index]
		var finish := river[index + 1]
		var tangent := finish - start
		var length := tangent.length()
		if length < 0.01:
			continue
		tangent /= length
		var normal := Vector2(-tangent.y, tangent.x)
		for side in [-1.0, 1.0]:
			var middle: Vector2 = (start + finish) * 0.5 \
				+ normal * side * (river_half + 0.25)
			var skip := false
			for bridge in bridges:
				if absf(middle.x - bridge.x) < 8.0 \
						and absf(middle.y - bridge.z) < 8.0:
					skip = true
			if middle.distance_to(riverside_diner_position) < 22.0:
				skip = true
			if Vector2(middle.x, middle.y - plaza.y).length() > 132.0:
				skip = true
			if skip:
				continue
			var basis := Basis(Vector3.UP, atan2(tangent.x, tangent.y))
			basis = basis * Basis.from_scale(
				Vector3(1.0, 1.0, (length + 0.25) / 4.2))
			transforms.append(Transform3D(
				basis,
				Vector3(
					middle.x,
					float(bank_h.call(middle.x, middle.y)) - 1.02,
					middle.y)))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = lib.make_multimesh(
		mesh, transforms, [], out_dir + "gen/mm_revetment.res")
	instance.material_override = lib.flat_mat(
		"岸石", Color(0.205, 0.198, 0.183), 0.96)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = 160.0
	lib.add(root, instance, "護岸")
	audit.append("護岸 %d 段 → 1 個 MultiMesh（一段一節點的話是 %d 個節點）"
		% [transforms.size(), transforms.size()])


static func plug_river_mouths(
		root: Node3D,
		river: PackedVector2Array,
		river_half: float,
		half: float) -> void:
	var body := StaticBody3D.new()
	body.name = "河口封堵"
	root.add_child(body)
	body.owner = root
	for point in [river[0], river[river.size() - 1]]:
		var collision_shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(river_half * 2.0 + 10.0, 10.0, 1.0)
		collision_shape.shape = box
		collision_shape.position = Vector3(
			point.x, -3.0, clampf(point.y, -(half - 1.5), half - 1.5))
		body.add_child(collision_shape)
		collision_shape.owner = root


static func build_bridges(
		lib,
		root: Node3D,
		bridges: Array,
		mods: Dictionary,
		bank_h: Callable,
		obb_of: Callable,
		dump: Array,
		reserved: Array,
		audit: Array[String]) -> void:
	var group: Node3D = lib.add(root, Node3D.new(), "橋")
	for bridge in bridges:
		var mesh: Mesh = lib.prop_mesh(String(mods[bridge.kind]["glb"]))
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.position = Vector3(
			bridge.x,
			float(bank_h.call(bridge.x, bridge.z)) + 0.02,
			bridge.z)
		instance.rotation.y = bridge.yaw
		instance.set_meta("needs_trimesh", true)
		lib.add(group, instance, "%s_%d" % [bridge.kind, int(bridge.z)])
		dump.append([
			bridge.kind, bridge.x, instance.position.y, bridge.z, bridge.yaw])
		reserved.append(obb_of.call(
			[bridge.kind, bridge.x, 0.0, bridge.z, bridge.yaw]))
	audit.append("橋 %d 座（主橋 12m + 小橋 4.2m ×2），全部帶 needs_trimesh"
		% bridges.size())
