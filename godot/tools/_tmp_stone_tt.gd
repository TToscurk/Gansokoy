extends SceneTree
const T := ["res://assets/riverbank/洗物石段.glb", "res://assets/riverbank/濱水平台一塊.glb",
	"res://assets/riverbank/塊石疊砌牆一段.glb", "res://assets/riverbank/石造堰檻.glb",
	"res://assets/_incoming/gobkit_nature/Rock001.glb", "res://assets/_incoming/gobkit_nature/Rock002.glb",
	"res://assets/_incoming/gobkit_nature/Rock003.glb", "res://assets/nature/Rock_Medium_2.gltf",
	"res://assets/nature/RockPath_Square_Wide.gltf", "res://assets/nature/Pebble_Square_1.gltf"]
var _out := "D:/神社/shrine/_review/stone_tt"
func _init() -> void: _run.call_deferred()
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var w := Node3D.new(); root.add_child(w)
	var we := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.55, 0.60, 0.66)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.60, 0.64, 0.70); e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_ACES; we.environment = e; w.add_child(we)
	var sun := DirectionalLight3D.new(); sun.light_energy = 1.6; sun.shadow_enabled = true; w.add_child(sun)
	sun.global_position = Vector3(6, 14, 6); sun.look_at(Vector3.ZERO, Vector3.UP)
	var cam := Camera3D.new(); cam.fov = 40.0; w.add_child(cam); cam.current = true
	for path in T:
		var ps := ResourceLoader.load(path, "PackedScene") as PackedScene
		if ps == null: print("[T] 載入失敗 ", path); continue
		var inst := ps.instantiate() as Node3D; w.add_child(inst)
		await process_frame
		var bb := AABB(); var first := true; var tris := 0
		for mi in _m(inst):
			var b := mi.global_transform * mi.get_aabb()
			if first: bb = b; first = false
			else: bb = bb.merge(b)
			for s in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(s)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		var c := bb.get_center(); var r := bb.size.length() * 0.5
		cam.global_position = c + Vector3(0.9, 0.9, 1.6).normalized() * r * 2.3
		cam.look_at(c, Vector3.UP)
		for i in 4: await process_frame
		var lbl: String = String(path).get_file().get_basename()
		root.get_texture().get_image().save_png("%s/%s.png" % [_out, lbl])
		print("[T] %-18s %6.2f x %6.2f x %6.2f  min.y %+.3f  tris %6d" % [lbl, bb.size.x, bb.size.y, bb.size.z, bb.position.y, tris])
		inst.queue_free(); await process_frame
	quit(0)
func _m(n: Node) -> Array[MeshInstance3D]:
	var o: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null: o.append(n)
	for c in n.get_children(): o.append_array(_m(c))
	return o
