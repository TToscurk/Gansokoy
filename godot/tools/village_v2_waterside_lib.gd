extends RefCounted
## 人間之里 V2 P9 R4-4 Hero Surroundings：水車／龍神像周邊（ART-FIRST）。
##   規劃（plan）＋烘焙（bake）→ maps/village_v2/gen/waterside_p9.scn → village_v2.tscn 掛 Vegetation/WatersideP9
##   （ForestP9 → BambooP9 → HiedaGardenP9 → ShrineGroveP9 → SchoolYardP9 → WatersideP9）。
##   水車 ×3／龍神像 Hero 本體（P5 R4）、P7 河岸護岸、P8 農地與灌溉、R1–R4-3 封存內容一律不動，只讀當障礙。
##   植物性格（§31.2）：水車＝柳、河岸草、濕地植物；龍神像＝濕石、苔、河岸植被、少量神聖感樹木。
##   新構件＝waterside_kit（蘆／小蘆／花菖蒲／菅／米俵／石臼／供物台）；只讀重用：R1 柳・樟・灌木 prefab、
##   R4 garden_kit 春日燈籠、P7 riverbank_kit 轉石、R4-2 神社周邊的地面 shader（sg_ground）與注連繩生成（rope_plan／rope_mesh）。

const SG := preload("res://tools/village_v2_shrine_grove_lib.gd")
const GL := preload("res://tools/village_v2_hieda_garden_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const FLib := preload("res://tools/village_v2_forest_lib.gd")

const OUTPUT := "res://maps/village_v2/gen/waterside_p9.scn"
const NODE_NAME := "WatersideP9"
const WK := "res://assets/village_v2/waterside_kit/mesh/"
const GK := "res://assets/village_v2/garden_kit/mesh/"
const RB := "res://assets/village_v2/riverbank_kit/mesh/"
const SEED := 4441
const LOD_SWITCH := 36.0

const DRAGON := Vector2(388.0, -188.0)
const WHEELS := [Vector2(334.8, -52.0), Vector2(329.2, 0.0), Vector2(310.6, 58.0)]
const WHEEL_CLEAR := 6.0          # layout keep_clear「水車輪と維修空間」
const DRAGON_TREE_CLEAR := 12.0   # layout keep_clear「龍神像基座與參拜空間」：樹不進
## 各 site 範圍（地面 overlay＋蘆探索）
const SITES := {
	"dragon": Rect2(358.0, -222.0, 44.0, 66.0),
	"ww1": Rect2(318.0, -68.0, 34.0, 30.0),
	"ww2": Rect2(312.0, -16.0, 34.0, 30.0),
	"ww3": Rect2(292.0, 44.0, 34.0, 28.0),
}
const PLANT_IDS := ["wk_reed", "wk_reed_s", "wk_iris", "wk_sedge"]
const UNDER_IDS := ["fern_a", "sasa_a", "shrub_a", "tsutsuji_a"]
const TREE_OK := ["yanagi_a", "yanagi_b", "kusu_hero", "young_broad_a", "young_broad_b", "enoki_a"]
## 構件外框（local 半寬 x, 半寬 z, 高）＝碰撞箱
const PROP_BOX := {"wk_tawara": [0.38, 0.23, 0.46], "wk_tawara3": [0.4, 0.46, 0.84], "wk_usu": [0.45, 0.31, 0.52],
	"wk_sonae": [0.45, 0.25, 0.82], "gk_toro_kasuga": [0.38, 0.44, 1.94]}
const STONE_IDS := ["rb_bld_a", "rb_bld_b", "rb_bld_c", "rb_bld_d", "rb_bld_e"]

## 龍神像 參拜動線（世界；RiverNorthPath → 基座西面 walkway）
const DRAGON_APPROACH := [Vector2(375.2, -188.0), Vector2(381.0, -188.0)]
## r4 水車の作業場（Hero 局部座標：−x＝陸側、+z＝南；入口＝(−5, 3.5)）：[id, 希望位置, 視線からの長軸角(°), 淨空半径, 既置との中心距離下限]
const WORK_SPOTS := [
	[["wk_tawara3", Vector2(-9.0, 3.4), 30.0, 0.55, 0.0], ["wk_usu", Vector2(-8.0, 6.4), 205.0, 0.5, 2.1]],
	[["wk_tawara3", Vector2(-9.4, 2.8), 30.0, 0.55, 0.0], ["wk_tawara", Vector2(-8.4, 3.9), 80.0, 0.4, 1.15], ["wk_usu", Vector2(-8.2, 6.6), 205.0, 0.5, 2.1]],
	[["wk_tawara", Vector2(-8.8, 3.2), 75.0, 0.4, 0.0], ["wk_usu", Vector2(-8.4, 5.8), 205.0, 0.5, 2.0]],
]
## 注連繩：樟の御神木（龍神の依り代）
const KUSU := Vector2(363.6, -200.5)
const KUSU_SC := 1.0
## r4：中距 TPS で繩体が読める太さ（R4-2 SG.ROPE_R 0.11 → Ø 0.36 m）＋二本撚り。R4-2 lib は只讀、ここで独自に生成。
const ROPE_R := 0.18
const ROPE_TWIST := 0.13          # 撚り：環半径の振幅（ROPE_R 比）
const ROPE_PITCH := 0.42          # 撚り 1 周の長さ（m）
const ROPE_PTS := 96


static func xf2(xf: Transform3D, q: Vector2) -> Vector2:
	var w := xf * Vector3(q.x, 0.0, q.y)
	return Vector2(w.x, w.z)


## Hero 幾何（MCP runtime 實測同源：從場景讀 global_transform 與 Collision 形狀）
static func hero_geo(v: Node3D) -> Dictionary:
	var g := {"boxes": [], "walkways": [], "entries": [], "hubs": [], "hero_xf": []}
	for k in 3:
		var hero := v.get_node("Landmarks/LANDMARK_WATERWHEEL_%d/Hero" % (k + 1)) as Node3D
		var xf := hero.global_transform
		g["hero_xf"].append(xf)
		var wk := [xf2(xf, Vector2(-5.6, -2.5)), xf2(xf, Vector2(-4.6, -2.5)), xf2(xf, Vector2(-4.6, 2.5)), xf2(xf, Vector2(-5.6, 2.5))]
		g["walkways"].append(wk)
		g["entries"].append(xf2(xf, Vector2(-5.0, 3.5)))
		var wh := hero.get_node("Wheel/LOD0") as MeshInstance3D
		var a := wh.global_transform * wh.get_aabb()
		g["hubs"].append(a.get_center())
		g["boxes"].append(Rect2(a.position.x, a.position.z, a.size.x, a.size.z))
	var dh := v.get_node("Landmarks/LANDMARK_DRAGON/Hero") as Node3D
	var dx := dh.global_transform
	g["dragon_walkway"] = [xf2(dx, Vector2(-7.8, -4.0)), xf2(dx, Vector2(-6.3, -4.0)), xf2(dx, Vector2(-6.3, 4.0)), xf2(dx, Vector2(-7.8, 4.0))]
	for top: String in ["Landmarks/LANDMARK_DRAGON", "Landmarks/LANDMARK_WATERWHEEL_1", "Landmarks/LANDMARK_WATERWHEEL_2",
			"Landmarks/LANDMARK_WATERWHEEL_3", "Roads/Bridges"]:
		var n := v.get_node_or_null(top)
		if n == null:
			continue
		for cs in n.find_children("*", "CollisionShape3D", true, false):
			var sh := (cs as CollisionShape3D).shape
			var aa := AABB()
			if sh is BoxShape3D:
				aa = AABB(-(sh as BoxShape3D).size * 0.5, (sh as BoxShape3D).size)
			elif sh is ConvexPolygonShape3D:
				var pts := (sh as ConvexPolygonShape3D).points
				aa = AABB(pts[0], Vector3.ZERO)
				for q in pts:
					aa = aa.expand(q)
			elif sh is CylinderShape3D:
				var cy := sh as CylinderShape3D
				aa = AABB(Vector3(-cy.radius, -cy.height * 0.5, -cy.radius), Vector3(cy.radius * 2, cy.height, cy.radius * 2))
			else:
				continue
			var w := (cs as Node3D).global_transform * aa
			if w.size.x > 60 or w.size.z > 60:
				continue
			g["boxes"].append(Rect2(w.position.x, w.position.z, w.size.x, w.size.z))
	return g


## 建物・農地（P8）の footprint
static func obstacle_rects(v: Node3D) -> Array:
	var out: Array = []
	var area := Rect2(286, -230, 124, 310)
	for top: String in ["Districts"]:
		var root := v.get_node_or_null(top)
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if not g.is_visible_in_tree() or g.mesh == null or String(g.name).contains("ParcelLines"):
				continue
			var a := g.global_transform * g.get_aabb()
			if a.size.x > 40.0 or a.size.z > 40.0:
				continue
			var r := Rect2(a.position.x, a.position.z, a.size.x, a.size.z)
			if area.intersects(r):
				out.append(r)
	return out


## P7 河岸石積・P8 灌溉の頂點（樹／構件は 0.5 m 内に入れない；蘆は可）
class PtBins:
	var cell := 2.0
	var bins := {}

	func add(p: Vector3) -> void:
		var k := Vector2i(floori(p.x / cell), floori(p.z / cell))
		if not bins.has(k):
			bins[k] = PackedVector3Array()
		var arr: PackedVector3Array = bins[k]
		arr.append(p)
		bins[k] = arr

	func near(p: Vector2, r: float, y_min := -INF) -> bool:
		var ci := floori(p.x / cell)
		var cj := floori(p.y / cell)
		var n := int(ceil(r / cell))
		for i in range(ci - n, ci + n + 1):
			for j in range(cj - n, cj + n + 1):
				var k := Vector2i(i, j)
				if not bins.has(k):
					continue
				for q: Vector3 in bins[k]:
					if q.y >= y_min and Vector2(q.x, q.z).distance_to(p) < r:
						return true
		return false


static func stone_bins(v: Node3D) -> PtBins:
	var B := PtBins.new()
	var area := Rect2(286, -230, 124, 310)
	for top: String in ["Riverbank", "Districts/FarmlandEast/FarmlandP8/Irrigation"]:
		var root := v.get_node_or_null(top)
		if root == null:
			continue
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null or String(g.name).contains("LOD1") or String(g.name).contains("LOD2"):
				continue
			var a := g.global_transform * g.get_aabb()
			if not area.intersects(Rect2(a.position.x, a.position.z, a.size.x, a.size.z)):
				continue
			var xf := g.global_transform
			for s in g.mesh.get_surface_count():
				var V: PackedVector3Array = g.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for k in range(0, V.size(), 2):
					B.add(xf * V[k])
	return B


class WaterQ:
	var S: RLib.TriSampler
	var WL: Dictionary

	func level(p: Vector2) -> float:
		var best := NAN
		for nm in WL:
			var lv: float = (WL[nm] as RLib.WaterLv).at(p.x, p.y)
			if not is_nan(lv) and (is_nan(best) or lv > best):
				best = lv
		return best

	## 水面下の深さ（>0＝水中）
	func depth(p: Vector2) -> float:
		var lv := level(p)
		var h := S.h(p.x, p.y)
		if is_nan(lv) or is_nan(h):
			return -9.0
		return lv - h

	## 最近水面までの水平距離（0.5 m 刻み、max r）
	func dist(p: Vector2, r := 4.0) -> float:
		if depth(p) > 0.03:
			return 0.0
		var st := 0.5
		var k := 1
		while k * st <= r:
			for a in 12:
				var q := p + Vector2(cos(a * TAU / 12.0), sin(a * TAU / 12.0)) * k * st
				if depth(q) > 0.03:
					return k * st
			k += 1
		return INF


static func item(S: RLib.TriSampler, kind: String, id: String, p: Vector2, yaw: float, sc: float, tag: String, extra := {}) -> Dictionary:
	var r := 0.25
	if kind == "tree" and not (id in UNDER_IDS):
		r = maxf(SG.trunk_r(id, sc, FLib.modules()) * 0.7, 0.12)
	elif PROP_BOX.has(id):
		r = minf(float(PROP_BOX[id][0]), float(PROP_BOX[id][1])) * sc
	elif id in PLANT_IDS:
		r = 0.15
	var y := GL.ground(S, p, r) - (0.05 if kind == "tree" else 0.0)
	var it := {"kind": kind, "id": id, "p": p, "y": y, "yaw": yaw, "sc": Vector3.ONE * sc, "tag": tag}
	it.merge(extra, true)
	return it


static func prop_corners(it: Dictionary) -> PackedVector2Array:
	var b: Array = PROP_BOX.get(String(it["id"]), [0.15, 0.15, 0.1])
	var s: float = (it["sc"] as Vector3).x
	var c := cos(float(it["yaw"]))
	var sn := sin(float(it["yaw"]))
	var out := PackedVector2Array()
	for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var lx := q.x * float(b[0]) * s
		var lz := q.y * float(b[1]) * s
		out.append((it["p"] as Vector2) + Vector2(lx * c + lz * sn, -lx * sn + lz * c))
	return out


static func _nz(p: Vector2, a := 1.0) -> float:
	return 0.5 + 0.5 * sin(p.x * 0.41 * a + p.y * 0.23) * sin(p.y * 0.37 * a - p.x * 0.19) + 0.12 * sin(p.x * 1.7 * a - p.y * 1.3)


static func plan(v: Node3D, L: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var S := RLib.terrain_sampler(v)
	var R := RLib.road_sampler(v)
	var W := WaterQ.new()
	W.S = S
	W.WL = RLib.water_levels(v)
	var M := FLib.modules()
	var H := hero_geo(v)
	var obs := obstacle_rects(v)
	var SB := stone_bins(v)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var items: Array = []
	# ── 樹：龍神像＝樟の御神木 1（注連繩）＋入江の柳 1；水車＝柳（1 と 3 に 1、2 に 2）
	var kusu := item(S, "tree", "kusu_hero", KUSU, 2.2, KUSU_SC, "goshinboku", {"preset": "deep"})
	kusu["y"] = SG.conform_y(S, kusu)
	kusu["rope_h"] = 2.6 / KUSU_SC
	items.append(kusu)
	var SB0: PtBins = stone_bins(v)
	var W0 := WaterQ.new()
	W0.S = S
	W0.WL = RLib.water_levels(v)
	for q: Array in [["yanagi_a", Vector2(374.6, -166.6), 0.82, "dragon_willow", "mature"],
			["yanagi_a", Vector2(326.4, -66.8), 0.85, "ww1_willow", "mature"],
			["yanagi_a", Vector2(319.6, -9.6), 1.0, "ww2_willow", "mature"],
			["yanagi_b", Vector2(341.8, 9.6), 0.85, "ww2_willow_e", "young"],
			["yanagi_a", Vector2(302.2, 51.8), 0.82, "ww3_willow", "mature"]]:
		var pw: Vector2 = q[1]
		if String(q[3]).begins_with("ww"):
			pw = crest_spot(pw, W0, SB0, R, H, obs, 1.4)
		items.append(item(S, "tree", String(q[0]), pw, rng.randf() * TAU, float(q[2]), String(q[3]), {"preset": String(q[4])}))
	# 御神木根元・柳根元の下草
	for q: Array in [["fern_a", Vector2(360.2, -197.6), 1.0], ["sasa_a", Vector2(366.8, -204.2), 0.9], ["shrub_a", Vector2(360.6, -203.8), 0.9],
			["fern_a", Vector2(367.4, -197.0), 0.8], ["shrub_a", Vector2(321.0, -63.8), 0.8], ["fern_a", Vector2(317.4, -12.6), 0.9],
			["shrub_a", Vector2(299.2, 48.2), 0.85]]:
		items.append(item(S, "tree", String(q[0]), q[1], rng.randf() * TAU, float(q[2]), "under", {"preset": "mature"}))
	# ── 龍神像：春日燈籠一対＋供物台（walkway の外、基座西面の足元）
	items.append(item(S, "mesh", "gk_toro_kasuga", Vector2(380.9, -194.6), PI * 0.5, 1.1, "dragon_lantern"))
	items.append(item(S, "mesh", "gk_toro_kasuga", Vector2(380.9, -181.4), PI * 0.5, 1.1, "dragon_lantern"))
	# 供物台：walkway（x 380.2–381.7）と基座 Collision/Base（x ≥ 383.15）の間 1.45 m に収める
	items.append(item(S, "mesh", "wk_sonae", Vector2(382.62, -191.0), PI * 0.5, 1.1, "dragon_offering"))
	# ── 水車：米俵・石臼（r4：生活細節として 3–8 m で読めるよう、位置／前後景分離／向き／留白で解決。拡大しない）
	#   入口の陸側（局部 −x）・日向（柳の樹冠外、水車本体の影＝西側 8 m 以内を避け南寄り）・水際 ≥ 2.5 m・石積から ≥ 1 m、
	#   背景＝芝（暗い水車／石積／水面を背負わない）。群の間に 1.3 m 以上の留白。
	#   向き：視線（入口西南から水車軸へ）に対し 米俵 3 俵積み＝端面の三角が見える角度、単俵＝縄 3 道の側面、石臼＝上臼の円盤面を手前へ。
	var willows: Array = []
	for it: Dictionary in items:
		if String(it["id"]).begins_with("yanagi"):
			willows.append([it["p"], float(M[it["id"]]["crown_w"]) * 0.45 * (it["sc"] as Vector3).x + 0.4])
	for k in 3:
		var hero_xf: Transform3D = H["hero_xf"][k]
		var hub2 := Vector2((H["hubs"][k] as Vector3).x, (H["hubs"][k] as Vector3).z)
		var placed: Array = []
		for q: Array in WORK_SPOTS[k]:
			var pref := xf2(hero_xf, q[1])
			var p := work_spot(pref, float(q[3]), float(q[4]), W, SB, S, R, H, obs, willows, placed, k)
			var vw := (hub2 - p).normalized()
			var d := vw.rotated(deg_to_rad(float(q[2])))
			var it := item(S, "mesh", String(q[0]), p, atan2(-d.y, d.x), 1.0, "ww%d_mill" % (k + 1))
			items.append(it)
			placed.append(p)
	# ── 濕石（P7 轉石の流用）：龍神像入江・基座の陸側水際
	for q: Array in [["rb_bld_c", Vector2(379.4, -173.6), 0.55], ["rb_bld_a", Vector2(381.6, -175.2), 0.7], ["rb_bld_e", Vector2(376.6, -170.2), 0.5],
			["rb_bld_b", Vector2(383.2, -178.8), 0.6]]:
		var st := item(S, "mesh", String(q[0]), q[1], rng.randf() * TAU, float(q[2]), "wet_stone")
		st["y"] = S.h((q[1] as Vector2).x, (q[1] as Vector2).y) - 0.18 * float(q[2])
		items.append(st)
	# ── 河岸植生（蘆・花菖蒲・菅）：水際の帯に叢で、間を空ける
	var plants := _waterside_plants(S, R, W, H, obs, SB, rng, items)
	items.append_array(plants)
	return {"items": items, "S": S, "R": R, "W": W, "M": M, "H": H, "obs": obs, "SB": SB, "rope": rope_plan(kusu), "willows": willows,
		"ms": Time.get_ticks_msec() - t0}


## 護岸天端：石積（P7 riverbank／P8 灌溉）の外で、水面から水平 lo–hi m
static func bank_zone(p: Vector2, W: WaterQ, SB: PtBins, S: RLib.TriSampler) -> String:
	var dp := W.depth(p)
	if dp < -2.9:
		return ""
	var h := S.h(p.x, p.y)
	var stone := SB.near(p, 0.5, h - 0.5)
	if dp > 0.05:
		return "shallow" if dp < 0.35 and not stone else ""
	if stone:
		return ""
	if dp > -0.45:
		return "shore"
	var dw := W.dist(p, 6.0)
	if dw <= 6.0:
		return "crest"
	return ""


static func crest_spot(pref: Vector2, W: WaterQ, SB: PtBins, R: RLib.TriSampler, H: Dictionary, obs: Array, r: float) -> Vector2:
	var cands: Array = []
	for j in range(-20, 21):
		for i in range(-20, 21):
			cands.append(pref + Vector2(i, j) * 0.5)
	cands.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(pref) < b.distance_squared_to(pref))
	for p: Vector2 in cands:
		var ok := true
		for wc: Vector2 in WHEELS:
			if p.distance_to(wc) < WHEEL_CLEAR + 1.5:
				ok = false
		if not ok or W.depth(p) > -0.3 or SB.near(p, r, -INF) or _blocked(p, r, R, H, obs):
			continue
		var dw := W.dist(p, 4.5)
		if dw >= 2.5 and dw <= 4.5:
			return p
	return pref


## r4 水車作業場：希望位置の近傍 3 m（0.25 m 刻み、近い順）で条件を満たす最初の点
static func work_spot(pref: Vector2, r: float, sep: float, W: WaterQ, SB: PtBins, S: RLib.TriSampler, R: RLib.TriSampler,
		H: Dictionary, obs: Array, willows: Array, placed: Array, k: int) -> Vector2:
	var cands: Array = []
	for j in range(-12, 13):
		for i in range(-12, 13):
			cands.append(pref + Vector2(i, j) * 0.25)
	cands.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(pref) < b.distance_squared_to(pref))
	for p: Vector2 in cands:
		if p.distance_to(WHEELS[k]) < WHEEL_CLEAR + 1.0 or W.depth(p) > -0.3 or W.dist(p, 2.5) <= 2.5:
			continue
		if SB.near(p, r + 1.0, -INF) or _blocked(p, r + 0.3, R, H, obs):
			continue
		var ok := true
		for wd: Array in willows:
			if p.distance_to(wd[0]) < float(wd[1]):
				ok = false
		for q: Vector2 in placed:
			if p.distance_to(q) < sep:
				ok = false
		var h0 := S.h(p.x, p.y)
		for a in 4:
			var o := Vector2(cos(a * PI * 0.5), sin(a * PI * 0.5)) * (r + 0.2)
			if absf(S.h(p.x + o.x, p.y + o.y) - h0) > 0.12:
				ok = false
		if ok:
			return p
	push_warning("work_spot: 條件を満たす点なし %s" % pref)
	return pref


