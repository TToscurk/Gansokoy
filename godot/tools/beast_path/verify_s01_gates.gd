extends RefCounted
## 獸道 S01 入口林道（R1）的驗證關卡：不連動保護（S02／S03／S04 與共用 shader 對 V1.3 基準）、S01 候選植被規劃可重現、
## S01 地形與碰撞不變、layout 只動 S01 的部分。由 verify_beast_path.gd 呼叫：S01Gates.new().run(self)。
##
## 基準＝V1.3 備份（使用者裁定 V1.3 為 S04 固定基準；備份在 repo 外的 hermes backups）。
## 基準清單 tools/beast_path/frozen/protected_v13_manifest.json、layout_digest_v13.json 是從備份算出來的——
## 要更新它們＝使用者核准後的明確動作，不得為了讓 gate 通過而改。

const BP := preload("res://tools/beast_path/bp_lib.gd")
const ForestPlanner := preload("res://tools/beast_path/forest_planner.gd")
const S01Wall := preload("res://tools/beast_path/s01_wall.gd")
const MANIFEST := "res://tools/beast_path/frozen/protected_v13_manifest.json"
const LAYOUT_DIGEST := "res://tools/beast_path/frozen/layout_digest_v13.json"
const INPUTS := "res://maps/beast_path/gen/s01_forest_inputs.json"
const PLAN := "res://maps/beast_path/gen/forest_plan.json"
const LAYOUT := "res://tools/beast_path/layout_beast_path.json"

var v                                  # 呼叫的 verifier（取 _gate／_info／lib／inst）
var lib: BP
var inst: Node
const BUDGET_MIN := 361        # S01 植被總量預算：V0.1 基準 380，−5 %…+10 %（第一輪維持約 380；超過要先提理由與效能預估）
const BUDGET_MAX := 418
var _plan_cache: Array = []
# 反向測試的注入點（正式驗證不設，行為不變）：verify_s01_negatives.gd 會在記憶體裡動手腳，確認這些 Gate 真的會 FAIL
var man_override: Dictionary = {}       # 取代 protected_v13_manifest.json
var digest_override: Dictionary = {}    # 取代 layout_digest_v13.json
var plan_override: Array = []           # 取代 forest_plan.json 的 trees


func run(verifier) -> void:
	v = verifier
	lib = v.lib
	inst = v.inst
	_g_isolation_files()
	_g_isolation_layout()
	_g_s01_terrain_locked()
	_g_s01_candidate()
	_g_s01_r2()


# ================================================================= 工具
static func canon(x: Variant) -> String:
	return JSON.stringify(x, "", true, true)


static func digest(x: Variant) -> String:
	return canon(x).sha256_text()


## 數量預算的判定式（獨立成函式，讓反向測試能直接丟邊界值）
static func count_in_budget(n: int) -> bool:
	return n >= BUDGET_MIN and n <= BUDGET_MAX


## layout 的分段摘要（基準與現況用同一個函式算）。pois 每筆附上所在場景（和生成器 _poi_pos 同一套位置規則）。
static func layout_digest(L: Dictionary, lib_: BP) -> Dictionary:
	var top := {}
	for k: String in L:
		if k == "pois" or k == "forest":
			continue
		top[k] = digest(L[k])
	var forest := {}
	for k: String in (L["forest"] as Dictionary):
		forest[k] = digest(L["forest"][k])
	var pois := {}
	var order: Array = []
	for poi: Dictionary in L["pois"]:
		var id := String(poi["id"])
		pois[id] = {"d": digest(poi), "scene": poi_scene(poi, lib_)}
		order.append(id)
	return {"top": top, "forest": forest, "pois": pois, "order": order}


## 與 generate_beast_path.gd 的 _poi_pos + scene_id_of_z 同一套規則（POI 屬於哪個場景）
static func poi_scene(poi: Dictionary, lib_: BP) -> String:
	var p := Vector2.ZERO
	if poi.has("at"):
		var a: Dictionary = poi["at"]
		if a.has("br") and a.has("u0"):
			var bp: BP.Poly = lib_.branches[String(a["br"])]
			p = bp.pos_at((float(a["u0"]) + float(a["u1"])) * 0.5 * bp.length)
		elif a.has("st") and a.has("ds0"):
			p = lib_.main.pos_at(lib_.st_s(String(a["st"])) + (float(a["ds0"]) + float(a["ds1"])) * 0.5)
		else:
			p = lib_.resolve(a)["p"]
	elif poi.has("st0"):
		var s0 := lib_.st_s(String(poi["st0"])) + float(poi.get("ds0", 0.0))
		var s1 := lib_.st_s(String(poi["st1"])) + float(poi.get("ds1", 0.0))
		p = lib_.main.pos_at((s0 + s1) * 0.5)
	elif String(poi.get("kind", "")) == "shimenawa":
		p = Vector2(0, -400)        # 注連繩（between 兩棵樹）：只在 S04，不屬 S01
	return lib_.scene_id_of_z(p.y)


