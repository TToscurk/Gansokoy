extends SceneTree
## Render the original vs decimated building side by side for Human Art Review.
##
## Takes matched shots (same camera, same light, same framing) of
## assets/machiya/小町家1.glb and assets/machiya_lod/小町家1.glb so the user can
## judge whether 915,529 -> 19,999 triangles is visually acceptable. Per the
## project constitution only the user grants ART_APPROVED; this tool only
## produces the evidence.
##
## Shots are taken at review distance (how the building reads in the village)
## and close up (worst case for silhouette and roof-tile detail).

const SHOTS := [
	{"name": "review", "dist": 18.0, "height": 6.0, "label": "村中觀看距離"},
	{"name": "close", "dist": 8.0, "height": 3.0, "label": "近距離"},
	{"name": "roof", "dist": 12.0, "height": 14.0, "label": "屋頂俯角"},
]

var _out_dir := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	if _out_dir == "":
		_out_dir = "user://lod_review"
	DirAccess.make_dir_recursive_absolute(_out_dir)

	var vp := root
	vp.transparent_bg = false

	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.68, 0.74)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.60, 0.68)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	world.add_child(sun)
	sun.global_position = Vector3(0, 20, 0)
	sun.look_at(Vector3(-6, 0, -5), Vector3.UP)

	var cam := Camera3D.new()
	cam.fov = 45.0
	world.add_child(cam)
	cam.current = true

	for variant in [
		{"key": "orig", "path": "res://assets/machiya/小町家1.glb"},
		{"key": "lod", "path": "res://assets/machiya_lod/小町家1.glb"},
	]:
		var packed := ResourceLoader.load(variant["path"], "PackedScene") as PackedScene
		if packed == null:
			print("[REVIEW] 載入失敗 %s" % variant["path"])
			continue
		var inst := packed.instantiate() as Node3D
		world.add_child(inst)

		var aabb := _aabb_of(inst)
		var tris := _tris_of(inst)
		print("[REVIEW] %s  三角面 %d  尺寸 %.2f x %.2f x %.2f m" % [
			variant["key"], tris, aabb.size.x, aabb.size.y, aabb.size.z])

		var centre := aabb.get_center()
		for shot in SHOTS:
			var d: float = shot["dist"]
			cam.global_position = centre + Vector3(d * 0.8, shot["height"], d * 0.8)
			cam.look_at(centre, Vector3.UP)
			await process_frame
			await process_frame
			await process_frame
			var img := vp.get_texture().get_image()
			var p := "%s/%s_%s.png" % [_out_dir, shot["name"], variant["key"]]
			img.save_png(p)
			print("[REVIEW] 已存 %s" % p)

		inst.queue_free()
		await process_frame

	print("[REVIEW] done")
	quit(0)


func _aabb_of(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(n):
		var b := mi.global_transform * mi.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


func _tris_of(n: Node) -> int:
	var t := 0
	for mi in _meshes(n):
		var m := mi.mesh
		if m == null:
			continue
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			if arr.is_empty():
				continue
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx != null and idx.size() > 0:
				t += idx.size() / 3
			else:
				var v = arr[Mesh.ARRAY_VERTEX]
				if v != null:
					t += v.size() / 3
	return t


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