static func _blocked(p: Vector2, r: float, R: RLib.TriSampler, H: Dictionary, obs: Array) -> bool:
	if not is_nan(R.h(p.x, p.y)):
		return true
	for q in 6:
		var a := q * TAU / 6.0
		if not is_nan(R.h(p.x + cos(a) * r, p.y + sin(a) * r)):
			return true
	for b: Rect2 in H["boxes"]:
		if b.grow(r).has_point(p):
			return true
	for b: Rect2 in obs:
		if b.grow(r).has_point(p):
			return true
	for wk: Array in H["walkways"]:
		if GL.poly_d(PackedVector2Array(wk), p) < r + 0.6 or Geometry2D.is_point_in_polygon(p, PackedVector2Array(wk)):
			return true
	if Geometry2D.is_point_in_polygon(p, PackedVector2Array(H["dragon_walkway"])) or GL.poly_d(PackedVector2Array(H["dragon_walkway"]), p) < r + 0.6:
		return true
	if GL.line_d(DRAGON_APPROACH, p).x < r + 1.2:
		return true
	for e: Vector2 in H["entries"]:
		if p.distance_to(e) < r + 1.4:
			return true
	return false


static func _waterside_plants(S: RLib.TriSampler, R: RLib.TriSampler, W: WaterQ, H: Dictionary, obs: Array, SB: PtBins,
		rng: RandomNumberGenerator, placed: Array) -> Array:
	var out: Array = []
	var taken: Array = []
	for it: Dictionary in placed:
		var tg := String(it["tag"])
		taken.append([it["p"], 1.2 if String(it["kind"]) == "tree" else (1.8 if tg.ends_with("_mill") else 0.8)])
	for key: String in SITES:
		var rc: Rect2 = SITES[key]
		var cand: Array = []
		var y := rc.position.y + 0.25
		while y < rc.end.y:
			var x := rc.position.x + 0.25
			while x < rc.end.x:
				var p := Vector2(x, y)
				var zn := bank_zone(p, W, SB, S)
				if zn != "":
					cand.append([p, zn])
				x += 0.5
			y += 0.5
		# 決定性シャッフル（seeded；global RNG の shuffle() は毎回変わる）
		for ii in range(cand.size() - 1, 0, -1):
			var jj := rng.randi_range(0, ii)
			var tmp: Variant = cand[ii]
			cand[ii] = cand[jj]
			cand[jj] = tmp
		var n_site := 0
		var cap := 70 if key == "dragon" else 36
		for c: Array in cand:
			if n_site >= cap:
				break
			var p: Vector2 = c[0]
			var zn: String = c[1]
			# 叢：低周波ノイズで帯を切る（連続した壁にしない）
			var nz := _nz(p, 1.0 if key == "dragon" else 1.4)
			if nz < 0.5:
				continue
			var id := ""
			if zn != "crest":
				id = "wk_reed" if nz > 0.6 else "wk_reed_s"
			else:
				id = "wk_reed" if nz > 0.86 else ("wk_iris" if _nz(p * 1.7, 2.3) > 0.55 else ("wk_reed_s" if nz > 0.7 else "wk_sedge"))
			# 水車：輪の前（keep_clear）と walkway には置かない；龍神像：基座正面の陸側には置かない
			var bad := false
			for wc: Vector2 in WHEELS:
				if p.distance_to(wc) < 4.6:
					bad = true
			if p.distance_to(DRAGON) < 7.5 and p.x < DRAGON.x - 3.0:
				bad = true
			if bad or _blocked(p, 0.4, R, H, obs):
				continue
			var sp := 1.3 if id.begins_with("wk_reed") else 0.9
			var ok := true
			for t: Array in taken:
				if (t[0] as Vector2).distance_to(p) < maxf(sp, float(t[1])):
					ok = false
					break
			if not ok:
				continue
			var sc := rng.randf_range(0.95, 1.3)
			var it := item(S, "plant", id, p, rng.randf() * TAU, sc, key + "_bank")
			it["y"] = S.h(p.x, p.y) - 0.04
			out.append(it)
			taken.append([p, sp * 0.8])
			n_site += 1
			# 叢の取り巻き：同じ水分帯に 2–4 株（蘆の周りに菅・小蘆・花菖蒲）
			for k in rng.randi_range(3, 5):
				var a := rng.randf() * TAU
				var q := p + Vector2(cos(a), sin(a)) * rng.randf_range(0.7, 1.3)
				var zq := bank_zone(q, W, SB, S)
				if zq == "" or _blocked(q, 0.3, R, H, obs):
					continue
				var bad2 := false
				for wc: Vector2 in WHEELS:
					if q.distance_to(wc) < 4.6:
						bad2 = true
				if bad2 or (q.distance_to(DRAGON) < 7.5 and q.x < DRAGON.x - 3.0):
					continue
				var id2: String = "wk_reed_s" if zq != "crest" else (["wk_sedge", "wk_iris", "wk_sedge", "wk_reed_s"][rng.randi() % 4])
				var it2 := item(S, "plant", id2, q, rng.randf() * TAU, rng.randf_range(0.85, 1.2), key + "_bank")
				it2["y"] = S.h(q.x, q.y) - 0.04
				out.append(it2)
				n_site += 1
	return out


