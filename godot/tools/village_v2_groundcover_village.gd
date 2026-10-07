extends RefCounted
## 人間之里 V2 P9 R5-2 Groundcover 全村擴張（Pilot r10f ART_APPROVED の美術語彙を全村へ）。
##   Pilot lib（village_v2_groundcover_lib.gd）は一切変更しない＝Pilot 4 區の規劃・地面は r10f と逐位元組同一（gate で sha 固定）。
##   本檔は同じ素材（草叢 4 silhouette／牆腳雜草／野花／落葉／卵石／樹根／veg_kit 蕨・笹・低木／waterside_kit 菅・蘆・花菖蒲）、
##   同じ shader（gc_ground）、同じ bake を使い、全村用の空間索引（hash）と距離場（DGrid）だけを持つ。
## 語彙（使用者 2026-10-03 定版）：
##   草地＝群聚＋大片留白／土場＝裸土為主、邊緣・牆腳から草侵入／牆腳＝斷續雜草・苔、完整一圈にしない／
##   林緣＝forest-floor-first（暗土・落葉・苔の層）、小尺度樹根は gate にしない／
##   溪岸＝substrate-first、P7 核心外緣へ最大 0.5 m 淡入、P7 構件・水面は覆わない。
## 擴張の約束：均一 scatter 禁止・空地を全部消さない・P8 農田內部に入らない・P7 核心を上書きしない・R1–R4 封存 composition を壊さない・
##   區域ごとの密度は環境語意（地形の草／土、道路からの距離、牆、林床層、水際の自然度）で決める。

const GC := preload("res://tools/village_v2_groundcover_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")

## 全村範圍＝parcels bbox（x 117.2–501.6、z −260.8–125.4）＋20 m
const BB := Rect2(97.0, -281.0, 425.0, 427.0)
const SEED_V := 5301
const HC := 8.0
## 地面 overlay の格子（類別ごと）
const STEP := {"gen": 0.5, "forest": 0.4, "stream": 0.35}
## 一般類（gen：草地の草叢・土場・牆腳・路肩の micro）は P9 R5 Macro Expansion で退役——一般の地面は
##   village_v2_groundcover_mvillage.gd（全村 Macro）が担う。memb().x は全村 Macro の領域として残す。林緣・溪岸類別は Pilot 語彙のまま。
const CLASSES := ["forest", "stream"]
const ZPFX := "v_"
## R5 Macro Pilot 三區（village_v2_groundcover_macro.gd が担う）：全村 r5 はこの中に置かず、緣 4 m で交叉淡化
const MACRO_ZONES := {"A": Rect2(232.0, 74.0, 74.0, 54.0), "B": Rect2(312.0, -150.0, 84.0, 64.0), "C": Rect2(440.0, -252.0, 72.0, 66.0)}
## 竹林（BambooP9）＝R3 封存の核心：構件 AABB をこれだけ広げて除外
const BAMBOO_PAD := 1.2


# ─────────────────────────── 空間索引 ───────────────────────────

class RectHash:
	var cells := {}
	var rects: Array = []
	var tags: Array = []

	func add(r: Rect2, tag: String) -> void:
		var i := rects.size()
		rects.append(r)
		tags.append(tag)
		for cx in range(floori(r.position.x / 8.0), floori(r.end.x / 8.0) + 1):
			for cz in range(floori(r.position.y / 8.0), floori(r.end.y / 8.0) + 1):
				var k := Vector2i(cx, cz)
				if not cells.has(k):
					cells[k] = []
				(cells[k] as Array).append(i)

	func hit(p: Vector2) -> String:
		for i: int in cells.get(Vector2i(floori(p.x / 8.0), floori(p.y / 8.0)), []):
			if (rects[i] as Rect2).has_point(p):
				return tags[i]
		return ""


class ObbHash:
	var cells := {}
	var obbs: Array = []

	func add(o: Dictionary, margin: float) -> void:
		var i := obbs.size()
		obbs.append(o)
		var hh: Vector2 = o["h"]
		var rad := hh.length() + margin
		var c: Vector2 = o["o"]
		for cx in range(floori((c.x - rad) / 8.0), floori((c.x + rad) / 8.0) + 1):
			for cz in range(floori((c.y - rad) / 8.0), floori((c.y + rad) / 8.0) + 1):
				var k := Vector2i(cx, cz)
				if not cells.has(k):
					cells[k] = []
				(cells[k] as Array).append(i)

	func near(p: Vector2) -> Array:
		return cells.get(Vector2i(floori(p.x / 8.0), floori(p.y / 8.0)), [])

	func d(p: Vector2) -> float:
		var best := 99.0
		for i: int in near(p):
			best = minf(best, GC.obb_d(obbs[i], p))
		return best


class PtHash:
	var cells := {}

	func add(p: Vector2) -> void:
		var k := Vector2i(floori(p.x / 2.0), floori(p.y / 2.0))
		if not cells.has(k):
			cells[k] = []
		(cells[k] as Array).append(p)

	func any_within(p: Vector2, r: float) -> bool:
		var k := Vector2i(floori(p.x / 2.0), floori(p.y / 2.0))
		var n := int(ceil(r / 2.0))
		for dx in range(-n, n + 1):
			for dz in range(-n, n + 1):
				for q: Vector2 in cells.get(k + Vector2i(dx, dz), []):
					if q.distance_to(p) < r:
						return true
		return false


# ─────────────────────────── 文脈 ───────────────────────────

