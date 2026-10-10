extends SceneTree
const P11R2Swap := preload("res://tools/p11r2/p11r2_swap.gd")
## P10 FINAL 統合走訪（Read-Only Review）：正式 main.tscn の通常 F5 経路（scripts/main.gd → ReviewStart の review spawn → village_v2）で、
## 既存の TPS 相機（Player/CameraAdapter）・10:00（review start の凍結）のまま、実際の入力で道を歩く。場景・封存には一切書き込まない。
##   godot --path godot --script res://tools/walk_p10_final.gd -- --review=kirisame --out=<dir/>           走訪（非 headless、録画・still・log）
##   godot --headless --path godot --script res://tools/walk_p10_final.gd -- --precheck                    ルートの事前点検（headless、village_v2 だけ）
##   -- --route=res://tools/walk_p10_rehab_sando_route.json …   別ルート（P10 R6b 參道石段の上下通行テスト）
## 歩き方：毎 physics frame に Input.action_press("move_forward")（＝プレイヤーの W）、視線は CameraAdapter._target_yaw を進む方向へ
##   （＝マウスで向きを変える；相機の rotation_smoothing・SpringArm はそのまま）。向きの差 > 50° の間は前進を離して振り向く。
##   瞬間移動しない（開始は review spawn から歩く）。詰まったら左右へ 0.6 s 横歩き（moved < 0.4 m / 1.5 s）を最大 6 回、それでも駄目なら BLOCKED を記録して次へ。
## 記録：0.1 s（6 physics tick）ごとに 960×540 JPG（区間ごと）、still＝1600×900 PNG（止まって look へ向きを変え 1.4 s 落ち着かせる）、
##   0.5 s ごとのサンプル（位置・接地・速度・SpringArm 実長／設定長・fps・最寄り NPC）と事件（STUCK／BLOCKED／ARM_PULL／DIALOGUE）を JSON に。
## P11 R1 追加（2026-10-10）：
##   --start=trail   起動後に main.load_map("village_v2", "trail")＝獸道から村へ入る正式の落点から歩き始める（落点・着地時間を記録）
##   --step=<m>      診断用：プレイヤーの step_height をメモリ上だけ上書き（ファイル不変；乗り上がり帯の比較）
##   route の追加ステップ ["tp", x, z, yaw] ＝区間テスト用の配置（地面＋0.1、20 tick 落ち着かせる；事件 TP として記録）、
##   ["xbridge", "Bridge_0N"] ＝橋の中心へ最寄りの道路線の方向で橋長＋8 m を往復
##   事件 LIFT＝接地中、足元の最初の当たりが構件（Props／HumanUse*／Vegetation／EnvironmentP9 の Collision）で地形より 0.2 m 以上高い
##         NPC_CONTACT＝プレイヤーの滑り衝突の相手が Population の NPC（連続 0.5 s 以上で 1 件）
## HUD（CanvasLayer）は撮影のため非表示（main.gd の "hud": false と同じ扱い）。マウスは捕捉しない（ユーザーの操作を奪わない・入力を混ぜない）。
const ROUTE := "res://tools/walk_p10_final_route.json"
const WIN := Vector2i(1600, 900)
const VID := Vector2i(960, 540)
const FRAME_TICKS := 6
const SAMPLE_TICKS := 30
const TURN_GATE := deg_to_rad(50.0)
const ARRIVE := 1.1
const LOOKAHEAD := 2.5