# ─────────────────────────── 地面 overlay（sg_ground：COLOR＝砂利, 苔, 土, 落葉；UV2＝濕潤, 淡出） ───────────────────────────

const G_STEP := 0.5


static func ground_w(P: Dictionary, key: String, p: Vector2) -> Variant:
	var W: WaterQ = P["W"]
	var rc: Rect2 = SITES[key]
	var de := Vector2(maxf(maxf(rc.position.x - p.x, p.x - rc.end.x), 0.0), maxf(maxf(rc.position.y - p.y, p.y - rc.end.y), 0.0)).length()
	if de > 0.0:
		return null
	var edge := minf(minf(p.x - rc.position.x, rc.end.x - p.x), minf(p.y - rc.position.y, rc.end.y - p.y))
	var dp := W.depth(p)
	# r4：水際で頂点を切らない（切ると 0.5 m 格子の階段縁が出る）→ 浅い水中まで伸ばし、水深で淡出（水面下は見えない）
	if dp > 0.6:
		return null
	var dw := W.dist(p, 6.5)
	var nz := _nz(p * 1.3, 1.1)
	var mo := 0.0
	var so := 0.0
	var li := 0.0
	var wet := 0.0
	if dw < 6.5:
		# 石積の際は苔を抜くが、二値で抜かず距離で段階的に（ぼかし前の段差を減らす）
		var hh := (P["S"] as RLib.TriSampler).h(p.x, p.y) - 0.4
		var SBp := P["SB"] as PtBins
		var st := 1.0 if SBp.near(p, 0.3, hh) else (0.55 if SBp.near(p, 0.65, hh) else (0.2 if SBp.near(p, 1.0, hh) else 0.0))
		var k := (1.0 - smoothstep(3.2, 6.5, dw)) * (1.0 - st)
		wet = 0.9 * k
		mo = clampf(1.15 * k * (0.8 + 0.4 * nz), 0.0, 1.0)
		so = 0.1 * k
	# 踏み跡：龍神像 参拝道、水車 walkway→入口
	if key == "dragon":
		var da := GL.line_d([Vector2(374.0, -188.0), Vector2(381.6, -188.0)], p).x
		if da < 1.2 + 0.4 * (nz - 0.5):
			so = maxf(so, 0.8)
		if Geometry2D.is_point_in_polygon(p, PackedVector2Array((P["H"] as Dictionary)["dragon_walkway"])):
			so = maxf(so, 0.7)
		# 基座陸側の足元：苔
		if absf(p.x - 382.6) < 1.2 and p.y > -194.0 and p.y < -182.0:
			mo = maxf(mo, 0.7)
	else:
		var k := int(key.substr(2)) - 1
		var wk := PackedVector2Array((P["H"] as Dictionary)["walkways"][k])
		var ent: Vector2 = (P["H"] as Dictionary)["entries"][k]
		if Geometry2D.is_point_in_polygon(p, wk) or GL.poly_d(wk, p) < 0.6:
			so = maxf(so, 0.85)
		if p.distance_to(ent) < 1.6 + 0.5 * (nz - 0.5):
			so = maxf(so, 0.75)
		# r4 作業場：踏み固め土（暗い石臼を明るい土の上に置いて前後景を分離、米俵は縁＝芝との境）＋入口からの踏み跡で水車と結ぶ
		var mills: Array = []
		for it: Dictionary in P["items"]:
			if String(it["tag"]) == "ww%d_mill" % (k + 1):
				mills.append(it["p"])
				var dt := p.distance_to(it["p"])
				var r0 := 0.9 if String(it["id"]) == "wk_usu" else 0.6
				so = maxf(so, 0.7 * (1.0 - smoothstep(r0, r0 + 0.9 + 0.3 * (nz - 0.5), dt)))
		if not mills.is_empty():
			var cen := Vector2.ZERO
			for q: Vector2 in mills:
				cen += q
			cen /= mills.size()
			var dtr := GL.line_d([ent, cen], p).x
			so = maxf(so, 0.5 * (1.0 - smoothstep(0.35, 0.8 + 0.3 * (nz - 0.5), dtr)))
	for it: Dictionary in P["items"]:
		if String(it["kind"]) != "tree" or String(it["id"]) in UNDER_IDS:
			continue
		var cr := float((P["M"] as Dictionary)[it["id"]]["crown_w"]) * 0.4 * (it["sc"] as Vector3).x
		var dt := p.distance_to(it["p"])
		if dt < cr:
			li = maxf(li, 0.5 * (1.0 - dt / cr) + 0.12)
			mo = maxf(mo, 0.25 * (1.0 - dt / cr))
	var tot := mo + so + li
	if tot > 1.0:
		mo /= tot
		so /= tot
		li /= tot
	# r4：外縁は alpha dither より權重（苔→草）で移す：alpha は低い tot で早めに 1
	var f := smoothstep(0.0, 0.08, tot) * clampf(edge / 2.0, 0.0, 1.0) * (1.0 - smoothstep(0.02, 0.2, dp))
	return [Color(0.0, mo, so, li), Vector2(wet, f)]


