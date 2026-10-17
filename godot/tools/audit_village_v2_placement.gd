extends SceneTree
## 人間之里 V2：場景級擺放／碰撞稽核（skill godot-asset-placement-validation 的專案實作）。
##   Godot --headless --path godot --script res://tools/audit_village_v2_placement.gd [-- 選項]
##     --out=<json>   完整報告
##     --strict       退出碼＝FAIL 單位數（單跑 clean／neg 用）
##     --neg=<case>   單跑一個反向／對照案例（float|sink|clash|aabbfp|noproxy）
##     --selftest     回歸用：clean＋5 個永久案例依序跑，任一結果不符預期 → 退出碼＝不符項數
##
## 只讀、不改場景（反向案例只改記憶體中的實例）。擺放單位：
##   - Landmarks/*/Hero（P5 已過 Asset Gate 的 Hero／地標，compound 碰撞）
##   - Landmarks/* 下仍在用的 placeholder StaticBody3D（例：丘腳社寺 P4 Block，待參考圖）
##   - Districts/**/B_*（P4 灰盒 StaticBody3D，單一 BoxShape3D）
##   退場灰盒（collision_layer 0／shape disabled）略過。
##   visual_only：Landmarks/* 的 Wire／Footprint（P0 未定案線框，產生器註明無碰撞）、QuestAnchors/*/Pole（任務錨點標桿）；
##     或節點 meta visual_only／no_collision_required／decorative_only＝true。只列清單、不驗、不算 PASS。
##   稽核範圍外（只報數量）：Vegetation 合併林、Roads／Water／Yards／ParcelLines 等地表貼片、Terrain。
##
## 分層驗證（AABB 只當 broad phase，不當碰撞結論）：
##   1 Broad phase    ：單位世界 AABB（有碰撞＝碰撞 shape 聯集；沒碰撞＝可見網格）兩兩相交 → 候選對
##   2 Shape-aware    ：候選對逐 shape 做 collide_shape（實際 Box/Cylinder/Convex、含旋轉），接觸點對距離＝穿插深度；
##                      AABB 相交但形狀不接觸 → AABB_FALSE_POSITIVE（只計數）。
##                      候選對任一方沒有可用碰撞（且非 visual_only）→ NO_COLLISION_PROXY＝REVIEW（物理查詢沒回報≠安全）
##   3 Multi-point 接地：每個落地 shape 底面取 adaptive 格點（間距 SAMPLE_SPACING、每軸 3–SAMPLE_MAX_N、每單位 ≤ RAYS_MAX），
##                      向下只認地形碰撞；碰撞代理離地時再比對同 XZ 可見網格最低點（代理離地≠畫面懸空）
##   4 Support %／5 Slope／6 Penetration（建築：地形高過基準面＝頂進屋內；單位間穿插深度）
## 輸出 [PLACE] 開頭。

var SCENE := "res://maps/village_v2/village_v2.tscn"   # --scene=res://… 可改（快速通道示範場景用）
const FLOAT_TOL := 0.05      # 底面高於地形超過這個＝該點懸空
const FLOAT_FAIL := 0.15     # 可見懸空超過這個＝FLOATING FAIL
const FOOT_BAND := 0.6       # shape 底面距單位最低 shape 底 ≤ 這個＝落地 shape
const GRADE_TOL := 0.05      # 建築：地形高過原點（基準面）這麼多＝地形頂進屋內
const PEN_REVIEW := 0.02     # 單位間穿插深度
const PEN_FAIL := 0.05
const SLOPE_REVIEW_BLD := 20.0
const SINK_REVIEW := 0.6     # 建築最淺埋深（全部點都埋超過這個）＝整棟下沉
const SUPPORT_PASS := 0.8
const SUPPORT_FAIL := 0.6
const SAMPLE_SPACING := 2.0  # adaptive 接地取樣：目標點距（m）
const SAMPLE_MAX_N := 12     # 每軸上限（≤ 144 點／shape）
const RAYS_MAX := 400        # 每單位射線上限（超過就等比降密度）
const RENDER_R := 0.25       # 可見網格最低點格網（m）
const VISUAL_ONLY_META: Array[String] = ["visual_only", "no_collision_required", "decorative_only"]

## 永久反向／對照案例：改哪個、預期什麼。selftest 逐一驗，結果改變 → 回歸失敗。
const CASES := {
	"float": "鈴奈庵抬高 0.3 m → 鈴奈庵 FAIL（FLOATING）",
	"sink": "鈴奈庵下沉 0.8 m → 鈴奈庵 FAIL（TERRAIN_PENETRATION）",
	"clash": "霧雨店推進鈴奈庵側面 6 m → 兩者 FAIL（OBJECT_PENETRATION）",
	"aabbfp": "兩個 10×3×3 m 箱體 yaw 40°、短軸淨距 0.6 m 並排（AABB 明顯重疊、形狀不接觸）→ 兩者 PASS、計入 AABB_FALSE_POSITIVE",
	"noproxy": "霧雨店碰撞全停用並推進鈴奈庵 AABB → 霧雨店 REVIEW（NO_COLLISION_PROXY），不得 PASS",
}