var outdir := ""
var main: Node
var player: CharacterBody3D
var adapter: Node
var arm: SpringArm3D
var cam: Camera3D
var vil: Node3D
var dm: Node
var log := {"samples": [], "events": [], "segments": [], "stills": []}
var seg_name := ""
var seg_rec := false
var seg_frame := 0
var tick := 0
var seg_t0 := 0
var seg_dist := 0.0
var last_pos := Vector3.ZERO
var fps_acc: Array = []
var npcs: Array = []


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	if "--precheck" in args:
		await _precheck()
		quit(0)
		return
	for a: String in args:
		if a.begins_with("--grid="):
			await _grid(a.trim_prefix("--grid="))
			quit(0)
			return
	for a: String in args:
		if a.begins_with("--out="):
			outdir = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(outdir + "frames")
	DisplayServer.window_set_size(WIN)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	# P11 R2：--candidate=A|B|C（候補スクリプトをメモリ上で差し替え、ファイル不変；tools/p11r2/p11r2_swap.gd）
	var _cand := P11R2Swap.parse(OS.get_cmdline_user_args())
	if _cand != "":
		print("[P11R2] candidate ", P11R2Swap.apply(main, _cand))
	root.add_child(main)
	current_scene = main
	# review start（main.gd → ReviewStart.apply）が終わるまで：プレイヤーが village_v2 の spawn に立つ
	var t0 := Time.get_ticks_msec()
	while true:
		await physics_frame
		player = main.get("player")
		vil = root.find_child("VillageV2", true, false) as Node3D
		if player and vil and player.global_position.distance_to(Vector3(237.1, player.global_position.y, 71.7)) < 3.0 and player.is_on_floor():
			break
		if Time.get_ticks_msec() - t0 > 90000:
			push_error("boot timeout")
			quit(2)
			return
	for i in 30:
		await physics_frame
	adapter = player.get_node("CameraAdapter")
	arm = adapter.get("arm")
	cam = player.find_child("Camera3D", true, false) as Camera3D
	dm = root.get_node_or_null("/root/DialogueManager")
	adapter.set_process_unhandled_input(false)
	player.set_process_unhandled_input(false)
	# --pitch=：相機の初期 pitch を固定（起動中のマウス移動で pitch がずれた回を比較に使わないため；P10 R6b ROUND 3）
	for a3: String in args:
		if a3.begins_with("--pitch="):
			adapter.set("_target_pitch", float(a3.trim_prefix("--pitch=")))
			adapter.set("_current_pitch", float(a3.trim_prefix("--pitch=")))
	for a4: String in args:
		if a4.begins_with("--step="):
			player.set("step_height", float(a4.trim_prefix("--step=")))
			log["step_height_override"] = float(a4.trim_prefix("--step="))
	if "--start=trail" in args:
		main.call("load_map", "village_v2", "trail")
		var tl := Time.get_ticks_msec()
		var arrive := Vector3.ZERO
		var floor_t := -1.0
		var fr := 0
		while true:
			await physics_frame
			fr += 1
			if fr == 3:
				arrive = player.global_position
			if fr > 3 and player.is_on_floor():
				floor_t = (fr - 3) / 60.0
				break
			if Time.get_ticks_msec() - tl > 30000:
				break
		for i in 30:
			await physics_frame
		vil = main.get("map_root") as Node3D
		log["start_trail"] = {"arrival": _v3(arrive), "on_floor_after_s": snappedf(floor_t, 0.01), "settled": _v3(player.global_position),
			"map": String(main.get("current_id")), "portal_at": [224, 172]}
		print("[WALK] start=trail %s" % JSON.stringify(log["start_trail"]))
	if vil:
		var tc := vil.get_node_or_null("Collision/TerrainCollision") as CollisionObject3D
		if tc:
			terrain_rid = tc.get_rid()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	for n in vil.find_children("*", "AnimatableBody3D", true, false):
		if n.get_parent() and String(n.get_path()).contains("/Population/"):
			npcs.append(n)
	var dn := root.get_node_or_null("/root/DayNight")
	log["boot"] = {"ms": Time.get_ticks_msec() - t0, "spawn": _v3(player.global_position), "hour": dn.get("hour") if dn else null,
		"npc_bodies": npcs.size(), "arm_length": arm.spring_length, "pitch": adapter.get("_target_pitch"), "window": [WIN.x, WIN.y],
		"renderer": RenderingServer.get_current_rendering_method(), "scene": String(main.scene_file_path)}
	print("[WALK] boot %d ms spawn %s hour %s npc %d renderer %s" % [log["boot"]["ms"], log["boot"]["spawn"], str(log["boot"]["hour"]), npcs.size(), log["boot"]["renderer"]])
	var route_path := ROUTE
	for a2: String in args:
		if a2.begins_with("--route="):
			route_path = a2.trim_prefix("--route=")   # P10 R6b：參道石段通行測試等，用別的路線檔（預設＝P10 FINAL 路線）
	var R: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(route_path))
	log["route"] = route_path
	last_pos = player.global_position
	for step: Array in R["route"]:
		match String(step[0]):
			"seg":
				_end_seg()
				seg_name = String(step[1])
				seg_rec = bool(step[3])
				seg_frame = 0
				seg_t0 = tick
				seg_dist = 0.0
				log["segments"].append({"name": seg_name, "label": String(step[2]), "rec": seg_rec, "start": _v3(player.global_position), "events": 0})
				if seg_rec:
					DirAccess.make_dir_recursive_absolute(outdir + "frames/" + seg_name)
				print("[WALK] seg %s" % seg_name)
			"wp":
				await _walk_to(Vector2(float(step[1]), float(step[2])))
			"still":
				await _still(String(step[1]), Vector2(float(step[2]), float(step[3])))
			"tp":
				await _tp(Vector2(float(step[1]), float(step[2])), float(step[3]) if step.size() > 3 else 0.0)
			"xbridge":
				await _xbridge(String(step[1]))
	_end_seg()
	Input.action_release("move_forward")
	var f := FileAccess.open(outdir + "walk_log.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(log, "\t") + "\n")
	f.close()
	print("[WALK] done events %d stills %d" % [(log["events"] as Array).size(), (log["stills"] as Array).size()])
	quit(0)


func _v3(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


func _end_seg() -> void:
	if seg_name == "":
		return
	var s: Dictionary = log["segments"][-1]
	s["end"] = _v3(player.global_position)
	s["seconds"] = snappedf((tick - seg_t0) / 60.0, 0.1)
	s["walked_m"] = snappedf(seg_dist, 0.1)
	s["frames"] = seg_frame
	var fl: Array = fps_acc.filter(func(x: float) -> bool: return x > 0.0)
	if not fl.is_empty():
		fl.sort()
		s["fps_min"] = fl[0]
		s["fps_med"] = fl[fl.size() / 2]
	fps_acc.clear()


func _yaw_for(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


func _event(kind: String, extra: Dictionary) -> void:
	var e := {"kind": kind, "seg": seg_name, "t": snappedf(tick / 60.0, 0.1), "pos": _v3(player.global_position)}
	e.merge(extra)
	log["events"].append(e)
	(log["segments"][-1] as Dictionary)["events"] = int((log["segments"][-1] as Dictionary)["events"]) + 1
	print("[WALK] EVENT %s" % JSON.stringify(e))


## P11 R2：相機の指標（区間ごと）＝玩家の遮蔽（相機→頭 pivot・相機→体 0.9 m の射線が何かに当たる幀；頭が 6 幀以上続けば OCCLUDED 事件）、
##   腕の長さの幀間変化（|Δ| > 0.5 m/幀＝鏡頭の跳び；伸び方向は CAM_SNAP_OUT 事件）、実効 pitch（pivot.rotation.x）。
##   録画区間（rec）は幀ごとの trace も残す（log.camtrace[seg] = [t, 腕, 望む長さ, 実効 pitch, 坂バイアス, 頭遮蔽, 体遮蔽]）。
var occl_run := 0
var last_hl := -1.0
func _ray_blocked(from: Vector3, to: Vector3) -> Dictionary:
	var rq := PhysicsRayQueryParameters3D.create(from, to)
	rq.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(rq)


func _occl_name(h: Dictionary) -> String:
	var cn := h["collider"] as Node
	if cn == null:
		return "?"
	if vil and vil.is_ancestor_of(cn):
		var pth := String(vil.get_path_to(cn))
		var parts := pth.split("/")
		return "/".join(parts.slice(0, mini(3, parts.size())))
	return String(cn.name)


func _cam_metrics(hl: float) -> void:
	var s: Dictionary = log["segments"][-1] if log["segments"].size() > 0 else {}
	if s.is_empty():
		return
	s["cam_frames"] = int(s.get("cam_frames", 0)) + 1
	var piv := adapter.get("pivot") as Node3D
	var hit := _ray_blocked(cam.global_position, piv.global_position)
	var hit_b := _ray_blocked(cam.global_position, player.global_position + Vector3(0, 0.9, 0))
	if not hit_b.is_empty():
		s["occl_body_frames"] = int(s.get("occl_body_frames", 0)) + 1
		var bn := _occl_name(hit_b)
		var ob: Dictionary = s.get("occl_body_by", {})
		ob[bn] = int(ob.get(bn, 0)) + 1
		s["occl_body_by"] = ob
	if not hit.is_empty():
		s["occl_frames"] = int(s.get("occl_frames", 0)) + 1
		var hn := _occl_name(hit)
		var oh: Dictionary = s.get("occl_head_by", {})
		oh[hn] = int(oh.get(hn, 0)) + 1
		s["occl_head_by"] = oh
		occl_run += 1
		if occl_run == 6:
			var cn := hit["collider"] as Node
			_event("OCCLUDED", {"by": String(vil.get_path_to(cn)) if vil and cn and vil.is_ancestor_of(cn) else (String(cn.name) if cn else "?"), "cam": _v3(cam.global_position)})
	else:
		occl_run = 0
	if last_hl >= 0.0:
		var d := hl - last_hl
		s["arm_dmax"] = maxf(float(s.get("arm_dmax", 0.0)), absf(d))
		if absf(d) > 0.5:
			s["arm_jump_frames"] = int(s.get("arm_jump_frames", 0)) + 1
			if d > 0.0:
				_event("CAM_SNAP_OUT", {"from": snappedf(last_hl, 0.01), "to": snappedf(hl, 0.01)})
	last_hl = hl
	var pe := piv.rotation.x
	var bias := float(adapter.call("slope_bias")) if adapter.has_method("slope_bias") else 0.0
	s["pitch_min"] = minf(float(s.get("pitch_min", 0.0)), pe)
	s["slope_bias_min"] = minf(float(s.get("slope_bias_min", 0.0)), bias)
	if seg_rec or "--camtrace" in OS.get_cmdline_user_args():
		if not log.has("camtrace"):
			log["camtrace"] = {}
		var ct: Dictionary = log["camtrace"]
		if not ct.has(seg_name):
			ct[seg_name] = []
		(ct[seg_name] as Array).append([snappedf(tick / 60.0, 0.01), snappedf(hl, 0.01), snappedf(float(adapter.get("_current_distance")), 0.01),
			snappedf(pe, 0.001), snappedf(bias, 0.001), 0 if hit.is_empty() else 1, 0 if hit_b.is_empty() else 1])


## 1 physics tick：録画・サンプル・対話の監視・距離
var arm_pull_on := false
func _tick() -> void:
	await physics_frame
	tick += 1
	var p := player.global_position
	seg_dist += Vector2(p.x - last_pos.x, p.z - last_pos.z).length()
	last_pos = p
	if dm and dm.call("is_active"):
		_event("DIALOGUE", {"id": str(dm.get("_current"))})
		dm.call("_end")
	# SpringArm が縮む＝相機が建物・屋根・崖に押し込まれた（既知：Market West の屋根）
	var hl := arm.get_hit_length()
	# P11 R2：基準は使用者の望む腕の長さ（_current_distance＝ズーム）。候補 B は伸び戻りをなめらかにするため spring_length を一時的に短くするので、
	#   spring_length ではなく望む長さと比べる（現行の相機では両者は同じ＝R1 と同じ判定）。
	var want_len := float(adapter.get("_current_distance"))
	var pulled := hl < want_len * 0.55
	if pulled and not arm_pull_on:
		_event("ARM_PULL", {"hit_length": snappedf(hl, 0.01), "spring": snappedf(want_len, 0.01), "cam": _v3(cam.global_position)})
	arm_pull_on = pulled
	_cam_metrics(hl)
	_lift_npc_check(p)
	if tick % SAMPLE_TICKS == 0:
		var nd := 1e9
		for n: Node3D in npcs:
			nd = minf(nd, n.global_position.distance_to(p))
		var fps := Engine.get_frames_per_second()
		fps_acc.append(float(fps))
		log["samples"].append({"t": snappedf(tick / 60.0, 0.1), "seg": seg_name, "pos": _v3(p), "floor": player.is_on_floor(),
			"v": snappedf(Vector2(player.velocity.x, player.velocity.z).length(), 0.01), "arm": snappedf(hl, 0.01), "fps": fps, "npc_m": snappedf(nd, 0.1)})
	if seg_rec and tick % FRAME_TICKS == 0:
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.resize(VID.x, VID.y, Image.INTERPOLATE_BILINEAR)
		img.save_jpg(outdir + "frames/%s/%05d.jpg" % [seg_name, seg_frame], 0.82)
		seg_frame += 1


func _walk_to(goal: Vector2) -> void:
	var start := Vector2(player.global_position.x, player.global_position.z)
	var hist: Array = []
	var nudges := 0
	var nudge_dir := 1
	var guard := 0
	while true:
		var p := Vector2(player.global_position.x, player.global_position.z)
		var to_goal := goal - p
		if to_goal.length() < ARRIVE:
			break
		guard += 1
		if guard > 60 * 90:
			_event("TIMEOUT", {"goal": [goal.x, goal.y]})
			break
		# pure pursuit：start→goal の線分上、投影点の LOOKAHEAD 先を狙う
		var seg := goal - start
		var tpar := clampf((p - start).dot(seg) / maxf(seg.length_squared(), 0.0001), 0.0, 1.0)
		var aim := start + seg * minf(1.0, tpar + LOOKAHEAD / maxf(seg.length(), 0.001))
		if aim.distance_to(p) < 0.5:
			aim = goal
		var want := _yaw_for(aim - p)
		adapter.set("_target_yaw", want)
		var cur := float(adapter.get("_current_yaw"))
		if absf(angle_difference(cur, want)) > TURN_GATE:
			Input.action_release("move_forward")
		else:
			Input.action_press("move_forward")
		await _tick()
		hist.append(p)
		if hist.size() > 90:
			hist.pop_front()
			if (hist[-1] as Vector2).distance_to(hist[0]) < 0.4 and absf(angle_difference(cur, want)) <= TURN_GATE:
				if nudges >= 6:
					_event("BLOCKED", {"goal": [goal.x, goal.y], "nudges": nudges})
					Input.action_release("move_right")
					Input.action_release("move_left")
					break
				_event("STUCK", {"goal": [goal.x, goal.y], "nudge": nudges + 1})
				var act := "move_right" if nudge_dir > 0 else "move_left"
				nudge_dir = -nudge_dir
				nudges += 1
				Input.action_release("move_forward")
				for i in 36:
					Input.action_press(act)
					await _tick()
				Input.action_release(act)
				hist.clear()
	Input.action_release("move_forward")


func _still(name: String, look: Vector2) -> void:
	Input.action_release("move_forward")
	var p := Vector2(player.global_position.x, player.global_position.z)
	adapter.set("_target_yaw", _yaw_for(look - p))
	for i in 84:
		await _tick()
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(outdir + "stills")
	img.save_png(outdir + "stills/%s.png" % name)
	var nd := 1e9
	var n_near := 0
	for n: Node3D in npcs:
		var d := n.global_position.distance_to(player.global_position)
		nd = minf(nd, d)
		if d < 25.0:
			n_near += 1
	var rec := {"name": name, "seg": seg_name, "player": _v3(player.global_position), "look": [look.x, look.y], "cam": _v3(cam.global_position),
		"arm_hit": snappedf(arm.get_hit_length(), 0.01), "arm_set": snappedf(arm.spring_length, 0.01), "pitch": snappedf(float(adapter.get("_current_pitch")), 0.001),
		"floor": player.is_on_floor(), "npc_nearest_m": snappedf(nd, 0.1), "npc_within_25m": n_near, "fps": Engine.get_frames_per_second()}
	log["stills"].append(rec)
	print("[WALK] STILL %s" % JSON.stringify(rec))


# ─────────────────────────── 事前点検（headless） ───────────────────────────

func _precheck() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await physics_frame
	var sp := v.get_world_3d().direct_space_state
	var R: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROUTE))
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.0
	var prev := Vector2(237.1, 71.7)
	var seg := ""
	var n_bad := 0
	for step: Array in R["route"]:
		if String(step[0]) == "seg":
			seg = String(step[1])
			continue
		if String(step[0]) != "wp":
			continue
		var goal := Vector2(float(step[1]), float(step[2]))
		var L := prev.distance_to(goal)
		var lastg := NAN
		var hits := {}
		for k in int(L / 0.4) + 1:
			var q := prev.lerp(goal, k * 0.4 / maxf(L, 0.001))
			var r := sp.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(q.x, 60.0, q.y), Vector3(q.x, -30.0, q.y)))
			if r.is_empty():
				hits["NO_GROUND"] = int(hits.get("NO_GROUND", 0)) + 1
				continue
			var gy := float(r.position.y)
			var gname := str((r.collider as Node).get_path()).trim_prefix("/root/VillageV2/") if r.collider is Node else "?"
			if not is_nan(lastg) and absf(gy - lastg) > 0.45:
				hits["STEP %.2f m @%s" % [gy - lastg, gname]] = int(hits.get("STEP %.2f m @%s" % [gy - lastg, gname], 0)) + 1
			lastg = gy
			var qs := PhysicsShapeQueryParameters3D.new()
			qs.shape = cap
			qs.transform = Transform3D(Basis(), Vector3(q.x, gy + 0.62 + 0.5, q.y))
			for w in sp.intersect_shape(qs, 8):
				var nm := str((w["collider"] as Node).get_path()).trim_prefix("/root/VillageV2/") if w["collider"] is Node else "?"
				if nm.contains("TerrainCollision"):
					continue
				hits[nm] = int(hits.get(nm, 0)) + 1
		if not hits.is_empty():
			n_bad += 1
			print("[PRE] %s (%.1f,%.1f)→(%.1f,%.1f) %.1f m：%s" % [seg, prev.x, prev.y, goal.x, goal.y, L, JSON.stringify(hits)])
		prev = goal
	print("[PRE] 結果：問題のある区間 %d" % n_bad)