## C＝Pilot の文脈（S／R／WS／FS は全村共通の取樣器なのでそのまま使う）
static func context_v(v: Node3D, C: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var CV := {"S": C["S"], "R": C["R"], "WS": C["WS"], "FS": C["FS"], "bb": BB, "drifts": []}
	# 建物 OBB（全 187 棟）
	var OH := ObbHash.new()
	var obb_list: Array = []
	for b in v.get_node("Districts").find_children("B_*", "", true, false):
		var n3 := b as Node3D
		if n3 == null or not n3.has_meta("width_m"):
			continue
		var o := Vector2(n3.global_position.x, n3.global_position.z)
		if not BB.grow(10.0).has_point(o):
			continue
		var bx := Vector2(n3.global_transform.basis.x.x, n3.global_transform.basis.x.z).normalized()
		var bz := Vector2(n3.global_transform.basis.z.x, n3.global_transform.basis.z.z).normalized()
		var od := {"o": o, "bx": bx, "bz": bz, "h": Vector2(float(n3.get_meta("width_m")) * 0.5, float(n3.get_meta("depth_m")) * 0.5), "name": String(n3.name)}
		OH.add(od, 5.0)
		obb_list.append(od)
	CV["OH"] = OH
	CV["obb"] = obb_list
	# 障礙物：P6 frontage（地面 overlay も描かない）と Hero／その他構件（地面は下に描いてよい）
	var OB := RectHash.new()
	for root_name in ["Districts", "Landmarks"]:
		for mi in v.get_node(root_name).find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null or not g.is_visible_in_tree():
				continue
			var path := String(v.get_path_to(g))
			var front := path.contains("/Frontage/")
			if path.contains("/B_") and not front and String(g.name) != "Foundation":
				continue
			var a := g.global_transform * g.get_aabb()
			var r := Rect2(a.position.x, a.position.z, a.size.x, a.size.z)
			if r.size.x > 30.0 or r.size.y > 30.0 or not BB.intersects(r) or a.size.y < 0.08:
				continue
			OB.add(r, "frontage" if front else "obstacle")
	CV["OB"] = OB
	# 封存 overlay（R4 Hero 周邊・稗田邸庭園・鎮守之森…）＋竹林核心
	var SH := RectHash.new()
	for nm: String in GC.SEALED_OVERLAYS:
		var ov := v.get_node_or_null("Vegetation/" + nm)
		if ov == null:
			continue
		for mi in ov.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null:
				continue
			var a := g.global_transform * g.get_aabb()
			var r := Rect2(a.position.x, a.position.z, a.size.x, a.size.z)
			if BB.intersects(r.grow(1.0)):
				SH.add(r.grow(1.0) if String(g.name) != "Ground" else r.grow(0.5), "sealed:" + nm)
	var bam := v.get_node_or_null("Vegetation/BambooP9/Near")
	var n_bam := 0
	if bam != null:
		for mi in bam.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null:
				continue
			var a := g.global_transform * g.get_aabb()
			var r := Rect2(a.position.x, a.position.z, a.size.x, a.size.z)
			if r.size.x < 20.0 and r.size.y < 20.0 and BB.intersects(r.grow(BAMBOO_PAD)):
				SH.add(r.grow(BAMBOO_PAD), "sealed:BambooP9")
				n_bam += 1
	CV["SH"] = SH
	CV["n_bamboo_rects"] = n_bam
	# P7 河岸構件（區塊 AABB）＋上面 sampler（LOD0）
	var RB := RectHash.new()
	var RBS := RLib.TriSampler.new()
	var n_rbf := 0
	for mi in v.get_node("Riverbank").find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		if g.mesh == null:
			continue
		var a := g.global_transform * g.get_aabb()
		var r := Rect2(a.position.x, a.position.z, a.size.x, a.size.z)
		if not BB.intersects(r.grow(1.5)):
			continue
		RB.add(r.grow(1.0), "rb")
		if g.visibility_range_begin <= 0.001:
			var fc := g.mesh.get_faces()
			n_rbf += fc.size() / 3
			RBS.add(fc, RLib.rel_xf(g, v))
	var bridges := v.get_node_or_null("Roads/Bridges")
	if bridges != null:
		for mi in bridges.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null or g.visibility_range_begin > 0.001:
				continue
			var a := g.global_transform * g.get_aabb()
			if not BB.intersects(Rect2(a.position.x, a.position.z, a.size.x, a.size.z).grow(1.0)):
				continue
			var fc := g.mesh.get_faces()
			n_rbf += fc.size() / 3
			RBS.add(fc, RLib.rel_xf(g, v))
	CV["RB"] = RB
	CV["RBS"] = RBS
	CV["n_rb_faces"] = n_rbf
	# 樹＝封存 ForestP9 の實ノード（Pilot と同じ規則）
	var trees: Array = []
	var th := {}
	var uh := {}
	var tbb := BB.grow(24.0)
	var fnear := v.get_node_or_null("Vegetation/ForestP9/Near")
	if fnear != null:
		for ch in fnear.get_children():
			for t in ch.get_children():
				var nm := String(t.name)
				if not (t is Node3D) or nm.length() < 6 or nm[4] != "_":
					continue
				var tn := t as Node3D
				var p := Vector2(tn.global_position.x, tn.global_position.z)
				if not tbb.has_point(p):
					continue
				var id := nm.substr(5)
				if GC.UNDER_IDS.any(func(u: String) -> bool: return id.begins_with(u)):
					var ku := Vector2i(floori(p.x / 4.0), floori(p.y / 4.0))
					if not uh.has(ku):
						uh[ku] = []
					uh[ku].append(p)
					continue
				var sc := tn.global_transform.basis.get_scale().x
				var cr := 2.5 * sc
				for mi in tn.find_children("LOD0", "MeshInstance3D", true, false):
					var ab := (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
					cr = 0.4 * maxf(ab.size.x, ab.size.z)
					break
				cr = clampf(cr, 1.2, 4.5)
				trees.append({"id": id, "p": p, "sc": sc, "cr": cr})
				var k := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
				if not th.has(k):
					th[k] = []
				th[k].append([p, cr])
	CV["trees"] = trees
	CV["tree_hash"] = th
	CV["under_hash"] = uh
	var TW := GC.TerrainW.new()
	for nm in ["Terrain/MainTerrain", "Terrain/NorthHill", "Terrain/RiverTerrain"]:
		var tm := v.get_node_or_null(nm) as MeshInstance3D
		if tm != null:
			TW.add(tm, RLib.rel_xf(tm, v), BB.grow(10.0))
	CV["TW"] = TW
	var fm := v.get_node("Terrain/FarmlandTerrain") as MeshInstance3D
	var fa := fm.global_transform * fm.get_aabb()
	CV["frect"] = Rect2(fa.position.x, fa.position.z, fa.size.x, fa.size.z).grow(18.0).intersection(BB.grow(4.0))
	CV["ms_context"] = Time.get_ticks_msec() - t0
	fields_v(CV)
	CV["ms_fields"] = Time.get_ticks_msec() - t0 - int(CV["ms_context"])
	return CV


## 全村の距離場：水面・地形の林床層・地形の草・路面
static func fields_v(CV: Dictionary) -> void:
	var S: RLib.TriSampler = CV["S"]
	var WS: RLib.TriSampler = CV["WS"]
	var R: RLib.TriSampler = CV["R"]
	var TW: GC.TerrainW = CV["TW"]
	var gb := BB.grow(9.0)
	var wg := GC.DGrid.new()
	wg.build(gb, 0.4, func(q: Vector2) -> bool:
		var wh := WS.h(q.x, q.y)
		return not is_nan(wh) and wh > S.h(q.x, q.y) + 0.02)
	CV["wgrid"] = wg
	var sg := GC.DGrid.new()
	sg.build(gb, 0.5, func(q: Vector2) -> bool:
		var w := TW.weights(q)
		return not w.is_empty() and w[4] >= 0.5)
	CV["seam"] = sg
	var gg := GC.DGrid.new()
	gg.build(gb, 0.5, func(q: Vector2) -> bool: return TW.grass(q) >= GC.GRASS_MIN)
	CV["ggrid"] = gg
	var rg := GC.DGrid.new()
	rg.build(gb, 0.4, func(q: Vector2) -> bool: return not is_nan(R.h(q.x, q.y)))
	CV["rgrid"] = rg
	# P8 農田までの距離場（田と村の間の水渠の判定・全村 Macro の農田交界）
	var FS: RLib.TriSampler = CV["FS"]
	var fg := GC.DGrid.new()
	fg.build(CV["frect"], 0.5, func(q: Vector2) -> bool: return not is_nan(FS.h(q.x, q.y)))
	CV["fgrid"] = fg


# ─────────────────────────── 問い合わせ ───────────────────────────

## P8 農田までの距離（田の中＝−、外＝＋、範圍外＝99）
static func farm_d(CV: Dictionary, p: Vector2) -> float:
	if not (CV["frect"] as Rect2).has_point(p):
		return 99.0
	return (CV["fgrid"] as GC.DGrid).at(p)


static func wall_d(CV: Dictionary, p: Vector2) -> float:
	return (CV["OH"] as ObbHash).d(p)


## 路面からの符號付き距離（路面上＝−、外＝＋）
static func road_sd(CV: Dictionary, p: Vector2) -> float:
	return (CV["rgrid"] as GC.DGrid).at(p)


static func on_road(CV: Dictionary, p: Vector2) -> bool:
	return not is_nan((CV["R"] as RLib.TriSampler).h(p.x, p.y))


## Pilot 區（凍結）の淡出係数：Pilot 地面が縁 4 m で淡出する分だけ全村側を淡入させる（1＝Pilot が完全に担う）
static func pilot_k(p: Vector2) -> float:
	var k := 0.0
	for z: String in GC.ZONE_ORDER:
		if GC.in_zone(z, p):
			k = maxf(k, smoothstep(0.0, 4.0, GC.zone_inset(z, p)))
	for zn: String in MACRO_ZONES:
		var r: Rect2 = MACRO_ZONES[zn]
		if r.has_point(p):
			k = maxf(k, smoothstep(0.0, 4.0, minf(minf(p.x - r.position.x, r.end.x - p.x), minf(p.y - r.position.y, r.end.y - p.y))))
	return k


static func in_macro(p: Vector2) -> bool:
	for zn: String in MACRO_ZONES:
		if (MACRO_ZONES[zn] as Rect2).has_point(p):
			return true
	return false


static func in_pilot(p: Vector2) -> bool:
	return GC.zone_of(p) != "" or in_macro(p)


## 置いてはいけない所（Pilot の blocked と同じ語彙＋"pilot"）
static func blocked_v(CV: Dictionary, p: Vector2, allow_road_edge := false, road_in := 0.35, macro_ok := false) -> String:
	if not BB.has_point(p):
		return "bb"
	if is_nan((CV["S"] as RLib.TriSampler).h(p.x, p.y)):
		return "terrain"
	if GC.zone_of(p) != "" or (not macro_ok and in_macro(p)):
		return "pilot"
	if not is_nan((CV["FS"] as RLib.TriSampler).h(p.x, p.y)):
		return "farm"
	if wall_d(CV, p) < 0.05:
		return "building"
	if GC.trunk_d(CV, p) < 0.4:
		return "trunk"
	var ob := (CV["OB"] as RectHash).hit(p)
	if ob != "":
		return ob
	var sh := (CV["SH"] as RectHash).hit(p)
	if sh != "":
		return sh
	if (CV["RB"] as RectHash).hit(p) != "" and GC.wdist(CV, p) <= GC.RB_CORE:
		return "riverbank"
	if p7_covered(CV, p):
		return "p7piece"
	if on_road(CV, p):
		if not allow_road_edge or road_sd(CV, p) < -road_in:
			return "road"
	var wh := (CV["WS"] as RLib.TriSampler).h(p.x, p.y)
	if not is_nan(wh) and wh > (CV["S"] as RLib.TriSampler).h(p.x, p.y) - 0.02:
		return "water"
	return ""


static func p7_covered(CV: Dictionary, p: Vector2) -> bool:
	var h := (CV["RBS"] as RLib.TriSampler).h(p.x, p.y)
	return not is_nan(h) and h > (CV["S"] as RLib.TriSampler).h(p.x, p.y) - 0.03


## 水際の自然度（1＝低い自然岸、0＝護岸・高い岸）：岸の地表が最寄り水面より何 m 高いか
static func bank_nat(CV: Dictionary, p: Vector2) -> float:
	var S: RLib.TriSampler = CV["S"]
	var WS: RLib.TriSampler = CV["WS"]
	var g := GC.wgrad(CV, p)
	var wd := GC.wdist(CV, p)
	for k in 4:
		var q := p - g * (wd + 0.3 + 0.4 * k)
		var wl := WS.h(q.x, q.y)
		if not is_nan(wl):
			return 1.0 - smoothstep(0.9, 1.8, S.h(p.x, p.y) - wl)
	return 0.5


## 常走の度合い（道路の縁から 0.8–3 m で 1 → 0）
static func walk_d(CV: Dictionary, p: Vector2) -> float:
	return maxf(road_sd(CV, p), 0.0)


## 土場の「草が侵入しうる度合い」（Pilot lawn_inv と同式：草の縁 2.4 m・牆腳 3.4 m から、道路から 1.6 m 以上離れた所だけ）
static func dirt_inv(CV: Dictionary, p: Vector2) -> float:
	var src := maxf(0.6 * (1.0 - smoothstep(0.5, 2.4, GC.gdist(CV, p))), 1.0 - smoothstep(0.6, 3.4, wall_d(CV, p)))
	return src * smoothstep(1.6, 4.5, walk_d(CV, p))


## 地面の草色舌用の侵入度（宅地が狭い全村では牆 2.2 m まで；草叢の dirt_inv より狭い）
static func dirt_inv_g(CV: Dictionary, p: Vector2) -> float:
	var src := maxf(0.6 * (1.0 - smoothstep(0.5, 2.4, GC.gdist(CV, p))), 1.0 - smoothstep(0.4, 2.2, wall_d(CV, p)))
	return src * smoothstep(1.6, 4.5, walk_d(CV, p))


## 類別 membership（gen, forest, stream）：溪岸 → 林緣 → 一般 の優先、境は 2 m で交叉淡化
static func memb(CV: Dictionary, p: Vector2) -> Vector3:
	var e := GC.wdist(CV, p) - GC.RB_CORE
	# 溪岸類別の幅：自然岸 6.5–8.5 m、護岸・高い岸（水渠など）は 1.5–3 m（その外は全村 Macro が渠沿いの草・踏み跡を担う）
	var ms := 0.0
	if e <= 8.5:
		var nat := bank_nat(CV, p)
		# 田と村の間の水渠（田が水の向こう 40 m 以内）：溪岸類別は細く、その外は全村 Macro が農田交界（渠上の草・渠沿いの農路）を担う
		var fd := farm_d(CV, p)
		if fd < 40.0 and fd > e + GC.RB_CORE + 2.0:
			nat = minf(nat, 0.15)
		ms = 1.0 - smoothstep(lerpf(1.5, 6.5, nat), lerpf(3.0, 8.5, nat), e)
	var sd := GC.seam_d(CV, p)
	var mf := smoothstep(-7.0, -5.0, sd) * (1.0 - smoothstep(10.0, 12.0, sd)) * (1.0 - ms)
	return Vector3(maxf(1.0 - ms - mf, 0.0), mf, ms)


# ─────────────────────────── 規劃 ───────────────────────────

## Pilot 規劃 P に全村分を追加する（Pilot の items／nodes は先頭のまま、順序・内容とも不変）
static func extend(P: Dictionary, v: Node3D) -> void:
	var t0 := Time.get_ticks_msec()
	var CV := context_v(v, P["C"])
	P["CV"] = CV
	P["n_pilot_items"] = (P["items"] as Array).size()
	P["n_pilot_nodes"] = (P["nodes"] as Array).size()
	var items: Array = []
	var nodes: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_V
	var NH := PtHash.new()
	CV["NH"] = NH
	# 一般類（_v_lawn／_v_dirt／_v_wall／_v_shoulder）は退役：全村 Macro が担う（tiny grass で空地を埋めない）
	_v_forest(CV, rng, items, nodes)
	_v_stream(CV, rng, items, nodes)
	(P["items"] as Array).append_array(items)
	(P["nodes"] as Array).append_array(nodes)
	var stats: Dictionary = P["stats"]
	for it: Dictionary in items:
		var key := "%s/%s" % [it["zone"], GC.KIND_NAMES[int(it["k"])]]
		stats[key] = int(stats.get(key, 0)) + 1
	for it: Dictionary in nodes:
		var key := "%s/%s" % [it["zone"], it["id"]]
		stats[key] = int(stats.get(key, 0)) + 1
	P["ms_village"] = Time.get_ticks_msec() - t0


static func grid_pts(step: float, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var gx := BB.position.x
	while gx < BB.end.x:
		var gz := BB.position.y
		while gz < BB.end.y:
			out.append(Vector2(gx + rng.randf_range(0.0, step), gz + rng.randf_range(0.0, step)))
			gz += step
		gx += step
	return out


## Pilot tuft_group と同じ群れ（中心ほど立ち株・穂草、縁は丸株・枯れ株、外に飛び株）——判定だけ全村索引
static func tuft_group_v(CV: Dictionary, rng: RandomNumberGenerator, items: Array, c: Vector2, r: float, n: int, zone: String, dry: float, tall_p: float, allow_road := false, tag := "tuft", on_dirt := false, register := true, hscale := 1.0, gmin := 0.45) -> void:
	var S: RLib.TriSampler = CV["S"]
	if register:
		(CV["drifts"] as Array).append([c, r])
	var ang := rng.randf() * TAU
	var ax := Vector2(cos(ang), sin(ang))
	var ay := Vector2(-ax.y, ax.x)
	var el := rng.randf_range(0.45, 0.85)
	for i in n:
		var u := Vector2(rng.randfn(0.0, 0.45), rng.randfn(0.0, 0.45))
		if u.length() > 1.0:
			u = u.normalized() * rng.randf_range(0.7, 1.0)
		var p := c + ax * u.x * r + ay * u.y * r * el
		if blocked_v(CV, p, allow_road) != "":
			continue
		if on_dirt:
			if dirt_inv(CV, p) < 0.12:
				continue
		else:
			var gm := GC.GRASS_MIN_EDGE if allow_road else gmin
			if rng.randf() > smoothstep(gm - GC.FEATHER, gm + 0.15, GC.grass_w(CV, p)):
				continue
		var cen := clampf(1.0 - u.length(), 0.0, 1.0)
		var k := GC.K_SHORT
		var h := rng.randf_range(0.18, 0.30)
		var roll := rng.randf()
		var p_stem := tall_p * (0.3 + cen)
		var p_fine := p_stem + 0.45
		var p_dry := p_fine + 0.1 + 0.15 * dry
		if roll < p_stem:
			k = GC.K_STEM
			h = rng.randf_range(0.45, 0.70)
		elif roll < p_fine:
			k = GC.K_FINE
			h = rng.randf_range(0.30, 0.48) * lerpf(0.75, 1.0, cen)
		elif roll < p_dry:
			k = GC.K_DRY
			h = rng.randf_range(0.24, 0.34)
		items.append(GC.gi(S, k, p, h * hscale, rng.randf_range(0.85, 1.2), rng.randf() * TAU, GC.grass_col(rng, 0.85 if k == GC.K_DRY else dry), zone, tag))
	for i in rng.randi_range(0, 2):
		var a := rng.randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * r * rng.randf_range(1.3, 2.2)
		var ok_g := dirt_inv(CV, p) >= 0.12 if on_dirt else GC.grass_w(CV, p) >= gmin
		if blocked_v(CV, p, allow_road) == "" and ok_g:
			items.append(GC.gi(S, GC.K_SHORT, p, rng.randf_range(0.18, 0.28), 1.0, rng.randf() * TAU, GC.grass_col(rng, dry), zone, tag))


## 大片留白の遮罩（40–70 m 尺度の斑；低い所＝草叢を置かない開けた草地）
static func macro_open(p: Vector2) -> float:
	return GC._n(p * 0.055, 1.0, 91.0)


## 一般の場か（溪岸・林緣の類別が主でない）
static func is_gen(CV: Dictionary, p: Vector2) -> bool:
	var m := memb(CV, p)
	return m.x >= 0.5


## 1 開闊草地（Pilot _lawn と同じ語彙）：低頻 noise の島だけに群れ（大片留白）、道路の近くは減らす
static func _v_lawn(CV: Dictionary, rng: RandomNumberGenerator, items: Array) -> void:
	var S: RLib.TriSampler = CV["S"]
	for c: Vector2 in grid_pts(3.2, rng):
		var pn := GC._n(c * 0.33, 1.0, 1.3)
		if pn < 0.55 or macro_open(c) < 0.47:
			continue
		var pd := walk_d(CV, c)
		if pd < 1.6 or blocked_v(CV, c) != "" or GC.grass_w(CV, c) < 0.6 or not is_gen(CV, c):
			continue
		if wall_d(CV, c) < 1.2:
			continue
		var k := smoothstep(0.55, 0.85, pn) * smoothstep(1.6, 4.0, pd)
		if rng.randf() > 0.35 + 0.65 * k:
			continue
		var r := lerpf(0.8, 2.1, k) * rng.randf_range(0.8, 1.2)
		tuft_group_v(CV, rng, items, c, r, int(lerpf(18, 42, k) * rng.randf_range(0.7, 1.2)), "v_lawn", 0.15 + 0.25 * GC._n(c * 0.2, 1.0, 4.0), 0.22)
		if rng.randf() < 0.28 * k:
			var kf := GC.K_FLOWER_Y if GC._n(c * 0.5, 1.0, 9.0) > 0.5 else GC.K_FLOWER_V
			for i in rng.randi_range(2, 5):
				var p := c + Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.8, 0.8))
				if blocked_v(CV, p) == "":
					items.append(GC.gi(S, kf, p, rng.randf_range(0.8, 1.15), 1.0, rng.randf() * TAU, Color(1, 1, 1), "v_lawn", "flower"))
	# 近地層 micro（疎ら、noise で濃淡）
	for q: Vector2 in grid_pts(1.2, rng):
		if rng.randf() > (0.08 + 0.18 * GC._n(q * 0.5, 1.0, 29.0)) * smoothstep(0.33, 0.55, macro_open(q)) or walk_d(CV, q) < 0.9 or wall_d(CV, q) < 0.8:
			continue
		if blocked_v(CV, q) != "" or GC.grass_w(CV, q) < 0.55 or not is_gen(CV, q):
			continue
		var km := GC.K_DRY if rng.randf() < 0.25 else GC.K_SHORT
		items.append(GC.gi(S, km, q, rng.randf_range(0.08, 0.15), rng.randf_range(1.0, 1.4), rng.randf() * TAU, GC.grass_col(rng, 0.25), "v_lawn", "micro"))
	# 群れの間の疎らな低い株（noise 中間帯・確率で間引く）
	for q: Vector2 in grid_pts(1.6, rng):
		var pn2 := GC._n(q * 0.33, 1.0, 1.3)
		if pn2 < 0.42 or pn2 > 0.6 or rng.randf() > 0.1 or macro_open(q) < 0.5 or walk_d(CV, q) < 1.2 or wall_d(CV, q) < 1.2:
			continue
		if blocked_v(CV, q) != "" or GC.grass_w(CV, q) < 0.6 or not is_gen(CV, q):
			continue
		var kk := GC.K_DRY if rng.randf() < 0.3 else GC.K_SHORT
		items.append(GC.gi(S, kk, q, rng.randf_range(0.12, 0.22), rng.randf_range(0.9, 1.2), rng.randf() * TAU, GC.grass_col(rng, 0.2), "v_lawn", "tuft"))
	# 地形の草／土の境界（等値線）の草側に小さな群れ（断続）
	for q: Vector2 in grid_pts(1.0, rng):
		if blocked_v(CV, q) != "" or not is_gen(CV, q):
			continue
		var gw := GC.grass_w(CV, q)
		if gw < 0.5 or gw > 0.72 or GC._n(q * 0.6, 1.0, 23.0) < 0.62 or rng.randf() < 0.7 or walk_d(CV, q) < 1.0 or macro_open(q) < 0.45:
			continue
		tuft_group_v(CV, rng, items, q, rng.randf_range(0.3, 0.6), rng.randi_range(3, 6), "v_lawn", 0.3, 0.1)


## 2 土場（Pilot _lawn_dirt と同じ語彙）：地形が土の所に、縁・牆腳・低使用區から局所的な草叢、中央と通行區は裸土
static func _v_dirt(CV: Dictionary, rng: RandomNumberGenerator, items: Array) -> void:
	var S: RLib.TriSampler = CV["S"]
	for c: Vector2 in grid_pts(1.8, rng):
		if blocked_v(CV, c) != "" or GC.grass_w(CV, c) >= GC.GRASS_MIN or wall_d(CV, c) < 0.9 or not is_gen(CV, c):
			continue
		var pr := smoothstep(0.3, 0.9, dirt_inv(CV, c)) * smoothstep(0.35, 0.65, GC._n(c * 0.45, 1.0, 47.0))
		if rng.randf() > pr * (0.85 if wall_d(CV, c) < 2.5 else 0.45):
			continue
		tuft_group_v(CV, rng, items, c, rng.randf_range(0.35, 0.8), rng.randi_range(4, 9), "v_dirt", 0.45, 0.03, false, "dirt", true, false, 0.75)
		if rng.randf() < 0.1:
			for j in rng.randi_range(1, 2):
				var q := c + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
				if blocked_v(CV, q) == "" and dirt_inv(CV, q) >= 0.12:
					items.append(GC.gi(S, GC.K_ROSETTE, q, rng.randf_range(0.7, 1.0), 1.0, rng.randf() * TAU, Color(0.85, 0.9, 0.8), "v_dirt", "dirt"))


## 3 牆腳（Pilot _wall_foot と同じ語彙）：周長沿いの noise の山だけ（斷續、完整一圈にしない）、路面直結の正面は除く
static func _v_wall(CV: Dictionary, rng: RandomNumberGenerator, items: Array) -> void:
	var S: RLib.TriSampler = CV["S"]
	for o: Dictionary in CV["obb"]:
		var hh: Vector2 = o["h"]
		var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		# ① 候補の叢（壁面ごと：約 1/3 の壁は何も生えない、残りも noise の山だけ・連続 1.2 m ごとに 3.5–5.5 m の切れ目）
		var cands: Array = []
		var exposed := 0.0
		for e in 4:
			var a: Vector2 = corners[e]
			var b: Vector2 = corners[(e + 1) % 4]
			var A := (o["o"] as Vector2) + (o["bx"] as Vector2) * a.x * hh.x + (o["bz"] as Vector2) * a.y * hh.y
			var B := (o["o"] as Vector2) + (o["bx"] as Vector2) * b.x * hh.x + (o["bz"] as Vector2) * b.y * hh.y
			var L := A.distance_to(B)
			var out := ((A + B) * 0.5 - (o["o"] as Vector2)).normalized()
			# 露出周長（路面直結・frontage・封存・建物で塞がれていない牆腳の長さ）
			var ts := 0.25
			while ts < L:
				var w := A.lerp(B, ts / L) + out * 0.3
				if blocked_v(CV, w) == "" and road_sd(CV, w) >= 0.6:
					exposed += 0.5
				ts += 0.5
			if GC._n((A + B) * 0.5 * 0.21, 1.0, 97.0 + e) < 0.32:
				continue
			var t := rng.randf_range(0.0, 0.6)
			var run0 := -1.0
			while t < L:
				var q := A.lerp(B, t / L)
				t += rng.randf_range(0.55, 0.9)
				if not BB.has_point(q) or in_pilot(q):
					continue
				var corner := minf(t, L - t) < 1.2
				if GC._n(q * 0.9, 1.0, float(e) * 2.1 + hh.x) < (0.6 if corner else 0.68):
					run0 = -1.0
					continue
				if run0 < 0.0:
					run0 = t
				elif t - run0 > 1.2:
					t += rng.randf_range(3.5, 5.5)
					run0 = -1.0
					continue
				var c := q + out * rng.randf_range(0.15, 0.35)
				if blocked_v(CV, c) != "" or road_sd(CV, c) < 0.6:
					continue
				# 隣棟との隙間が 1.2 m 未満の路地（日が入らず、両側の牆腳草が一本の帯になる）には置かない
				var other := 99.0
				for oi: int in (CV["OH"] as ObbHash).near(c):
					var o2: Dictionary = (CV["OH"] as ObbHash).obbs[oi]
					if o2["name"] != o["name"]:
						other = minf(other, GC.obb_d(o2, c))
				if other < 1.2:
					continue
				cands.append([q, c, out, (B - A).normalized()])
		# ② 棟ごとの予算：叢 1 つ ≈ 牆腳 2.4 m 分（株の広がり ±0.4 m＋見た目の幅）、露出周長の 40 % まで（小さな棟・短い露出壁でも完整一圈・六割超にしない）
		var nmax := maxi(1, int(floor(0.40 * exposed / 2.4)))
		if cands.size() > nmax:
			GC._shuffle(cands, rng)
			cands = cands.slice(0, nmax)
		for cd: Array in cands:
			var q: Vector2 = cd[0]
			var c: Vector2 = cd[1]
			var out: Vector2 = cd[2]
			var tg: Vector2 = cd[3]
			for j in rng.randi_range(7, 12):
				var p := c + tg * rng.randf_range(-0.4, 0.4) + out * rng.randf_range(-0.08, 0.22)
				if blocked_v(CV, p) != "":
					continue
				var r := rng.randf()
				if r < 0.28:
					items.append(GC.gi(S, GC.K_ROSETTE, p, rng.randf_range(0.7, 1.0), 1.0, rng.randf() * TAU, Color(0.85, 0.9, 0.8).lerp(Color(1, 1, 1), rng.randf()), "v_wall", "wallfoot"))
				elif r < 0.5:
					items.append(GC.gi(S, GC.K_TALLWEED, p, rng.randf_range(0.75, 1.15), 1.0, rng.randf() * TAU, Color(0.88, 0.92, 0.84), "v_wall", "wallfoot"))
				elif r < 0.84:
					items.append(GC.gi(S, GC.K_FINE, p, rng.randf_range(0.30, 0.50), 1.0, rng.randf() * TAU, GC.grass_col(rng, 0.25), "v_wall", "wallfoot"))
				elif r < 0.95:
					var pm := q + out * rng.randf_range(0.12, 0.3)
					if blocked_v(CV, pm) == "":
						items.append(GC.gi(S, GC.K_MOSS, pm, rng.randf_range(0.8, 1.2), rng.randf_range(0.9, 1.5), rng.randf() * TAU, Color(1, 1, 1), "v_wall", "wallfoot"))
				else:
					items.append(GC.gi(S, GC.K_STONE, p, rng.randf_range(0.6, 1.0), 1.0, rng.randf() * TAU, Color(1, 1, 1), "v_wall", "wallfoot"))


## 4 路肩（Pilot _street の路肩と同じ語彙）：路縁の外が地形の草の所だけ、noise の山に小さな群れ、群れの後は 1.5–3.5 m 空ける
static func _v_shoulder(CV: Dictionary, rng: RandomNumberGenerator, items: Array) -> void:
	var used := PtHash.new()
	for q: Vector2 in grid_pts(0.8, rng):
		var rs := road_sd(CV, q)
		if rs < 0.0 or rs > 0.45:
			continue
		if in_pilot(q) or not is_gen(CV, q) or GC.grass_w(CV, q) < 0.45:
			continue
		var g := Vector2(road_sd(CV, q + Vector2(0.4, 0)) - road_sd(CV, q - Vector2(0.4, 0)), road_sd(CV, q + Vector2(0, 0.4)) - road_sd(CV, q - Vector2(0, 0.4)))
		var nrm := g.normalized() if g.length() > 1e-5 else Vector2.RIGHT
		if blocked_v(CV, q + nrm * 0.4) != "":
			continue                        # P6 frontage が路縁まで来ている所は触らない
		if GC._n(q * 0.7, 1.0, 3.0) < 0.55 or used.any_within(q, rng.randf_range(2.1, 4.1)):
			continue
		tuft_group_v(CV, rng, items, q + nrm * rng.randf_range(0.0, 0.35), rng.randf_range(0.35, 0.7), rng.randi_range(4, 9), "v_road", 0.3, 0.0, true)
		used.add(q)


## 5 林緣（Pilot _forest r10 forest-floor-first と同じ語彙）：地面は overlay の林床が主、植物は群落で
static func _v_forest(CV: Dictionary, rng: RandomNumberGenerator, items: Array, nodes: Array) -> void:
	var S: RLib.TriSampler = CV["S"]
	var NH: PtHash = CV["NH"]
	for c: Vector2 in grid_pts(4.2, rng):
		if blocked_v(CV, c) != "":
			continue
		var mm := memb(CV, c)
		if mm.z > 0.5:
			continue
		var fd := GC.forest_d(CV, c) + 2.0 * (GC._n(c * 0.25, 1.0, 7.0) - 0.5)
		var pn := GC._n(c * 0.3, 1.0, 5.5)
		if fd > 9.0 or fd < -7.0:
			continue
		if fd > 3.0:
			if pn > 0.45 and rng.randf() < 0.22 + 0.4 * smoothstep(9.0, 4.0, fd):
				tuft_group_v(CV, rng, items, c, rng.randf_range(1.0, 1.8), rng.randi_range(10, 20), "v_forest", 0.25, 0.4, false, "tuft", false, true, 1.0, 0.3)
		elif fd > -1.5:
			var sdc := GC.seam_d(CV, c)
			if sdc > -3.0 and sdc < 5.0 and rng.randf() < 0.9:
				var main := "fern_a" if pn > 0.5 else "sasa_a"
				for j in rng.randi_range(4, 8):
					var q := c + Vector2(clampf(rng.randfn(0.0, 0.8), -1.8, 1.8), clampf(rng.randfn(0.0, 0.8), -1.8, 1.8))
					var id := main if rng.randf() < 0.8 else ("sasa_a" if main == "fern_a" else "fern_a")
					if GC.forest_d(CV, q) < 1.0 and rng.randf() < 0.2:
						id = "shrub_a"
					var sc := rng.randf_range(0.6, 0.9) if id == "shrub_a" else rng.randf_range(0.5, 0.85)
					if fits_v(CV, q, 0.5 * sc) and not GC.near_under(CV, q, 0.8) and not NH.any_within(q, 0.55) and GC.trunk_d(CV, q) > 1.6:
						nodes.append(GC.tnode(S, id, q, sc, rng, "v_forest", "edge"))
						NH.add(q)
			if rng.randf() < 0.35:
				tuft_group_v(CV, rng, items, c + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5)), rng.randf_range(0.6, 1.0), rng.randi_range(4, 8), "v_forest", 0.3, 0.3, false, "tuft", false, true, 1.0, 0.3)
		else:
			if rng.randf() < 0.25:
				items.append(GC.gi(S, GC.K_LITTER, c, 1.0, rng.randf_range(1.0, 1.6), rng.randf() * TAU, Color(1, 1, 1), "v_forest", "litter"))
	# 林縁の樹：全村では張り出し根を置かない（使用者裁定 2026-10-03「每棵樹都有巨大盤根，反而假」；Pilot r10f の小尺度根は Pilot 區だけ）。
	#   落葉の塊は根元が林床（地形の林床層）の上にある林縁木の約 1/3 だけ（草地に立つ孤立木の根元に色紙を撒かない）
	for t: Dictionary in CV["trees"]:
		var p: Vector2 = t["p"]
		if not BB.has_point(p) or in_pilot(p) or GC.seam_d(CV, p) < -0.5 or rng.randf() > 0.35:
			continue
		var edge := false
		for a in 8:
			if GC.forest_d(CV, p + Vector2(cos(a * TAU / 8.0), sin(a * TAU / 8.0)) * (float(t["cr"]) + 2.5)) > 0.0:
				edge = true
				break
		if not edge:
			continue
		var r0 := 0.6 + 0.15 * float(t["sc"])
		for k in rng.randi_range(1, 3):
			var a := -PI * 0.5 + rng.randf_range(-1.6, 1.6)
			var q := p + Vector2(cos(a), sin(a)) * rng.randf_range(r0, r0 + 1.0)
			if blocked_v(CV, q) != "":
				continue
			items.append(GC.gi(S, GC.K_LITTER, q, rng.randf_range(0.9, 1.2), rng.randf_range(1.1, 1.6), a, Color(1, 1, 1), "v_forest", "root"))


