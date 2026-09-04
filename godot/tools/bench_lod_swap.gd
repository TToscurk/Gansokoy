extends SceneTree
## Measure the FPS gain from the decimated buildings WITHOUT rewiring the scene.
##
## Swaps each MeshInstance3D's mesh resource in memory for its counterpart in
## assets/_lod/, then re-runs the same benchmark views as tools/bench_slice.gd.
## Nothing is saved: this answers "is it worth wiring in?" before any scene edit
## touches the user's hand-tuned slice.tscn.
##
## Matching is by source-GLB basename, taken from the mesh resource_path
## ("res://assets/machiya/小町家1.glb::ArrayMesh_1waij"), because the LOD tree is
## flat while the sources are spread across assets/ and maps/village/gen/.

const WARMUP := 90
const SAMPLE := 150
const LOD_DIR := "res://assets/_lod/"

const VIEWS := [
	{"name": "主街街道", "pos": Vector3(235.0, 1.7, -10.0), "look": Vector3(235.0, 3.0, 60.0)},
	{"name": "河岸水車", "pos": Vector3(430.0, 4.0, 10.0), "look": Vector3(300.0, 2.0, 20.0)},
	{"name": "村落俯瞰", "pos": Vector3(300.0, 55.0, -90.0), "look": Vector3(300.0, 0.0, 40.0)},
]

var _cache: Dictionary = {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var packed := ResourceLoader.load("res://maps/slice/slice.tscn", "PackedScene") as PackedScene
	var scene := packed.instantiate()
	var cull := scene.get_node_or_null("場景效能裁剪")
	if cull != null:
		cull.set("啟用", true)
	root.add_child(scene)

	var cam := Camera3D.new()
	cam.fov = 72.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.current = true

	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await process_frame

	var targets: Array[MeshInstance3D] = []
	_collect(scene, targets)

	# Record originals so the A side is exact, then build the swap list.
	var pairs: Array = []
	for mi in targets:
		var lod := _lod_for(mi.mesh)
		if lod != null:
			pairs.append({"node": mi, "hi": mi.mesh, "lo": lod})
	print("[SWAP] 可替換 %d 個 MeshInstance" % pairs.size())

	for view in VIEWS:
		cam.global_position = view["pos"]
		cam.look_at(view["look"], Vector3.UP)

		for p in pairs:
			p["node"].mesh = p["hi"]
		var hi := await _sample(vp)

		for p in pairs:
			p["node"].mesh = p["lo"]
		var lo := await _sample(vp)

		print("[SWAP] %s | 原始 %.1f fps / GPU %.2f ms / %.0f 萬面 | 減面 %.1f fps / GPU %.2f ms / %.0f 萬面 | 提升 %+.0f%%" % [
			view["name"],
			hi["fps"], hi["gpu"], hi["tri"] / 10000.0,
			lo["fps"], lo["gpu"], lo["tri"] / 10000.0,
			100.0 * (lo["fps"] - hi["fps"]) / maxf(hi["fps"], 1.0)])

	print("[SWAP] done")
	quit(0)


func _sample(vp: RID) -> Dictionary:
	for i in WARMUP:
		await process_frame
	var gpu := 0.0
	var tri := 0.0
	var fps: Array[float] = []
	for i in SAMPLE:
		await process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		tri += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		fps.append(Performance.get_monitor(Performance.TIME_FPS))
	fps.sort()
	return {"gpu": gpu / SAMPLE, "tri": tri / SAMPLE, "fps": fps[fps.size() / 2]}


func _lod_for(mesh: Mesh) -> Mesh:
	if mesh == null:
		return null
	var rp := mesh.resource_path
	if rp == "" or not rp.contains(".glb"):
		return null
	var base := rp.get_slice("::", 0).get_file()
	if _cache.has(base):
		return _cache[base]

	var lod_path := LOD_DIR + base
	var result: Mesh = null
	if ResourceLoader.exists(lod_path):
		var ps := ResourceLoader.load(lod_path, "PackedScene") as PackedScene
		if ps != null:
			var inst := ps.instantiate()
			var found: Array[MeshInstance3D] = []
			_collect(inst, found)
			# These building GLBs are single-mesh; take the densest surface set
			# so a stray helper mesh cannot win.
			var best := 0
			for f in found:
				if f.mesh == null:
					continue
				var c := f.mesh.get_surface_count()
				if result == null or c > best:
					result = f.mesh
					best = c
			inst.free()
	_cache[base] = result
	return result


func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