func _read_plan() -> Array:
	if not plan_override.is_empty():
		return plan_override
	if not _plan_cache.is_empty():
		return _plan_cache
	var f := FileAccess.open(PLAN, FileAccess.READ)
	if f != null:
		var j: Variant = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			_plan_cache = (j as Dictionary)["trees"]
	return _plan_cache


func _scene_of(arr: Array, sc: String) -> Array:
	var r: Array = []
	for t: Dictionary in arr:
		if String(t["scene"]) == sc:
			r.append(t)
	return r


## 與 _write_plan 同樣的量化（x／z／y 到 0.01、s／yaw 到 0.001），讓記憶體裡的規劃能和 forest_plan.json 逐筆比
func _snap(t: Dictionary) -> Dictionary:
	var d := {"id": String(t["id"]), "kind": String(t["kind"]), "pin": String(t["pin"]), "scene": String(t["scene"]),
		"x": snappedf(float(t["x"]), 0.01), "z": snappedf(float(t["z"]), 0.01), "y": snappedf(float(t["y"]), 0.01),
		"s": snappedf(float(t["s"]), 0.001), "yaw": snappedf(float(t["yaw"]), 0.001)}
	if t.has("lean"):
		var ln: Array = t["lean"]
		d["lean"] = [snappedf(float(ln[0]), 0.001), snappedf(float(ln[1]), 0.001), snappedf(float(ln[2]), 0.0001)]
	return d


func _eq(a: Dictionary, b: Dictionary) -> bool:
	for k: String in ["id", "kind", "pin"]:
		if String(a[k]) != String(b[k]):
			return false
	for k: String in ["x", "z", "y", "s", "yaw"]:
		if absf(float(a[k]) - float(b[k])) > 1e-6:
			return false
	if a.has("lean") != b.has("lean"):
		return false
	if a.has("lean"):
		for k2 in 3:
			if absf(float(a["lean"][k2]) - float(b["lean"][k2])) > 1e-6:
				return false
	return true


func _mesh_geom_sha(path: String) -> String:
	var mesh := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
	if mesh == null:
		return ""
	var arr := mesh.surface_get_arrays(0)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array())
	ctx.update((arr[Mesh.ARRAY_NORMAL] as PackedVector3Array).to_byte_array())
	ctx.update((arr[Mesh.ARRAY_INDEX] as PackedInt32Array).to_byte_array())
	return ctx.finish().hex_encode()


func _load_manifest() -> Dictionary:
	if not man_override.is_empty():
		return man_override
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return j if j is Dictionary else {}


# ================================================================= 不連動保護：檔案
func _g_isolation_files() -> void:
	var man := _load_manifest()
	if man.is_empty():
		v._gate("isolation.protected_files", false, "讀不到基準清單 %s" % MANIFEST)
		return
	var raw: Dictionary = man["raw"]
	var bad: Array = []
	for rel: String in raw:
		var p := "res://" + rel
		if not FileAccess.file_exists(p) or FileAccess.get_sha256(p) != String(raw[rel]):
			bad.append(rel)
	var re := RegEx.create_from_string(" unique_id=\\d+")
	var sc_raw := 0
	var sc_norm: Array = []
	var sc_bad: Array = []
	for rel: String in man["scene_norm"]:
		var p := "res://" + rel
		if not FileAccess.file_exists(p):
			sc_bad.append(rel)
			continue
		var e: Dictionary = man["scene_norm"][rel]
		if FileAccess.get_sha256(p) == String(e["raw"]):
			sc_raw += 1
			continue
		var txt := FileAccess.get_file_as_bytes(p).get_string_from_utf8()
		if re.sub(txt, "", true).sha256_text() == String(e["norm"]):
			sc_norm.append(rel.get_file())
		else:
			sc_bad.append(rel)
	var shared := ["assets/beast_path/materials/bp_ground.gdshader", "assets/beast_path/materials/bp_ground.tres", "assets/beast_path/materials/bp_rock.gdshader", "assets/beast_path/materials/bp_rock.tres"]
	var shared_ok := true
	for rel2: String in shared:
		if not raw.has(rel2) or bad.has(rel2):
			shared_ok = false
	v._gate("isolation.protected_files", bad.is_empty() and sc_bad.is_empty() and shared_ok,
		"V1.3 基準 %d 個檔逐位元相同（不同 %d：%s）；場景檔 raw 相同 %d、只差 unique_id %s、不同 %s；S04 共用 shader／材質（bp_ground／bp_rock）未動 %s" % [
			raw.size() - bad.size(), bad.size(), str(bad.slice(0, 6)), sc_raw, str(sc_norm), str(sc_bad), str(shared_ok)])


