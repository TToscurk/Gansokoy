extends SceneTree
## Compare several decimation ratios of 小町家1 at the SAME framing, tightly
## cropped so the user can actually judge the silhouette and roof.
##
## The first review render framed the building far too small (a 1.36 m
## unit-normalized model shot from 18 m), which made a badly shredded 2.2%
## result look merely "small". Frame from the model's own bounding box instead
## of fixed metres, so every variant fills the frame identically.

const VARIANTS := [
	{"key": "00_orig", "path": "res://assets/machiya/小町家1.glb"},
	{"key": "01_gp203k", "path": "res://assets/machiya_lod_test/gp203k/小町家1.glb"},
	{"key": "02_sa137k", "path": "res://assets/machiya_lod_test/sa15/小町家1.glb"},
	{"key": "03_sa91k", "path": "res://assets/machiya_lod_test/sa10/小町家1.glb"},
]

var _out := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)

	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.58, 0.65, 0.72)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.65, 0.72)
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	world.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	world.add_child(sun)
	sun.rotation_degrees = Vector3(-42, 128, 0)

	var cam := Camera3D.new()
	cam.fov = 40.0
	world.add_child(cam)
	cam.current = true

	for v in VARIANTS:
		var packed := ResourceLoader.load(v["path"], "PackedScene") as PackedScene
		if packed == null:
			print("[CMP] 載入失敗 %s" % v["path"])
			continue
		var inst := packed.instantiate() as Node3D
		world.add_child(inst)

		var aabb := _aabb(inst)
		var tris := _tris(inst)
		var centre := aabb.get_center()
		# Frame from the model's own size so all variants match exactly.
		var radius := aabb.size.length() * 0.5
		var dist := radius / tan(deg_to_rad(cam.fov * 0.5)) * 1.15

		for shot in [
			{"n": "front", "dir": Vector3(0.75, 0.35, 0.75)},
			{"n": "roof", "dir": Vector3(0.45, 1.05, 0.55)},
		]:
			var dir: Vector3 = (shot["dir"] as Vector3).normalized()
			cam.global_position = centre + dir * dist
			cam.look_at(centre, Vector3.UP)
			await process_frame
			await process_frame
			await process_frame
			var p := "%s/%s_%s.png" % [_out, shot["n"], v["key"]]
			root.get_texture().get_image().save_png(p)

		print("[CMP] %-9s 三角面 %8d" % [v["key"], tris])
		inst.queue_free()
		await process_frame

	print("[CMP] done")
	quit(0)


func _aabb(n: Node) -> AABB:
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


func _tris(n: Node) -> int:
	var t := 0
	for mi in _meshes(n):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			if arr.is_empty():
				continue
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx != null and idx.size() > 0:
				t += idx.size() / 3
			else:
				var vtx = arr[Mesh.ARRAY_VERTEX]
				if vtx != null:
					t += vtx.size() / 3
	return t


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
