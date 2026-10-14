extends RefCounted
## 人間之里 V2 P13 W9 Visible Village Enrichment — 環境豐富化（第一輪：住宅側巷・主街南段・農家）の生成器（source of truth）。
##   overlay `EnrichW9P13`（root 直下・LodCalBatch1P13 の次）→ gen/enrich_w9_p13.scn。ビルド／掛載：tools/p13/w9/build_w9.gd。
## 方針（使用者 2026-10-14）：建築の footprint・戸口・碰撞は一切不変。既存の町家には「足す」だけ（簾・軒の吊るし物・植木棚・板塀・下屋…）。
##   - 壁付け（wall）：建物局部座標（x＝幅、z＝前面、floor＝基壇上端 +0.32）で置く。戸口の前・戸口の凹み・店先の通路は塞がない。
##   - 宅間（gap）：隣り合う 2 棟の壁の間を、板塀＋木戸／下屋／小庭／祠で「各戸の使い方」にする。
##   - 地面（ground／veg）：地形＋店先帯＋地被 decal の最上面に接地。重なり検査は独自 why（mode 別）。
## 材質は町で使用中の承認済みだけ（w9_kit：V2_Wood／V2_Kawara／ST_Street）。重用優先：既存 Kit の物は新造しない。
const HU := preload("res://tools/village_v2_human_use_lib.gd")
const HX := preload("res://tools/village_v2_human_use_exp_lib.gd")
const SL := preload("res://tools/village_v2_street_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")

const NODE_NAME := "EnrichW9P13"
const OUTPUT := "res://maps/village_v2/gen/enrich_w9_p13.scn"
const SCENE := "res://maps/village_v2/village_v2.tscn"
const AFTER := "LodCalBatch1P13"
const LOD_SWITCH := 34.0
const ART_REVISION := "P13 W9 Visible Village Enrichment 第一輪 r1（ART_REVIEW）"
const W9_DIR := "res://assets/village_v2/w9_kit/"
const KITS := {"hu_": "humanuse_kit", "hx_": "humanuse_exp_kit", "st_": "street_kit", "mk_": "market_kit", "sk_": "school_kit", "tk_": "tower_kit",
	"kr_": "kiri_kit", "sz_": "suzu_kit", "wk_": "waterside_kit", "gk_": "garden_kit", "ms_": "mise_kit", "gd_": "geidon_kit", "w9_": "w9_kit"}
## veg_kit の名前（LOD0..）：shrub／fern／sasa／幼樹
const VEG := ["shrub_a", "fern_a", "sasa_a", "young_broad_a", "young_broad_b", "young_sugi", "niwamatsu_a"]
const VEG_RANGES := [[0.0, 26.0], [26.0, 60.0], [60.0, 130.0], [130.0, 200.0]]
const WALL_T := 0.06                 # 外壁の外面（局部 z = d/2 + 0.06）
const DOOR_MARGIN := 0.30            # 戸口の polygon の外側余白
const BLD_PAD := 0.25
const RELIEF_MAX := 0.16
const ROAD_PAD := 0.45               # 地面物（壁付け以外）の道路からの余白
const NPC_PAD := 0.9
const PATROL_PAD := 0.7
const FLOOR_Y := 0.32                # 町家 Kit の基壇上端（node 局部 y）
## 衝突を付けない（吊り物・植物・薄い物・地面に貼る物）
const NO_COLLIDE := ["w9_tsurushi_kaki", "w9_tsurushi_togarashi", "w9_sudare", "w9_hana_higanbana", "w9_hana_kiiro", "w9_hana_shiro", "w9_hana_pink",
	"w9_sugidama", "w9_asagao", "shrub_a", "fern_a", "sasa_a", "young_broad_a", "young_broad_b", "young_sugi", "niwamatsu_a"]
const ZONE_NAME := {"R": "住宅側巷（WestBankLane：宅間・門前・小庭）", "M": "主街南段（MainStreet：店の用途と暮らしの目印）", "F": "村外の農家（FarmsteadP13：生活過渡と田の縁）"}

static var _dims := {}


# ─────────────────────────── 資産 ───────────────────────────

static func kit_of(id: String) -> String:
	for pre: String in KITS:
		if id.begins_with(pre):
			return KITS[pre]
	return ""


static func is_veg(id: String) -> bool:
	return id in VEG


static func veg_path(id: String, lod: int) -> String:
	return "res://assets/village_v2/veg_kit/mesh/%s_LOD%d.res" % [id, lod]


static func veg_lods(id: String) -> int:
	var n := 0
	while n < 4 and ResourceLoader.exists(veg_path(id, n)):
		n += 1
	return n


## [[mesh path, begin, end, cast shadow]]
static func bundle(id: String) -> Array:
	if is_veg(id):
		var out: Array = []
		var n := veg_lods(id)
		for k in n:
			var r: Array = VEG_RANGES[k]
			out.append([veg_path(id, k), r[0], (r[1] if k < n - 1 else 200.0), k < 2])
		return out
	var dir := "res://assets/village_v2/%s/mesh/" % kit_of(id)
	return [[dir + id + ".res", 0.0, LOD_SWITCH, true], [dir + id + "_l1.res", LOD_SWITCH, 160.0, false]]


## [minx, miny, minz, maxx, maxy, maxz]（Godot 座標、原点＝足元）
static func dims(id: String) -> Array:
	if _dims.is_empty():
		for pre: String in KITS:
			var kit: String = KITS[pre]
			var f := "res://assets/village_v2/%s/src/modules_blender.json" % kit
			if not FileAccess.file_exists(f):
				continue
			var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(f))
			var m: Variant = j["modules"]
			if m is Dictionary:
				for n: String in m:
					if not n.ends_with("_l1") and (m[n] as Dictionary).has("dims"):
						_dims[n] = m[n]["dims"]
		_dims["_probe"] = [-0.3, 0.0, -0.3, 0.3, 0.5, 0.3]
	if not _dims.has(id):
		if is_veg(id):
			var a := (load(veg_path(id, 0)) as Mesh).get_aabb()
			_dims[id] = [a.position.x, a.position.y, a.position.z, a.end.x, a.end.y, a.end.z]
		else:
			push_error("W9 dims 無し: " + id)
			return [-0.3, 0.0, -0.3, 0.3, 0.5, 0.3]
	return _dims[id]


static func yaw_to(d: Vector2) -> float:
	var n := d.normalized()
	return atan2(n.x, n.y)


## 足元の四隅（scale 込み）
static func foot(it: Dictionary) -> PackedVector2Array:
	var d: Array = dims(String(it["id"]))
	var sx := float(it.get("sx", 1.0))
	var sz := float(it.get("sz", 1.0))
	var yaw := float(it["yaw"])
	var p: Vector2 = it["p"]
	var ex := Vector2(cos(yaw), -sin(yaw))
	var ez := Vector2(sin(yaw), cos(yaw))
	if is_veg(String(it["id"])) and bool(it.get("soft", false)):
		# 植物は幹・株元だけを足元とする（葉は壁や垣に触れてよい）
		var r := (0.3 if String(it["id"]).begins_with("young") else 0.35) * maxf(sx, sz)
		return PackedVector2Array([p + ex * -r + ez * -r, p + ex * r + ez * -r, p + ex * r + ez * r, p + ex * -r + ez * r])
	var x0 := minf(float(d[0]) * sx, float(d[3]) * sx)
	var x1 := maxf(float(d[0]) * sx, float(d[3]) * sx)
	var z0 := float(d[2]) * sz
	var z1 := float(d[5]) * sz
	return PackedVector2Array([p + ex * x0 + ez * z0, p + ex * x1 + ez * z0, p + ex * x1 + ez * z1, p + ex * x0 + ez * z1])


static func height_of(it: Dictionary) -> float:
	return float(dims(String(it["id"]))[4]) * float(it.get("sy", 1.0))


# ─────────────────────────── 文脈 ───────────────────────────

## 見えている最上面（地形・路面・P4 院子・P8 田・ground decal）＋店先帯
static func top_h(C: Dictionary, p: Vector2) -> float:
	var h := HX.top_h(C, p)
	var f := (C["F"] as RLib.TriSampler).h(p.x, p.y)
	if not is_nan(f):
		h = maxf(h, f)
	return h


static func context(v: Node3D, meadow_pts: PackedVector2Array) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var C := HX.context(v, meadow_pts)
	C["D"] = {}
	C["dropped"] = []
	# 町家の基壇上端の絶対 y と、Kit の軒下端
	var by := {}
	var brec := {}
	for b in v.get_node("Districts").find_children("B_*", "", true, false):
		var n3 := b as Node3D
		if n3 != null and n3.has_meta("width_m"):
			by[String(n3.name)] = RLib.rel_xf(n3, v).origin.y
			var kit := n3.get_node_or_null("Kit")
			if kit != null:
				brec[String(n3.name)] = [float(kit.get_meta("door_rec", 0.0)), float(kit.get_meta("door_w", 1.8))]
	C["bld_y"] = by
	C["bld_rec"] = brec
	# root 直下の「物」overlay（R4／R4b の生活 props・農家・水車の柄杓・参道）：AABB +0.4
	var RP := HU.Grid.new()
	var n_rp := 0
	for nm in ["HumanUseP10", "HumanUseExpansionP10", "FarmsteadP13", "WaterLifeP10"]:
		var ov := v.get_node_or_null(nm)
		if ov == null:
			continue
		for mi in ov.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null or g.visibility_range_begin > 0.001:
				continue
			var r := HU._rect_of(g, v)
			if r.size.x > 60.0 or r.size.y > 60.0:
				continue
			RP.add(r.grow(0.4), r.grow(0.4))
			n_rp += 1
	C["rootp_g"] = RP
	C["n_rootp"] = n_rp
	C["w9_ms"] = Time.get_ticks_msec() - t0
	return C