## 診断：x0,z0,x1,z1 の範囲を 0.3 m 格子で、プレイヤーの capsule（r 0.3）が立てるか（. 立てる / # 物 / N NPC / ^ 段差 > 0.45 m / ~ 地面なし）
func _grid(spec: String) -> void:
	var a := spec.split(",")
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await physics_frame
	var sp := v.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.0
	var x0 := float(a[0]); var z0 := float(a[1]); var x1 := float(a[2]); var z1 := float(a[3])
	print("[GRID] %s（行＝z、列＝x、0.3 m）" % spec)
	var z := z0
	while z <= z1:
		var row := "%7.1f " % z
		var x := x0
		while x <= x1:
			var r := sp.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 60.0, z), Vector3(x, -30.0, z)))
			var ch := "~"
			if not r.is_empty():
				var nm := str((r.collider as Node).get_path()) if r.collider is Node else ""
				var t := RLib_ground(sp, x, z)
				ch = "."
				if not is_nan(t) and float(r.position.y) - t > 0.45:
					ch = "^"
				var qs := PhysicsShapeQueryParameters3D.new()
				qs.shape = cap
				qs.transform = Transform3D(Basis(), Vector3(x, (t if not is_nan(t) else float(r.position.y)) + 1.12, z))
				for w in sp.intersect_shape(qs, 8):
					var nn := str((w["collider"] as Node).get_path()) if w["collider"] is Node else ""
					if nn.contains("TerrainCollision"):
						continue
					ch = "N" if nn.contains("/Population/") else "#"
					break
			row += ch
			x += 0.3
		print("[GRID] " + row)
		z += 0.3


