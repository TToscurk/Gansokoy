extends SceneTree
## 獸道 S04 實景擷取（非 headless）：正式 main.tscn + 真玩家 + 玩家自己的第三人稱相機。
##   godot --path godot --script res://tools/beast_path/tps_shots.gd -- --map=beast_path --out=<dir> [--hour=10] [--only=a,b] [--w=1600 --h=900] [--hide=<組1>|<組2>]
## --hide：隔離渲染（找穿幫來源）。每組是逗號分隔的名稱子字串（不分大小寫）或 meta:<鍵>；每組各拍一張（檔名 __h1、__h2…），拍完還原。
## 兩種鏡位：
##   t* ＝ TPS：玩家站到指定位置／朝向（可帶 pitch、dist＝玩家用滑鼠看低、滾輪拉近能到的範圍），畫面來自玩家的 SpringArm 相機。
##   f* ＝ 自由攝影機（玩家隱藏）：只用在 TPS 看不到的角度（瀑布近景、俯瞰）。
## 座標：at＝[x,z]；arena＝[deg,r]（0=北、90=東、180=南、270=西，圓心取 layout boss_arena.c）。
## face＝羅盤方位角度（0=北、90=東、180=南、270=西）。
const BP := preload("res://tools/beast_path/bp_lib.gd")

var main: Node
var player: CharacterBody3D
var adapter: Node
var lib: BP


func _initialize() -> void:
	_go.call_deferred()


func _views() -> Array:
	var c0 := lib.arena_c()
	var fall := Vector2(float(lib.L["boss_arena"]["waterfall"]["x"]), float(lib.L["boss_arena"]["waterfall"]["z"]))
	var to_fall := rad_to_deg(atan2(fall.x - c0.x, -(fall.y - c0.y)))
	return [
		# --- 規格 T20 的 10 張（TPS）
		{"name": "t01_entrance_south", "arena": [180.0, 34.0], "face": 0.0},
		{"name": "t02_entrance_to_center", "arena": [180.0, 21.0], "face": 0.0},
		{"name": "t03_center_ground_close", "arena": [200.0, 3.0], "face": 20.0, "pitch": -0.62, "dist": 3.4},
		{"name": "t04_center_to_waterfall", "at": [c0.x, c0.y + 2.0], "face": to_fall},
		{"name": "t05_pool_waterfall", "at": [fall.x, fall.y + 15.0], "face": 0.0, "pitch": -0.06, "dist": 5.0},
		{"name": "t06_north_wall", "arena": [8.0, 15.0], "face": 0.0, "pitch": 0.0},
		{"name": "t07_outer_forest_east", "arena": [90.0, 17.0], "face": 90.0},
		{"name": "t08_ground_forest_transition", "arena": [250.0, 19.0], "face": 250.0, "pitch": -0.22},
		{"name": "t09_boss_spawn_player_view", "arena": [180.0, 15.0], "face": 0.0},
		{"name": "t10_look_back_to_road", "arena": [180.0, 8.0], "face": 180.0},
		# --- 補充（TPS）
		{"name": "t11_ne_exit", "arena": [40.0, 14.0], "face": 50.0},
		{"name": "t12_seam_s03_s04", "at": [float(lib.main.pos_at(lib.st_s("s03_s04") - 8.0).x), float(lib.main.pos_at(lib.st_s("s03_s04") - 8.0).y)], "face": 0.0},
		{"name": "t13_west_wall_altar", "arena": [270.0, 15.0], "face": 270.0, "pitch": -0.1},
		# --- 自由攝影機
		{"name": "f01_waterfall_closeup", "free": {"cam": [fall.x + 3.5, 0.0, fall.y + 13.0], "look": [fall.x, 0.0, fall.y - 4.0], "cam_above": 2.2, "look_above": 6.5}},
		{"name": "f02_pool_surface", "free": {"cam": [fall.x - 6.5, 0.0, fall.y + 6.5], "look": [fall.x + 0.5, 0.0, fall.y - 0.5], "cam_above": 1.9, "look_above": 0.2}},
		{"name": "f03_cliff_overview", "free": {"cam": [c0.x + 4.0, 0.0, c0.y + 10.0], "look": [fall.x, 0.0, fall.y - 6.0], "cam_above": 7.0, "look_above": 8.5}},
		{"name": "f04_arena_aerial", "free": {"cam": [c0.x + 2.0, 0.0, c0.y + 46.0], "look": [c0.x, 0.0, c0.y - 8.0], "cam_above": 26.0, "look_above": 0.0}},
		{"name": "f05_ground_macro", "free": {"cam": [c0.x + 1.5, 0.0, c0.y + 6.0], "look": [c0.x - 1.0, 0.0, c0.y + 1.5], "cam_above": 1.25, "look_above": 0.0}},
		# --- V1.2 補充（岩群／樹根／倒木／入口守門岩／溪缺口）
		{"name": "t14_approach_gate", "arena": [180.0, 62.0], "face": 0.0},
		{"name": "t15_east_bank", "arena": [120.0, 17.0], "face": 120.0},
		{"name": "t16_west_stream_gap", "arena": [262.0, 16.0], "face": 262.0},
		{"name": "t17_center_to_entrance", "arena": [0.0, 3.0], "face": 180.0},
		{"name": "f06_roots_east", "free": {"cam": [26.0, 0.0, -391.6], "look": [30.5, 0.0, -394.7], "cam_above": 1.7, "look_above": 0.1}},
		{"name": "f07_cover_log", "free": {"cam": [-3.8, 0.0, -406.4], "look": [-9.1, 0.0, -411.1], "cam_above": 1.8, "look_above": 0.3}},
		{"name": "f08_entrance_jaws", "free": {"cam": [c0.x, 0.0, c0.y + 52.0], "look": [c0.x, 0.0, c0.y + 30.0], "cam_above": 3.2, "look_above": 3.6}},
		{"name": "f09_falls_head", "free": {"cam": [-1.0, 0.0, -424.0], "look": [-7.0, 0.0, -453.0], "cam_above": 40.0, "look_above": 0.0}},
		{"name": "f10_falls_lip", "free": {"cam": [-1.5, 0.0, -437.5], "look": [-8.0, 0.0, -447.0], "cam_above": 24.5, "look_above": 0.2}},
	]