static func fits_v(CV: Dictionary, p: Vector2, r: float) -> bool:
	if blocked_v(CV, p) != "":
		return false
	for d in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		if blocked_v(CV, p + d) != "":
			return false
	return true


## 6 溪岸（Pilot _stream r10 substrate-first と同じ語彙）：植物は點綴。蘆＝自然岸だけ・小群落（孤立單叢なし）、間隔は岸長に応じて不規則
static func _v_stream(CV: Dictionary, rng: RandomNumberGenerator, items: Array, nodes: Array) -> void:
	var S: RLib.TriSampler = CV["S"]
	var c_reed: Array = []
	var c_bank: Array = []
	var gx := BB.position.x + 0.25
	while gx < BB.end.x:
		var gz := BB.position.y + 0.25
		while gz < BB.end.y:
			var q := Vector2(gx, gz)
			gz += 0.5
			var e := GC.wdist(CV, q) - GC.RB_CORE
			if e < 0.4 or e > 2.6:
				continue
			if blocked_v(CV, q) != "":
				continue
			if e < 1.0:
				c_reed.append(q)
			elif e > 1.4:
				c_bank.append(q)
		gx += 0.5
	GC._shuffle(c_reed, rng)
	GC._shuffle(c_bank, rng)
	CV["n_reed_cand"] = c_reed.size()
	# ① 蘆：自然岸（bank_nat ≥ 0.6）の候補だけ、群落どうし ≥ 14 m、さらに確率で間引く（等間隔にしない）
	var cols: Array = []
	var colh := PtHash.new()
	for c: Vector2 in c_reed:
		if colh.any_within(c, 14.0) or bank_nat(CV, c) < 0.6:
			continue
		if rng.randf() > 0.5 * smoothstep(0.35, 0.6, GC._n(c * 0.08, 1.0, 81.0)) + 0.08:
			colh.add(c)                    # 見送った所も間隔の基準にする（密集させない）
			continue
		var g := GC.wgrad(CV, c)
		var tg := Vector2(-g.y, g.x)
		var hl := rng.randf_range(1.2, 2.4)
		var placed: Array = []
		var subs: Array = []
		var along := -hl * 0.5
		for j in rng.randi_range(2, 3):
			subs.append(c + tg * along + g * rng.randf_range(-0.2, 0.6))
			along += rng.randf_range(0.9, 1.3)
		var members: Array = []
		for sc2: Vector2 in subs:
			for k2 in rng.randi_range(2, 3):
				members.append([sc2 + Vector2(clampf(rng.randfn(0.0, 0.25), -0.45, 0.45), clampf(rng.randfn(0.0, 0.25), -0.45, 0.45)), rng.randf_range(0.6, 0.9)])
		for k2 in rng.randi_range(0, 1):
			members.append([c + tg * rng.randf_range(-hl - 0.6, hl + 0.6) + g * rng.randf_range(0.0, 0.7), rng.randf_range(0.5, 0.7)])
		for mb: Array in members:
			var q: Vector2 = mb[0]
			var e := GC.wdist(CV, q) - GC.RB_CORE
			if blocked_v(CV, q) != "" or e < 0.1 or e > 1.7 or bank_nat(CV, q) < 0.5:
				continue
			placed.append(GC.wnode(S, "wk_reed" if rng.randf() < 0.6 else "wk_reed_s", q, float(mb[1]), rng, "v_stream", "reed"))
		placed = GC._largest_component(placed, 1.6)
		colh.add(c)
		if placed.size() >= 5:
			nodes.append_array(placed)
			cols.append(c)
	# ② 菅・花菖蒲：泥帯（自然岸寄り）に 3–5 株の小群、互いに ≥ 6 m、蘆の群落から ≥ 3 m
	var gsh := PtHash.new()
	for c: Vector2 in c_bank:
		if gsh.any_within(c, 6.0) or colh.any_within(c, 3.0) or bank_nat(CV, c) < 0.4:
			continue
		if rng.randf() > 0.55:
			gsh.add(c)
			continue
		var n_ok := 0
		for j in rng.randi_range(3, 5):
			var q := c + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
			if blocked_v(CV, q) != "" or GC.wdist(CV, q) - GC.RB_CORE < 1.0:
				continue
			nodes.append(GC.wnode(S, "wk_iris" if rng.randf() < 0.2 else "wk_sedge", q, rng.randf_range(0.65, 0.95), rng, "v_stream", "bank"))
			n_ok += 1
		gsh.add(c)
	# ③ 卵石（3D）：汀帯 e 0.15–1.3 に小さな寄り（自然岸）、⑤ 草：外縁 e 3.2–5.8 に小さな群れ（疎）
	for c: Vector2 in grid_pts(1.3, rng):
		var e := GC.wdist(CV, c) - GC.RB_CORE
		if e < 0.15 or e > 1.3 or blocked_v(CV, c) != "":
			continue
		if rng.randf() < 0.45 * smoothstep(0.3, 0.6, GC._n(c * 0.7, 1.0, 59.0)) * bank_nat(CV, c):
			for j in rng.randi_range(1, 3):
				var q := c + Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))
				if blocked_v(CV, q) == "":
					items.append(GC.gi(S, GC.K_PEBBLE, q, rng.randf_range(0.8, 1.3), 1.0, rng.randf() * TAU, Color(1, 1, 1), "v_stream", "stone"))
	for c: Vector2 in grid_pts(3.0, rng):
		var e := GC.wdist(CV, c) - GC.RB_CORE
		if e < 3.2 or e > 5.8 or blocked_v(CV, c) != "":
			continue
		if GC._n(c * 0.5, 1.0, 11.0) > 0.55 and rng.randf() < 0.35:
			tuft_group_v(CV, rng, items, c, rng.randf_range(0.7, 1.1), rng.randi_range(8, 14), "v_stream", 0.15, 0.25, false, "tuft", false, true, 1.0, 0.0)