static func bld(C: Dictionary, name: String) -> Dictionary:
	for b: Dictionary in C["bld"]:
		if String(b["name"]) == name:
			return b
	push_error("W9 建物なし " + name)
	return {}


static func _hit(G: HU.Grid, q: Vector2) -> bool:
	for r in G.at(q):
		if (r as Rect2).has_point(q):
			return true
	return false


## 主街の店先帯（壁から BAND m まで）に点があるか。band 指定の物だけ、その帯の中では路面を許す
static func _in_band(C: Dictionary, it: Dictionary, q: Vector2) -> bool:
	var nm := String(it.get("b", ""))
	if nm == "":
		return false
	var b := bld(C, nm)
	if b.is_empty():
		return false
	var d: float = SL.obb_d(b, q)
	return d >= -0.14 and d <= SL.BAND + 0.05


## 置けない理由（"" なら置ける）。mode：ground（地面）／wall（壁付け：店先帯・外壁際が許される）／soft（植物：草・env の足元を許す）
static func why(C: Dictionary, it: Dictionary, items: Array, mode: String) -> String:
	var poly := foot(it)
	var S: RLib.TriSampler = C["S"]
	var WS: RLib.TriSampler = C["WS"]
	var RBS: RLib.TriSampler = C["RBS"]
	var P8: RLib.TriSampler = C["P8"]
	var Rr: RLib.TriSampler = C["R"]
	var Fr: RLib.TriSampler = C["F"]
	var wall := mode == "wall"
	var soft := mode == "soft"
	var hang := bool(it.get("hang", false))
	var band := bool(it.get("band", false))
	for q in HU.samples(poly, 0.3):
		var sh := S.h(q.x, q.y)
		if is_nan(sh):
			return "terrain"
		if hang:
			# 壁・軒から吊るす物（頭より上／壁に張り付く薄い物）：地面の占有（道・店先帯・P10・NPC・田…）は問わない。壁に埋まる・水の上・建物の中だけ止める
			if not bool(it.get("recess", false)):
				for b: Dictionary in C["bld"]:
					if (b["o"] as Vector2).distance_to(q) < 14.0 and SL.obb_d(b, q) < -0.14:
						return "inside_building(%s %.2f)" % [String(b["name"]).trim_prefix("B_P_"), SL.obb_d(b, q)]
			continue
		if not is_nan(Rr.h(q.x, q.y)) and not (band and _in_band(C, it, q)):
			return "road"
		if not wall and not is_nan(Fr.h(q.x, q.y)) and not bool(it.get("on_frontage", false)):
			return "frontage"
		if not wall and not bool(it.get("gap", false)):
			for b: Dictionary in C["bld"]:
				if (b["o"] as Vector2).distance_to(q) < 14.0 and SL.obb_d(b, q) < BLD_PAD:
					return "building"
		else:
			for b: Dictionary in C["bld"]:
				if (b["o"] as Vector2).distance_to(q) < 14.0 and SL.obb_d(b, q) < -0.14:
					return "inside_building(%s %.2f)" % [String(b["name"]).trim_prefix("B_P_"), SL.obb_d(b, q)]
		for o in [Vector2.ZERO, Vector2(0.8, 0), Vector2(-0.8, 0), Vector2(0, 0.8), Vector2(0, -0.8)]:
			var p: Vector2 = q + o
			var wh := WS.h(p.x, p.y)
			if not is_nan(wh) and wh > S.h(p.x, p.y) - 0.02:
				return "water"
		var rh := RBS.h(q.x, q.y)
		if not is_nan(rh) and rh > sh + 0.03:
			return "p7"
		if (C["bridges"] as Array).any(func(r: Rect2) -> bool: return r.has_point(q)):
			return "bridge"
		if _hit(C["hero_g"], q):
			return "hero"
		for o in [Vector2.ZERO, Vector2(0.4, 0), Vector2(-0.4, 0), Vector2(0, 0.4), Vector2(0, -0.4)]:
			if not is_nan(P8.h(q.x + o.x, q.y + o.y)):
				return "p8"
		if _hit(C["sealed_g"], q):
			return "sealed"
		for t: Vector2 in C["trunks"]:
			if t.distance_to(q) < 0.6:
				return "trunk"
		if _hit(C["env_g"], q) and not soft:
			return "env"
		if _hit(C["p10_g"], q):
			return "p10"
		if _hit(C["rootp_g"], q) and not bool(it.get("hang", false)) and not bool(it.get("allow_rootp", false)):
			return "r4"
		if _hit(C["pop_g"], q):
			return "npc"
		for t: Vector2 in C["npc"]:
			if t.distance_to(q) < NPC_PAD:
				return "npc"
		for pts: PackedVector2Array in C["npc_paths"]:
			for k in range(1, pts.size()):
				if Geometry2D.get_closest_point_to_segment(q, pts[k - 1], pts[k]).distance_to(q) < PATROL_PAD:
					return "npc"
		for a: Vector2 in C["env_anchor"]:
			if a.distance_to(q) < HU.ENV_ANCHOR_PAD and not soft:
				return "env"
	# 地面物は道路から少し離す（中心線の通行を確保）
	if not wall and not soft and not bool(it.get("gap", false)):
		for q in HU.samples(poly, 0.45):
			for o in [Vector2(ROAD_PAD, 0), Vector2(-ROAD_PAD, 0), Vector2(0, ROAD_PAD), Vector2(0, -ROAD_PAD)]:
				if not is_nan(Rr.h(q.x + o.x, q.y + o.y)):
					return "road_pad"
	for bp: PackedVector2Array in C["backdoor"]:
		if not wall and (bp[0] as Vector2).distance_to(it["p"]) < 12.0 and not Geometry2D.intersect_polygons(poly, bp).is_empty():
			return "backdoor"
	for b: Dictionary in C["bld"]:
		if (b["o"] as Vector2).distance_to(it["p"]) < 14.0:
			var dp := SL.door_poly(b)
			var grown := Geometry2D.offset_polygon(dp, 0.02 if bool(it.get("gap", false)) else (0.12 if wall else DOOR_MARGIN))
			for g: PackedVector2Array in grown:
				if not Geometry2D.intersect_polygons(poly, g).is_empty() and not bool(it.get("hang", false)):
					return "door"
	for m: Dictionary in C["market"]:
		if not hang and (m["p"] as Vector2).distance_to(it["p"]) < 8.0 and not Geometry2D.intersect_polygons(poly, SL.MK.corners(m)).is_empty():
			return "p10"
	if not soft and not hang and not bool(it.get("meadow_ok", false)) and not bool(it.get("gap", false)) and (C["meadow"] as Dictionary).size() > 0:
		var r := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			r = r.expand(q)
		if HU.meadow_in(C, r.grow(0.3)) > 0:
			return "meadow"
	if not bool(it.get("nov", false)):
		for o: Dictionary in items:
			if o == it or bool(o.get("nov", false)) or (o["p"] as Vector2).distance_to(it["p"]) > 9.0:
				continue
			if hang != bool(o.get("hang", false)) and height_of(o) < 1.6 and hang:
				continue          # 低い地面の物の上に吊る物が重なるのは構わない（高さが違う）
			if not Geometry2D.intersect_polygons(poly, foot(o)).is_empty():
				return "overlap:" + String(o["id"])
	return ""


static func relief(C: Dictionary, it: Dictionary) -> float:
	var hs: Array = [top_h(C, it["p"])]
	for q in foot(it):
		hs.append(top_h(C, q))
	return float(hs.max()) - float(hs.min())


static func ground_y(C: Dictionary, it: Dictionary) -> float:
	var hs: Array = [top_h(C, it["p"])]
	for q in foot(it):
		hs.append(top_h(C, q))
	return float(hs.min())


static func item(C: Dictionary, id: String, p: Vector2, face: Vector2, meta: Dictionary) -> Dictionary:
	var it := {"id": id, "p": p, "yaw": yaw_to(face), "y": 0.0}
	it.merge(meta, true)
	if not bool(it.get("hang", false)):
		it["y"] = ground_y(C, it)
	return it


## 置く（足元が合法・平ら）。ring 検索 rmax（0＝その場のみ）
static func place(C: Dictionary, items: Array, id: String, c: Vector2, face: Vector2, meta: Dictionary, mode := "ground", rmax := 0.0) -> Dictionary:
	var r := 0.0
	var last := ""
	while r <= rmax + 0.001:
		var n := 1 if r == 0.0 else 12
		for k in n:
			var a := TAU * k / 12.0
			var it := item(C, id, c + Vector2(cos(a), sin(a)) * r, face, meta)
			if not bool(it.get("hang", false)) and relief(C, it) > float(meta.get("relief_max", RELIEF_MAX)):
				last = "slope"
				continue
			var w := why(C, it, items, mode)
			if w != "":
				last = w
				continue
			items.append(it)
			return it
		r += 0.25
	(C["dropped"] as Array).append("%s near (%.1f,%.1f) 置けない（%s）[%s]" % [id, c.x, c.y, last, meta.get("cluster", "?")])
	return {}


# ─────────────────────────── 幾何：建物・宅間 ───────────────────────────

## 建物局部 → 世界（x＝幅方向、z＝前面からの距離）。壁の外面は z = d/2 + WALL_T
static func bw(b: Dictionary, x: float, zl: float) -> Vector2:
	return (b["o"] as Vector2) + (b["ax"] as Vector2) * x + (b["az"] as Vector2) * zl