# ================================================================= 不連動保護：layout 只動 S01
func _g_isolation_layout() -> void:
	var jb: Variant = digest_override if not digest_override.is_empty() else JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_DIGEST))
	if not (jb is Dictionary):
		v._gate("isolation.layout_other_zones", false, "讀不到 %s" % LAYOUT_DIGEST)
		return
	var base: Dictionary = jb
	var cur := layout_digest(lib.L, lib)
	var bad: Array = []
	for k: String in (base["top"] as Dictionary):
		if not (cur["top"] as Dictionary).has(k) or String(cur["top"][k]) != String(base["top"][k]):
			bad.append("top." + k)
	var top_extra: Array = []
	for k2: String in (cur["top"] as Dictionary):
		if not (base["top"] as Dictionary).has(k2):
			top_extra.append(k2)
	for k3: String in (base["forest"] as Dictionary):
		if k3 == "freeze":
			continue                                   # 凍結區範圍依授權改為 S02／S03；由 forest.freeze_file 逐項檢查
		if not (cur["forest"] as Dictionary).has(k3) or String(cur["forest"][k3]) != String(base["forest"][k3]):
			bad.append("forest." + k3)
	var forest_extra: Array = []
	for k4: String in (cur["forest"] as Dictionary):
		if not (base["forest"] as Dictionary).has(k4):
			forest_extra.append(k4)
	var changed_s01: Array = []
	var other_changed: Array = []
	for id: String in (base["pois"] as Dictionary):
		var b: Dictionary = base["pois"][id]
		var c: Variant = (cur["pois"] as Dictionary).get(id, null)
		if String(b["scene"]) == "S01":
			if c == null or String(c["d"]) != String(b["d"]):
				changed_s01.append(id)
			continue
		if c == null or String(c["d"]) != String(b["d"]) or String(c["scene"]) != String(b["scene"]):
			other_changed.append(id)
	var new_pois: Array = []
	var new_outside: Array = []
	for id2: String in (cur["pois"] as Dictionary):
		if not (base["pois"] as Dictionary).has(id2):
			new_pois.append(id2)
			if String(cur["pois"][id2]["scene"]) != "S01":
				new_outside.append(id2)
	# 非 S01 的 POI 順序必須和基準相同（props 的共用亂數狀態只由 POI 順序與 id 決定）
	var ord_b: Array = []
	for id3: String in base["order"]:
		if String(base["pois"][id3]["scene"]) != "S01":
			ord_b.append(id3)
	var ord_c: Array = []
	for id4: String in cur["order"]:
		if (cur["pois"] as Dictionary).has(id4) and String(cur["pois"][id4]["scene"]) != "S01":
			ord_c.append(id4)
	var extra_ok := true
	for k5: String in top_extra:
		if k5 != "s01_ground":
			extra_ok = false
	for k6: String in forest_extra:
		if k6 != "s01_candidate":
			extra_ok = false
	v._gate("isolation.layout_other_zones", bad.is_empty() and other_changed.is_empty() and new_outside.is_empty() and ord_b == ord_c and extra_ok,
		"layout 對 V1.3：S02／S03／S04 與全域設定改動 %s；非 S01 的 POI 改動 %s、新增在 S01 之外 %s、順序相同 %s；新增鍵 %s／%s（只允許 s01_ground、s01_candidate）；S01 的 POI 有變 %d 筆、新增 %d 筆" % [
			str(bad), str(other_changed), str(new_outside), str(ord_b == ord_c), str(top_extra), str(forest_extra), changed_s01.size(), new_pois.size()])


