extends SceneTree
## Bound the possible win: measure the same views with the heavy Meshy
## buildings hidden, to separate architecture cost from everything else.
##
## This is a DIAGNOSTIC ONLY — nothing is saved. Round A (distance culling)
## removed 6300 objects and 300 draw calls but left GPU time unchanged, which
## says the remaining ~75M triangles per frame are what actually costs. This
## proves whether that is the buildings before anyone spends hours decimating.

const WARMUP := 90
const SAMPLE := 150
const HEAVY_TRIS := 100000

const VIEWS := [
	{"name": "主街街道", "pos": Vector3(235.0, 1.7, -10.0), "look": Vector3(235.0, 3.0, 60.0)},
	{"name": "村落俯瞰", "pos": Vector3(300.0, 55.0, -90.0), "look": Vector3(300.0, 0.0, 40.0)},
]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var packed := ResourceLoader.load("res://maps/slice/slice.tscn", "PackedScene") as PackedScene
	var scene := packed.instantiate()
	var cull_node := scene.get_node_or_null("場景效能裁剪")
	if cull_node != null:
		cull_node.set("啟用", true)
	root.add_child(scene)

	var cam := Camera3D.new()
	cam.fov = 72.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.current = true

	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await process_frame

	var heavy: Array[MeshInstance3D] = []
	_collect_heavy(scene, heavy)
	var total := 0
	for m in heavy:
		total += _tris(m.mesh)
	print("[診斷] 高面數建築 %d 個，合計 %d 萬三角面" % [heavy.size(), total / 10000])

	for view in VIEWS:
		cam.global_position = view["pos"]
		cam.look_at(view["look"], Vector3.UP)
		for m in heavy:
			m.visible = true
		var with_b := await _sample(vp)
		for m in heavy:
			m.visible = false
		var without_b := await _sample(vp)
		for m in heavy:
			m.visible = true

		print("[診斷] %s | 有建築 GPU %.2f ms (%.0f fps) | 無建築 GPU %.2f ms (%.0f fps) | 建築占 %.0f%%" % [
			view["name"], with_b["gpu"], with_b["fps"], without_b["gpu"], without_b["fps"],
			100.0 * (with_b["gpu"] - without_b["gpu"]) / maxf(with_b["gpu"], 0.01)])

	print("[診斷] done")
	quit(0)


func _sample(vp: RID) -> Dictionary:
	for i in WARMUP:
		await process_frame
	var gpu := 0.0
	var fps: Array[float] = []
	for i in SAMPLE:
		await process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		fps.append(Performance.get_monitor(Performance.TIME_FPS))
	fps.sort()
	return {"gpu": gpu / SAMPLE, "fps": fps[fps.size() / 2]}


func _collect_heavy(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null and _tris(mi.mesh) >= HEAVY_TRIS:
			out.append(mi)
	for c in n.get_children():
		_collect_heavy(c, out)


func _tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var t := 0
	for i in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(i)
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