static func front_z(b: Dictionary) -> float:
	return float(b["d"]) * 0.5 + WALL_T


## 開間（local x の範囲と kind）。bay_x は境界、kinds は各開間
static func bays(b: Dictionary) -> Array:
	var out: Array = []
	var bx: Array = b["bay_x"]
	var ks: Array = b["kinds"]
	for i in ks.size():
		if i + 1 < bx.size():
			out.append({"i": i, "x0": float(bx[i]), "x1": float(bx[i + 1]), "kind": String(ks[i])})
	return out


static func door_bay(b: Dictionary) -> int:
	var cx := float(b["door_cx"])
	var bs := bays(b)
	for e: Dictionary in bs:
		if cx >= float(e["x0"]) - 0.02 and cx <= float(e["x1"]) + 0.02 and String(e["kind"]).begins_with("door"):
			return int(e["i"])
	for e: Dictionary in bs:
		if cx >= float(e["x0"]) and cx <= float(e["x1"]):
			return int(e["i"])
	return -1


## 隣り合う 2 棟の壁の間（同じ道の同じ側）。a＝路に沿って小さい側、b＝大きい側
static func gaps(C: Dictionary, road: String) -> Array:
	var bs: Array = []
	for b: Dictionary in C["bld"]:
		if String(b["road"]) == road:
			bs.append(b)
	var out: Array = []
	for side in [1, -1]:
		var row: Array = []
		for b: Dictionary in bs:
			var az: Vector2 = b["az"]
			# 側＝道に対する向き（az の向き）：az.x の符号（WestBankLane は南北）
			if (1 if az.x > 0.0 else -1) == side:
				row.append(b)
		if row.is_empty():
			continue
		var ax0: Vector2 = (row[0]["ax"] as Vector2)
		row.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return (p["o"] as Vector2).dot(ax0) < (q["o"] as Vector2).dot(ax0))
		for k in range(row.size() - 1):
			var a: Dictionary = row[k]
			var c: Dictionary = row[k + 1]
			var axm: Vector2 = ((a["ax"] as Vector2) + (c["ax"] as Vector2)).normalized()
			var azm: Vector2 = ((a["az"] as Vector2) + (c["az"] as Vector2)).normalized()
			var dist: float = ((c["o"] as Vector2) - (a["o"] as Vector2)).dot(axm)
			var gw: float = absf(dist) - (float(a["w"]) + float(c["w"])) * 0.5
			if gw < 0.8:
				continue
			# 前面：奥行の小さい側（路から引っ込む側）に揃える
			var dmin := minf(float(a["d"]), float(c["d"]))
			var mid: Vector2 = ((a["o"] as Vector2) + (c["o"] as Vector2)) * 0.5
			# 壁間の中心（axm 方向の 2 つの壁面の中点）
			var sgn := 1.0 if dist > 0.0 else -1.0
			var wa: Vector2 = (a["o"] as Vector2) + axm * sgn * float(a["w"]) * 0.5
			var wc: Vector2 = (c["o"] as Vector2) - axm * sgn * float(c["w"]) * 0.5
			var center: Vector2 = (wa + wc) * 0.5
			var fr: Vector2 = mid + azm * (dmin * 0.5 + WALL_T)
			# center を前面の面へ射影
			var cf: Vector2 = fr + axm * (center - fr).dot(axm)
			out.append({"a": String(a["name"]), "b": String(c["name"]), "w": gw, "ax": axm * sgn, "az": azm, "front": cf, "dmin": dmin, "side": side,
				"wa": wa, "wc": wc, "depth_a": float(a["d"]), "depth_c": float(c["d"]), "oa": a["o"], "oc": c["o"], "a_ax": a["ax"], "c_ax": c["ax"]})
	return out


# ─────────────────────────── 壁付けの特徴（建物ごとの生活） ───────────────────────────

## 特徴＝部品の並び。[id, dx（開間中心から局部 x）, dz（外壁面からの距離。-1＝壁に背を付ける自動）, yaw°, sx 種別（"fit"＝開間に合わせる／数値）, 追加 meta]
## prefer＝その特徴が似合う開間の kind（先に書いた kind を優先）、span＝使う開間数、hang＝壁・軒から吊る（足元は地面でなく基壇上端）
const FEAT := {
	"ueki": {"prefer": ["plain", "koshi", "koshir", "koshib", "mado", "amado"], "span": 1, "hang": false, "parts": [["w9_ueki_tana", 0.0, -1.0, 0.0, "fit1", {}]],
		"who": "草花を育てる家", "why": "壁際の植木棚（鉢の花と葉）：門前の暮らしの目印"},
	"sudare": {"prefer": ["koshi", "koshir", "koshib", "mado", "amado", "plain"], "span": 2, "hang": true, "parts": [["w9_sudare", 0.0, 0.0, 0.0, "fit", {}]],
		"who": "夏の日差しを避ける家", "why": "格子窓の前に簾を下げる（窓まわりの変化）"},
	"kaki": {"prefer": ["koshi", "koshir", "koshib", "mado", "amado", "plain"], "span": 2, "hang": true, "parts": [["w9_tsurushi_kaki", 0.0, 0.0, 0.0, "fit", {}]],
		"who": "干し柿をつくる家", "why": "軒先に竹竿を渡して干し柿を吊るす（秋の保存食）"},
	"toga": {"prefer": ["koshi", "koshir", "koshib", "mado", "amado", "plain"], "span": 2, "hang": true, "parts": [["w9_tsurushi_togarashi", 0.0, 0.0, 0.0, "fit", {}]],
		"who": "唐辛子を干す家", "why": "軒先に唐辛子と大蒜を吊るして干す"},
	"asagao": {"prefer": ["mado", "amado", "koshi", "koshir", "koshib", "plain"], "span": 2, "hang": false, "parts": [["w9_asagao", 0.0, -1.0, 0.0, "fit", {}]],
		"who": "朝顔を這わせる家", "why": "壁際に竹の棚をたて、朝顔を這わせる"},
	"wood": {"prefer": ["plain", "amado", "koshi", "koshir", "koshib", "mado"], "span": 2, "hang": false, "parts": [["sk_woodpile", 0.0, -1.0, 0.0, "fit", {}]],
		"who": "薪を焚く家", "why": "壁際に薪を積んで乾かす"},
	"kame": {"prefer": ["plain", "amado", "koshi", "koshir", "koshib", "mado"], "span": 1, "hang": false, "parts": [["mk_kame", 0.0, -1.0, 0.0, 1.0, {}], ["kr_houki", 0.55, -1.0, 12.0, 1.0, {}]],
		"who": "水を汲み置く家", "why": "戸口脇の水甕と立て掛けた箒"},
	"kago": {"prefer": ["plain", "amado", "koshi", "koshir", "koshib", "mado"], "span": 1, "hang": false, "parts": [["kr_kago", -0.18, -1.0, 20.0, 1.0, {}], ["sk_teoke", 0.22, -1.0, -25.0, 1.0, {}]],
		"who": "畑仕事から戻った家", "why": "戸口脇の竹籠と手桶"},
	"hachi": {"prefer": ["plain", "amado", "koshi", "koshir", "koshib", "mado"], "span": 1, "hang": false, "low": true, "parts": [["sz_hachi", -0.15, -1.0, 0.0, 1.0, {}], ["sz_hachi", 0.2, -1.0, 40.0, 0.85, {}]],
		"who": "鉢を並べる家", "why": "戸口脇に鉢を 2 つ"},
	"tools": {"prefer": ["plain", "amado", "koshi", "koshir", "koshib", "mado"], "span": 1, "hang": false, "parts": [["st_kuwa", 0.0, -1.0, 0.0, 1.0, {}]],
		"who": "畑を持つ家", "why": "壁に鍬を立て掛ける"},
	"sugi": {"prefer": ["shop_k", "shop_c", "koshi", "koshir", "koshib", "plain", "mado"], "span": 1, "hang": true, "dy": 0.0, "parts": [["w9_sugidama", 0.0, 0.0, 0.0, 1.0, {}]],
		"who": "酒屋", "why": "軒先の杉玉（酒屋の印）：遠くからでも酒屋とわかる"},
	"zori": {"prefer": ["koshib", "koshi", "koshir", "plain", "shop_c", "shop_k"], "span": 2, "hang": false, "parts": [["w9_zori_kake", 0.0, 0.5, 0.0, 1.0, {}]],
		"who": "履物屋", "why": "店先の草鞋掛け（藁草履を吊るして売る）"},
	"zaru": {"prefer": ["koshi", "plain", "koshib", "koshir", "shop_c", "shop_k"], "span": 2, "hang": false, "parts": [["w9_zaru_kake", 0.0, 0.5, 0.0, 1.0, {}]],
		"who": "竹細工・荒物屋", "why": "店先に笊と籠の吊り棚（竹細工の店）"},
	"hana": {"prefer": ["plain", "koshi", "koshir", "koshib", "mado", "amado"], "span": 1, "hang": false, "soft": true, "low": true, "parts": [["w9_hana_kiiro", 0.0, 0.35, 0.0, 1.0, {"soft": true, "nov": true}]],
		"who": "壁際の野の花", "why": "犬走りの隙間に自然に咲く花（整えすぎない）"},
}