var v: Node3D
var space: PhysicsDirectSpaceState3D
var terrain_rid: RID
var static_rids: Array[RID] = []
var units: Array = []        # {name, node, kind, building, proxy, shapes:[{cs, rid, xf, laabb, waabb, name}], waabb, rids}
var visual_only: Array = []  # {name, reason}
var neg := ""
var quiet := false


func _init() -> void:
	_run.call_deferred()


func _p(s: String) -> void:
	print("[PLACE] " + s)


func _run() -> void:
	var out := ""
	var strict := false
	var selftest := false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a == "--strict":
			strict = true
		elif a.begins_with("--neg="):
			neg = a.trim_prefix("--neg=")
		elif a == "--selftest":
			selftest = true
		elif a.begins_with("--scene="):
			SCENE = a.trim_prefix("--scene=")
	if selftest:
		quit(await _selftest(out))
		return
	if neg != "" and not CASES.has(neg):
		_p("FAIL 未知案例 --neg=%s（可用：%s）" % [neg, ", ".join(CASES.keys())])
		quit(1)
		return
	var R := await _audit(neg)
	if out != "":
		_write(out, R)
	quit(int(R["tally"]["FAIL"]) if strict else 0)


# ─────────────────────────── selftest（回歸） ───────────────────────────

func _selftest(out: String) -> int:
	var bad := 0
	var t_all := Time.get_ticks_msec()
	# clean：目前涵蓋範圍內全部 PASS
	var C := await _audit("")
	var ok: bool = int(C["tally"]["FAIL"]) == 0 and int(C["tally"]["REVIEW"]) == 0
	_p("%s clean：PASS %d／REVIEW %d／FAIL %d（涵蓋 %d 單位）" % ["OK" if ok else "FAIL（期望全部 PASS）",
		C["tally"]["PASS"], C["tally"]["REVIEW"], C["tally"]["FAIL"], C["coverage"]])
	bad += 0 if ok else 1
	if out != "":
		_write(out, C)
	quiet = true
	for c: String in CASES:
		var R := await _audit(c)
		var u: Dictionary = R["by_name"]
		var S := _st(u, "LANDMARK_SUZUNAAN/Hero")
		var K := _st(u, "LANDMARK_KIRISAME/Hero")
		var got := ""
		match c:
			"float":
				ok = S[0] == "FAIL" and S[1].contains("FLOATING")
				got = "鈴奈庵 %s %s" % S
			"sink":
				ok = S[0] == "FAIL" and S[1].contains("TERRAIN_PENETRATION")
				got = "鈴奈庵 %s %s" % S
			"clash":
				ok = S[0] == "FAIL" and K[0] == "FAIL" and S[1].contains("OBJECT_PENETRATION") \
					and K[1].contains("OBJECT_PENETRATION")
				got = "鈴奈庵 %s／霧雨店 %s %s" % [S[0], K[0], K[1]]
			"aabbfp":
				var A := _st(u, "AuditControl/CTRL_A")
				var B := _st(u, "AuditControl/CTRL_B")
				var cand := false
				var touch := true
				for pr: Dictionary in R["pairs"]:
					if [pr["na"], pr["nb"]].has("AuditControl/CTRL_A") and [pr["na"], pr["nb"]].has("AuditControl/CTRL_B"):
						cand = true
						touch = pr["touch"]
				ok = cand and not touch and A[0] == "PASS" and B[0] == "PASS" and int(R["tally"]["FAIL"]) == 0
				got = "AABB 候選 %s、形狀接觸 %s、CTRL_A %s／CTRL_B %s %s" % [cand, touch, A[0], B[0], A[1] + B[1]]
			"noproxy":
				ok = K[0] == "REVIEW" and K[1].contains("NO_COLLISION_PROXY")
				got = "霧雨店 %s %s" % K
		_p("%s %s：%s → %s（%d ms）" % ["OK" if ok else "FAIL", c, CASES[c], got, R["ms"]])
		bad += 0 if ok else 1
	_p("結果：selftest %d 項不符預期（clean＋%d 案例，共 %d ms）" % [bad, CASES.size(), Time.get_ticks_msec() - t_all])
	return bad


func _st(by_name: Dictionary, n: String) -> Array:
	if not by_name.has(n):
		return ["MISSING", ""]
	var r: Dictionary = by_name[n]
	return [String(r["status"]), "；".join(r["issues"])]


func _write(out: String, R: Dictionary) -> void:
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"case": R["case"], "tally": R["tally"], "issues": R["issues"],
		"coverage": R["coverage"], "aabb_false_positive": R["fp"], "rays": R["rays"], "ms": R["ms"],
		"visual_only": R["visual_only"], "out_of_scope": R["out_of_scope"], "units": R["units"]}, "\t"))
	f.close()
	_p("報告 → %s" % out)


