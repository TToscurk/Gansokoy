extends SceneTree
## 獸道 驗證器（V0.1 起；V1.2 增加岩牆節奏／Hero Rock／崖頂上游／潭岸石／草叢層）（headless、真物理）。
##   godot --headless --path godot --script res://tools/beast_path/verify_beast_path.gd [-- --out=<json>]
## 不是「程式沒報錯」就算過：每一關都量實際數值並對照 layout.limits（出處：規格書＋player_yoriichi.tscn）。
## 只讀，不寫任何遊戲檔案（報告 JSON 除外）。
const BP := preload("res://tools/beast_path/bp_lib.gd")
const ForestPlanner := preload("res://tools/beast_path/forest_planner.gd")
const S01Gates := preload("res://tools/beast_path/verify_s01_gates.gd")      # S01 R1：不連動保護＋S01 候選規劃（新增；不放寬任何既有關卡）
const SCENE := "res://maps/beast_path/beast_path.tscn"
const CAP_R := 0.3          # player_yoriichi.tscn CapsuleShape3D_body
const CAP_H := 1.7
const STEP_H := 0.35        # yoriichi_character.gd step_height

var lib: BP
var space: PhysicsDirectSpaceState3D
var inst: Node
var results: Array = []
var _plan_override: Array = []          # 反向測試的注入點（正式驗證不設）：取代 forest_plan.json 的 trees
var out_path := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.trim_prefix("--out=")
	_go.call_deferred()


func _gate(name: String, ok: bool, detail: String) -> void:
	results.append({"gate": name, "ok": ok, "detail": detail})
	print("[%s] %-34s %s" % ["PASS" if ok else "FAIL", name, detail])


func _info(name: String, detail: String) -> void:
	results.append({"gate": name, "ok": true, "info": true, "detail": detail})
	print("[INFO] %-34s %s" % [name, detail])


func _go() -> void:
	lib = BP.new()
	lib.setup(true, true)
	_g_limits()
	if not ResourceLoader.exists(SCENE):
		_gate("scene.load", false, "找不到 %s" % SCENE)
		quit(1)
		return
	var ps := ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	inst = ps.instantiate()
	root.add_child(inst)
	for i in 4:
		await physics_frame
	space = root.world_3d.direct_space_state
	_gate("scene.own_colliders_meta", bool(inst.get_meta("own_colliders", false)), "root meta own_colliders＝true 才不會被 main.gd 重複建 trimesh")
	_g_nodes()
	_g_seams()
	_g_ground_main()
	_g_capsule_paths()
	_g_arena()
	_g_boss_scenery()
	_g_trees()
	_g_forest_freeze()
	S01Gates.new().run(self)
	_g_v12()
	_g_v13()
	var fails := 0
	for r: Dictionary in results:
		if not bool(r["ok"]):
			fails += 1
	print("═══ 獸道 V1.3 驗證：%d 項、%d 失敗 ═══" % [results.size(), fails])
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"fails": fails, "results": results}, "\t") + "\n")
		f.close()
	quit(0 if fails == 0 else 1)


# ---------------------------------------------------------------- G1 規格上限（資料層）
func _g_limits() -> void:
	var lim: Dictionary = lib.lim if not lib.lim.is_empty() else lib.L["limits"]
	var mw: Array = lim["main_width"]
	var wmin := 1e9
	var wmax := -1e9
	var s := 0.0
	while s <= lib.main.length:
		var w := lib.main.w_at(s)
		wmin = minf(wmin, w)
		wmax = maxf(wmax, w)
		s += 0.5
	_gate("limits.main_width", wmin >= float(mw[0]) - 0.01 and wmax <= float(mw[1]) + 0.01, "主路寬 %.2f~%.2f m（限制 %.1f~%.1f）" % [wmin, wmax, float(mw[0]), float(mw[1])])
	var bw: Array = lim["branch_width"]
	var bad := ""
	for id: String in lib.branches:
		var br: BP.Poly = lib.branches[id]
		if String(br.kind) != "branch":
			continue
		var lo := 1e9
		var hi := -1e9
		for w in br.w:
			lo = minf(lo, w)
			hi = maxf(hi, w)
		if lo < float(bw[0]) - 0.01 or hi > float(bw[1]) + 0.01:
			bad += "%s(%.2f~%.2f) " % [id, lo, hi]
	_gate("limits.branch_width", bad == "", "支線寬皆在 %.1f~%.1f m" % [float(bw[0]), float(bw[1])] if bad == "" else "超出：" + bad)
	# 橫坡（路中心 vs 路緣）
	var cross := 0.0
	s = 0.0
	while s <= lib.main.length:
		var p := lib.main.pos_at(s)
		var t := lib.main.tan_at(s)
		var rv := BP.right_of(t)
		var hw := lib.main.w_at(s) * 0.5
		var hc := lib.h_at(p.x, p.y)
		for sg: float in [-1.0, 1.0]:
			var q: Vector2 = p + rv * sg * hw
			cross = maxf(cross, rad_to_deg(atan(absf(lib.h_at(q.x, q.y) - hc) / maxf(hw, 0.1))))
		s += 2.0
	_gate("limits.main_cross_slope", cross <= 15.0, "主路橫坡（中心↔路緣）最大 %.1f°（要求 ≤ 15°）" % cross)
	# BOSS 場
	var A: Dictionary = lib.L["boss_arena"]
	var diam := 2.0 * float(A["r_effective"])
	var bd: Array = lim["boss_combat_diameter"]
	_gate("limits.boss_diameter", diam >= float(bd[0]) and diam <= float(bd[1]), "有效戰鬥直徑 %.0f m（限制 %.0f~%.0f）" % [diam, float(bd[0]), float(bd[1])])
	var c0 := lib.arena_c()
	var maxsl := 0.0
	var n_over := 0
	var n_tot := 0
	var over_pts: Array = []
	for dx in range(-22, 23, 2):
		for dz in range(-22, 23, 2):
			if Vector2(dx, dz).length() > float(A["r_flat"]) - 2.0:
				continue
			var sl := lib.slope_deg_at(c0.x + dx, c0.y + dz)
			maxsl = maxf(maxsl, sl)
			n_tot += 1
			if sl > float(lim["arena_flat_slope_deg_max"]):
				n_over += 1
				if over_pts.size() < 6:
					over_pts.append("(%.0f,%.0f)%.0f°" % [c0.x + dx, c0.y + dz, sl])
	_gate("limits.arena_flat", n_over == 0, "戰鬥場（r≤20）坡度最大 %.1f°，超過 %.0f° 的取樣點 %d/%d %s" % [maxsl, float(lim["arena_flat_slope_deg_max"]), n_over, n_tot, str(over_pts)])
	# 場景尺寸（±25 %）
	var tol := float(lim["scene_size_tolerance"])
	var sbad := ""
	for sc: Dictionary in lib.L["scenes"]:
		var r: Array = sc["play_rect"]
		var w2 := float(r[2]) - float(r[0])
		var d2 := float(r[3]) - float(r[1])
		var nom: Array = sc["nominal"]
		if absf(w2 / float(nom[0]) - 1.0) > tol or absf(d2 / float(nom[1]) - 1.0) > tol:
			sbad += "%s(%.0f×%.0f vs %.0f×%.0f) " % [sc["id"], w2, d2, float(nom[0]), float(nom[1])]
	_gate("limits.scene_size", sbad == "", "四區尺寸皆在建議值 ±%.0f%% 內" % (tol * 100.0) if sbad == "" else "超出：" + sbad)
	# 橋面離水
	var hit := lib.resolve({"cross": "stream_main"})
	var sst: float = hit["stream_s"]
	var wl := lib.water_y_at_stream("stream_main", sst)
	var deck := lib.main.y_at(float(hit["s"]))
	var cl: Array = lim["bridge_clear_over_water"]
	_gate("limits.bridge_clear", deck - wl >= float(cl[0]) and deck - wl <= float(cl[1]), "橋面 %.2f m，水面 %.2f m → 淨高 %.2f m（要求 %.1f~%.1f）；交角 %.0f°" % [deck, wl, deck - wl, float(cl[0]), float(cl[1]), float(hit.get("cross_ang_deg", 0.0))])


func _max_grade(poly: BP.Poly, step: float) -> float:
	var worst := 0.0
	var s := 0.0
	var prev := lib.h_at(poly.pos_at(0.0).x, poly.pos_at(0.0).y)
	while s < poly.length - step:
		s += step
		var p := poly.pos_at(s)
		var h := lib.h_at(p.x, p.y)
		worst = maxf(worst, rad_to_deg(atan(absf(h - prev) / step)))
		prev = h
	return worst


# ---------------------------------------------------------------- G 節點齊全
func _find(n: Node, nm: String) -> Node:
	return n.find_child(nm, true, false)


func _g_nodes() -> void:
	var missing: Array = []
	for poi: Dictionary in lib.L["pois"]:
		var k := String(poi["kind"])
		if k == "spawn" or k == "portal_marker":
			continue
		var id := String(poi["id"])
		if _find(inst, id) == null and _find(inst, id + "_root") == null:
			missing.append(id)
	_gate("nodes.pois", missing.is_empty(), "layout.pois 的節點都存在" if missing.is_empty() else "缺：" + str(missing))
	var need := ["Spawn_S01", "Portal_Village", "PlayerSpawn_Arena", "BossSpawn", "BossTrigger", "ExitSealBlock", "Exit_Shrine_Reserved", "Exit_Bamboo_Reserved",
		"TerrainMesh", "TerrainBody", "Water", "Waterfall", "PoolSurface", "Forest"]
	var m2: Array = []
	for nm: String in need:
		if _find(inst, nm) == null:
			m2.append(nm)
	_gate("nodes.markers", m2.is_empty(), "出生點／傳送／BOSS 觸發／出口封印／地形／水／森林節點齊全" if m2.is_empty() else "缺：" + str(m2))
	var n_col := 0
	for sb in inst.find_children("*", "StaticBody3D", true, false):
		n_col += 1
	_info("nodes.static_bodies", "StaticBody3D 共 %d 個" % n_col)