func _go() -> void:
	var out := ""
	var hour := 10.0
	var only: PackedStringArray = []
	var win := Vector2i(1600, 900)
	var hide_sets: Array = []
	var budget_off := false
	for a: String in OS.get_cmdline_user_args():
		if a == "--budget=off":
			budget_off = true                               # 對照用：還原 S04 ShadowBudget 關掉的所有投影（拍「沒有陰影預算」的版本）
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--hour="):
			hour = float(a.trim_prefix("--hour="))
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
		elif a.begins_with("--hide="):
			for g in a.trim_prefix("--hide=").split("|"):
				hide_sets.append(g.split(","))
		elif a.begins_with("--w="):
			win.x = int(a.trim_prefix("--w="))
		elif a.begins_with("--h="):
			win.y = int(a.trim_prefix("--h="))
	if out == "":
		push_error("需要 --out=<dir>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	lib = BP.new()
	lib.setup(true, true)
	get_root().size = win
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var t0 := Time.get_ticks_msec()
	while true:
		await physics_frame
		player = main.get("player")
		if player and String(main.get("current_id")) == "beast_path" and player.is_on_floor():
			break
		if Time.get_ticks_msec() - t0 > 120000:
			print("[TPS] ✗ 120 秒內沒進到 beast_path")
			quit(2)
			return
	adapter = player.get_node("CameraAdapter")
	adapter.set_process_unhandled_input(false)
	player.set_process_unhandled_input(false)
	var dn := root.get_node_or_null("DayNight")
	if dn != null:
		dn.set("flowing", false)
		dn.call("set_hour", hour)
	print("[TPS] 進圖 OK；DayNight=%s；視窗 %s" % [str(dn != null), str(get_root().size)])
	for _i in 12:
		await process_frame
	var sbn := main.find_child("ShadowBudget", true, false)
	if sbn != null:
		if budget_off:
			sbn.call("restore_all")
		else:
			sbn.call("apply", true)                          # 時刻剛改過：不等 _process 的 1 秒節拍，立刻依現在的太陽重算
		print("[TPS] ShadowBudget：%s；關閉 %s／%s 個幾何體；太陽仰角 %.1f°" % ["已還原（對照）" if budget_off else "啟用中", str(sbn.get_meta("shadow_off_geoms", "?")) if not budget_off else "0", str(sbn.get_meta("shadow_total_geoms", "?")), float(sbn.get_meta("sun_elev_deg", 0.0))])
	var gp_cam: Camera3D = player.get_viewport().get_camera_3d()
	var free_cam := Camera3D.new()
	free_cam.fov = 62.0
	free_cam.far = 900.0
	root.add_child(free_cam)
	var n_ok := 0
	for v: Dictionary in _views():
		var nm := String(v["name"])
		if not only.is_empty() and not only.has(nm):
			continue
		_hide_hud()
		if v.has("free"):
			var fr: Dictionary = v["free"]
			var cm: Array = fr["cam"]
			var lk: Array = fr["look"]
			var cy := lib.h_at(float(cm[0]), float(cm[2])) + float(fr.get("cam_above", 2.0))
			var ly := lib.h_at(float(lk[0]), float(lk[2])) + float(fr.get("look_above", 1.0))
			free_cam.global_position = Vector3(float(cm[0]), cy, float(cm[2]))
			free_cam.look_at(Vector3(float(lk[0]), ly, float(lk[2])))
			free_cam.make_current()
			player.visible = false
		else:
			var q: Vector2
			if v.has("arena"):
				q = lib.arena_pos(float(v["arena"][0]), float(v["arena"][1]))
			else:
				q = Vector2(float(v["at"][0]), float(v["at"][1]))
			await _put(q, -deg_to_rad(float(v["face"])), float(v.get("pitch", -0.18)), float(v.get("dist", 8.5)))
			if gp_cam != null:
				gp_cam.make_current()
			player.visible = true
		for i in 70:
			await process_frame
		var img := get_root().get_texture().get_image()
		var path := "%s/%s.png" % [out, nm]
		img.save_png(path)
		n_ok += 1
		var hi := 0
		for hs: PackedStringArray in hide_sets:
			hi += 1
			var hidden := _hide_matching(hs)
			for i in 6:
				await process_frame
			get_root().get_texture().get_image().save_png("%s/%s__h%d.png" % [out, nm, hi])
			print("    隔離 h%d [%s]：隱藏 %d 個節點" % [hi, ",".join(hs), hidden.size()])
			for n3: Node3D in hidden:
				n3.visible = true
		var pp := player.global_position
		print("  ✓ %-30s player=(%.1f, %.1f, %.1f)  %dx%d" % [nm, pp.x, pp.y, pp.z, img.get_width(), img.get_height()])
	print("[TPS] 完成 %d 張 → %s" % [n_ok, out])
	quit(0)


func _hide_matching(tokens: PackedStringArray) -> Array[Node3D]:
	var res: Array[Node3D] = []
	for n in main.find_children("*", "Node3D", true, false):
		var n3 := n as Node3D
		if not n3.visible:
			continue
		var hit := false
		for t in tokens:
			if t.begins_with("meta:"):
				hit = hit or n3.has_meta(t.trim_prefix("meta:"))
			elif String(n3.name).to_lower().contains(t.to_lower()):
				hit = true
		if hit:
			n3.visible = false
			res.append(n3)
	return res


func _hide_hud() -> void:
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false


func _put(q: Vector2, yaw: float, pitch: float, dist: float) -> void:
	var sp := player.get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(Vector3(q.x, 80.0, q.y), Vector3(q.x, -60.0, q.y), player.collision_mask)
	rq.exclude = [player.get_rid()]
	var r := sp.intersect_ray(rq)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(q.x, (float((r["position"] as Vector3).y) if not r.is_empty() else 2.0) + 0.2, q.y)
	adapter.set("_target_yaw", yaw)
	adapter.set("_target_pitch", pitch)
	adapter.set("_current_pitch", pitch)
	adapter.set("_target_distance", dist)
	adapter.set("_current_distance", dist)
	if player.has_method("snap_yaw"):
		player.snap_yaw(yaw)
	for i in 30:
		await physics_frame
