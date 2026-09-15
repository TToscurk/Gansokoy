extends SceneTree
## Split the authored river vegetation into Z-bands without changing its source.
## River vegetation is visual-only; terrain and ground collision remain resident.

const SOURCE := "res://maps/slice/gen/river_vegetation.tscn"
const ZONES := [
	{"name": "river_vegetation_south", "z0": -620.0, "z1": -300.0},
	{"name": "river_vegetation_lower", "z0": -308.0, "z1": 0.0},
	{"name": "river_vegetation_upper", "z0": -8.0, "z1": 300.0},
	{"name": "river_vegetation_north", "z0": 292.0, "z1": 660.0},
]
const OUT_DIR := "res://maps/slice/gen/"

func _init() -> void:
	var packed := load(SOURCE) as PackedScene
	if packed == null:
		push_error("Missing %s" % SOURCE)
		quit(1)
		return
	var source := packed.instantiate() as Node3D
	for spec: Dictionary in ZONES:
		if not _write_zone(source, spec):
			source.free()
			quit(2)
			return
	source.free()
	quit(0)

func _write_zone(source: Node3D, spec: Dictionary) -> bool:
	var chunk := Node3D.new()
	chunk.name = String(spec["name"])
	var z0 := float(spec["z0"])
	var z1 := float(spec["z1"])
	for original: Node in source.get_children():
		var scatter := original.duplicate() as Node3D
		var original_crests: Array[Node] = []
		for child: Node in original.get_children():
			if child.name.begins_with("Crest"):
				original_crests.append(child)
		for child: Node in scatter.get_children():
			if child.name.begins_with("Crest"):
				scatter.remove_child(child)
				child.free()
		var crest_index := 0
		for original_crest: Node in original_crests:
			var source_shape = original_crest.get("shape")
			if source_shape == null or source_shape.curve == null:
				continue
			for curve: Curve3D in _clip_curve(source_shape.curve as Curve3D, z0, z1):
				var crest := original_crest.duplicate() as Node3D
				crest.name = "Crest%d" % crest_index
				crest_index += 1
				var shape_copy = source_shape.duplicate()
				shape_copy.curve = curve
				crest.set("shape", shape_copy)
				scatter.add_child(crest)
		if crest_index == 0:
			scatter.free()
			continue
		chunk.add_child(scatter)
		_set_owner_recursive(scatter, chunk)
	var out_path := OUT_DIR + String(spec["name"]) + ".tscn"
	var out := PackedScene.new()
	var pack_error := out.pack(chunk)
	if pack_error != OK:
		push_error("Pack failed %s: %d" % [out_path, pack_error])
		return false
	var save_error := ResourceSaver.save(out, out_path)
	if save_error != OK:
		push_error("Save failed %s: %d" % [out_path, save_error])
		return false
	print("[RIVER SPLIT] %s z=%.0f..%.0f rows=%d" % [out_path, z0, z1, chunk.get_child_count()])
	chunk.free()
	return true

func _clip_curve(source: Curve3D, z0: float, z1: float) -> Array[Curve3D]:
	var clipped: Array[Curve3D] = []
	var run := Curve3D.new()
	for i in source.point_count:
		var point := source.get_point_position(i)
		if point.z >= z0 and point.z <= z1:
			run.add_point(point)
		elif run.point_count >= 2:
			clipped.append(run)
			run = Curve3D.new()
		else:
			run = Curve3D.new()
	if run.point_count >= 2:
		clipped.append(run)
	return clipped

func _set_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child: Node in node.get_children():
		_set_owner_recursive(child, owner)
