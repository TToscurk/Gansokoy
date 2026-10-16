extends "res://tools/p13/w6/w6_base.gd"
## [scratch：P13 W9 收尾] 人間之里 V2 主路線 smoke（唯讀・場景檔不寫）。
##   godot --path godot --script <this> -- <outdir/> <tag> --map=village_v2 [--mount=Name=res://x.scn] [--gate] [--legs=<json>] [--transitions]
## 正式 main.tscn、--map=village_v2（不經 ReviewStart＝正常載入路徑）、實際玩家控制器＋TPS SpringArm。
## 走法：Input.action_press("move_forward")＋控制器 snap_yaw，依 legs.json 的 waypoint 依序前進（瞬移只在每段起點）。
##   along：每個 waypoint 都要到（1.0 m 內）；卡住（速度 < 0.3 m/s 連續 45 幀）記 BLOCK（位置＋碰撞對象），跳到 2 個 waypoint 後繼續
##   to   ：門口／錨點前允許停下：第一次停下時離目標 ≤ stop_ok
## 每 15 幀取樣：SpringArm 實長／設定長（重度＝縮 ≥ 2.0 m 且 < 3.0 m）、接地、單幀上下；placeholder 是否在畫面中且未被遮（相機→中心射線）。
## --mount：記憶體內掛 overlay（EnrichW9P8 放在 EnrichW9P4 之後）。--gate：記憶體內掛 DevLayerGate。
## --transitions：最後以 main.load_map 實測 beast_path→village_v2 等換圖的落點。
const DEV_PATHS := ["Debug", "QuestAnchors", "Districts/LandmarkParcelLines", "Districts/AuxParcelLines", "Portals"]
const PH_NAMES := ["Block", "Placeholder", "Wire", "Footprint"]
const STALL := 45
const SAMPLE := 15

var _tag := ""
var _legs: Array = []
var _rows: Array = []
var _blocks: Array = []
var _arm_sev: Array = []
var _ph: Array = []        # {path, c: Vector3, seen, first}
var _arm: SpringArm3D
var _stats := {"samples": 0, "arm_sev": 0, "arm_min": 99.0, "lost": 0, "pop": 0}


func _dev_report(when: String) -> Array:
	var out: Array = []
	for p: String in DEV_PATHS:
		var n := vil.get_node_or_null(p) as Node3D
		if n == null:
			out.append({"path": p, "exists": false})
			continue
		var lab := 0
		var mesh := 0
		for c in n.find_children("*", "Label3D", true, false):
			if (c as Node3D).is_visible_in_tree():
				lab += 1
		for c in n.find_children("*", "MeshInstance3D", true, false):
			if (c as Node3D).is_visible_in_tree():
				mesh += 1
		out.append({"path": p, "exists": true, "visible_in_tree": n.is_visible_in_tree(), "visible_label3d": lab, "visible_mesh": mesh})
		print("[V2SMOKE] DEV %s %-30s visible_in_tree=%s label3d=%d mesh=%d" % [when, p, n.is_visible_in_tree(), lab, mesh])
	# Debug 以外の可視 Label3D（任務・規劃の名牌がほかに残っていないか）
	var stray := 0
	for c in vil.find_children("*", "Label3D", true, false):
		if (c as Node3D).is_visible_in_tree():
			stray += 1
	print("[V2SMOKE] DEV %s 全村で可視の Label3D：%d" % [when, stray])
	out.append({"path": "*Label3D(all)", "visible_label3d": stray})
	return out


func _scan_placeholders() -> void:
	for c in vil.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var path := String(vil.get_path_to(mi))
		if path.begins_with("Debug") or path.begins_with("QuestAnchors") or "FarmsteadP13" in path or "FarmlandP8" in path:
			continue
		var prim := mi.mesh is BoxMesh or mi.mesh is CylinderMesh
		if (mi.name in PH_NAMES) or (prim and ("Landmarks" in path or "Waterfalls" in path)):
			var ab := mi.global_transform * mi.get_aabb()
			_ph.append({"path": path, "c": ab.get_center(), "size": ab.size, "mesh": mi.mesh.get_class(), "seen": 0, "first": [], "min_d": 1e9})
	for p: Dictionary in _ph:
		print("[V2SMOKE] PH %s %s center=(%.1f, %.1f, %.1f) size=(%.1f, %.1f, %.1f)" % [p.path, p.mesh, p.c.x, p.c.y, p.c.z, p.size.x, p.size.y, p.size.z])