## side（+1＝戸口の右（局部 x が大きい）／−1＝左）の、戸口でない開間を戸口に近い順に
static func side_bays(b: Dictionary, side: int) -> Array:
	var db := door_bay(b)
	var bs := bays(b)
	var out: Array = []
	var dx0 := 0.0
	var dx1 := 0.0
	for e: Dictionary in bs:
		if int(e["i"]) == db:
			dx0 = float(e["x0"])
			dx1 = float(e["x1"])
	for e: Dictionary in bs:
		if int(e["i"]) == db or String(e["kind"]).begins_with("door"):
			continue
		var mid := (float(e["x0"]) + float(e["x1"])) * 0.5
		if (side > 0 and mid > dx1 - 0.05) or (side < 0 and mid < dx0 + 0.05):
			out.append(e)
	out.sort_custom(func(p: Dictionary, q: Dictionary) -> bool:
		return absf((float(p["x0"]) + float(p["x1"])) * 0.5 - (dx0 + dx1) * 0.5) < absf((float(q["x0"]) + float(q["x1"])) * 0.5 - (dx0 + dx1) * 0.5))
	return out


## 特徴を 1 つ置く。pick＝戸口から数えて nth 番目の開間群（side）。成功した item の配列を返す
static func wall_feature(C: Dictionary, items: Array, b: Dictionary, feat: String, side: int, nth: int, meta: Dictionary, o := {}) -> Array:
	var F: Dictionary = FEAT[feat]
	var cand := side_bays(b, side)
	if cand.is_empty():
		(C["dropped"] as Array).append("%s %s：開間なし（side %d）[%s]" % [b["name"], feat, side, meta.get("cluster", "?")])
		return []
	# 優先 kind で並べ替え（安定：戸口に近い順を保ち、prefer の先頭 kind を前に）
	var pref: Array = F["prefer"]
	var ranked := cand.duplicate()
	ranked.sort_custom(func(p: Dictionary, q: Dictionary) -> bool:
		var rp := pref.find(String(p["kind"]))
		var rq := pref.find(String(q["kind"]))
		rp = 99 if rp < 0 else rp
		rq = 99 if rq < 0 else rq
		if rp != rq:
			return rp < rq
		return cand.find(p) < cand.find(q))
	# 使用済みの開間は避ける（C["used_bays"][建物名] = [開間 index…]）。低い物（hachi／hana）は共有可
	var used: Array = (C.get("used_bays", {}) as Dictionary).get(String(b["name"]), [])
	var free := ranked.filter(func(e: Dictionary) -> bool: return not used.has(int(e["i"])))
	if not free.is_empty() and not bool(F.get("low", false)):
		ranked = free
	var first: Dictionary = ranked[mini(nth, ranked.size() - 1)]
	var x0 := float(first["x0"])
	var x1 := float(first["x1"])
	# span 2：隣接する同じ側の開間（戸口でない・別の kind でも可）を足す
	if int(F["span"]) >= 2:
		for e: Dictionary in cand:
			if (int(e["i"]) == int(first["i"]) + 1 or int(e["i"]) == int(first["i"]) - 1) and not used.has(int(e["i"])):
				if maxf(x1, float(e["x1"])) - minf(x0, float(e["x0"])) <= 2.0:
					x0 = minf(x0, float(e["x0"]))
					x1 = maxf(x1, float(e["x1"]))
				break
	var width := x1 - x0
	var xc := (x0 + x1) * 0.5 + float(o.get("shift", 0.0))
	var got: Array = []
	var hang := bool(F["hang"])
	var floor_y := float((C["bld_y"] as Dictionary)[String(b["name"])]) + FLOOR_Y
	var face: Vector2 = b["az"]
	for part: Array in F["parts"]:
		var id := String(part[0])
		var d: Array = dims(id)
		var iw := float(d[3]) - float(d[0])
		var sx := 1.0
		var fit: Variant = part[4]
		if fit is String:
			sx = clampf(width * 0.94 / maxf(iw, 0.1), 0.45, 1.3) if String(fit) == "fit" else clampf(width * 0.98 / maxf(iw, 0.1), 0.7, 1.15)
		else:
			sx = float(fit)
		var sz := 1.0
		var dz := float(part[2])
		if dz < 0.0:
			dz = -float(d[2]) * sz + 0.04
		var xl := xc + float(part[1]) * minf(1.0, width / 1.8)
		var p := bw(b, xl, front_z(b) + dz)
		var yaw_off := deg_to_rad(float(part[3]))
		var m2 := {"cluster": String(meta["cluster"]), "zone": String(meta["zone"]), "who": String(F["who"]), "why": String(F["why"]), "b": String(b["name"]),
			"mode": "wall", "hang": hang, "sx": sx, "sy": 1.0, "sz": sz, "kind": "new" if id.begins_with("w9_") else "reuse", "feature": feat}
		(m2 as Dictionary).merge(part[5], true)
		for fk in ["band", "meadow_ok", "allow_rootp"]:
			if meta.has(fk):
				m2[fk] = meta[fk]
		if o.has("who"):
			m2["who"] = String(o["who"])
		var f2 := face.rotated(yaw_off) if yaw_off != 0.0 else face
		var it := item(C, id, p, f2, m2)
		if hang:
			it["y"] = floor_y + float(o.get("dy", float(F.get("dy", 0.0))))
		var mode := "soft" if bool(m2.get("soft", false)) else "wall"
		if not hang and relief(C, it) > 0.30:
			(C["dropped"] as Array).append("%s on %s：壁際の起伏 %.2f m（%s）" % [id, b["name"], relief(C, it), meta["cluster"]])
			continue
		var w := why(C, it, items, mode)
		if w != "" and not hang:
			# 壁際を戸口から離れる向きに 0.15 m ずつ最大 0.6 m 滑らせて再試行
			var ok := false
			for k in range(1, 5):
				for sgn in [1.0, -1.0]:
					var it2 := item(C, id, bw(b, xl + sgn * 0.15 * k, front_z(b) + dz), f2, m2)
					if why(C, it2, items, mode) == "" and relief(C, it2) <= 0.30:
						it = it2
						ok = true
						break
				if ok:
					break
			if not ok:
				(C["dropped"] as Array).append("%s on %s：置けない（%s）[%s]" % [id, b["name"], w, meta["cluster"]])
				continue
		elif w != "" and hang:
			(C["dropped"] as Array).append("%s on %s：置けない（%s）[%s]" % [id, b["name"], w, meta["cluster"]])
			continue
		items.append(it)
		got.append(it)
	if not got.is_empty() and not bool(F.get("low", false)):
		var ub: Dictionary = C.get("used_bays", {})
		var arr: Array = ub.get(String(b["name"]), [])
		for e: Dictionary in cand:
			if float(e["x0"]) >= x0 - 0.02 and float(e["x1"]) <= x1 + 0.02:
				arr.append(int(e["i"]))
		ub[String(b["name"])] = arr
		C["used_bays"] = ub
	return got


## 戸口の掀げ暖簾（既存 mise_kit の ms_noren_age_*：竿＋水引＋両脇に束ねた布）：戸口の幅に合わせ、戸口の凹みの面に掛ける
static func door_noren(C: Dictionary, items: Array, b: Dictionary, color: String, meta: Dictionary) -> void:
	var id := "ms_noren_age_" + color
	var rec: Array = (C["bld_rec"] as Dictionary).get(String(b["name"]), [0.0, 1.8])
	var dw := float(rec[1])
	var d: Array = dims(id)
	var sx := clampf(dw * 1.02 / (float(d[3]) - float(d[0])), 0.7, 1.15)
	var zl := front_z(b) - float(rec[0]) + 0.05
	var p := bw(b, float(b["door_cx"]), zl)
	var m2 := {"cluster": String(meta["cluster"]), "zone": String(meta["zone"]), "who": "戸口に暖簾を掛ける家", "why": "戸口の掀げ暖簾（藍・紅・生成り）：家ごとの色の目印", "b": String(b["name"]),
		"mode": "wall", "hang": true, "recess": true, "sx": sx, "sy": 1.0, "sz": 1.0, "kind": "reuse", "feature": "noren"}
	var it := item(C, id, p, b["az"], m2)
	it["y"] = float((C["bld_y"] as Dictionary)[String(b["name"])]) + FLOOR_Y + 1.92
	var w := why(C, it, items, "wall")
	if w != "":
		(C["dropped"] as Array).append("%s on %s：置けない（%s）[%s]" % [id, b["name"], w, meta["cluster"]])
		return
	items.append(it)


# ─────────────────────────── 宅間（gap） ───────────────────────────

static func gap_frame(g: Dictionary) -> Dictionary:
	var az: Vector2 = g["az"]
	var xd := Vector2(az.y, -az.x)
	var front: Vector2 = g["front"]
	var ua: float = ((g["wa"] as Vector2) - front).dot(xd)
	var uc: float = ((g["wc"] as Vector2) - front).dot(xd)
	return {"front": front, "xd": xd, "az": az, "ua": ua, "uc": uc, "w": absf(uc - ua), "lo": minf(ua, uc), "hi": maxf(ua, uc)}


## 宅間の点：front から u（xd 方向）、v（前面から奥へ）
static func gp(F: Dictionary, u: float, v: float) -> Vector2:
	return (F["front"] as Vector2) + (F["xd"] as Vector2) * u - (F["az"] as Vector2) * v


## 板塀／竹垣を [u0,u1] に敷き詰める（長さ 2.04 の module を等倍に近く伸縮）
static func fence_run(C: Dictionary, items: Array, F: Dictionary, id: String, u0: float, u1: float, v: float, meta: Dictionary) -> Array:
	var got: Array = []
	var L := u1 - u0
	if L < 0.3:
		return got
	var n := maxi(1, int(round(L / 2.0)))
	var seg := L / n
	var d: Array = dims(id)
	var mw := float(d[3]) - float(d[0])
	for k in n:
		var uc := u0 + seg * (k + 0.5)
		var m2 := meta.duplicate()
		m2.merge({"mode": "gap", "gap": true, "sx": seg / mw * 1.02, "sy": 1.0, "sz": 1.0, "kind": "new"}, true)
		var it := item(C, id, gp(F, uc, v), F["az"], m2)
		var w := why(C, it, items, "wall")
		if w != "":
			(C["dropped"] as Array).append("%s（宅間の垣）%.1f m：%s [%s]" % [id, seg, w, meta.get("cluster", "?")])
			continue
		items.append(it)
		got.append(it)
	return got