# ================================================================= S01 地形與碰撞不變
func _g_s01_terrain_locked() -> void:
	var man := _load_manifest()
	var lk: Dictionary = man.get("s01_locked", {})
	var shape_rel := "maps/beast_path/gen/s01_terrain_shape.res"
	var shape_ok: bool = lk.has(shape_rel) and FileAccess.get_sha256("res://" + shape_rel) == String(lk[shape_rel])
	var geom := _mesh_geom_sha("res://maps/beast_path/gen/s01_terrain.res")
	var geom_ok: bool = lk.has("terrain_geom_sha") and geom == String(lk["terrain_geom_sha"])
	v._gate("isolation.s01_terrain_locked", shape_ok and geom_ok,
		"S01 地形碰撞檔 s01_terrain_shape.res 與 V1.3 逐位元相同 %s；S01 地形網格的頂點位置＋法線＋索引雜湊與 V1.3 相同 %s（本輪只動地表著色，不動高度與碰撞）" % [str(shape_ok), str(geom_ok)])


# ================================================================= S01 候選植被規劃
func _g_s01_candidate() -> void:
	var F: Dictionary = lib.L["forest"]
	var cand: Dictionary = F.get("s01_candidate", {})
	var mode := String(cand.get("mode", ""))
	var plan_all := _read_plan()
	var plan_s01 := _scene_of(plan_all, "S01")
	v._gate("s01.candidate_declared", bool(cand.get("enabled", false)) and (mode == "replay" or mode == "r1" or (mode == "r2" and cand.get("r2", {}) is Dictionary and not (cand.get("r2", {}) as Dictionary).is_empty())) and not (F["freeze"]["scenes"] as Array).has("S01"),
		"S01 候選 mode＝%s、round＝%s；現行凍結區 %s；forest_plan.json 的 S01 %d 筆" % [mode, String(cand.get("round", "")), str(F["freeze"]["scenes"]), plan_s01.size()])
	# (a) 同 seed 可重現：用生成器存下的規劃輸入（道具腳印）重算兩次，必須逐筆相同，且等於 forest_plan.json 與場景裡實際的 Forest
	var jf: Variant = JSON.parse_string(FileAccess.get_file_as_string(INPUTS))
	var foot: Array = []
	if jf is Dictionary:
		for e: Dictionary in jf["footprints"]:
			foot.append({"id": String(e["id"]), "p": Vector2(float(e["p"][0]), float(e["p"][1])), "r": float(e["r"])})
	var pa := ForestPlanner.new()
	pa.setup(lib, foot)
	pa.plan()
	var pb := ForestPlanner.new()
	pb.setup(lib, foot)
	pb.plan()
	var ea := _scene_of(pa.trees, "S01")
	var eb := _scene_of(pb.trees, "S01")
	var d_ab := 0
	var d_plan := 0
	if ea.size() != eb.size():
		d_ab = absi(ea.size() - eb.size())
	else:
		for i in ea.size():
			if not _eq(_snap(ea[i]), _snap(eb[i])):
				d_ab += 1
	if ea.size() != plan_s01.size():
		d_plan = absi(ea.size() - plan_s01.size())
	else:
		for i in ea.size():
			if not _eq(_snap(ea[i]), plan_s01[i]):
				d_plan += 1
	v._gate("s01.candidate_reproducible", jf is Dictionary and pa.freeze_error == "" and pb.freeze_error == "" and d_ab == 0 and d_plan == 0 and ea.size() > 0,
		"S01 候選（%d 筆）以相同輸入與 seed 規劃兩次：不同 %d 筆（要求 0）；與 forest_plan.json 逐筆比對不同 %d 筆（要求 0）；規劃輸入 %s" % [ea.size(), d_ab, d_plan, "已讀到 %d 個道具腳印" % foot.size() if jf is Dictionary else "讀不到 " + INPUTS])
	# (b) 場景裡 S01 Forest 的實例 transform ＝ 規劃（有 xf 用 xf，沒有用 x／y／z／yaw／s）
	var s1: Node = null
	for f in inst.find_children("Forest", "Node3D", true, false):
		if String((f as Node).get_parent().get_meta("bp_scene", "")) == "S01":
			s1 = f
	var diff_scene := 0
	var worst := 0.0
	if s1 == null or s1.get_child_count() != ea.size():
		diff_scene = -1
	else:
		for i in ea.size():
			var n3 := s1.get_child(i) as Node3D
			var t: Dictionary = ea[i]
			var exp: Array = _expected_xf(t)
			var tb := n3.transform.basis
			var to := n3.transform.origin
			var got := [tb.x.x, tb.y.x, tb.z.x, tb.x.y, tb.y.y, tb.z.y, tb.x.z, tb.y.z, tb.z.z, to.x, to.y, to.z]
			var bad := false
			for k in 12:
				var d := absf(float(got[k]) - float(exp[k]))
				worst = maxf(worst, d)
				if d > 2e-4 * maxf(1.0, absf(float(exp[k]))):
					bad = true
			if bad or not String(n3.name).begins_with(String(t["id"]) + "_"):
				diff_scene += 1
	v._gate("s01.scene_equals_plan", diff_scene == 0, "S01 場景裡 %d 棵植被的 transform 與候選規劃不同 %s 棵；最大數值差 %f" % [ea.size(), "（數量不符）" if diff_scene < 0 else str(diff_scene), worst])
	# (b2) 微傾的語意檢查（不靠 _expected_xf，獨立）：實際實例的『上方向』水平分量＝規劃的傾向 (−lean[1], lean[0])，傾角＝lean[2]
	var n_lean := 0
	var bad_lean := 0
	var worst_dir := 0.0
	var worst_ang := 0.0
	if s1 != null and s1.get_child_count() == ea.size():
		for i2 in ea.size():
			var t2: Dictionary = ea[i2]
			if not t2.has("lean"):
				continue
			n_lean += 1
			var up: Vector3 = ((s1.get_child(i2) as Node3D).transform.basis.y).normalized()
			var ln2: Array = t2["lean"]
			var want_dir := Vector2(-float(ln2[1]), float(ln2[0])).normalized()
			var got_h := Vector2(up.x, up.z)
			var ang_got := acos(clampf(up.y, -1.0, 1.0))
			var d_dir := 0.0 if got_h.length() < 1e-6 else (got_h.normalized() - want_dir).length()
			var d_ang := absf(ang_got - float(ln2[2]))
			worst_dir = maxf(worst_dir, d_dir)
			worst_ang = maxf(worst_ang, d_ang)
			if d_dir > 2e-3 or d_ang > 2e-3:
				bad_lean += 1
	v._gate("s01.lean_semantics", n_lean > 0 and bad_lean == 0, "微傾的樹 %d 棵：傾向／傾角與規劃不符 %d 棵（要求 0）；傾向最大差 %.5f、傾角最大差 %.5f rad；設定的最大傾角 %.1f°" % [n_lean, bad_lean, worst_dir, worst_ang, float(F["s01_candidate"].get("lean_max_deg", 0.0))])
	# (c) replay：S01 必須逐筆等於 V0.1 凍結檔的 S01（含場景存檔 xf）——工程隔離的『零變化』對照
	var fz: Dictionary = F["freeze"]
	var src: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(fz["file"])))
	var v01: Array = (src as Dictionary)["scenes"]["S01"] if src is Dictionary else []
	if mode == "replay":
		var d_rep := 0
		if v01.size() != ea.size():
			d_rep = absi(v01.size() - ea.size())
		else:
			for i in v01.size():
				var xa: Array = (v01[i] as Dictionary)["xf"]
				var xb: Array = _expected_xf(ea[i])
				if not _eq(_snap(ea[i]), v01[i]):
					d_rep += 1
					continue
				for k in 12:
					if absf(float(xa[k]) - float(xb[k])) > 1e-9:
						d_rep += 1
						break
		v._gate("s01.replay_equals_v01", d_rep == 0 and v01.size() == 380, "replay 模式：S01 %d 筆與 V0.1 凍結檔（%d 筆）逐筆（含 xf）比對不同 %d 筆" % [ea.size(), v01.size(), d_rep])
	# (d) 數量：第一輪維持約 380；超過 +10 % 需先提理由與效能預估
	var cnt := {"tree": 0, "pin": 0, "under": 0, "dead": 0, "bamboo": 0}
	for t2: Dictionary in ea:
		cnt[String(t2["kind"])] = int(cnt.get(String(t2["kind"]), 0)) + 1
	var n := ea.size()
	v._gate("s01.count_budget", count_in_budget(n), "S01 植被 %d 筆（V0.1 基準 380；允許 %d–%d＝−5 %%…+10 %%，超過要先提理由）：%s" % [n, BUDGET_MIN, BUDGET_MAX, str(cnt)])