func _sample(leg: String) -> void:
	_stats.samples += 1
	if _arm != null:
		var hl := _arm.get_hit_length()
		_stats.arm_min = minf(_stats.arm_min, hl)
		if _arm.spring_length - hl >= 2.0 and hl < 3.0:
			_stats.arm_sev += 1
			var pp := player.global_position
			var dup := false
			for s: Dictionary in _arm_sev:
				if Vector2(s.x, s.z).distance_to(Vector2(pp.x, pp.z)) < 5.0:
					s.n += 1
					dup = true
					break
			if not dup:
				_arm_sev.append({"leg": leg, "x": snappedf(pp.x, 0.1), "z": snappedf(pp.z, 0.1), "len": snappedf(hl, 0.01), "n": 1})
	var cam := root.get_viewport().get_camera_3d()
	if cam == null:
		return
	var ss := root.get_world_3d().direct_space_state
	for p: Dictionary in _ph:
		var c: Vector3 = p.c
		var d := cam.global_position.distance_to(c)
		if d > 160.0 or not cam.is_position_in_frustum(c):
			continue
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, c)
		q.exclude = [player.get_rid()]
		var hit := ss.intersect_ray(q)
		var r_obj: float = 0.5 * (p.size as Vector3).length()
		if hit.is_empty() or cam.global_position.distance_to(hit.position) > d - r_obj - 1.0:
			p.seen += 1
			if d < p.min_d:
				p.min_d = d
				p.first = [leg, snappedf(player.global_position.x, 0.1), snappedf(player.global_position.z, 0.1), snappedf(d, 0.1)]