# ─────────────────────────── 一輪稽核 ───────────────────────────

func _audit(case: String) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	neg = case
	units = []
	visual_only = []
	v = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	_apply_neg()
	for i in 3:
		await physics_frame
	space = v.get_world_3d().direct_space_state
	terrain_rid = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	static_rids = [terrain_rid, (v.get_node("Collision/Boundary") as CollisionObject3D).get_rid()]
	_collect()
	var pairs := _broad_phase()
	var contacts := _narrow_phase(pairs)
	var report: Array = []
	var by_name := {}
	var tally := {"PASS": 0, "REVIEW": 0, "FAIL": 0}
	var issue_count := {}
	var rays := 0
	for u: Dictionary in units:
		var r := _ground(u)
		rays += int(r["samples"])
		r["contacts"] = contacts.get(u["name"], [])
		_classify(u, r)
		report.append(r)
		by_name[u["name"]] = r
		tally[r["status"]] += 1
		for iss: String in r["issues"]:
			var k := iss.get_slice(" ", 0)
			issue_count[k] = int(issue_count.get(k, 0)) + 1
	var fp := 0
	for pr in pairs:
		if not pr["touch"] and not pr["noproxy"]:
			fp += 1
	var oos := _out_of_scope()
	var ms := Time.get_ticks_msec() - t0
	if not quiet:
		var kinds := {}
		for u: Dictionary in units:
			kinds[u["kind"]] = int(kinds.get(u["kind"], 0)) + 1
		_p("案例：%s" % (case if case != "" else "clean"))
		_p("涵蓋 %d 擺放單位 %s；接地射線 %d 條（adaptive，間距 %.1f m、每軸 ≤ %d、每單位 ≤ %d）" % [units.size(),
			JSON.stringify(kinds), rays, SAMPLE_SPACING, SAMPLE_MAX_N, RAYS_MAX])
		_p("visual_only（不驗、不計 PASS）%d：%s" % [visual_only.size(), _summ(visual_only)])
		_p("稽核範圍外（只報數量）：%s" % JSON.stringify(oos))
		_p("Broad phase：AABB 相交候選 %d 對 → 形狀實際接觸 %d 對、AABB_FALSE_POSITIVE %d 對、缺碰撞代理 %d 對" % [
			pairs.size(), pairs.filter(func(p): return p["touch"]).size(), fp,
			pairs.filter(func(p): return p["noproxy"]).size()])
		for r: Dictionary in report:
			if r["status"] != "PASS":
				_p("%s %s [%s] support %d/%d gap_max %.3f slope_max %.1f° relief %.2f：%s" % [r["status"], r["name"],
					r["kind"], r["hits"], r["samples"], r["gap_max"], r["slope_max"], r["relief"], "；".join(r["issues"])])
		var infos: Array = []
		for r: Dictionary in report:
			if not (r["info"] as Array).is_empty():
				infos.append("%s（%s）" % [r["name"], "、".join(r["info"])])
		if not infos.is_empty():
			_p("INFO %d 單位（刻意重疊／代理差異）：%s%s" % [infos.size(), "；".join(infos.slice(0, 6)),
				" …" if infos.size() > 6 else ""])
		_p("問題分類：%s" % JSON.stringify(issue_count))
		_p("結果：PASS %d／REVIEW %d／FAIL %d（涵蓋 %d 單位，%d ms）——結論只適用於目前涵蓋範圍" % [tally["PASS"],
			tally["REVIEW"], tally["FAIL"], units.size(), ms])
	v.queue_free()
	await process_frame
	return {"case": case if case != "" else "clean", "tally": tally, "issues": issue_count, "coverage": units.size(),
		"fp": fp, "rays": rays, "ms": ms, "pairs": pairs.map(func(p): return {"na": units[p["a"]]["name"],
			"nb": units[p["b"]]["name"], "touch": p["touch"], "noproxy": p["noproxy"]}),
		"visual_only": visual_only, "out_of_scope": oos, "units": report, "by_name": by_name}


func _summ(a: Array) -> String:
	var by := {}
	for e: Dictionary in a:
		by[e["reason"]] = int(by.get(e["reason"], 0)) + 1
	return JSON.stringify(by)


## 反向／對照案例：只改記憶體中的實例，不存檔。
func _apply_neg() -> void:
	var s := v.get_node_or_null("Landmarks/LANDMARK_SUZUNAAN/Hero") as Node3D
	var k := v.get_node_or_null("Landmarks/LANDMARK_KIRISAME/Hero") as Node3D
	match neg:
		"float":
			s.position.y += 0.3
		"sink":
			s.position.y -= 0.8
		"clash":
			k.global_position = s.global_position + s.global_basis.x * 6.0
		"noproxy":
			for c in k.find_children("*", "CollisionShape3D", true, false):
				(c as CollisionShape3D).disabled = true
			k.global_position = s.global_position + s.global_basis.x * 6.0
		"aabbfp":
			_add_control()


