extends RefCounted


static func emit_batches(
		lib,
		root: Node3D,
		out_dir: String,
		mods: Dictionary,
		batches: Dictionary,
		audit: Array[String]) -> void:
	var group: Node3D = lib.add(root, Node3D.new(), "町家")
	var total := 0
	var names: Array = batches.keys()
	names.sort()
	for kind in names:
		var transforms: Array = batches[kind]
		var semantic_result: Array = lib.semantic_mesh(String(mods[kind]["glb"]))
		var mesh: Mesh = semantic_result[0]
		if mesh.get_surface_count() > 1:
			audit.append("　%s：語意材質 %d surface %s" % [
				kind, mesh.get_surface_count(), str(semantic_result[1])])
		else:
			mesh = lib.prop_mesh(String(mods[kind]["glb"]))
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = lib.make_multimesh(
			mesh, transforms, [], out_dir + "gen/mm_%s.res" % kind)
		lib.add(group, instance, "MM_%s" % kind)
		total += transforms.size()
	audit.append("町家 %d 棟 / %d 種模組（%d draw call）"
		% [total, names.size(), names.size()])


static func build_collision(
		root: Node3D,
		mods: Dictionary,
		dump: Array,
		is_house_kind: Callable,
		audit: Array[String]) -> void:
	var body := StaticBody3D.new()
	body.name = "町家碰撞"
	root.add_child(body)
	body.owner = root
	var count := 0
	for entry in dump:
		if not bool(is_house_kind.call(String(entry[0]))):
			continue
		var module: Dictionary = mods[entry[0]]
		var yaw: float = entry[4]
		var forward := Vector2(sin(yaw), cos(yaw))
		var centre := Vector2(entry[1], entry[3])
		if not bool(module.get("centered", false)):
			centre -= forward * (float(module["d"]) * 0.5)
		var collision_shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(
			float(module["w"]), float(module["h"]), float(module["d"]))
		collision_shape.shape = box
		collision_shape.position = Vector3(
			centre.x,
			float(entry[2]) + float(module["h"]) * 0.5,
			centre.y)
		collision_shape.rotation.y = yaw
		body.add_child(collision_shape)
		collision_shape.owner = root
		count += 1
	audit.append("町家碰撞箱 %d 個（1 個 StaticBody3D）" % count)
