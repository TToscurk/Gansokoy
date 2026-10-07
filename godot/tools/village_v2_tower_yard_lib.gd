extends RefCounted
## 人間之里 V2 P9 R4-5 Hero Surroundings：火見櫓周邊（ART-FIRST）。
##   規劃（plan）＋烘焙（bake）→ maps/village_v2/gen/tower_yard_p9.scn → village_v2.tscn 掛 Vegetation/TowerYardP9
##   （ForestP9 → BambooP9 → HiedaGardenP9 → ShrineGroveP9 → SchoolYardP9 → WatersideP9 → TowerYardP9）。
##   讀感＝「村の防火／瞭望設施」：庭園でも森の名所でもない。開けた踏み固めの基部、巡回路、消防の実用品。
##   火見櫓 Hero 本體（P5 R5：四柱外八・石基礎・梯子 −x 面＝MainStreet 側・半鐘）不動；P3 地塊／道路、R1–R4-4 封存內容不動。
##   新構件＝tower_kit（用水桶積み／予備梯子／道具掛け〔鳶口・刺股・掛矢・縄〕／縄束）；
##   只讀重用：school_kit 天水桶・手桶・木箱、garden_kit 雨落ち縁石（排水溝の縁）、waterside_kit 菅（雜草）、
##   R1 蕨・灌木 prefab、R4-2 sg_ground shader（COLOR＝碎石, 苔, 踏み固め土, 落葉；instance 參數で灰色の碎石に）。
## 構成（塔心 (250, 66)、柱脚石 ±2.55、梯子 −x 面 x≈246.9；地塊 P_LM_TOWER x 244.5–255.5、z 60.5–71.5）：
##   1 進出：MainStreet 東縁 (241.5, 66) → 梯子の足元＝踏み固めの前庭（梯子の正面は空ける）。
##   2 巡回路：塔を一周する踏み跡（柱脚石の外 0.3 m、角は丸く）、南東の道具置き場へ枝分かれ。
##   3 基腳：柱脚石まわりの碎石＋濕り、南西の柱脚石 → 天水桶の南 → MainStreet 側溝へ碎石の排水溝（出口は縁石で縁取り）。
##   4 消防：北西角（街側）に用水桶積み、南西角に天水桶＋手桶、東に道具掛け（塔の脚越しに見える）、南に予備梯子、
##     道具掛けの南に木箱・縄（全部 塔の脚から 3 m 以内）。
##   5 植生：低い雜草（菅）と北側日陰の蕨 2 のみ（地塊縁・柱脚石の外角）。灌木・高木なし、塔頂と街路視線を遮らない。
##   地面：sg_ground の殘り權重＝草なので、雜草帯以外は土で埋める（草地に見せない）；道は碎石混じりの踏み固めで地の土と分ける。

