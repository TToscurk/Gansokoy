extends SceneTree
## 新版地圖接管（2026-10-23）審圖截圖：真的 main.tscn（傳送光印由 main 生成）、固定鏡位、可指定時刻。
##   godot --path godot --script res://tools/capture_new_world.gd -- --out=<abs dir>
## ⚠ 不可加 --headless（要真的渲染）。HUD 全藏。

var main: Node
var player: CharacterBody3D
var out_dir := ""

## [名稱, 地圖, 時刻, 相機, 看向, 玩家位置（null＝放遠處 → 光印待機亮度）]
const SHOTS := [
	["01_reimu_front", "shrine_v3", 10.0, Vector3(-0.2, 31.55, -12.9), Vector3(-1.35, 30.95, -16.95), Vector3(0.0, 30.2, -9.0)],
	["02_reimu_close", "shrine_v3", 10.0, Vector3(-1.05, 31.35, -15.0), Vector3(-1.35, 30.85, -16.95), Vector3(0.0, 30.2, -9.0)],
	["03_reimu_sando", "shrine_v3", 10.0, Vector3(0.0, 32.6, -2.5), Vector3(-0.6, 30.8, -17.5), Vector3(-0.2, 30.2, -12.6)],
	["04_seal_shrine_lit", "shrine_v3", 10.0, Vector3(-16.6, 7.4, 88.6), Vector3(-18.0, 4.6, 94.6), Vector3(-17.3, 4.9, 93.6)],
	["05_seal_shrine_idle", "shrine_v3", 10.0, Vector3(-16.6, 7.4, 88.6), Vector3(-18.0, 4.6, 94.6), null],
	["06_seal_shrine_night", "shrine_v3", 21.5, Vector3(-16.6, 7.4, 88.6), Vector3(-18.0, 4.6, 94.6), Vector3(-17.3, 4.9, 93.6)],
	["07_seal_beast_south", "beast_path", 10.0, Vector3(1.2, 2.6, -0.8), Vector3(0.0, 0.3, 6.0), Vector3(0.6, 0.6, 5.0)],
	["08_seal_beast_north", "beast_path", 10.0, Vector3(44.6, 20.6, -434.0), Vector3(46.0, 17.6, -441.0), Vector3(45.6, 18.0, -440.0)],
	["09_seal_village_south", "village_v2", 10.0, Vector3(219.5, 2.9, 166.0), Vector3(224.0, 0.4, 172.0), Vector3(223.4, 0.6, 171.0)],
	["10_seal_village_hieda", "village_v2", 10.0, Vector3(396.0, 3.2, 9.0), Vector3(398.0, 0.6, 2.0), Vector3(398.6, 0.8, 3.0)],
	["11_seal_village_night", "village_v2", 21.5, Vector3(219.5, 2.9, 166.0), Vector3(224.0, 0.4, 172.0), Vector3(223.4, 0.6, 171.0)],
]


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func set_hour(h: float) -> void:
	for nm in ["DayNight", "WorldTimeManager"]:
		var n: Node = root.get_node_or_null("/root/" + nm)
		if n == null:
			continue
		if n.has_method("set_hour"):
			n.call("set_hour", h)
		elif "hour" in n:
			n.set("hour", h)
		if "time_scale" in n:
			n.set("time_scale", 0.0)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await frames(3)
	player = main.get("player")
	var cam := Camera3D.new()
	cam.fov = 60.0
	root.add_child(cam)
	var cur_map := ""
	for s in SHOTS:
		if s[1] != cur_map:
			main.call("load_map", s[1], "")
			cur_map = s[1]
			await frames(40)
		for cl in main.find_children("*", "CanvasLayer", true, false):
			(cl as CanvasLayer).visible = false
		set_hour(float(s[2]))
		player.velocity = Vector3.ZERO
		if s[5] == null:
			# 水平遠離光印（> far_dist 10 m）、停掉物理免得掉落：光印維持待機亮度
			player.set_physics_process(false)
			player.global_position = Vector3(s[4]) + Vector3(40, 30, 0)
			player.visible = false
		else:
			player.set_physics_process(true)
			player.global_position = s[5]
			player.visible = true
		cam.global_position = s[3]
		cam.look_at(s[4])
		cam.current = true
		await frames(150)            # 光印點亮 ≈1.6 s＋粒子
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		var path := "%s/%s.png" % [out_dir, s[0]]
		img.save_png(path)
		print("[SHOT] ", path)
	quit(0)