## 對照組兩箱放在 spot 時，除地形外不得碰到任何既有 collider。
## StaticBody 原點 ±15 m 的粗篩看不到「原點在別處、shape 散在全圖」的 overlay 碰撞
## （分塊植被 Collision/C_x_z、Props/EnvironmentP9/Collision 等），所以逐 shape 實查。
func _control_clear(sp: PhysicsDirectSpaceState3D, trid: RID, spot: Vector3) -> bool:
	var basis := Basis(Vector3.UP, deg_to_rad(40.0))
	var bs := BoxShape3D.new()
	bs.size = Vector3(10.0, 3.0, 3.0)
	for i in 2:
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = bs
		q.transform = Transform3D(basis, spot + basis.z * (1.8 if i == 0 else -1.8) + Vector3(0, 1.4, 0))
		q.exclude = [trid]
		q.margin = 0.05
		if not sp.intersect_shape(q, 1).is_empty():
			return false
	return true


## aabbfp：在遠離所有單位的平地放兩個旋轉 40° 的長箱，短軸方向並排、淨距 0.6 m。
func _add_control() -> void:
	var sp := v.get_world_3d().direct_space_state
	var trid := (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	var boxes: Array[AABB] = []
	for b in v.find_children("*", "CollisionObject3D", true, false):
		if b is StaticBody3D and b.name != "TerrainCollision" and b.name != "Boundary":
			var c3 := (b as Node3D).global_position
			boxes.append(AABB(c3 - Vector3(15, 50, 15), Vector3(30, 100, 30)))
	var spot := Vector3.INF
	for gx in range(0, 51):
		for gz in range(0, 51):
			var p := Vector3(-100.0 + gx * 12.0, 0.0, -350.0 + gz * 12.0)
			var clear := true
			for bb in boxes:
				if bb.has_point(Vector3(p.x, bb.get_center().y, p.z)):
					clear = false
					break
			if not clear:
				continue
			var lo := INF
			var hi := -INF
			for o in [Vector2(0, 0), Vector2(9, 0), Vector2(-9, 0), Vector2(0, 9), Vector2(0, -9), Vector2(7, 7),
					Vector2(-7, -7), Vector2(7, -7), Vector2(-7, 7)]:
				var q := PhysicsRayQueryParameters3D.create(Vector3(p.x + o.x, 400, p.z + o.y),
					Vector3(p.x + o.x, -80, p.z + o.y))
				var h := sp.intersect_ray(q)
				if h.is_empty() or h["rid"] != trid:
					lo = INF
					break
				lo = minf(lo, h["position"].y)
				hi = maxf(hi, h["position"].y)
			if lo < INF and hi - lo < 0.25 and _control_clear(sp, trid, Vector3(p.x, lo, p.z)):
				spot = Vector3(p.x, lo, p.z)
				break
		if spot != Vector3.INF:
			break
	if spot == Vector3.INF:
		push_error("[PLACE] aabbfp：找不到平地放對照組")
		return
	var root3 := Node3D.new()
	root3.name = "AuditControl"
	v.add_child(root3)
	var yaw := deg_to_rad(40.0)
	var basis := Basis(Vector3.UP, yaw)
	var size := Vector3(10.0, 3.0, 3.0)
	for i in 2:
		var sb := StaticBody3D.new()
		sb.name = "CTRL_A" if i == 0 else "CTRL_B"
		var off := basis.z * (1.8 if i == 0 else -1.8)   # 短軸中心距 3.6 m − 3.0 m 厚＝淨距 0.6 m
		sb.global_transform = Transform3D(basis, spot + off + Vector3(0, size.y * 0.5 - 0.1, 0))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		sb.add_child(mi)
		root3.add_child(sb)


# ─────────────────────────── 收集 ───────────────────────────

func _collect() -> void:
	var lm := v.get_node("Landmarks")
	for a: Node in lm.get_children():
		for c: Node in a.get_children():
			var nm := "%s/%s" % [a.name, c.name]
			if _is_visual_only(c):
				visual_only.append({"name": nm, "reason": "meta"})
				continue
			if c.name == "Hero":
				var bld := false
				var aj := String(c.get_meta("asset_json", ""))
				if aj != "":
					var S: Variant = JSON.parse_string(FileAccess.get_file_as_string(aj))
					if S is Dictionary:
						var gs: Dictionary = S.get("gate_spec", {})
						bld = gs.has("body") or gs.has("building")
				_add(c as Node3D, nm, "hero", bld)
			elif c is StaticBody3D:
				_add(c as Node3D, nm, "placeholder", true)   # 退場灰盒（layer 0）在 _add 內略過
			elif c is MeshInstance3D and (c.name == "Wire" or c.name == "Footprint"):
				visual_only.append({"name": nm, "reason": "P0 線框（產生器註明無碰撞）"})
	for b: Node in v.get_node("Districts").find_children("B_*", "StaticBody3D", true, false):
		_add(b as Node3D, String(b.name), "greybox", true)
	# P7 R2 正式橋（Roads/Bridges/Bridge_*/Hero）：已過 Asset Gate 的橋入涵蓋；灰盒橋本身（Roads）仍屬範圍外
	var brs := v.get_node_or_null("Roads/Bridges")
	if brs != null:
		for b: Node in brs.get_children():
			var h := b.get_node_or_null("Hero") as Node3D
			if h != null:
				_add(h, "Roads/Bridges/%s/Hero" % b.name, "hero", false)
	# 建築快速通道（tools/fastlane/place_building.gd，2026-10-18）：FastLane/<id> 每個都是建築單位
	var fl := v.get_node_or_null("FastLane")
	if fl != null:
		for b: Node in fl.get_children():
			if b is Node3D:
				_add(b as Node3D, "FastLane/%s" % b.name, "hero", true)
	for q: Node in v.get_node("QuestAnchors").find_children("Pole", "MeshInstance3D", true, false):
		visual_only.append({"name": "QuestAnchors/%s/Pole" % q.get_parent().name, "reason": "任務錨點標桿"})
	var ctrl := v.get_node_or_null("AuditControl")
	if ctrl != null:
		for c: Node in ctrl.get_children():
			_add(c as Node3D, "AuditControl/%s" % c.name, "control", false)


func _is_visual_only(n: Node) -> bool:
	for k in VISUAL_ONLY_META:
		if bool(n.get_meta(k, false)):
			return true
	return false


func _add(n: Node3D, name: String, kind: String, building: bool) -> void:
	var shapes: Array = []
	var cos: Array = [n] if n is CollisionObject3D else []
	cos.append_array(n.find_children("*", "CollisionObject3D", true, false))
	var rids: Array[RID] = []
	var retired := not cos.is_empty()
	for co: CollisionObject3D in cos:
		if co.collision_layer == 0:
			continue
		retired = false
		for c in co.get_children():
			if c is CollisionShape3D:
				var cs := c as CollisionShape3D
				if not cs.disabled and cs.shape != null:
					var la := _shape_aabb(cs.shape)
					var xf := cs.global_transform
					shapes.append({"cs": cs, "rid": co.get_rid(), "xf": xf, "laabb": la, "waabb": xf * la,
						"name": String(cs.name)})
		if not rids.has(co.get_rid()):
			rids.append(co.get_rid())
	if retired and bool(n.get_meta("retired_by_hero", false)):
		return   # 灰盒已被 Hero 取代（retire()：layer 0＋shape disabled＋隱藏）
	var wa := AABB()
	if shapes.is_empty():
		# 沒有可用碰撞代理：用可見網格的世界 AABB 參與 broad phase（NO_COLLISION_PROXY）
		var mis := n.find_children("*", "MeshInstance3D", true, false)
		if n is MeshInstance3D:
			mis.append(n)
		var got := false
		for mi: MeshInstance3D in mis:
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var a := mi.global_transform * mi.get_aabb()
			wa = a if not got else wa.merge(a)
			got = true
		if not got:
			return   # 既無碰撞也無可見網格：空節點，不是擺放單位
	else:
		wa = shapes[0]["waabb"]
		for s in shapes:
			wa = wa.merge(s["waabb"])
	units.append({"name": name, "node": n, "kind": kind, "building": building, "proxy": not shapes.is_empty(),
		"shapes": shapes, "waabb": wa, "rids": rids})


func _shape_aabb(sh: Shape3D) -> AABB:
	if sh is BoxShape3D:
		var s := (sh as BoxShape3D).size
		return AABB(-s * 0.5, s)
	if sh is CylinderShape3D:
		var c := sh as CylinderShape3D
		return AABB(Vector3(-c.radius, -c.height * 0.5, -c.radius), Vector3(c.radius * 2, c.height, c.radius * 2))
	if sh is CapsuleShape3D:
		var k := sh as CapsuleShape3D
		return AABB(Vector3(-k.radius, -k.height * 0.5, -k.radius), Vector3(k.radius * 2, k.height, k.radius * 2))
	if sh is SphereShape3D:
		var r := (sh as SphereShape3D).radius
		return AABB(Vector3.ONE * -r, Vector3.ONE * r * 2)
	if sh is ConvexPolygonShape3D:
		var pts := (sh as ConvexPolygonShape3D).points
		var a := AABB(pts[0], Vector3.ZERO)
		for p in pts:
			a = a.expand(p)
		return a
	return sh.get_debug_mesh().get_aabb()


## 稽核範圍外的內容：只報數量，讓「全部 PASS」不被誤讀成整張圖沒問題。
func _out_of_scope() -> Dictionary:
	var o := {}
	for grp in ["Vegetation", "Roads", "Water", "Terrain", "Props"]:
		var n := v.get_node_or_null(grp)
		if n != null:
			o[grp] = n.find_children("*", "MeshInstance3D", true, false).size() + n.find_children("*",
				"MultiMeshInstance3D", true, false).size()
	var flat := 0
	for d in v.get_node("Districts").get_children():
		for c in d.get_children():
			if c is MeshInstance3D:
				flat += 1
	o["Districts 地表貼片（Yards／AuxYards／ParcelLines）"] = flat
	return o


# ─────────────────────────── 1＋2 碰撞 ───────────────────────────

func _broad_phase() -> Array:
	var pairs: Array = []
	for i in units.size():
		var ai: AABB = units[i]["waabb"]
		for j in range(i + 1, units.size()):
			if ai.intersects(units[j]["waabb"]):
				pairs.append({"a": i, "b": j, "touch": false,
					"noproxy": not units[i]["proxy"] or not units[j]["proxy"]})
	return pairs


## 候選對逐 shape：collide_shape 只對 B（exclude 場景中 B 以外的所有碰撞體：其他單位、地形、邊界，以及 overlay 的道具碰撞），接觸點對距離＝穿插深度。
## （2026-10-16 修正：原本只排除「單位＋地形＋邊界」，A 的 shape 碰到第三者——例如 EnrichW9P8 貼牆的棚、ArchW9R2P13 的柱——
##   也被記成 A×B 穿插。判定門檻不變，只修正接觸的歸屬。）
## 任一方沒有碰撞代理 → 不做物理查詢（查了也必然「沒碰到」），記 NO_COLLISION_PROXY。
func _narrow_phase(pairs: Array) -> Dictionary:
	var all_rids: Array[RID] = static_rids.duplicate()
	for u in units:
		all_rids.append_array(u["rids"])
	for co in v.find_children("*", "CollisionObject3D", true, false):
		var rid := (co as CollisionObject3D).get_rid()
		if not all_rids.has(rid):
			all_rids.append(rid)
	var res := {}
	for pr: Dictionary in pairs:
		var A: Dictionary = units[pr["a"]]
		var B: Dictionary = units[pr["b"]]
		if pr["noproxy"]:
			for X: Dictionary in [A, B]:
				if not X["proxy"]:
					var other: Dictionary = B if X == A else A
					res[X["name"]] = (res.get(X["name"], []) as Array) + [{"with": other["name"], "noproxy": true}]
			continue
		var ex: Array[RID] = []
		for r in all_rids:
			if not (B["rids"] as Array).has(r):
				ex.append(r)
		var depth := 0.0
		var where := ""
		for sa: Dictionary in A["shapes"]:
			if not (sa["waabb"] as AABB).intersects(B["waabb"]):
				continue
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = (sa["cs"] as CollisionShape3D).shape
			q.transform = sa["xf"]
			q.exclude = ex
			q.margin = 0.0
			var pts := space.collide_shape(q, 16)
			for k in range(0, pts.size() - 1, 2):
				var d: float = (pts[k] as Vector3).distance_to(pts[k + 1])
				if d > depth:
					depth = d
					where = String(sa["name"])
			if not pts.is_empty():
				pr["touch"] = true
		if pr["touch"]:
			var e := {"with": B["name"], "depth": snappedf(depth, 0.001), "shape": where}
			var e2 := {"with": A["name"], "depth": snappedf(depth, 0.001), "shape": "?"}
			res[A["name"]] = (res.get(A["name"], []) as Array) + [e]
			res[B["name"]] = (res.get(B["name"], []) as Array) + [e2]
	return res


# ─────────────────────────── 3–6 接地 ───────────────────────────

func _terrain(x: float, z: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -80.0, z))
	q.exclude = [] as Array[RID]
	for i in 24:
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return {}
		if hit["rid"] == terrain_rid:
			return {"y": float(hit["position"].y), "n": hit["normal"]}
		var ex := q.exclude
		ex.append(hit["rid"])
		q.exclude = ex
	return {}


