extends SceneTree
## 驗證魔理莎隨性散步＋玩家互動（npc_casual_actor）。非 headless（要截圖）。
##   godot --path godot -s res://tools/marisa/verify_marisa_casual.gd -- [--out=<dir/>] [--scale=3] [--sec=90]
## 流程：(1) 沒有玩家：Engine.time_scale 加速跑 --sec 秒，記錄動作／狀態切換、位置、是否離開路線、最大步長；
##      (2) 放一個假玩家（group "player"）逼近 3 m：驗證停步→轉向→打招呼→閒聊，截圖；
##      (3) 假玩家離開：驗證結束閒聊、轉回路線繼續走。
const SIZE := Vector2i(1600, 900)
const NAMES := ["WALK", "PAUSE", "TURN", "CHAT"]
var out := "D:/神社/shrine/docs/marisa/casual/"
var tscale := 3.0
var sec := 90.0
var actor: Node3D
var npc: Node
var cam: Camera3D
var dummy: Node3D
var log: Array = []
var last_key := ""
var t_sim := 0.0
var max_step := 0.0
var last_pos := Vector3.ZERO
var seen := {}
var nolook := false
var gaze: Array = []
var _last_gaze := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--scale="): tscale = float(a.substr(8))
		elif a.begins_with("--sec="): sec = float(a.substr(6))
		elif a == "--nolook": nolook = true
	run.call_deferred()


func _snap(name: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + name + ".png")
	print("[CASUAL] SHOT ", name)


## off 是相對角色朝向的位置（+Z＝她的正面，+X＝她的左側）；look_h＝注視高度。
func _cam_follow(off: Vector3 = Vector3(-1.4, 1.3, 3.2), look_h := 1.05) -> void:
	var p := actor.global_position
	cam.global_position = p + actor.global_transform.basis * off
	cam.look_at(p + Vector3(0, look_h, 0), Vector3.UP)


## 玩家視角：相機放在假玩家頭部高度，看向她的胸口。
func _cam_player() -> void:
	cam.global_position = dummy.global_position + Vector3(0, 1.45, 0)
	cam.look_at(actor.global_position + Vector3(0, 1.15, 0), Vector3.UP)


func _state() -> String:
	return "%s/%s" % [NAMES[int(actor.get("_st"))], String(npc.get("animation"))]


func _tick(dt_real: float) -> void:
	var k := _state()
	if k != last_key:
		last_key = k
		log.append("t=%6.1f %-18s pos (%.1f, %.2f, %.1f) u %.1f dir %d" % [t_sim, k, actor.global_position.x, actor.global_position.y, actor.global_position.z, float(actor.get("_u")), int(actor.get("_dir"))])
		seen[k] = true
	max_step = maxf(max_step, actor.global_position.distance_to(last_pos))
	last_pos = actor.global_position