const SG := preload("res://tools/village_v2_shrine_grove_lib.gd")
const GL := preload("res://tools/village_v2_hieda_garden_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const FLib := preload("res://tools/village_v2_forest_lib.gd")

const OUTPUT := "res://maps/village_v2/gen/tower_yard_p9.scn"
const NODE_NAME := "TowerYardP9"
const TK := "res://assets/village_v2/tower_kit/mesh/"
const SK := "res://assets/village_v2/school_kit/mesh/"
const GK := "res://assets/village_v2/garden_kit/mesh/"
const WK := "res://assets/village_v2/waterside_kit/mesh/"
const PARCELS := "res://maps/village_v2/gen/parcels.json"
const SEED := 4451
const LOD_SWITCH := 34.0

const C := Vector2(250.0, 66.0)
const PARCEL := Rect2(244.5, 60.5, 11.0, 11.0)
const PARCEL_ID := "P_LM_TOWER"
const FOOT_HALF := 0.605                 # Hero Collision Foot0–3 1.21 m 角
const FEET := [Vector2(247.45, 63.45), Vector2(252.55, 63.45), Vector2(252.55, 68.55), Vector2(247.45, 68.55)]
const LADDER_FOOT := Vector2(246.85, 66.0)
## 進出路：MainStreet 東縁 → 梯子の足元
const APPROACH := [Vector2(241.2, 66.0), Vector2(246.6, 66.0)]
const APPROACH_HW := 0.9
## 巡回路：角丸正方形（半辺 RING_H、角半径 RING_R）、帯幅 ±RING_W
const RING_H := 3.95
const RING_R := 1.3
const RING_W := 0.5
## 道具掛けの南の小さな置き場（地塊外の未區劃空地、塔の南東脚から 3 m 以内）＋巡回路からの踏み跡
const YARD := Rect2(255.3, 68.6, 2.6, 3.4)
const YARD_PATH := [Vector2(253.9, 69.45), Vector2(255.4, 69.9)]
## 排水溝：南西の柱脚石 → 天水桶の南 → MainStreet 側溝（出口の 2.6 m は石で縁取り）
const DRAIN := [Vector2(247.3, 69.8), Vector2(246.6, 70.45), Vector2(245.9, 71.05), Vector2(244.6, 71.15), Vector2(243.3, 71.05)]
const DRAIN_LINED := 2
const REGION := Rect2(237.0, 54.0, 32.0, 24.0)

const UNDER_IDS := ["fern_a", "shrub_a"]
const PLANT_IDS := ["wk_sedge"]
const LOW_MAX_H := 1.3
## 構件外框（local xz 半寬、高）＝碰撞箱
const PROP_BOX := {"tk_okeyama": [0.53, 0.28, 1.21], "tk_ladder": [1.8, 0.35, 0.19], "tk_rack": [1.0, 0.2, 2.5],
	"sk_tensui": [0.31, 0.31, 0.75], "sk_box": [0.31, 0.21, 0.38], "sk_teoke": [0.15, 0.15, 0.46], "tk_rope": [0.3, 0.3, 0.17]}
const NO_COLLIDE := ["tk_rope", "sk_teoke", "gk_amaochi"]


static func item(S: RLib.TriSampler, kind: String, id: String, p: Vector2, yaw: float, sc: float, tag: String, extra := {}) -> Dictionary:
	var r := 0.25
	if PROP_BOX.has(id):
		r = minf(float(PROP_BOX[id][0]), float(PROP_BOX[id][1])) * sc
	elif id in PLANT_IDS:
		r = 0.15
	var y := GL.ground(S, p, r)
	var it := {"kind": kind, "id": id, "p": p, "y": y, "yaw": yaw, "sc": Vector3.ONE * sc, "tag": tag}
	it.merge(extra, true)
	return it


static func prop_corners(it: Dictionary) -> PackedVector2Array:
	var b: Array = PROP_BOX.get(String(it["id"]), [0.12, 0.12, 0.1])
	var s: float = (it["sc"] as Vector3).x
	var c := cos(float(it["yaw"]))
	var sn := sin(float(it["yaw"]))
	var out := PackedVector2Array()
	for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var lx := q.x * float(b[0]) * s
		var lz := q.y * float(b[1]) * s
		out.append((it["p"] as Vector2) + Vector2(lx * c + lz * sn, -lx * sn + lz * c))
	return out


## 塔の局部 → 世界（Hero は yaw 0、原點＝塔心）
static func ring_d(p: Vector2) -> float:
	## 角丸正方形（半辺 RING_H、角半径 RING_R）までの符號距離（外＋）
	var q := (p - C).abs() - Vector2(RING_H - RING_R, RING_H - RING_R)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - RING_R


static func foot_d(p: Vector2) -> float:
	var best := INF
	for f: Vector2 in FEET:
		var q := (p - f).abs() - Vector2(FOOT_HALF, FOOT_HALF)
		best = minf(best, Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0))
	return best


## Hero 幾何（場景同源：Collision 形狀）＋建物 footprint
static func hero_boxes(v: Node3D) -> Array:
	var out: Array = []
	for top: String in ["Landmarks/LANDMARK_TOWER"]:
		for cs in v.get_node(top).find_children("*", "CollisionShape3D", true, false):
			var sh := (cs as CollisionShape3D).shape
			var aa := AABB()
			if sh is BoxShape3D:
				aa = AABB(-(sh as BoxShape3D).size * 0.5, (sh as BoxShape3D).size)
			elif sh is ConvexPolygonShape3D:
				var pts := (sh as ConvexPolygonShape3D).points
				aa = AABB(pts[0], Vector3.ZERO)
				for q in pts:
					aa = aa.expand(q)
			else:
				continue
			var w := (cs as Node3D).global_transform * aa
			out.append([String(cs.name), Rect2(w.position.x, w.position.z, w.size.x, w.size.z), w])
	return out