## 可見網格在 (x,z) 周圍 RENDER_R 內的最低頂點世界 y（Hero 用 LOD0；其他用全部 MeshInstance3D）。格網懶建、快取在 u。
func _render_min(u: Dictionary, x: float, z: float) -> float:
	if not u.has("rgrid"):
		var grid := {}
		var n3 := u["node"] as Node3D
		var mis: Array = []
		var lod0 := n3.get_node_or_null("LOD0")
		if lod0 is MeshInstance3D:
			mis = [lod0]
		else:
			mis = n3.find_children("*", "MeshInstance3D", true, false)
		for mi: MeshInstance3D in mis:
			if mi.mesh == null:
				continue
			var xf := mi.global_transform
			for si in mi.mesh.get_surface_count():
				var vs: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
				for p in vs:
					var w := xf * p
					var k := Vector2i(floori(w.x / RENDER_R), floori(w.z / RENDER_R))
					grid[k] = minf(float(grid.get(k, INF)), w.y)
		u["rgrid"] = grid
	var g: Dictionary = u["rgrid"]
	var kx := floori(x / RENDER_R)
	var kz := floori(z / RENDER_R)
	var lo := INF
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			lo = minf(lo, float(g.get(Vector2i(kx + dx, kz + dz), INF)))
	return lo


