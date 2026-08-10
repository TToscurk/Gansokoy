extends RefCounted

## Deterministic street-edge fixtures for the Human Village generator.

static func build_lamps(lib, root: Node3D, anchors: Array,
		reserved_fn: Callable, height_fn: Callable, audit: Array[String]) -> void:
	var group: Node3D = lib.add(root, Node3D.new(), "街燈")
	var wood: StandardMaterial3D = lib.pbr(
		"行灯柱", "dark_wood", 2.4, Color(0.42, 0.40, 0.37))
	var stone: StandardMaterial3D = lib.pbr(
		"行灯台石", "stone_flag", 1.8, Color(0.50, 0.51, 0.49))
	var paper: StandardMaterial3D = lib.flat_mat(
		"行灯紙", Color(0.93, 0.87, 0.72), 0.6,
		Color(0.34, 0.245, 0.115))
	var count := 0
	for anchor in anchors:
		var position := Vector2(float(anchor[0]), float(anchor[1]))
		if bool(reserved_fn.call(position, 0.8)):
			continue
		var lamp := Node3D.new()
		lamp.position = Vector3(
			position.x,
			float(height_fn.call(position.x, position.y)),
			position.y)
		lamp.rotation.y = 0.35 * float((count * 7) % 5 - 2) * 0.25
		lib.add(group, lamp, "街燈_%d" % count)
		lib.box(lamp, "台石", Vector3(0.50, 0.22, 0.50), stone,
			Vector3(0, 0.11, 0))
		lib.box(lamp, "柱", Vector3(0.13, 1.85, 0.13), wood,
			Vector3(0, 0.22 + 0.925, 0))
		lib.box(lamp, "火袋", Vector3(0.36, 0.44, 0.36), paper,
			Vector3(0, 2.32, 0))
		for corner in 4:
			lib.box(lamp, "框_%d" % corner, Vector3(0.05, 0.50, 0.05), wood,
				Vector3((-1.0 if corner % 2 == 0 else 1.0) * 0.165, 2.32,
					(-1.0 if corner < 2 else 1.0) * 0.165))
		lib.box(lamp, "笠", Vector3(0.56, 0.06, 0.56), wood,
			Vector3(0, 2.60, 0))
		lib.box(lamp, "笠上", Vector3(0.34, 0.05, 0.34), wood,
			Vector3(0, 2.65, 0))
		var light := OmniLight3D.new()
		light.position = Vector3(0, 2.32, 0)
		light.light_color = Color(1.0, 0.76, 0.46)
		light.light_energy = 1.1
		light.omni_range = 8.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 55.0
		light.distance_fade_length = 15.0
		lib.add(lamp, light, "光")
		count += 1
	audit.append(
		"街燈 %d 盞（辻行灯：門・辻・社前・市の口・橋詰だけ。等間隔配置は廃止）" % count)
