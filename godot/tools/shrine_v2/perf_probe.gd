extends SceneTree
## 效能探針（視窗模式）：載入場景＋固定鏡頭，量每幀 CPU/GPU 渲染時間、draw calls、頂點／面、物件數。
##   godot --path godot --resolution 1280x720 --script res://tools/shrine_v2/perf_probe.gd -- --map=<tscn> --views=<json>
## --views JSON：[{"name","cam":[x,y,z],"look":[x,y,z]}]；y 可寫 "g+1.7"（地面高＋1.7，需場景有碰撞）。
## 量測：RenderingServer.viewport_set_measure_render_time（真 GPU／CPU 毫秒），垂直同步關閉，每視角暖機 30 幀、取 90 幀平均。

var _map := "res://maps/shrine_v2/shrine_v2.tscn"
var _views: Array = []
var _hide: PackedStringArray = []
var _noshadow: PackedStringArray = []
var _shadow_dist := -1.0
var _lod_scale := 1.0


func _init() -> void:
	_run.call_deferred()


func _set_shadow_dist(n: Node, d: float) -> void:
	if n is DirectionalLight3D:
		(n as DirectionalLight3D).directional_shadow_max_distance = d
	for c in n.get_children():
		_set_shadow_dist(c, d)


func _set_noshadow(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_set_noshadow(c)


## 樹 LOD 偏移：visibility_range 與 shader 交叉帶（lod_band）同比縮放，等於讓樹更早換成粗 LOD
func _scale_lod(n: Node, k: float) -> void:
	if n is MeshInstance3D and String(n.name).begins_with("LOD"):
		var mi := n as MeshInstance3D
		mi.visibility_range_begin *= k
		mi.visibility_range_end *= k
		var lb: Variant = mi.get_instance_shader_parameter("lod_band")
		if lb is Vector4:
			mi.set_instance_shader_parameter("lod_band", (lb as Vector4) * k)
	for c in n.get_children():
		_scale_lod(c, k)


func _ground(world: Node3D, x: float, z: float) -> float:
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -50.0, z))
	var hit := space.intersect_ray(q)
	return float(hit["position"].y) if hit.size() > 0 else NAN


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			_map = a.substr(6)
		elif a.begins_with("--views="):
			_views = JSON.parse_string(FileAccess.get_file_as_string(a.substr(8)))
		elif a.begins_with("--hide="):
			_hide = a.substr(7).split(",")
		elif a.begins_with("--noshadow="):
			_noshadow = a.substr(11).split(",")
		elif a.begins_with("--shadowdist="):
			_shadow_dist = float(a.substr(13))
		elif a.begins_with("--lodscale="):
			_lod_scale = float(a.substr(11))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var world := Node3D.new()
	root.add_child(world)
	var scene := (load(_map) as PackedScene).instantiate()
	world.add_child(scene)
	# 與 main.gd 一致：地形網格在載入時才生成 trimesh 碰撞。沒有它，"g+1.7" 的地面射線打不到東西 → 相機座標 NaN → 整個場景不裁切
	# （2026-10-22 發現：先前 court_N／forest_W 兩個視角的數字完全相同＝整張圖全畫，不能當證據）
	for tn in scene.find_children("Terrain", "MeshInstance3D", true, false):
		(tn as MeshInstance3D).create_trimesh_collision()
	await physics_frame
	await physics_frame
	for hn in _hide:
		var hnode := scene.get_node_or_null(hn) as Node3D
		if hnode != null:
			hnode.visible = false
	for sn in _noshadow:
		var snode := scene.get_node_or_null(sn)
		if snode != null:
			_set_noshadow(snode)
	if _shadow_dist > 0.0:
		_set_shadow_dist(scene, _shadow_dist)
	if _lod_scale != 1.0:
		for gname in ["樹木", "下層植栽"]:
			var gnode := scene.get_node_or_null(gname)
			if gnode != null:
				_scale_lod(gnode, _lod_scale)
	var cam := Camera3D.new()
	cam.far = 4000.0
	world.add_child(cam)
	cam.current = true
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 20:
		await process_frame
	print("[PERF] map=%s  GPU=%s" % [_map, RenderingServer.get_video_adapter_name()])
	for v in _views:
		var c: Array = v["cam"]
		var l: Array = v["look"]
		var cy = c[1]
		var ly = l[1]
		if typeof(cy) == TYPE_STRING:
			var g := _ground(world, float(c[0]), float(c[2]))
			cy = g + float(String(cy).substr(2))
		if typeof(ly) == TYPE_STRING:
			var g2 := _ground(world, float(l[0]), float(l[2]))
			ly = g2 + float(String(ly).substr(2))
		if is_nan(float(cy)) or is_nan(float(ly)):
			print("[PERF] %-14s 略過：地面射線沒打到（相機座標 NaN）" % v["name"])
			continue
		cam.global_position = Vector3(c[0], cy, c[2])
		cam.look_at(Vector3(l[0], ly, l[2]), Vector3.UP)
		for i in 30:
			await process_frame
		var gpu := 0.0
		var cpu := 0.0
		var wall := 0.0
		var n := 90
		var t0 := Time.get_ticks_usec()
		for i in n:
			await process_frame
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		wall = float(Time.get_ticks_usec() - t0) / 1000.0 / n
		print("[PERF] %-14s gpu %.2f ms  cpu %.2f ms  wall %.2f ms (%.0f fps)  draw_calls %d  prims %.2f M  objects %d" % [
			v["name"], gpu / n, cpu / n, wall, 1000.0 / maxf(wall, 0.001),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1.0e6,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))])
	print("[PERF] video_mem %.0f MB  texture_mem %.0f MB" % [Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0])
	quit()
