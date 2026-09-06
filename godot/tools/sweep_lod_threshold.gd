extends SceneTree
## Sweep the mesh LOD threshold and measure GPU time, to find out whether
## Godot's own import-time LOD chain can carry this scene.
##
## Why this instead of reading the LOD data: ArrayMesh.surface_get_lods() does
## not exist in 4.7, so the chain cannot be inspected directly. But its EFFECT
## is measurable — raising the threshold makes the renderer drop to coarser LOD
## levels sooner. If GPU time falls as the threshold rises, healthy LOD chains
## exist and this is a one-setting fix. If GPU time is flat, the chains are
## absent or degenerate and offline decimation is the only route.
##
## Threshold is in pixels: a LOD level is used when its screen-space error is
## below this. 1.0 = Godot default (highest quality).

const WARMUP := 60
const SAMPLE := 120
const THRESHOLDS := [1.0, 4.0, 16.0, 64.0]

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

	for view in VIEWS:
		cam.global_position = view["pos"]
		cam.look_at(view["look"], Vector3.UP)
		print("--- %s ---" % view["name"])
		for t in THRESHOLDS:
			# This is a Viewport PROPERTY in 4.7, not a RenderingServer call
			# (viewport_set_mesh_lod_threshold does not exist).
			root.mesh_lod_threshold = t
			for i in WARMUP:
				await process_frame
			var gpu := 0.0
			var prims := 0.0
			var fps: Array[float] = []
			for i in SAMPLE:
				await process_frame
				gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
				prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
				fps.append(Performance.get_monitor(Performance.TIME_FPS))
			fps.sort()
			print("[LOD] 門檻 %5.1f px | GPU %6.2f ms | FPS %3.0f | 三角面 %.0f 萬" % [
				t, gpu / SAMPLE, fps[fps.size() / 2], prims / SAMPLE / 10000.0])

	print("done")
	quit(0)