func _leg(lg: Dictionary) -> void:
	var name := String(lg.name)
	var kind := String(lg.kind)
	var wps: Array = []
	for w in lg.wps:
		wps.append(Vector2(float(w[0]), float(w[1])))
	var stop_ok := float(lg.get("stop_ok", 0.0))
	await _tpw(wps[0], (wps[1] - wps[0]).normalized())
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var length := 0.0
	for i in wps.size() - 1:
		length += wps[i].distance_to(wps[i + 1])
	var budget_ms := int((length / 1.5 + 20.0) * 1000.0)
	var t0 := Time.get_ticks_msec()
	var idx := 1
	var n := 0
	var run := 0
	var lost := 0
	var max_dy := 0.0
	var blocks := 0
	var prev := player.global_position
	var stop := ""
	var first_stall_d := NAN
	Input.action_press("move_forward")
	while true:
		await physics_frame
		n += 1
		var pp := player.global_position
		var q := Vector2(pp.x, pp.z)
		var tgt: Vector2 = wps[idx]
		var dv := tgt - q
		var d := dv.length()
		if kind == "along" and d < 1.0 and idx < wps.size() - 1:
			idx += 1
			continue
		if d > 0.05:
			player.call("snap_yaw", atan2(-dv.x / d, -dv.y / d))
		if n % 8 == 1:
			_fix_camera()
		if n % SAMPLE == 0:
			_sample(name)
		if ("--trace=" + name) in OS.get_cmdline_user_args() and n % 10 == 0:
			var fl := ""
			var kc2 := player.get_last_slide_collision()
			if kc2 != null and kc2.get_collider() is Node:
				fl = String((kc2.get_collider() as Node).name)
			print("[V2SMOKE] TRACE %s n=%d pos=(%.2f, %.2f, %.2f) floor=%s wp=%d col=%s" % [name, n, pp.x, pp.y, pp.z, player.is_on_floor(), idx, fl])
		var sp := Vector2(pp.x - prev.x, pp.z - prev.z).length() / dt
		var dy := absf(pp.y - prev.y)
		max_dy = maxf(max_dy, dy)
		if dy > 0.4:
			_stats.pop += 1
		prev = pp
		if not player.is_on_floor():
			lost += 1
		if idx == wps.size() - 1 and d <= (0.6 if kind == "along" else 0.35):
			stop = "reached"
			break
		if n > 8 and sp < 0.3:
			run += 1
		else:
			run = 0
		if run >= STALL:
			if kind == "to":
				first_stall_d = d
				stop = "stopped"
				break
			var col := ""
			var kc := player.get_last_slide_collision()
			if kc != null and kc.get_collider() is Node:
				col = String((kc.get_collider() as Node).get_path()).replace("/root/Main/", "")
			blocks += 1
			_blocks.append({"leg": name, "x": snappedf(pp.x, 0.1), "z": snappedf(pp.z, 0.1), "collider": col, "wp": idx})
			print("[V2SMOKE] BLOCK %s at (%.1f, %.1f) wp %d/%d collider=%s" % [name, pp.x, pp.z, idx, wps.size() - 1, col])
			idx = mini(idx + 2, wps.size() - 1)
			Input.action_release("move_forward")
			await _tpw(wps[idx - 1] if idx > 0 else wps[0], (wps[idx] - wps[maxi(idx - 1, 0)]).normalized())
			prev = player.global_position
			run = 0
			Input.action_press("move_forward")
			if blocks > 6:
				stop = "abandoned"
				break
		if Time.get_ticks_msec() - t0 > budget_ms:
			stop = "timeout"
			break
	Input.action_release("move_forward")
	_stats.lost += lost
	var end := player.global_position
	var ok := false
	var verdict := ""
	if kind == "along":
		ok = stop == "reached" and blocks == 0 and lost <= 6 and max_dy <= 0.4
		verdict = "%s blocks=%d" % [stop, blocks]
	else:
		var sd := 0.0 if stop == "reached" else (first_stall_d if not is_nan(first_stall_d) else Vector2(end.x, end.z).distance_to(wps[-1]))
		ok = sd <= stop_ok and lost <= 6
		verdict = "%s 目標まで %.2f m（許容 %.2f）" % [stop, sd, stop_ok]
	var row := {"leg": name, "group": lg.group, "kind": kind, "ok": ok, "stop": stop, "blocks": blocks, "frames": n, "lost_floor": lost,
		"max_dy": snappedf(max_dy, 0.001), "length_m": snappedf(length, 0.1), "end": [snappedf(end.x, 0.1), snappedf(end.y, 0.01), snappedf(end.z, 0.1)]}
	_rows.append(row)
	print("[V2SMOKE] %s %-20s %-16s %s len=%.0fm frames=%d lost=%d max_dy=%.2f" % ["PASS" if ok else "FAIL", name, lg.group, verdict, length, n, lost, max_dy])