static func ground_mesh(P: Dictionary, key: String) -> ArrayMesh:
	var S: RLib.TriSampler = P["S"]
	var R: RLib.TriSampler = P["R"]
	var rc: Rect2 = SITES[key]
	var nx := int(ceil(rc.size.x / G_STEP))
	var nz := int(ceil(rc.size.y / G_STEP))
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var Cc := PackedColorArray()
	var U2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var vid := {}
	var WG := {}
	var boxes: Array = ((P["H"] as Dictionary)["boxes"] as Array) + (P["obs"] as Array)
	for j in nz + 1:
		for i in nx + 1:
			var p := rc.position + Vector2(i * G_STEP, j * G_STEP)
			var h := S.h(p.x, p.y)
			if is_nan(h) or not is_nan(R.h(p.x, p.y)):
				continue
			# r4：Hero／建物・農地の footprint は「三角面を抜く」（硬い 0.5 m 四角の穴）のではなく頂点ごと除外 → 下の縁淡出で柔らかく
			var inside := false
			for b: Rect2 in boxes:
				if b.size.x > 0.5 and b.size.y > 0.5 and b.grow(-0.1).has_point(p):
					inside = true
					break
			if inside:
				continue
			var w: Variant = ground_w(P, key, p)
			if w == null:
				continue
			WG[Vector2i(i, j)] = [(w as Array)[0], (w as Array)[1]]
	# r4：格子の階段縁を消す——①網格の縁からの格子距離（BFS、4 近傍）で淡出を 1.0 m かけて 0→1（緩い岸では縁が水面下 0.6 m に沈むので水際の濕り帯は残る）、②權重と淡出を 3×3 ガウスで 2 回ぼかす
	var NB := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
	var N4 := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
	var bd := {}
	var front: Array = []
	for g: Vector2i in WG:
		for d: Vector2i in NB:
			if not WG.has(g + d):
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
	for pass_i in 2:
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
	for g: Vector2i in WG:
		var uo: Vector2 = WG[g][1]
		uo.y *= smoothstep(0.0, 2.0, float(bd.get(g, 4)))
		WG[g][1] = uo
	for j in nz + 1:
		for i in nx + 1:
			var g := Vector2i(i, j)
			if not WG.has(g):
				continue
			var p := rc.position + Vector2(i * G_STEP, j * G_STEP)
			var h := S.h(p.x, p.y)
			var d := 0.4
			var nrm := Vector3(S.h(p.x - d, p.y) - S.h(p.x + d, p.y), 2.0 * d, S.h(p.x, p.y - d) - S.h(p.x, p.y + d))
			vid[g] = V.size()
			V.append(Vector3(p.x, h + 0.011, p.y))
			N.append(nrm.normalized() if nrm.is_finite() else Vector3.UP)
			Cc.append(WG[g][0])
			U2.append(WG[g][1])
	for j in nz:
		for i in nx:
			var k00: Variant = vid.get(Vector2i(i, j))
			var k10: Variant = vid.get(Vector2i(i + 1, j))
			var k01: Variant = vid.get(Vector2i(i, j + 1))
			var k11: Variant = vid.get(Vector2i(i + 1, j + 1))
			if k00 == null or k10 == null or k01 == null or k11 == null:
				continue
			# 対角は高低差の小さい方（斜面で折れ目を出さない）
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
	m.resource_name = "WS_Ground"
	# 水邊の濕った苔：R4-2 sg_ground shader（只讀）の instance 參數だけ水邊用に（濃い・暗い緑）
	m.set_shader_parameter("moss_tint", Vector3(0.30, 0.47, 0.19))
	m.set_shader_parameter("moss_contrast", 0.85)
	am.surface_set_material(0, m)
	am.resource_name = "ws_ground_" + key
	return am