## 規劃條目在場景裡應有的 transform（12 個數：列優先 3×3＋原點）。凍結來源的條目用存檔的 xf；其餘依 x／y／z／yaw／s（候選可帶 lean）。
func _expected_xf(t: Dictionary) -> Array:
	if t.has("xf"):
		return t["xf"]
	var b := Basis(Vector3.UP, float(t["yaw"]))
	if t.has("lean"):
		# 與 generate_beast_path.gd 同一個合成順序：樹先繞自己的垂直軸轉 yaw，再在世界座標裡傾斜（傾向不會被 yaw 轉走），最後縮放
		var ln: Array = t["lean"]
		if Vector2(float(ln[0]), float(ln[1])).length() > 1e-9:
			b = Basis(Vector3(float(ln[0]), 0.0, float(ln[1])).normalized(), float(ln[2])) * b
	b = b.scaled(Vector3.ONE * float(t["s"]))
	return [b.x.x, b.y.x, b.z.x, b.x.y, b.y.y, b.z.y, b.x.z, b.y.z, b.z.z, float(t["x"]), float(t["y"]), float(t["z"])]


# ================================================================= S01 R2（mode＝r2 才檢查；R1／replay 只記資訊）
## R2 新增的東西各自一道 Gate：谷壁點綴＝規劃可重現、落地（不懸空）、不進路／溪／鋪石、只在 S01（不過 z＝−100 接縫）、
## 碰撞只給玩家走得到的凸出岩；釘點櫻＝五棵都在、種類與大小不變、位移有上限、不是任何 POI 的錨點；總量＝380。
## pa_override：反向測試可注入一個已規劃好的 ForestPlanner（不設＝當場規劃一次）。
var pa_override: RefCounted = null
const R2_PIN_MAX_MOVE := 6.0        # 釘點櫻位移上限（m）：使用者 R2 §7「小幅位移」；超過要另提影響評估
const R2_COLLIDE_MAX := 40          # 谷壁點綴碰撞體上限（使用者：不要加不必要的碰撞物）