## 壁に背を付けて宅間へ張り出す物（下屋・植木棚など）。wall_u＝壁の u（lo／hi）、v＝前面から奥へ（物の中心）
static func lean_to(C: Dictionary, items: Array, F: Dictionary, id: String, wall_hi: bool, v: float, meta: Dictionary, mirror := false) -> Dictionary:
	var u_wall: float = float(F["hi"]) if wall_hi else float(F["lo"])
	var n: Vector2 = (F["xd"] as Vector2) * (-1.0 if wall_hi else 1.0)    # 壁から宅間の内へ向く方向
	var m2 := meta.duplicate()
	m2.merge({"mode": "gap", "gap": true, "sx": 1.0, "sy": 1.0, "sz": 1.0, "kind": "new" if id.begins_with("w9_") else "reuse"}, true)
	# 下屋の開いた側（局部 +x）を路（az）へ向ける：壁が hi 側なら +x が az、lo 側なら −az になるので反転版を使う
	if (id == "w9_shita_wood" or id == "w9_shita_tool") and not wall_hi:
		id = id + "_m"
	var it := item(C, id, gp(F, u_wall, v), n, m2)
	# 壁面から 0.04 離す
	it["p"] = (it["p"] as Vector2) + n * 0.04
	it["y"] = ground_y(C, it)
	var w := why(C, it, items, "wall")
	if w != "" or relief(C, it) > 0.35:
		(C["dropped"] as Array).append("%s（lean-to）%s [%s]" % [id, w if w != "" else "slope %.2f" % relief(C, it), meta.get("cluster", "?")])
		return {}
	items.append(it)
	return it


## 宅間の地面の点に置く（植物・祠・棚）：gap の内側 u,v
static func gap_point(C: Dictionary, items: Array, F: Dictionary, id: String, u: float, v: float, face_deg: float, meta: Dictionary, mode := "soft", rmax := 0.5) -> Dictionary:
	var m2 := meta.duplicate()
	m2.merge({"mode": "gap", "gap": true, "kind": "new" if id.begins_with("w9_") else "reuse"}, true)
	var f: Vector2 = (F["az"] as Vector2).rotated(deg_to_rad(face_deg))
	return place(C, items, id, gp(F, u, v), f, m2, mode, rmax)


# ─────────────────────────── 設計：Zone R（住宅側巷 WestBankLane） ───────────────────────────

## 各戸の暮らし（facade の特徴）：[feat, side（+1 戸口の右／−1 左）, nth（優先順位の何番目の開間群か）]
const R_HOUSES := {
	"B_P_RSW_046": [["noren_ai", 0, 0], ["ueki", -1, 0], ["sudare", -1, 0], ["hachi", 1, 0]],
	"B_P_RSW_047": [["sudare", 1, 0], ["kago", -1, 0]],
	"B_P_RSW_048": [["wood", -1, 0], ["sudare", 1, 0]],
	"B_P_RSW_049": [["noren_beni", 0, 0], ["kaki", -1, 0], ["ueki", -1, 0]],
	"B_P_RSW_050": [["asagao", 1, 0], ["kago", -1, 0]],
	"B_P_RSW_051": [["tools", -1, 0], ["sudare", 1, 0]],
	"B_P_RSW_052": [["toga", 1, 0], ["hachi", 1, 0]],
	"B_P_RSW_053": [["noren_kinari", 0, 0], ["ueki", -1, 0], ["hachi", -1, 0], ["sudare", 1, 0]],
	"B_P_RSW_059": [["noren_kinari", 0, 0], ["wood", -1, 0], ["sudare", 1, 0]],
	"B_P_RSW_060": [["asagao", 1, 0], ["ueki", 1, 0]],
	"B_P_RSW_061": [["noren_ai", 0, 0], ["ueki", 1, 0], ["sudare", -1, 0], ["hachi", -1, 0]],
	"B_P_RSW_062": [["kame", 1, 0], ["kago", -1, 0]],
	"B_P_RSW_063": [["toga", 1, 0], ["hachi", -1, 0]],
	"B_P_RSW_064": [["tools", -1, 0], ["sudare", -1, 0]],
	"B_P_RSW_065": [["kago", 1, 0]],
	"B_P_RSW_066": [["noren_beni", 0, 0], ["kaki", 1, 0], ["wood", -1, 0]],
	"B_P_RSW_067": [["ueki", 1, 0], ["hachi", -1, 0]],
}
## 宅間：key＝"a|b"（gaps() の a|b）→ recipe, 引数
const R_GAPS := {
	"B_P_RSW_046|B_P_RSW_047": ["fence_gate", {"gate": 0.35}],
	"B_P_RSW_047|B_P_RSW_048": ["yard", {"gate": 0.62, "kaki": true}],
	"B_P_RSW_048|B_P_RSW_049": ["shed_wood", {"wall": "a"}],
	"B_P_RSW_049|B_P_RSW_050": ["fence", {}],
	"B_P_RSW_050|B_P_RSW_051": ["fence_gate", {"gate": 0.5, "id": "w9_takegaki"}],
	"B_P_RSW_051|B_P_RSW_052": ["shed_tool", {"wall": "a"}],
	"B_P_RSW_052|B_P_RSW_053": ["shrine", {"id": "w9_hokora"}],
	"B_P_RSW_053|B_P_RSW_054": ["open", {}],
	"B_P_RSW_060|B_P_RSW_061": ["shrine", {"id": "w9_jizo"}],
	"B_P_RSW_061|B_P_RSW_062": ["yard", {"gate": 0.4}],
	"B_P_RSW_062|B_P_RSW_063": ["fence", {"id": "w9_itabei_b"}],
	"B_P_RSW_063|B_P_RSW_064": ["shed_wood", {"wall": "c"}],
	"B_P_RSW_064|B_P_RSW_065": ["yard", {"gate": 0.55, "id": "w9_takegaki"}],
	"B_P_RSW_065|B_P_RSW_066": ["shed_tool", {"wall": "c"}],
	"B_P_RSW_066|B_P_RSW_067": ["fence_gate", {"gate": 0.45}],
	"B_P_RSW_067|B_P_RSW_068": ["fence", {}],
}


static func _cl_meta(cl: Dictionary) -> Dictionary:
	return {"cluster": String(cl["id"]), "zone": String(cl["zone"])}


