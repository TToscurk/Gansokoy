extends SceneTree
## P11 R2 — Scene Transition 実測（非 headless・正式 main.tscn・場景／封存／玩家ファイル不変）。
## 実際の portal Area3D に玩家を入れて ↑（portal_enter 入力）を押し、main.gd の通常経路（_unhandled_input → _try_portal_interaction →
## _on_portal_entered → _travel：黒幕・pause・背景載入・load_map・_place_player）
## で地図を往復し、各ホップの「最初に見える位置・落下・着地時間・膠囊の重なり・portal の中に立っていないか・向き」を記録する。
## V2 へ戻る portal は他の地図に無い（trail／hieda1f／kourindou の人間之里 portal は正式の slice を指す）ため、
## V2 への返回だけ main._travel("village_v2", from) を直接呼ぶ（portal と同じ関数）。
##   godot --path godot --script res://tools/p11r2/verify_p11r2_transition.gd -- --review=kirisame [--candidate=C] [--cycles=3] --out=<dir>/
## 判定（P11 R2 提案 gate）：最初の位置が戻り portal から ≤ 6 m・(0,40,0) なし・落下 ≤ 0.30 m・着地 ≤ 0.10 s・膠囊の重なり 0・
##   portal 円筒（r 1.6＋膠囊 0.3）の外・向き＝arrival_yaw（有れば）または portal から離れる方向 ±60°。
const P11R2Swap := preload("res://tools/p11r2/p11r2_swap.gd")
const V_ALIASES := ["village_v2", "slice", "village"]
const HOPS := [
	# [方法, 行き先]  portal＝今の地図の Portal_<行き先> に入る／travel＝main._travel(行き先, 今の地図)
	["portal", "trail"], ["travel", "village_v2"],
	["portal", "hieda1f"], ["travel", "village_v2"],
	["portal", "kourindou"], ["travel", "village_v2"],
	["portal", "trail"], ["portal", "slice"], ["portal", "hieda1f"], ["portal", "slice"],
	["portal", "kourindou"], ["portal", "slice"], ["portal", "trail"], ["travel", "village_v2"],
]

var main: Node
var player: CharacterBody3D
var adapter: Node
var outdir := "user://p11r2_transition/"
var R := {"hops": []}


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var cycles := 3
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			outdir = a.trim_prefix("--out=")
		if a.begins_with("--cycles="):
			cycles = int(a.trim_prefix("--cycles="))
	DirAccess.make_dir_recursive_absolute(outdir)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var cand := P11R2Swap.parse(OS.get_cmdline_user_args())
	R["candidate"] = cand
	if cand != "":
		R["swapped"] = P11R2Swap.apply(main, cand)
		print("[P11R2] candidate ", R["swapped"])
	root.add_child(main)
	current_scene = main
	var t0 := Time.get_ticks_msec()
	while true:
		await physics_frame
		player = main.get("player")
		if player and String(main.get("current_id")) == "village_v2" and player.is_on_floor():
			break
		if Time.get_ticks_msec() - t0 > 120000:
			push_error("boot timeout")
			quit(2)
			return
	for i in 60:
		await physics_frame
	adapter = player.get_node("CameraAdapter")
	adapter.set_process_unhandled_input(false)
	player.set_process_unhandled_input(false)
	var fails := 0
	for cy in cycles:
		for h: Array in HOPS:
			var rec := await _hop(String(h[0]), String(h[1]))
			rec["cycle"] = cy + 1
			R["hops"].append(rec)
			if not rec["ok"]:
				fails += 1
			print("[TRANS] c%d %-10s → %-10s %s first %s fall %s t_floor %s portal_d %s overlap %s inside %s face %s %s" % [cy + 1, rec["from"], rec["to"], rec["via"],
				str(rec.get("first")), str(rec.get("fall_m")), str(rec.get("t_floor_s")), str(rec.get("first_dist_to_return_portal_m")), str((rec.get("overlap", []) as Array).size()),
				str(rec.get("inside_portal")), str(rec.get("facing_err_deg")), "OK" if rec["ok"] else "FAIL " + str(rec["why"])])
	R["fails"] = fails
	var f := FileAccess.open(outdir + "transition.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(R, "\t") + "\n")
	f.close()
	print("[TRANS] 結果：%d ホップ、%d 失敗" % [R["hops"].size(), fails])
	quit(0 if fails == 0 else 1)


func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]


func _portals_of(id: String) -> Array:
	var m := FileAccess.get_file_as_string("res://data/%s.meta.json" % id)
	var d: Variant = JSON.parse_string(m)
	return (d as Dictionary).get("portals", []) if d is Dictionary else []


func _return_portal(dest: String, from: String) -> Dictionary:
	var ps := _portals_of(dest)
	for p: Dictionary in ps:
		if p.get("target") == from:
			return p
	if from in V_ALIASES:
		for p: Dictionary in ps:
			if String(p.get("target", "")) in V_ALIASES:
				return p
	return {}