# ─────────────────────────── 地面 overlay ───────────────────────────

## 地面重み（Pilot ground_w の各類別と同じ式）：[Color(碎石,苔,踏土,落葉), Vector2(濕潤, 淡出), Vector2(泥, 卵石)] または null
static func ground_w_v(P: Dictionary, p: Vector2, cls: String) -> Variant:
	var CV: Dictionary = P["CV"]
	var mm := memb(CV, p)
	var mk: float = mm.x if cls == "gen" else (mm.y if cls == "forest" else mm.z)
	if mk < 0.002:
		return null
	var fade := (1.0 - pilot_k(p)) * smoothstep(0.0, 4.0, minf(minf(p.x - BB.position.x, BB.end.x - p.x), minf(p.y - BB.position.y, BB.end.y - p.y)))
	if fade < 0.002:
		return null
	var nz := GC._n(p, 1.0)
	var pb := GC._n(p * 2.7 + Vector2(19.0, 41.0), 1.1)
	var gv := 0.0
	var mo := 0.0
	var so := 0.0
	var li := 0.0
	var wet := 0.0
	var md := 0.0
	var pe := 0.0
	var k_in := 1.0
	if cls != "stream":
		var wd := wall_d(CV, p)
		if wd < 0.8:
			var kw := (1.0 - smoothstep(0.05, 0.8, wd)) * smoothstep(0.38, 0.55, GC._n(p * 0.8, 1.0, 2.0)) * smoothstep(0.2, 0.6, GC.grass_w(CV, p))
			so = maxf(so, 0.55 * kw)
			gv = maxf(gv, 0.45 * kw * smoothstep(0.4, 0.6, pb))
			mo = maxf(mo, 0.4 * kw * smoothstep(0.55, 0.7, GC._n(p * 1.7, 1.0, 4.0)))
			wet = maxf(wet, 0.12 * kw)
	if cls == "gen":
		var gw := GC.grass_w(CV, p)
		if gw >= 0.0 and absf(gw - 0.5) < 0.42:
			var e := gw - 0.5 + 0.6 * (GC._n(p * 0.45, 1.0, 12.0) - 0.5) + 0.3 * (GC._n(p * 1.3, 1.0, 19.0) - 0.5)
			if gw >= 0.5 and e < 0.0:
				so = maxf(so, 0.75 * smoothstep(0.0, -0.25, e))
				gv = maxf(gv, 0.2 * smoothstep(0.0, -0.25, e) * smoothstep(0.5, 0.7, pb))
			elif gw < 0.5 and e > 0.0:
				var kt := (1.0 - smoothstep(1.2, 2.6, GC.gdist(CV, p))) * smoothstep(1.0, 2.2, walk_d(CV, p))
				mo = maxf(mo, 0.5 * smoothstep(0.0, 0.25, e) * kt)
	var dk := GC.drift_k(CV, p)
	so = maxf(so, 0.16 * dk * smoothstep(0.3, 0.6, GC.grass_w(CV, p)))
	match cls:
		"gen":
			# 濃い草の斑は地形が草として描かれている所だけ（全村には草と土が混ざった茶色いセルが多く、0.35 からだと土場が緑に洗われた）
			var on_g := smoothstep(0.62, 0.85, GC.grass_w(CV, p))
			mo = maxf(mo, 0.25 * smoothstep(0.62, 0.8, GC._n(p * 0.12, 1.0, 21.0)) * on_g)
			li = maxf(li, 0.26 * smoothstep(0.64, 0.82, GC._n(p * 0.15 + Vector2(7.0, 3.0), 1.0, 33.0)) * on_g)
			if GC.grass_w(CV, p) < 0.5:
				var tg := smoothstep(0.6, 0.9, dirt_inv_g(CV, p) * (0.5 + 0.9 * GC._n(p * 0.6, 1.0, 41.0)))
				mo = maxf(mo, 0.4 * tg)
			so = maxf(so, 0.3 * smoothstep(0.7, 0.86, GC._n(p * 0.2, 1.0, 44.0)))
			so = maxf(so, 0.8 * smoothstep(0.8, 0.9, GC._n(p * 1.3, 1.0, 6.0)))
			# 路肩（Pilot street）：路縁の線を揺らし、路面側に草が食い込み、草地側に踏み跡の指
			var red := road_sd(CV, p)
			if red > -1.2 and red < 2.4:
				var e2 := red - 1.2 * (GC._n(p * 0.5, 1.0, 1.0) - 0.5)
				var fing := 1.7 * smoothstep(0.58, 0.82, GC._n(p * 0.9, 1.0, 5.0))
				if red < 0.0 and e2 > 0.0:
					# 路面側の草の舌は路縁の外が草の所だけ（主街の frontage 側の路面には描かない）
					mo = maxf(mo, 0.9 * smoothstep(0.0, 0.3, e2) * (1.0 - smoothstep(0.8, 2.0, GC.gdist(CV, p))))
				elif red >= 0.0:
					var kr := maxf(1.0 - smoothstep(-0.3, 0.0, e2), 1.0 - smoothstep(fing * 0.55, fing + 0.01, red))
					so = maxf(so, 0.85 * kr)
					gv = maxf(gv, 0.35 * kr * smoothstep(0.5, 0.7, pb))
		"forest":
			var sd := GC.seam_d(CV, p)
			var n1 := GC._n(p * 0.22, 1.0, 7.0)
			var n2 := GC._n(p * 0.8, 1.0, 13.0)
			var nF := GC._n(p * 0.45, 1.0, 71.0)
			var reach := maxf(1.0 + 3.6 * smoothstep(0.45, 0.8, nF) + 0.9 * smoothstep(0.55, 0.8, n1) + 0.5 * (n2 - 0.5), 0.6)
			if P.get("_neg_no_floor_v", false):
				reach = 0.0
			var spill := 1.0 if sd >= 0.0 else 1.0 - smoothstep(reach * 0.45, reach + 0.01, -sd)
			var inner := smoothstep(0.5, 5.0, sd)
			var tip := 1.0 if sd >= 0.0 else 1.0 - 0.45 * smoothstep(0.0, reach, -sd)
			li = maxf(li, 0.8 * spill * tip * (1.0 - 0.4 * inner) * (0.7 + 0.3 * smoothstep(0.3, 0.6, pb)))
			var band := smoothstep(-0.5, 0.5, sd)
			var edge_b := band * (1.0 - smoothstep(3.0, 6.0, sd))
			md = maxf(md, band * (0.35 * edge_b + 0.5 * smoothstep(0.45, 0.7, GC._n(p * 0.3, 1.0, 31.0))))
			mo = maxf(mo, band * 0.45 * smoothstep(0.58, 0.78, GC._n(p * 0.25, 1.0, 3.0)))
			li = maxf(li, band * 0.55 * smoothstep(0.35, 0.65, GC._n(p * 0.2 + Vector2(13.0, 5.0), 1.0, 77.0)))
			md = maxf(md, 0.55 * edge_b)
			var tn := GC.trunk_near(CV, p)
			var td: float = tn[0]
			if td < 3.2:
				var shade := 0.5 + 0.5 * (tn[1] as Vector2).dot(Vector2(0.0, -1.0))
				var R := (2.2 + 1.0 * GC._n(p * 1.1, 1.0, 37.0)) * (0.9 + 0.2 * n1)
				var cr := 1.3 + 0.5 * GC._n(p * 1.7, 1.0, 39.0)
				var root := smoothstep(0.12, 0.25, td) * (1.0 - smoothstep(0.45, 0.7, td))
				var collar := smoothstep(0.35, 0.55, td) * (1.0 - smoothstep(cr * 0.8, cr, td))
				var ring := smoothstep(cr * 0.7, cr, td) * (1.0 - smoothstep(R * 0.7, R, td))
				md = maxf(md, 0.8 * root)
				mo = maxf(mo, collar * (0.55 + 0.35 * shade))
				li = maxf(li, 0.7 * ring)
				wet = maxf(wet, 0.25 * root + 0.1 * collar)
			if P.get("_neg_no_floor_v", false):
				li = 0.0
				md = 0.0
				mo = 0.0
			wet = maxf(wet, 0.25 * md)
		"stream":
			var e := GC.wdist(CV, p) - GC.RB_CORE
			if e < 7.5:
				var nat := bank_nat(CV, p)
				var nA := GC._n(p * 0.5, 1.0, 51.0)
				var nB := GC._n(p * 1.1, 1.0, 53.0)
				var ew := e - 2.4 * (nA - 0.5) - 0.7 * (nB - 0.5) - 1.0 * (GC._n(p * 1.6, 1.0, 67.0) - 0.5)
				# 自然岸ほど帯が広い（護岸・高い岸は苔と濕った土の細い帯だけ）
				var pw := (0.7 + 1.0 * smoothstep(0.3, 0.7, GC._n(p * 0.6, 1.0, 55.0))) * lerpf(0.45, 1.0, nat)
				var mw := (2.2 + 1.8 * smoothstep(0.35, 0.75, GC._n(p * 0.42, 1.0, 61.0)) + 1.6 * smoothstep(0.68, 0.85, GC._n(p * 0.35, 1.0, 57.0))) * lerpf(0.4, 1.0, nat)
				var el := e - 0.6 * (nB - 0.5)
				# 岸沿いの斷續（波長 8–15 m）：連続した帯を岸と平行に見ると小道に見える
				var brk := smoothstep(0.36, 0.62, GC._n(p * 0.6, 1.0, 83.0)) * smoothstep(0.28, 0.5, GC._n(p * 0.21, 1.0, 87.0))
				pe = 0.7 * (1.0 - smoothstep(pw * 0.5, pw, el)) * lerpf(0.3, 1.0, nat) * lerpf(0.15, 1.0, brk)
				gv = maxf(gv, 0.45 * smoothstep(pw * 0.3, pw * 0.8, ew) * (1.0 - smoothstep(pw, pw + 0.9, ew)))
				md = 0.75 * smoothstep(pw * 0.4, pw * 0.9, ew) * (1.0 - smoothstep(mw * 0.7, mw, ew)) * (0.65 + 0.35 * smoothstep(0.3, 0.7, pb)) * lerpf(0.5, 1.0, nat) * lerpf(0.55, 1.0, brk)
				mo = maxf(mo, 0.55 * smoothstep(mw * 0.55, mw * 0.95, ew) * (1.0 - smoothstep(mw + 1.0, mw + 2.6, ew)) * smoothstep(0.3, 0.62, GC._n(p * 0.7, 1.0, 63.0)))
				so = maxf(so, 0.22 * smoothstep(mw * 0.6, mw, ew) * (1.0 - smoothstep(mw + 1.0, mw + 2.4, ew)))
				wet = 0.55 * (1.0 - smoothstep(0.3, mw + 0.5, ew))
				var fd: float = 1.5 if P.get("_neg_core_deep_v", false) else GC.RB_FADE
				k_in = smoothstep(-fd, 0.15, e)
				md = maxf(md, 0.45 * smoothstep(-fd, -0.1, e) * (1.0 - smoothstep(0.2, 0.7, e)) * smoothstep(0.35, 0.6, pb))
				gv = maxf(gv, 0.35 * (1.0 - smoothstep(-0.1, 0.5, e)) * smoothstep(0.45, 0.7, nB))
				wet = maxf(wet, 0.6 * (1.0 - smoothstep(0.0, 0.8, e)))
	var kk := k_in * mk
	gv *= kk
	mo *= kk
	so *= kk
	li *= kk
	md *= kk
	pe *= kk
	wet *= mk
	var tot := gv + mo + so + li + md + pe
	if tot > 1.0:
		gv /= tot
		mo /= tot
		so /= tot
		li /= tot
		md /= tot
		pe /= tot
		tot = 1.0
	if tot < 0.02:
		return null
	return [Color(gv, mo, so, li), Vector2(wet, fade), Vector2(md, pe)]