static func _plants(C: Dictionary, items: Array, F: Dictionary, meta: Dictionary, seed_i: int, n_shrub: int, n_hana: int, tree := false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90000 + seed_i
	var lo := float(F["lo"])
	var hi := float(F["hi"])
	var hana_ids := ["w9_hana_kiiro", "w9_hana_shiro", "w9_hana_pink", "w9_hana_higanbana"]
	for k in n_shrub:
		var id: String = ["shrub_a", "shrub_a", "fern_a", "sasa_a"][rng.randi() % 4]
		var u := lerpf(lo + 0.5, hi - 0.5, rng.randf())
		var v := rng.randf_range(1.2, 5.0)
		var m2 := meta.duplicate()
		m2.merge({"who": "宅間の庭木", "why": "宅間に生える低木・羊歯・笹（家ごとに種類と密度が違う）", "sx": rng.randf_range(0.7, 1.15), "sy": 1.0, "sz": 1.0, "soft": true, "nov": true}, true)
		m2["sy"] = m2["sx"]
		m2["sz"] = m2["sx"]
		gap_point(C, items, F, id, u, v, rng.randf_range(0.0, 360.0), m2, "soft", 0.6)
	for k in n_hana:
		var id2: String = hana_ids[rng.randi() % 3 + (1 if rng.randf() < 0.2 else 0)]
		var u2 := lerpf(lo + 0.4, hi - 0.4, rng.randf())
		var v2 := rng.randf_range(-0.5, 2.0)
		var m3 := meta.duplicate()
		m3.merge({"who": "宅間の野の花", "why": "宅間の入口に自然に咲く小さな花", "sx": rng.randf_range(0.8, 1.2), "sy": 1.0, "sz": 1.0, "soft": true, "nov": true, "on_frontage": true}, true)
		m3["sy"] = m3["sx"]
		m3["sz"] = m3["sx"]
		gap_point(C, items, F, id2, u2, v2, rng.randf_range(0.0, 360.0), m3, "soft", 0.5)
	if tree:
		var m4 := meta.duplicate()
		m4.merge({"who": "宅間の木", "why": "宅間の奥に立つ庭木（板塀の上から見える）", "sx": 0.85, "sy": 0.85, "sz": 0.85, "soft": true, "nov": true}, true)
		gap_point(C, items, F, ["young_broad_a", "young_broad_b"][seed_i % 2], (lo + hi) * 0.5 + rng.randf_range(-0.3, 0.3), 5.5, rng.randf_range(0.0, 360.0), m4, "soft", 1.0)


static func gap_recipe(C: Dictionary, items: Array, g: Dictionary, rc: String, args: Dictionary, meta: Dictionary, seed_i: int) -> void:
	var F := gap_frame(g)
	var lo := float(F["lo"])
	var hi := float(F["hi"])
	var w := float(F["w"])
	var fence_id := String(args.get("id", "w9_itabei_a"))
	var m := meta.duplicate()
	match rc:
		"fence", "fence_gate", "yard":
			m["who"] = "宅間を板塀で閉じる家"
			m["why"] = "宅間の正面を板塀（または竹垣）で閉じ、各戸の庭を街並みから分ける"
			var fid := fence_id if rc != "yard" else (fence_id if args.has("id") else "gk_yotsume")
			var v_f := 0.18
			if rc == "fence" or w < 2.3:
				fence_run(C, items, F, fid, lo - 0.05, hi + 0.05, v_f, m)
			else:
				var uc := clampf(lerpf(lo, hi, float(args.get("gate", 0.5))), lo + 1.0, hi - 1.0)
				fence_run(C, items, F, fid, lo - 0.05, uc - 0.94, v_f, m)
				var mg := m.duplicate()
				mg.merge({"who": "宅間の木戸", "why": "板塀の途中に小さな屋根付きの木戸（庭と路地の出入口）", "mode": "gap", "gap": true, "sx": 1.0, "sy": 1.0, "sz": 1.0, "kind": "new"}, true)
				var it := item(C, "w9_kido", gp(F, uc, v_f), F["az"], mg)
				var wy := why(C, it, items, "wall")
				if wy == "":
					items.append(it)
				else:
					(C["dropped"] as Array).append("w9_kido（宅間）%s [%s]" % [wy, meta["cluster"]])
				fence_run(C, items, F, fid, uc + 0.94, hi + 0.05, v_f, m)
			if rc == "yard":
				var mu := meta.duplicate()
				mu.merge({"who": "小庭を持つ家", "why": "塀の内に植木棚と朝顔（塀越しに見える）", "mode": "gap", "gap": true, "sx": 1.0, "sy": 1.0, "sz": 1.0, "kind": "new"}, true)
				lean_to(C, items, F, "w9_ueki_tana", true, 2.4, mu)
				var ma := mu.duplicate()
				ma["why"] = "塀の内の朝顔の棚"
				gap_point(C, items, F, "w9_asagao", lo + 0.9, 3.4, 0.0, ma, "wall", 0.4)
				if w >= 3.5:
					var mh := mu.duplicate()
					mh.merge({"who": "洗い物を干す家", "why": "宅間に渡した物干し（色とりどりの布）", "sx": minf(1.0, (w - 0.6) / 3.44), "sy": 1.0, "sz": 1.0, "kind": "reuse"}, true)
					gap_point(C, items, F, "mk_hoshimono", (lo + hi) * 0.5, 4.2, 0.0, mh, "wall", 0.3)
				if bool(args.get("kaki", false)) and w >= 4.4:
					var mk2 := mu.duplicate()
					mk2.merge({"who": "柿を干す家", "why": "塀の内の干し柿の棚（塀越しに橙の簾が見える）", "kind": "new"}, true)
					gap_point(C, items, F, "w9_kaki_dai", (lo + hi) * 0.5, 5.6, 0.0, mk2, "wall", 0.3)
				_plants(C, items, F, meta, seed_i, 2, 2, true)
			else:
				_plants(C, items, F, meta, seed_i, 1 if rc == "fence_gate" else 0, 3)
		"shed_wood", "shed_tool":
			var wall_hi := String(args.get("wall", "a")) == "c"
			if float(F["uc"]) < float(F["ua"]):
				wall_hi = not wall_hi
			var id := "w9_shita_wood" if rc == "shed_wood" else "w9_shita_tool"
			var ms := meta.duplicate()
			ms.merge({"who": "薪をつくる家" if rc == "shed_wood" else "畑道具をしまう家", "why": "宅間に壁を借りた下屋（片流れ屋根）。薪／農具の置き場で、屋根の高さが街並みの隙間に変化を与える"}, true)
			lean_to(C, items, F, id, wall_hi, 3.0 + 0.2, ms)
			# 路地側の入口：低い垣の端だけ（下屋が見えるように開ける）
			var mf := meta.duplicate()
			mf.merge({"who": "宅間の板塀", "why": "下屋の奥を隠す短い板塀（正面は開けておく）"}, true)
			var other_lo := lo if wall_hi else (lo + 1.7)
			var other_hi := (hi - 1.7) if wall_hi else hi
			if w > 3.2:
				if wall_hi:
					fence_run(C, items, F, "w9_itabei_b", lo - 0.05, lo + 1.0, 0.18, mf)
				else:
					fence_run(C, items, F, "w9_itabei_b", hi - 1.0, hi + 0.05, 0.18, mf)
			_plants(C, items, F, meta, seed_i, 1, 3)
		"shrine":
			var id2 := String(args.get("id", "w9_jizo"))
			var mz := meta.duplicate()
			mz.merge({"who": "宅間の祠を守る人々", "why": "宅間の隅の祠（供え花と小さな花）：路地の端に信仰の目印"}, true)
			gap_point(C, items, F, id2, (lo + hi) * 0.5 + 0.2, 1.6, 0.0, mz, "wall", 0.6)
			var mf2 := meta.duplicate()
			mf2.merge({"who": "宅間の垣", "why": "祠の両脇の低い垣"}, true)
			if w > 4.0:
				fence_run(C, items, F, "w9_takegaki", lo - 0.05, lo + 0.9, 0.2, mf2)
				fence_run(C, items, F, "w9_takegaki", hi - 0.9, hi + 0.05, 0.2, mf2)
			_plants(C, items, F, meta, seed_i, 2, 4, w > 5.0)
		"open":
			_plants(C, items, F, meta, seed_i, 3, 4, true)
			var mo := meta.duplicate()
			mo.merge({"who": "宅間の垣", "why": "道に面した低い四つ目垣（半分だけ）"}, true)
			var id3 := "gk_yotsume"
			var d3: Array = dims(id3)
			var mw3 := float(d3[3]) - float(d3[0])
			var seg := minf(w * 0.5, 2.8)
			var mi := mo.duplicate()
			mi.merge({"mode": "gap", "gap": true, "sx": seg / mw3, "sy": 1.0, "sz": 1.0, "kind": "reuse"}, true)
			var it3 := item(C, id3, gp(F, lo + seg * 0.5 - 0.05, 0.2), F["az"], mi)
			if why(C, it3, items, "wall") == "":
				items.append(it3)


## Zone R の cluster 一覧（戸ごと・宅間ごと）
static func _house_runner(b: Dictionary, feats: Array, extra := {}) -> Callable:
	return func(C2: Dictionary, items: Array, meta0: Dictionary) -> void:
		var meta := meta0.duplicate()
		meta.merge(extra, true)
		for f: Array in feats:
			if String(f[0]).begins_with("noren_"):
				door_noren(C2, items, b, String(f[0]).trim_prefix("noren_"), meta)
			else:
				wall_feature(C2, items, b, String(f[0]), int(f[1]), int(f[2]), meta)


static func _gap_runner(g: Dictionary, spec: Array, seed_i: int) -> Callable:
	return func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		gap_recipe(C2, items, g, String(spec[0]), spec[1], meta, seed_i)


static func design_R(C: Dictionary) -> Array:
	var D: Array = []
	var names: Array = R_HOUSES.keys()
	names.sort()
	for nm: String in names:
		var b := bld(C, nm)
		var feats: Array = R_HOUSES[nm]
		var who: Array = []
		for f: Array in feats:
			who.append("暖簾" if String(f[0]).begins_with("noren_") else String(FEAT[f[0]]["who"]))
		D.append({"id": "H_" + nm.trim_prefix("B_P_"), "zone": "R",
			"desc": "%s（%s・幅 %.1f m）の門前：%s" % [nm, b["type"], b["w"], " ・ ".join(PackedStringArray(who))],
			"center": b["o"], "run": _house_runner(b, feats)})
	var si := 0
	for g: Dictionary in gaps(C, "WestBankLane"):
		var key := "%s|%s" % [g["a"], g["b"]]
		var swap := false
		if not R_GAPS.has(key):
			key = "%s|%s" % [g["b"], g["a"]]
			swap = true
		if not R_GAPS.has(key):
			continue
		si += 1
		var spec: Array = (R_GAPS[key] as Array).duplicate(true)
		if swap and (spec[1] as Dictionary).has("wall"):
			(spec[1] as Dictionary)["wall"] = "c" if String((spec[1] as Dictionary)["wall"]) == "a" else "a"
		D.append({"id": "G_" + String(g["a"]).trim_prefix("B_P_") + "_" + String(g["b"]).trim_prefix("B_P_RSW_"), "zone": "R",
			"desc": "宅間 %s（幅 %.1f m）：%s" % [key, g["w"], spec[0]], "center": g["front"], "run": _gap_runner(g, spec, si)})
	return D


# ─────────────────────────── 設計：Zone M（主街南段） ───────────────────────────

## 店の用途が通りから読める目印（新規：杉玉・草鞋掛け・笊吊り・簾・植木棚）。業種は P13 W2 の正式設計表（data/village_v2_p13_mainstreet.json の cat）どおり。
## 町家 Kit は shop_o 開間にすでに暖簾、shop_k 開間の半分に簾を掛けるので、ここでは重ねない（格子窓・壁面・店先帯に置く）
const M_HOUSES := {
	"B_P_MKT_002": [["zori", 1, 0]],                                  # 履物屋
	"B_P_MKT_006": [["zaru", -1, 0]],                                 # 竹籠製作兼販売の工房
	"B_P_MKT_009": [["sudare", 1, 0]],                                # 二階退縮の茶屋
	"B_P_MKT_010": [["ueki", 1, 0], ["kaki", -1, 0]],                 # 蔵造りの住居（閉じた正面に暮らしの目印）
	"B_P_MKT_011": [["zaru", 1, 0]],                                  # 荒物屋
	"B_P_MKT_012": [["sugi", 1, 0], ["sugi", -1, 0]],                 # 大店の酒屋：杉玉を軒の両端に
	"B_P_MKT_014": [["sudare", -1, 0]],                               # 茶屋
	"B_P_MKT_017": [["sugi", 1, 0]],                                  # 酒屋
	"B_P_MKT_018": [["ueki", 1, 0], ["asagao", -1, 0], ["hachi", -1, 0]],   # 厨子二階の住宅
	"B_P_MKT_019": [["zaru", 1, 0]],                                  # 質素な荒物屋
	"B_P_MKT_020": [["sudare", -1, 0]],                               # 豆腐屋
	"B_P_MKT_022": [["sudare", 1, 0]],                                # 茶屋
	"B_P_MKT_026": [["zori", -1, 0]],                                 # 履物屋
}
const M_WHO := {"B_P_MKT_002": "履物屋", "B_P_MKT_006": "竹籠工房", "B_P_MKT_009": "茶屋", "B_P_MKT_010": "蔵造りの住居", "B_P_MKT_011": "荒物屋", "B_P_MKT_012": "酒屋（大店）",
	"B_P_MKT_014": "茶屋", "B_P_MKT_017": "酒屋", "B_P_MKT_018": "住居", "B_P_MKT_019": "荒物屋", "B_P_MKT_020": "豆腐屋", "B_P_MKT_022": "茶屋", "B_P_MKT_026": "履物屋"}


static func _slit_runner(g: Dictionary, si: int) -> Callable:
	return func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var F := gap_frame(g)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7100 + si * 31
		var left := rng.randf() < 0.5
		var u: float = (float(F["lo"]) + 0.34) if left else (float(F["hi"]) - 0.34)
		var du := 0.42 if left else -0.42
		var menu: Array = [["fern_a", "w9_hana_shiro"], ["w9_hana_kiiro", "fern_a"], ["w9_hana_pink", "w9_hana_shiro"], ["fern_a", "w9_hana_kiiro"], ["w9_hana_shiro", "w9_hana_pink"]][si % 5]
		var m2 := meta.duplicate()
		m2.merge({"who": "巷口の足元", "why": "町家の隙間の足元に生えた草と花（手入れされすぎない自然な縁取り）", "soft": true, "sx": 0.8, "sy": 0.8, "sz": 0.8}, true)
		gap_point(C2, items, F, String(menu[0]), u, 0.55, rng.randf_range(-40.0, 40.0), m2, "soft", 0.25)
		var m3 := m2.duplicate()
		m3["sx"] = 0.7
		m3["sy"] = 0.7
		m3["sz"] = 0.7
		gap_point(C2, items, F, String(menu[1]), u + du, 1.0, rng.randf_range(-40.0, 40.0), m3, "soft", 0.25)


static func design_M(C: Dictionary) -> Array:
	var D: Array = []
	var names: Array = M_HOUSES.keys()
	names.sort()
	for nm: String in names:
		var b := bld(C, nm)
		D.append({"id": "M_" + nm.trim_prefix("B_P_"), "zone": "M", "desc": "%s（%s）の店先：用途の目印" % [nm, M_WHO[nm]], "center": b["o"], "run": _house_runner(b, M_HOUSES[nm], {"band": true})})
	var si := 0
	for g: Dictionary in gaps(C, "MainStreet"):
		if float(g["w"]) > 2.0:
			continue
		si += 1
		D.append({"id": "S_%s_%s" % [String(g["a"]).trim_prefix("B_P_"), String(g["b"]).trim_prefix("B_P_")], "zone": "M", "desc": "巷口（%s｜%s・隙 %.1f m）の足元：草と花" % [g["a"], g["b"], g["w"]],
			"center": g["front"], "run": _slit_runner(g, si)})
	# 村の南の入口（南大門の北・道の東側の空き地）：道祖神の辻＝小祠・石灯籠・地蔵・縁台・屋敷木
	D.append({"id": "M_entrance", "zone": "M", "desc": "南の入口（南大門の北）の辻：小祠・石灯籠・地蔵・縁台・木（村に入って最初に目に入る生活の場）", "center": Vector2(245.5, 96.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var W := Vector2(-1.0, 0.0)
		_put(C2, items, "w9_hokora", 246.2, 96.4, W, meta, 1.0, {"who": "道を守る村人", "why": "村の入口の小さな祠（赤い小鳥居・注連縄）。村に入る人が手を合わせる", "sx": 1.35, "sy": 1.35, "sz": 1.35})
		_put(C2, items, "gk_toro_kasuga", 244.3, 94.2, W, meta, 0.8, {"who": "祠を守る村人", "why": "祠の脇の石灯籠（縦の輪郭で入口を示す）"})
		_put(C2, items, "w9_jizo", 244.7, 98.6, W, meta, 0.8, {"who": "道を守る村人", "why": "入口の地蔵（赤い前掛け）", "sx": 1.25, "sy": 1.25, "sz": 1.25})
		_put(C2, items, "sk_bench", 244.4, 101.8, W, meta, 1.0, {"who": "旅人を休ませる村人", "why": "入口の縁台（旅人の休み場）"})
		_put(C2, items, "young_broad_a", 249.2, 96.0, W, meta, 1.2, {"soft": true, "sx": 1.5, "sy": 1.5, "sz": 1.5, "who": "屋敷木", "why": "祠の後ろの木（社叢の名残）"})
		_put(C2, items, "young_broad_b", 248.0, 100.2, W, meta, 1.2, {"soft": true, "sx": 1.2, "sy": 1.2, "sz": 1.2, "who": "屋敷木", "why": "入口の脇の木"})
		var mp := meta.duplicate()
		mp.merge({"who": "祠の足元", "why": "祠の足元に咲く花と羊歯（人の手が入りすぎない縁取り）"}, true)
		_drift(C2, items, Rect2(244.8, 94.0, 3.4, 8.0), 5, ["w9_hana_shiro", "w9_hana_higanbana", "fern_a", "w9_hana_pink"], 21, mp, 0.7)})
	return D


# ─────────────────────────── 設計：Zone F（村外の農家 FarmsteadP13） ───────────────────────────
## 実測（w9_probe_pt の地図）：主屋 A1（x 314.8–321.2・z 77.5–86.5、戸口は東向き z 84.3）と納屋 A2（x 321.2–324.8・z 68.3–73.8）の前は
## 東の帯 x 324.5–328.5・z 76–92（草地 MeadowP9 なし・田 P8 は x≥328.5）が庭先。そこに「収穫物を扱う庭先」を作る。

static func _put(C: Dictionary, items: Array, id: String, x: float, z: float, face: Vector2, meta: Dictionary, rmax := 0.5, extra := {}) -> Dictionary:
	var m2 := meta.duplicate()
	m2.merge({"kind": "new" if id.begins_with("w9_") else "reuse", "mode": "ground"}, true)
	m2.merge(extra, true)
	var mode := "soft" if bool(m2.get("soft", false)) else "ground"
	var it := place(C, items, id, Vector2(x, z), face, m2, mode, rmax)
	if not it.is_empty() and bool(m2.get("hang", false)) and m2.has("y_off"):
		it["y"] = ground_y(C, it) + float(m2["y_off"])
	return it


## 区域内に群落ふうに植物を撒く：中心 n_c 個の周りに 2–4 株（間隔不均一・同色が固まる）
static func _drift(C: Dictionary, items: Array, rect: Rect2, n_c: int, ids: Array, seed_i: int, meta: Dictionary, spread := 1.1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91000 + seed_i
	for k in n_c:
		var c := Vector2(rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y))
		var id: String = ids[rng.randi() % ids.size()]
		for j in rng.randi_range(2, 4):
			var p := c + Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread))
			var m2 := meta.duplicate()
			var s := rng.randf_range(0.8, 1.25)
			m2.merge({"sx": s, "sy": s, "sz": s, "soft": true, "kind": "new" if id.begins_with("w9_") else "reuse", "mode": "soft", "on_frontage": false}, true)
			place(C, items, id, p, Vector2.from_angle(rng.randf_range(0.0, TAU)), m2, "soft", 0.3)


