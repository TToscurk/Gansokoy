extends SceneTree
## Windowed A/B render benchmark for res://maps/slice/slice.tscn.
##
## Run from the terminal, NOT headless — headless has no renderer, so every
## GPU number would be zero and the whole comparison would be meaningless.
##
##   Godot --path godot --script tools/bench_slice.gd -- --cull
##   Godot --path godot --script tools/bench_slice.gd -- --no-cull
##
## Why a standalone SceneTree script instead of a node inside slice.tscn:
## driving the open editor over MCP to add/remove a benchmark node kept timing
## out, and every attempt risked re-saving a 16 MB hand-tuned scene. This loads
## the scene fresh from disk, so it measures exactly what is committed.
##
## The A/B switch flips 場景效能裁剪.啟用 BEFORE add_child(), because that node
## does its work in _ready() -> _run.call_deferred().

const WARMUP := 90
const SAMPLE := 180

## Fixed viewpoints, sampled identically in both runs. Street level is what the
## player actually sees; the overview is the worst case for draw calls.
const VIEWS := [
	{"name": "主街街道", "pos": Vector3(235.0, 1.7, -10.0), "look": Vector3(235.0, 3.0, 60.0)},
	{"name": "河岸水車", "pos": Vector3(430.0, 4.0, 10.0), "look": Vector3(300.0, 2.0, 20.0)},
	{"name": "村落俯瞰", "pos": Vector3(300.0, 55.0, -90.0), "look": Vector3(300.0, 0.0, 40.0)},
]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var cull := true
	var shadow := true
	var taa := true
	var msaa := true
	var shadow_size := 0
	var grass_interactive := true
	var shadow_dist := 0.0
	var splits := 0
	var volfog := true
	var ssao := true
	var filter_q := -1
	var moon := true
	var angular := -1.0
	for a in OS.get_cmdline_user_args():
		if a == "--no-cull":
			cull = false
		elif a == "--no-shadow":
			shadow = false
		elif a == "--no-taa":
			taa = false
		elif a == "--no-msaa":
			msaa = false
		elif a.begins_with("--shadow="):
			shadow_size = int(a.substr(9))
		elif a == "--no-grass-interactive":
			grass_interactive = false
		elif a.begins_with("--shadow-dist="):
			shadow_dist = float(a.substr(14))
		elif a.begins_with("--splits="):
			splits = int(a.substr(9))
		elif a == "--no-volfog":
			volfog = false
		elif a == "--no-ssao":
			ssao = false
		elif a.begins_with("--filter="):
			filter_q = int(a.substr(9))
		elif a == "--no-moon":
			moon = false
		elif a.begins_with("--angular="):
			angular = float(a.substr(10))

	# Uncapped, or vsync pins everything to 60 and hides the entire difference.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if shadow_size > 0:
		RenderingServer.directional_shadow_atlas_set_size(shadow_size, true)
	if filter_q >= 0:
		RenderingServer.directional_soft_shadow_filter_set_quality(filter_q)
		RenderingServer.positional_soft_shadow_filter_set_quality(filter_q)
	if not taa:
		root.use_taa = false
		root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	if not msaa:
		root.msaa_3d = Viewport.MSAA_DISABLED
	if not grass_interactive:
		var sg := root.get_node_or_null("/root/SimpleGrass")
		if sg != null:
			sg.set("interactive", false)

	var packed := ResourceLoader.load("res://maps/slice/slice.tscn", "PackedScene") as PackedScene
	if packed == null:
		print("[BENCH] 無法載入 slice.tscn")
		quit(1)
		return

	var scene := packed.instantiate()
	var cull_node := scene.get_node_or_null("場景效能裁剪")
	if cull_node == null:
		print("[BENCH] 警告：找不到 場景效能裁剪 節點")
	else:
		cull_node.set("啟用", cull)

	root.add_child(scene)
	if not shadow:
		for l in _lights(scene):
			l.shadow_enabled = false
	# The sky system rebuilds the sun every frame and re-enables its shadow;
	# tell it too.
	var sky := scene.get_node_or_null("天象系統")
	if sky != null and not shadow:
		sky.set("太陽投影", false)
	if sky != null and shadow_dist > 0.0:
		sky.set("高品質陰影", false)
		sky.set("陰影距離", shadow_dist)
	if sky != null and splits > 0:
		sky.set("陰影分級", splits)
	if sky != null and not volfog:
		sky.set("體積霧", false)
	if sky != null and not ssao:
		sky.set("環境光遮蔽", false)
	if sky != null and not moon:
		sky.set("顯示月亮", false)
	if angular >= 0.0:
		_force_angular = angular
	print("[BENCH] 旗標 shadow=%s taa=%s msaa=%s shadow_size=%d grass_interactive=%s dist=%.0f splits=%d volfog=%s ssao=%s" % [
		shadow, taa, msaa, shadow_size, grass_interactive, shadow_dist, splits, volfog, ssao])

	var cam := Camera3D.new()
	cam.fov = 72.0
	cam.far = 4000.0
	root.add_child(cam)
	cam.current = true

	# Ask the server to time the GPU. Without this the measured-time getters
	# return 0 and we would be reporting CPU-side FPS only.
	var vp_rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)

	await process_frame

	print("[BENCH] 模式=%s  暖機%d 採樣%d" % ["裁剪ON" if cull else "裁剪OFF", WARMUP, SAMPLE])
	print("[BENCH] 記憶體 靜態 %.0f MB | VRAM 貼圖 %.0f MB | VRAM 緩衝 %.0f MB | VRAM 合計 %.0f MB | 物件 %d 節點 %d" % [
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / 1048576.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])

	for view in VIEWS:
		cam.global_position = view["pos"]
		cam.look_at(view["look"], Vector3.UP)

		for i in WARMUP:
			await process_frame
			if _force_angular >= 0.0:
				for l in _lights(scene):
					if l is DirectionalLight3D:
						l.light_angular_distance = _force_angular

		var fps: Array[float] = []
		var cpu: Array[float] = []
		var gpu: Array[float] = []
		var draws: Array[float] = []
		var prims: Array[float] = []
		var objs: Array[float] = []
		var tproc: Array[float] = []
		var tphys: Array[float] = []
		var tnav: Array[float] = []

		for i in SAMPLE:
			await process_frame
			if _force_angular >= 0.0:
				for l in _lights(scene):
					if l is DirectionalLight3D:
						l.light_angular_distance = _force_angular
			fps.append(Performance.get_monitor(Performance.TIME_FPS))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp_rid))
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp_rid))
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			objs.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
			tproc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			tphys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			tnav.append(Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0)

		# Median FPS, not mean: a couple of stalled frames drag a mean far below
		# what the view actually runs at, and we are comparing two runs.
		var vp_prims := RenderingServer.viewport_get_render_info(vp_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		var sh_prims := RenderingServer.viewport_get_render_info(vp_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		var sh_draws := RenderingServer.viewport_get_render_info(vp_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		print("[BENCH] %s | FPS 中位 %.1f 最低 %.1f | CPU %.2f ms | GPU %.2f ms | draw %.0f | 三角面 %.0f（可見 %d + 陰影 %d，陰影 draw %d）| 物件 %.0f" % [
			view["name"], _median(fps), _min_v(fps),
			_avg(cpu), _avg(gpu), _avg(draws), _avg(prims), vp_prims, sh_prims, sh_draws, _avg(objs)])
		print("[BENCH]   ↳ 主迴圈 process %.1f ms（最大 %.1f）| physics %.1f ms（最大 %.1f）| nav %.1f ms" % [
			_avg(tproc), _max_v(tproc), _avg(tphys), _max_v(tphys), _avg(tnav)])

	print("[BENCH] done")
	quit(0)


func _avg(v: Array[float]) -> float:
	var t := 0.0
	for x in v:
		t += x
	return t / maxf(v.size(), 1.0)


func _max_v(v: Array[float]) -> float:
	var m := -1e9
	for x in v:
		m = maxf(m, x)
	return m


func _median(v: Array[float]) -> float:
	var s := v.duplicate()
	s.sort()
	return s[s.size() / 2]


func _min_v(v: Array[float]) -> float:
	var r := INF
	for x in v:
		r = minf(r, x)
	return r


var _force_angular := -1.0


func _lights(n: Node) -> Array[Light3D]:
	var out: Array[Light3D] = []
	if n is Light3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_lights(c))
	return out