# ─────────────────────────── 注連繩（r4：太繩＋撚り；樹幹 3 断面の外形に沿う） ───────────────────────────

## 繩の上・中・下 3 断面（R4-2 trunk_profile を只讀呼叫）の外側包絡 → 太い繩でも上下で樹皮に食い込まない
static func rope_plan(gos: Dictionary) -> Dictionary:
	var rh := float(gos.get("rope_h", SG.ROPE_H))
	var id := String(gos["id"])
	var mid: Array = SG.trunk_profile(id, rh)
	var c: Vector2 = mid[0]
	var nb := SG.ROPE_BINS
	var prof: Array = []
	prof.resize(nb)
	prof.fill(0.0)
	for tp: Array in [SG.trunk_profile(id, rh - ROPE_R * 0.8), mid, SG.trunk_profile(id, rh + ROPE_R * 0.8)]:
		var dc: Vector2 = (tp[0] as Vector2) - c
		for k in nb:
			var a := (k + 0.5) / nb * TAU
			prof[k] = maxf(float(prof[k]), float(tp[1][k]) + dc.dot(Vector2(cos(a), sin(a))))
	var pr: Array = []
	for k in nb:
		pr.append(maxf(float(prof[k]), maxf(float(prof[(k + 1) % nb]), float(prof[(k - 1 + nb) % nb])) * 0.96))
	return {"center": c, "prof": pr, "h": rh, "rope_r": ROPE_R}


