extends "res://tools/p13/w6/w6_base.gd"
## P13 W9 FIX 最終驗收：TPS 相機の実プレイ確認（唯讀・場景ファイルは書かない・有視窗）。
##   godot --path godot --resolution 1600x900 --script res://tools/p13/w9/w9fix_cam_review.gd -- <out_dir> <ids,comma>
## 正式 main.tscn → village_v2・実際の玩家 controller（move_* の入力・相機基準）・実際の CameraAdapter／SpringArm（7.5 m・margin 0.2）。
## 各棟：正面 1.3 m／道 3.0 m／背面 1.3 m の 3 路線を端から端まで歩く。相機の腕の向き 6 つ（建物へ・建物へ ±45°・路線に沿って 2 方向・通りへ）
##   × 俯仰 2 つ（既定 −0.18・見下ろし −0.6）。同じ脚を BEFORE（元の箱・Shell 無効）→ AFTER（Shell）で続けて歩く（同じ位置・同じ向き）。
## 毎フレーム：
##   pen     ＝ 腕の根元→相機の線が『見た目の面』（46 棟の Kit LOD0＋L0）を越えている（相機が壁・屋根の向こう＝壁の中が映る）
##   hidden  ＝ pen でなく、相機→玩家の胸 1.2 m・頭 1.6 m の両方が見た目の面で遮られる（玩家が見えない）
##   snap    ＝ 腕の長さが 1 フレームで 1.5 m 以上縮む（急な寄り）
##   short   ＝ 腕 < 2.0 m（寄りっぱなし）
## 最後に、AFTER で BEFORE より悪化した最長の pen／hidden の場面を同じ位置・向きで BEFORE／AFTER とも撮る。
const L := preload("res://tools/p13/w9/w9r2_lib.gd")
const VIS := 1 << 19
const PITCHES := [-0.18, -0.6]
## 腕の向き（建物局部・正面側 s=+1 の時。背面路線は z を反転＝常に『建物へ』が in）
const ARMS := [[0.0, -1.0, "in"], [0.707, -0.707, "in_r"], [-0.707, -0.707, "in_l"], [1.0, 0.0, "along_r"], [-1.0, 0.0, "along_l"], [0.0, 1.0, "out"]]
const ROUTES := [["front_near", 1.3, 1.0], ["front_road", 3.0, 1.0], ["back_near", 1.3, -1.0]]
const STALL := 30
const LEG_MS := 12000

var _cf: Dictionary
var _vis_name := {}
var _arm: SpringArm3D
var _cam: Camera3D
var _phys_ms := {"before": [0.0, 0], "after": [0.0, 0]}


func _cfg(after: bool) -> void:
	var ov := vil.get_node("ArchW9R2P13")
	for id: String in _cf:
		var body := vil.get_node(NodePath(String(L.SPECS[id]["path"])))
		for c in body.get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).disabled = after
		for c in ov.get_node(id + "/Shell").get_children():
			(c as CollisionShape3D).disabled = not after
	for i in 3:
		await physics_frame


func _build_vis() -> void:
	var ov := vil.get_node("ArchW9R2P13")
	for sid: String in L.SPECS:
		var body := vil.get_node(NodePath(String(L.SPECS[sid]["path"])))
		var meshes: Array = []
		var k0 := body.get_node_or_null("Kit/LOD0")
		if k0:
			for mi in k0.get_children():
				if mi is MeshInstance3D and (mi as MeshInstance3D).is_visible_in_tree():
					meshes.append(mi)
		var l0 := ov.get_node_or_null(sid + "/L0")
		if l0 and (l0 as Node3D).is_visible_in_tree():
			meshes.append(l0)
		var faces := PackedVector3Array()
		for mi: MeshInstance3D in meshes:
			for p in mi.mesh.get_faces():
				faces.append(mi.global_transform * p)
		var vb := StaticBody3D.new()
		vb.collision_layer = VIS
		vb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cp := ConcavePolygonShape3D.new()
		cp.backface_collision = true
		cp.set_faces(faces)
		cs.shape = cp
		vb.add_child(cs)
		root.add_child(vb)
		_vis_name[vb.get_rid()] = sid
	await physics_frame


func _set_cam(yaw: float, pitch: float) -> void:
	adapter.set("_target_yaw", yaw)
	adapter.set("_current_yaw", yaw)
	adapter.set("_target_pitch", pitch)
	adapter.set("_current_pitch", pitch)


func _release() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(a)


