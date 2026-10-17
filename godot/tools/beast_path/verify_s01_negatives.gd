extends "res://tools/beast_path/verify_beast_path.gd"
## S01 R1／R2 Gate 反向測試：證明『不連動』與『凍結』類 Gate 真的會 FAIL，而不是無條件 PASS。
## R2（2026-10-16）：加上谷壁點綴、釘點櫻位移、總量 380 的 Gate 各自的對照與竄改（N27–N37；只在 S01 候選 mode＝r2 時跑）。
##
## 做法：沿用正式 verifier 的全部程式（本檔 extends verify_beast_path.gd），在『記憶體裡』對基準清單／layout／規劃／場景實例動手腳，
## 再呼叫同一個 Gate 函式，確認它回報 FAIL；每組 Gate 另有一個『不動手腳』的對照（必須 PASS），證明 FAIL 不是環境本身壞掉。
## 完全不寫任何 live 檔案（執行前後以 sha256 對照）。
##   godot --headless --path godot --script res://tools/beast_path/verify_s01_negatives.gd [-- --out=<json>]
const S01GatesScript := preload("res://tools/beast_path/verify_s01_gates.gd")

var neg: Array = []
var _L0: Dictionary = {}
var _g: RefCounted


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.trim_prefix("--out=")
	_go.call_deferred()


# 內部 Gate 的輸出不印、只收（避免把被動過手腳的 FAIL 誤當成真失敗）
func _gate(name: String, ok: bool, detail: String) -> void:
	results.append({"gate": name, "ok": ok, "detail": detail})


func _info(name: String, detail: String) -> void:
	results.append({"gate": name, "ok": true, "info": true, "detail": detail})


func _restore_layout() -> void:
	lib.L = _L0.duplicate(true)


func _case(id: String, gate: String, expect_fail: bool, what: String, runner: Callable) -> void:
	results.clear()
	runner.call()
	var found := false
	var ok_val := true
	var det := ""
	for r: Dictionary in results:
		if String(r["gate"]) == gate:
			found = true
			ok_val = bool(r["ok"])
			det = String(r["detail"])
	var good: bool = found and ((not ok_val) if expect_fail else ok_val)
	neg.append({"id": id, "gate": gate, "expect": "FAIL" if expect_fail else "PASS", "got": ("PASS" if ok_val else "FAIL") if found else "（Gate 沒有輸出）", "ok": good, "what": what, "detail": det.substr(0, 400)})
	print("[%s] %-6s %-34s 預期 %s／實際 %s  ← %s" % ["PASS" if good else "FAIL", id, gate, "FAIL" if expect_fail else "PASS", ("PASS" if ok_val else "FAIL") if found else "—", what])
	results.clear()
	_restore_layout()


func _forest_of(sc: String) -> Node:
	for f in inst.find_children("Forest", "Node3D", true, false):
		if String((f as Node).get_parent().get_meta("bp_scene", "")) == sc:
			return f
	return null


func _flip(h: String) -> String:
	return ("0" if h.substr(0, 1) != "0" else "1") + h.substr(1)


func _first_key(d: Dictionary, needle: String) -> String:
	for k: String in d:
		if k.contains(needle):
			return k
	return ""


func _man() -> Dictionary:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(S01GatesScript.MANIFEST))
	return (j as Dictionary).duplicate(true)


func _digest_base() -> Dictionary:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(S01GatesScript.LAYOUT_DIGEST))
	return (j as Dictionary).duplicate(true)


func _plan_all() -> Array:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://maps/beast_path/gen/forest_plan.json"))
	return ((j as Dictionary)["trees"] as Array).duplicate(true)