func _hop(via: String, dest: String) -> Dictionary:
	var from := String(main.get("current_id"))
	var rec := {"from": from, "to": dest, "via": via, "ok": false, "why": []}
	# 前の到着の cooldown（2 s）が切れるまで待つ
	for i in 160:
		await physics_frame
	if via == "portal":
		var area: Area3D = null
		for a in main.find_children("Portal_*", "Area3D", true, false):
			if String(a.name) == "Portal_" + dest:
				area = a
		if area == null:
			rec["why"].append("portal %s not found in %s" % [dest, from])
			return rec
		player.velocity = Vector3.ZERO
		player.global_position = area.global_position + Vector3(0, -0.9, 0)
		# portal は「重なって ↑（portal_enter）を押す」で発動（main.gd _unhandled_input → _try_portal_interaction）
		for i in 6:
			await physics_frame
		if not area.overlaps_body(player):
			rec["why"].append("not overlapping portal %s" % dest)
		var ev := InputEventAction.new()
		ev.action = "portal_enter"
		ev.pressed = true
		Input.parse_input_event(ev)
		await process_frame
		var ev2 := InputEventAction.new()
		ev2.action = "portal_enter"
		ev2.pressed = false
		Input.parse_input_event(ev2)
		# 物語フラグで閉じている portal（例：trail → slice は met_reimu）は押しても発動しない → 同じ関数 _travel で代替し記録
		var waited := 0
		while waited < 90 and not bool(main.get("_traveling")) and String(main.get("current_id")) != dest:
			await physics_frame
			waited += 1
		if not bool(main.get("_traveling")) and String(main.get("current_id")) != dest:
			rec["via"] = "travel(portal locked)"
			main.call("_travel", dest, from)
	else:
		main.call("_travel", dest, from)
	# 移動開始（_traveling）→ 終了まで。current_id が変わった最初の幀の位置＝_place_player の結果（pause 中で物理は止まっている）
	var tw := Time.get_ticks_msec()
	var placed := Vector3.INF
	var started := false
	while Time.get_ticks_msec() - tw < 60000:
		await physics_frame
		if bool(main.get("_traveling")):
			started = true
		if String(main.get("current_id")) == dest and placed == Vector3.INF:
			placed = player.global_position
		if started and not bool(main.get("_traveling")) and String(main.get("current_id")) == dest:
			break
	if String(main.get("current_id")) != dest:
		rec["why"].append("did not arrive (now %s)" % String(main.get("current_id")))
		return rec
	# 揭幕＝物理再開の最初の幀
	var first := player.global_position
	if placed != Vector3.INF:
		first = placed
	rec["first"] = _v(first)
	var miny := first.y
	var t_floor := -1.0
	var fr := 0
	while fr < 240:
		await physics_frame
		fr += 1
		miny = minf(miny, player.global_position.y)
		if player.is_on_floor() and t_floor < 0.0:
			t_floor = (fr - 1) / 60.0
		if t_floor >= 0.0 and fr > 30:
			break
	var fin := player.global_position
	rec["final"] = _v(fin)
	rec["fall_m"] = snappedf(first.y - fin.y, 0.01)
	rec["t_floor_s"] = snappedf(t_floor, 0.01)
	# 戻り portal（来た地図へ戻る portal）からの距離
	var rp := _return_portal(dest, from)
	var rpos := Vector2(float(rp.get("x", 0.0)), float(rp.get("z", 0.0))) if not rp.is_empty() else Vector2.INF
	rec["return_portal"] = [rpos.x, rpos.y] if rpos != Vector2.INF else null
	rec["first_dist_to_return_portal_m"] = snappedf(Vector2(first.x, first.z).distance_to(rpos), 0.01) if rpos != Vector2.INF else null
	# 膠囊の重なり（到着後の静止位置）
	var cap: Shape3D = player.call("_capsule_shape")
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, fin + Vector3(0, 0.02, 0)) * (player.call("_capsule_local") as Transform3D)
	q.collision_mask = player.collision_mask
	q.exclude = [player.get_rid()]
	var ov: Array = []
	for h: Dictionary in player.get_world_3d().direct_space_state.intersect_shape(q, 8):
		ov.append(String((h["collider"] as Node).name))
	rec["overlap"] = ov
	# portal 円筒の中に立っていないか（ping-pong 防止）
	var inside := ""
	for p: Dictionary in _portals_of(dest):
		var t := String(p.get("target", ""))
		if t == "":
			continue
		if Vector2(fin.x, fin.z).distance_to(Vector2(float(p.x), float(p.z))) < 1.6 + 0.3:
			inside = t
	rec["inside_portal"] = inside
	# 向き：相機 yaw の前方 vs arrival_yaw（有れば）または portal から離れる方向
	var yaw := float(adapter.get("_current_yaw"))
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var want := Vector2.ZERO
	if not rp.is_empty() and rp.has("arrival_yaw"):
		var ay := float(rp["arrival_yaw"])
		want = Vector2(-sin(ay), -cos(ay))
		rec["facing_ref"] = "arrival_yaw"
	elif rpos != Vector2.INF:
		want = (Vector2(fin.x, fin.z) - rpos).normalized()
		rec["facing_ref"] = "away_from_portal"
	rec["facing_err_deg"] = snappedf(rad_to_deg(fwd.angle_to(want)), 0.1) if want != Vector2.ZERO else null
	rec["cam_yaw"] = snappedf(yaw, 0.001)
	# 判定
	var why: Array = rec["why"]
	if first.distance_to(Vector3(0, 40, 0)) < 0.5:
		why.append("(0,40,0)")
	if rec["first_dist_to_return_portal_m"] == null or float(rec["first_dist_to_return_portal_m"]) > 6.0:
		why.append("far from return portal")
	if float(rec["fall_m"]) > 0.30:
		why.append("fall %.2f" % float(rec["fall_m"]))
	if t_floor < 0.0 or t_floor > 0.10:
		why.append("t_floor %.2f" % t_floor)
	if ov.size() > 0:
		why.append("overlap")
	if inside != "":
		why.append("inside portal " + inside)
	if rec["facing_err_deg"] != null and absf(float(rec["facing_err_deg"])) > 60.0:
		why.append("facing")
	rec["ok"] = why.is_empty()
	return rec