## 世界の向き d（水平）へ歩く入力（相機の yaw 基準：input_dir = (v.x, 0, v.y).rotated(UP, yaw)）
func _steer(d: Vector3, yaw: float) -> void:
	var l := d.rotated(Vector3.UP, -yaw)
	_release()
	if l.x > 0.01:
		Input.action_press("move_right", l.x)
	elif l.x < -0.01:
		Input.action_press("move_left", -l.x)
	if l.z > 0.01:
		Input.action_press("move_back", l.z)
	elif l.z < -0.01:
		Input.action_press("move_forward", -l.z)


func _place(p: Vector3, face: Vector2, yb: float) -> void:
	_release()
	var sp := player.get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(Vector3(p.x, yb + 1.8, p.z), Vector3(p.x, yb - 4.0, p.z), player.collision_mask)
	rq.exclude = [player.get_rid()]
	var r := sp.intersect_ray(rq)
	var gy := float((r["position"] as Vector3).y) if not r.is_empty() else yb
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(p.x, gy + 0.1, p.z)
	player.call("snap_yaw", atan2(-face.x, -face.y))
	for i in 30:
		await physics_frame


func _ray(a: Vector3, b: Vector3, back: bool) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, VIS)
	q.hit_back_faces = back
	return _arm.get_world_3d().direct_space_state.intersect_ray(q)


func _metrics() -> Array:
	var o := _arm.global_position
	var c := _cam.global_position
	var lo := o.distance_to(c)
	var pen := false
	var who := ""
	var h := _ray(o, c, true)
	if not h.is_empty() and o.distance_to(h["position"]) < lo - 0.10:
		pen = true
		who = String(_vis_name.get(h["rid"], ""))
	var hid := false
	if not pen:
		var pp := player.global_position
		hid = not _ray(c, pp + Vector3(0, 1.2, 0), false).is_empty() and not _ray(c, pp + Vector3(0, 1.6, 0), false).is_empty()
	return [pen, hid, _arm.get_hit_length(), who]


func _leg(id: String, bxf: Transform3D, box: Dictionary, rt: Array, arm: Array, pitch: float, cfg: String, trace := false, shot_lx := NAN, shot_path := "") -> Dictionary:
	var s: float = rt[2]
	var zr: float = (float(box["z1"]) + float(rt[1])) if s > 0 else (float(box["z0"]) - float(rt[1]))
	var p0 := bxf * Vector3(float(box["x0"]) - 1.5, 0.0, zr)
	var p1 := bxf * Vector3(float(box["x1"]) + 1.5, 0.0, zr)
	var aw := (bxf.basis * Vector3(float(arm[0]), 0.0, float(arm[1]) * s)).normalized()
	var yaw := atan2(aw.x, aw.z)
	var wd := Vector2(p1.x - p0.x, p1.z - p0.z).normalized()
	await _place(p0, wd, bxf.origin.y)
	_set_cam(yaw, pitch)
	await _frames(20)
	var st := {"frames": 0, "dur": 0.0, "pen_t": 0.0, "pen_run": 0.0, "hid_t": 0.0, "hid_run": 0.0, "snap": 0, "short_t": 0.0, "short_run": 0.0,
		"min_arm": 99.0, "reached": false, "end_lx": 0.0, "pen_who": {}, "worst": {}, "trace": [], "shot": []}
	var shot_done := false
	var prev_lx := NAN
	var inv := bxf.affine_inverse()
	var run_p := 0.0
	var run_h := 0.0
	var run_s := 0.0
	var prev_arm := -1.0
	var stall := 0
	var prev := player.global_position
	var t0 := Time.get_ticks_msec()
	var tl := Time.get_ticks_usec()
	while true:
		var to := Vector3(p1.x - player.global_position.x, 0.0, p1.z - player.global_position.z)
		if to.length() <= 0.35:
			st["reached"] = true
			break
		_steer(to.normalized(), yaw)
		_set_cam(yaw, pitch)
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - tl) / 1e6
		tl = now
		var pm: Array = _phys_ms[cfg]
		pm[0] = float(pm[0]) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		pm[1] = int(pm[1]) + 1
		st["frames"] += 1
		st["dur"] += dt
		var m := _metrics()
		var arm_l: float = m[2]
		st["min_arm"] = minf(st["min_arm"], arm_l)
		if prev_arm >= 0.0 and prev_arm - arm_l >= 1.5:
			st["snap"] += 1
		prev_arm = arm_l
		var lp := inv * player.global_position
		if trace:
			(st["trace"] as Array).append([snappedf(lp.x, 0.01), m[0], m[1], snappedf(arm_l, 0.01), m[3]])
		if not is_nan(shot_lx) and not shot_done and not is_nan(prev_lx) and (prev_lx - shot_lx) * (lp.x - shot_lx) <= 0.0:
			shot_done = true
			root.get_viewport().get_texture().get_image().save_png(shot_path)
			st["shot"] = [snappedf(lp.x, 0.01), m[0], m[1], snappedf(arm_l, 0.01), m[3]]
		prev_lx = lp.x
		if m[0]:
			st["pen_t"] += dt
			run_p += dt
			st["pen_who"][m[3]] = int(st["pen_who"].get(m[3], 0)) + 1
			if run_p > float(st["pen_run"]):
				st["pen_run"] = run_p
				st["worst"]["pen"] = [player.global_position, lp.x]
		else:
			run_p = 0.0
		if m[1]:
			st["hid_t"] += dt
			run_h += dt
			if run_h > float(st["hid_run"]):
				st["hid_run"] = run_h
				st["worst"]["hid"] = [player.global_position, lp.x]
		else:
			run_h = 0.0
		if arm_l < 2.0:
			st["short_t"] += dt
			run_s += dt
			st["short_run"] = maxf(st["short_run"], run_s)
		else:
			run_s = 0.0
		var sp := Vector2(player.global_position.x - prev.x, player.global_position.z - prev.z).length() / maxf(dt, 1e-4)
		prev = player.global_position
		stall = stall + 1 if (st["frames"] > 10 and sp < 0.3) else 0
		if stall >= STALL or Time.get_ticks_msec() - t0 > LEG_MS:
			break
	_release()
	st["end_lx"] = snappedf((inv * player.global_position).x, 0.01)
	st["yaw"] = yaw
	for k in ["dur", "pen_t", "pen_run", "hid_t", "hid_run", "short_t", "short_run", "min_arm"]:
		st[k] = snappedf(float(st[k]), 0.001)
	return st