func RLib_ground(sp: PhysicsDirectSpaceState3D, x: float, z: float) -> float:
	# 歩ける面の高さ：上からの最初の当たりのうち、地形・道路・橋の床（Bridge の床は Hero/Collision）を優先せず最下の連続面＝地形
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60.0, z), Vector3(x, -30.0, z))
	var ex: Array[RID] = []
	var best := NAN
	for k in 8:
		q.exclude = ex
		var r := sp.intersect_ray(q)
		if r.is_empty():
			break
		best = float(r.position.y)
		if str((r.collider as Node).get_path()).contains("TerrainCollision"):
			break
		ex.append(r.rid)
	return best


# ─────────────────────────── P11 R1 追加 ───────────────────────────

var terrain_rid := RID()
var lift_on := ""
var npc_contact_ticks := 0
var npc_contact_name := ""
const PROP_PREFIX := ["Props/", "HumanUseP10", "HumanUseExpansionP10", "Vegetation/", "WaterLifeP10", "PropFixP10"]

func _terrain_y(x: float, z: float) -> float:
	var sp := player.get_world_3d().direct_space_state
	var ex: Array[RID] = [player.get_rid()]
	for i in 16:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -40.0, z))
		q.exclude = ex
		var h := sp.intersect_ray(q)
		if h.is_empty():
			return NAN
		if h["rid"] == terrain_rid:
			return float((h["position"] as Vector3).y)
		ex.append(h["rid"])
	return NAN


