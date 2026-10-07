extends RefCounted
## 人間之里 V2 P9 R4-2 Hero Surroundings：神社周邊（鎮守之森／參道）（ART-FIRST）。
##   規劃（plan）＋烘焙（bake）→ maps/village_v2/gen/shrine_grove_p9.scn → village_v2.tscn 掛 Vegetation/ShrineGroveP9
##   （ForestP9 → BambooP9 → HiedaGardenP9 → ShrineGroveP9）。
##   R2 林帶（ForestP9）已封存：本包只「加」不改——讀它的近級樹（位置／樹幹半徑／樹冠）當障礙，在它留下的空間補鎮守林。
##   重用（只讀）：R1 樹庫 prefab（杉 A／B／C、檜、御神木杉、椎、若杉、灌木／笹／蕨、倒木）、R4 garden_kit 春日燈籠、
##   P5 參道鳥居 atlas（注連繩稻草撚紋＋紙垂）、P7 地面 Texture2DArray（新 sg_ground.gdshader 取樣）。
## 構成（參道 HillApproach (300,−130)→(266,−208)、半寬 2.5；參道鳥居 (289.6,−166) yaw 22°；山頂社殿 (258, 34.17, −228)）：
##   1 鳥居＝結界：鳥居後方左右一對大杉（門杉）＋林緣在鳥居處收攏（鳥居以南仍是草地，鳥居以北進入杉林）。
##   2 參道兩側鎮守林：近路一列（杉為主、檜少量）＋後列（杉／椎／若杉），不等距、不同種連排 ≤ 2；樹幹離路緣 ≥ 1.2 m。
##   3 視線：鳥居外（村側）1.7 m 眼高望社殿屋頂／屋身不被新樹擋；R2 的社殿背景天窗（FLib.back_cap）照守。
##   4 御神木：前庭西緣一株御神木杉＋注連繩（依樹幹實際截面繞一圈）＋紙垂；根元苔。
##   5 石燈籠：鳥居前一對、拜殿前一對（社殿整平面上）。
##   6 林下：蕨／笹／灌木／若杉成叢、倒木；地面 overlay：參道肩＝踏み固め土→苔→落葉，林內＝落葉＋苔，前庭＝玉砂利。
##   7 社殿周邊留白：拜殿前前庭（FORECOURT）不種樹、不放灌木（只有燈籠），樹冠投影覆蓋 ≤ 上限。