## 焦点モード：ids の各要素＝"<id>:<route>:<arm>:<pitch>"。AFTER を記録付きで歩き、最長の pen（無ければ hidden）連続区間の中点 lx を求め、
## BEFORE と AFTER をもう一度歩いてその lx を通る瞬間を撮る（同じ脚・同じ向き・同じ位置・歩いている最中）。
func _focus(specs: PackedStringArray) -> void:
	var res := {}
	for sp: String in specs:
		var f := sp.split(":")
		var id := f[0]
		var rt: Array = []
		for r: Array in ROUTES:
			if r[0] == f[1]:
				rt = r
		var arm: Array = []
		for a: Array in ARMS:
			if a[2] == f[2]:
				arm = a
		var pitch := float(f[3])
		var body := vil.get_node(NodePath(String(L.SPECS[id]["path"]))) as Node3D
		var bxf := body.global_transform
		var box: Dictionary = (_cf[id] as Dictionary)["orig"]
		var row := {}
		for cfg in ["before", "after"]:
			await _cfg(cfg == "after")
			row[cfg + "_trace"] = await _leg(id, bxf, box, rt, arm, pitch, cfg, true)
		var tr: Array = row["after_trace"]["trace"]
		var best := [0, -1, -1]
		for kind in [1, 2]:
			var i := 0
			while i < tr.size():
				if tr[i][kind]:
					var j := i
					while j + 1 < tr.size() and tr[j + 1][kind]:
						j += 1
					if j - i + 1 > int(best[0]):
						best = [j - i + 1, i, j]
					i = j + 1
				else:
					i += 1
			if int(best[0]) > 0:
				break
		var lx := NAN
		if int(best[0]) > 0:
			lx = float(tr[(int(best[1]) + int(best[2])) / 2][0])
		if f.size() > 4:
			lx = float(f[4])    # 5 番目＝撮る lx を指定（修正前の回に見つけた場面を修正後に同じ所で撮る）
		row["focus_lx"] = lx
		var tag := "focus_%s_%s_%s_p%d" % [id.trim_prefix("B_P_"), f[1], f[2], int(round(-pitch * 100))]
		if not is_nan(lx):
			for cfg in ["before", "after"]:
				await _cfg(cfg == "after")
				var st := await _leg(id, bxf, box, rt, arm, pitch, cfg, false, lx, out + tag + "_" + cfg + ".png")
				row[cfg + "_shot"] = st["shot"]
				print("[W9CAM] FOCUS %s %s lx %.2f：%s" % [tag, cfg, lx, str(st["shot"])])
		res[sp] = row
		await _cfg(true)
	var fo := FileAccess.open(out + "focus_" + specs[0].get_slice(":", 0).trim_prefix("B_P_") + ".json", FileAccess.WRITE)
	fo.store_string(JSON.stringify(res, "\t"))
	fo.close()