## 地面重み 7 値（gate 用；全類別の和、overlay なし＝全 0）
static func gwt_v(P: Dictionary, p: Vector2) -> PackedFloat32Array:
	var out := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])
	for cls: String in CLASSES:
		if not vertex_ok(P, p, cls):
			continue
		var w: Variant = ground_w_v(P, p, cls)
		if w == null:
			continue
		var c: Color = w[0]
		var u: Vector2 = w[2]
		var f: float = (w[1] as Vector2).y
		out[0] += c.r * f
		out[1] += c.g * f
		out[2] += c.b * f
		out[3] += c.a * f
		out[4] += u.x * f
		out[5] += u.y * f
		out[6] = maxf(out[6], (w[1] as Vector2).x)
	return out


## この點に類別 cls の地面頂點を置いてよいか（Pilot ground_mesh と同じ規則＋frontage の上は描かない）
static func vertex_ok(P: Dictionary, p: Vector2, cls: String) -> bool:
	var CV: Dictionary = P["CV"]
	var br := blocked_v(CV, p, true, 1.25)
	if br == "pilot":
		if pilot_k(p) >= 0.999:
			return false
		if GC.zone_of(p) != "":
			return true                                  # Pilot r10f の緣（従来どおり）
		br = blocked_v(CV, p, true, 1.25, true)          # Macro 區の緣の交叉淡化帯：通常の禁區規則をそのまま適用
	if cls == "stream" and br == "riverbank":
		var fd: float = 1.5 if P.get("_neg_core_deep_v", false) else GC.RB_FADE
		if GC.wdist(CV, p) < GC.RB_CORE - fd:
			return false
		return P.get("_neg_core_deep_v", false) or not p7_covered(CV, p)
	if br == "p7piece" and not (cls == "stream" and P.get("_neg_core_deep_v", false)):
		return false
	if br == "road" and cls != "gen":
		return false
	if br != "" and br != "road" and br != "obstacle" and br != "trunk":
		return false
	if cls == "stream" and not P.get("_neg_core_deep_v", false) and p7_covered(CV, p):
		return false
	return true