static func building_rects(v: Node3D) -> Array:
	var out: Array = []
	for mi in v.get_node("Districts").find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		if not g.is_visible_in_tree() or g.mesh == null:
			continue
		var a := g.global_transform * g.get_aabb()
		if a.size.y < 1.2 or a.size.x > 40.0 or a.size.z > 40.0:
			continue
		var r := Rect2(a.position.x, a.position.z, a.size.x, a.size.z)
		if REGION.grow(6.0).intersects(r):
			out.append(r)
	return out


## 他の地塊（町家・附屬）多邊形：構件は入れない（植物は附屬地の縁まで可）
static func other_parcels() -> Array:
	var PJ: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PARCELS))
	var out: Array = []
	for r: Dictionary in PJ["parcels"]:
		if String(r["id"]) == PARCEL_ID:
			continue
		var poly := PackedVector2Array()
		for q: Array in r["footprint"]:
			poly.append(Vector2(float(q[0]), float(q[1])))
		var bb := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			bb = bb.expand(q)
		if bb.intersects(REGION.grow(4.0)):
			out.append({"id": String(r["id"]), "kind": String(r["kind"]), "poly": poly})
	return out


static func in_parcel(pp: Array, p: Vector2, kinds: Array) -> String:
	for r: Dictionary in pp:
		if String(r["kind"]) in kinds and Geometry2D.is_point_in_polygon(p, r["poly"]):
			return String(r["id"])
	return ""


static func plan(v: Node3D, L: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var S := RLib.terrain_sampler(v)
	var R := RLib.road_sampler(v)
	var M := FLib.modules()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var items: Array = []
	# ── 消防の実用品（塔 → 基部 → 道具 の順に読ませる：街側の正面は梯子の足元だけ空け、道具は角と奥）
	# 北西角（街側）：用水桶積み（長手を z 沿い、桶の正面を街へ）
	items.append(item(S, "mesh", "tk_okeyama", Vector2(245.35, 61.95), -PI * 0.5, 1.0, "fire"))
	# 南西角：天水桶＋手桶（排水溝の起点の脇）
	items.append(item(S, "mesh", "sk_tensui", Vector2(245.25, 70.35), 0.4, 1.0, "fire"))
	items.append(item(S, "mesh", "sk_teoke", Vector2(244.55, 69.95), 2.6, 1.0, "fire"))
	# 東：道具掛け（正面＝−x で塔の脚越しに見える；P_MKT_046 の地塊縁 x 255.2 より内）
	items.append(item(S, "mesh", "tk_rack", Vector2(254.75, 68.0), -PI * 0.5, 1.0, "tools"))
	# 南：予備梯子（枕木の上、巡回路の外・地塊の内）
	items.append(item(S, "mesh", "tk_ladder", Vector2(252.3, 70.95), 0.0, 1.0, "tools"))
	# 道具掛けの南：木箱 2、縄束（塔の南東脚から 3 m 以内にまとめる）
	items.append(item(S, "mesh", "sk_box", Vector2(256.2, 70.1), 0.35, 1.0, "yard"))
	items.append(item(S, "mesh", "sk_box", Vector2(256.75, 70.9), 1.3, 1.0, "yard"))
	items.append(item(S, "mesh", "tk_rope", Vector2(255.75, 71.55), 0.8, 1.0, "yard"))
	# ── 排水溝の出口（MainStreet 側溝へ）：両側を縁石で連続に縁取る（点線の石列にしない）
	for k in range(DRAIN.size() - DRAIN_LINED - 1, DRAIN.size() - 1):
		var a: Vector2 = DRAIN[k]
		var b: Vector2 = DRAIN[k + 1]
		var d := (b - a).normalized()
		var nrm := Vector2(-d.y, d.x)
		var n := maxi(1, int(ceil(a.distance_to(b) / 0.88)))
		for i in n:
			var p := a.lerp(b, (i + 0.5) / n)
			for sg: float in [-1.0, 1.0]:
				var q := p + nrm * 0.3 * sg
				var it := item(S, "mesh", "gk_amaochi", q, atan2(-d.y, d.x) + rng.randf_range(-0.04, 0.04), 1.0, "drain")
				it["y"] = S.h(q.x, q.y) + 0.02
				items.append(it)
	# ── 低い植生：地塊の縁・柱脚石の外角・置き場の縁（叢、林帯にしない）
	# 庭の植栽に見せない：灌木なし、蕨は北側の日陰の地塊縁 2 叢だけ、あとは雜草（菅）
	for q: Array in [["fern_a", Vector2(249.6, 60.95), 0.75], ["fern_a", Vector2(251.9, 60.85), 0.7]]:
		items.append(item(S, "tree", String(q[0]), q[1], rng.randf() * TAU, float(q[2]), "low", {"preset": "mature"}))
	for p: Vector2 in [Vector2(246.65, 62.6), Vector2(253.4, 62.55), Vector2(253.45, 69.45), Vector2(246.6, 69.5),
			Vector2(248.3, 60.9), Vector2(253.3, 60.85), Vector2(255.2, 64.4), Vector2(244.85, 63.9),
			Vector2(257.6, 69.0), Vector2(257.5, 72.0), Vector2(249.6, 71.3), Vector2(254.7, 71.2), Vector2(244.8, 67.9)]:
		var it := item(S, "plant", "wk_sedge", p + Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12)),
			rng.randf() * TAU, rng.randf_range(0.75, 1.05), "weed")
		it["y"] = S.h((it["p"] as Vector2).x, (it["p"] as Vector2).y) - 0.03
		items.append(it)
	return {"items": items, "S": S, "R": R, "M": M, "hero": hero_boxes(v), "bld": building_rects(v), "pp": other_parcels(),
		"ms": Time.get_ticks_msec() - t0}