# ---------------------------------------------------------------- G 接縫
func _tile_rows(sid: String) -> Dictionary:
	var mesh := ResourceLoader.load("res://maps/beast_path/gen/%s_terrain.res" % sid.to_lower(), "", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
	var arr := mesh.surface_get_arrays(0)
	var col: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	if (mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM0) != 0:
		# V1.1 S04 天然地表：COLOR 是地表權重；CUSTOM0.rgb 存的是和 S03 同一份白模頂點色（接縫淡出用）→ 接縫比對這份
		var cb: PackedByteArray = arr[Mesh.ARRAY_CUSTOM0]
		col = PackedColorArray()
		col.resize(cb.size() / 4)
		for k in col.size():
			col[k] = Color(float(cb[k * 4]) / 255.0, float(cb[k * 4 + 1]) / 255.0, float(cb[k * 4 + 2]) / 255.0, 1.0)
	return {"V": arr[Mesh.ARRAY_VERTEX], "N": arr[Mesh.ARRAY_NORMAL], "C": col}


func _g_seams() -> void:
	var sc: Array = lib.L["scenes"]
	var worst_p := 0.0
	var worst_n := 0.0
	var worst_c := 0.0
	var nan_cnt := 0
	for i in range(0, sc.size() - 1):
		var a := _tile_rows(String(sc[i]["id"]))      # 南（z 大）
		var b := _tile_rows(String(sc[i + 1]["id"]))  # 北
		var ta: Array = sc[i]["tile"]
		var nxv := int(round((float(ta[2]) - float(ta[0])) / lib.cell)) + 1
		var va: PackedVector3Array = a["V"]
		var vb: PackedVector3Array = b["V"]
		var na: PackedVector3Array = a["N"]
		var nb: PackedVector3Array = b["N"]
		var ca: PackedColorArray = a["C"]
		var cb: PackedColorArray = b["C"]
		# 南 tile 的第 0 列（最北）＝ 北 tile 的最後一列（最南）
		var last_row_off := vb.size() - nxv
		for k in nxv:
			worst_p = maxf(worst_p, va[k].distance_to(vb[last_row_off + k]))
			worst_n = maxf(worst_n, na[k].distance_to(nb[last_row_off + k]))
			worst_c = maxf(worst_c, absf(ca[k].r - cb[last_row_off + k].r) + absf(ca[k].g - cb[last_row_off + k].g) + absf(ca[k].b - cb[last_row_off + k].b))
	for sci: Dictionary in sc:
		var t := _tile_rows(String(sci["id"]))
		for v: Vector3 in (t["V"] as PackedVector3Array):
			if is_nan(v.x) or is_nan(v.y) or is_nan(v.z) or is_inf(v.y):
				nan_cnt += 1
	_gate("seams.tiles", worst_p < 1e-4 and worst_n < 1e-4 and worst_c < 1e-4, "S01|S02|S03|S04 接縫列：位置差 %.6f、法線差 %.6f、顏色差 %.6f" % [worst_p, worst_n, worst_c])
	_gate("terrain.finite", nan_cnt == 0, "地形頂點 NaN/Inf：%d" % nan_cnt)


# ---------------------------------------------------------------- G 地面連續性＋行走面坡度
func _ray_down(x: float, y_top: float, z: float, y_bot: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, y_top, z), Vector3(x, y_bot, z))
	return space.intersect_ray(q)


## 預期會擋住盡頭的東西（出口封印、預留木戶）不算地面
func _is_barrier(h: Dictionary) -> bool:
	var col := h["collider"] as Node
	if col == null:
		return false
	var path := String(inst.get_path_to(col))
	return path.contains("ExitSealBlock") or path.contains("lane_gate")


## 沿 poly 每 0.5 m 向下射線，回傳 {holes, steps_over, worst_step, worst_at, grade_deg（2 m 窗）, nonterrain}
func _walk_surface(poly: BP.Poly, use_poly_y: bool) -> Dictionary:
	var ys: Array = []
	var holes := 0
	var steps_over := 0
	var worst_step := 0.0
	var worst_at := Vector2.ZERO
	var nonterrain := 0
	var prev := 0.0
	var first := true
	var s := 0.0
	while s <= poly.length:
		var p := poly.pos_at(s)
		var yc := poly.y_at(s) if use_poly_y else lib.h_at(p.x, p.y)
		var h := _ray_down(p.x, yc + 3.0, p.y, yc - 6.0)
		if h.is_empty():
			holes += 1
			ys.append(null)
		elif _is_barrier(h):
			ys.append(null)
		else:
			var y: float = (h["position"] as Vector3).y
			ys.append(y)
			if not first:
				var d := absf(y - prev)
				if d > worst_step:
					worst_step = d
					worst_at = p
				if d > STEP_H + 0.10:
					steps_over += 1
			prev = y
			first = false
			if String((h["collider"] as Node).name) != "TerrainBody":
				nonterrain += 1
		s += 0.5
	var grade := 0.0
	for i in range(0, ys.size() - 4):
		if ys[i] == null or ys[i + 4] == null:
			continue
		grade = maxf(grade, rad_to_deg(atan(absf(float(ys[i + 4]) - float(ys[i])) / 2.0)))
	return {"holes": holes, "steps_over": steps_over, "worst_step": worst_step, "worst_at": worst_at, "grade": grade, "nonterrain": nonterrain}


func _g_ground_main() -> void:
	var lim: Dictionary = lib.L["limits"]
	var m := _walk_surface(lib.main, true)
	_gate("ground.main_no_holes", int(m["holes"]) == 0, "主路 %.0f m 沿線每 0.5 m 向下射線：無地面 %d 處" % [lib.main.length, int(m["holes"])])
	var wa: Vector2 = m["worst_at"]
	_gate("ground.main_steps", int(m["steps_over"]) == 0, "相鄰 0.5 m 取樣的行走面高差最大 %.2f m @ (%.0f,%.0f)（玩家 step_height %.2f，容許 +0.10）；超過 %d 處；橋面等非地形碰撞命中 %d 點" % [float(m["worst_step"]), wa.x, wa.y, STEP_H, int(m["steps_over"]), int(m["nonterrain"])])
	_gate("limits.main_grade", float(m["grade"]) <= float(lim["main_grade_deg_max"]), "主路行走面最大縱坡（2 m 窗，含橋面）%.1f°（限制 %.0f°）" % [float(m["grade"]), float(lim["main_grade_deg_max"])])
	var bh := 0
	var bs := 0
	var bg := 0.0
	var worst_txt := ""
	for id: String in lib.branches:
		var r := _walk_surface(lib.branches[id], false)
		bh += int(r["holes"])
		bs += int(r["steps_over"])
		bg = maxf(bg, float(r["grade"]))
		if int(r["steps_over"]) > 0 or int(r["holes"]) > 0:
			var w: Vector2 = r["worst_at"]
			worst_txt += "%s(高差 %.2f @ %.0f,%.0f) " % [id, float(r["worst_step"]), w.x, w.y]
	_gate("ground.branches", bh == 0 and bs == 0, "四條支線沿線（排除出口封印／預留木戶）：無地面 %d、高差超過 %.2f m 的 %d 處 %s" % [bh, STEP_H + 0.10, bs, worst_txt])
	_gate("limits.branch_grade", bg <= float(lim["branch_grade_deg_max"]), "支線行走面最大縱坡 %.1f°（限制 %.0f°）" % [bg, float(lim["branch_grade_deg_max"])])


# ---------------------------------------------------------------- G 玩家膠囊沿線掃描
func _capsule_hits(c: Vector3) -> Array:
	var shape := CapsuleShape3D.new()
	shape.radius = CAP_R
	shape.height = CAP_H
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, c)
	q.margin = 0.0
	var res := space.intersect_shape(q, 16)
	var names: Array = []
	for r: Dictionary in res:
		var col := r["collider"] as Node
		if col == null:
			continue
		if String(col.name) == "TerrainBody":
			continue
		names.append(String(inst.get_path_to(col)))
	return names


func _sweep_poly(poly: BP.Poly, use_poly_y: bool) -> Dictionary:
	var blocked: Dictionary = {}
	var s := 0.0
	var n := 0
	while s <= poly.length:
		var p := poly.pos_at(s)
		var yc := poly.y_at(s) if use_poly_y else lib.h_at(p.x, p.y)
		var h := _ray_down(p.x, yc + 3.0, p.y, yc - 6.0)
		if not h.is_empty():
			var gy: float = (h["position"] as Vector3).y
			for nm: String in _capsule_hits(Vector3(p.x, gy + STEP_H + CAP_H * 0.5 + 0.03, p.y)):
				if not blocked.has(nm):
					blocked[nm] = [snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(s, 0.1)]
		s += 0.5
		n += 1
	return {"blocked": blocked, "n": n}


func _g_capsule_paths() -> void:
	var m := _sweep_poly(lib.main, true)
	_gate("capsule.main", (m["blocked"] as Dictionary).is_empty(), "主路 %d 個取樣點，玩家膠囊（r=%.1f h=%.1f，離地 +%.2f）沿線被非地形碰撞擋住：%s" % [m["n"], CAP_R, CAP_H, STEP_H, str(m["blocked"])])
	var expected := {"exit_shrine": "ExitSealBlock", "return_lane": "lane_gate"}
	for id: String in lib.branches:
		var br: BP.Poly = lib.branches[id]
		var r := _sweep_poly(br, false)
		var bl: Dictionary = r["blocked"]
		var ok := true
		var detail := ""
		if expected.has(id):
			# 這兩條在盡頭刻意被封（出口封印／預留木戶）：只允許被「預期的那一個」擋住
			for k: String in bl:
				if not String(k).contains(String(expected[id])):
					ok = false
			detail = "（盡頭刻意被 %s 封住）" % expected[id]
		else:
			ok = bl.is_empty()
		_gate("capsule.branch.%s" % id, ok, "%d 點；擋住：%s %s" % [r["n"], str(bl), detail])


# ---------------------------------------------------------------- G BOSS 場
func _g_arena() -> void:
	var A: Dictionary = lib.L["boss_arena"]
	var c0 := lib.arena_c()
	var free_r := float(lib.L["limits"]["arena_central_free_r"])
	var bad: Dictionary = {}
	var n := 0
	for dx in range(-14, 15):
		for dz in range(-14, 15):
			var v := Vector2(dx, dz)
			if v.length() > free_r:
				continue
			var p := c0 + v
			var gy := lib.h_at(p.x, p.y)
			var shape := SphereShape3D.new()
			shape.radius = 0.5
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = shape
			q.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, gy + STEP_H + 0.6, p.y))
			for r: Dictionary in space.intersect_shape(q, 8):
				var col := r["collider"] as Node
				if col != null and String(col.name) != "TerrainBody":
					bad[String(inst.get_path_to(col))] = [snappedf(p.x, 0.1), snappedf(p.y, 0.1)]
			n += 1
	_gate("arena.central_free", bad.is_empty(), "戰鬥場中央 r<%.0f m 共 %d 個取樣點，碰撞物：%s" % [free_r, n, str(bad)])
	# 玩家出生點／BOSS 出生點／出入口貼地
	var mk_ok := true
	var txt := ""
	for nm: String in ["PlayerSpawn_Arena", "BossSpawn"]:
		var node := _find(inst, nm) as Node3D
		var g := _ray_down(node.global_position.x, node.global_position.y + 2.0, node.global_position.z, node.global_position.y - 4.0)
		var dy := node.global_position.y - float((g["position"] as Vector3).y) if not g.is_empty() else 99.0
		txt += "%s 離地 %.2f m  " % [nm, dy]
		if dy > 0.5 or dy < -0.1:
			mk_ok = false
	_gate("arena.spawns_grounded", mk_ok, txt)
	# 繞圈：以 r=18 圓周取 72 點，膠囊不得被非地形碰撞擋住（B04 掩體只在外環 r 15~19.5，不能把圈堵死）
	var blocked_ring := 0
	var worst_free := 99.0
	for rr: float in [8.0, 12.0]:
		for k in 72:
			var a := TAU * float(k) / 72.0
			var p2 := c0 + Vector2(sin(a), -cos(a)) * rr
			var gy2 := lib.h_at(p2.x, p2.y)
			if not _capsule_hits(Vector3(p2.x, gy2 + STEP_H + CAP_H * 0.5 + 0.03, p2.y)).is_empty():
				blocked_ring += 1
	_gate("arena.circling", blocked_ring == 0, "r=8/12 m 兩圈共 144 點可繞行，被擋 %d 點" % blocked_ring)