func _lift_npc_check(p: Vector3) -> void:
	# LIFT：接地中の足元の最初の当たりが構件で、地形より 0.2 m 以上高い
	if tick % 6 == 0 and vil:
		var cur := ""
		if player.is_on_floor():
			var sp := player.get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.25, 0), p + Vector3(0, -0.6, 0), player.collision_mask)
			q.exclude = [player.get_rid()]
			var h := sp.intersect_ray(q)
			if not h.is_empty() and h["collider"] is Node:
				var path := String(vil.get_path_to(h["collider"] as Node))
				for pre: String in PROP_PREFIX:
					if path.begins_with(pre):
						var ty := _terrain_y(p.x, p.z)
						if not is_nan(ty) and p.y - ty > 0.2:
							var shp := ""
							var co := h["collider"] as CollisionObject3D
							var so := co.shape_find_owner(int(h["shape"]))
							var sn := co.shape_owner_get_owner(so)
							if sn:
								shp = String(sn.name)
							cur = path + "/" + shp
							if cur != lift_on:
								_event("LIFT", {"on": cur, "above_terrain": snappedf(p.y - ty, 0.01)})
						break
		lift_on = cur
	# NPC_CONTACT：滑り衝突の相手が Population の NPC
	var hit := ""
	for i in player.get_slide_collision_count():
		var c := player.get_slide_collision(i).get_collider()
		if c is Node and vil and String(vil.get_path_to(c as Node)).begins_with("Population/"):
			hit = String((c as Node).name)
	if hit != "":
		npc_contact_ticks += 1
		npc_contact_name = hit
		if npc_contact_ticks == 30:
			_event("NPC_CONTACT", {"npc": hit})
	else:
		npc_contact_ticks = 0