# ─────────────────────────── 地面 overlay（sg_ground：COLOR＝碎石, 苔, 踏み固め土, 落葉；UV2＝濕潤, 淡出） ───────────────────────────

const G_STEP := 0.4


static func _n(p: Vector2, a: float) -> float:
	return 0.5 + 0.35 * sin(p.x * 0.83 * a + p.y * 0.37) * sin(p.y * 0.71 * a - p.x * 0.29) + 0.15 * sin(p.x * 2.3 * a - p.y * 1.9)


static func ground_w(P: Dictionary, p: Vector2) -> Variant:
	var nz := _n(p, 1.0)
	var warp := 0.9 * (nz - 0.5) + 0.35 * sin(p.x * 1.1 - p.y * 0.7)
	# 範囲：地塊（＋1 m）・道具置き場・進出路・排水溝；外へ 2.5 m で淡出
	var dpar := _rect_d(PARCEL.grow(1.0), p)
	var dyard := _rect_d(YARD.grow(0.6), p)
	var dap := GL.line_d(APPROACH, p).x - APPROACH_HW - 0.8
	var ddr := GL.line_d(DRAIN, p).x - 0.6
	var dmin := minf(minf(dpar, dyard), minf(dap, ddr)) + warp * 0.8
	var f := 1.0 - smoothstep(0.0, 2.5, dmin)
	if f <= 0.0:
		return null
	var gv := 0.0
	var mo := 0.0
	var so := 0.0
	var li := 0.0
	var wet := 0.06
	# 雜草（shader の殘り＝草）：地塊の縁の内側 1 m と地塊外の淡出帯だけ。他の殘り權重は土で埋める（草地に見せない）
	# 斑の雜草（矩形の縁取りにしない：低周波雜訊の高いところだけ、地塊縁から内 1.2 m の帯で）
	var din := -_rect_d(PARCEL, p)
	var gr := 0.0
	var nw := _n(p * 0.6 + Vector2(17.0, 3.0), 1.7)
	if din > -1.5 and din < 1.2 and nw > 0.55:
		gr = 0.7 * smoothstep(0.55, 0.75, nw) * (1.0 - smoothstep(0.3, 1.2, din))
	# 地塊全体：踏み固め土
	so = (0.45 + 0.2 * nz) * (1.0 - smoothstep(-0.5, 1.5, dpar + warp))
	# 進出路：MainStreet → 梯子の足元（幅は雜訊で揺れる、中心ほど固い）
	var da := GL.line_d(APPROACH, p).x
	var aw := APPROACH_HW + 0.35 * (nz - 0.5) + 0.2 * sin(p.x * 1.7 + p.y)
	if da < aw + 0.9:
		var ka := 1.0 - smoothstep(aw * 0.5, aw + 0.9, da)
		so = maxf(so, 0.5 * ka)
		gv = maxf(gv, 0.6 * (1.0 - smoothstep(aw * 0.4, aw + 0.4, da)))
		gr = 0.0
	# 梯子の足元：踏み込みが一番強い
	var dl := p.distance_to(LADDER_FOOT + Vector2(-0.5, 0.0))
	if dl < 1.6:
		so = maxf(so, 0.7 * (1.0 - smoothstep(0.7, 1.6, dl)))
		gv = maxf(gv, 0.3 * (1.0 - smoothstep(0.5, 1.4, dl)))
		gr = 0.0
	# 巡回路（角丸正方形の帯、ところどころ薄くなる）
	var dr := absf(ring_d(p)) - (RING_W + 0.2 * (nz - 0.5))
	if dr < 0.5:
		var k := 1.0 - smoothstep(-0.25, 0.5, dr)
		so = maxf(so, (0.55 + 0.2 * _n(p * 1.7, 1.3)) * k)
		gv = maxf(gv, (0.5 + 0.12 * _n(p * 2.3, 1.1)) * (1.0 - smoothstep(-0.3, 0.2, dr)))
		gr *= 1.0 - k
	# 塔の下（脚の内側）：踏み固め＋少し碎石
	var dc := maxf(absf(p.x - C.x), absf(p.y - C.y))
	if dc < 2.4:
		so = maxf(so, 0.5)
		gv = maxf(gv, 0.3 + 0.15 * nz)
		gr = 0.0
	# 柱脚石まわり：碎石の環（濕り）、北側は苔
	var df := foot_d(p)
	if df < 0.95:
		var k2 := 1.0 - smoothstep(0.35, 0.95, df + 0.2 * (nz - 0.5))
		gv = maxf(gv, 0.95 * k2)
		wet = maxf(wet, 0.35 * k2)
		gr *= 1.0 - k2
		if p.y < 64.4 or (p.y > 67.6 and p.y < 68.0):
			mo = maxf(mo, 0.3 * k2 * (1.0 if p.y < 64.4 else 0.4))
	# 排水溝：碎石の溝＋両側の濕った泥
	var ddrain := GL.line_d(DRAIN, p).x
	if ddrain < 0.75:
		var kd := 1.0 - smoothstep(0.22, 0.38, ddrain)
		gv = maxf(gv, 0.95 * kd)
		gr = 0.0
		so = maxf(so, 0.7 * (1.0 - smoothstep(0.25, 0.75, ddrain)))
		wet = maxf(wet, 0.95 * (1.0 - smoothstep(0.15, 0.75, ddrain)))
	# 柱脚石 → 排水溝 の短い溝（南の 2 本）
	for f2: Vector2 in [FEET[2]]:
		var dd := GL.line_d([f2 + Vector2(0, FOOT_HALF), Vector2(f2.x, 69.9), Vector2(248.0, 69.75)], p).x
		if dd < 0.4:
			gv = maxf(gv, 0.6 * (1.0 - smoothstep(0.12, 0.4, dd)))
			wet = maxf(wet, 0.5 * (1.0 - smoothstep(0.1, 0.4, dd)))
	# 天水桶の足元：ぬかるみ
	var dt := p.distance_to(Vector2(245.3, 70.5))
	if dt < 1.4:
		so = maxf(so, 0.8 * (1.0 - smoothstep(0.6, 1.4, dt)))
		wet = maxf(wet, 0.7 * (1.0 - smoothstep(0.4, 1.4, dt)))
	# 道具置き場：踏み固め（斑）＋入口からの踏み跡
	var dy := _rect_d(YARD, p) + 0.6 * (nz - 0.5)
	if dy < 0.6:
		so = maxf(so, (0.5 + 0.3 * _n(p * 1.4, 1.7)) * (1.0 - smoothstep(-0.6, 0.6, dy)))
	var dyp := GL.line_d(YARD_PATH, p).x
	if dyp < 0.9:
		so = maxf(so, 0.7 * (1.0 - smoothstep(0.35, 0.9, dyp)))
	# 道具掛けの前：落ちた藁屑・木屑（落葉層を少量）
	if p.distance_to(Vector2(254.1, 68.0)) < 1.3:
		li = maxf(li, 0.25 * (1.0 - p.distance_to(Vector2(254.1, 68.0)) / 1.3))
	var tot := gv + mo + so + li
	if tot < 1.0:
		so += (1.0 - tot) * (1.0 - clampf(gr * 1.3, 0.0, 1.0))
		tot = gv + mo + so + li
	if tot > 1.0:
		gv /= tot
		mo /= tot
		so /= tot
		li /= tot
		tot = 1.0
	f *= smoothstep(0.0, 0.1, tot)
	return [Color(gv, mo, so, li), Vector2(wet, f)]