# ---------------------------------------------------------------- G 森林節點
func _g_trees() -> void:
	var forest_n := 0
	var floating := 0
	var worst := 0.0
	for f in inst.find_children("Forest", "Node3D", true, false):
		for c in (f as Node).get_children():
			var n3 := c as Node3D
			if n3 == null:
				continue
			forest_n += 1
			var gy := lib.h_at(n3.global_position.x, n3.global_position.z)
			var d := n3.global_position.y - gy
			worst = maxf(worst, absf(d))
			if d > 0.15 or d < -0.9:
				floating += 1
	_gate("trees.grounded", floating == 0 and forest_n > 0, "森林實例 %d 個，離地高度異常（> +0.15 或 < −0.9 m）%d 個，最大偏差 %.2f m" % [forest_n, floating, worst])
	var plan_n := 0
	var f := FileAccess.open("res://maps/beast_path/gen/forest_plan.json", FileAccess.READ)
	if f != null:
		var j: Variant = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			plan_n = (j["trees"] as Array).size()
	_gate("trees.match_plan", plan_n == forest_n, "forest_plan.json %d 筆＝場景實例 %d 個" % [plan_n, forest_n])


# ---------------------------------------------------------------- G BOSS 場景觀：崖面／水潭／瀑布／岩壁／石鋪
func _g_boss_scenery() -> void:
	var A: Dictionary = lib.L["boss_arena"]
	var cx := float(A["waterfall"]["x"])
	var pz := float(A["pool"]["z"])
	# 1) 北崖：近垂直、至少 12 m 的落差在 4 m 水平距離內（37° 的河岸錐曾把它削掉）
	var best_rise := 0.0
	var best_z := 0.0
	var z := pz - 4.0
	while z > pz - 24.0:
		var rise := lib.h_at(cx, z - 4.0) - lib.h_at(cx, z)
		if rise > best_rise:
			best_rise = rise
			best_z = z
		z -= 0.5
	var peak := 0.0
	z = pz - 4.0
	while z > pz - 24.0:
		peak = maxf(peak, rad_to_deg(atan(absf(lib.h_at(cx, z - 0.5) - lib.h_at(cx, z + 0.5)))))
		z -= 0.5
	_gate("cliff.face", best_rise >= 12.0 and peak >= 65.0, "北崖（x=%.0f）：4 m 水平距離內最大落差 %.1f m（z=%.0f 起）、最陡 %.0f°（要求 ≥ 12 m、≥ 65°）" % [cx, best_rise, best_z, peak])
	# 2) 水潭：水面高於潭底；從潭心往 8 個方位走，地形在 2.5~8 m 內升到水面以上＝有岸（至少 6 個方位，其餘為支流出口）
	var pc := Vector2(float(A["pool"]["x"]), pz)
	var wl := lib.water_y_at_stream("stream_trib", 0.0)
	var bed := lib.h_at(pc.x, pc.y)
	var shore_ok := 0
	var open_dirs: Array = []
	var shore_txt := ""
	for k in 8:
		var a := TAU * float(k) / 8.0
		var dirv := Vector2(sin(a), -cos(a))
		var rs := -1.0
		var rad := 0.5
		while rad <= 8.0:
			var q := pc + dirv * rad
			if lib.h_at(q.x, q.y) >= wl - 0.01:
				rs = rad
				break
			rad += 0.25
		if rs >= 2.5:
			shore_ok += 1
			shore_txt += "%.1f " % rs
		else:
			open_dirs.append("%d°" % int(round(rad_to_deg(a))))
	var pool_mi := _find(inst, "PoolSurface") as MeshInstance3D
	var ptri := ((pool_mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	_gate("pool.shoreline", wl - bed >= 0.25 and shore_ok >= 6 and ptri >= 100, "潭底 %.2f、水面 %.2f（水深 %.2f m）；8 個方位中 %d 個在 2.5~8 m 內有岸（距離 %s），缺口：%s；水面依地形裁切 %d 個三角形" % [bed, wl, wl - bed, shore_ok, shore_txt, str(open_dirs), ptri])
	# 2b) 從戰場看得到潭：玩家出生點眼高（+1.6 m）到潭面上三個點的視線不得被地形／岩片擋住
	var eye := (_find(inst, "PlayerSpawn_Arena") as Node3D).global_position + Vector3(0, 1.6, 0)
	var seen := 0
	var blockers: Array = []
	for dx: float in [-2.0, 0.0, 2.0]:
		var tgt := Vector3(pc.x + dx, wl + 0.03, pc.y)
		var rq := PhysicsRayQueryParameters3D.create(eye, tgt)
		var rh := space.intersect_ray(rq)
		if rh.is_empty():
			seen += 1
		else:
			var hp: Vector3 = rh["position"]
			blockers.append("%s @(%.1f,%.1f,%.1f)" % [String(inst.get_path_to(rh["collider"] as Node)), hp.x, hp.y, hp.z])
	_gate("pool.visible_from_arena", seen >= 2, "戰場出生點眼高 %.1f m → 潭面 3 個取樣點中 %d 個視線通暢（要求 ≥ 2）；擋住的：%s" % [eye.y, seen, str(blockers)])
	# 3) 瀑布幕：每個頂點離崖面 0.02~1.4 m（水平射線往北打到地形），且不在地形裡面
	var wf := _find(inst, "Waterfall") as MeshInstance3D
	var arrs := (wf.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
	var n_curtain := verts.size()                  # V1.1：surface 0 只有水幕（上游帶在 surface 1）
	var hit := 0
	var inside := 0
	var far_ := 0
	for i in n_curtain:
		var v := verts[i]
		if lib.h_at(v.x, v.z) > v.y + 0.12:
			inside += 1
		var q2 := PhysicsRayQueryParameters3D.create(v + Vector3(0, 0, 0.01), v + Vector3(0, 0, -2.6))
		var r := space.intersect_ray(q2)
		if r.is_empty():
			far_ += 1
		else:
			var dist := v.distance_to(r["position"])
			if dist >= 0.02 and dist <= 1.4:
				hit += 1
			else:
				far_ += 1
	var ratio := float(hit) / float(maxi(n_curtain, 1))
	# 最頂列在崖頂（面轉成平台），射線會打不到——所以門檻 88 %，並且不得有頂點在地形裡面超過 2 %
	_gate("waterfall.on_face", ratio >= 0.88 and float(inside) / float(maxi(n_curtain, 1)) <= 0.02, "水幕頂點 %d 個：離崖面 0.02~1.4 m 的 %d（%.0f%%）、在地形裡 %d、離崖太遠/打不到 %d" % [n_curtain, hit, ratio * 100.0, inside, far_])
	# 4) 岩壁：環形崖岩片數量、不侵入平坦戰場、四周有分布（東西各 ≥ 3）
	var slabs: Array = []
	for nd in inst.find_children("*", "Node3D", true, false):
		if nd.has_meta("bp_slab"):
			slabs.append(nd)
	var c0 := lib.arena_c()
	var min_edge := 1e9
	var east := 0
	var west := 0
	for sl: Node3D in slabs:
		var sp := Vector2(sl.global_position.x, sl.global_position.z)
		var edge := sp.distance_to(c0) - float(sl.get_meta("bp_slab_r"))
		min_edge = minf(min_edge, edge)
		if sp.x > c0.x + 10.0:
			east += 1
		elif sp.x < c0.x - 10.0:
			west += 1
	_gate("arena.walls", slabs.size() >= 18 and min_edge >= 21.0 and east >= 3 and west >= 6, "崖岩片 %d 片（東 %d、西 %d）；最近一片的內緣離戰場中心 %.1f m（平坦圓 r=%.0f，要求 ≥ 21）" % [slabs.size(), east, west, min_edge, float(A["r_flat"])])
	# 4b) 入口隘口：南口兩側的守門岩（JL／JR）之間淨寬 6~16 m——寬了沒有「隘口」，窄了擋路
	var jl: Node3D = null
	var jr: Node3D = null
	for sl2: Node3D in slabs:
		if String(sl2.name).contains("_JL_"):
			jl = sl2
		elif String(sl2.name).contains("_JR_"):
			jr = sl2
	var gap := -1.0
	if jl != null and jr != null:
		gap = Vector2(jl.global_position.x, jl.global_position.z).distance_to(Vector2(jr.global_position.x, jr.global_position.z)) - float(jl.get_meta("bp_slab_r")) - float(jr.get_meta("bp_slab_r"))
	_gate("arena.entrance_jaws", gap >= 6.0 and gap <= 16.0, "南口守門岩 JL／JR 淨寬 %.1f m（要求 6~16 m；主路寬 %.1f m）" % [gap, lib.main.w_at(lib.st_s("arena_s"))])
	# 5) V1.1 天然地表：沒有人工石鋪／環紋／場邊石柱／祭壇；地面是 bp_ground 材質；組成落在「泥土為主」的範圍
	var s4 := _find(inst, "S04_BossClearing")
	var bad_nodes: Array = []
	for nm: String in ["ArenaPaving", "arena_altar"]:
		if _find(s4, nm) != null:
			bad_nodes.append(nm)
	for n3 in s4.find_children("arena_pillar_*", "", true, false):
		bad_nodes.append(String(n3.name))
	for mi3 in s4.find_children("*", "MeshInstance3D", true, false):
		var m3 := (mi3 as MeshInstance3D).mesh
		if m3 == null:
			continue
		for sj in m3.get_surface_count():
			var sm3 := m3.surface_get_material(sj) as ShaderMaterial
			if sm3 != null and sm3.shader != null and sm3.shader.resource_path.contains("arena_paving"):
				bad_nodes.append(String(mi3.name) + ":arena_paving")
	var bad_keys: Array = []
	for k3: String in ["rings", "pillars", "altar"]:
		if A.has(k3):
			bad_keys.append(k3)
	_gate("arena.no_artificial_paving", bad_nodes.is_empty() and bad_keys.is_empty(), "S04 沒有鋪石覆層／環紋／場邊石柱／祭壇（殘留節點 %s、殘留 layout 鍵 %s）" % [str(bad_nodes), str(bad_keys)])
	var tmesh := s4.get_node("TerrainMesh") as MeshInstance3D
	var gm := tmesh.mesh.surface_get_material(0) as ShaderMaterial
	var mat_ok := gm != null and gm.shader != null and gm.shader.resource_path.ends_with("bp_ground.gdshader")
	var miss_tex: Array = []
	if gm != null:
		for un: String in ["albedo_arr", "nrh_arr", "noise_tex"]:
			if gm.get_shader_parameter(un) == null:
				miss_tex.append(un)
	var tfmt: int = (tmesh.mesh as ArrayMesh).surface_get_format(0)
	var fmt_ok := (tfmt & Mesh.ARRAY_FORMAT_CUSTOM0) != 0 and (tfmt & Mesh.ARRAY_FORMAT_TEX_UV2) != 0
	_gate("arena.ground_material", mat_ok and miss_tex.is_empty() and fmt_ok, "S04 地形用 bp_ground.gdshader（材質 %s；缺貼圖 %s；頂點格式含 UV2／CUSTOM0：%s）" % [str(mat_ok), str(miss_tex), str(fmt_ok)])
	# 5a) V1.1 岩壁／水體：崖岩片與巨石是 rock_builder 生成的自然岩石（外部 .res、bp_rock 材質、平滑法線、頂點屬性齊），
	#     瀑布幕／潭／支流用 bp_waterfall／bp_water 材質；沒有 V0.1 的「6×6 細分方盒＋平面著色」
	var n_rock := 0
	var rock_bad: Array = []
	var rock_tri := 0
	for mi4 in s4.find_children("*", "MeshInstance3D", true, false):
		var par := mi4.get_parent()
		if par == null or not (par.has_meta("bp_slab") or par.has_meta("bp_rock_r")):
			continue
		n_rock += 1
		var rm := (mi4 as MeshInstance3D).mesh as ArrayMesh
		var okm := rm != null and rm.resource_path.begins_with("res://maps/beast_path/gen/rocks/")
		if okm:
			var rfmt: int = rm.surface_get_format(0)
			okm = (rfmt & Mesh.ARRAY_FORMAT_NORMAL) != 0 and (rfmt & Mesh.ARRAY_FORMAT_COLOR) != 0
			var rsm := rm.surface_get_material(0) as ShaderMaterial
			okm = okm and rsm != null and rsm.shader != null and rsm.shader.resource_path.ends_with("bp_rock.gdshader")
			rock_tri += rm.surface_get_array_index_len(0) / 3
		if not okm:
			rock_bad.append(String(par.name))
	_gate("arena.natural_rocks", n_rock >= 40 and rock_bad.is_empty() and rock_tri > 40000, "S04 崖岩片／巨石 %d 件全是自然岩石（外部網格＋bp_rock 材質＋法線＋頂點屬性）；總 %d 三角形；不合格 %s" % [n_rock, rock_tri, str(rock_bad)])
	var wat_ok := true
	var wat_bad: Array = []
	for mi5 in s4.find_children("*", "MeshInstance3D", true, false):
		var wm5 := (mi5 as MeshInstance3D).mesh
		if wm5 == null or not (String(wm5.resource_name).contains("waterfall") or String(wm5.resource_name).contains("pool_surface") or String(wm5.resource_name).ends_with("_water")):
			continue
		for sj5 in wm5.get_surface_count():
			var sm5 := wm5.surface_get_material(sj5) as ShaderMaterial
			if sm5 == null or sm5.shader == null or not (sm5.shader.resource_path.ends_with("bp_water.gdshader") or sm5.shader.resource_path.ends_with("bp_waterfall.gdshader")):
				wat_ok = false
				wat_bad.append("%s#%d" % [wm5.resource_name, sj5])
	_gate("arena.water_materials", wat_ok and wat_bad.is_empty(), "S04 瀑布幕／潭面／支流都用 bp_waterfall／bp_water 材質（不合格 %s）" % str(wat_bad))
	# 5b) 戰鬥圓（r ≤ 20）內的地表組成（取自場景裡實際存的網格權重）：規格 V1.1 的視覺參考——泥土約 6 成、草土約 2 成、落葉約 1 成、碎石／裸岩約 1 成
	var garr := (tmesh.mesh as ArrayMesh).surface_get_arrays(0)
	var gv: PackedVector3Array = garr[Mesh.ARRAY_VERTEX]
	var gc: PackedColorArray = garr[Mesh.ARRAY_COLOR]
	var gu: PackedVector2Array = garr[Mesh.ARRAY_TEX_UV]
	var gu2: PackedVector2Array = garr[Mesh.ARRAY_TEX_UV2]
	var n_in := 0
	var f_dirt := 0.0
	var f_grass := 0.0
	var f_leaf := 0.0
	var f_stone := 0.0
	var f_moss := 0.0
	var f_wet := 0.0
	for gi in gv.size():
		if Vector2(gv[gi].x, gv[gi].z).distance_to(c0) > 20.0:
			continue
		n_in += 1
		var tot := gc[gi].r + gc[gi].g + gc[gi].b + gc[gi].a + gu[gi].x
		f_dirt += gc[gi].r + gc[gi].b
		f_stone += gc[gi].g + gc[gi].a
		f_leaf += gu[gi].x
		f_grass += maxf(1.0 - tot, 0.0)
		f_moss += gu2[gi].x
		f_wet += gu[gi].y
	var inv := 1.0 / float(maxi(n_in, 1))
	f_dirt *= inv
	f_grass *= inv
	f_leaf *= inv
	f_stone *= inv
	f_moss *= inv
	f_wet *= inv
	_gate("arena.ground_mix", n_in > 800 and f_dirt >= 0.48 and f_dirt <= 0.74 and f_grass >= 0.10 and f_grass <= 0.32 and f_leaf >= 0.04 and f_leaf <= 0.20 and f_stone >= 0.02 and f_stone <= 0.14,
		"戰鬥圓內 %d 個頂點：泥土 %.0f%%（要求 48–74）、草土 %.0f%%（10–32）、落葉 %.0f%%（4–20）、碎石／裸岩 %.0f%%（2–14）；苔覆蓋均值 %.2f、濕度均值 %.2f" % [n_in, f_dirt * 100.0, f_grass * 100.0, f_leaf * 100.0, f_stone * 100.0, f_moss, f_wet])


# ---------------------------------------------------------------- V1.2 E：S01–S03 森林凍結＋分區亂數獨立
const FREEZE_KEYS := ["id", "kind", "pin"]
const FREEZE_NUM := ["x", "z", "y", "s", "yaw"]


func _entry_eq(a: Dictionary, b: Dictionary) -> bool:
	for k: String in FREEZE_KEYS:
		if String(a[k]) != String(b[k]):
			return false
	for k: String in FREEZE_NUM:
		if absf(float(a[k]) - float(b[k])) > 1e-6:
			return false
	return true


func _scene_entries(arr: Array, sc: String) -> Array:
	var r: Array = []
	for t: Dictionary in arr:
		if String(t["scene"]) == sc:
			r.append(t)
	return r


func _g_forest_freeze() -> void:
	var fz: Dictionary = (lib.L["forest"] as Dictionary).get("freeze", {})
	var scenes: Array = fz.get("scenes", [])
	var path := String(fz.get("file", ""))
	var frozen: Dictionary = {}
	var sha_ok := false
	if not fz.is_empty() and FileAccess.file_exists(path):
		sha_ok = FileAccess.get_sha256(path) == String(fz.get("sha256", ""))
		var src: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if src is Dictionary:
			frozen = (src as Dictionary).get("scenes", {})
	var n_frozen := 0
	for sc: String in scenes:
		n_frozen += (frozen.get(sc, []) as Array).size()
	# S01 R1（使用者 2026-10-16 授權只解凍 S01）：凍結檔本身（V0.1，含 S01 的 380 筆）是歷史基準，雜湊與筆數必須原樣；
	# 現行凍結區＝S02／S03（逐棵原樣載入、不重抽）；S01 解凍就必須宣告候選規劃（layout.forest.s01_candidate），否則 S01 會被舊抽樣悄悄換掉。
	var hist: Dictionary = fz.get("history_counts", {})
	var n_hist := 0
	var hist_ok := true
	for hsc: String in ["S01", "S02", "S03"]:
		var hn := (frozen.get(hsc, []) as Array).size()
		n_hist += hn
		if hn != int(hist.get(hsc, -1)):
			hist_ok = false
	var cand0: Dictionary = (lib.L["forest"] as Dictionary).get("s01_candidate", {})
	var s01_decl := not scenes.has("S01") and bool(cand0.get("enabled", false))
	_gate("forest.freeze_file", bool(fz.get("enabled", false)) and sha_ok and n_hist == 2776 and hist_ok and scenes == ["S02", "S03"] and n_frozen == 2396 and s01_decl,
		"凍結檔 %s：雜湊吻合 %s；歷史基準 %d 筆（S01 %d／S02 %d／S03 %d；V0.1 為 380／1213／1183）；現行凍結區 %s 共 %d 筆（要求 2396）；S01 已宣告候選規劃 %s" % [path.get_file(), str(sha_ok), n_hist, (frozen.get("S01", []) as Array).size(), (frozen.get("S02", []) as Array).size(), (frozen.get("S03", []) as Array).size(), str(scenes), n_frozen, str(s01_decl)])
	# (a) 規劃檔 forest_plan.json 的 S01–S03 與凍結檔逐筆相同（id／kind／pin／x／z／y／s／yaw）
	var pf := FileAccess.open("res://maps/beast_path/gen/forest_plan.json", FileAccess.READ)
	var plan_trees: Array = []
	if not _plan_override.is_empty():
		plan_trees = _plan_override
	elif pf != null:
		var pj: Variant = JSON.parse_string(pf.get_as_text())
		if pj is Dictionary:
			plan_trees = (pj as Dictionary)["trees"]
	var diff_plan := 0
	var cnt_plan := 0
	for sc: String in scenes:
		var a: Array = _scene_entries(plan_trees, sc)
		var b: Array = frozen.get(sc, [])
		cnt_plan += a.size()
		if a.size() != b.size():
			diff_plan += absi(a.size() - b.size())
			continue
		for i in a.size():
			if not _entry_eq(a[i], b[i]):
				diff_plan += 1
	_gate("forest.frozen_plan_equal", diff_plan == 0 and cnt_plan == n_frozen and cnt_plan > 0,
		"forest_plan.json 的 %s 共 %d 筆，與凍結檔（V0.1）逐筆比對不同 %d 筆" % [str(scenes), cnt_plan, diff_plan])
	# (b) 場景裡實際的 Forest 節點 transform ＝ 凍結檔存的 transform（逐位元還原的證據）
	var diff_scene := 0
	var cnt_scene := 0
	var worst := 0.0
	for f in inst.find_children("Forest", "Node3D", true, false):
		var sc2 := String((f as Node).get_parent().get_meta("bp_scene", ""))
		if not scenes.has(sc2):
			continue
		var fr: Array = frozen.get(sc2, [])
		var kids := (f as Node).get_children()
		if kids.size() != fr.size():
			diff_scene += absi(kids.size() - fr.size())
			continue
		for i in kids.size():
			var n3 := kids[i] as Node3D
			var tb := n3.global_transform.basis
			var to := n3.global_transform.origin
			var got := [tb.x.x, tb.y.x, tb.z.x, tb.x.y, tb.y.y, tb.z.y, tb.x.z, tb.y.z, tb.z.z, to.x, to.y, to.z]
			var xf: Array = (fr[i] as Dictionary)["xf"]
			var bad := false
			for k in 12:
				var e := absf(float(got[k]) - float(xf[k]))
				worst = maxf(worst, e)
				if e > 1e-5 * maxf(1.0, absf(float(xf[k]))):
					bad = true
			if bad or not String(n3.name).begins_with(String((fr[i] as Dictionary)["id"]) + "_"):
				diff_scene += 1
			cnt_scene += 1
	_gate("forest.frozen_scene_equal", diff_scene == 0 and cnt_scene == n_frozen,
		"%s 場景裡 %d 棵植被的 transform 與凍結檔（V0.1 場景存檔值）不同 %d 棵；最大數值差 %f" % [str(scenes), cnt_scene, diff_scene, worst])
	# (c) 分區獨立：關掉凍結，只擾動 S04 的規則（加一塊空地＋密度×1.35）→ S01–S03 必須一棵都不變，S04 必須變（對照組，證明擾動有效）
	var pa := ForestPlanner.new()
	pa.setup(lib, [])
	pa.set_freeze(false)
	pa.plan()
	var pb := ForestPlanner.new()
	pb.setup(lib, [])
	pb.set_freeze(false)
	pb.perturb_s04()
	pb.plan()
	var leak := 0
	var n_other := 0
	for sc3: String in ["S01", "S02", "S03"]:
		var ea: Array = _scene_entries(pa.trees, sc3)
		var eb: Array = _scene_entries(pb.trees, sc3)
		n_other += ea.size()
		if ea.size() != eb.size():
			leak += absi(ea.size() - eb.size())
			continue
		for i in ea.size():
			if not _entry_eq(ea[i], eb[i]):
				leak += 1
	var s4a: Array = _scene_entries(pa.trees, "S04")
	var s4b: Array = _scene_entries(pb.trees, "S04")
	var s4_changed := s4a.size() != s4b.size()
	if not s4_changed:
		for i in s4a.size():
			if not _entry_eq(s4a[i], s4b[i]):
				s4_changed = true
				break
	_gate("forest.zone_independent", leak == 0 and n_other > 2000 and s4_changed and pa.freeze_error == "" and pb.freeze_error == "",
		"不靠凍結檔、只改 S04 規則：S01–S03 共 %d 筆植被改變 %d 筆（要求 0）；S04 %d→%d 筆（對照組：必須有變）" % [n_other, leak, s4a.size(), s4b.size()])


# ================================================================= V1.2 新增內容
const Rhythm := preload("res://tools/beast_path/rhythm_lib.gd")
const Meadow := preload("res://tools/beast_path/meadow_s04.gd")
const ML := preload("res://tools/village_v2_meadow_lib.gd")
const RockBuilder := preload("res://tools/beast_path/rock_builder.gd")
const TG := preload("res://tools/beast_path/terrain_generator.gd")
const MEADOW_INPUTS := "res://maps/beast_path/gen/s04_meadow_inputs.json"
var _meadow_adopted: Dictionary = {}                                # V1.3：_g_v12_meadow 算過的凍結採用結果（_g_v13_meadow 沿用）


func _g_v12() -> void:
	_g_v12_rhythm()
	_g_v12_hero()
	_g_v12_falls()
	_g_v12_shore()
	_g_v12_meadow()
	_g_v12_shadow_budget()


## 戰場往四周看，岩壁不得連成一整圈（使用者：「大型岩石連成封閉岩牆，形成明顯人工競技場感」）
func _g_v12_rhythm() -> void:
	var m: Dictionary = Rhythm.measure(space, lib)
	var c: Dictionary = m["center"]
	var ok := float(c["rock_frac"]) <= 0.40 and float(m["rock_frac_mean"]) <= 0.42 and float(m["tall_frac_mean"]) <= 0.20 \
		and float(m["max_arc_worst"]) <= 40.0 and float(c["max_arc_deg"]) <= 30.0 and int(c["gaps"]) >= 4
	_gate("arena.rock_rhythm", ok, "戰場中央視野：岩壁岩 %.0f%%（≤ 40）、高岩 %.0f%%、最長連續岩壁弧 %.0f°（≤ 30）、缺口 %d 個（≥ 4）；9 站平均岩壁岩 %.0f%%（≤ 42）／高岩 %.0f%%（≤ 20）、最差站最長弧 %.0f°（≤ 40）。對照 V1.1 實測：59%%／59%%／42°／74°" % [
		float(c["rock_frac"]) * 100.0, float(c["tall_frac"]) * 100.0, float(c["max_arc_deg"]), int(c["gaps"]),
		float(m["rock_frac_mean"]) * 100.0, float(m["tall_frac_mean"]) * 100.0, float(m["max_arc_worst"])])


## Hero Rock：Godot 裡實際的尺寸、材質、碰撞、與 GLB 現檔的對應
func _g_v12_hero() -> void:
	var heroes: Array = []
	for nd in inst.find_children("*", "Node3D", true, false):
		if nd.has_meta("bp_hero"):
			heroes.append(nd)
	var forms := {}
	var bad: Array = []
	var info_parts: Array = []
	for h: Node3D in heroes:
		var form := String(h.get_meta("bp_hero"))
		forms[form] = true
		var mi: MeshInstance3D = null
		for c in h.get_children():
			if c is MeshInstance3D:
				mi = c
		if mi == null or mi.mesh == null:
			bad.append("%s 沒有網格" % h.name)
			continue
		var ab := mi.mesh.get_aabb()
		var want: Vector3 = h.get_meta("bp_hero_size", Vector3.ZERO)
		var why := ""
		if want == Vector3.ZERO or absf(ab.size.x - want.x) > want.x * 0.03 or absf(ab.size.y - want.y) > want.y * 0.03 or absf(ab.size.z - want.z) > want.z * 0.03:
			why += "尺寸 %s ≠ 預期 %s；" % [str(ab.size.snapped(Vector3.ONE * 0.01)), str(want.snapped(Vector3.ONE * 0.01))]
		var mat := mi.mesh.surface_get_material(0)
		if mat == null or not String(mat.resource_path).ends_with("bp_rock.tres"):
			why += "材質不是 bp_rock.tres；"
		var arr := mi.mesh.surface_get_arrays(0)
		var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cc: Variant = arr[Mesh.ARRAY_COLOR]
		if cc == null or (cc as PackedColorArray).size() != vv.size():
			why += "缺頂點色；"
		var cols := h.find_children("*", "CollisionShape3D", true, false)
		if cols.is_empty():
			why += "沒有碰撞；"
		else:
			var sh := (cols[0] as CollisionShape3D).shape as ConvexPolygonShape3D
			if sh == null or sh.points.size() < 8:
				why += "碰撞凸包點數不足；"
			else:
				var worst := 0.0
				for p: Vector3 in sh.points:
					worst = maxf(worst, maxf(maxf(ab.position.x - p.x, p.x - ab.end.x), maxf(maxf(ab.position.y - p.y, p.y - ab.end.y), maxf(ab.position.z - p.z, p.z - ab.end.z))))
				if worst > 0.05:
					why += "碰撞點超出網格 %.2f m；" % worst
		var glb := "res://assets/beast_path/rocks/hero_rock_%s.glb" % form.trim_prefix("hero_")
		if String(h.get_meta("bp_hero_sha", "")) != FileAccess.get_sha256(glb):
			why += "GLB 雜湊與現檔不同；"
		if why != "":
			bad.append("%s：%s" % [h.name, why])
		else:
			var nat: AABB = RockBuilder.load_hero("hero_rock_" + form.trim_prefix("hero_"))["aabb"]
			info_parts.append("%s %s（原 %.1f×%.1f×%.1f→%.1f×%.1f×%.1f m，拉伸 %.2f/%.2f/%.2f；%d 頂點）" % [h.name, form, nat.size.x, nat.size.y, nat.size.z, ab.size.x, ab.size.y, ab.size.z,
				ab.size.x / nat.size.x, ab.size.y / nat.size.y, ab.size.z / nat.size.z, vv.size()])
	_gate("rocks.hero", heroes.size() >= 3 and forms.size() == 3 and bad.is_empty(),
		"Hero Rock 放置 %d 顆、形式 %s；尺寸＝預期 ±3%%、材質 bp_rock.tres、有頂點色與凸包碰撞、GLB 雜湊與現檔相同；問題：%s" % [heroes.size(), str(forms.keys()), str(bad)])
	for t in info_parts:
		_info("rocks.hero.detail", t)


## 崖頂上游：泉眼 → 蜿蜒淺河道 → 崖口 → 水幕
func _g_v12_falls() -> void:
	var A: Dictionary = lib.L["boss_arena"]
	var P: Dictionary = A["pool"]
	var wl := lib.water_y_at_stream("stream_trib", 0.0)
	_gate("falls.pool_unchanged", is_equal_approx(float(P["x"]), -8.0) and is_equal_approx(float(P["z"]), -431.0) and is_equal_approx(float(P["r"]), 5.0) \
		and is_equal_approx(float(A["waterfall"]["x"]), -8.0) and absf(wl - 12.35) < 0.01,
		"水潭位置 (%.0f,%.0f)、半徑 %.1f、水面 %.2f、瀑布 x=%.0f，與 V1.1 完全相同（使用者：保留現有水潭位置、尺度與碰撞）" % [float(P["x"]), float(P["z"]), float(P["r"]), wl, float(A["waterfall"]["x"])])
	if not lib.streams.has("stream_head"):
		_gate("falls.head_stream", false, "layout 沒有 stream_head（崖頂上游）")
		return
	var hs: BP.Poly = lib.streams["stream_head"]
	var wd := float(lib._stream_def("stream_head")["water_depth"])
	var bad_mono := 0
	for i in hs.bed.size() - 1:
		if hs.bed[i + 1] >= hs.bed[i]:
			bad_mono += 1
	var min_depth := 99.0
	var max_cut := -9.0
	var max_float := -9.0
	var max_float_s := 0.0
	var s := 0.5
	while s < hs.length - 1.5:
		var q: Vector2 = hs.pos_at(s)
		var tn: Vector2 = hs.tan_at(s)
		var rt := Vector2(-tn.y, tn.x)
		var bed: float = hs.bed_at(s)
		var wlev := bed + wd
		min_depth = minf(min_depth, wlev - lib.h_at(q.x, q.y))
		max_cut = maxf(max_cut, lib.h_at(q.x, q.y) - bed)
		var hw: float = hs.w_at(s) * 0.5 + 0.12
		for sg: float in [-1.0, 1.0]:
			var pe: Vector2 = q + rt * hw * 0.92 * sg
			var fl := wlev - lib.h_at(pe.x, pe.y)
			if fl > max_float:
				max_float = fl
				max_float_s = s
		s += 0.5
	var g: Dictionary = TG.waterfall_geom(lib)
	var end2: Vector2 = hs.pts[hs.pts.size() - 1]
	var lip_gap := absf(end2.y - float(g["z_top"]))
	var water_end := lib.water_y_at_stream("stream_head", hs.length)
	var wf := _find(inst, "Waterfall") as MeshInstance3D
	var top_y := -1e9
	for v: Vector3 in ((wf.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		top_y = maxf(top_y, v.y)
	var surfs := (wf.mesh as ArrayMesh).get_surface_count()
	var ok := bad_mono == 0 and hs.length >= 12.0 and min_depth >= 0.12 and max_cut <= 0.25 and max_float <= 0.40 and lip_gap <= 1.2 and absf(top_y - water_end) <= 0.06 and surfs == 2
	_gate("falls.head_stream", ok, "崖頂上游溪 %.1f m：床面逐點下降（違反 %d 處）、中央水深最小 %.2f m（≥ 0.12）、河道確實挖出（地形高於床最多 %.2f m，≤ 0.25）、水面高出岸緣最多 %.2f m @s=%.1f（≤ 0.40）、終點離崖口 %.2f m（≤ 1.2）、水幕頂端 %.2f ＝ 河道末端水面 %.2f（±0.06）、水幕 %d 層（要求 2）" % [
		hs.length, bad_mono, min_depth, max_cut, max_float, max_float_s, lip_gap, top_y, water_end, surfs])


## 潭岸石：落在實際岸線上、不擋落水點、朝戰場的可走側無碰撞
func _g_v12_shore() -> void:
	var holder := _find(inst, "PoolShore")
	if holder == null:
		_gate("pool.shore_stones", false, "找不到 PoolShore")
		return
	var P: Dictionary = lib.L["boss_arena"]["pool"]
	var pc := Vector2(float(P["x"]), float(P["z"]))
	var wl := lib.water_y_at_stream("stream_trib", 0.0)
	var g: Dictionary = TG.waterfall_geom(lib)
	var imp := Vector2(float(g["cx"]), float(g["fz"]))
	var n := 0
	var off_shore := 0
	var near_imp := 0
	var south_col := 0
	var worst := 0.0
	for st in holder.get_children():
		var n3 := st as Node3D
		if n3 == null:
			continue
		n += 1
		var p := Vector2(n3.global_position.x, n3.global_position.z)
		var dir := (p - pc).normalized()
		var rs := 2.5
		while rs < 9.5 and lib.h_at(pc.x + dir.x * rs, pc.y + dir.y * rs) < wl - 0.02:
			rs += 0.1
		var err := p.distance_to(pc) - rs
		worst = maxf(worst, absf(err))
		if err < -1.5 or err > 1.7:
			off_shore += 1
		if p.distance_to(imp) < 2.2:
			near_imp += 1
		var ang := rad_to_deg(atan2(dir.y, dir.x))
		if ang > 5.0 and ang < 175.0 and not n3.find_children("*", "CollisionShape3D", true, false).is_empty():
			south_col += 1
	_gate("pool.shore_stones", n >= 10 and off_shore == 0 and near_imp == 0 and south_col == 0,
		"潭岸石 %d 顆：離實際岸線最遠 %.2f m（要求 −1.5~+1.7 內，超出 %d 顆）、落水點 2.2 m 內 %d 顆、朝戰場可走側帶碰撞 %d 顆（要求 0）" % [n, worst, off_shore, near_imp, south_col])


## 草叢層：新鮮度、規劃一致、無碰撞、戰鬥圓不堆放、排除規則
func _g_v12_meadow() -> void:
	var ms := _find(inst, "MeadowS04")
	if ms == null:
		_gate("meadow.attached", false, "S04 沒有 MeadowS04（先跑 bake_meadow_s04.gd 再重生一次）")
		return
	var sha := FileAccess.get_sha256(MEADOW_INPUTS)
	var fresh := String(ms.get_meta("inputs_sha", "")) == sha
	var cols := ms.find_children("*", "CollisionObject3D", true, false)
	_gate("meadow.attached", fresh and cols.is_empty() and int(ms.get_meta("items", 0)) > 1000,
		"MeadowS04 掛載；烘焙時的岩／樹輸入雜湊 %s 現況（%s）；近級 %d 叢／中級 %d 叢；碰撞物件 %d 個（要求 0）" % ["＝" if fresh else "≠", sha.substr(0, 10), int(ms.get_meta("items", 0)), int(ms.get_meta("mid_items", 0)), cols.size()])
	var gf := FileAccess.open("user://beast_path_gctx.bin", FileAccess.READ)
	if gf == null:
		_gate("meadow.plan_matches", false, "沒有 user://beast_path_gctx.bin（先跑 generate_beast_path.gd）")
		return
	var ctx := {}
	for key: String in ["canopy", "rock_d"]:
		var cnt := gf.get_32()
		ctx[key] = gf.get_buffer(cnt * 4).to_float32_array()
	gf.close()
	var inp: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MEADOW_INPUTS))
	# V1.3：草叢凍結＝V1.2 時，「規劃」就是 adopt_frozen（與 bake_meadow_s04.gd 同一條路）；未凍結時才是 plan()
	var fzm: Dictionary = (lib.L["forest"] as Dictionary).get("freeze_s04_meadow", {})
	var M: Dictionary
	var how := "plan()"
	if not fzm.is_empty() and bool(fzm.get("enabled", true)):
		M = Meadow.adopt_frozen(lib, ctx, inp["feet"], inp["stems"], JSON.parse_string(FileAccess.get_file_as_string(String(fzm["file"]))))
		how = "V1.2 凍結 adopt_frozen()"
		_meadow_adopted = M
	else:
		M = Meadow.plan(lib, ctx, inp["feet"], inp["stems"])
	var n: int = M["n"]
	_gate("meadow.plan_matches", n == int(ms.get_meta("planned", -1)) and n == int(ms.get_meta("items", -2)),
		"以現在的岩／樹輸入重算（%s）%d 叢；烘焙時 %d 叢、場景近級 %d 叢（要求相同＝場景不是舊的）" % [how, n, int(ms.get_meta("planned", -1)), int(ms.get_meta("items", -2))])
	var c0 := lib.arena_c()
	var aP: PackedVector2Array = M["p"]
	var aK: PackedByteArray = M["k"]
	var core_n := 0
	var core_tall := 0
	var mid_ring := 0
	for i in n:
		var d := aP[i].distance_to(c0)
		if d < 14.0:
			core_n += 1
			if not (aK[i] == ML.K_SHORT or aK[i] == ML.K_SPARSE or aK[i] == ML.K_DRY):
				core_tall += 1
		if d >= 18.0 and d < 34.0:
			mid_ring += 1
	_gate("meadow.combat_open", core_n <= 40 and core_tall == 0 and mid_ring >= 800,
		"戰鬥圓（r < 14 m）內只有 %d 叢（≤ 40）、其中高草／羊歯 %d 叢（要求 0）；外圈（18~34 m）%d 叢（≥ 800，補足『外圈低矮草叢與蕨類』）" % [core_n, core_tall, mid_ring])
	var in_rock := 0
	var in_stem := 0
	var in_water := 0
	var too_steep := 0
	var feet: Array = inp["feet"]
	var stems: Array = inp["stems"]
	for i in n:
		var p := aP[i]
		for f: Dictionary in feet:
			if p.distance_to(Vector2(float(f["p"][0]), float(f["p"][1]))) - float(f["r"]) < -0.6 - 1e-3:
				in_rock += 1
				break
		for t: Array in stems:
			if p.distance_to(Vector2(float(t[0]), float(t[1]))) < float(t[2]) + 0.3 - 1e-3:
				in_stem += 1
				break
		if lib.sample_arr(lib.DS, p.x, p.y) < 0.5 - 1e-3:
			in_water += 1
		if lib.slope_deg_at(p.x, p.y) > 36.0 + 1e-3:
			too_steep += 1
	_gate("meadow.exclusions", in_rock + in_stem + in_water + too_steep == 0,
		"%d 叢中：長進岩腳 %d、長在樹幹圓內 %d、長進水裡 %d、長在 > 36° 陡坡 %d（要求全 0）" % [n, in_rock, in_stem, in_water, too_steep])
	_info("meadow.headless", "MultiMesh 的 instance 矩陣在 headless 下讀不到（全 0），不得當證據；零矩陣稽核在 bake_meadow_s04.gd 非 headless 烘焙後回讀完成（見 bake log『MMBAKE 回讀稽核』）")


## 陰影預算：只留「影子線段碰得到戰場」的樹影；低太陽的太陽側廊道全保留、背離太陽的一側才省、沒有太陽退回固定半徑；絕不動 S01–S03
func _g_v12_shadow_budget() -> void:
	var sb := _find(inst, "ShadowBudget")
	if sb == null:
		_gate("perf.shadow_budget", false, "S04 沒有 ShadowBudget 節點")
		return
	var s4n := _find(inst, "S04_BossClearing")
	var forest := s4n.get_node("Forest")                              # 注意：_find(inst, "Forest") 會先找到 S01 的
	var geoms: Array = sb.get("_geoms")
	var orig: PackedInt32Array = sb.get("_orig")
	var px: PackedFloat32Array = sb.get("_px")
	var pz: PackedFloat32Array = sb.get("_pz")
	var dist: PackedFloat32Array = sb.get("_dist")
	var hgt: PackedFloat32Array = sb.get("_hgt")
	var margin := float(sb.get("margin"))
	var rmin := float(sb.get("min_radius"))
	var rmax := float(sb.get("max_radius"))
	var fb := float(sb.get("fallback_radius"))
	var sk := float(sb.get("slope_k"))
	var c0: Vector2 = lib.arena_c()
	var bad: Array = []
	var OFF := int(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	if geoms.size() < 1000 or geoms.size() != orig.size() or geoms.size() != px.size():
		bad.append("預算腳本只收集到 %d 個幾何體" % geoms.size())
	# 0) 腳本記下的樹根位置／高度＝場景裡真正的值（逐棵對照）
	var idx := 0
	var pos_bad := 0
	for ch in forest.get_children():
		var c3 := ch as Node3D
		var gs := c3.find_children("*", "GeometryInstance3D", true, false)
		if gs.is_empty():
			continue
		if idx >= px.size() or absf(px[idx] - c3.global_position.x) > 0.01 or absf(pz[idx] - c3.global_position.z) > 0.01 \
				or absf(dist[idx] - Vector2(c3.global_position.x, c3.global_position.z).distance_to(c0)) > 0.01 or geoms[idx] != gs[0]:
			pos_bad += 1
		idx += gs.size()
	if pos_bad > 0 or idx != geoms.size():
		bad.append("%d 棵樹的記錄位置與場景不符（共收 %d／場景 %d 個幾何體）" % [pos_bad, geoms.size(), idx])
	# 1) 沒有太陽（verify 只載入單張地圖）→ 固定半徑 fallback
	sb.call("apply", true)
	var wrong := 0
	for i in geoms.size():
		var want := orig[i] if dist[i] <= fb else OFF
		if int((geoms[i] as GeometryInstance3D).cast_shadow) != want:
			wrong += 1
	if wrong > 0:
		bad.append("沒有太陽時 %d 個幾何體的投影狀態不對（應為半徑 %.0f m 內維持原值、之外關閉）" % [wrong, fb])
	# 2) 放一顆太陽：10:00＝68.4°、13:00＝75.5°、07:00／17:00＝24.6°；方位東／西各一
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_energy = 1.35
	root.add_child(sun)
	var res := {}
	var scen := [[68.4, 100.0], [75.5, 100.0], [24.6, 100.0], [24.6, 280.0], [68.4, 100.0]]
	for sc: Array in scen:
		var e: float = sc[0]
		var yaw: float = sc[1]
		sun.rotation = Vector3(-deg_to_rad(e), deg_to_rad(yaw), 0.0)
		sb.call("apply", true)
		var zb := sun.global_transform.basis.z
		var tdir := Vector2(-zb.x, -zb.z).normalized()
		var tan_e := tan(deg_to_rad(e))
		var off := 0
		var viol := 0
		var miss := 0
		for i in geoms.size():
			var p := Vector2(px[i], pz[i])
			var keep: bool
			if dist[i] <= rmin:
				keep = true
			elif dist[i] > rmax:
				keep = false
			else:
				var ab := tdir * (hgt[i] / tan_e * sk)
				var t := clampf((c0 - p).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
				keep = (p + ab * t).distance_to(c0) <= margin
			var cs := int((geoms[i] as GeometryInstance3D).cast_shadow)
			var want2 := orig[i] if keep else OFF
			if cs != want2:
				viol += 1
			if cs == OFF and orig[i] != OFF:
				off += 1
				# 物理檢查（不含安全係數）：被關的樹，真實的影子線段不得進入戰場圓
				var ab0 := tdir * (hgt[i] / tan_e)
				var t0 := clampf((c0 - p).dot(ab0) / maxf(ab0.length_squared(), 1e-6), 0.0, 1.0)
				if (p + ab0 * t0).distance_to(c0) < margin - 0.01:
					miss += 1
		res["%.1f°/%d°" % [e, int(yaw)] + ("'" if res.has("%.1f°/%d°" % [e, int(yaw)]) else "")] = "%d/%d" % [off, geoms.size()]
		if viol > 0:
			bad.append("仰角 %.1f° 方位 %d°：%d 個幾何體的狀態不符規則" % [e, int(yaw), viol])
		if miss > 0:
			bad.append("仰角 %.1f° 方位 %d°：%d 棵被關的樹其真實影子進入戰場圓" % [e, int(yaw), miss])
	sun.free()
	# 3) 低太陽時保留的比高太陽多（太陽側廊道），兩個方位的廊道不同
	var hi := int(str(res["68.4°/100°"]).split("/")[0])
	var lo_e := int(str(res["24.6°/100°"]).split("/")[0])
	var lo_w := int(str(res["24.6°/280°"]).split("/")[0])
	if not (lo_e < hi and lo_w < hi):
		bad.append("低太陽應比高太陽關得少（高 %d／低東 %d／低西 %d）" % [hi, lo_e, lo_w])
	if lo_e == lo_w:
		bad.append("兩個方位的結果相同（廊道沒有隨方位改變）")
	# 4) S01–S03 不碰：ShadowBudget 掛在 S04 場景根，只處理同場景的 Forest
	if sb.get_parent() != s4n:
		bad.append("ShadowBudget 的父節點不是 S04_BossClearing")
	var n_sb := 0
	for nd in inst.find_children("ShadowBudget", "", true, false):
		n_sb += 1
	if n_sb != 1:
		bad.append("ShadowBudget 節點共 %d 個（要求只有 S04 的 1 個）" % n_sb)
	_gate("perf.shadow_budget", bad.is_empty(), "樹影依太陽仰角＋方位收放（被關的幾何體／總數）：%s；沒有太陽時退回 %.0f m；違規：%s" % [str(res), fb, str(bad.slice(0, 4))])


# ================================================================= V1.3（局部美術修正：崖頂水源／崖口、北崖連續性、S04 森林凍結、大氣）
func _g_v13() -> void:
	_g_v13_head()
	_g_v13_face_rocks()
	_g_v13_forest_s04()
	_g_v13_meadow_s04()
	_g_v13_pool_shore()
	_g_v13_atmosphere()


## 潭岸石＝V1.2 原樣：Props/PoolShore 的每顆石頭 transform／半徑與凍結檔（V1.2 備份場景的值）逐值相同、網格檔 sha256 相同
func _g_v13_pool_shore() -> void:
	var fz: Dictionary = lib.L.get("freeze_s04_pool_shore", {})
	if fz.is_empty():
		_gate("pool.shore_v12_kept", false, "layout.freeze_s04_pool_shore 不存在")
		return
	var path := String(fz["file"])
	var sha_ok := FileAccess.get_sha256(path) == String(fz["sha256"])
	var F: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var s04 := _find(inst, "S04_BossClearing")
	var holder := _find(s04, "PoolShore") if s04 != null else null
	var by_id := {}
	for e: Dictionary in F["stones"]:
		by_id[String(e["id"])] = e
	var same := 0
	var mesh_same := 0
	var bad: Array = []
	var seen := 0
	if holder != null:
		for c in holder.get_children():
			var n3 := c as Node3D
			if n3 == null or not by_id.has(String(n3.name)):
				bad.append(String(c.name) + "（凍結檔沒有）")
				continue
			seen += 1
			var e2: Dictionary = by_id[String(n3.name)]
			# 凍結值取自 V1.2 場景文字（7 位有效數字）；場景載入後是 float32 → 先轉 float32 再比（與 meadow 的比較同理，避免 1 ulp 誤報）
			var xf := PackedFloat32Array(e2["xf"] as Array)
			var t := n3.transform
			var cur := [t.basis.x.x, t.basis.y.x, t.basis.z.x, t.basis.x.y, t.basis.y.y, t.basis.z.y, t.basis.x.z, t.basis.y.z, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]
			var d := 0.0
			for k in 12:
				d = maxf(d, absf(float(cur[k]) - float(xf[k])))
			var dr := absf(float(n3.get_meta("bp_rock_r", -1.0)) - float(e2["r"]))
			if d <= 1e-6 and dr <= 1e-6:
				same += 1
			else:
				bad.append("%s（transform 差 %.6f、半徑差 %.6f）" % [n3.name, d, dr])
			if FileAccess.get_sha256("res://maps/beast_path/gen/rocks/%s.res" % n3.name) == String(e2["mesh_sha256"]):
				mesh_same += 1
	var n := int(F["n"])
	_gate("pool.shore_v12_kept", sha_ok and holder != null and seen == n and same == n and bad.is_empty(),
		"潭岸石 %d 顆（凍結檔＝V1.2 %d 顆、雜湊 %s）：transform／半徑與 V1.2 逐值相同 %d；網格檔 sha256 與 V1.2 相同 %d；不同：%s" % [
		seen, n, "吻合" if sha_ok else "不符", same, mesh_same, str(bad.slice(0, 6))])


## S04 草叢＝V1.2 凍結：凍結檔雜湊、掛載的 MeadowS04 帶同一份凍結 meta、剔除／重新落地只出現在 V1.3 修改區、不新增
##   （headless 讀不到 MultiMesh 矩陣 → 用 _g_v12_meadow 以 adopt_frozen 重算的結果；它和 bake 走同一條路）
func _g_v13_meadow_s04() -> void:
	var fz: Dictionary = (lib.L["forest"] as Dictionary).get("freeze_s04_meadow", {})
	if fz.is_empty() or not bool(fz.get("enabled", true)) or _meadow_adopted.is_empty():
		_gate("meadow.s04_v12_kept", false, "layout.forest.freeze_s04_meadow 未啟用，或 _g_v12_meadow 沒有算出凍結採用結果")
		return
	var path := String(fz["file"])
	var sha_ok := FileAccess.get_sha256(path) == String(fz["sha256"])
	var F: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var ms := _find(inst, "MeadowS04")
	var st: Dictionary = _meadow_adopted["stats"]
	var meta_ok := ms != null and String(ms.get_meta("frozen_sha", "")) == String(fz["sha256"]) and int(ms.get_meta("frozen_n", -1)) == int(F["n"]) \
		and int(ms.get_meta("frozen_dropped", -1)) == int(st["dropped_n"]) and int(ms.get_meta("frozen_reground", -1)) == int(st["reground_n"])
	var outside: Array = []
	for d: Dictionary in (st["dropped"] as Array) + (st["reground"] as Array):
		if not (float(d["z"]) < -436.0 and float(d["x"]) > -62.0 and float(d["x"]) < 40.0):
			outside.append(d)
	# 保留下來的每一叢都必須是凍結檔裡的那一叢（位置／種類／尺度／方向逐值相同；y 只容許重新落地的那些）
	#   比較在 float32 進行：場景與規劃陣列都是 float32，JSON 讀回的 float64 可能差 1 ulp（Godot 的字串轉浮點不保證正確捨入）
	var aP: PackedVector2Array = _meadow_adopted["p"]
	var order: PackedInt32Array = _meadow_adopted["order"]
	var not_same := 0
	for q in int(_meadow_adopted["n"]):
		var i := order[q]
		var fp: Array = F["p"][i]
		var f32 := PackedFloat32Array([float(F["yaw"][i]), float(F["s"][i]), float(F["w"][i])])
		if aP[q] != Vector2(float(fp[0]), float(fp[1])) or (_meadow_adopted["k"] as PackedByteArray)[q] != int(F["k"][i]) \
				or (_meadow_adopted["yaw"] as PackedFloat32Array)[q] != f32[0] or (_meadow_adopted["s"] as PackedFloat32Array)[q] != f32[1] \
				or (_meadow_adopted["w"] as PackedFloat32Array)[q] != f32[2]:
			not_same += 1
	_gate("meadow.s04_v12_kept", sha_ok and meta_ok and outside.is_empty() and not_same == 0 and int(st["dropped_n"]) <= 40,
		"S04 草叢＝V1.2 凍結（%d 叢、雜湊 %s）：原樣 %d、重新落地 %d、剔除 %d %s、新增 0；保留的叢與凍結檔逐值不同的 %d（要求 0）；掛載 MeadowS04 的凍結 meta %s；剔除／落地在 V1.3 修改區外的 %d（要求 0）；為維持中級 LOD 的 index 而搬位 %d" % [
		int(F["n"]), "吻合" if sha_ok else "不符", int(st["kept"]) - int(st["reground_n"]), int(st["reground_n"]), int(st["dropped_n"]), str(st["why"]), not_same,
		"一致" if meta_ok else "不一致", outside.size(), int(st["moved_for_mid"])])


## 崖頂上游：岸要高出水面（V1.2 的水像一張平鋪的膜）、往崖口收窄（V1.2 越近崖口越寬）、河道停在崖口並由水幕接著翻落（V1.2 懸空 1.3 m）
func _g_v13_head() -> void:
	if not lib.streams.has("stream_head"):
		_gate("falls.head_banks", false, "layout 沒有 stream_head")
		return
	var hs: BP.Poly = lib.streams["stream_head"]
	var wd := float(lib._stream_def("stream_head")["water_depth"])
	# (a) 岸頂：河道邊（u＝1）與再往外 0.6 m 的地形高出水面多少
	var n := 0
	var low_edge := 0
	var low_out := 0
	var min_edge := 99.0
	var min_edge_s := 0.0
	var min_out := 99.0
	var sum_edge := 0.0
	var s := 0.5
	while s <= hs.length - 1.2:
		var q: Vector2 = hs.pos_at(s)
		var tn: Vector2 = hs.tan_at(s)
		var rt := Vector2(-tn.y, tn.x)
		var wl: float = hs.bed_at(s) + wd
		var hw: float = hs.w_at(s) * 0.5
		for sg: float in [-1.0, 1.0]:
			var pe: Vector2 = q + rt * hw * sg
			var po: Vector2 = q + rt * (hw + 0.6) * sg
			var e1 := lib.h_at(pe.x, pe.y) - wl
			var e2 := lib.h_at(po.x, po.y) - wl
			n += 1
			sum_edge += e1
			if e1 < 0.05:
				low_edge += 1
			if e2 < 0.12:
				low_out += 1
			if e1 < min_edge:
				min_edge = e1
				min_edge_s = s
			min_out = minf(min_out, e2)
		s += 0.5
	_gate("falls.head_banks", low_edge == 0 and low_out <= maxi(n / 20, 1),
		"崖頂河道 %d 個岸點（s 0.5–%.1f m、兩岸）：河道邊地形高出水面 最低 %.2f m @s=%.1f、平均 %.2f m（要求全部 ≥ 0.05；V1.2 為水面高出岸 0.29 m）；岸外 0.6 m 最低 %.2f m（< 0.12 的 %d 點，容許 %d）" % [
		n, hs.length - 1.2, min_edge, min_edge_s, sum_edge / float(maxi(n, 1)), min_out, low_out, maxi(n / 20, 1)])
	# (b) 往崖口收窄
	var w_end: float = hs.w[hs.w.size() - 1]
	var w_max := 0.0
	for i in hs.w.size():
		if hs.s[i] >= hs.length * 0.4:
			w_max = maxf(w_max, hs.w[i])
	_gate("falls.lip_narrowing", w_end <= w_max * 0.8,
		"崖口河寬 %.2f m／下游段最寬 %.2f m ＝ %.2f（要求 ≤ 0.80；V1.2：4.6／4.6＝1.00，越近崖口越寬）" % [w_end, w_max, w_end / maxf(w_max, 0.01)])
	# (c) 崖口銜接：河道末端不懸空、水幕頂列就在河道末端那條水線上、翻落段往崖外單調
	var end2: Vector2 = hs.pts[hs.pts.size() - 1]
	var water_end := lib.water_y_at_stream("stream_head", hs.length)
	var overhang := water_end - lib.h_at(end2.x, end2.y)
	var g: Dictionary = TG.waterfall_geom(lib)
	var e_r := BP.right_of(hs.tan_at(hs.length))
	if e_r.x < 0.0:
		e_r = -e_r
	var w_top := float(g["w_top"])
	var wf := _find(inst, "Waterfall") as MeshInstance3D
	var arr := (wf.mesh as ArrayMesh).surface_get_arrays(0)
	var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var top_bad := 0
	var top_n := 0
	var top_dmax := 0.0
	var col_z := {}
	for i in vv.size():
		var v := vv[i]
		if uv[i].y < 1e-4:
			top_n += 1
			var a := end2 - e_r * w_top * 0.5
			var b := end2 + e_r * w_top * 0.5
			var pxz := Vector2(v.x, v.z)
			var t := clampf((pxz - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
			var dxz := pxz.distance_to(a + (b - a) * t)
			top_dmax = maxf(top_dmax, dxz)
			if dxz > 0.2 or absf(v.y - water_end) > 0.06:
				top_bad += 1
		if v.y > water_end - TG.BRINK_H - 0.01:
			var cx := snappedf(uv[i].x, 0.001)
			if not col_z.has(cx):
				col_z[cx] = []
			(col_z[cx] as Array).append(Vector2(v.y, v.z))
	var nonmono := 0
	for cx2 in col_z:
		var lst: Array = col_z[cx2]
		lst.sort_custom(func(p: Vector2, q2: Vector2) -> bool: return p.x > q2.x)       # 由上往下
		for k in range(1, lst.size()):
			if (lst[k] as Vector2).y < (lst[k - 1] as Vector2).y - 0.02:                  # z 變小＝往崖內縮回
				nonmono += 1
	_gate("falls.lip_join", overhang <= 0.35 and top_n >= 13 and top_bad == 0 and nonmono == 0,
		"河道末端水面離地 %.2f m（≤ 0.35；V1.2 為 1.28 m 懸空）；水幕頂列 %d 點全在河道末端水線上（偏離 > 0.2 m 或高差 > 0.06 m 的 %d 點，最遠 %.2f m）；翻落段（頂端 %.1f m）往崖內縮回的 %d 處（要求 0）" % [
		overhang, top_n, top_bad, top_dmax, TG.BRINK_H, nonmono])


## 北崖崖面岩塊：嵌進崖裡（不是浮在崖前、也不是整顆埋掉）、沒有碰撞、不壓到水幕
func _g_v13_face_rocks() -> void:
	var want := (lib.L["boss_arena"].get("cliff_face", []) as Array).size()
	var rocks: Array = []
	for nd in inst.find_children("*", "Node3D", true, false):
		if nd.has_meta("bp_face_rock"):
			rocks.append(nd)
	var wf := _find(inst, "Waterfall") as MeshInstance3D
	var cv := PackedVector3Array()
	for sj in (wf.mesh as ArrayMesh).get_surface_count():
		cv.append_array((wf.mesh as ArrayMesh).surface_get_arrays(sj)[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	var bad: Array = []
	var fr_min := 1.0
	var fr_max := 0.0
	var clear_min := 99.0
	var tri := 0
	for r: Node3D in rocks:
		var mi: MeshInstance3D = null
		for c in r.get_children():
			if c is MeshInstance3D:
				mi = c
		if mi == null:
			bad.append("%s 沒有網格" % r.name)
			continue
		var pts: PackedVector3Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		tri += (mi.mesh as ArrayMesh).surface_get_array_index_len(0) / 3
		var xf := mi.global_transform
		var inside := 0
		for p: Vector3 in pts:
			var w := xf * p
			if w.y < lib.h_at(w.x, w.z):
				inside += 1
		var fr := float(inside) / float(maxi(pts.size(), 1))
		fr_min = minf(fr_min, fr)
		fr_max = maxf(fr_max, fr)
		if fr < 0.2 or fr > 0.85:
			bad.append("%s 埋入比例 %.2f" % [r.name, fr])
		if not r.find_children("*", "CollisionShape3D", true, false).is_empty():
			bad.append("%s 有碰撞" % r.name)
		var mat := (mi.mesh as ArrayMesh).surface_get_material(0)
		if mat == null or not String(mat.resource_path).ends_with("bp_rock.tres"):
			bad.append("%s 材質不是 bp_rock" % r.name)
		var bb: AABB = r.get_meta("bp_face_aabb", AABB())
		for v: Vector3 in cv:
			var dx := maxf(maxf(bb.position.x - v.x, v.x - bb.end.x), 0.0)
			var dy := maxf(maxf(bb.position.y - v.y, v.y - bb.end.y), 0.0)
			var dz := maxf(maxf(bb.position.z - v.z, v.z - bb.end.z), 0.0)
			clear_min = minf(clear_min, Vector3(dx, dy, dz).length())
	if clear_min < 0.25:
		bad.append("水幕離崖面岩塊最近 %.2f m（< 0.25）" % clear_min)
	_gate("cliff.face_rocks", rocks.size() == want and want > 0 and bad.is_empty(),
		"北崖崖面岩塊 %d 顆（layout %d）；埋進崖裡的頂點比例 %.0f–%.0f%%（要求 20–85）；無碰撞；材質 bp_rock；水幕離岩塊外框最近 %.2f m（≥ 0.25）；共 %d 三角形；問題：%s" % [
		rocks.size(), want, fr_min * 100.0, fr_max * 100.0, clear_min, tri, str(bad.slice(0, 5))])


## S04 森林＝V1.2 凍結：場景裡每棵樹與凍結檔逐棵比對（transform 逐位元相同；只容許 V1.3 局部修改附近的重新落地／剔除）
func _g_v13_forest_s04() -> void:
	var fz: Dictionary = (lib.L["forest"] as Dictionary).get("freeze_s04", {})
	if fz.is_empty() or not bool(fz.get("enabled", true)):
		_gate("forest.s04_v12_kept", false, "layout.forest.freeze_s04 未啟用")
		return
	var path := String(fz["file"])
	var sha_ok := FileAccess.get_sha256(path) == String(fz["sha256"])
	var src: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var ents: Array = src["scenes"]["S04"]
	var by_key := {}
	for e: Dictionary in ents:
		var xf: Array = e["xf"]
		by_key["%s@%.2f,%.2f" % [String(e["id"]), float(xf[9]), float(xf[11])]] = xf
	var forest := _find(_find(inst, "S04_BossClearing"), "Forest")
	var same := 0
	var y_only: Array = []
	var extra: Array = []
	var matched := {}
	for c in forest.get_children():
		var n3 := c as Node3D
		var nm := String(n3.name)
		var id := nm.substr(0, nm.rfind("_"))
		var o := n3.transform.origin
		var key := "%s@%.2f,%.2f" % [id, o.x, o.z]
		if not by_key.has(key):
			extra.append(key)
			continue
		matched[key] = true
		var m: Array = by_key[key]
		var b := n3.transform.basis
		var db := 0.0
		for k in 9:
			var bv: float = [b.x.x, b.y.x, b.z.x, b.x.y, b.y.y, b.z.y, b.x.z, b.y.z, b.z.z][k]
			db = maxf(db, absf(bv - float(m[k])))
		var dxz := maxf(absf(o.x - float(m[9])), absf(o.z - float(m[11])))
		var dy := o.y - float(m[10])
		if db <= 1e-5 and dxz <= 1e-5 and absf(dy) <= 1e-5:
			same += 1
		elif db <= 1e-5 and dxz <= 1e-5:
			y_only.append({"k": key, "dy": snappedf(dy, 0.001)})
		else:
			extra.append(key + "（transform 不同）")
	var dropped: Array = []
	for k2 in by_key:
		if not matched.has(k2):
			dropped.append(k2)
	# 改動只准出現在 V1.3 的修改區（北崖／崖頂：z < −436，x −62..40）
	var outside: Array = []
	for k3 in dropped + y_only.map(func(d: Dictionary) -> String: return String(d["k"])):
		var xz := String(k3).split("@")[1].split(",")
		if not (float(xz[1]) < -436.0 and float(xz[0]) > -62.0 and float(xz[0]) < 40.0):
			outside.append(k3)
	_gate("forest.s04_v12_kept", sha_ok and extra.is_empty() and outside.is_empty() and dropped.size() <= 10 and y_only.size() <= 10,
		"S04 植被 %d 棵（凍結檔＝V1.2 %d 棵、雜湊 %s）：transform 與 V1.2 逐位元相同 %d、只重新落地 %d %s、剔除 %d %s、凍結檔沒有的 %d；改動在 V1.3 修改區外的 %d（要求 0）" % [
		forest.get_child_count(), ents.size(), "吻合" if sha_ok else "不符", same, y_only.size(), str(y_only), dropped.size(), str(dropped), extra.size(), outside.size()])


## 大氣：beast_path 根節點下有且只有一個 BP_Atmosphere（WorldEnvironment＋bp_atmosphere.gd），值＝layout；地圖不帶自己的太陽（main 的 Sun／ShadowBudget 照舊）
func _g_v13_atmosphere() -> void:
	var cfg: Dictionary = lib.L.get("atmosphere", {})
	var envs := inst.find_children("*", "WorldEnvironment", true, false)
	var suns := inst.find_children("*", "DirectionalLight3D", true, false)
	var atm := _find(inst, "BP_Atmosphere") as WorldEnvironment
	var bz: Array = cfg.get("blend_z", [-340.0, -366.0])
	var dk: Array = cfg.get("day_k", [0.40, 0.85])
	var ok := atm != null and envs.size() == 1 and suns.is_empty() and atm.get_script() != null \
		and String((atm.get_script() as Script).resource_path).ends_with("bp_atmosphere.gd") \
		and is_equal_approx(float(atm.get("fog_sky_affect")), float(cfg.get("fog_sky_affect", -1.0))) \
		and is_equal_approx(float(atm.get("fog_aerial_perspective")), float(cfg.get("fog_aerial_perspective", -1.0))) \
		and is_equal_approx(float(atm.get("blend_z0")), float(bz[0])) and is_equal_approx(float(atm.get("blend_z1")), float(bz[1])) \
		and is_equal_approx(float(atm.get("day_k0")), float(dk[0])) and is_equal_approx(float(atm.get("day_k1")), float(dk[1])) \
		and (String(cfg.get("scope", "S04")) != "S04" or float(bz[0]) <= -340.0 + 0.01)
	_gate("sky.atmosphere", ok, "BP_Atmosphere：%s；地圖內 WorldEnvironment %d 個（要求 1）、DirectionalLight3D %d 個（要求 0）；fog_sky_affect %s（layout %s）、fog_aerial_perspective %s（layout %s）；只在 S04：相機 z %s → %s 淡入（S03 南界 −340 以北＝main 原值）；只在日高：日照係數 k %s → %s 淡入（07:00／17:00＝main 原值）；霧密度／霧色沿用 main（執行期複製）" % [
		"有" if atm != null else "沒有", envs.size(), suns.size(), str(atm.get("fog_sky_affect")) if atm else "-", str(cfg.get("fog_sky_affect")),
		str(atm.get("fog_aerial_perspective")) if atm else "-", str(cfg.get("fog_aerial_perspective")), str(atm.get("blend_z0")) if atm else "-", str(atm.get("blend_z1")) if atm else "-",
		str(atm.get("day_k0")) if atm else "-", str(atm.get("day_k1")) if atm else "-"])