static func design_F(_C: Dictionary) -> Array:
	var D: Array = []
	var E := Vector2(1.0, 0.0)
	D.append({"id": "F_A1_eave", "zone": "F", "desc": "茅葺の主屋の前の軒下：唐辛子と大蒜（戸口は空ける）", "center": Vector2(321.3, 81.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		_put(C2, items, "w9_tsurushi_togarashi", 321.25, 82.2, E, meta, 0.0, {"hang": true, "y_off": 0.06, "who": "唐辛子を干す農家", "why": "戸口の手前の軒下に唐辛子と大蒜を吊るす"})})
	D.append({"id": "F_A1_yard", "zone": "F", "desc": "主屋の東の庭先（収穫物を扱う場所）：日向の干し柿の棚 2・藁塚・大根干し・甕・桶・籠", "center": Vector2(326.0, 84.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		_put(C2, items, "w9_kaki_dai", 326.6, 76.4, Vector2(0.9, 0.35), meta, 0.5, {"who": "柿を干す農家", "why": "庭先の日向に干し柿の棚（橙の簾）。渡し板から来ると最初に目に入る位置。主屋の立面の中央は空ける"})
		_put(C2, items, "w9_kaki_dai", 326.0, 90.6, Vector2(0.95, -0.3), meta, 0.5, {"who": "柿を干す農家", "why": "庭の南端にもう 1 つ（数・向きを揃えすぎない）", "sx": 0.8})
		_put(C2, items, "st_warazuka", 326.2, 73.8, Vector2(0.4, 1.0), meta, 1.0, {"who": "藁を積む農家", "why": "庭の北端の藁塚（脱穀のあとの藁）。縦の輪郭で庭先の端を示す", "sx": 1.1, "sy": 1.1, "sz": 1.1})
		_put(C2, items, "mk_kame", 324.7, 86.2, Vector2(0.9, 0.4), meta, 0.5, {"who": "水を汲み置く農家", "why": "戸口の南の水甕（庭先の水仕事）"})
		_put(C2, items, "sk_teoke", 325.3, 86.8, Vector2(0.4, 0.9), meta, 0.4, {"who": "水を汲み置く農家", "why": "手桶"})
		_put(C2, items, "kr_kago", 326.1, 85.9, Vector2(0.6, -0.8), meta, 0.5, {"who": "畑から戻った農家", "why": "収穫物の竹籠"})
		_put(C2, items, "kr_kago", 326.6, 86.7, Vector2(0.9, 0.4), meta, 0.4, {"who": "畑から戻った農家", "why": "収穫物の竹籠"})
		_put(C2, items, "hx_daikon_kake", 326.9, 87.6, E, meta, 1.0, {"who": "大根を干す農家", "why": "庭先の大根干し（冬の保存食づくり）"})
		_put(C2, items, "st_wara", 324.5, 91.3, Vector2(0.7, 0.7), meta, 0.8, {"who": "藁を積む農家", "why": "藁束"})})
	D.append({"id": "F_yard_edge", "zone": "F", "desc": "田の縁の案山子、路傍の地蔵、庭の隅の木", "center": Vector2(327.5, 80.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		_put(C2, items, "w9_kakashi", 328.0, 77.6, E, meta, 0.6, {"who": "田を守る農家", "why": "田の縁に立てた案山子（蓑・笠・藍の袖）。田へ向く", "sx": 1.1, "sy": 1.1, "sz": 1.1})
		_put(C2, items, "w9_jizo", 325.9, 66.6, Vector2(0.5, 0.9), meta, 1.2, {"who": "道を守る村人", "why": "渡し板の手前の路傍の地蔵（供え花と小皿）", "sx": 1.2, "sy": 1.2, "sz": 1.2})
		_put(C2, items, "young_broad_a", 325.2, 93.2, Vector2(0, 1), meta, 1.2, {"soft": true, "sx": 1.1, "sy": 1.1, "sz": 1.1, "who": "庭木", "why": "庭の南東の隅の屋敷木"})})
	D.append({"id": "F_edge", "zone": "F", "desc": "庭先の縁・水渠の西岸・農路の路肩の植物：群落ごとに種類と密度を変える（均一な草地にしない）", "center": Vector2(326.0, 78.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var mp := meta.duplicate()
		mp.merge({"who": "庭先の花", "why": "庭先と田の縁に咲く野の花（黄・白・桃の小群落）"}, true)
		_drift(C2, items, Rect2(324.8, 76.0, 2.6, 12.0), 5, ["w9_hana_kiiro", "w9_hana_shiro", "w9_hana_pink"], 11, mp, 0.7)
		var mb := meta.duplicate()
		mb.merge({"who": "水渠の西岸の彼岸花", "why": "水渠の西の岸に群れて咲く彼岸花（農路沿い）"}, true)
		_drift(C2, items, Rect2(321.4, 54.0, 3.0, 12.0), 6, ["w9_hana_higanbana", "w9_hana_higanbana", "fern_a"], 12, mb, 1.0)
		var mr := meta.duplicate()
		mr.merge({"who": "農路の路肩の草花", "why": "農路の南北の路肩に不均一に咲く草花と低木"}, true)
		_drift(C2, items, Rect2(333.0, 72.4, 16.0, 2.4), 6, ["w9_hana_kiiro", "w9_hana_shiro", "shrub_a", "sasa_a"], 13, mr, 1.2)
		_drift(C2, items, Rect2(333.0, 65.2, 16.0, 2.4), 5, ["w9_hana_pink", "w9_hana_kiiro", "fern_a"], 14, mr, 1.2)})
	return D


# ─────────────────────────── 計画・烘焙 ───────────────────────────

static func plan(v: Node3D, meadow_pts: PackedVector2Array, zones: Array = ["R"]) -> Dictionary:
	var C := context(v, meadow_pts)
	var items: Array = []
	var clusters: Array = []
	var des: Array = []
	for z: String in zones:
		match z:
			"R":
				des.append_array(design_R(C))
			"M":
				des.append_array(design_M(C))
			"F":
				des.append_array(design_F(C))
	for cl: Dictionary in des:
		var n0 := items.size()
		var meta := _cl_meta(cl)
		(cl["run"] as Callable).call(C, items, meta)
		var got: Array = items.slice(n0)
		clusters.append({"id": String(cl["id"]), "zone": String(cl["zone"]), "desc": String(cl["desc"]), "center": cl["center"], "n": got.size()})
	return {"C": C, "items": items, "clusters": clusters}


static func bake(P: Dictionary) -> Node3D:
	var C: Dictionary = P["C"]
	var root := Node3D.new()
	root.name = NODE_NAME
	var groups := {}
	for z: String in ZONE_NAME:
		var n := Node3D.new()
		n.name = "Zone" + z
		n.set_meta("zone", ZONE_NAME[z])
		root.add_child(n)
		groups[z] = n
	var cl_nodes := {}
	for cl: Dictionary in P["clusters"]:
		if int(cl["n"]) == 0:
			continue
		var n := Node3D.new()
		n.name = String(cl["id"])
		n.set_meta("desc", String(cl["desc"]))
		var c2: Vector2 = cl["center"]
		n.position = Vector3(c2.x, top_h(C, c2), c2.y)
		(groups[String(cl["zone"])] as Node).add_child(n)
		cl_nodes[String(cl["id"])] = n
	var col := StaticBody3D.new()
	col.name = "Collision"
	root.add_child(col)
	var meshes := {}
	var n_i := 0
	var ns := 0
	for it: Dictionary in P["items"]:
		var id := String(it["id"])
		var parent: Node3D = cl_nodes[String(it["cluster"])]
		var node := Node3D.new()
		node.name = "%03d_%s" % [n_i, id]
		var yaw := float(it["yaw"])
		var sc := Vector3(float(it.get("sx", 1.0)), float(it.get("sy", 1.0)), float(it.get("sz", 1.0)))
		var wxf := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(sc), Vector3((it["p"] as Vector2).x, float(it["y"]), (it["p"] as Vector2).y))
		node.transform = parent.transform.affine_inverse() * wxf
		for k in ["who", "why", "cluster", "zone", "kind"]:
			node.set_meta("w9_" + k, String(it.get(k, "")))
		node.set_meta("w9_id", id)
		node.set_meta("w9_feature", String(it.get("feature", "")))
		node.set_meta("w9_b", String(it.get("b", "")))
		node.set_meta("w9_mode", String(it.get("mode", "ground")))
		var fl := PackedStringArray()
		for fk in ["hang", "band", "recess", "meadow_ok", "allow_rootp", "soft", "gap", "nov", "on_frontage"]:
			if bool(it.get(fk, false)):
				fl.append(fk)
		node.set_meta("w9_flags", ",".join(fl))
		parent.add_child(node)
		for lv in bundle(id):
			var path := String(lv[0])
			if not meshes.has(path):
				meshes[path] = load(path)
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % (node.get_child_count())
			mi.mesh = meshes[path]
			mi.visibility_range_begin = float(lv[1])
			mi.visibility_range_end = float(lv[2])
			if not bool(lv[3]):
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
		if not (id in NO_COLLIDE) and not bool(it.get("hang", false)):
			var d: Array = dims(id)
			if float(d[4]) * sc.y >= 0.35:
				var bx := BoxShape3D.new()
				bx.size = Vector3((float(d[3]) - float(d[0])) * absf(sc.x), float(d[4]) * sc.y, (float(d[5]) - float(d[2])) * absf(sc.z))
				var cs := CollisionShape3D.new()
				cs.name = "%s_c" % node.name
				cs.shape = bx
				var ba := Basis(Vector3.UP, yaw)
				cs.transform = Transform3D(ba, wxf.origin + ba * Vector3((float(d[0]) + float(d[3])) * 0.5 * sc.x, float(d[4]) * sc.y * 0.5, (float(d[2]) + float(d[5])) * 0.5 * sc.z))
				col.add_child(cs)
				ns += 1
		n_i += 1
	root.set_meta("items", (P["items"] as Array).size())
	root.set_meta("clusters", cl_nodes.size())
	root.set_meta("shapes", ns)
	root.set_meta("art_revision", ART_REVISION)
	return root


## 診断：理由の頭文字の地図
static func survey(C: Dictionary, r: Rect2, step := 0.5) -> PackedStringArray:
	var out := PackedStringArray()
	var code := {"": ".", "terrain": " ", "road": "R", "frontage": "F", "building": "B", "water": "W", "p7": "w", "bridge": "b", "hero": "H", "p8": "A",
		"sealed": "S", "trunk": "T", "env": "E", "p10": "P", "npc": "N", "backdoor": "d", "door": "D", "meadow": "g", "slope": "/", "r4": "r", "road_pad": "~"}
	for j in int(r.size.y / step) + 1:
		var z := r.position.y + j * step
		var row := "%7.1f " % z
		for i in int(r.size.x / step) + 1:
			var x := r.position.x + i * step
			var it := item(C, "_probe", Vector2(x, z), Vector2(0, 1), {})
			var w := why(C, it, [], "ground")
			if w == "" and relief(C, it) > RELIEF_MAX:
				w = "slope"
			row += String(code.get(w, "?"))
		out.append(row)
	return out