## adaptive 格點數：每軸 ceil(長/間距)+1，夾在 [3, SAMPLE_MAX_N]；圓柱固定 3（小柱腳）。
func _grid_n(len_m: float, cyl: bool) -> int:
	if cyl:
		return 3
	return clampi(ceili(len_m / SAMPLE_SPACING) + 1, 3, SAMPLE_MAX_N)


func _ground(u: Dictionary) -> Dictionary:
	var n3 := u["node"] as Node3D
	var base := {"name": u["name"], "kind": u["kind"], "building": u["building"], "proxy": u["proxy"],
		"pos": [snappedf(n3.global_position.x, 0.01), snappedf(n3.global_position.y, 0.01),
			snappedf(n3.global_position.z, 0.01)]}
	if not u["proxy"]:
		base.merge({"feet": [], "float_shapes": {}, "proxy_gaps": {}, "samples": 0, "hits": 0, "support": 0.0,
			"gap_max": 0.0, "embed_min": 0.0, "embed_max": 0.0, "slope_max": 0.0, "relief": 0.0,
			"terrain_hi": -INF, "grade": n3.global_position.y, "grid": []})
		return base
	var lowest := INF
	for s: Dictionary in u["shapes"]:
		lowest = minf(lowest, (s["waabb"] as AABB).position.y)
	# 先決定各落地 shape 的格點數，總數超過 RAYS_MAX 就等比縮
	var feet_s: Array = []
	var total := 0
	# 快速通道建築：有標 meta foot 的 shape（牆腳範圍的薄箱）就只用它們當落地 shape，不拿含屋簷的整體網格去量
	var marked := false
	for s: Dictionary in u["shapes"]:
		marked = marked or bool((s["cs"] as CollisionShape3D).get_meta("foot", false))
	for s: Dictionary in u["shapes"]:
		if marked and not bool((s["cs"] as CollisionShape3D).get_meta("foot", false)):
			continue
		if (s["waabb"] as AABB).position.y - lowest > FOOT_BAND:
			continue
		var la: AABB = s["laabb"]
		var cyl := (s["cs"] as CollisionShape3D).shape is CylinderShape3D
		var nx := _grid_n(la.size.x, cyl)
		var nz := _grid_n(la.size.z, cyl)
		feet_s.append([s, nx, nz, cyl])
		total += nx * nz
	if total > RAYS_MAX:
		var k := sqrt(float(RAYS_MAX) / total)
		total = 0
		for f: Array in feet_s:
			f[1] = maxi(3, int(f[1] * k))
			f[2] = maxi(3, int(f[2] * k))
			total += f[1] * f[2]
	var samples := 0
	var hits := 0
	var gap_max := -INF
	var embed_min := INF
	var embed_max := -INF
	var slope_max := 0.0
	var t_lo := INF
	var t_hi := -INF
	var feet: Array = []
	var grids: Array = []
	var float_shapes := {}   # shape 名 → 最大懸空（碰撞與可見網格都離地 > FLOAT_TOL 才記）
	var proxy_gaps := {}     # shape 名 → 碰撞代理離地、但可見網格有接地（INFO）
	for f: Array in feet_s:
		var s: Dictionary = f[0]
		var nx: int = f[1]
		var nz: int = f[2]
		feet.append(s["name"])
		grids.append("%s %d×%d" % [s["name"], nx, nz])
		var la: AABB = s["laabb"]
		var xf: Transform3D = s["xf"]
		var inset := 0.2 if f[3] else 0.08
		for iu in nx:
			for iv in nz:
				var fu := lerpf(inset, 1.0 - inset, float(iu) / float(nx - 1))
				var fv := lerpf(inset, 1.0 - inset, float(iv) / float(nz - 1))
				var lp := Vector3(la.position.x + la.size.x * fu, la.position.y, la.position.z + la.size.z * fv)
				var wp := xf * lp
				var g := _terrain(wp.x, wp.z)
				if g.is_empty():
					continue
				samples += 1
				var t: float = g["y"]
				var gap := wp.y - t
				gap_max = maxf(gap_max, gap)
				embed_min = minf(embed_min, -gap)
				embed_max = maxf(embed_max, -gap)
				if gap <= FLOAT_TOL:
					hits += 1
				else:
					# 碰撞代理懸空 ≠ 畫面懸空：同一 XZ 的可見網格若已碰到地形 → 只是代理底面偏高（INFO）
					var rmin := _render_min(u, wp.x, wp.z)
					if rmin - t <= FLOAT_TOL:
						hits += 1
						proxy_gaps[s["name"]] = snappedf(maxf(float(proxy_gaps.get(s["name"], 0.0)), gap), 0.001)
					else:
						float_shapes[s["name"]] = snappedf(maxf(float(float_shapes.get(s["name"], 0.0)),
							minf(gap, rmin - t)), 0.001)
				slope_max = maxf(slope_max, rad_to_deg((g["n"] as Vector3).angle_to(Vector3.UP)))
				t_lo = minf(t_lo, t)
				t_hi = maxf(t_hi, t)
	base.merge({"feet": feet, "grid": grids, "float_shapes": float_shapes, "proxy_gaps": proxy_gaps,
		"samples": samples, "hits": hits, "support": (float(hits) / samples) if samples > 0 else 0.0,
		"gap_max": snappedf(gap_max, 0.001) if samples > 0 else 0.0,
		"embed_min": snappedf(embed_min, 0.001) if samples > 0 else 0.0,
		"embed_max": snappedf(embed_max, 0.001) if samples > 0 else 0.0,
		"slope_max": snappedf(slope_max, 0.1), "relief": snappedf(t_hi - t_lo, 0.01) if samples > 0 else 0.0,
		"terrain_hi": t_hi, "grade": n3.global_position.y})
	return base