func _transition(to_id: String, from_id: String) -> Dictionary:
	main.call("load_map", to_id, from_id)
	var pl: CharacterBody3D = null
	for i in 150:
		await physics_frame
	pl = main.get("player")
	var pp := pl.global_position
	var ss := root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pp + Vector3.UP * 2.0, pp + Vector3.DOWN * 60.0)
	q.exclude = [pl.get_rid()]
	var hit := ss.intersect_ray(q)
	var r := {"to": to_id, "from": from_id, "current_id": String(main.get("current_id")), "pos": [snappedf(pp.x, 0.01), snappedf(pp.y, 0.01), snappedf(pp.z, 0.01)],
		"on_floor": pl.is_on_floor(), "ground_hit": not hit.is_empty(), "ground_collider": String((hit.collider as Node).name) if not hit.is_empty() and hit.collider is Node else ""}
	print("[V2SMOKE] TRANSITION %s → %s：current=%s pos=(%.1f, %.1f, %.1f) on_floor=%s ground=%s" % [from_id if from_id != "" else "(none)", to_id, r.current_id, pp.x, pp.y, pp.z, r.on_floor, r.ground_collider])
	return r


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	_tag = args[1]
	var legs_path := ""
	var mounts: Array = []
	for a: String in args:
		if a.begins_with("--mount="):
			var mt := a.trim_prefix("--mount=").split("=", false, 1)
			mounts.append([mt[0], mt[1]])
		elif a.begins_with("--legs="):
			legs_path = a.trim_prefix("--legs=")
	DirAccess.make_dir_recursive_absolute(out)
	await _boot()
	var rep := {"tag": _tag, "mounts": mounts, "gate_in_memory": "--gate" in args}
	rep["dev_before"] = _dev_report("loaded")
	for mt2: Array in mounts:
		var inst := (load(String(mt2[1])) as PackedScene).instantiate()
		inst.name = String(mt2[0])
		vil.add_child(inst)
		var p4 := vil.get_node_or_null("EnrichW9P4")
		if p4 != null:
			vil.move_child(inst, p4.get_index() + 1)
		print("[V2SMOKE] mounted (memory only) %s" % mt2[0])
	if "--gate" in args:
		var g := Node.new()
		g.name = "DevLayerGate"
		g.set_script(load("res://maps/village_v2/scripts_p13/dev_layer_gate.gd"))
		vil.add_child(g)
		print("[V2SMOKE] DevLayerGate (memory only)")
	await _frames(6)
	rep["dev_after"] = _dev_report("final")
	var names: Array = []
	for c in vil.get_children():
		names.append(String(c.name))
	rep["root_children_tail"] = names.slice(maxi(0, names.size() - 6))
	var arms := player.find_children("*", "SpringArm3D", true, false)
	_arm = arms[0] as SpringArm3D if arms.size() > 0 else null
	print("[V2SMOKE] SpringArm %s spring_length=%s" % [str(_arm != null), str(_arm.spring_length) if _arm else "-"])
	_scan_placeholders()
	for a2: String in args:
		if a2.begins_with("--shots="):
			for spec: String in a2.trim_prefix("--shots=").split("|"):
				var f := spec.split(":")
				var at := Vector2(float(f[1]), float(f[2]))
				var lk := Vector2(float(f[3]), float(f[4]))
				await _tpw(at, (lk - at).normalized())
				# TPS 相當の視点（玩家の後方 5 m・高さ 2.4 m → 注視点の地面 +1.5 m）を固定相機で撮る（相機 adapter の初期 pitch に依存しない）
				var dir := (lk - at).normalized()
				var gy := player.global_position.y
				var fc := Camera3D.new()
				fc.fov = 60.0
				root.add_child(fc)
				var eye := Vector3(at.x - dir.x * 5.0, gy + 2.4, at.y - dir.y * 5.0)
				var tgt := Vector3(lk.x, gy + 1.5, lk.y)
				fc.global_transform = Transform3D(Basis(), eye).looking_at(tgt, Vector3.UP)
				fc.make_current()
				await _shot(_tag + "_" + f[0], 20)
				fc.queue_free()
	if legs_path != "":
		_legs = (JSON.parse_string(FileAccess.get_file_as_string(legs_path)) as Dictionary)["legs"]
		for lg: Dictionary in _legs:
			await _leg(lg)
	var fails := 0
	for r: Dictionary in _rows:
		if not r.ok:
			fails += 1
	var ph_out: Array = []
	for p: Dictionary in _ph:
		ph_out.append({"path": p.path, "mesh": p.mesh, "center": [snappedf(p.c.x, 0.1), snappedf(p.c.y, 0.1), snappedf(p.c.z, 0.1)],
			"size": [snappedf(p.size.x, 0.1), snappedf(p.size.y, 0.1), snappedf(p.size.z, 0.1)], "visible_samples": p.seen, "closest_view": p.first})
		print("[V2SMOKE] PH-SEEN %s samples=%d closest=%s" % [p.path, p.seen, str(p.first)])
	rep["legs"] = _rows
	rep["blocks"] = _blocks
	rep["arm_severe"] = _arm_sev
	rep["placeholders"] = ph_out
	_stats.arm_min = snappedf(_stats.arm_min, 0.01)
	rep["stats"] = _stats
	rep["fails"] = fails
	if "--portal-walk" in args:
		rep["portal_walk"] = await _portal_walk()
	if "--transitions" in args:
		var tr: Array = []
		tr.append(await _transition("beast_path", "village_v2"))
		tr.append(await _transition("village_v2", "beast_path"))
		tr.append(await _transition("hieda1f", "village_v2"))
		tr.append(await _transition("village_v2", "hieda1f"))
		tr.append(await _transition("kourindou", "village_v2"))
		tr.append(await _transition("village_v2", "kourindou"))
		rep["transitions"] = tr
	var f := FileAccess.open(out + _tag + "_smoke.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(rep, "\t") + "\n")
	f.close()
	print("[V2SMOKE] 結果：%d 段・FAIL %d・BLOCK %d・SpringArm 重度 %d 樣本（%d 處）・接地喪失 %d 幀・單幀跳動>0.4 m %d" % [_rows.size(), fails, _blocks.size(), _stats.arm_sev, _arm_sev.size(), _stats.lost, _stats.pop])
	quit(1 if fails > 0 else 0)


## 実際の入力で portal へ歩き、portal_enter を押す（main.gd は重なり中の portal_enter で換圖）：V2 村南入口 → beast_path → 南端 portal → V2
func _walk_portal(goal: Vector2, want: String, max_ms: int) -> Dictionary:
	var pl: CharacterBody3D = main.get("player")
	var t0 := Time.get_ticks_msec()
	Input.action_press("move_forward")
	while Time.get_ticks_msec() - t0 < max_ms:
		await physics_frame
		var pp := pl.global_position
		var dv := goal - Vector2(pp.x, pp.z)
		if dv.length() < 0.8:
			break
		pl.call("snap_yaw", atan2(-dv.x / dv.length(), -dv.y / dv.length()))
	Input.action_release("move_forward")
	for i in 20:
		await physics_frame
	var cd := float(main.get("portal_cooldown"))
	var ev := InputEventAction.new()
	ev.action = "portal_enter"
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var ev2 := InputEventAction.new()
	ev2.action = "portal_enter"
	ev2.pressed = false
	Input.parse_input_event(ev2)
	var t1 := Time.get_ticks_msec()
	while String(main.get("current_id")) != want and Time.get_ticks_msec() - t1 < 8000:
		await physics_frame
	var ok := String(main.get("current_id")) == want
	for i in 150:
		await physics_frame
	pl = main.get("player")
	var pp2 := pl.global_position
	var r := {"want": want, "current_id": String(main.get("current_id")), "ok": ok, "cooldown_at_press": snappedf(cd, 0.01),
		"pos": [snappedf(pp2.x, 0.01), snappedf(pp2.y, 0.01), snappedf(pp2.z, 0.01)], "on_floor": pl.is_on_floor()}
	print("[V2SMOKE] PORTALWALK → %s：%s current=%s cooldown=%.2f pos=(%.1f, %.1f, %.1f) on_floor=%s" % [want, "OK" if ok else "NG", r.current_id, cd, pp2.x, pp2.y, pp2.z, r.on_floor])
	return r


func _portal_walk() -> Array:
	var out_r: Array = []
	await _tpw(Vector2(223.9, 164.0), Vector2(0.0, 1.0))
	out_r.append(await _walk_portal(Vector2(224.0, 172.0), "beast_path", 15000))   # V2 村南入口の portal
	for i in 200:   # PORTAL_COOLDOWN を待つ
		await physics_frame
	out_r.append(await _walk_portal(Vector2(0.0, 6.0), "village_v2", 15000))       # 獸道南端の portal（z=6）
	return out_r
