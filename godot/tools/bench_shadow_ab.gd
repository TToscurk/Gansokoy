extends SceneTree
## 陰影預算 A/B：關掉每一類投影各值多少 FPS。
##
##   Godot --path godot --script tools/bench_shadow_ab.gd
##   （需要渲染，不可 --headless）
##
## 為什麼要這支：24.3M 投影面是目前的瓶頸，但「關誰」是視覺取捨，得先知道
## 每一項的價碼。路燈關投影只值 0.7%（實測 44→43 fps，在誤差內）——那次
## 教訓是：不量就改，會把時間花在沒有價值的地方。
##
## 每一組都在同一機位、同一時刻、同一組旗標下量，唯一的變數是「哪一類
## 節點的 cast_shadow 被關掉」。

const WARMUP := 60
const SAMPLE := 120
## 主街街道：玩家真正會待的視角。俯瞰是最壞情況，但不是體驗基準。
const CAM_POS := Vector3(235.0, 1.7, -10.0)
const CAM_LOOK := Vector3(235.0, 3.0, 60.0)

## 每一組：標籤 + 要關閉投影的頂層節點名。空陣列 = 對照組。
const CASES := [
	["對照（現況）", []],
	["關 B1_Street", ["B1_Street"]],
	["關 竹垣 TakeFence", ["TakeFence"]],
	["關 5 片 VillageTrees", ["VillageTrees", "VillageTrees2", "VillageTrees3",
		"VillageTrees4", "VillageTrees5"]],
	["關 MachiCanal 全部", ["MachiCanal"]],
	["三者全關", ["B1_Street", "TakeFence", "VillageTrees", "VillageTrees2",
		"VillageTrees3", "VillageTrees4", "VillageTrees5"]],
]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	print("[AB] %-22s %7s %8s %9s %12s %10s" % [
		"組別", "FPS", "GPU ms", "draw", "投影面", "省下"])

	var base_fps := 0.0
	var base_shadow := 0
	for case in CASES:
		var label: String = case[0]
		var targets: Array = case[1]

		var packed := ResourceLoader.load("res://maps/slice/slice.tscn", "PackedScene",
			ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
		var scene := packed.instantiate()
		root.add_child(scene)
		# 讓 場景效能裁剪 先跑完它自己的規則，再疊我們的實驗
		await process_frame
		await process_frame
		await process_frame

		var off := 0
		for nm in targets:
			var n := scene.find_child(nm, true, false)
			if n == null:
				continue
			off += _kill_shadows(n)

		var cam := Camera3D.new()
		cam.fov = 72.0
		cam.far = 4000.0
		root.add_child(cam)
		cam.global_position = CAM_POS
		cam.look_at(CAM_LOOK, Vector3.UP)
		cam.current = true

		var vp := root.get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		for i in WARMUP:
			await process_frame

		var fps := 0.0
		var gpu := 0.0
		var draws := 0.0
		for i in SAMPLE:
			await process_frame
			fps += Performance.get_monitor(Performance.TIME_FPS)
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		fps /= SAMPLE
		gpu /= SAMPLE
		draws /= SAMPLE
		var sh_prims := RenderingServer.viewport_get_render_info(vp,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW,
			RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)

		if base_fps == 0.0:
			base_fps = fps
			base_shadow = sh_prims
			print("[AB] %-22s %7.1f %8.2f %9.0f %12s %10s" % [
				label, fps, gpu, draws, _fmt(sh_prims), "—"])
		else:
			print("[AB] %-22s %7.1f %8.2f %9.0f %12s %+9.1f%% / %s面" % [
				label, fps, gpu, draws, _fmt(sh_prims),
				(fps - base_fps) / base_fps * 100.0,
				_fmt(base_shadow - sh_prims)])

		cam.queue_free()
		scene.queue_free()
		await process_frame
		await process_frame

	print("[AB] done")
	quit(0)


func _kill_shadows(n: Node) -> int:
	var c := 0
	if n is GeometryInstance3D:
		var gi := n as GeometryInstance3D
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			c += 1
	for ch in n.get_children():
		c += _kill_shadows(ch)
	return c


func _fmt(v: int) -> String:
	var s := str(v)
	var out := ""
	var k := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		k += 1
		if k % 3 == 0 and i > 0:
			out = "," + out
	return out