func _tp(q: Vector2, yaw: float) -> void:
	Input.action_release("move_forward")
	var ty := _terrain_y(q.x, q.y)
	var sp := player.get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(Vector3(q.x, (ty if not is_nan(ty) else 0.0) + 6.0, q.y), Vector3(q.x, -40.0, q.y), player.collision_mask)
	rq.exclude = [player.get_rid()]
	var r := sp.intersect_ray(rq)
	var gy := float((r["position"] as Vector3).y) if not r.is_empty() else ty
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(q.x, gy + 0.1, q.y)
	adapter.set("_target_yaw", yaw)
	adapter.set("_current_yaw", yaw)
	for i in 20:
		await _tick()
	last_pos = player.global_position
	_event("TP", {"to": [q.x, q.y], "ground": snappedf(gy, 0.01)})


func _xbridge(nm: String) -> void:
	var br := vil.get_node_or_null("Roads/Bridges")
	var b := (br.find_child(nm + "*", false, false) if br else vil.find_child(nm + "*", true, false)) as Node3D
	if b == null:
		_event("NO_BRIDGE", {"name": nm})
		return
	var c := Vector2(b.global_position.x, b.global_position.z)
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/village_v2/layout_v2.json"))
	var best := INF
	var dir := Vector2.RIGHT
	for r: Dictionary in L["roads"]:
		var pts: Array = r.get("pts", r.get("points", []))
		for i in pts.size() - 1:
			var a := Vector2(float(pts[i][0]), float(pts[i][1]))
			var e := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
			var cp := Geometry2D.get_closest_point_to_segment(c, a, e)
			if cp.distance_to(c) < best:
				best = cp.distance_to(c)
				dir = (e - a).normalized()
	var span := 0.0
	var spans: Dictionary = L["terrain"]["bridge_spans"]["preferred"]
	for k: String in spans:
		if k.begins_with(nm):
			span = float(spans[k])
	var half := span * 0.5 + 4.0
	await _tp(c - dir * half, _yaw_for(dir))
	_event("BRIDGE", {"name": nm, "span": span, "road_dist": snappedf(best, 0.01)})
	await _walk_to(c + dir * half)
	await _walk_to(c - dir * half)