## 繩心路徑（世界）：ROPE_PTS 点、断面半径は bin 間を線形補間
static func rope_path(gos: Dictionary, rope: Dictionary) -> Array:
	var xf := SG.xf_of(gos)
	var c: Vector2 = rope["center"]
	var pr: Array = rope["prof"]
	var nb := pr.size()
	var out: Array = []
	for i in ROPE_PTS:
		var a := (i + 0.5) / ROPE_PTS * TAU
		var fi := a / TAU * nb - 0.5
		var k0 := floori(fi)
		var t := fi - k0
		var rp := lerpf(float(pr[posmod(k0, nb)]), float(pr[posmod(k0 + 1, nb)]), t)
		var r := rp + ROPE_R + 0.025
		var sag := 0.07 * maxf(0.0, sin(a))
		out.append(xf * Vector3(c.x + cos(a) * r, float(rope["h"]) - sag, c.y + sin(a) * r))
	return out


static func rope_mesh(gos: Dictionary, rope: Dictionary) -> ArrayMesh:
	var path := rope_path(gos, rope)
	var n := path.size()
	var ctr := Vector3.ZERO
	for q: Vector3 in path:
		ctr += q
	ctr /= n
	var s_acc: Array = [0.0]
	for i in n:
		s_acc.append(float(s_acc[i]) + (path[(i + 1) % n] as Vector3).distance_to(path[i]))
	var L := float(s_acc[n])
	var nseg := maxi(1, roundi(L / 1.2))
	var UL := L / nseg
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var U := PackedVector2Array()
	var RU := Vector4(0.5, 0.0, 1.0, 0.25)
	var SU := Vector4(0.5, 0.25, 0.75, 0.5)
	var m := 14
	var rings: Array = []
	for i in n + 1:
		var p: Vector3 = path[i % n]
		var tg: Vector3 = ((path[(i + 1) % n] as Vector3) - (path[(i - 1 + n) % n] as Vector3)).normalized()
		var out := Vector3(p.x - ctr.x, 0, p.z - ctr.z).normalized()
		var b1 := (out - tg * out.dot(tg)).normalized()
		var b2 := tg.cross(b1).normalized()
		var s := float(s_acc[i])
		var ring: Array = []
		for k in m + 1:
			var ang := float(k) / m * TAU
			var nr := b1 * cos(ang) + b2 * sin(ang)
			var rr := ROPE_R * (1.0 + ROPE_TWIST * cos(2.0 * ang - TAU * s / ROPE_PITCH))
			ring.append([p + nr * rr, nr])
		rings.append(ring)
	for i in n:
		var u0 := fposmod(float(s_acc[i]) / UL, 1.0)
		var u1 := u0 + (float(s_acc[i + 1]) - float(s_acc[i])) / UL
		if u1 > 1.0 + 1e-4:
			u1 = 1.0
		for k in m:
			var va := lerpf(RU.y, RU.w, float(k) / m)
			var vb := lerpf(RU.y, RU.w, float(k + 1) / m)
			var ua := lerpf(RU.x, RU.z, u0)
			var ub := lerpf(RU.x, RU.z, u1)
			var q := [rings[i][k], rings[i + 1][k], rings[i + 1][k + 1], rings[i][k + 1]]
			var uv := [Vector2(ua, va), Vector2(ub, va), Vector2(ub, vb), Vector2(ua, vb)]
			for t3: Array in [[0, 1, 2], [0, 2, 3]]:
				for e: int in t3:
					V.append(q[e][0])
					N.append(q[e][1])
					U.append(uv[e])
	# 紙垂：正面（局部 +z）4 本＋背面 1 本；繩に比例して長く（四折 ≈ 0.72 m）
	for kk: float in [0.12, 0.23, 0.34, 0.45, 0.84]:
		var idx := int(kk * n) % n
		var top: Vector3 = path[idx] - Vector3(0, ROPE_R * 0.75, 0)
		var out := Vector3(top.x - ctr.x, 0, top.z - ctr.z).normalized()
		var side := out.cross(Vector3.UP).normalized()
		top += out * (ROPE_R * 0.75)
		for f in 4:
			var dx := side * (0.075 if f % 2 == 0 else -0.075)
			var c0 := top + dx + Vector3(0, -0.18 * f, 0)
			var hw := side * 0.075
			var a := c0 - hw
			var b := c0 + hw
			var c := b - Vector3(0, 0.17, 0)
			var d := a - Vector3(0, 0.17, 0)
			var su0 := lerpf(SU.x, SU.z, 0.1)
			var su1 := lerpf(SU.x, SU.z, 0.9)
			var v0 := lerpf(SU.y, SU.w, f / 4.0)
			var v1 := lerpf(SU.y, SU.w, (f + 1) / 4.0)
			for face: Array in [[a, b, c, d, out], [b, a, d, c, -out]]:
				var uvs := [Vector2(su0, v0), Vector2(su1, v0), Vector2(su1, v1), Vector2(su0, v1)]
				if face[4] != out:
					uvs = [Vector2(su1, v0), Vector2(su0, v0), Vector2(su0, v1), Vector2(su1, v1)]
				for t3: Array in [[0, 1, 2], [0, 2, 3]]:
					for e: int in t3:
						V.append(face[e])
						N.append(face[4])
						U.append(uvs[e])
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
	# P5 參道鳥居材質（只讀）を複製し albedo 1.0（R4-2 と同じ扱い）
	var mat := (load(SG.ROPE_MAT) as StandardMaterial3D).duplicate() as StandardMaterial3D
	mat.albedo_color = Color(1.0, 1.0, 1.0)
	mat.resource_name = "WS_Shimenawa"
	am.surface_set_material(0, mat)
	am.resource_name = "ws_shimenawa"
	return am