## 24 m 區塊ごとの地面網格（類別ごと；格子は全村共通の位相＝區塊の境で頂點が一致、縁は BFS で 1.2 m 淡出）
static func ground_chunk(P: Dictionary, cls: String, ck: Vector2i) -> ArrayMesh:
	var CV: Dictionary = P["CV"]
	var S: RLib.TriSampler = CV["S"]
	var R: RLib.TriSampler = CV["R"]
	var gs: float = STEP[cls]
	var cr := Rect2(ck.x * GC.CHUNK, ck.y * GC.CHUNK, GC.CHUNK, GC.CHUNK)
	var MG := 4
	var i0 := floori((cr.position.x - BB.position.x) / gs) - MG
	var i1 := ceili((cr.end.x - BB.position.x) / gs) + MG
	var j0 := floori((cr.position.y - BB.position.y) / gs) - MG
	var j1 := ceili((cr.end.y - BB.position.y) / gs) + MG
	var WG := {}
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := BB.position + Vector2(i * gs, j * gs)
			if not BB.has_point(p) or not vertex_ok(P, p, cls):
				continue
			var w: Variant = ground_w_v(P, p, cls)
			if w == null:
				continue
			WG[Vector2i(i, j)] = w
	if WG.is_empty():
		return null
	# 3×3 平滑
	var nw := {}
	var NB8 := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
	for g: Vector2i in WG:
		var c4: Color = (WG[g][0] as Color) * 4.0
		var u2: Vector2 = (WG[g][1] as Vector2) * 4.0
		var u1: Vector2 = (WG[g][2] as Vector2) * 4.0
		var ws := 4.0
		for d: Vector2i in NB8:
			if WG.has(g + d):
				var wt := 1.0 if (d.x != 0 and d.y != 0) else 2.0
				c4 += (WG[g + d][0] as Color) * wt
				u2 += (WG[g + d][1] as Vector2) * wt
				u1 += (WG[g + d][2] as Vector2) * wt
				ws += wt
		nw[g] = [c4 / ws, u2 / ws, u1 / ws]
	# 縁（封存區・建物・水・路面で切れる所）の淡出：欠けたセルからの格子距離（區塊外の margin は欠けとみなさない＝區塊境で切れない）
	var dist := {}
	var front: Array = []
	for g: Vector2i in nw:
		var edge := false
		for d: Vector2i in NB8:
			var q: Vector2i = g + d
			if q.x < i0 or q.x > i1 or q.y < j0 or q.y > j1:
				continue
			if not nw.has(q):
				edge = true
				break
		if edge:
			dist[g] = 0
			front.append(g)
	var nfade := maxi(2, int(round(1.2 / gs)))
	while not front.is_empty():
		var nxt: Array = []
		for g: Vector2i in front:
			var dg: int = dist[g]
			if dg >= nfade:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = g + d
				if nw.has(q) and not dist.has(q):
					dist[q] = dg + 1
					nxt.append(q)
		front = nxt
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var Cc := PackedColorArray()
	var U2 := PackedVector2Array()
	var U1 := PackedVector2Array()
	var idx := PackedInt32Array()
	var vid := {}
	var ci0 := floori((cr.position.x - BB.position.x) / gs)
	var ci1 := ceili((cr.end.x - BB.position.x) / gs)
	var cj0 := floori((cr.position.y - BB.position.y) / gs)
	var cj1 := ceili((cr.end.y - BB.position.y) / gs)
	var yo: float = {"gen": 0.011, "forest": 0.012, "stream": 0.013}[cls]
	for j in range(cj0, cj1 + 1):
		for i in range(ci0, ci1 + 1):
			var g := Vector2i(i, j)
			if not nw.has(g):
				continue
			var p := BB.position + Vector2(i * gs, j * gs)
			var h := S.h(p.x, p.y)
			var rh := R.h(p.x, p.y)
			if not is_nan(rh):
				h = maxf(h, rh)
			var d := 0.4
			var nrm := Vector3(S.h(p.x - d, p.y) - S.h(p.x + d, p.y), 2.0 * d, S.h(p.x, p.y - d) - S.h(p.x, p.y + d))
			var u2: Vector2 = nw[g][1]
			if dist.has(g):
				u2.y *= smoothstep(0.0, float(nfade), float(dist[g]))
			vid[g] = V.size()
			V.append(Vector3(p.x, h + yo, p.y))
			N.append(nrm.normalized() if nrm.is_finite() else Vector3.UP)
			Cc.append(nw[g][0])
			U2.append(u2)
			U1.append(nw[g][2])
	for j in range(cj0, cj1):
		for i in range(ci0, ci1):
			# 區塊の所有：セルの左上が區塊内
			var px := BB.position.x + i * gs
			var pz := BB.position.y + j * gs
			if px < cr.position.x - 1e-4 or px >= cr.end.x - 1e-4 or pz < cr.position.y - 1e-4 or pz >= cr.end.y - 1e-4:
				continue
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
	if idx.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_COLOR] = Cc
	arr[Mesh.ARRAY_TEX_UV2] = U2
	arr[Mesh.ARRAY_TEX_UV] = U1
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.resource_name = "gcv_%s_%d_%d" % [cls, ck.x, ck.y]
	return am