func _classify(u: Dictionary, r: Dictionary) -> void:
	var fail: Array = []
	var review: Array = []
	var info: Array = []
	if not u["proxy"]:
		var with: Array = []
		for c: Dictionary in r["contacts"]:
			with.append(c["with"])
		if with.is_empty():
			review.append("NO_COLLISION_PROXY 沒有可用碰撞、也未標 visual_only（無法驗接地／穿插）")
		else:
			review.append("NO_COLLISION_PROXY 與 %s AABB 重疊但沒有可用碰撞，物理查詢無法判定" % "、".join(with))
	elif r["samples"] == 0:
		fail.append("INSUFFICIENT_SUPPORT 腳下取樣全部打不到地形（出界？）")
	else:
		var sup: float = r["support"]
		var fs := JSON.stringify(r["float_shapes"])
		var vis_gap := 0.0   # 碰撞與可見網格都離地的最大值（只有碰撞代理離地不算懸空）
		for k in r["float_shapes"]:
			vis_gap = maxf(vis_gap, float(r["float_shapes"][k]))
		if vis_gap > FLOAT_FAIL:
			fail.append("FLOATING 最大懸空 %.3f m %s" % [vis_gap, fs])
		elif vis_gap > FLOAT_TOL:
			review.append("FLOATING 局部懸空 %.3f m %s" % [vis_gap, fs])
		if not (r["proxy_gaps"] as Dictionary).is_empty():
			info.append("碰撞代理底離地但可見網格接地 %s" % JSON.stringify(r["proxy_gaps"]))
		if sup < SUPPORT_FAIL:
			fail.append("INSUFFICIENT_SUPPORT %.0f%%" % (sup * 100))
		elif sup < SUPPORT_PASS:
			review.append("INSUFFICIENT_SUPPORT %.0f%%" % (sup * 100))
		if r["building"]:
			var over: float = float(r["terrain_hi"]) - float(r["grade"])
			if over > GRADE_TOL:
				fail.append("TERRAIN_PENETRATION 地形高出基準面 %.3f m" % over)
			if r["slope_max"] > SLOPE_REVIEW_BLD:
				review.append("BAD_SLOPE 腳下最陡 %.1f°" % r["slope_max"])
			if r["embed_min"] > SINK_REVIEW:
				review.append("SINK 最淺埋深 %.2f m（整棟下沉？）" % r["embed_min"])
		if r["embed_max"] > 0.0:
			info.append("基礎埋深 %.2f–%.2f m" % [maxf(r["embed_min"], 0.0), r["embed_max"]])
	for c: Dictionary in r["contacts"]:
		if c.get("noproxy", false):
			if u["proxy"]:
				review.append("NO_COLLISION_PROXY 與無碰撞的 %s AABB 重疊，無法確認不穿插" % c["with"])
			continue
		var d: float = c["depth"]
		if d > PEN_FAIL:
			fail.append("OBJECT_PENETRATION 與 %s 穿插 %.3f m" % [c["with"], d])
		elif d > PEN_REVIEW:
			review.append("OBJECT_PENETRATION 與 %s 穿插 %.3f m" % [c["with"], d])
		else:
			info.append("貼齊 %s（%.3f m）" % [c["with"], d])
	r["issues"] = fail + review
	r["info"] = info
	r["status"] = "FAIL" if not fail.is_empty() else ("REVIEW" if not review.is_empty() else "PASS")
	r.erase("terrain_hi")