# ─────────────────────────── 烘焙 ───────────────────────────

static func bake(P: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	var gr := Node3D.new()
	gr.name = "Ground"
	root.add_child(gr)
	for key: String in SITES:
		var g := MeshInstance3D.new()
		g.name = key
		g.mesh = ground_mesh(P, key)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gr.add_child(g)
	var groups := {}
	for nm: String in ["Trees", "Under", "Plants", "Props", "Stones"]:
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
			t.set_meta("ws_tag", String(it["tag"]))
			(groups["Under"] if id in UNDER_IDS else groups["Trees"]).add_child(t)
			n_i += 1
			continue
		var node := Node3D.new()
		node.name = "%03d_%s" % [n_i, id]
		node.transform = xf
		node.set_meta("ws_id", id)
		node.set_meta("ws_tag", String(it["tag"]))
		var grp := "Plants" if id in PLANT_IDS else ("Stones" if id in STONE_IDS else "Props")
		(groups[grp] as Node).add_child(node)
		var dir := WK if id.begins_with("wk_") else (GK if id.begins_with("gk_") else RB)
		for lod in 2:
			var key := id + ("_l1" if lod == 1 else "")
			if not meshes.has(key):
				meshes[key] = load(dir + key + ".res")
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % lod
			mi.mesh = meshes[key]
			mi.visibility_range_begin = 0.0 if lod == 0 else LOD_SWITCH
			mi.visibility_range_end = LOD_SWITCH if lod == 0 else (90.0 if id in PLANT_IDS else 220.0)
			if lod == 1 or id in ["wk_sedge", "wk_iris", "wk_reed_s"]:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
		if PROP_BOX.has(id):
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
	# 注連繩（樟の御神木）：R4-2 の rope_plan／rope_mesh を流用（R4-2 lib は只讀呼叫）
	var gos: Dictionary = {}
	for it: Dictionary in P["items"]:
		if String(it["tag"]) == "goshinboku":
			gos = it
	if not gos.is_empty():
		var rm := MeshInstance3D.new()
		rm.name = "Shimenawa"
		rm.mesh = rope_mesh(gos, P["rope"])
		root.add_child(rm)
	root.set_meta("items", (P["items"] as Array).size())
	root.set_meta("shapes", ns)
	root.set_meta("art_revision", "P9 R4-4 水車／龍神像周邊 r4（ART_REVIEW）")
	return root


static func own(n: Node, owner: Node) -> void:
	SG.own(n, owner)