## 類別ごとに地面網格を作る區塊（2 m の粗い走査で membership と可否を見る）
static func chunk_keys(P: Dictionary, cls: String) -> Array:
	var CV: Dictionary = P["CV"]
	var ks := {}
	var x := BB.position.x + 1.0
	while x < BB.end.x:
		var z := BB.position.y + 1.0
		while z < BB.end.y:
			var p := Vector2(x, z)
			z += 2.0
			var m := memb(CV, p)
			var mk: float = m.x if cls == "gen" else (m.y if cls == "forest" else m.z)
			if mk < 0.002:
				continue
			var br := blocked_v(CV, p, true, 1.25)
			if br == "" or br == "road" or br == "obstacle" or br == "trunk" or br == "riverbank" or (br == "pilot" and pilot_k(p) < 0.999):
				for dx in [-2.0, 0.0, 2.0]:
					for dz in [-2.0, 0.0, 2.0]:
						ks[Vector2i(floori((p.x + dx) / GC.CHUNK), floori((p.y + dz) / GC.CHUNK))] = true
		x += 2.0
	var out := ks.keys()
	out.sort()
	return out


# ─────────────────────────── 烘焙 ───────────────────────────

const ART_REVISION := "P9 R5 Macro Expansion v3（全村 Macro Ground Integration：一般類は全村 Macro、林緣・溪岸は r5、Pilot r10f・Macro Pilot m9 凍結、可見最上面ルール；ART_REVIEW 前）"
## Pilot r10f（2026-10-03 ART_APPROVED）の規劃・地面網格 digest：全村擴張後もこれと一致しなければ FAIL
const PILOT_R10F_PLAN_SHA := "c3ffaaed9db3e38370185bf467a805b5749a1b43edc5856eee49fb7349d6de83"
const PILOT_R10F_GROUND_SHA := "3ec32ee02db5d03294557cc3454f429e5ee19944fd2439187cd4e5d5ccce7e2f"