const TreeLib := preload("res://tools/village_v2_veg_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const FLib := preload("res://tools/village_v2_forest_lib.gd")
const GL := preload("res://tools/village_v2_hieda_garden_lib.gd")

const OUTPUT := "res://maps/village_v2/gen/shrine_grove_p9.scn"
const NODE_NAME := "ShrineGroveP9"
const TREES := "res://assets/village_v2/veg_kit/trees/"
const GK := "res://assets/village_v2/garden_kit/mesh/"
const SG_SHADER := "res://assets/village_v2/shrine_grove/sg_ground.gdshader"
const ROPE_MAT := "res://assets/village_v2/sando_torii/V2_SandoTorii.tres"
const SEED := 4421
const LOD_SWITCH := 38.0

## 地標幾何（實測：Landmarks/*/Hero 可見網格 AABB）
const TORII := Vector2(289.6, -166.0)
const TORII_BOX := Rect2(286.45, -167.55, 6.3, 3.1)
const SHRINE_C := Vector2(258.0, -228.0)
const SHRINE_BOX := Rect2(251.17, -232.53, 13.66, 9.5)
const SHRINE_ROOF := Vector3(258.0, 42.39, -227.78)
const SHRINE_BODY := Vector3(258.0, 38.69, -227.78)
const TEMPLE_BOX := Rect2(219.0, -176.0, 18.0, 12.0)
const ROAD_HW := 2.5
## 前庭（神域留白）：拜殿正面 → 參道終點
const FORECOURT := [Vector2(249.0, -223.2), Vector2(267.0, -223.2), Vector2(269.0, -213.0), Vector2(265.5, -206.5),
	Vector2(256.0, -207.5), Vector2(248.0, -214.5)]
const VOID_MAX := 0.15
## 御神木杉（前庭西緣）
## 北丘頂はどこも 20–30° の斜面：板根の張った御神木杉は谷側の根張り底面を地形に沿わせる（conform_y）と中心が埋まる。
## 候補地探索（探針、8 方位 yaw）で埋深最小＝前庭東縁 (271,−223) yaw 0（1.26 m）。注連繩は山側地面から胸〜頭の高さ。
const GOSHIN := Vector2(271.0, -223.0)
const GOSHIN_YAW := 0.0
const ROPE_ABOVE := 1.65
const ROPE_H := 2.45
## 視線機位（xz、眼高 1.7）：鳥居外村側、鳥居前
const SIGHT_CAMS := [Vector2(296.5, -142.0), Vector2(293.0, -152.0), Vector2(318.0, -112.0), Vector2(305.0, -118.0)]
## 規劃範圍
const REGION := Rect2(228.0, -262.0, 98.0, 126.0)

const ROW1_MIX := {"sugi_a": 30, "sugi_c": 26, "sugi_b": 18, "hinoki_a": 5, "hinoki_b": 5, "young_sugi": 8, "shii_a": 6}
const ROW2_MIX := {"sugi_a": 18, "sugi_c": 16, "sugi_b": 10, "hinoki_a": 4, "hinoki_b": 4, "shii_a": 18, "young_sugi": 16,
	"momiji_b": 3}
const UNDER_MIX := {"fern_a": 34, "sasa_a": 22, "shrub_a": 24, "young_sugi": 10, "tsutsuji_a": 4}
const CONIFER := ["sugi_a", "sugi_b", "sugi_c", "hinoki_a", "hinoki_b", "sugi_hero", "young_sugi"]
const UNDER_IDS := ["fern_a", "sasa_a", "shrub_a", "tsutsuji_a"]
const SC_RANGE := {"sugi_a": [0.82, 1.06], "sugi_b": [0.85, 1.08], "sugi_c": [0.9, 1.15], "hinoki_a": [0.85, 1.0],
	"hinoki_b": [0.8, 0.95], "young_sugi": [0.8, 1.25], "shii_a": [0.7, 0.95], "momiji_b": [0.7, 0.85], "fern_a": [0.8, 1.2],
	"sasa_a": [0.7, 1.05], "shrub_a": [0.75, 1.2], "tsutsuji_a": [0.7, 0.95], "log_a": [0.8, 1.0], "sugi_hero": [1.0, 1.0]}


# ─────────────────────────── 幾何 ───────────────────────────

static func road_pts(L: Dictionary) -> Array:
	for r: Dictionary in L["roads"]:
		if String(r["name"]) == "HillApproach":
			var out: Array = []
			for q: Array in r["pts"]:
				out.append(Vector2(float(q[0]), float(q[1])))
			return out
	return []


static func ground(S: RLib.TriSampler, p: Vector2, r: float) -> float:
	return GL.ground(S, p, r)


## 路面外的距離（＜0＝在路上）
static func road_e(road: Array, p: Vector2) -> float:
	return GL.line_d(road, p).x - ROAD_HW


## 沿路弧長（投影）
static func arc_of(road: Array, p: Vector2) -> float:
	var best := INF
	var acc := 0.0
	var out := 0.0
	for i in road.size() - 1:
		var a: Vector2 = road[i]
		var b: Vector2 = road[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			out = acc + ab.length() * t
		acc += ab.length()
	return out


static func in_poly(poly: Array, p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, PackedVector2Array(poly))


## 樹冠近似圓柱（世界）：[中心 xz, 半徑, y0, y1]
static func crown_cyl(it: Dictionary, M: Dictionary) -> Array:
	var id := String(it["id"])
	var sc: float = (it["sc"] as Vector3).x
	var info: Dictionary = M.get(id, {})
	var h := float(info.get("height", 2.0)) * sc
	var cr := float(info.get("crown_w", 2.0)) * 0.5 * sc
	var y := float(it["y"])
	var base := 0.22 if id.begins_with("sugi") or id.begins_with("hinoki") or id == "young_sugi" else 0.3
	return [it["p"], cr * 0.95, y + h * base, y + h]


static func trunk_r(id: String, sc: float, M: Dictionary) -> float:
	var col: Array = (M.get(id, {}) as Dictionary).get("collision", [])
	return float(col[0]["r"]) * sc if not col.is_empty() else 0.0


## 線段 a→b 是否穿過樹冠／樹幹圓柱
static func seg_hits(a: Vector3, b: Vector3, cyl: Array) -> bool:
	var c: Vector2 = cyl[0]
	var r: float = cyl[1]
	var n := int(ceil(a.distance_to(b) / 0.5))
	for k in n + 1:
		var q := a.lerp(b, float(k) / n)
		if q.y >= float(cyl[2]) and q.y <= float(cyl[3]) and Vector2(q.x, q.z).distance_to(c) < r:
			return true
	return false


# ─────────────────────────── 既有（封存）障礙 ───────────────────────────

## R2 林帶近級樹：[Vector2, tid, sc, layer, trunk_r, crown_r, height]
static func sealed_trees(v: Node3D, M: Dictionary) -> Array:
	var out: Array = []
	var fo := v.get_node_or_null("Vegetation/" + FLib.NODE_NAME)
	if fo == null:
		return out
	for t in fo.get_node("Near").find_children("*", "Node3D", true, false):
		if not t.has_meta("veg_id"):
			continue
		var n := t as Node3D
		var p := Vector2(n.global_position.x, n.global_position.z)
		if not REGION.grow(12.0).has_point(p):
			continue
		var tid := String(n.get_meta("veg_id"))
		var sc := n.global_transform.basis.get_scale().x
		out.append([p, tid, sc, String(n.get_meta("layer")), trunk_r(tid, sc, M),
			float(M[tid]["crown_w"]) * 0.5 * sc, float(M[tid]["height"]) * sc])
	return out


## 建物 footprint（Districts／Landmarks 有體積的網格，REGION 內）
static func building_rects(v: Node3D) -> Array:
	var out: Array = []
	for top: String in ["Districts", "Landmarks"]:
		var root := v.get_node_or_null(top)
		if root == null:
			continue
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if not g.is_visible_in_tree():
				continue
			var a := g.global_transform * g.get_aabb()
			if a.size.y < 1.0 or a.size.x > 60.0 or a.size.z > 60.0:
				continue
			var r := Rect2(a.position.x, a.position.z, a.size.x, a.size.z)
			if REGION.grow(10.0).intersects(r):
				out.append(r)
	return out


# ─────────────────────────── 規劃 ───────────────────────────

static func _pick(rng: RandomNumberGenerator, w: Dictionary, avoid: Array = []) -> String:
	var tot := 0.0
	for k: String in w:
		if not (k in avoid):
			tot += float(w[k])
	var x := rng.randf() * tot
	for k: String in w:
		if k in avoid:
			continue
		x -= float(w[k])
		if x <= 0.0:
			return k
	return String(w.keys()[0])


## 接地環半徑：樹＝實際樹幹半徑＋0.12（30° 坡上用樹冠尺度會整棵埋太深）、林下＝0.25、構件＝0.38×
static func foot_r(kind: String, id: String, sc: float) -> float:
	if kind != "tree":
		return 0.38 * sc
	if id in UNDER_IDS:
		return 0.25
	var M := FLib.modules()
	return maxf(trunk_r(id, sc, M) * 0.7, 0.12) if M.has(id) else 0.3


static func item(S: RLib.TriSampler, kind: String, id: String, p: Vector2, yaw: float, sc: float, tag: String,
		extra := {}) -> Dictionary:
	var r := foot_r(kind, id, sc)
	var y := ground(S, p, r) - (0.06 if kind == "tree" else 0.0)
	var it := {"kind": kind, "id": id, "p": p, "y": y, "yaw": yaw, "sc": Vector3.ONE * sc, "tag": tag}
	it.merge(extra, true)
	return it


class Ctx:
	var S: RLib.TriSampler
	var M: Dictionary
	var road: Array
	var sealed: Array
	var bld: Array
	var items: Array = []
	var cams: Array = []          # Vector3（眼高）
	var targets: Array = []       # Vector3
	var rejects := {}


static func _reject(C: Ctx, why: String) -> String:
	C.rejects[why] = int(C.rejects.get(why, 0)) + 1
	return why


## 可否種樹（空字串＝可）
static func tree_ok(C: Ctx, it: Dictionary) -> String:
	var p: Vector2 = it["p"]
	var id := String(it["id"])
	var sc: float = (it["sc"] as Vector3).x
	var under := id in UNDER_IDS
	var tr := trunk_r(id, sc, C.M)
	var cr := float(C.M[id]["crown_w"]) * 0.5 * sc
	if not REGION.has_point(p):
		return _reject(C, "region")
	# 切土法面・急斜面（中心が環最低より 0.4 m 以上高い）には植えない
	if C.S.h(p.x, p.y) - float(it["y"]) > 0.4:
		return _reject(C, "steep")
	var e := road_e(C.road, p)
	if e < (0.45 + cr * 0.4 if under else 1.2 + tr):
		return _reject(C, "road")
	if in_poly(FORECOURT, p) or GL.poly_d(PackedVector2Array(FORECOURT), p) < (0.3 if under else 1.0 + tr):
		return _reject(C, "void")
	if TORII_BOX.grow(2.0).has_point(p) or SHRINE_BOX.grow(3.0).has_point(p) or TEMPLE_BOX.grow(4.0).has_point(p):
		return _reject(C, "landmark")
	for r: Rect2 in C.bld:
		if r.grow(2.5).has_point(p):
			return _reject(C, "building")
	for t: Array in C.sealed:
		var d := p.distance_to(t[0])
		if d > 14.0:
			continue
		if float(t[4]) > 0.0 and d < float(t[4]) + tr + (0.6 if under else 1.2):
			return _reject(C, "sealed_trunk")
		if not under and not it.get("hero", false) and not (String(t[3]) in ["under"]) and d < (0.3 if id in CONIFER else 0.42) * (cr + float(t[5])):
			return _reject(C, "sealed_crown")
		if under and String(t[1]) in UNDER_IDS and d < 1.1:
			return _reject(C, "sealed_under")
	for o: Dictionary in C.items:
		if String(o["kind"]) != "tree":
			continue
		var d := p.distance_to(o["p"])
		if d > 14.0:
			continue
		var oid := String(o["id"])
		var osc: float = (o["sc"] as Vector3).x
		var otr := trunk_r(oid, osc, C.M)
		var ocr := float(C.M[oid]["crown_w"]) * 0.5 * osc
		var ounder := oid in UNDER_IDS
		if (tr > 0.0 or otr > 0.0) and d < tr + otr + (0.5 if under or ounder else 1.4):
			return _reject(C, "own_trunk")
		if not under and not ounder and d < 0.45 * (cr + ocr):
			return _reject(C, "own_crown")
		if under and ounder and d < 0.7 * (cr + ocr):
			return _reject(C, "own_under")
	if not under:
		var cyl := crown_cyl(it, C.M)
		var tcyl := [p, tr + 0.05, float(it["y"]), float(it["y"]) + float(C.M[id]["height"]) * sc * 0.4]
		for cam: Vector3 in C.cams:
			for tg: Vector3 in C.targets:
				if seg_hits(cam, tg, cyl) or seg_hits(cam, tg, tcyl):
					return _reject(C, "sightline")
	return ""


## 高度上限：R2 社殿背景天窗
static func fit_height(C: Ctx, it: Dictionary) -> bool:
	var id := String(it["id"])
	if id in UNDER_IDS:
		return true
	var p: Vector2 = it["p"]
	var cap := FLib.back_cap(p, SHRINE_ROOF)
	if cap == INF:
		return true
	var h := float(C.M[id]["height"])
	var allow := cap - float(it["y"])
	var sc: float = (it["sc"] as Vector3).x
	if h * sc <= allow:
		return true
	var s2 := allow / h
	if s2 < 0.6:
		return false
	it["sc"] = Vector3.ONE * s2
	return true


static func _try(C: Ctx, it: Dictionary) -> bool:
	if not fit_height(C, it):
		_reject(C, "back_cap")
		return false
	if tree_ok(C, it) != "":
		return false
	C.items.append(it)
	return true


static func plan(v: Node3D, L: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var C := Ctx.new()
	C.S = RLib.terrain_sampler(v)
	C.M = FLib.modules()
	C.road = road_pts(L)
	C.sealed = sealed_trees(v, C.M)
	C.bld = building_rects(v)
	var S := C.S
	for c: Vector2 in SIGHT_CAMS:
		C.cams.append(Vector3(c.x, S.h(c.x, c.y) + 1.7, c.y))
	C.targets = [SHRINE_ROOF, SHRINE_BODY, SHRINE_BODY + Vector3(-5.0, -0.6, 4.0), SHRINE_BODY + Vector3(5.0, -0.6, 4.0)]
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var nz := FastNoiseLite.new()
	nz.seed = SEED
	nz.frequency = 1.0 / 18.0
	var rs := GL.resample(C.road, 0.25)
	var L_road: float = rs[-1][2]
	var s_torii := arc_of(C.road, TORII)
	# ── 1 門杉：鳥居後方左右一對大杉（結界）＋鳥居處林緣收攏
	var dir_t := (C.road[2] - C.road[1] as Vector2).normalized()
	var n_t := Vector2(-dir_t.y, dir_t.x)
	for sgn: float in [-1.0, 1.0]:
		var p := TORII + dir_t * 1.0 + n_t * sgn * 5.6
		for k in 24:
			var it := item(S, "tree", "sugi_c", p + n_t * sgn * (k % 6) * 0.8 + dir_t * (k / 6) * 1.3,
				rng.randf() * TAU, 1.12 - 0.012 * k, "gate_sugi", {"preset": "deep", "hero": true})
			if _try(C, it):
				break
			elif k == 23:
				print("[SG] gate_sugi side %d：24 候補全部不可（多為村側視線）" % sgn)
	# 鳥居處林緣：左右各一小群（若杉＋灌木＋蕨），把林緣拉到鳥居線
	for sgn: float in [-1.0, 1.0]:
		for k in 7:
			var p := TORII + dir_t * rng.randf_range(-2.0, 3.0) + n_t * sgn * rng.randf_range(9.5, 15.0)
			var id := _pick(rng, {"young_sugi": 30, "shrub_a": 30, "fern_a": 25, "sasa_a": 15})
			var sr: Array = SC_RANGE[id]
			_try(C, item(S, "tree", id, p, rng.randf() * TAU, rng.randf_range(sr[0], sr[1]), "torii_edge"))
	# ── 2 參道兩側鎮守林：近路一列＋後列（不等距；不同種連排 ≤ 2）
	var rows := [[1, ROW1_MIX, Vector2(1.6, 4.6), Vector2(4.2, 9.5), "sando_row1"],
		[2, ROW2_MIX, Vector2(6.5, 12.5), Vector2(6.0, 12.0), "sando_row2"]]
	for row: Array in rows:
		for sgn: float in [-1.0, 1.0]:
			var s := s_torii + 4.5 + rng.randf_range(0.0, 3.0)
			var last: Array = []
			while s < L_road - 1.0:
				var k := clampi(int(s / 0.25), 0, rs.size() - 1)
				var e: Array = rs[k]
				var p0: Vector2 = e[0]
				var d: Vector2 = e[1]
				var nn := Vector2(-d.y, d.x) * sgn
				var mix: Dictionary = row[1]
				var avoid: Array = []
				if last.size() >= 2 and last[-1] == last[-2]:
					avoid = [last[-1]]
				var id := _pick(rng, mix, avoid)
				var sr: Array = SC_RANGE[id]
				var sc := rng.randf_range(sr[0], sr[1])
				var off_r: Vector2 = row[2]
				var ok := false
				for tr_i in 4:
					var off := ROAD_HW + rng.randf_range(off_r.x, off_r.y) + tr_i * 1.2
					var p := p0 + nn * off + d * rng.randf_range(-1.2, 1.2)
					var preset := "deep" if FLib._n01(nz, p.x, p.y) > 0.55 else ("shade" if FLib._n01(nz, p.x + 91.0, p.y) > 0.6 else "mature")
					if _try(C, item(S, "tree", id, p, rng.randf() * TAU, sc, String(row[4]), {"preset": preset, "side": sgn,
							"arc": s})):
						ok = true
						last.append(id)
						break
				var sp: Vector2 = row[3]
				# 間距本身也由低頻雜訊調（成叢／疏處），不是固定節奏
				s += rng.randf_range(sp.x, sp.y) * lerpf(0.75, 1.35, FLib._n01(nz, p0.x * 1.7, p0.y)) * (1.0 if ok else 0.45)
	# 椎（常緑広葉、鎮守林の下層高木）：後列のさらに外に数株
	var n_shii := 0
	for k in 120:
		if n_shii >= 4:
			break
		var s3 := rng.randf_range(s_torii + 8.0, L_road - 6.0)
		var e3: Array = rs[clampi(int(s3 / 0.25), 0, rs.size() - 1)]
		var d3: Vector2 = e3[1]
		var sg3 := 1.0 if k % 2 == 0 else -1.0
		var p3: Vector2 = (e3[0] as Vector2) + Vector2(-d3.y, d3.x) * sg3 * (ROAD_HW + rng.randf_range(6.0, 20.0))
		if _try(C, item(S, "tree", "shii_a", p3, rng.randf() * TAU, rng.randf_range(0.6, 0.85), "sando_row2", {"preset": "deep",
				"side": sg3, "arc": s3})):
			n_shii += 1
	# ── 3 御神木杉＋周り（前庭西緣）
	var gos := item(S, "tree", "sugi_hero", GOSHIN, GOSHIN_YAW, 1.0, "goshinboku", {"preset": "deep"})
	if not fit_height(C, gos):
		_reject(C, "goshin_cap")
	gos["y"] = conform_y(S, gos)
	# 注連繩の局部高さ＝中心埋深＋ROPE_ABOVE（地面から胸〜頭の高さ）
	gos["rope_h"] = S.h(GOSHIN.x, GOSHIN.y) - float(gos["y"]) + ROPE_ABOVE
	C.items.append(gos)
	# ── 4 石燈籠（春日）：鳥居前一對、拜殿前一對
	for sgn: float in [-1.0, 1.0]:
		var p := TORII - dir_t * 3.2 + n_t * sgn * 3.45
		C.items.append(item(S, "mesh", "gk_toro_kasuga", p, atan2(-dir_t.y, dir_t.x) + PI * 0.5 * (1.0 - sgn), 1.12, "lantern"))
	for x: float in [250.1, 265.9]:
		var p := Vector2(x, -224.4)
		C.items.append(item(S, "mesh", "gk_toro_kasuga", p, 0.0, 1.0, "lantern"))
	# ── 5 林下：每棵新樹 1–3 叢（蕨／笹／灌木／若杉），參道肩零星蕨笹；倒木 2
	var canopy := C.items.filter(func(it: Dictionary) -> bool: return String(it["kind"]) == "tree" and not (String(it["id"]) in UNDER_IDS))
	for ct: Dictionary in canopy:
		var n := rng.randi_range(3, 6)
		var a0 := rng.randf() * TAU
		for k in n:
			# 片寄った叢：主方向 ±70° に寄せる（樹の周りに均等散布しない）
			var a := a0 + rng.randf_range(-1.2, 1.2)
			var p: Vector2 = (ct["p"] as Vector2) + Vector2(cos(a), sin(a)) * rng.randf_range(1.2, 4.8)
			var id := _pick(rng, UNDER_MIX)
			var sr: Array = SC_RANGE[id]
			_try(C, item(S, "tree", id, p, rng.randf() * TAU, rng.randf_range(sr[0], sr[1]), "under"))
	# R2 既存高木の根元にも林下叢（新樹だけでなく林全体の地被を揃える）
	for t: Array in C.sealed:
		if String(t[3]) == "under" or float(t[6]) < 8.0:
			continue
		var pt: Vector2 = t[0]
		var e0 := road_e(C.road, pt)
		if e0 > 16.0 or arc_of(C.road, pt) < s_torii - 2.0:
			continue
		var a0 := rng.randf() * TAU
		for k in rng.randi_range(1, 3):
			var a := a0 + rng.randf_range(-1.0, 1.0)
			var p: Vector2 = pt + Vector2(cos(a), sin(a)) * rng.randf_range(1.0, 3.8)
			var id := _pick(rng, UNDER_MIX)
			var sr: Array = SC_RANGE[id]
			_try(C, item(S, "tree", id, p, rng.randf() * TAU, rng.randf_range(sr[0], sr[1]), "under"))
	var s2 := s_torii + 2.0
	while s2 < L_road - 2.0:
		var e: Array = rs[clampi(int(s2 / 0.25), 0, rs.size() - 1)]
		var d: Vector2 = e[1]
		var sgn := 1.0 if rng.randf() < 0.5 else -1.0
		var p: Vector2 = (e[0] as Vector2) + Vector2(-d.y, d.x) * sgn * (ROAD_HW + rng.randf_range(0.7, 1.6))
		var id := "fern_a" if rng.randf() < 0.6 else "sasa_a"
		_try(C, item(S, "tree", id, p, rng.randf() * TAU, rng.randf_range(0.7, 1.0), "shoulder"))
		s2 += rng.randf_range(2.5, 6.5)
	# 倒木 2：參道外 6–14 m、最平的地點（環 1.2 m 落差 < 0.3），不放在切土法面
	var n_log := 0
	var cands: Array = []
	for k in 160:
		var sl := rng.randf_range(s_torii + 6.0, L_road - 8.0)
		var el: Array = rs[clampi(int(sl / 0.25), 0, rs.size() - 1)]
		var dl: Vector2 = el[1]
		var sgl := 1.0 if k % 2 == 0 else -1.0
		var pl: Vector2 = (el[0] as Vector2) + Vector2(-dl.y, dl.x) * sgl * (ROAD_HW + rng.randf_range(6.0, 14.0))
		var drop := S.h(pl.x, pl.y) - ground(S, pl, 1.2)
		if drop < 0.42:
			cands.append([drop, pl, atan2(-dl.y, dl.x) + rng.randf_range(-0.5, 0.5)])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for cd: Array in cands:
		if n_log >= 2:
			break
		var it := item(S, "tree", "log_a", cd[1], float(cd[2]), 0.9, "log")
		it["y"] = ground(S, cd[1], 1.2) + 0.02
		var why := tree_ok(C, it)
		if why in ["", "steep", "sealed_crown", "own_crown", "sightline"]:
			C.items.append(it)
			n_log += 1
	# 御神木の根元：苔の上に小さな添石 3（P7 河岸石、只讀）
	for k in 3:
		var a := deg_to_rad(150.0 + k * 55.0)
		var p := GOSHIN + Vector2(cos(a), sin(a)) * rng.randf_range(2.0, 2.6)
		var it := item(S, "mesh", "rb_bld_%s" % "abcde"[k], p, rng.randf() * TAU, rng.randf_range(0.42, 0.55), "goshin_stone")
		it["y"] -= 0.06
		C.items.append(it)
	var rope := rope_plan(gos, C.M)
	return {"items": C.items, "S": S, "road": C.road, "sealed": C.sealed, "bld": C.bld, "cams": C.cams, "targets": C.targets,
		"rope": rope, "rejects": C.rejects, "ms": Time.get_ticks_msec() - t0, "M": C.M, "s_torii": s_torii, "L_road": L_road}


## 斜面接地（御神木）：根張り底面（樹皮網格 local y < 0.25）の全頂點が地形以下になる高さ（谷側が浮かない、山側は埋まる）
static func flare_verts(id: String) -> PackedVector3Array:
	var t: Node3D = (load(TREES + id + ".tscn") as PackedScene).instantiate()
	var V: PackedVector3Array = ((t.get_node("LOD0") as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	t.free()
	var out := PackedVector3Array()
	for q in V:
		if q.y < 0.25:
			out.append(q)
	return out


static func conform_y(S: RLib.TriSampler, it: Dictionary) -> float:
	var xf := xf_of(it)
	var worst := -INF
	for q in flare_verts(String(it["id"])):
		var w := xf * q
		worst = maxf(worst, w.y - S.h(w.x, w.z))
	return float(it["y"]) - worst - 0.03


# ─────────────────────────── 注連繩（依御神木樹幹實際截面） ───────────────────────────

const ROPE_BINS := 36
const ROPE_R := 0.11


## 樹幹截面（局部、高度 ROPE_H）：樹皮 surface 三角面與水平面 y＝ROPE_H 的交線＝實際外形；
## 中心＝交線端點重心（迭代、只取 1.8 m 內），每 10° 由中心往外的射線取「最外側」交點 → 繩一定在樹皮外。
## 枝／斷枝伸出的交點以全體中位數 1.6 倍夾住（繩不繞去枝端）。回傳 [中心, 半徑[ROPE_BINS], 中位數]
static func trunk_profile(id: String, rope_h := ROPE_H) -> Array:
	var t: Node3D = (load(TREES + id + ".tscn") as PackedScene).instantiate()
	var am := (t.get_node("LOD0") as MeshInstance3D).mesh as ArrayMesh
	var arr := am.surface_get_arrays(0)
	t.free()
	var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var I: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var segs: Array = []
	for k in range(0, I.size(), 3):
		var tri := [V[I[k]], V[I[k + 1]], V[I[k + 2]]]
		var pts: Array = []
		for e in 3:
			var a: Vector3 = tri[e]
			var b: Vector3 = tri[(e + 1) % 3]
			if (a.y - rope_h) * (b.y - rope_h) < 0.0:
				var q := a.lerp(b, (rope_h - a.y) / (b.y - a.y))
				pts.append(Vector2(q.x, q.z))
		if pts.size() == 2:
			segs.append(pts)
	var M := FLib.modules()
	var col: Dictionary = (M[id]["collision"] as Array)[0]
	var ca := Vector3(col["a"][0], col["a"][1], col["a"][2])
	var cb := Vector3(col["b"][0], col["b"][1], col["b"][2])
	var c3 := ca.lerp(cb, (rope_h - ca.y) / (cb.y - ca.y))
	var c := Vector2(c3.x, c3.z)
	for it in 4:
		var acc := Vector2.ZERO
		var n := 0
		for sg: Array in segs:
			for q: Vector2 in sg:
				if q.distance_to(c) < 1.8:
					acc += q
					n += 1
		if n > 0:
			c = acc / n
	var prof: Array = []
	for k in ROPE_BINS:
		var ang := (k + 0.5) / ROPE_BINS * TAU
		var dir := Vector2(cos(ang), sin(ang))
		var far := -1.0
		for sg: Array in segs:
			var a: Vector2 = sg[0] - c
			var b: Vector2 = sg[1] - c
			var e := b - a
			var den := dir.x * e.y - dir.y * e.x
			if absf(den) < 1e-9:
				continue
			var tt := (a.x * e.y - a.y * e.x) / den
			var u := (a.x * dir.y - a.y * dir.x) / den
			if tt > 0.0 and tt < 1.8 and u >= 0.0 and u <= 1.0:
				far = maxf(far, tt)
		prof.append(far)
	var allr: Array = prof.filter(func(r: float) -> bool: return r > 0.0)
	allr.sort()
	var med := float(allr[allr.size() / 2]) if not allr.is_empty() else float(col["r"])
	for k in ROPE_BINS:
		var r := float(prof[k])
		prof[k] = med if r <= 0.0 else minf(r, med * 1.6)
	return [c, prof, med]


static func rope_plan(gos: Dictionary, M: Dictionary) -> Dictionary:
	var rh := float(gos.get("rope_h", ROPE_H))
	var tp := trunk_profile(String(gos["id"]), rh)
	var sc: float = (gos["sc"] as Vector3).x
	var prof: Array = tp[1]
	# 平滑（3 點最大）＋ 繩半徑：繩心＝截面＋繩粗（緊貼，不懸空）
	var pr: Array = []
	for k in ROPE_BINS:
		pr.append(maxf(float(prof[k]), maxf(float(prof[(k + 1) % ROPE_BINS]), float(prof[(k - 1 + ROPE_BINS) % ROPE_BINS])) * 0.96))
	return {"center": tp[0], "prof": pr, "sc": sc, "h": rh, "rope_r": ROPE_R}


## 繩心路徑（世界）：每 bin 一點，局部 → 世界（御神木的 yaw／scale／位置）
static func rope_path(gos: Dictionary, rope: Dictionary) -> Array:
	var xf := xf_of(gos)
	var c: Vector2 = rope["center"]
	var out: Array = []
	for k in ROPE_BINS:
		var a := (k + 0.5) / ROPE_BINS * TAU
		var r := float(rope["prof"][k]) + ROPE_R + 0.025
		# 正面（局部 +z 朝前庭）略垂：繩的自然下垂
		var sag := 0.05 * maxf(0.0, sin(a))
		out.append(xf * Vector3(c.x + cos(a) * r, float(rope["h"]) - sag, c.y + sin(a) * r))
	return out


# ─────────────────────────── 地面 overlay ───────────────────────────

const G_STEP := 0.5
const COR_R := 22.0


## [COLOR(玉砂利, 苔, 土, 落葉), UV2(濕潤, 淡出)]；回傳 null＝範圍外
static func ground_w(P: Dictionary, p: Vector2, trees: Array) -> Variant:
	var road: Array = P["road"]
	var s_t: float = P["s_torii"]
	var ld := GL.line_d(road, p)
	var arc := arc_of(road, p)
	var e := ld.x - ROAD_HW
	var f := 0.0
	# 參道帶：鳥居南 6 m 起到終點、兩側 COR_R
	var f_cor := clampf((COR_R - ld.x) / 6.0, 0.0, 1.0) * clampf((arc - (s_t - 6.0)) / 4.0, 0.0, 1.0)
	f = maxf(f, f_cor)
	var dpad := Vector2(maxf(maxf(248.0 - p.x, p.x - 268.0), 0.0), maxf(maxf(-236.0 - p.y, p.y + 205.0), 0.0)).length()
	f = maxf(f, clampf((4.0 - dpad) / 3.0, 0.0, 1.0))
	f = maxf(f, clampf((9.0 - p.distance_to(GOSHIN)) / 3.0, 0.0, 1.0))
	f = maxf(f, clampf((13.0 - p.distance_to(Vector2(303.0, -186.0))) / 3.0, 0.0, 1.0))
	if f <= 0.0:
		return null
	var gv := 0.0
	var mo := 0.0
	var so := 0.0
	var li := 0.0
	var wet := 0.12
	var n1 := 0.5 + 0.5 * sin(p.x * 0.37 + p.y * 0.23) * sin(p.x * 0.11 - p.y * 0.41)
	# 林內基底：落葉＋苔斑；鳥居以南（草地）漸淡
	var meadow := clampf((s_t + 1.0 - arc) / 5.0, 0.0, 1.0) if ld.x < COR_R else 0.0
	li = lerpf(0.5 + 0.35 * n1, 0.1, meadow)
	mo = lerpf(0.22 * (1.0 - n1) + 0.1, 0.05, meadow)
	# 樹下：落葉更多、樹幹根元苔
	for t: Array in trees:
		var d := p.distance_to(t[0])
		if d < float(t[1]):
			li = maxf(li, 0.75)
		if d < float(t[2]) + 1.2:
			mo = maxf(mo, 0.6 * (1.0 - d / (float(t[2]) + 1.2)) + 0.25)
			wet = 0.22
	# 參道終點：道路 decal の端（硬い切り口）を踏み固め土の広がりで受ける
	var L_r: float = P["L_road"]
	var end_d := p.distance_to(road[-1])
	if end_d < 4.5 and arc > L_r - 3.0:
		var t0 := smoothstep(4.5, 1.5, end_d + 0.6 * sin(p.x * 1.7 + p.y))
		so = maxf(so, 0.75 * t0)
		li *= 1.0 - 0.7 * t0
	# 參道肩：踏み固め土 → 苔 → 落葉
	if e < 0.7:
		so = 0.6
		li = 0.35
		mo = 0.05
	elif e < 2.2:
		var t := (e - 0.7) / 1.5
		mo = maxf(mo, lerpf(0.6, 0.3, t))
		li = maxf(li * t, 0.3)
		so = 0.15 * (1.0 - t)
	# 前庭＝玉砂利（縁 0.6 m 苔）；整平面其餘＝土＋苔
	# 前庭＝玉砂利：境界を雜訊で崩した符号付き距離（内側＋）→ 1.6 m かけて苔→落葉へ（直線・矩形の縁を出さない）
	var fc := PackedVector2Array(FORECOURT)
	var dd := GL.poly_d(fc, p) * (1.0 if Geometry2D.is_point_in_polygon(p, fc) else -1.0)
	dd += 0.45 * sin(p.x * 0.9 + p.y * 0.4) * sin(p.y * 0.7 - p.x * 0.3) + 0.25 * sin(p.x * 2.3 - p.y * 1.7)
	# 玉砂利は整平面（緩斜面 < 14°）だけ：前庭ポリゴンの斜面部分は苔＋土＋落葉（斜面に砂利を敷かない）
	var flat := smoothstep(11.0, 6.0, float(P.get("_slope", 0.0)) + 2.0 * sin(p.x * 1.3 - p.y * 0.8))
	dd = minf(dd, lerpf(-1.7, dd, flat))
	if dd <= -1.6 and Geometry2D.is_point_in_polygon(p, fc):
		mo = maxf(mo, 0.5)
		so = maxf(so, 0.2)
		li = minf(li, 0.3)
	if dd > -1.6:
		var t := smoothstep(-1.6, 0.6, dd)
		gv = maxf(gv * (1.0 - t), t)
		mo = lerpf(maxf(mo, 0.45), 0.0, t) if dd > -1.2 else mo
		so *= 1.0 - t
		li *= 1.0 - t
		wet = lerpf(wet, 0.0, t)
	# 御神木根元：苔
	var dg := p.distance_to(GOSHIN)
	if dg < 3.6:
		mo = maxf(mo, 0.9 - dg * 0.1)
		li = minf(li, 0.2)
		wet = 0.25
	var tot := gv + mo + so + li
	if tot > 1.0:
		gv /= tot
		mo /= tot
		so /= tot
		li /= tot
	return [Color(gv, mo, so, li), Vector2(wet, f)]


static func sg_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SG_SHADER)
	m.set_shader_parameter("albedo_arr", load("res://assets/village_v2/_matlib/ground/V2G_albedo.jpg"))
	m.set_shader_parameter("nrh_arr", load("res://assets/village_v2/_matlib/ground/V2G_nrh.jpg"))
	m.set_shader_parameter("noise_tex", load("res://assets/village_v2/_matlib/ground/V2G_noise.png"))
	m.resource_name = "SG_Ground"
	return m


static func ground_mesh(P: Dictionary) -> ArrayMesh:
	var S: RLib.TriSampler = P["S"]
	var road: Array = P["road"]
	var M: Dictionary = P["M"]
	var trees: Array = []
	for it: Dictionary in P["items"]:
		if String(it["kind"]) == "tree" and not (String(it["id"]) in UNDER_IDS) and String(it["id"]) != "log_a":
			var sc: float = (it["sc"] as Vector3).x
			trees.append([it["p"], float(M[it["id"]]["crown_w"]) * 0.45 * sc, trunk_r(String(it["id"]), sc, M)])
	for t: Array in P["sealed"]:
		if String(t[3]) != "under" and float(t[4]) > 0.0:
			trees.append([t[0], float(t[5]) * 0.9, float(t[4])])
	var nx := int(ceil(REGION.size.x / G_STEP))
	var nz := int(ceil(REGION.size.y / G_STEP))
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var Cc := PackedColorArray()
	var U2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var vid := {}
	var near_t := {}
	for t: Array in trees:
		var k := Vector2i(floori((t[0] as Vector2).x / 8.0), floori((t[0] as Vector2).y / 8.0))
		if not near_t.has(k):
			near_t[k] = []
		(near_t[k] as Array).append(t)
	for j in nz + 1:
		for i in nx + 1:
			var p := REGION.position + Vector2(i * G_STEP, j * G_STEP)
			var h := S.h(p.x, p.y)
			if is_nan(h):
				continue
			var loc: Array = []
			var k0 := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
			for dj in range(-2, 3):
				for di in range(-2, 3):
					loc.append_array(near_t.get(k0 + Vector2i(di, dj), []))
			var sx := S.h(p.x + 0.5, p.y) - S.h(p.x - 0.5, p.y)
			var sz := S.h(p.x, p.y + 0.5) - S.h(p.x, p.y - 0.5)
			P["_slope"] = rad_to_deg(atan(Vector2(sx, sz).length()))
			var w: Variant = ground_w(P, p, loc)
			if w == null:
				continue
			var e := road_e(road, p)
			# 路下：壓低到 P5 道路 decal 之下（decal 離地 ≥ 0.014）
			var lift := lerpf(0.004, 0.016, clampf(e / 0.6, 0.0, 1.0))
			var d := 0.5
			var nrm := Vector3(S.h(p.x - d, p.y) - S.h(p.x + d, p.y), 2.0 * d, S.h(p.x, p.y - d) - S.h(p.x, p.y + d))
			vid[Vector2i(i, j)] = V.size()
			V.append(Vector3(p.x, h + lift, p.y))
			N.append(nrm.normalized() if nrm.is_finite() else Vector3.UP)
			Cc.append((w as Array)[0])
			U2.append((w as Array)[1])
	for j in nz:
		for i in nx:
			var k00: Variant = vid.get(Vector2i(i, j))
			var k10: Variant = vid.get(Vector2i(i + 1, j))
			var k01: Variant = vid.get(Vector2i(i, j + 1))
			var k11: Variant = vid.get(Vector2i(i + 1, j + 1))
			if k00 == null or k10 == null or k01 == null or k11 == null:
				continue
			var c := REGION.position + Vector2((i + 0.5) * G_STEP, (j + 0.5) * G_STEP)
			if SHRINE_BOX.grow(-0.4).has_point(c):
				continue
			if absf(V[k00].y - V[k11].y) <= absf(V[k10].y - V[k01].y):
				idx.append_array([k00, k10, k11, k00, k11, k01])
			else:
				idx.append_array([k00, k10, k01, k10, k11, k01])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_COLOR] = Cc
	arr[Mesh.ARRAY_TEX_UV2] = U2
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.surface_set_material(0, sg_material())
	am.resource_name = "sg_ground"
	return am


# ─────────────────────────── 注連繩網格 ───────────────────────────

static func _quad(V: PackedVector3Array, N: PackedVector3Array, U: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	var n := (b - a).cross(d - a).normalized()
	for t: Array in [[a, b, c, ua, ub, uc], [a, c, d, ua, uc, ud]]:
		for k in 3:
			V.append(t[k])
			N.append(n)
			U.append(t[k + 3])


static func rope_mesh(P: Dictionary) -> ArrayMesh:
	var gos: Dictionary = {}
	for it: Dictionary in P["items"]:
		if String(it["tag"]) == "goshinboku":
			gos = it
	var path := rope_path(gos, P["rope"])
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var U := PackedVector2Array()
	# atlas（P5 參道鳥居，只讀）：rope [0.5,0,1,0.25]、shide [0.5,0.25,0.75,0.5]
	var RU := Vector4(0.5, 0.0, 1.0, 0.25)
	var SU := Vector4(0.5, 0.25, 0.75, 0.5)
	var m := 10
	var n := path.size()
	var ctr := Vector3.ZERO
	for q: Vector3 in path:
		ctr += q
	ctr /= n
	var halves := 3          # 繩一圈分 3 段，各自 u 0..1（atlas 不循環也不拉長）
	for i in n:
		var a: Vector3 = path[i]
		var b: Vector3 = path[(i + 1) % n]
		var ta: Vector3 = (path[(i + 1) % n] - path[(i - 1 + n) % n]).normalized()
		var tb: Vector3 = (path[(i + 2) % n] - path[i]).normalized()
		var seg := int(float(i) / n * halves)
		var u0 := fposmod(float(i) / n * halves, 1.0)
		var u1 := u0 + 1.0 / n * halves
		if int(float(i + 1) / n * halves) != seg and i + 1 < n:
			u1 = 1.0
		for k in m:
			var ang0 := float(k) / m * TAU
			var ang1 := float(k + 1) / m * TAU
			var ra := _ring_pt(a, ta, ctr, ang0)
			var rb := _ring_pt(b, tb, ctr, ang0)
			var rc := _ring_pt(b, tb, ctr, ang1)
			var rd := _ring_pt(a, ta, ctr, ang1)
			var va := lerpf(RU.y, RU.w, float(k) / m)
			var vb := lerpf(RU.y, RU.w, float(k + 1) / m)
			var ua := lerpf(RU.x, RU.z, u0)
			var ub := lerpf(RU.x, RU.z, u1)
			_quad(V, N, U, a + ra, b + rb, b + rc, a + rd, Vector2(ua, va), Vector2(ub, va), Vector2(ub, vb), Vector2(ua, vb))
	# 紙垂：正面（局部 +z、朝前庭）3 本＋背面 1 本；四折、左右交錯
	var xf := xf_of(gos)
	var fwd := (xf.basis * Vector3(0, 0, 1)).normalized()
	for kk: float in [0.14, 0.26, 0.38, 0.5, 0.86]:
		var idx := int(kk * n) % n
		var top: Vector3 = path[idx] - Vector3(0, ROPE_R * 0.8, 0)
		var out := Vector3(top.x - ctr.x, 0, top.z - ctr.z).normalized() * 0.05
		var side := out.cross(Vector3.UP).normalized()
		for f in 4:
			var y0 := top.y - 0.135 * f
			var dx := side * (0.06 if f % 2 == 0 else -0.06)
			var c0 := top + out + dx + Vector3(0, y0 - top.y, 0)
			var hw := side * 0.058
			var a := c0 - hw
			var b := c0 + hw
			var c := b - Vector3(0, 0.13, 0)
			var d := a - Vector3(0, 0.13, 0)
			var u0 := lerpf(SU.x, SU.z, 0.1)
			var u1 := lerpf(SU.x, SU.z, 0.9)
			var v0 := lerpf(SU.y, SU.w, f / 4.0)
			var v1 := lerpf(SU.y, SU.w, (f + 1) / 4.0)
			_quad(V, N, U, a, b, c, d, Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1))
			_quad(V, N, U, b, a, d, c, Vector2(u1, v0), Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1))
	var C := PackedColorArray()
	C.resize(V.size())
	C.fill(Color.WHITE)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_TEX_UV] = U
	arr[Mesh.ARRAY_COLOR] = C
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# P5 鳥居材質（albedo 0.42 × 頂點色）只讀 → 這裡複製一份 albedo 1.0（稲藁・白紙垂がくすまない）
	var mat := (load(ROPE_MAT) as StandardMaterial3D).duplicate() as StandardMaterial3D
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	mat.resource_name = "SG_Shimenawa"
	am.surface_set_material(0, mat)
	am.resource_name = "sg_shimenawa"
	return am


static func _ring_pt(p: Vector3, t: Vector3, ctr: Vector3, ang: float) -> Vector3:
	var out := Vector3(p.x - ctr.x, 0, p.z - ctr.z).normalized()
	var b1 := (out - t * out.dot(t)).normalized()
	var b2 := t.cross(b1).normalized()
	return (b1 * cos(ang) + b2 * sin(ang)) * ROPE_R


# ─────────────────────────── 烘焙 ───────────────────────────

static func xf_of(it: Dictionary) -> Transform3D:
	var p: Vector2 = it["p"]
	var b := Basis(Vector3.UP, float(it["yaw"])).scaled(it["sc"])
	return Transform3D(b, Vector3(p.x, float(it["y"]), p.y))


## R1 樹 prefab 展開成自有節點（LOD mesh 共用、Collision 複製）＋色調 instance uniform（展開後才會存進 .scn）
static func tree_expanded(id: String, preset: String) -> Node3D:
	var t: Node3D = (load(TREES + id + ".tscn") as PackedScene).instantiate()
	var pr: Array = TreeLib.COLOR_PRESETS.get(preset, TreeLib.COLOR_PRESETS["mature"])
	var t2 := Node3D.new()
	for mi: MeshInstance3D in t.find_children("LOD*", "MeshInstance3D", false, false):
		var cp := MeshInstance3D.new()
		cp.name = mi.name
		cp.mesh = mi.mesh
		for prop in ["visibility_range_begin", "visibility_range_end", "visibility_range_begin_margin",
				"visibility_range_end_margin", "visibility_range_fade_mode", "cast_shadow"]:
			cp.set(prop, mi.get(prop))
		for u: String in ["lod_band", "lod_ref"]:
			var val: Variant = mi.get_instance_shader_parameter(u)
			if val != null:
				cp.set_instance_shader_parameter(u, val)
		cp.set_instance_shader_parameter("leaf_tint", pr[0])
		cp.set_instance_shader_parameter("leaf_sat", pr[1])
		if id in UNDER_IDS:
			cp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t2.add_child(cp)
	var tc := t.get_node_or_null("Collision")
	if tc:
		t2.add_child(tc.duplicate())
	t.free()
	t2.set_meta("veg_id", id)
	t2.set_meta("preset", preset)
	return t2


static func bake(P: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	var g := MeshInstance3D.new()
	g.name = "Ground"
	g.mesh = ground_mesh(P)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(g)
	var rp := MeshInstance3D.new()
	rp.name = "Shimenawa"
	rp.mesh = rope_mesh(P)
	rp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rp)
	var trees := Node3D.new()
	trees.name = "Trees"
	root.add_child(trees)
	var under := Node3D.new()
	under.name = "Under"
	root.add_child(under)
	var props := Node3D.new()
	props.name = "Props"
	root.add_child(props)
	var col := StaticBody3D.new()
	col.name = "Collision"
	root.add_child(col)
	var n := 0
	var ns := 0
	var meshes := {}
	for it: Dictionary in P["items"]:
		var id := String(it["id"])
		var xf := xf_of(it)
		if String(it["kind"]) == "tree":
			var t := tree_expanded(id, String(it.get("preset", "mature")))
			t.name = "%03d_%s" % [n, id]
			t.transform = xf
			t.set_meta("grove_tag", String(it["tag"]))
			(under if id in UNDER_IDS else trees).add_child(t)
			n += 1
			continue
		var node := Node3D.new()
		node.name = "%03d_%s" % [n, id]
		node.transform = xf
		node.set_meta("grove_id", id)
		node.set_meta("grove_tag", String(it["tag"]))
		props.add_child(node)
		var dir := GK if id.begins_with("gk_") else GL.RB
		for lod in 2:
			var key := id + ("_l1" if lod == 1 else "")
			if not meshes.has(key):
				meshes[key] = load(dir + key + ".res")
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % lod
			mi.mesh = meshes[key]
			mi.visibility_range_begin = 0.0 if lod == 0 else LOD_SWITCH
			mi.visibility_range_end = LOD_SWITCH if lod == 0 else 260.0
			if lod == 1:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
		for c: Array in GL.coll_of(id):
			var cs := CollisionShape3D.new()
			cs.name = "%s_%d" % [node.name, ns]
			var s: Vector3 = it["sc"]
			cs.transform = Transform3D(Basis(Vector3.UP, float(it["yaw"])), (xf * (c[1] as Transform3D)).origin)
			if c[0] is CylinderShape3D:
				var cy := (c[0] as CylinderShape3D).duplicate() as CylinderShape3D
				cy.radius *= maxf(s.x, s.z)
				cy.height *= s.y
				cs.shape = cy
			else:
				cs.shape = c[0]
			cs.set_meta("grove_id", id)
			col.add_child(cs)
			ns += 1
		n += 1
	root.set_meta("items", (P["items"] as Array).size())
	root.set_meta("shapes", ns)
	root.set_meta("art_revision", "P9 R4-2 神社周邊（鎮守之森／參道）r1（ART_REVIEW）")
	return root


static func own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		if c.scene_file_path == "":
			own(c, owner)