func _s01_root() -> Node:
	for n in inst.find_children("*", "Node3D", true, false):
		if String((n as Node).get_meta("bp_scene", "")) == "S01":
			return n
	return null


func _rock_world_pts(r: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var mi := r.get_node_or_null("Mesh") as MeshInstance3D
	if mi == null or mi.mesh == null:
		return out
	var arr := mi.mesh.surface_get_arrays(0)
	for q: Vector3 in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		out.append(r.transform * (mi.transform * q))
	return out


func _g_s01_r2() -> void:
	var F: Dictionary = lib.L["forest"]
	var cand: Dictionary = F.get("s01_candidate", {})
	if String(cand.get("mode", "")) != "r2":
		v._info("s01r2.skipped", "S01 候選 mode＝%s：R2 Gate 不適用（R2 的谷壁點綴與釘點位移不存在）" % String(cand.get("mode", "")))
		return
	var r2: Dictionary = cand["r2"]
	var pa: RefCounted = pa_override
	if pa == null:
		var jf: Variant = JSON.parse_string(FileAccess.get_file_as_string(INPUTS))
		var foot: Array = []
		for e: Dictionary in (jf as Dictionary)["footprints"]:
			foot.append({"id": String(e["id"]), "p": Vector2(float(e["p"][0]), float(e["p"][1])), "r": float(e["r"])})
		pa = ForestPlanner.new()
		pa.setup(lib, foot)
		pa.plan()
	var wall: Dictionary = pa.s01_wall
	var s1r := _s01_root()
	var wd: Node = s1r.find_child("WallDressing", false, false) if s1r != null else null
	var rocks_n: Node = wd.get_node_or_null("Rocks") if wd != null else null
	# ---- (1) 規劃可重現：場景裡的每顆岩＝規劃（名稱、transform），埋掉的（露出太少）規劃也不建
	var want := {}
	var n_plan := 0
	for r: Dictionary in wall.get("rocks", []):
		var geo := S01Wall.rock_geom(lib, r)
		var deb := String(r["kind"]) == "debris"
		n_plan += 1
		if float(geo["vis_h"]) < (0.08 if deb else 0.35):
			continue
		want[String(r["id"])] = geo["xf"]
	var bad_xf := 0
	var extra := 0
	var worst := 0.0
	var seen := {}
	if rocks_n != null:
		for c in rocks_n.get_children():
			var nm := String(c.name)
			if not want.has(nm):
				extra += 1
				continue
			seen[nm] = true
			var a: Transform3D = (c as Node3D).transform
			var b: Transform3D = want[nm]
			var d := maxf(a.origin.distance_to(b.origin), maxf((a.basis.x - b.basis.x).length(), maxf((a.basis.y - b.basis.y).length(), (a.basis.z - b.basis.z).length())))
			worst = maxf(worst, d)
			if d > 2e-4:
				bad_xf += 1
	var missing := want.size() - seen.size()
	v._gate("s01r2.wall_matches_plan", rocks_n != null and not want.is_empty() and bad_xf == 0 and extra == 0 and missing == 0,
		"谷壁點綴：規劃 %d 顆（露出夠的 %d 顆）；場景 %d 顆；transform 不符 %d、場景多出 %d、缺少 %d（要求皆 0）；最大差 %.6f" % [n_plan, want.size(), rocks_n.get_child_count() if rocks_n != null else -1, bad_xf, extra, missing, worst])
	# ---- (2)(3)(4) 每顆岩：落地、不進路、只在 S01
	var n_float := 0
	var worst_float := -1e9
	var n_route := 0
	var worst_route := 1e9
	var n_out := 0
	var zmin := 1e9
	var float_ids: Array = []
	var route_ids: Array = []
	if rocks_n != null:
		for c2 in rocks_n.get_children():
			var P := _rock_world_pts(c2 as Node3D)
			var xf2: Transform3D = (c2 as Node3D).transform
			var loc := PackedVector3Array()
			for w: Vector3 in P:
				loc.append(xf2.affine_inverse() * w)
			var mins := S01Wall.sector_min(lib, xf2, loc)
			var wmax := -1e9
			for m: float in mins:
				if m < 1e8:
					wmax = maxf(wmax, m)
			worst_float = maxf(worst_float, wmax)
			if wmax > 0.02:
				n_float += 1
				float_ids.append(String(c2.name))
			var rbad := false
			for w2: Vector3 in P:
				zmin = minf(zmin, w2.z)
				if w2.z < -99.5 or w2.z > 30.0 or absf(w2.x) > 108.0:
					n_out += 1
					break
			for w3: Vector3 in P:
				if w3.y < lib.h_at(w3.x, w3.z) - 0.05:
					continue                                    # 地下的頂點不算（埋在土裡）
				var de := S01Wall.path_edge_d(lib, Vector2(w3.x, w3.z))
				worst_route = minf(worst_route, de)
				if de < 1.0 or lib.sample_arr(lib.DB, w3.x, w3.z) < 1.0 or lib.sample_arr(lib.DS, w3.x, w3.z) < 1.0 or lib.sample_arr(lib.PV, w3.x, w3.z) > 0.05:
					rbad = true
			if rbad:
				n_route += 1
				route_ids.append(String(c2.name))
	v._gate("s01r2.wall_grounded", rocks_n != null and n_float == 0,
		"谷壁點綴 %d 顆：繞岩 16 個方位扇區、每個扇區最低的頂點都要在地面以下（不懸空）；有扇區懸空 > 2 cm 的 %d 顆 %s；最淺扇區最高 %.3f m" % [rocks_n.get_child_count() if rocks_n != null else -1, n_float, str(float_ids.slice(0, 6)), worst_float])
	v._gate("s01r2.wall_clear_of_routes", rocks_n != null and n_route == 0,
		"地面以上的岩頂點離主路路緣 ≥ 1 m、離支線／溪 ≥ 1 m、不在鋪石上：違反 %d 顆 %s；地上頂點離主路路緣最近 %.2f m" % [n_route, str(route_ids.slice(0, 6)), worst_route])
	v._gate("s01r2.wall_in_s01", rocks_n != null and n_out == 0,
		"岩的所有頂點都在 S01（z ∈ [−99.5, 30]、|x| ≤ 108；S01/S02 接縫 z＝−100 不得越過）：越界 %d 顆；最南的頂點 z＝%.2f" % [n_out, zmin])
	# ---- (5) 碰撞：只給玩家走得到、凸出 > 0.45 m 的岩，碎石不給；總數有上限
	var rm := S01Wall.reach_map(lib, float((r2.get("wall", {}) as Dictionary).get("reach_deg", 50.0)))
	var n_body := 0
	var bad_body := 0
	var need_body := 0
	if wd != null:
		for c3 in rocks_n.get_children():
			var bodies := (c3 as Node).find_children("*", "StaticBody3D", true, false)
			n_body += bodies.size()
			var deb2 := String(c3.get_meta("bp_kind", "")) == "debris"
			var P2 := _rock_world_pts(c3 as Node3D)
			var vis := -1e9
			var reach := false
			for w4: Vector3 in P2:
				var hh: float = w4.y - lib.h_at(w4.x, w4.z)
				vis = maxf(vis, hh)
				if hh > 0.2 and S01Wall.reachable(rm, Vector2(w4.x, w4.z)):
					reach = true
			var should := (not deb2) and vis > 0.45 and reach
			if should:
				need_body += 1
			if bodies.size() > 1 or (bodies.size() == 1) != should:
				bad_body += 1
		n_body += wd.find_child("Roots", false, false).find_children("*", "StaticBody3D", true, false).size() if wd.find_child("Roots", false, false) != null else 0
	v._gate("s01r2.wall_collision", wd != null and bad_body == 0 and n_body <= R2_COLLIDE_MAX,
		"谷壁點綴碰撞體 %d 個（上限 %d）；應有碰撞（玩家走得到且凸出 > 0.45 m 的岩）%d 顆；有無碰撞與規則不符 %d 顆（碎石、露根不得有碰撞）" % [n_body, R2_COLLIDE_MAX, need_body, bad_body])
	# ---- (6) 釘點櫻：五棵都在、種類／大小不變、位移 ≤ 上限、不是任何 POI 的錨點
	var pm: Dictionary = r2.get("pin_moves", {})
	var src: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(F["freeze"]["file"])))
	var v01: Array = (src as Dictionary)["scenes"]["S01"] if src is Dictionary else []
	var orig := {}
	for e2: Dictionary in v01:
		if String(e2["kind"]) == "pin" and pm.has(String(e2["pin"])):
			orig[String(e2["pin"])] = e2
	var cur := {}
	for t2: Dictionary in pa.trees:
		if String(t2["scene"]) == "S01" and String(t2["kind"]) == "pin" and pm.has(String(t2["pin"])):
			cur[String(t2["pin"])] = t2
	var anchored: Array = []
	for poi: Dictionary in lib.L["pois"]:
		for b2 in poi.get("between", []):
			if pm.has(String(b2)):
				anchored.append(String(b2))
	var rows: Array = []
	var bad_pin := 0
	var n_pm := 0
	for k: String in pm:
		if k.begins_with("_"):
			continue
		n_pm += 1
		if not orig.has(k) or not cur.has(k):
			bad_pin += 1
			rows.append("%s 缺" % k)
			continue
		var o: Dictionary = orig[k]
		var c4: Dictionary = cur[k]
		var dist := Vector2(float(o["x"]), float(o["z"])).distance_to(Vector2(float(c4["x"]), float(c4["z"])))
		var same := String(o["id"]) == String(c4["id"]) and absf(float(o["s"]) - snappedf(float(c4["s"]), 0.001)) < 1e-6     # 凍結檔的 s 是量化到 0.001 的
		if not same or dist > R2_PIN_MAX_MOVE or lib.scene_id_of_z(float(c4["z"])) != "S01":
			bad_pin += 1
		rows.append("%s %s %.2f m%s" % [k, String(c4["id"]), dist, "" if same else "（種類／大小變了）"])
	v._gate("s01r2.pins_moved_limited", n_pm == 5 and bad_pin == 0 and anchored.is_empty(),
		"釘點櫻 %d 棵（要求 5）：%s；位移上限 %.1f m；不符 %d；被 POI 當錨點的 %s（要求無）" % [n_pm, "，".join(rows), R2_PIN_MAX_MOVE, bad_pin, str(anchored)])
	# ---- (7) 總量：R2 維持 380（使用者 R2 §3）
	var cnt := {"tree": 0, "pin": 0, "under": 0, "dead": 0, "bamboo": 0}
	var n_all := 0
	for t3: Dictionary in pa.trees:
		if String(t3["scene"]) == "S01":
			cnt[String(t3["kind"])] = int(cnt.get(String(t3["kind"]), 0)) + 1
			n_all += 1
	var target := int(cand.get("target_total", 380))
	v._gate("s01r2.total_kept", n_all == target, "S01 植被 %d 筆（R2 要求＝%d，與 R1 相同）：%s" % [n_all, target, str(cnt)])