## Pilot 部分（items／nodes の先頭）の正規化 sha256 と、Pilot 4 區の地面網格 sha256
static func pilot_digest(P: Dictionary, with_ground := true) -> Array:
	var s := ""
	var items: Array = P["items"]
	var nodes: Array = P["nodes"]
	for i in int(P.get("n_pilot_items", items.size())):
		var it: Dictionary = items[i]
		var p: Vector2 = it["p"]
		var c: Color = it["col"]
		s += "%d|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%s|%s\n" % [int(it["k"]), p.x, p.y, float(it["y"]), float(it["h"]), float(it["w"]), float(it["yaw"]), c.r, c.g, c.b, it["zone"], it["tag"]]
	for i in int(P.get("n_pilot_nodes", nodes.size())):
		var n: Dictionary = nodes[i]
		var p: Vector2 = n["p"]
		s += "N|%s|%.4f|%.4f|%.4f|%.4f|%.4f|%s|%s\n" % [n["id"], p.x, p.y, float(n["y"]), float(n["yaw"]), (n["sc"] as Vector3).x, n["zone"], n["tag"]]
	var g := ""
	if with_ground:
		for z: String in GC.ZONE_ORDER:
			var m := GC.ground_mesh(P, z)
			var arr := m.surface_get_arrays(0)
			var hs := HashingContext.new()
			hs.start(HashingContext.HASH_SHA256)
			for a in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_INDEX]:
				hs.update(arr[a].to_byte_array())
			g += hs.finish().hex_encode()
		g = g.sha256_text()
	return [s.sha256_text(), g]

## Pilot bake（items／nodes は Pilot＋全村）に全村の地面網格を足す
static func bake_all(P: Dictionary) -> Node3D:
	var root := GC.bake(P)
	var gnode := root.get_node("Ground")
	var vg := Node3D.new()
	vg.name = "Village"
	gnode.add_child(vg)
	var n_ch := 0
	var n_v := 0
	for cls: String in CLASSES:
		var mat := GC.gc_material({"gen": "lawn", "forest": "forest", "stream": "stream"}[cls])
		mat.resource_name = "GC_Ground_v_" + cls
		var cnode := Node3D.new()
		cnode.name = cls
		vg.add_child(cnode)
		for ck: Vector2i in chunk_keys(P, cls):
			var m := ground_chunk(P, cls, ck)
			if m == null:
				continue
			m.surface_set_material(0, mat)
			var g := MeshInstance3D.new()
			g.name = "G_%s_%d_%d" % [cls, ck.x, ck.y]
			g.mesh = m
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			g.visibility_range_end = 120.0
			g.visibility_range_end_margin = 10.0
			g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			cnode.add_child(g)
			n_ch += 1
			n_v += m.surface_get_array_len(0)
	root.set_meta("village_ground_chunks", n_ch)
	root.set_meta("village_ground_verts", n_v)
	root.set_meta("art_revision", ART_REVISION)
	return root