func _go() -> void:
	lib = BP.new()
	lib.setup(true, true)
	_L0 = lib.L.duplicate(true)
	var ps := ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	inst = ps.instantiate()
	root.add_child(inst)
	for i in 4:
		await physics_frame
	space = root.world_3d.direct_space_state
	_g = S01GatesScript.new()
	_g.v = self
	_g.lib = lib
	_g.inst = inst
	var g: RefCounted = _g

	# ============================================================ 對照組：不動手腳，必須 PASS
	_case("C0.a", "isolation.protected_files", false, "對照：未動手腳", func(): g._g_isolation_files())
	_case("C0.b", "isolation.layout_other_zones", false, "對照：未動手腳", func(): g._g_isolation_layout())
	_case("C0.c", "isolation.s01_terrain_locked", false, "對照：未動手腳", func(): g._g_s01_terrain_locked())
	for gn: String in ["forest.freeze_file", "forest.frozen_plan_equal", "forest.frozen_scene_equal", "forest.zone_independent"]:
		_case("C0.d", gn, false, "對照：未動手腳", func(): _g_forest_freeze())
	for gn2: String in ["s01.candidate_declared", "s01.candidate_reproducible", "s01.scene_equals_plan", "s01.lean_semantics", "s01.count_budget"]:
		_case("C0.e", gn2, false, "對照：未動手腳", func(): g._g_s01_candidate())

	# ============================================================ isolation.protected_files（基準檔／場景／S04 共用 shader）
	var m: Dictionary = _man()
	var k_s03: String = _first_key(m["raw"], "s03_")
	var k_shd := "assets/beast_path/materials/bp_ground.gdshader"
	var k_tres := "assets/beast_path/materials/bp_ground.tres"
	_case("N1", "isolation.protected_files", true, "基準清單裡一個 S03 檔（%s）的雜湊被改" % k_s03, func():
		var mm: Dictionary = _man()
		mm["raw"][k_s03] = _flip(String(mm["raw"][k_s03]))
		g.man_override = mm
		g._g_isolation_files()
		g.man_override = {})
	_case("N2", "isolation.protected_files", true, "S04 共用的 bp_ground.gdshader 雜湊被改（＝有人動了共用 shader）", func():
		var mm: Dictionary = _man()
		mm["raw"][k_shd] = _flip(String(mm["raw"][k_shd]))
		g.man_override = mm
		g._g_isolation_files()
		g.man_override = {})
	_case("N3", "isolation.protected_files", true, "基準清單少了 bp_ground.tres（共用材質不再被保護）", func():
		var mm: Dictionary = _man()
		(mm["raw"] as Dictionary).erase(k_tres)
		g.man_override = mm
		g._g_isolation_files()
		g.man_override = {})
	var k_s04sc: String = _first_key(m["scene_norm"], "s04_boss")
	_case("N4", "isolation.protected_files", true, "S04 場景（%s）的 raw 與正規化雜湊都被改" % k_s04sc, func():
		var mm: Dictionary = _man()
		mm["scene_norm"][k_s04sc]["raw"] = _flip(String(mm["scene_norm"][k_s04sc]["raw"]))
		mm["scene_norm"][k_s04sc]["norm"] = _flip(String(mm["scene_norm"][k_s04sc]["norm"]))
		g.man_override = mm
		g._g_isolation_files()
		g.man_override = {})
	var k_s02sc: String = _first_key(m["scene_norm"], "s02_")
	_case("N5", "isolation.protected_files", true, "S02 場景（%s）的 raw 與正規化雜湊都被改" % k_s02sc, func():
		var mm: Dictionary = _man()
		mm["scene_norm"][k_s02sc]["raw"] = _flip(String(mm["scene_norm"][k_s02sc]["raw"]))
		mm["scene_norm"][k_s02sc]["norm"] = _flip(String(mm["scene_norm"][k_s02sc]["norm"]))
		g.man_override = mm
		g._g_isolation_files()
		g.man_override = {})

	# ============================================================ isolation.layout_other_zones
	var non_s01: Array = []
	for i2 in (lib.L["pois"] as Array).size():
		var poi: Dictionary = lib.L["pois"][i2]
		if poi.has("id") and S01GatesScript.poi_scene(poi, lib) != "S01":
			non_s01.append(i2)
	_case("N6", "isolation.layout_other_zones", true, "一個非 S01 的 POI（%s）多了一個欄位" % String(lib.L["pois"][non_s01[0]]["id"]), func():
		(lib.L["pois"][non_s01[0]] as Dictionary)["_tamper"] = 1
		g._g_isolation_layout())
	var topk := ""
	for k3: String in lib.L:
		if k3 != "pois" and k3 != "forest" and k3 != "s01_ground":
			topk = k3
			break
	_case("N7", "isolation.layout_other_zones", true, "全域設定 '%s' 被改" % topk, func():
		var cur: Variant = lib.L[topk]
		if cur is Dictionary:
			(cur as Dictionary)["_tamper"] = 1
		else:
			lib.L[topk] = [cur, "_tamper"]
		g._g_isolation_layout())
	_case("N8", "isolation.layout_other_zones", true, "forest.clearings（S02–S04 共用的林中空地）多一塊", func():
		((lib.L["forest"] as Dictionary)["clearings"] as Array).append({"id": "_neg", "c": [0.0, -300.0], "r": 5.0})
		g._g_isolation_layout())
	_case("N9", "isolation.layout_other_zones", true, "在 S04 區新增一個 POI（S01 以外不准新增）", func():
		var np: Dictionary = (lib.L["pois"][non_s01[non_s01.size() - 1]] as Dictionary).duplicate(true)
		np["id"] = "_neg_new_poi"
		(lib.L["pois"] as Array).append(np)
		g._g_isolation_layout())
	_case("N10", "isolation.layout_other_zones", true, "兩個非 S01 的 POI 順序對調（props 共用亂數序列會位移）", func():
		var arr: Array = lib.L["pois"]
		var ia: int = non_s01[0]
		var ib: int = non_s01[1]
		var tmp: Variant = arr[ia]
		arr[ia] = arr[ib]
		arr[ib] = tmp
		g._g_isolation_layout())
	_case("N11", "isolation.layout_other_zones", false, "（容許）S01 自己的柵欄 POI 被改——這是授權範圍，必須仍 PASS", func():
		for p: Dictionary in lib.L["pois"]:
			if String(p.get("id", "")) == "fence_village_L":
				(p["at"] as Dictionary)["ds1"] = 14.0
		g._g_isolation_layout())

	# ============================================================ isolation.s01_terrain_locked
	_case("N12", "isolation.s01_terrain_locked", true, "S01 地形網格的幾何雜湊（頂點＋法線＋索引）被改", func():
		var mm: Dictionary = _man()
		mm["s01_locked"]["terrain_geom_sha"] = _flip(String(mm["s01_locked"]["terrain_geom_sha"]))
		g.man_override = mm
		g._g_s01_terrain_locked()
		g.man_override = {})
	_case("N13", "isolation.s01_terrain_locked", true, "S01 地形碰撞檔的雜湊被改", func():
		var mm: Dictionary = _man()
		var sk: String = _first_key(mm["s01_locked"], "s01_terrain_shape")
		mm["s01_locked"][sk] = _flip(String(mm["s01_locked"][sk]))
		g.man_override = mm
		g._g_s01_terrain_locked()
		g.man_override = {})

	# ============================================================ 三個森林凍結 Gate（改為分區驗證後仍會 FAIL）
	_case("N14", "forest.freeze_file", true, "凍結檔的雜湊（layout 記錄）不符", func():
		(lib.L["forest"]["freeze"] as Dictionary)["sha256"] = _flip(String(lib.L["forest"]["freeze"]["sha256"]))
		_g_forest_freeze())
	_case("N15", "forest.freeze_file", true, "凍結區被改成 S01／S02／S03（把 S01 偷偷重新凍結）", func():
		(lib.L["forest"]["freeze"] as Dictionary)["scenes"] = ["S01", "S02", "S03"]
		_g_forest_freeze())
	_case("N16", "forest.freeze_file", true, "凍結區被縮成只剩 S02（S03 被偷偷解凍）", func():
		(lib.L["forest"]["freeze"] as Dictionary)["scenes"] = ["S02"]
		_g_forest_freeze())
	_case("N17", "forest.freeze_file", true, "S01 解凍卻沒有宣告候選規劃（舊抽樣會悄悄取代 S01）", func():
		(lib.L["forest"]["s01_candidate"] as Dictionary)["enabled"] = false
		_g_forest_freeze())
	var plan: Array = _plan_all()
	var i_s02 := -1
	var i_s03 := -1
	for i4 in plan.size():
		var sc4: String = String((plan[i4] as Dictionary)["scene"])
		if sc4 == "S02" and i_s02 < 0:
			i_s02 = i4
		if sc4 == "S03":
			i_s03 = i4
	_case("N18", "forest.frozen_plan_equal", true, "forest_plan.json 裡一棵 S02 的樹被挪動 0.5 m", func():
		var p2: Array = _plan_all()
		(p2[i_s02] as Dictionary)["x"] = float(p2[i_s02]["x"]) + 0.5
		_plan_override = p2
		_g_forest_freeze()
		_plan_override = [])
	_case("N19", "forest.frozen_plan_equal", true, "forest_plan.json 少了一棵 S03 的樹", func():
		var p2: Array = _plan_all()
		p2.remove_at(i_s03)
		_plan_override = p2
		_g_forest_freeze()
		_plan_override = [])
	var f_s03: Node = _forest_of("S03")
	var f_s02: Node = _forest_of("S02")
	_case("N20", "forest.frozen_scene_equal", true, "場景裡一棵 S03 的樹被挪動 0.3 m", func():
		var kid := f_s03.get_child(5) as Node3D
		var p0 := kid.position
		kid.position = p0 + Vector3(0.3, 0.0, 0.0)
		_g_forest_freeze()
		kid.position = p0)
	_case("N21", "forest.frozen_scene_equal", true, "場景裡少了一棵 S02 的樹", func():
		var kid2 := f_s02.get_child(7)
		f_s02.remove_child(kid2)
		_g_forest_freeze()
		f_s02.add_child(kid2)
		f_s02.move_child(kid2, 7))

	# ============================================================ S01 候選規劃 Gate
	var s01_plan_i := -1
	var s01_lean_i := -1
	var s01_seen := 0
	for i5 in plan.size():
		if String((plan[i5] as Dictionary)["scene"]) == "S01":
			if s01_plan_i < 0 and String((plan[i5] as Dictionary)["kind"]) == "tree":
				s01_plan_i = i5
			if s01_lean_i < 0 and (plan[i5] as Dictionary).has("lean"):
				s01_lean_i = s01_seen
			s01_seen += 1
	_case("N22", "s01.candidate_reproducible", true, "forest_plan.json 的一棵 S01 樹被挪動 0.5 m（候選規劃不能由輸入重現）", func():
		var p2: Array = _plan_all()
		(p2[s01_plan_i] as Dictionary)["x"] = float(p2[s01_plan_i]["x"]) + 0.5
		g.plan_override = p2
		g._g_s01_candidate()
		g.plan_override = [])
	var f_s01: Node = _forest_of("S01")
	_case("N23", "s01.scene_equals_plan", true, "場景裡一棵 S01 的樹被挪動 0.2 m", func():
		var kid3 := f_s01.get_child(10) as Node3D
		var p0b := kid3.position
		kid3.position = p0b + Vector3(0.2, 0.0, 0.0)
		g._g_s01_candidate()
		kid3.position = p0b)
	_case("N24", "s01.lean_semantics", true, "場景裡一棵微傾的 S01 樹，傾斜多轉了 3°", func():
		var kid4 := f_s01.get_child(s01_lean_i) as Node3D
		var t0 := kid4.transform
		kid4.transform = Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(3.0)) * t0.basis, t0.origin)
		g._g_s01_candidate()
		kid4.transform = t0)
	# 數量預算：直接丟邊界值給判定式（規劃器的總量由背景林稀疏化守恆，單靠改 target_total 拉不出界外，見 N25p）
	for nn: int in [360, 419, 520, 0]:
		_case("N25", "s01.count_budget(n=%d)" % nn, true, "S01 植被 %d 筆（預算 361–418）" % nn, func():
			results.append({"gate": "s01.count_budget(n=%d)" % nn, "ok": S01GatesScript.count_in_budget(nn), "detail": "count_in_budget(%d)" % nn}))
	for nn2: int in [361, 380, 418]:
		_case("N25c", "s01.count_budget(n=%d)" % nn2, false, "對照：S01 植被 %d 筆在預算內" % nn2, func():
			results.append({"gate": "s01.count_budget(n=%d)" % nn2, "ok": S01GatesScript.count_in_budget(nn2), "detail": "count_in_budget(%d)" % nn2}))
	_case("N25p", "s01.count_budget", false, "資訊：候選的 target_total 拉到 520，規劃器仍把總量守在預算內（背景林少剪而已）", func():
		(lib.L["forest"]["s01_candidate"] as Dictionary)["target_total"] = 520
		g._g_s01_candidate())
	_case("N26", "s01.candidate_declared", true, "S01 被塞回凍結區（候選宣告與凍結互斥）", func():
		(lib.L["forest"]["freeze"] as Dictionary)["scenes"] = ["S01", "S02", "S03"]
		g._g_s01_candidate())

	# ============================================================ S01 R2 Gate（谷壁點綴／釘點櫻／總量）
	if String((lib.L["forest"]["s01_candidate"] as Dictionary).get("mode", "")) == "r2":
		_r2_cases(g)

	var fails := 0
	for r: Dictionary in neg:
		if not bool(r["ok"]):
			fails += 1
	print("═══ S01 Gate 反向測試：%d 項、%d 失敗（對照 %d 項必須 PASS、動手腳 %d 項必須 FAIL）═══" % [neg.size(), fails, neg.filter(func(x): return x["expect"] == "PASS").size(), neg.filter(func(x): return x["expect"] == "FAIL").size()])
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"fails": fails, "cases": neg}, "\t") + "\n")
		f.close()
	quit(0 if fails == 0 else 1)


