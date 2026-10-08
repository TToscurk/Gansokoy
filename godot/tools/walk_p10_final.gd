extends SceneTree
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
	var pulled := hl < arm.spring_length * 0.55
	if pulled and not arm_pull_on:
		_event("ARM_PULL", {"hit_length": snappedf(hl, 0.01), "spring": snappedf(arm.spring_length, 0.01), "cam": _v3(cam.global_position)})
	arm_pull_on = pulled
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
