extends SceneTree
const T := ["res://assets/landscape/大衫.glb", "res://assets/landscape/2大衫.glb",
	"res://assets/landscape/松樹.glb", "res://assets/landscape/普通樹.glb"]
var _out := "D:/神社/shrine/_review/tree_tt"
func _init() -> void: _run.call_deferred()
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var w := Node3D.new(); root.add_child(w)
	var we := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.60, 0.66)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.60, 0.64, 0.70)
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = e; w.add_child(we)
	var sun := DirectionalLight3D.new(); sun.light_energy = 1.6; w.add_child(sun)
	sun.global_position = Vector3(6, 14, 6); sun.look_at(Vector3.ZERO, Vector3.UP)
	var cam := Camera3D.new(); cam.fov = 40.0; w.add_child(cam); cam.current = true
	for path in T:
		var ps := ResourceLoader.load(path, "PackedScene") as PackedScene
		var inst := ps.instantiate() as Node3D; w.add_child(inst)
		await process_frame
		var bb := AABB(); var first := true
		for mi in _m(inst):
			var b := mi.global_transform * mi.get_aabb()
			if first: bb = b; first = false
			else: bb = bb.merge(b)
		var c := bb.get_center(); var r := bb.size.length() * 0.5
		cam.global_position = c + Vector3(0, 0.4, 2.4) * r
		cam.look_at(c, Vector3.UP)
		for i in 4: await process_frame
		var lbl: String = String(path).get_file().get_basename()
		root.get_texture().get_image().save_png("%s/%s.png" % [_out, lbl])
		print("[T] %s/%s.png" % [_out, lbl])
		inst.queue_free(); await process_frame
	quit(0)
func _m(n: Node) -> Array[MeshInstance3D]:
	var o: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null: o.append(n)
	for c in n.get_children(): o.append_array(_m(c))
	return o