func run() -> void:
	root.size = SIZE
	DirAccess.make_dir_recursive_absolute(out)
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	_add_sun(10.0)
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		if v.has_node(nm): v.get_node(nm).visible = false
	actor = v.get_node("Population/MarisaNPC/M1_marisa") as Node3D
	npc = actor.get_node("NPC")
	cam = Camera3D.new(); cam.fov = 42.0; v.add_child(cam); cam.current = true
	dummy = Node3D.new(); dummy.name = "DummyPlayer"; v.add_child(dummy); dummy.add_to_group("player")
	dummy.global_position = Vector3(actor.global_position.x + 60.0, 0, actor.global_position.z + 60.0)
	if nolook: actor.set("head_look", false)
	var sk0 := npc.find_child("GeneralSkeleton", true, false) as Skeleton3D
	sk0.skeleton_updated.connect(func():     # 修改器（頭部看向）的結果只在 skeleton_updated 讀得到
		var hb := sk0.global_transform * sk0.get_bone_global_pose(sk0.find_bone("Head"))
		var fwd := (hb.basis * Vector3.BACK).normalized()
		var to_p := ((dummy.global_position + Vector3(0, 1.45, 0)) - hb.origin).normalized()
		_last_gaze = rad_to_deg(Vector3(fwd.x, 0, fwd.z).normalized().angle_to(Vector3(to_p.x, 0, to_p.z).normalized())))
	for i in 6: await physics_frame
	print("[CASUAL] start pos ", actor.global_position, " len ", actor.get("_len"), " mode ", actor.get("mode"))
	last_pos = actor.global_position
	# (1) 沒有玩家的散步
	Engine.time_scale = tscale
	var shot_browse := false
	var shot_funny := false
	var shot_walk := false
	while t_sim < sec:
		await physics_frame
		t_sim += 1.0 / Engine.physics_ticks_per_second
		_tick(0.0)
		var an := String(npc.get("animation"))
		if not shot_walk and an == "walk" and t_sim > 2.0:
			shot_walk = true; Engine.time_scale = 1.0; _cam_follow(); await _snap("a_walk"); Engine.time_scale = tscale
		if not shot_browse and an == "browse":
			shot_browse = true; Engine.time_scale = 1.0; _cam_follow(Vector3(1.2, 1.2, 2.6), 1.0); await _snap("b_browse"); Engine.time_scale = tscale
		if not shot_funny and an == "talk_funny" and int(actor.get("_st")) == 1:
			shot_funny = true; Engine.time_scale = 1.0; _cam_follow(Vector3(-1.2, 1.3, 3.0), 1.1); await _snap("c_talk_alone"); Engine.time_scale = tscale
	print("[CASUAL] --- phase1 log (no player) ---")
	for l in log: print("[CASUAL] ", l)
	print("[CASUAL] max per-physics-step move %.3f m (time_scale %.0f)" % [max_step, tscale])
	# (2) 玩家逼近
	Engine.time_scale = 1.0
	log.clear(); last_key = ""; t_sim = 0.0
	var f := Vector3(sin(actor.rotation.y), 0, cos(actor.rotation.y))
	dummy.global_position = actor.global_position + f * 3.6 + Vector3(0.0, 0.0, 0.0)
	# 玩家站在她前進方向 3.6 m（react_radius 4.0 內）
	var t0 := 0.0
	var phase := 0
	var t_greet := 0.0
	while t0 < 22.0:
		await physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		t0 += dt; t_sim = t0
		_tick(dt)
		var st := int(actor.get("_st"))
		var an := String(npc.get("animation"))
		if phase == 0 and st == 3 and an == "talk_twohands":
			phase = 1; t_greet = t0
			print("[CASUAL] 打招呼開始 t=%.1f（玩家出現後）" % t0)
		elif phase == 1 and t0 - t_greet > 1.3:
			phase = 2; _cam_player(); await _snap("d_greet")
		elif phase == 2 and st == 3 and an in ["talk_general", "talk_funny"]:
			phase = 3; var yaw_err := absf(angle_difference(actor.rotation.y, atan2(dummy.global_position.x - actor.global_position.x, dummy.global_position.z - actor.global_position.z)))
			print("[CASUAL] chat clip ", an, " facing error to player %.1f deg" % rad_to_deg(yaw_err))
		if phase >= 2 and st == 3:
			gaze.append(_last_gaze)
		if phase == 3 and t0 - t_greet > 8.0:
			phase = 4; _cam_player(); await _snap("e_chat")
	if gaze.size() > 0:
		var mx := 0.0; var sm := 0.0
		for g in gaze: mx = maxf(mx, g); sm += g
		print("[CASUAL] 閒聊時頭部水平朝向與玩家頭部方向的夾角 平均 %.1f° 最大 %.1f°（%d 筆，head_look=%s）" % [sm / gaze.size(), mx, gaze.size(), str(not nolook)])
	print("[CASUAL] --- phase2 log (player near) ---")
	for l in log: print("[CASUAL] ", l)
	# (3) 玩家離開
	log.clear(); last_key = ""
	dummy.global_position = actor.global_position + Vector3(40, 0, 40)
	t0 = 0.0
	var resumed := false
	while t0 < 14.0:
		await physics_frame
		t0 += 1.0 / Engine.physics_ticks_per_second; t_sim = t0
		_tick(0.0)
		if not resumed and int(actor.get("_st")) == 0 and String(npc.get("animation")) == "walk":
			resumed = true
			_cam_follow(Vector3(-1.4, 1.3, 3.2)); await _snap("f_resume_walk")
	print("[CASUAL] --- phase3 log (player left) resumed=", resumed, " ---")
	for l in log: print("[CASUAL] ", l)
	print("[CASUAL] states seen: ", seen.keys())
	quit(0)


func _add_sun(hour: float) -> void:
	var main := Node3D.new()
	var gs := GDScript.new()
	gs.source_code = "extends Node3D\nvar map_root: Node = null\n"
	gs.reload()
	main.set_script(gs)
	main.name = "Main"
	root.add_child(main)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100.0
	main.add_child(sun)
	var dn: Node = root.get_node_or_null("DayNight")
	if dn != null:
		dn.set("flowing", false)
		dn.call("set_hour", hour)
