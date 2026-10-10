extends SceneTree
## P11 R2B TASK05（只讀、headless）：水車 1／2／3 の周り 14 m にある MeshInstance3D／CollisionObject3D を列挙（水道・樋の残骸探し）。
const SCENE := "res://maps/village_v2/village_v2.tscn"

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await process_frame
	for k in [1, 2, 3]:
		var hub := (v.get_node("Landmarks/LANDMARK_WATERWHEEL_%d" % k) as Node3D).global_position
		print("[WW] ===== 水車 %d at %s" % [k, hub])
		var seen := {}
		for n in v.find_children("*", "Node3D", true, false):
			if not (n is MeshInstance3D or n is CollisionObject3D):
				continue
			var path := String(v.get_path_to(n))
			if path.begins_with("Terrain") or path.begins_with("Vegetation") or path.begins_with("Debug") or path.begins_with("Population") or path.begins_with("Collision/Terrain") or path.contains("Riverbank"):
				continue
			var ab: AABB
			if n is MeshInstance3D:
				if (n as MeshInstance3D).mesh == null:
					continue
				ab = (n as Node3D).global_transform * (n as MeshInstance3D).get_aabb()
			else:
				ab = AABB((n as Node3D).global_position, Vector3.ZERO)
			var c := ab.get_center()
			var d := Vector2(c.x - hub.x, c.z - hub.z).length()
			if d > 14.0 or ab.size.length() > 60.0:
				continue
			var grp := path.get_slice("/", 0) + "/" + path.get_slice("/", 1) + "/" + path.get_slice("/", 2)
			var key := grp + " :: " + n.name
			if seen.has(key):
				continue
			seen[key] = true
			print("[WW] %5.1f m  y %.2f–%.2f  size %s  %s  vis=%s" % [d, ab.position.y, ab.end.y, ab.size.snapped(Vector3.ONE * 0.01), path, (n as Node3D).is_visible_in_tree()])
	quit(0)