## R2 的對照與竄改。規劃只做一次（pa_override），每個竄改在記憶體裡做、跑完就還原
func _r2_cases(g: RefCounted) -> void:
	var jf: Variant = JSON.parse_string(FileAccess.get_file_as_string(S01GatesScript.INPUTS))
	var foot: Array = []
	for e: Dictionary in (jf as Dictionary)["footprints"]:
		foot.append({"id": String(e["id"]), "p": Vector2(float(e["p"][0]), float(e["p"][1])), "r": float(e["r"])})
	var pa: RefCounted = S01GatesScript.ForestPlanner.new()
	pa.setup(lib, foot)
	pa.plan()
	g.pa_override = pa
	for gn3: String in ["s01r2.wall_matches_plan", "s01r2.wall_grounded", "s01r2.wall_clear_of_routes", "s01r2.wall_in_s01", "s01r2.wall_collision", "s01r2.pins_moved_limited", "s01r2.total_kept"]:
		_case("C1", gn3, false, "對照（R2）：未動手腳", func(): g._g_s01_r2())
	var rocks: Node = g._s01_root().find_child("WallDressing", false, false).get_node("Rocks")
	var r_out: Node3D = null
	var r_deb: Node3D = null
	var r_col: Node3D = null
	for c in rocks.get_children():
		var kd := String(c.get_meta("bp_kind", ""))
		if kd == "outcrop" and r_out == null:
			r_out = c
		if kd == "debris" and r_deb == null:
			r_deb = c
		if bool(c.get_meta("bp_collide", false)) and r_col == null:
			r_col = c
	_case("N27", "s01r2.wall_matches_plan", true, "場景裡一顆谷壁岩（%s）被挪動 0.2 m（點綴不能由規劃重現）" % r_out.name, func():
		var p0 := r_out.position
		r_out.position = p0 + Vector3(0.2, 0.0, 0.0)
		g._g_s01_r2()
		r_out.position = p0)
	_case("N28", "s01r2.wall_grounded", true, "一顆谷壁岩（%s）整顆抬高 0.4 m（懸空）" % r_out.name, func():
		var p0 := r_out.position
		r_out.position = p0 + Vector3(0.0, 0.4, 0.0)
		g._g_s01_r2()
		r_out.position = p0)
	_case("N28c", "s01r2.wall_grounded", false, "對照：同一顆岩往下多埋 0.3 m（埋深不是懸空，必須 PASS）", func():
		var p0 := r_out.position
		r_out.position = p0 - Vector3(0.0, 0.3, 0.0)
		g._g_s01_r2()
		r_out.position = p0)
	var sv: float = lib.st_s("torii") - 6.0
	var pv: Vector2 = lib.main.pos_at(sv)
	_case("N29", "s01r2.wall_clear_of_routes", true, "一顆谷壁岩被搬到主路中心（鳥居前 6 m）", func():
		var t0 := r_out.transform
		r_out.transform = Transform3D(t0.basis, Vector3(pv.x, lib.h_at(pv.x, pv.y) - 0.1, pv.y))
		g._g_s01_r2()
		r_out.transform = t0)
	_case("N30", "s01r2.wall_in_s01", true, "一顆谷壁岩被搬到 z＝−101（越過 S01/S02 接縫）", func():
		var t0 := r_out.transform
		r_out.transform = Transform3D(t0.basis, Vector3(t0.origin.x, t0.origin.y, -101.0))
		g._g_s01_r2()
		r_out.transform = t0)
	_case("N31", "s01r2.wall_collision", true, "一顆坡腳碎石（%s）被加上碰撞（不必要的碰撞物）" % r_deb.name, func():
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = SphereShape3D.new()
		sb.add_child(cs)
		r_deb.add_child(sb)
		g._g_s01_r2()
		r_deb.remove_child(sb)
		sb.free())
	_case("N31b", "s01r2.wall_collision", true, "一顆玩家走得到的凸出岩（%s）的碰撞被拿掉（玩家會穿過岩）" % r_col.name, func():
		var sb2 := r_col.get_node("Body")
		r_col.remove_child(sb2)
		g._g_s01_r2()
		r_col.add_child(sb2))
	var pin_t: Dictionary = {}
	for t3: Dictionary in pa.trees:
		if String(t3["pin"]) == "sakura_b":
			pin_t = t3
	_case("N32", "s01r2.pins_moved_limited", true, "釘點櫻 sakura_b 被挪 8 m（超過 6 m 的小幅位移上限）", func():
		var x0 := float(pin_t["x"])
		pin_t["x"] = x0 + 8.0
		g._g_s01_r2()
		pin_t["x"] = x0)
	_case("N33", "s01r2.pins_moved_limited", true, "釘點櫻 sakura_b 被換成別的樹種（sakura_yama）", func():
		var id0 := String(pin_t["id"])
		pin_t["id"] = "sakura_yama" if id0 != "sakura_yama" else "sakura_somei"
		g._g_s01_r2()
		pin_t["id"] = id0)
	_case("N34", "s01r2.pins_moved_limited", true, "新增一個以 sakura_a／sakura_b 為錨點的 POI（被移動的釘點有功能依存）", func():
		(lib.L["pois"] as Array).append({"id": "neg_rope", "kind": "shimenawa", "between": ["sakura_a", "sakura_b"]})
		g._g_s01_r2())
	_case("N35", "s01r2.pins_moved_limited", true, "一棵釘點櫻（sakura_c）從規劃裡消失（五棵都要保留）", func():
		var pc: Dictionary = {}
		for t4: Dictionary in pa.trees:
			if String(t4["pin"]) == "sakura_c":
				pc = t4
		var ic: int = pa.trees.find(pc)
		pa.trees.remove_at(ic)
		g._g_s01_r2()
		pa.trees.insert(ic, pc))
	var under_i := -1
	for i6 in pa.trees.size():
		if String(pa.trees[i6]["scene"]) == "S01" and String(pa.trees[i6]["kind"]) == "under":
			under_i = i6
	_case("N36", "s01r2.total_kept", true, "S01 少一株林下（總量 379 ≠ 380）", func():
		var u0: Dictionary = pa.trees[under_i]
		pa.trees.remove_at(under_i)
		g._g_s01_r2()
		pa.trees.insert(under_i, u0))
	_case("N37", "s01.candidate_declared", true, "mode＝r2 但 r2 設定是空的（R2 候選沒有宣告內容）", func():
		(lib.L["forest"]["s01_candidate"] as Dictionary)["r2"] = {}
		g._g_s01_candidate())
	g.pa_override = null