static func _rect_d(r: Rect2, p: Vector2) -> float:
	var dx := maxf(r.position.x - p.x, p.x - r.end.x)
	var dz := maxf(r.position.y - p.y, p.y - r.end.y)
	if dx <= 0.0 and dz <= 0.0:
		return maxf(dx, dz)
	return Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length()


## R4-4 で確立した格子縁なしの組み方：footprint 頂點排除＋網格邊緣 BFS 淡出（1 m）＋權重 3×3 高斯 2 回
static func ground_mesh(P: Dictionary) -> ArrayMesh:
	var S: RLib.TriSampler = P["S"]
	var R: RLib.TriSampler = P["R"]
	var boxes: Array = (P["bld"] as Array).duplicate()
	for hb: Array in P["hero"]:
		if String(hb[0]).begins_with("Foot"):
			boxes.append((hb[1] as Rect2).grow(-0.12))
	var nx := int(ceil(REGION.size.x / G_STEP))
	var nz := int(ceil(REGION.size.y / G_STEP))
	var WG := {}
	var roadx := {}
	for j in nz + 1:
		for i in nx + 1:
			var p := REGION.position + Vector2(i * G_STEP, j * G_STEP)
			var h := S.h(p.x, p.y)
			if is_nan(h):
				continue
			if not is_nan(R.h(p.x, p.y)):
				roadx[Vector2i(i, j)] = true
				continue
			var inside := false
			for b: Rect2 in boxes:
				if b.size.x > 0.5 and b.size.y > 0.5 and b.grow(-0.1).has_point(p):
					inside = true
					break
			if inside:
				continue
			var w: Variant = ground_w(P, p)
			if w == null:
				continue
			WG[Vector2i(i, j)] = [(w as Array)[0], (w as Array)[1]]
	var NB := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
	var N4 := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
	var bd := {}
	var front: Array = []
	# 道路側の縁は淡出しない（道路 decal が上に載る）→ 進出路が MainStreet にそのまま繋がる
	for g: Vector2i in WG:
		for d: Vector2i in NB:
			if not WG.has(g + d) and not roadx.has(g + d):
				bd[g] = 0
				front.append(g)
				break
	var lvl := 0
	while not front.is_empty() and lvl < 4:
		lvl += 1
		var nxt: Array = []
		for g: Vector2i in front:
			for d: Vector2i in N4:
				var q: Vector2i = g + d
				if WG.has(q) and not bd.has(q):
					bd[q] = lvl
					nxt.append(q)
		front = nxt
	for pass_i in 1:
		var nw := {}
		for g: Vector2i in WG:
			var c4: Color = (WG[g][0] as Color) * 4.0
			var u2: Vector2 = (WG[g][1] as Vector2) * 4.0
			var ws := 4.0
			for d: Vector2i in NB:
				if WG.has(g + d):
					var wt := 1.0 if (d.x != 0 and d.y != 0) else 2.0
					c4 += (WG[g + d][0] as Color) * wt
					u2 += (WG[g + d][1] as Vector2) * wt
					ws += wt
			nw[g] = [c4 / ws, u2 / ws]
		WG = nw
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var Cc := PackedColorArray()
	var U2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var vid := {}
	for j in nz + 1:
		for i in nx + 1:
			var g := Vector2i(i, j)
			if not WG.has(g):
				continue
			var uo: Vector2 = WG[g][1]
			uo.y *= smoothstep(0.0, 2.5, float(bd.get(g, 4)))
			var p := REGION.position + Vector2(i * G_STEP, j * G_STEP)
			var h := S.h(p.x, p.y)
			var d := 0.4
			var nrm := Vector3(S.h(p.x - d, p.y) - S.h(p.x + d, p.y), 2.0 * d, S.h(p.x, p.y - d) - S.h(p.x, p.y + d))
			vid[g] = V.size()
			V.append(Vector3(p.x, h + 0.011, p.y))
			N.append(nrm.normalized() if nrm.is_finite() else Vector3.UP)
			Cc.append(WG[g][0])
			U2.append(uo)
	for j in nz:
		for i in nx:
			var k00: Variant = vid.get(Vector2i(i, j))
			var k10: Variant = vid.get(Vector2i(i + 1, j))
			var k01: Variant = vid.get(Vector2i(i, j + 1))
			var k11: Variant = vid.get(Vector2i(i + 1, j + 1))
			if k00 == null or k10 == null or k01 == null or k11 == null:
				continue
			if absf(V[k00].y - V[k11].y) <= absf(V[k10].y - V[k01].y):
				idx.append_array([k00, k10, k11, k00, k11, k01])
			else:
				idx.append_array([k00, k10, k01, k10, k11, k01])
	var am := ArrayMesh.new()
	if idx.is_empty():
		return am
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_COLOR] = Cc
	arr[Mesh.ARRAY_TEX_UV2] = U2
	arr[Mesh.ARRAY_INDEX] = idx
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var m := SG.sg_material()
	m.resource_name = "TY_Ground"
	# R4-2 sg_ground（只讀）の instance 參數：玉砂利 → 灰色の碎石（白く光らせない）、踏み固め土は乾いた色
	m.set_shader_parameter("gravel_tint", Vector3(1.16, 1.11, 1.03))
	m.set_shader_parameter("gravel_contrast", 0.95)
	m.set_shader_parameter("gravel_sat", 0.4)
	m.set_shader_parameter("gravel_tile", 0.55)
	am.surface_set_material(0, m)
	am.resource_name = "ty_ground"
	return am