func _snap_png(path: String) -> void:
	await _frames(25)
	root.get_viewport().get_texture().get_image().save_png(path)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var ids: PackedStringArray = args[1].split(",")
	DirAccess.make_dir_recursive_absolute(out)
	_cf = (JSON.parse_string(FileAccess.get_file_as_string(L.COLFIT)) as Dictionary)["buildings"]
	await _boot()
	_arm = adapter.get("arm") as SpringArm3D
	_cam = _arm.get_node("Camera3D") as Camera3D
	await _build_vis()
	if args.size() > 2 and args[2] == "--focus":
		await _focus(ids)
		quit(0)
		return
	var res := {}
	for id: String in ids:
		var body := vil.get_node(NodePath(String(L.SPECS[id]["path"]))) as Node3D
		var bxf := body.global_transform
		var box: Dictionary = (_cf[id] as Dictionary)["orig"]
		var legs: Array = []
		for rt: Array in ROUTES:
			for arm: Array in ARMS:
				for pitch: float in PITCHES:
					var row := {"route": rt[0], "arm": arm[2], "pitch": pitch}
					for cfg in ["before", "after"]:
						await _cfg(cfg == "after")
						row[cfg] = await _leg(id, bxf, box, rt, arm, pitch, cfg)
					legs.append(row)
					var b: Dictionary = row["before"]
					var a: Dictionary = row["after"]
					print("[W9CAM] %s %-10s %-7s p%+.2f  B pen %.2f/%.2f hid %.2f/%.2f snap %d short %.2f reach %s | A pen %.2f/%.2f hid %.2f/%.2f snap %d short %.2f reach %s" % [
						id, rt[0], arm[2], pitch, b["pen_t"], b["pen_run"], b["hid_t"], b["hid_run"], b["snap"], b["short_t"], b["reached"],
						a["pen_t"], a["pen_run"], a["hid_t"], a["hid_run"], a["snap"], a["short_t"], a["reached"]])
		res[id] = legs
		# 証拠写真：AFTER で BEFORE より伸びた最長の pen／hidden の場面＋代表（道・腕は路線の後ろ・既定俯仰）
		var picks: Array = []
		for kind in ["pen", "hid"]:
			var best: Dictionary = {}
			var bestd := 0.05
			for row: Dictionary in legs:
				var d := float(row["after"][kind + "_run"]) - float(row["before"][kind + "_run"])
				if d > bestd and (row["after"]["worst"] as Dictionary).has(kind):
					bestd = d
					best = row
			if not best.is_empty():
				picks.append([kind, best])
		for row: Dictionary in legs:
			if row["route"] == "front_road" and row["arm"] == "along_l" and is_equal_approx(float(row["pitch"]), -0.18):
				picks.append(["typical", row])
		var shots: Array = []
		for pk: Array in picks:
			var row: Dictionary = pk[1]
			var pos: Vector3
			if pk[0] == "typical":
				pos = bxf * Vector3((float(box["x0"]) + float(box["x1"])) * 0.5, 0.0, float(box["z1"]) + 3.0)
			else:
				pos = (row["after"]["worst"][pk[0]] as Array)[0]
			var tag := "%s_%s_%s_%s_p%d" % [id.trim_prefix("B_P_"), pk[0], row["route"], row["arm"], int(round(-float(row["pitch"]) * 100))]
			for cfg in ["before", "after"]:
				await _cfg(cfg == "after")
				await _place(pos, Vector2(0, -1), bxf.origin.y)
				_set_cam(float(row["after"]["yaw"]), float(row["pitch"]))
				await _frames(5)
				_set_cam(float(row["after"]["yaw"]), float(row["pitch"]))
				var m := _metrics()
				await _snap_png(out + tag + "_" + cfg + ".png")
				shots.append([tag, cfg, m[0], m[1], snappedf(float(m[2]), 0.01)])
				print("[W9CAM] SHOT %s %s pen=%s hid=%s arm=%.2f" % [tag, cfg, m[0], m[1], m[2]])
		res[id + "__shots"] = shots
		await _cfg(true)
	var phys := {}
	for k in _phys_ms:
		phys[k] = snappedf(float(_phys_ms[k][0]) / maxf(1.0, float(_phys_ms[k][1])), 0.0001)
	res["__phys_ms"] = phys
	print("[W9CAM] physics process ms 平均：BEFORE %.4f・AFTER %.4f" % [phys["before"], phys["after"]])
	var f := FileAccess.open(out + "cam_" + ids[0].trim_prefix("B_P_") + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "\t"))
	f.close()
	quit(0)