# ─────────────────────────── 烘焙 ───────────────────────────

static func bake(P: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	var g := MeshInstance3D.new()
	g.name = "Ground"
	g.mesh = ground_mesh(P)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(g)
	var groups := {}
	for nm: String in ["Low", "Weeds", "Props", "Drain"]:
		var n := Node3D.new()
		n.name = nm
		root.add_child(n)
		groups[nm] = n
	var col := StaticBody3D.new()
	col.name = "Collision"
	root.add_child(col)
	var n_i := 0
	var ns := 0
	var meshes := {}
	for it: Dictionary in P["items"]:
		var id := String(it["id"])
		var xf := SG.xf_of(it)
		if String(it["kind"]) == "tree":
			var t := SG.tree_expanded(id, String(it.get("preset", "mature")))
			t.name = "%03d_%s" % [n_i, id]
			t.transform = xf
			t.set_meta("ty_tag", String(it["tag"]))
			(groups["Low"] as Node).add_child(t)
			n_i += 1
			continue
		var node := Node3D.new()
		node.name = "%03d_%s" % [n_i, id]
		node.transform = xf
		node.set_meta("ty_id", id)
		node.set_meta("ty_tag", String(it["tag"]))
		var grp := "Weeds" if id in PLANT_IDS else ("Drain" if id == "gk_amaochi" else "Props")
		(groups[grp] as Node).add_child(node)
		var dir := TK if id.begins_with("tk_") else (SK if id.begins_with("sk_") else (GK if id.begins_with("gk_") else WK))
		for lod in 2:
			var key := id + ("_l1" if lod == 1 else "")
			if not meshes.has(key):
				meshes[key] = load(dir + key + ".res")
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % lod
			mi.mesh = meshes[key]
			mi.visibility_range_begin = 0.0 if lod == 0 else LOD_SWITCH
			mi.visibility_range_end = LOD_SWITCH if lod == 0 else (90.0 if id in PLANT_IDS or id == "gk_amaochi" else 220.0)
			if lod == 1 or id in ["wk_sedge", "gk_amaochi", "tk_rope"]:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
		if PROP_BOX.has(id) and not (id in NO_COLLIDE):
			var b: Array = PROP_BOX[id]
			var s: float = (it["sc"] as Vector3).x
			var bx := BoxShape3D.new()
			bx.size = Vector3(float(b[0]) * 2.0, float(b[2]), float(b[1]) * 2.0) * s
			var cs := CollisionShape3D.new()
			cs.name = "%s_c" % node.name
			cs.shape = bx
			cs.transform = Transform3D(Basis(Vector3.UP, float(it["yaw"])), xf.origin + Vector3(0, float(b[2]) * s * 0.5, 0))
			col.add_child(cs)
			ns += 1
		n_i += 1
	root.set_meta("items", (P["items"] as Array).size())
	root.set_meta("shapes", ns)
	root.set_meta("art_revision", "P9 R4-5 火見櫓周邊 r3（ART_REVIEW）")
	return root


static func own(n: Node, owner: Node) -> void:
	SG.own(n, owner)
