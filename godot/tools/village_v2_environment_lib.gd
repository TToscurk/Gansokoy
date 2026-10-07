extends RefCounted
## 人間之里 V2 P9 R5-4 Existing Asset Environment Pass——既存資產で自然・過渡・空地・林緣・水邊・農田交界の中尺度環境（全村擴張 x1）。
## generator＝source of truth：本 lib（規劃＋烘焙）→ maps/village_v2/gen/environment_p9.scn → village_v2.tscn の Props/EnvironmentP9。
## 分工（使用者 2026-10-05）：R5-4＝自然・過渡・空地・林緣・水邊・農田交界と環境 cluster；P10＝市集・主街・生活 props・工作區・NPC。
##   後院の生活 props（薪・桶・箱・干し竿…）は P10 の担当＝本 lib では使わない（R54_IDS 以外は gate で FAIL）。
##   P10 の實ノード（MarketP10・StreetP10・MarketWestP10…）の足元＋1.5 m と NPC anchors＋1.2 m は occupancy＝置かない（P10 優先）。
## 資產は全部既存 kit の mesh .res を「唯讀參照」（P7 riverbank_kit・P9 R1 veg_kit・P9 R4 garden／waterside・P10 street の柴垣のみ）；
##   source・原擺放・shader は一切変えない。新規 mesh は作らない。
## MeadowP9（R5-3 封存）は重烘しない：固い物（石・倒木・杭・垣）の足元の芯に MeadowP9 の規劃株（同 seed で再計算）が入らない所を選ぶ。
## 盤點：docs/asset_audit/env_2026-10-04/（environment_asset_audit.csv／README.md）。
## 擺放はノード（MeshInstance3D LOD0/LOD1＋BoxShape 碰撞）＝個別に選べる（MultiMesh を使わない）。

const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const ML := preload("res://tools/village_v2_groundcover_macro.gd")
const GC := preload("res://tools/village_v2_groundcover_lib.gd")
const VL := preload("res://tools/village_v2_groundcover_village.gd")
const OUTPUT := "res://maps/village_v2/gen/environment_p9.scn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const NODE_NAME := "EnvironmentP9"
const PARENT := "Props"
const ART_REVISION := "P9 R5-4 Existing Asset Environment Pass — 全村擴張 x2 targeted density & continuity（主 ≥ 3 件・satellite 2–4・杭は 2–5 本＋連れ・水邊は据え置き；ART_REVIEW）"
const LOD_SWITCH := 34.0
## 接頭辞 → kit
const KITS := {"st_": "street_kit", "mk_": "market_kit", "kr_": "kiri_kit", "sk_": "school_kit", "tk_": "tower_kit", "wk_": "waterside_kit",
	"gk_": "garden_kit", "rb_": "riverbank_kit", "gd_": "geidon_kit", "sz_": "suzu_kit"}
## veg_kit（LOD0..3 の命名）：pilot で使う下層・倒木・幼樹
const VEG := ["log_a", "shrub_a", "sasa_a", "fern_a", "young_broad_a", "young_broad_b", "young_sugi", "snag_a"]
## R5-4 で使ってよい id（audit の r54_role＝R5-4；生活 props・商い・Hero 固有・藁物は含めない）
const R54_IDS := ["gk_kei_tall", "gk_kei_mid", "gk_kei_low", "gk_kei_flat", "rb_bld_a", "rb_bld_b", "rb_bld_c", "rb_bld_d", "rb_bld_e",
	"rb_cob_a", "rb_cob_b", "rb_cob_c", "wk_reed", "wk_reed_s", "wk_sedge", "wk_iris", "shrub_a", "sasa_a", "fern_a", "log_a", "snag_a",
	"young_broad_a", "young_broad_b", "young_sugi", "gk_tobi_a", "gk_tobi_b", "gk_tobi_c", "gk_tobi_d", "gk_nobe_a", "gk_nobe_b", "gk_nobe_c",
	"rb_flag_a", "rb_flag_b", "gk_amaochi", "rb_curb_a", "rb_curb_b", "gk_bridge", "gk_yotsume", "rb_rail", "rb_shig", "rb_pile_a", "rb_pile_r", "st_shibagaki"]
## 柔らかい物（植物）：足元に MeadowP9 の草があってよい；それ以外（石・倒木・杭・垣）は足元の芯（60 %）に草株を入れない
const SOFT := ["wk_reed", "wk_reed_s", "wk_sedge", "wk_iris", "shrub_a", "sasa_a", "fern_a", "young_broad_a", "young_broad_b", "young_sugi", "snag_a"]
## 草の中に立ってよい固い物（垣・杭：草が足元を抜けるのが自然）
const GRASS_OK := ["st_shibagaki", "gk_yotsume", "rb_pile_a", "rb_pile_r"]
const FENCES := ["st_shibagaki", "gk_yotsume"]
const P10_PAD := 1.5
const ANCHOR_PAD := 1.2
## 碰撞を付けない（地面に貼る・低い・柔らかい植物）
const NO_COLLIDE := ["gk_tobi_a", "gk_tobi_b", "gk_tobi_c", "gk_tobi_d", "rb_cob_a", "rb_cob_b", "rb_cob_c", "rb_flag_a", "rb_flag_b",
	"wk_reed", "wk_reed_s", "wk_sedge", "wk_iris", "shrub_a", "sasa_a", "fern_a", "tk_rope", "kr_nawa", "gk_nobe_a", "gk_nobe_b", "gk_nobe_c"]
## 地面に貼る（接地＝足元の最高点に合わせない；最低点−少し）
const FLAT := ["gk_tobi_a", "gk_tobi_b", "gk_tobi_c", "gk_tobi_d", "rb_cob_a", "rb_cob_b", "rb_cob_c", "gk_nobe_a", "gk_nobe_b", "gk_nobe_c"]


## 空間ハッシュ（全村擴張で why／cell／bdist を速くする）
class RH:
	var cs := 8.0
	var cell := {}

	func add(obj: Variant, r: Rect2) -> void:
		for i in range(floori(r.position.x / cs), floori(r.end.x / cs) + 1):
			for j in range(floori(r.position.y / cs), floori(r.end.y / cs) + 1):
				var k := Vector2i(i, j)
				if not cell.has(k):
					cell[k] = []
				(cell[k] as Array).append(obj)

	func at(p: Vector2) -> Array:
		return cell.get(Vector2i(floori(p.x / cs), floori(p.y / cs)), [])

	func near(p: Vector2, r: float) -> Array:
		# 點（大きさ 0）で add した物だけに使う（重複なし）
		var out: Array = []
		for i in range(floori((p.x - r) / cs), floori((p.x + r) / cs) + 1):
			for j in range(floori((p.y - r) / cs), floori((p.y + r) / cs) + 1):
				out.append_array(cell.get(Vector2i(i, j), []))
		return out


static func mesh_path(id: String, lod: int) -> String:
	if id in VEG:
		return "res://assets/village_v2/veg_kit/mesh/%s_LOD%d.res" % [id, lod]
	return "res://assets/village_v2/%s/mesh/%s%s.res" % [KITS[id.substr(0, 3)], id, "_l1" if lod == 1 else ""]


static var _box_cache := {}


## 足元の箱（局部）：[hx, hz, 高さ, cz, cx]——各 kit の modules_blender.json の dims（唯讀）から
static func box(id: String) -> Array:
	if _box_cache.is_empty():
		for pre: String in KITS:
			var k: String = KITS[pre]
			var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/village_v2/%s/src/modules_blender.json" % k))
			var m: Variant = d["modules"]
			var items: Array = []
			if m is Dictionary:
				for n: String in m:
					items.append([n, m[n]])
			else:
				for e: Dictionary in m:
					items.append([e.get("name", ""), e])
			for e: Array in items:
				var v: Dictionary = e[1]
				if v.has("dims"):
					var dm: Array = v["dims"]
					_box_cache[String(e[0])] = [(float(dm[3]) - float(dm[0])) * 0.5, (float(dm[5]) - float(dm[2])) * 0.5, float(dm[4]),
						(float(dm[2]) + float(dm[5])) * 0.5, (float(dm[0]) + float(dm[3])) * 0.5]
		var vd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/village_v2/veg_kit/src/modules_blender.json"))
		for n: String in vd["trees"]:
			var a: Array = (vd["trees"][n]["lods"] as Array)[0]["aabb"]
			var mn: Array = a[0]
			var mx: Array = a[1]
			_box_cache[n] = [(float(mx[0]) - float(mn[0])) * 0.5, (float(mx[2]) - float(mn[2])) * 0.5, float(mx[1]),
				(float(mn[2]) + float(mx[2])) * 0.5, (float(mn[0]) + float(mx[0])) * 0.5]
	return _box_cache.get(id, [0.3, 0.3, 0.5, 0.0, 0.0])


static func yaw_to(d: Vector2) -> float:
	var n := d.normalized()
	return atan2(n.x, n.y)


static func local_to_world(it: Dictionary, l: Vector2) -> Vector2:
	var yaw: float = it["yaw"]
	var s: float = it.get("s", 1.0)
	var ax := Vector2(cos(yaw), -sin(yaw))
	var az := Vector2(sin(yaw), cos(yaw))
	return (it["p"] as Vector2) + (ax * l.x + az * l.y) * s


static func corners(it: Dictionary) -> PackedVector2Array:
	var b := box(String(it["id"]))
	var out := PackedVector2Array()
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		out.append(local_to_world(it, Vector2(float(b[4]) + s.x * float(b[0]), float(b[3]) + s.y * float(b[1]))))
	return out


## 見えている地表の最上面（地形・路面・P4 院子地面；可見最上面 build rule）
static func top_h(C: Dictionary, p: Vector2) -> float:
	var h := (C["S"] as RLib.TriSampler).h(p.x, p.y)
	for k: String in ["R", "Y"]:
		var v := (C[k] as RLib.TriSampler).h(p.x, p.y)
		if not is_nan(v):
			h = maxf(h, v)
	return h


static func ground(C: Dictionary, it: Dictionary) -> void:
	var hs: Array = [top_h(C, it["p"])]
	for q: Vector2 in corners(it):
		hs.append(top_h(C, q))
	# 箱物は最低点に合わせる（浮かない）；地面に貼る物は中央値−1 cm
	if String(it["id"]) in FLAT:
		hs.sort()
		it["y"] = float(hs[hs.size() / 2]) - 0.01
	else:
		it["y"] = hs.min()


static func relief(C: Dictionary, it: Dictionary) -> float:
	var hs: Array = [top_h(C, it["p"])]
	for q: Vector2 in corners(it):
		hs.append(top_h(C, q))
	return float(hs.max()) - float(hs.min())


static func item(C: Dictionary, id: String, p: Vector2, face: Vector2, tag: String, s := 1.0) -> Dictionary:
	var it := {"id": id, "p": p, "yaw": yaw_to(face), "tag": tag, "y": 0.0, "s": s}
	ground(C, it)
	return it


# ─────────────────────────── 文脈（實際の場景ノードを讀む） ───────────────────────────

static func context(v: Node3D) -> Dictionary:
	var C := {"S": RLib.terrain_sampler(v), "R": RLib.road_sampler(v), "Y": ML.yard_sampler(v)}
	var F := RLib.TriSampler.new()
	for fr in v.get_node("Districts").find_children("Frontage", "", true, false):
		for mi in fr.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh != null and g.visibility_range_begin <= 0.001:
				F.add(g.mesh.get_faces(), RLib.rel_xf(g, v))
	C["F"] = F
	var FS := RLib.TriSampler.new()
	var fm := v.get_node_or_null("Terrain/FarmlandTerrain") as MeshInstance3D
	if fm != null:
		FS.add(fm.mesh.get_faces(), RLib.rel_xf(fm, v))
	C["FS"] = FS
	var WS := RLib.TriSampler.new()
	for nm in ["Water/MainRiver", "Water/Canal", "Water/Streams/WestStream"]:
		var wg := v.get_node_or_null(nm) as MeshInstance3D
		if wg != null:
			WS.add(wg.mesh.get_faces(), RLib.rel_xf(wg, v))
	C["WS"] = WS
	var rb: Array = []
	for root_nm in ["Riverbank", "Roads/Bridges"]:
		var rn := v.get_node_or_null(root_nm)
		if rn == null:
			continue
		for mi in rn.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null or g.visibility_range_begin > 0.001:
				continue
			var a := RLib.rel_xf(g, v) * g.get_aabb()
			if a.size.x < 40.0 and a.size.z < 40.0:
				rb.append(Rect2(a.position.x, a.position.z, a.size.x, a.size.z).grow(0.4))
	C["rb"] = rb
	var bl: Array = []
	for b in v.get_node("Districts").find_children("B_*", "", true, false):
		var n3 := b as Node3D
		if n3 == null or not n3.has_meta("width_m"):
			continue
		var xf := RLib.rel_xf(n3, v)
		bl.append({"name": String(n3.name), "o": Vector2(xf.origin.x, xf.origin.z), "ax": Vector2(xf.basis.x.x, xf.basis.x.z).normalized(),
			"az": Vector2(xf.basis.z.x, xf.basis.z.z).normalized(), "w": float(n3.get_meta("width_m")), "d": float(n3.get_meta("depth_m")),
			"road": String(n3.get_meta("road", "")), "kind": String(n3.get_meta("kind", ""))})
	C["bld"] = bl
	# 封存 overlay の構件（R4 Hero 周邊など）と竹林・樹幹——置かない
	var blk: Array = []
	for nm: String in GC.SEALED_OVERLAYS + ["BambooP9"]:
		var ov := v.get_node_or_null("Vegetation/" + nm)
		if ov == null:
			continue
		for mi in ov.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null or g.visibility_range_begin > 0.001:
				continue
			var a := RLib.rel_xf(g, v) * g.get_aabb()
			if a.size.x < 30.0 and a.size.z < 30.0:
				blk.append(Rect2(a.position.x, a.position.z, a.size.x, a.size.z).grow(0.5 if String(g.name) == "Ground" else 0.8))
	C["block"] = blk
	var trees: Array = []
	var fnear := v.get_node_or_null("Vegetation/ForestP9/Near")
	if fnear != null:
		for ch in fnear.get_children():
			for t in ch.get_children():
				if t is Node3D and String(t.name).length() > 5 and String(t.name)[4] == "_":
					var tp := (t as Node3D).global_position
					trees.append(Vector2(tp.x, tp.z))
	C["trees"] = trees
	# P10（Props/* の既存子＝市集・主街・市集西…）：實ノードの足元（+1.5 m）と NPC anchors（+1.2 m）＝occupancy（P10 優先、繞開して銜接）
	var pr: Array = []
	var shiba: Array = []
	var props := v.get_node_or_null("Props")
	if props != null:
		for ch in props.get_children():
			if String(ch.name) == NODE_NAME:
				continue
			for mi in ch.find_children("*", "MeshInstance3D", true, false):
				var g := mi as MeshInstance3D
				if g.mesh == null or g.visibility_range_begin > 0.001:
					continue
				var a := RLib.rel_xf(g, v) * g.get_aabb()
				pr.append(Rect2(a.position.x, a.position.z, a.size.x, a.size.z).grow(P10_PAD))
			for m in ch.find_children("*", "Marker3D", true, false):
				var q := (m as Node3D).global_position
				pr.append(Rect2(Vector2(q.x, q.z), Vector2.ZERO).grow(ANCHOR_PAD))
			# P10 の柴垣（田の縁）：R5-4 は同じ物を近くに重ねない
			for mi in ch.find_children("*", "MeshInstance3D", true, false):
				var g := mi as MeshInstance3D
				if g.mesh != null and String(g.mesh.resource_path).contains("shibagaki") and g.visibility_range_begin <= 0.001:
					var q3 := RLib.rel_xf(g, v).origin
					shiba.append(Vector2(q3.x, q3.z))
	C["p10"] = pr
	C["p10_shiba"] = shiba
	var LY: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var roads := {}
	for r: Dictionary in LY["roads"] + LY["lanes"]:
		var pts := PackedVector2Array()
		for q: Array in r["pts"]:
			pts.append(Vector2(float(q[0]), float(q[1])))
		roads[String(r["name"])] = {"pts": pts, "hw": float(r["half_w"])}
	C["roads"] = roads
	index(C)
	return C


static func index(C: Dictionary) -> void:
	for key: String in ["rb", "block", "p10"]:
		var h := RH.new()
		for r: Rect2 in C[key]:
			h.add(r, r)
		C["h_" + key] = h
	var ht := RH.new()
	ht.cs = 4.0
	for t: Vector2 in C["trees"]:
		ht.add(t, Rect2(t - Vector2(1.5, 1.5), Vector2(3, 3)))
	C["h_trees"] = ht
	var hb := RH.new()
	for b: Dictionary in C["bld"]:
		hb.add(b, Rect2((b["o"] as Vector2) - Vector2(31, 31), Vector2(62, 62)))
	C["h_bld"] = hb


static func _rect_hit(C: Dictionary, key: String, q: Vector2) -> bool:
	if C.has("h_" + key):
		for r: Rect2 in (C["h_" + key] as RH).at(q):
			if r.has_point(q):
				return true
		return false
	return (C[key] as Array).any(func(r: Rect2) -> bool: return r.has_point(q))


static func obb_d(b: Dictionary, p: Vector2) -> float:
	var d := p - (b["o"] as Vector2)
	var lx := absf(d.dot(b["ax"])) - float(b["w"]) * 0.5
	var lz := absf(d.dot(b["az"])) - float(b["d"]) * 0.5
	if lx <= 0.0 and lz <= 0.0:
		return maxf(lx, lz)
	return Vector2(maxf(lx, 0.0), maxf(lz, 0.0)).length()


static func bdist(C: Dictionary, p: Vector2) -> float:
	var best := 99.0
	for b: Dictionary in ((C["h_bld"] as RH).at(p) if C.has("h_bld") else C["bld"]):
		if (b["o"] as Vector2).distance_to(p) < 30.0:
			best = minf(best, obb_d(b, p))
	return best


static func in_water(C: Dictionary, q: Vector2, margin := 0.6) -> bool:
	var WS: RLib.TriSampler = C["WS"]
	var S: RLib.TriSampler = C["S"]
	for o: Vector2 in [Vector2.ZERO, Vector2(margin, 0), Vector2(-margin, 0), Vector2(0, margin), Vector2(0, -margin)]:
		var p := q + o
		var wh := WS.h(p.x, p.y)
		if not is_nan(wh) and wh > S.h(p.x, p.y) - 0.02:
			return true
	return false


## 1 點の分類（survey と why の共通）："" ＝空き
static func cell(C: Dictionary, q: Vector2) -> String:
	if is_nan((C["S"] as RLib.TriSampler).h(q.x, q.y)):
		return "x"
	if not is_nan((C["R"] as RLib.TriSampler).h(q.x, q.y)):
		return "R"
	if not is_nan((C["F"] as RLib.TriSampler).h(q.x, q.y)):
		return "F"
	if bdist(C, q) < 0.3:
		return "B"
	if in_water(C, q, 0.0):
		return "W"
	if _rect_hit(C, "rb", q):
		return "w"
	if not is_nan((C["FS"] as RLib.TriSampler).h(q.x, q.y)):
		return "A"
	if _rect_hit(C, "block", q):
		return "S"
	if _rect_hit(C, "p10", q):
		return "P"
	for t: Vector2 in ((C["h_trees"] as RH).at(q) if C.has("h_trees") else C["trees"]):
		if t.distance_to(q) < 0.9:
			return "T"
	return ""


static func poly_samples(poly: PackedVector2Array, step := 0.25) -> PackedVector2Array:
	var out := PackedVector2Array()
	var a := poly[0]
	var bx := poly[1] - poly[0]
	var bz := poly[3] - poly[0]
	var nx := maxi(1, int(ceil(bx.length() / step)))
	var nz := maxi(1, int(ceil(bz.length() / step)))
	for i in nx + 1:
		for j in nz + 1:
			out.append(a + bx * (float(i) / nx) + bz * (float(j) / nz))
	return out


## MeadowP9 の規劃株（R5-3 封存の同 seed 再計算）を 1 m セルの集合に（固い物の足元の芯の判定用）
static func set_meadow(C: Dictionary, pts: PackedVector2Array) -> void:
	var g := {}
	for q in pts:
		g[Vector2i(floori(q.x * 2.0), floori(q.y * 2.0))] = int(g.get(Vector2i(floori(q.x * 2.0), floori(q.y * 2.0)), 0)) + 1
	C["meadow"] = g


## 足元の芯（60 %）に入る MeadowP9 の株數（0.5 m セル單位の近似）
static func grass_in_core(C: Dictionary, it: Dictionary) -> int:
	if not C.has("meadow") or String(it["id"]) in SOFT or String(it["id"]) in GRASS_OK:
		return 0
	var g: Dictionary = C["meadow"]
	var cen := (it["p"] as Vector2)
	var poly := corners(it)
	var core := PackedVector2Array()
	var b := box(String(it["id"]))
	var mid := local_to_world(it, Vector2(float(b[4]), float(b[3])))
	for q in poly:
		core.append(mid + (q - mid) * 0.6)
	var n := 0
	for q in poly_samples(core, 0.25):
		n += int(g.get(Vector2i(floori(q.x * 2.0), floori(q.y * 2.0)), 0))
	return n


## 置けるか："" ＝可。足元が地形外・路面・店先帯・建物・水（+0.6 m）・P7 構件／橋・田・封存構件・P10・樹幹・他の物に入らない
static func why(C: Dictionary, it: Dictionary, items: Array) -> String:
	var poly := corners(it)
	var wet := String(it["id"]) in WETS
	var samp := poly
	if wet:
		# 水草は葉が水面・岸に掛かってよい：足元の芯（55 %）だけ判定、水の余白 0.25 m
		var b := box(String(it["id"]))
		var mid := local_to_world(it, Vector2(float(b[4]), float(b[3])))
		samp = PackedVector2Array()
		for q in poly:
			samp.append(mid + (q - mid) * 0.55)
	for q in poly_samples(samp):
		var c := cell(C, q)
		if c != "":
			return {"x": "terrain", "R": "road", "F": "frontage", "B": "building", "W": "water", "w": "p7", "A": "farm", "S": "sealed", "P": "p10", "T": "trunk"}[c]
		if in_water(C, q, 0.25 if wet else 0.6):
			return "water"
	var soft := String(it["id"]) in SOFT
	for o: Dictionary in items:
		if (o["p"] as Vector2).distance_to(it["p"]) < 8.0:
			# 植物どうしは葉が重なってよい（芯 55 % どうしで判定）；固い物が絡むときは足元全体
			var both := soft and String(o["id"]) in SOFT
			var pa := core(it, 0.55) if both else poly
			var pb := core(o, 0.55) if both else corners(o)
			if not Geometry2D.intersect_polygons(pa, pb).is_empty():
				return "overlap:" + String(o["id"])
	if grass_in_core(C, it) > 0:
		return "meadow"
	return ""


static func core(it: Dictionary, f: float) -> PackedVector2Array:
	var b := box(String(it["id"]))
	var mid := local_to_world(it, Vector2(float(b[4]), float(b[3])))
	var out := PackedVector2Array()
	for q in corners(it):
		out.append(mid + (q - mid) * f)
	return out


## c のまわり（0.4 m 刻みの輪、16 方向、rmax まで）で、空き・起伏 ≤ rel の置き場所
static func spot(C: Dictionary, items: Array, id: String, c: Vector2, face: Vector2, tag: String, rmax := 2.0, rel := 0.15, s := 1.0) -> Dictionary:
	var r := 0.0
	while r <= rmax:
		var n := 1 if r == 0.0 else 16
		for k in n:
			var a := TAU * k / 16.0
			var it := item(C, id, c + Vector2(cos(a), sin(a)) * r, face, tag, s)
			if relief(C, it) > rel or why(C, it, items) != "":
				continue
			items.append(it)
			return it
		r += 0.4
	var it0 := item(C, id, c, face, tag, s)
	(C["dropped"] as Array).append("%s@(%.1f,%.1f) %s [%s]" % [id, c.x, c.y, why(C, it0, items), tag])
	return {}


# ─────────────────────────── 全村擴張：距離場（MeadowP9 fields と同じ 1 m EXT 格子） ───────────────────────────
## 使用者裁定（2026-10-05）：n1＝ART_APPROVED_FOR_EXPANSION。語彙は n1 のまま（新資產なし）。
##   主 cluster → secondary／satellite → 單件の過渡 → 留白（固定數にしない、地形・建物・路・水岸・林緣・P10 で決まる）。
##   「展示樣板」にしない：同じ組成の繰り返し・石の陳列・倒木＋灌木の固定セット・杭＋柴垣の固定セット・等間隔を gate で禁止。

## 各類の距離場：water→W（水面）・farm→A（田面）・forest→T（樹幹）・edge→B（建物）・open→X（置けない所＝MeadowP9 の blk）
const CLS := ["water", "farm", "forest", "edge", "open"]
const FIELD := {"water": "W", "farm": "A", "forest": "T", "edge": "B", "open": "X"}
## 錨どうしの基準間隔（m）：各錨ごとに ×0.8–1.6 で揺らす（等距にしない）
const SPACING := {"water": 22.0, "farm": 32.0, "forest": 21.0, "edge": 26.0, "open": 22.0}
## 留白（omission）：低周波 noise がこの値未満の所には錨を置かない（何もない長い区間を残す）
const OMIT := {"water": 0.46, "farm": 0.55, "forest": 0.45, "edge": 0.38, "open": 0.46}
const SEED := 5407

const ROCK_BIG := ["gk_kei_tall", "gk_kei_mid", "rb_bld_a", "rb_bld_b"]
const ROCK_MID := ["gk_kei_mid", "gk_kei_low", "rb_bld_c", "rb_bld_d", "rb_bld_a"]
const ROCK_LOW := ["gk_kei_low", "gk_kei_flat", "rb_bld_e", "rb_bld_d"]
const COB := ["rb_cob_a", "rb_cob_b", "rb_cob_c"]
const TOBI := ["gk_tobi_a", "gk_tobi_b", "gk_tobi_c"]
const SAPL := ["young_broad_a", "young_broad_b", "young_sugi"]
const REED := ["wk_reed", "wk_reed_s"]
const STAKE := ["rb_pile_a", "rb_pile_r"]
const ROCKS := ["gk_kei_tall", "gk_kei_mid", "gk_kei_low", "gk_kei_flat", "rb_bld_a", "rb_bld_b", "rb_bld_c", "rb_bld_d", "rb_bld_e"]
const WETS := ["wk_reed", "wk_reed_s", "wk_sedge", "wk_iris"]

## member：ids／p（出る確率）／n（個數）／band（類の距離場での目標距離、x<0＝無指定）／t（錨から等高線沿いのずれ）／
##   s（縮尺）／sink（石の埋まり＝高さ比）／mode（pt・line＝等高線沿いの断續線・trail＝距離場を登る踏み跡）／yaw（edge・rand・away）
static func m(ids: Array, p: float, n: Vector2i, band: Vector2, t: Vector2, s := Vector2(0.85, 1.1), sink := Vector2.ZERO, mode := "pt", yaw := "rand") -> Dictionary:
	return {"ids": ids, "p": p, "n": n, "band": band, "t": t, "s": s, "sink": sink, "mode": mode, "yaw": yaw}


## 主 event の型（[名前, 重み, members]）——一つの event は一つの型だけ＝全部の資產を一度に出さない
## x2（使用者 2026-10-05：x1 は稀すぎ）：主は 3 件以上で 10–25 m から「環境の群」に読める；杭は必ず 2–5 本＋連れ（垣・石・草・灌木）
static func recipes(cls: String) -> Array:
	match cls:
		"water":
			# 水邊は密度を上げない（P7＋MeadowP9 が主層）：河原石・枯木・少量の蘆／菅・岸の灌木
			return [
				["reed_bed", 4.0, [m(REED, 1.0, Vector2i(3, 5), Vector2(1.0, 1.9), Vector2(0, 1.0), Vector2(0.6, 1.05), Vector2.ZERO, "line", "rand"),
					m(["wk_sedge"], 0.6, Vector2i(1, 2), Vector2(0.8, 2.3), Vector2(0.5, 4.5)), m(["wk_iris"], 0.3, Vector2i(1, 2), Vector2(0.7, 1.5), Vector2(1, 4))]],
				["stone_shore", 2.0, [m(ROCK_MID + ROCK_LOW, 1.0, Vector2i(1, 2), Vector2(1.0, 2.8), Vector2(0, 2.6), Vector2(0.5, 1.1), Vector2(0.28, 0.42)),
					m(COB, 0.7, Vector2i(1, 2), Vector2(0.9, 2.2), Vector2(0.4, 3.2), Vector2(0.7, 1.0)), m(["wk_sedge"], 0.5, Vector2i(1, 1), Vector2(0.8, 2.0), Vector2(1.2, 3.5))]],
				["dry_transition", 2.0, [m(["shrub_a"], 1.0, Vector2i(1, 1), Vector2(3.4, 6.0), Vector2(0, 2), Vector2(0.75, 1.05)),
					m(ROCK_LOW, 0.4, Vector2i(1, 1), Vector2(2.4, 4.2), Vector2(0.5, 2.5), Vector2(0.55, 0.9), Vector2(0.25, 0.4)),
					m(["wk_sedge"], 0.5, Vector2i(1, 2), Vector2(1.0, 2.4), Vector2(0, 3))]],
				["iris_patch", 1.0, [m(["wk_iris"], 1.0, Vector2i(1, 2), Vector2(0.7, 1.4), Vector2(0, 1.6)), m(["wk_sedge"], 1.0, Vector2i(1, 1), Vector2(0.9, 2.0), Vector2(0.6, 2.4))]],
			]
		"farm":
			# 田の縁：杭 2–5 本の不等間隔の線＋連れ（短い柴垣・拾い石・菅・灌木）；satellite も同じ境界の続き（間に空白）
			return [
				["boundary", 3.5, [m(["fence"], 1.0, Vector2i(3, 5), Vector2(0.9, 1.4), Vector2(0, 0.6), Vector2(0.85, 1.0), Vector2(0.05, 0.12), "line", "edge"),
					m(ROCK_LOW + COB, 0.9, Vector2i(1, 2), Vector2(1.4, 2.6), Vector2(0.5, 3.0), Vector2(0.45, 0.8), Vector2(0.12, 0.3)),
					m(["wk_sedge", "wk_reed_s"], 0.85, Vector2i(1, 2), Vector2(1.0, 2.2), Vector2(0.3, 3.0))]],
				["stone_pile", 2.0, [m(ROCK_LOW, 1.0, Vector2i(1, 2), Vector2(1.5, 3.0), Vector2(0, 1.0), Vector2(0.45, 0.75), Vector2(0.15, 0.3)),
					m(COB, 0.9, Vector2i(1, 2), Vector2(1.3, 2.8), Vector2(0.4, 1.6), Vector2(0.6, 0.9)), m(["wk_sedge"], 0.7, Vector2i(1, 2), Vector2(1.0, 2.4), Vector2(1.5, 3.5))]],
				["sedge_edge", 2.0, [m(["wk_sedge"], 1.0, Vector2i(2, 3), Vector2(0.9, 2.2), Vector2(0, 4.5)), m(["wk_reed_s"], 0.5, Vector2i(1, 1), Vector2(1.0, 2.4), Vector2(1, 4)),
					m(["shrub_a"], 0.5, Vector2i(1, 1), Vector2(3.0, 6.0), Vector2(0, 3), Vector2(0.7, 0.95))]],
				["shrub_corner", 1.0, [m(["shrub_a"], 1.0, Vector2i(1, 2), Vector2(3.0, 6.0), Vector2(0, 2.5), Vector2(0.75, 1.05)),
					m(["gk_kei_flat"], 0.6, Vector2i(1, 1), Vector2(2.0, 4.0), Vector2(0.8, 2.5), Vector2(0.6, 0.85), Vector2(0.1, 0.25)),
					m(["wk_sedge"], 0.6, Vector2i(1, 1), Vector2(1.0, 2.4), Vector2(1.0, 3.5))]],
			]
		"forest":
			# 林の縁の事件：倒木／枯立木／石と羊歯／下木／笹原——各事件は一部の要素だけ
			return [
				["deadwood", 3.0, [m(["log_a"], 1.0, Vector2i(1, 1), Vector2(1.6, 4.5), Vector2(0, 1), Vector2(0.75, 1.05), Vector2.ZERO, "pt", "edge"),
					m(["fern_a"], 0.6, Vector2i(1, 2), Vector2(1.2, 3.5), Vector2(1.0, 3.0), Vector2(1.1, 1.45)),
					m(["sasa_a"], 0.45, Vector2i(1, 1), Vector2(1.2, 3.5), Vector2(1.5, 3.5), Vector2(1.0, 1.3)),
					m(ROCK_LOW, 0.3, Vector2i(1, 1), Vector2(1.8, 4.5), Vector2(1.5, 3.5), Vector2(0.5, 0.85), Vector2(0.15, 0.35))]],
				["snag", 2.0, [m(["snag_a"], 1.0, Vector2i(1, 1), Vector2(1.6, 4.0), Vector2(0, 1), Vector2(0.7, 0.95)),
					m(["sasa_a"], 0.7, Vector2i(1, 2), Vector2(1.2, 3.5), Vector2(0.8, 3.0), Vector2(1.0, 1.3)),
					m(["fern_a"], 0.45, Vector2i(1, 1), Vector2(1.2, 3.5), Vector2(1.0, 3.0), Vector2(1.1, 1.45)),
					m(ROCK_LOW, 0.3, Vector2i(1, 1), Vector2(1.8, 4.5), Vector2(1.0, 3.0), Vector2(0.5, 0.85), Vector2(0.15, 0.35))]],
				["stone_fern", 2.0, [m(ROCK_MID, 1.0, Vector2i(1, 2), Vector2(2.0, 5.0), Vector2(0, 2), Vector2(0.6, 1.0), Vector2(0.15, 0.35)),
					m(["fern_a"], 1.0, Vector2i(1, 2), Vector2(1.2, 4.0), Vector2(0.6, 2.6), Vector2(1.1, 1.45)),
					m(["sasa_a"], 0.35, Vector2i(1, 1), Vector2(1.2, 4.0), Vector2(1.0, 3.0), Vector2(1.0, 1.3))]],
				["under", 2.0, [m(["shrub_a"], 1.0, Vector2i(2, 3), Vector2(2.0, 5.5), Vector2(0, 3), Vector2(0.65, 1.1)),
					m(SAPL, 0.6, Vector2i(1, 1), Vector2(2.4, 5.0), Vector2(1, 4), Vector2(0.65, 0.9)),
					m(["sasa_a"], 0.5, Vector2i(1, 1), Vector2(1.5, 4.0), Vector2(0.8, 3.0), Vector2(1.0, 1.3))]],
				["sasa_patch", 2.0, [m(["sasa_a"], 1.0, Vector2i(2, 3), Vector2(1.2, 4.0), Vector2(0, 3.2), Vector2(1.0, 1.3)),
					m(["fern_a"], 0.5, Vector2i(1, 1), Vector2(1.2, 3.5), Vector2(1, 3.5), Vector2(1.1, 1.45)),
					m(["shrub_a"], 0.35, Vector2i(1, 1), Vector2(2.0, 5.0), Vector2(1, 3), Vector2(0.65, 1.0))]],
			]
		"edge":
			# 人工 → 半人工 → 自然：垣の切れ端＋杭の続き＋後ろの灌木／杭 2–4 本の線＋灌木・幼樹／踏み石＋灌木／幼樹と笹／灌木
			return [
				["fence_frag", 0.7, [m(["gk_yotsume"], 1.0, Vector2i(1, 2), Vector2(4.5, 6.5), Vector2(0, 0.5), Vector2(0.9, 1.0), Vector2.ZERO, "line", "edge"),
					m(STAKE, 0.7, Vector2i(2, 3), Vector2(4.5, 6.5), Vector2(1.6, 3.2), Vector2(0.85, 1.0), Vector2(0.05, 0.12), "line", "edge"),
					m(["shrub_a"], 0.95, Vector2i(1, 2), Vector2(5.8, 8.0), Vector2(0, 2.5), Vector2(0.7, 1.05)),
					m(ROCK_LOW, 0.3, Vector2i(1, 1), Vector2(5.0, 8.0), Vector2(1.0, 3.0), Vector2(0.55, 0.85), Vector2(0.15, 0.3))]],
				["stake_shrub", 2.0, [m(STAKE, 1.0, Vector2i(2, 4), Vector2(4.5, 7.0), Vector2(0, 0.5), Vector2(0.85, 1.0), Vector2(0.05, 0.12), "line", "edge"),
					m(["shrub_a"], 1.0, Vector2i(1, 2), Vector2(5.6, 8.5), Vector2(0, 2.5), Vector2(0.7, 1.05)),
					m(SAPL, 0.5, Vector2i(1, 1), Vector2(8.0, 13.0), Vector2(0, 3), Vector2(0.65, 0.95))]],
				["stepping_out", 1.2, [m(TOBI, 1.0, Vector2i(3, 4), Vector2(3.5, 10.0), Vector2(0, 0), Vector2(0.95, 1.1), Vector2.ZERO, "trail", "away"),
					m(["shrub_a"], 1.0, Vector2i(1, 1), Vector2(6.0, 10.0), Vector2(1.6, 3.2), Vector2(0.75, 1.0)),
					m(ROCK_LOW, 0.4, Vector2i(1, 1), Vector2(5.0, 9.0), Vector2(1.5, 3.0), Vector2(0.55, 0.85), Vector2(0.15, 0.3))]],
				["tree", 2.0, [m(SAPL, 1.0, Vector2i(1, 2), Vector2(9.0, 17.0), Vector2(0, 2.5), Vector2(0.7, 1.05)),
					m(["sasa_a"], 0.6, Vector2i(1, 1), Vector2(8.0, 15.0), Vector2(0.8, 2.5), Vector2(1.0, 1.25)),
					m(["shrub_a"], 0.5, Vector2i(1, 1), Vector2(7.0, 13.0), Vector2(1.0, 3.0), Vector2(0.7, 1.0))]],
				["shrub_pair", 2.0, [m(["shrub_a"], 1.0, Vector2i(1, 2), Vector2(6.0, 12.0), Vector2(0, 3), Vector2(0.75, 1.05)),
					m(["gk_kei_low"], 0.5, Vector2i(1, 1), Vector2(6.0, 11.0), Vector2(1, 3), Vector2(0.6, 0.9), Vector2(0.15, 0.3)),
					m(["sasa_a"], 0.5, Vector2i(1, 1), Vector2(6.0, 11.0), Vector2(0.5, 2.5), Vector2(1.0, 1.25))]],
			]
		"open":
			# 大きな空き地の縁：景石＋灌木＋幼樹の主、周りに小さく単純な satellite 2–4（中央は抜く）
			return [
				["grove_edge", 2.0, [m(ROCK_MID, 1.0, Vector2i(1, 1), Vector2(1.2, 3.5), Vector2(0, 1), Vector2(0.6, 1.0), Vector2(0.25, 0.42)),
					m(["shrub_a"], 1.0, Vector2i(1, 2), Vector2(1.2, 4.0), Vector2(0.8, 2.6), Vector2(0.6, 1.0)),
					m(SAPL, 0.85, Vector2i(1, 1), Vector2(2.0, 5.5), Vector2(1.0, 3.0), Vector2(0.65, 0.95))]],
				["rock_group", 1.6, [m(ROCK_BIG, 0.6, Vector2i(1, 1), Vector2(1.2, 3.5), Vector2(0, 1), Vector2(0.7, 1.05), Vector2(0.25, 0.42)),
					m(ROCK_MID, 1.0, Vector2i(1, 2), Vector2(1.2, 3.5), Vector2(0.8, 2.4), Vector2(0.55, 1.0), Vector2(0.25, 0.42)),
					m(ROCK_LOW, 0.7, Vector2i(1, 2), Vector2(1.0, 3.5), Vector2(0.6, 3.0), Vector2(0.5, 0.85), Vector2(0.25, 0.42)),
					m(["shrub_a"], 0.6, Vector2i(1, 1), Vector2(1.0, 3.0), Vector2(0.5, 2.5), Vector2(0.55, 0.9))]],
				["low_shrub", 2.0, [m(["shrub_a"], 1.0, Vector2i(2, 3), Vector2(1.6, 5.0), Vector2(0, 2.6), Vector2(0.5, 1.0)),
					m(ROCK_LOW, 0.5, Vector2i(1, 1), Vector2(1.6, 5.0), Vector2(1, 3), Vector2(0.5, 0.8), Vector2(0.15, 0.35)),
					m(["sasa_a"], 0.4, Vector2i(1, 1), Vector2(1.6, 5.0), Vector2(0.8, 2.5), Vector2(1.0, 1.25))]],
				["sapling", 2.0, [m(SAPL, 1.0, Vector2i(1, 1), Vector2(2.6, 6.5), Vector2(0, 1), Vector2(0.65, 0.95)), m(["sasa_a"], 0.6, Vector2i(1, 1), Vector2(1.6, 5.0), Vector2(0.8, 2.5), Vector2(1.0, 1.25)),
					m(ROCK_LOW, 0.5, Vector2i(1, 1), Vector2(1.6, 5.0), Vector2(1, 3), Vector2(0.5, 0.8), Vector2(0.15, 0.35))]],
				["exposed_stone", 1.5, [m(["gk_kei_flat", "gk_nobe_a"] + COB, 1.0, Vector2i(2, 3), Vector2(1.2, 4.0), Vector2(0, 2.6), Vector2(0.75, 1.0), Vector2(0.1, 0.25)),
					m(["shrub_a"], 0.5, Vector2i(1, 1), Vector2(1.2, 4.0), Vector2(1, 3), Vector2(0.55, 0.9))]],
				["deadwood", 1.0, [m(["log_a"], 1.0, Vector2i(1, 1), Vector2(1.8, 4.5), Vector2(0, 1), Vector2(0.6, 0.85), Vector2.ZERO, "pt", "edge"),
					m(["fern_a"], 0.5, Vector2i(1, 1), Vector2(1.6, 4.0), Vector2(0.8, 2.4), Vector2(1.1, 1.45)), m(ROCK_LOW, 0.5, Vector2i(1, 1), Vector2(1.6, 4.0), Vector2(1, 3), Vector2(0.5, 0.8), Vector2(0.15, 0.35))]],
			]
	return []


## satellite（主の脇の小さく単純な塊：1–2 件、組成は主より少ない）
static func sat_recipes(cls: String) -> Array:
	match cls:
		"water":
			return [[m(REED, 1.0, Vector2i(2, 3), Vector2(1.0, 1.9), Vector2(0, 0.8), Vector2(0.6, 1.0), Vector2.ZERO, "line", "rand")],
				[m(["wk_sedge"], 1.0, Vector2i(1, 1), Vector2(0.8, 2.2), Vector2(0, 1)), m(["wk_iris"], 0.5, Vector2i(1, 1), Vector2(0.7, 1.5), Vector2(0.5, 1.5))],
				[m(ROCK_LOW, 1.0, Vector2i(1, 1), Vector2(1.0, 2.8), Vector2(0, 1), Vector2(0.45, 0.85), Vector2(0.28, 0.42))],
				[m(COB, 1.0, Vector2i(1, 2), Vector2(0.9, 2.2), Vector2(0, 1.6), Vector2(0.6, 0.95))],
				[m(["shrub_a"], 1.0, Vector2i(1, 1), Vector2(3.0, 6.0), Vector2(0, 1), Vector2(0.6, 0.9))]]
		"farm":
			# 境界の続き（杭 2–3＋菅）／拾い石／菅と灌木
			return [[m(STAKE, 1.0, Vector2i(2, 3), Vector2(0.9, 1.4), Vector2(0, 0.5), Vector2(0.85, 1.0), Vector2(0.05, 0.12), "line", "edge"),
					m(["wk_sedge", "wk_reed_s"], 1.0, Vector2i(1, 2), Vector2(1.0, 2.2), Vector2(0.3, 1.8))],
				[m(ROCK_LOW, 1.0, Vector2i(1, 1), Vector2(1.5, 3.0), Vector2(0, 1), Vector2(0.45, 0.7), Vector2(0.15, 0.3)), m(COB, 0.6, Vector2i(1, 1), Vector2(1.3, 2.8), Vector2(0.4, 1.4), Vector2(0.6, 0.9))],
				[m(["wk_sedge"], 1.0, Vector2i(1, 2), Vector2(0.9, 2.4), Vector2(0, 2)), m(["shrub_a"], 0.4, Vector2i(1, 1), Vector2(3.0, 6.0), Vector2(0, 2), Vector2(0.6, 0.9))]]
		"forest":
			return [[m(["fern_a"], 1.0, Vector2i(1, 2), Vector2(1.2, 4.0), Vector2(0, 1.6), Vector2(1.1, 1.45))],
				[m(["sasa_a"], 1.0, Vector2i(1, 1), Vector2(1.2, 4.0), Vector2(0, 1), Vector2(1.0, 1.3)), m(["fern_a"], 0.4, Vector2i(1, 1), Vector2(1.2, 4.0), Vector2(0.5, 1.5), Vector2(1.1, 1.45))],
				[m(ROCK_LOW, 1.0, Vector2i(1, 1), Vector2(1.6, 4.5), Vector2(0, 1), Vector2(0.5, 0.85), Vector2(0.15, 0.35)), m(["fern_a"], 0.5, Vector2i(1, 1), Vector2(1.2, 4.0), Vector2(0.5, 1.5), Vector2(1.1, 1.45))],
				[m(["shrub_a"], 1.0, Vector2i(1, 1), Vector2(2.0, 5.0), Vector2(0, 1), Vector2(0.7, 1.0))],
				[m(SAPL, 1.0, Vector2i(1, 1), Vector2(2.4, 5.0), Vector2(0, 1), Vector2(0.6, 0.85))],
				[m(["log_a"], 1.0, Vector2i(1, 1), Vector2(1.6, 4.5), Vector2(0, 1), Vector2(0.65, 0.9), Vector2.ZERO, "pt", "edge")]]
		"edge":
			return [[m(["shrub_a"], 1.0, Vector2i(1, 1), Vector2(6.0, 12.0), Vector2(0, 1), Vector2(0.7, 1.0)), m(ROCK_LOW, 0.5, Vector2i(1, 1), Vector2(6.0, 12.0), Vector2(0.5, 1.5), Vector2(0.55, 0.85), Vector2(0.15, 0.3))],
				[m(SAPL, 1.0, Vector2i(1, 1), Vector2(9.0, 16.0), Vector2(0, 1), Vector2(0.6, 0.9)), m(["sasa_a"], 0.5, Vector2i(1, 1), Vector2(8.0, 15.0), Vector2(0.5, 1.5), Vector2(1.0, 1.25))],
				[m(STAKE, 1.0, Vector2i(2, 3), Vector2(4.5, 8.0), Vector2(0, 0.5), Vector2(0.85, 1.0), Vector2(0.05, 0.12), "line", "edge"),
					m(["shrub_a"], 1.0, Vector2i(1, 1), Vector2(5.5, 9.0), Vector2(0, 1.5), Vector2(0.65, 0.95))],
				[m(["sasa_a"], 1.0, Vector2i(1, 2), Vector2(7.0, 14.0), Vector2(0, 1.5), Vector2(1.0, 1.25)), m(["fern_a"], 0.3, Vector2i(1, 1), Vector2(7.0, 14.0), Vector2(0.5, 1.5), Vector2(1.1, 1.45))]]
		"open":
			# 主より小さく単純：単灌木＋小石／幼樹＋飛石／枯木／小石／笹
			return [[m(["shrub_a"], 1.0, Vector2i(1, 1), Vector2(1.6, 5.0), Vector2(0, 1), Vector2(0.55, 0.9)), m(ROCK_LOW, 0.6, Vector2i(1, 1), Vector2(1.6, 5.0), Vector2(0.5, 1.5), Vector2(0.5, 0.8), Vector2(0.2, 0.4))],
				[m(SAPL, 1.0, Vector2i(1, 1), Vector2(2.0, 6.0), Vector2(0, 1), Vector2(0.6, 0.85)), m(TOBI, 0.6, Vector2i(1, 2), Vector2(1.5, 5.0), Vector2(0.8, 2.0), Vector2(0.95, 1.1))],
				[m(["log_a"], 1.0, Vector2i(1, 1), Vector2(1.6, 5.0), Vector2(0, 1), Vector2(0.6, 0.8), Vector2.ZERO, "pt", "edge")],
				[m(ROCK_LOW, 1.0, Vector2i(1, 1), Vector2(1.6, 5.5), Vector2(0, 1), Vector2(0.5, 0.85), Vector2(0.2, 0.4)), m(COB, 0.5, Vector2i(1, 1), Vector2(1.6, 5.5), Vector2(0.5, 1.5), Vector2(0.7, 1.0))],
				[m(["sasa_a"], 1.0, Vector2i(1, 2), Vector2(1.6, 5.0), Vector2(0, 1.2), Vector2(1.0, 1.25))]]
	return []


## 單件の過渡（杭は使わない＝杭が一本だけ立つ debug prop を作らない）
static func iso_recipes(cls: String) -> Array:
	match cls:
		"water":
			return [m(["wk_reed_s"], 1.0, Vector2i(1, 1), Vector2(1.0, 1.9), Vector2(0, 1), Vector2(0.6, 0.95)), m(["wk_sedge"], 1.0, Vector2i(1, 1), Vector2(0.8, 2.2), Vector2(0, 1)),
				m(ROCK_LOW, 1.0, Vector2i(1, 1), Vector2(1.0, 2.8), Vector2(0, 1), Vector2(0.45, 0.85), Vector2(0.28, 0.42))]
		"farm":
			return [m(["wk_sedge"], 1.0, Vector2i(1, 1), Vector2(0.9, 2.4), Vector2(0, 1)), m(ROCK_LOW, 1.0, Vector2i(1, 1), Vector2(1.5, 3.0), Vector2(0, 1), Vector2(0.45, 0.7), Vector2(0.15, 0.3)),
				m(["shrub_a"], 1.0, Vector2i(1, 1), Vector2(3.0, 6.0), Vector2(0, 1), Vector2(0.6, 0.9))]
		"forest":
			return [m(["fern_a"], 1.0, Vector2i(1, 1), Vector2(1.2, 4.0), Vector2(0, 1), Vector2(1.1, 1.45)), m(["sasa_a"], 1.0, Vector2i(1, 1), Vector2(1.2, 4.0), Vector2(0, 1), Vector2(1.0, 1.3)),
				m(ROCK_LOW, 1.0, Vector2i(1, 1), Vector2(1.6, 4.5), Vector2(0, 1), Vector2(0.5, 0.85), Vector2(0.15, 0.35)), m(SAPL, 1.0, Vector2i(1, 1), Vector2(2.4, 5.0), Vector2(0, 1), Vector2(0.6, 0.85)),
				m(["log_a"], 1.0, Vector2i(1, 1), Vector2(1.6, 4.5), Vector2(0, 1), Vector2(0.65, 0.9), Vector2.ZERO, "pt", "edge")]
		"edge":
			return [m(["shrub_a"], 1.0, Vector2i(1, 1), Vector2(6.0, 12.0), Vector2(0, 1), Vector2(0.65, 0.95)), m(SAPL, 1.0, Vector2i(1, 1), Vector2(9.0, 16.0), Vector2(0, 1), Vector2(0.6, 0.9)),
				m(ROCK_LOW, 1.0, Vector2i(1, 1), Vector2(6.0, 12.0), Vector2(0, 1), Vector2(0.55, 0.85), Vector2(0.15, 0.3))]
		"open":
			return [m(ROCK_LOW, 1.0, Vector2i(1, 1), Vector2(1.6, 5.5), Vector2(0, 1), Vector2(0.5, 0.85), Vector2(0.2, 0.4)), m(["shrub_a"], 1.0, Vector2i(1, 1), Vector2(1.6, 5.0), Vector2(0, 1), Vector2(0.5, 0.8)),
				m(COB, 1.0, Vector2i(1, 1), Vector2(1.6, 5.5), Vector2(0, 1), Vector2(0.7, 1.0))]
	return []


## satellite 數の重み（index＝個數 0..4）・距離（m）・單件數の重み（index＝個數）・距離
const SAT_W := {"water": [0.15, 0.4, 0.3, 0.15, 0.0], "farm": [0.1, 0.35, 0.35, 0.2, 0.0], "forest": [0.0, 0.15, 0.35, 0.35, 0.15],
	"edge": [0.1, 0.35, 0.35, 0.2, 0.0], "open": [0.0, 0.0, 0.35, 0.4, 0.25]}
const SAT_D := {"water": Vector2(5.0, 13.0), "farm": Vector2(5.0, 13.0), "forest": Vector2(5.0, 15.0), "edge": Vector2(5.0, 13.0), "open": Vector2(6.0, 18.0)}
const ISO_W := {"water": [0.35, 0.4, 0.25], "farm": [0.35, 0.4, 0.25], "forest": [0.0, 0.3, 0.4, 0.3], "edge": [0.35, 0.4, 0.25], "open": [0.35, 0.4, 0.25]}
const ISO_D := {"water": Vector2(12.0, 22.0), "farm": Vector2(12.0, 22.0), "forest": Vector2(15.0, 30.0), "edge": Vector2(12.0, 22.0), "open": Vector2(12.0, 22.0)}
## 主の最低件數（10–25 m で群に読める）
const MAIN_MIN := {"water": 2, "farm": 3, "forest": 3, "edge": 3, "open": 3}


static func _dist(mk: PackedByteArray, nx: int, nz: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(nx * nz)
	for k in nx * nz:
		a[k] = 0.0 if mk[k] == 1 else 1e6
	for j in nz:
		for i in nx:
			var k := j * nx + i
			var v := a[k]
			if v == 0.0:
				continue
			if i > 0:
				v = minf(v, a[k - 1] + 1.0)
			if j > 0:
				v = minf(v, a[k - nx] + 1.0)
				if i > 0:
					v = minf(v, a[k - nx - 1] + 1.4142)
				if i < nx - 1:
					v = minf(v, a[k - nx + 1] + 1.4142)
			a[k] = v
	for j in range(nz - 1, -1, -1):
		for i in range(nx - 1, -1, -1):
			var k := j * nx + i
			var v := a[k]
			if v == 0.0:
				continue
			if i < nx - 1:
				v = minf(v, a[k + 1] + 1.0)
			if j < nz - 1:
				v = minf(v, a[k + nx] + 1.0)
				if i < nx - 1:
					v = minf(v, a[k + nx + 1] + 1.4142)
				if i > 0:
					v = minf(v, a[k + nx - 1] + 1.4142)
			a[k] = v
	return a


## 半径 r（正方形）内の割合（積分画像）
static func _box_mean(mk: PackedByteArray, nx: int, nz: int, r: int) -> PackedFloat32Array:
	var I := PackedInt32Array()
	I.resize((nx + 1) * (nz + 1))
	for j in nz:
		var row := 0
		for i in nx:
			row += mk[j * nx + i]
			I[(j + 1) * (nx + 1) + i + 1] = I[j * (nx + 1) + i + 1] + row
	var out := PackedFloat32Array()
	out.resize(nx * nz)
	for j in nz:
		var j0 := maxi(0, j - r)
		var j1 := mini(nz, j + r + 1)
		for i in nx:
			var i0 := maxi(0, i - r)
			var i1 := mini(nx, i + r + 1)
			var s := I[j1 * (nx + 1) + i1] - I[j0 * (nx + 1) + i1] - I[j1 * (nx + 1) + i0] + I[j0 * (nx + 1) + i0]
			out[j * nx + i] = float(s) / float((i1 - i0) * (j1 - j0))
	return out


## 距離場を作る（Fm＝MeadowP9 の fields：同じ EXT・1 m・blk）
static func grids(C: Dictionary, Fm: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var o: Vector2 = Fm["o"]
	var nx: int = Fm["nx"]
	var nz: int = Fm["nz"]
	var n := nx * nz
	var mW := PackedByteArray()
	mW.resize(n)
	var mA := PackedByteArray()
	mA.resize(n)
	var mB := PackedByteArray()
	mB.resize(n)
	var mT := PackedByteArray()
	mT.resize(n)
	var mR := PackedByteArray()
	mR.resize(n)
	var mP := PackedByteArray()
	mP.resize(n)
	var mK := PackedByteArray()
	mK.resize(n)
	var blk: PackedByteArray = Fm["blk"]
	var S: RLib.TriSampler = C["S"]
	var WS: RLib.TriSampler = C["WS"]
	var FS: RLib.TriSampler = C["FS"]
	var R: RLib.TriSampler = C["R"]
	for j in nz:
		for i in nx:
			var k := j * nx + i
			var c := o + Vector2(i + 0.5, j + 0.5)
			var wh := WS.h(c.x, c.y)
			if not is_nan(wh) and wh > S.h(c.x, c.y) - 0.02:
				mW[k] = 1
			if not is_nan(FS.h(c.x, c.y)):
				mA[k] = 1
			if not is_nan(R.h(c.x, c.y)):
				mR[k] = 1
	for b: Dictionary in C["bld"]:
		var rr := Vector2(float(b["w"]), float(b["d"])).length() * 0.5 + 1.0
		var bo: Vector2 = b["o"]
		for j in range(maxi(0, floori(bo.y - rr - o.y)), mini(nz, ceili(bo.y + rr - o.y))):
			for i in range(maxi(0, floori(bo.x - rr - o.x)), mini(nx, ceili(bo.x + rr - o.x))):
				if obb_d(b, o + Vector2(i + 0.5, j + 0.5)) < 0.3:
					mB[j * nx + i] = 1
	for t: Vector2 in C["trees"]:
		var i := floori(t.x - o.x)
		var j := floori(t.y - o.y)
		if i >= 0 and j >= 0 and i < nx and j < nz:
			mT[j * nx + i] = 1
	for r: Rect2 in C["p10"]:
		for j in range(maxi(0, floori(r.position.y - o.y)), mini(nz, ceili(r.end.y - o.y))):
			for i in range(maxi(0, floori(r.position.x - o.x)), mini(nx, ceili(r.end.x - o.x))):
				mP[j * nx + i] = 1
	for r: Rect2 in C["rb"]:
		for j in range(maxi(0, floori(r.position.y - o.y)), mini(nz, ceili(r.end.y - o.y))):
			for i in range(maxi(0, floori(r.position.x - o.x)), mini(nx, ceili(r.end.x - o.x))):
				mK[j * nx + i] = 1
	var G := {"o": o, "nx": nx, "nz": nz, "blk": blk}
	G["K"] = _dist(mK, nx, nz)
	G["W"] = _dist(mW, nx, nz)
	G["A"] = _dist(mA, nx, nz)
	G["B"] = _dist(mB, nx, nz)
	G["T"] = _dist(mT, nx, nz)
	G["R"] = _dist(mR, nx, nz)
	G["P"] = _dist(mP, nx, nz)
	G["X"] = _dist(blk, nx, nz)
	G["MS"] = Fm["S"]
	G["dens"] = _box_mean(mB, nx, nz, 22)
	G["tden"] = _box_mean(mT, nx, nz, 9)
	# 村から見える林緣だけ：建物・田・路・水のどれかが近い所（林の奥の空き地は R5-4 の林緣にしない）

	G["ms"] = Time.get_ticks_msec() - t0
	return G


static func gi(G: Dictionary, p: Vector2) -> int:
	var o: Vector2 = G["o"]
	var i := clampi(floori(p.x - o.x), 0, int(G["nx"]) - 1)
	var j := clampi(floori(p.y - o.y), 0, int(G["nz"]) - 1)
	return j * int(G["nx"]) + i


## 双線形
static func gb(G: Dictionary, key: String, p: Vector2) -> float:
	var o: Vector2 = G["o"]
	var nx: int = G["nx"]
	var fx := p.x - o.x - 0.5
	var fz := p.y - o.y - 0.5
	var i := clampi(floori(fx), 0, nx - 2)
	var j := clampi(floori(fz), 0, int(G["nz"]) - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - j, 0.0, 1.0)
	var a: PackedFloat32Array = G[key]
	var k := j * nx + i
	return lerpf(lerpf(a[k], a[k + 1], tx), lerpf(a[k + nx], a[k + nx + 1], tx), tz)


## 距離が増える向き（＝特徴から離れる向き）
static func grad(G: Dictionary, key: String, p: Vector2) -> Vector2:
	var g := Vector2(gb(G, key, p + Vector2(1, 0)) - gb(G, key, p - Vector2(1, 0)), gb(G, key, p + Vector2(0, 1)) - gb(G, key, p - Vector2(0, 1)))
	return g.normalized() if g.length() > 0.05 else Vector2(0, 1)


## 1 點の環境類（錨の候補）："" ＝どれでもない
static func klass(C: Dictionary, G: Dictionary, p: Vector2) -> String:
	var k := gi(G, p)
	if (G["blk"] as PackedByteArray)[k] == 1:
		return ""
	var dP := (G["P"] as PackedFloat32Array)[k]
	var dR := (G["R"] as PackedFloat32Array)[k]
	if dP < 5.0 or dR < 2.0 or (G["K"] as PackedFloat32Array)[k] < 1.5:
		return ""
	var dW := (G["W"] as PackedFloat32Array)[k]
	var dA := (G["A"] as PackedFloat32Array)[k]
	var dT := (G["T"] as PackedFloat32Array)[k]
	var dB := (G["B"] as PackedFloat32Array)[k]
	var den := (G["dens"] as PackedFloat32Array)[k]
	if dW >= 0.8 and dW <= 6.0:
		return "water"
	if dA >= 0.8 and dA <= 7.0 and dW > 5.0:
		return "farm"
	if dT >= 1.5 and dT <= 8.0 and (G["tden"] as PackedFloat32Array)[k] * 361.0 >= 4.0 and dB > 5.0 and (dB <= 40.0 or dA <= 25.0 or dR <= 14.0 or dW <= 18.0):
		return "forest"
	if dB >= 4.0 and dB <= 22.0 and den < 0.06 and dA > 9.0 and dW > 7.0 and dT > 6.0:
		return "edge"
	if VL.BB.has_point(p) and dB >= 3.0 and den >= 0.06 and dR >= 3.0 and (G["X"] as PackedFloat32Array)[k] >= 2.0 and (G["MS"] as PackedFloat32Array)[k] >= 0.12 and _big_lot(G, p):
		return "open"
	return ""


## satellite／單件の置き場：錨の類でなくても、その類の帯の中で置ける所なら可（帯の外・禁區・P10 近くは不可）
static func fits(G: Dictionary, p: Vector2, cl: String) -> bool:
	var k := gi(G, p)
	if (G["blk"] as PackedByteArray)[k] == 1 or (G["P"] as PackedFloat32Array)[k] < 3.0 or (G["R"] as PackedFloat32Array)[k] < 1.5 or (G["K"] as PackedFloat32Array)[k] < 1.0:
		return false
	var d := (G[FIELD[cl]] as PackedFloat32Array)[k]
	match cl:
		"water":
			return d >= 0.6 and d <= 7.0
		"farm":
			return d >= 0.6 and d <= 8.0
		"forest":
			return d >= 1.2 and d <= 9.0
		"edge":
			return d >= 3.5 and d <= 24.0
	return d >= 1.5


## 大きな空き地か：6–11 m 先のどこかに「置けない所から 6 m 以上」の芯がある
static func _big_lot(G: Dictionary, p: Vector2) -> bool:
	for r: float in [6.0, 9.0, 11.0]:
		for a in 8:
			if gb(G, "X", p + Vector2.from_angle(TAU * a / 8.0) * r) >= 6.0:
				return true
	return false


## 等高線（d＝d0）に沿って L m 歩く（1 m 刻み、毎歩で勾配を取り直して曲がりに追従）
static func walk(G: Dictionary, key: String, p: Vector2, L: float) -> Vector2:
	var d0 := gb(G, key, p)
	var q := p
	var sgn := signf(L) if L != 0.0 else 1.0
	var left := absf(L)
	while left > 0.0:
		var stp := minf(1.0, left)
		var g := grad(G, key, q)
		q += Vector2(-g.y, g.x) * sgn * stp
		q += g * (d0 - gb(G, key, q))
		left -= stp
	return q


## 距離場で目標距離 d へ寄せる（勾配方向に 3 回）
static func to_band(G: Dictionary, key: String, p: Vector2, d: float) -> Vector2:
	var q := p
	for _i in 4:
		q += grad(G, key, q) * clampf(d - gb(G, key, q), -4.0, 4.0)
	return q


static func _pick(rng: RandomNumberGenerator, w: Array) -> int:
	var tot := 0.0
	for x in w:
		tot += float(x)
	var r := rng.randf() * tot
	for i in w.size():
		r -= float(w[i])
		if r <= 0.0:
			return i
	return w.size() - 1


## 一つの member を置く（rng・類の場・frame）；置けた件を返す
static func place(C: Dictionary, G: Dictionary, items: Array, rng: RandomNumberGenerator, cls: String, mb: Dictionary, a0: Vector2, tag: String, role: String) -> Array:
	var out: Array = []
	if rng.randf() > float(mb["p"]):
		return out
	var key: String = FIELD[cls]
	var n := rng.randi_range((mb["n"] as Vector2i).x, (mb["n"] as Vector2i).y)
	var band: Vector2 = mb["band"]
	# 村邊：帯は錨の位置から始まる相対（建物から遠い錨でも「人工 → 自然」の順を event の中で保つ）
	if cls == "edge":
		band += Vector2.ONE * maxf(0.0, gb(G, "B", a0) - 4.5)
	var tr: Vector2 = mb["t"]
	var sgn := -1.0 if rng.randf() < 0.5 else 1.0
	var t := sgn * rng.randf_range(tr.x, tr.y)
	var d0 := rng.randf_range(band.x, band.y)
	var prev_wide := false
	for k in n:
		var id: String = (mb["ids"] as Array)[rng.randi() % (mb["ids"] as Array).size()]
		if id == "fence":
			id = "st_shibagaki" if rng.randf() < 0.5 and _shiba_ok(C, a0) else STAKE[rng.randi() % 2]
		var p: Vector2
		match String(mb["mode"]):
			"line":
				# 等高線沿いの断續線：間隔 1.1–2.8 m、時々 3–5 m の切れ目、同じ距離 ±0.15 m
				if k > 0:
					t += sgn * (rng.randf_range(3.0, 4.5) if rng.randf() < 0.2 else rng.randf_range(1.1, 2.6))
					# 柴垣（幅 3 m）の前後は半幅ぶん空ける（隣の杭と重ならない）
					if id == "st_shibagaki" or prev_wide:
						t += sgn * 1.6
					if absf(t) > 6.5:
						break
				prev_wide = id == "st_shibagaki"
				p = to_band(G, key, walk(G, key, a0, t), d0 + rng.randf_range(-0.15, 0.15))
			"trail":
				# 距離場を登る踏み跡：band.x から 0.8–1.3 m 刻み、横に ±0.35 m
				var dd := band.x + k * rng.randf_range(0.8, 1.3) * 1.15
				var q := to_band(G, key, a0, dd)
				var g := grad(G, key, q)
				p = q + Vector2(-g.y, g.x) * rng.randf_range(-0.35, 0.35)
			_:
				if k > 0:
					t = sgn * rng.randf_range(tr.x, tr.y) * (1.0 if rng.randf() < 0.6 else -1.0)
					d0 = rng.randf_range(band.x, band.y)
				p = to_band(G, key, walk(G, key, a0, t), d0) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 0.3)
		if id == "st_shibagaki" and not _shiba_ok(C, p):
			id = STAKE[rng.randi() % 2]
		# 空地・村邊の植物は草の残る所（MeadowP9 の語意密度 ≥ 0.15）だけ——踏み固めた庭の真ん中に灌木を立てない
		if (cls == "open" or cls == "edge") and id in SOFT and (G["MS"] as PackedFloat32Array)[gi(G, p)] < 0.1:
			(C["dropped"] as Array).append("%s bare [%s]" % [id, tag])
			continue
		var g2 := grad(G, key, p)
		var face: Vector2
		match String(mb["yaw"]):
			"edge":
				face = g2.rotated(deg_to_rad(rng.randf_range(-12.0, 12.0)))
			"away":
				face = g2
			_:
				face = Vector2.from_angle(rng.randf() * TAU)
		var s := rng.randf_range((mb["s"] as Vector2).x, (mb["s"] as Vector2).y)
		# 中尺度：石は高さ ≥ 0.48 m か足元 ≥ 1 m（5 cm の小石は作らない）；菅は一回り大きく
		if id in ROCKS:
			var bx := box(id)
			s = maxf(s, minf(0.53 / float(bx[2]), 1.03 / (2.0 * maxf(float(bx[0]), float(bx[1])))))
		if id == "wk_sedge":
			s *= 1.3
		var rmax := 1.2 if String(mb["mode"]) == "line" else 2.0
		var it := spot(C, items, id, p, face, tag, rmax, 0.24 if id in ROCKS or id in VEG or id in FLAT else 0.18, s)
		if it.is_empty():
			continue
		# 主の件は錨から 7.5 m 以內（距離場の勾配が角で反転して遠くへ飛んだ件は捨てる＝主は一つの塊）
		if role == "main" and (it["p"] as Vector2).distance_to(a0) > 7.5:
			items.pop_back()
			(C["dropped"] as Array).append("%s far [%s]" % [id, tag])
			continue
		# 等高線の線（杭・垣）が帯から外れたら捨てる（境界の論理を崩さない）
		if String(mb["mode"]) == "line" and absf(gb(G, key, it["p"]) - d0) > 0.7:
			items.pop_back()
			(C["dropped"] as Array).append("%s offline [%s]" % [id, tag])
			continue
		# 帯の外へ逃げた水草（内陸の蘆）は捨てる
		if id in WETS and cls == "water" and gb(G, "W", it["p"]) > 2.6:
			items.pop_back()
			(C["dropped"] as Array).append("%s inland [%s]" % [id, tag])
			continue
		var sk := rng.randf_range((mb["sink"] as Vector2).x, (mb["sink"] as Vector2).y)
		if sk > 0.0:
			it["sink"] = sk
			it["y"] = float(it["y"]) - sk * float(box(id)[2]) * s
		it["cls"] = cls
		it["role"] = role
		it["mode"] = String(mb["mode"])
		it["line"] = ""
		out.append(it)
	# 線の識別（同じ member の線は同じ id）
	if String(mb["mode"]) == "line" and not out.is_empty():
		var lid := "%s|%s" % [tag, str(a0)]
		for it: Dictionary in out:
			it["line"] = lid
	return out


## 杭は 2 本以上＋連れ（杭以外）がある時だけ残す——一本だけ立つ杭・杭だけの塊は debug prop に見える
static func _fix_stakes(items: Array, got: Array) -> Array:
	# 幾何で判定（gate と同じ）：3.2 m 內に別の杭、5 m 內に杭以外の連れ——満たさない杭は消す（消えると隣も外れうるので繰り返す）
	var changed := true
	while changed:
		changed = false
		for it: Dictionary in got.duplicate():
			if not (String(it["id"]) in STAKE):
				continue
			var mate := false
			var comp := false
			for o: Dictionary in items:
				if o == it:
					continue
				var d := (o["p"] as Vector2).distance_to(it["p"])
				if (String(o["id"]) in STAKE or String(o["id"]) in FENCES) and d < 3.5:
					mate = true
				if not (String(o["id"]) in STAKE) and d < 5.0:
					comp = true
			if not (mate and comp):
				items.erase(it)
				got.erase(it)
				changed = true
	return got


## 柴垣：P10 の柴垣（田の縁）から 12 m 以上
static func _shiba_ok(C: Dictionary, p: Vector2) -> bool:
	for q: Vector2 in C.get("p10_shiba", []):
		if q.distance_to(p) < 12.0:
			return false
	return true


## 全村の規劃：錨の選定 → 主 event → satellite → 單件 → 留白
static func plan(v: Node3D, meadow_pts: PackedVector2Array, Fm: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var C := context(v)
	set_meadow(C, meadow_pts)
	C["dropped"] = []
	C["dbg"] = {}
	var G := grids(C, Fm)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var npri := FastNoiseLite.new()
	npri.seed = SEED + 1
	npri.frequency = 1.0 / 23.0
	var nom := FastNoiseLite.new()
	nom.seed = SEED + 2
	nom.frequency = 1.0 / 60.0
	nom.fractal_octaves = 2
	# 候補（2 m 格子）
	var cands: Array = []
	var o: Vector2 = G["o"]
	var counts := {}
	for j in range(1, int(G["nz"]) - 1, 2):
		for i in range(1, int(G["nx"]) - 1, 2):
			var p := o + Vector2(i + 0.5, j + 0.5)
			var cl := klass(C, G, p)
			if cl == "":
				continue
			counts[cl] = int(counts.get(cl, 0)) + 1
			var om := nom.get_noise_2d(p.x, p.y) * 0.5 + 0.5
			if om < float(OMIT[cl]):
				continue
			cands.append([npri.get_noise_2d(p.x, p.y) + rng.randf() * 0.35, p, cl])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var anchors: Array = []
	var ah := RH.new()
	ah.cs = 24.0
	for c: Array in cands:
		var p: Vector2 = c[1]
		var cl: String = c[2]
		# 間隔の揺らぎ：0.65–2.0 倍（等距の数珠にしない）
		var rad := float(SPACING[cl]) * rng.randf_range(0.65, 2.0)
		var ok := true
		for a: Dictionary in ah.near(p, 40.0):
			if (a["p"] as Vector2).distance_to(p) < maxf(rad, float(a["r"])) * (1.0 if a["cls"] == cl else 0.6):
				ok = false
				break
		if not ok:
			continue
		var a2 := {"p": p, "cls": cl, "r": rad}
		anchors.append(a2)
		ah.add(a2, Rect2(p, Vector2.ZERO))
	# event
	var items: Array = []
	var events: Array = []
	var last_type := {}
	var used := {}
	var fence_at: Array = []
	for ai in anchors.size():
		var a: Dictionary = anchors[ai]
		var cl: String = a["cls"]
		var rs := recipes(cl)
		var ev := {}
		var tname := ""
		var tag := ""
		var tried := {}
		# 型を選んで主を置く；主が MAIN_MIN 件に届かなければ撤回して別の型（最大 4 回、成功した型だけ「使った」に数える）
		for _att in 4:
			# 使った型ほど重みを下げる（型の偏りを作らない）；試した型・直前の型・35 m 內の二つ目の垣は避ける
			var w: Array = []
			for r: Array in rs:
				var wi := float(r[1]) / (1.0 + 0.9 * float(used.get("%s/%s" % [cl, r[0]], 0)))
				if tried.has(r[0]) or (rs.size() > 2 and last_type.get(cl, "") == r[0]):
					wi = 0.0
				if cl == "edge" and String(r[0]) == "fence_frag" and fence_at.any(func(q: Vector2) -> bool: return q.distance_to(a["p"]) < 35.0):
					wi = 0.0
				w.append(wi)
			if w.all(func(x: float) -> bool: return x <= 0.0):
				break
			var ti := _pick(rng, w)
			tname = rs[ti][0]
			tried[tname] = true
			tag = "%s/E%03d_%s" % [cl, ai, tname]
			ev = {"i": ai, "cls": cl, "type": tname, "p": a["p"], "tag": tag, "main": [], "sat": [], "iso": []}
			var n_before := items.size()
			var got: Array = []
			for mb: Dictionary in rs[ti][2]:
				got.append_array(place(C, G, items, rng, cl, mb, a["p"], tag, "main"))
			got = _fix_stakes(items, got)
			ev["main"] = got
			if got.size() >= int(MAIN_MIN[cl]):
				break
			items.resize(n_before)
			ev["main"] = []
		if ev.is_empty() or (ev["main"] as Array).is_empty():
			continue
		last_type[cl] = tname
		used["%s/%s" % [cl, tname]] = int(used.get("%s/%s" % [cl, tname], 0)) + 1
		if tname == "fence_frag":
			fence_at.append(a["p"])
		# satellite：等高線沿い（類ごとの距離、左右は乱数）；塞がれていれば任意の向きから類の帯へ
		var key: String = FIELD[cl]
		var ns := _pick(rng, SAT_W[cl])
		var srs := sat_recipes(cl)
		var sd: Vector2 = SAT_D[cl]
		for si in ns:
			var dbg: Dictionary = C["dbg"]
			for _try in (6 if cl == "water" else 5):
				var L := rng.randf_range(sd.x, sd.y) * (-1.0 if rng.randf() < 0.5 else 1.0)
				var sp := walk(G, key, a["p"], L)
				if not fits(G, sp, cl):
					sp = to_band(G, key, (a["p"] as Vector2) + Vector2.from_angle(rng.randf() * TAU) * absf(L), gb(G, key, a["p"]) + rng.randf_range(-0.5, 1.0))
				dbg[cl + "_try"] = int(dbg.get(cl + "_try", 0)) + 1
				if not fits(G, sp, cl):
					dbg[cl + "_unfit"] = int(dbg.get(cl + "_unfit", 0)) + 1
					continue
				var sr: Array = srs[rng.randi() % srs.size()]
				var got2: Array = []
				for mb: Dictionary in sr:
					got2.append_array(place(C, G, items, rng, cl, mb, sp, tag, "sat"))
				got2 = _fix_stakes(items, got2)
				(ev["sat"] as Array).append_array(got2)
				if not got2.is_empty():
					break
				dbg[cl + "_empty"] = int(dbg.get(cl + "_empty", 0)) + 1
		var ni := _pick(rng, ISO_W[cl])
		var irs := iso_recipes(cl)
		var idd: Vector2 = ISO_D[cl]
		for _k in ni:
			for _try in (6 if cl == "water" else 4):
				var L := rng.randf_range(idd.x, idd.y) * (-1.0 if rng.randf() < 0.5 else 1.0)
				var ip := walk(G, key, a["p"], L)
				if not fits(G, ip, cl):
					ip = to_band(G, key, (a["p"] as Vector2) + Vector2.from_angle(rng.randf() * TAU) * absf(L), gb(G, key, a["p"]) + rng.randf_range(-0.5, 1.5))
				if not fits(G, ip, cl):
					continue
				var got3 := place(C, G, items, rng, cl, irs[rng.randi() % irs.size()], ip, tag, "iso")
				(ev["iso"] as Array).append_array(got3)
				if not got3.is_empty():
					break
		events.append(ev)
	print("[ENV] INFO satellite 試行：%s" % str(C["dbg"]))
	return {"items": items, "events": events, "anchors": anchors, "C": C, "G": G, "counts": counts, "dropped": C["dropped"], "ms": Time.get_ticks_msec() - t0}


# ─────────────────────────── 烘焙 ───────────────────────────

static func bake(P: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	var groups := {}
	var col := StaticBody3D.new()
	col.name = "Collision"
	root.add_child(col)
	var meshes := {}
	var n_i := 0
	var ns := 0
	for it: Dictionary in P["items"]:
		var id := String(it["id"])
		var tg := String(it["tag"])
		if not groups.has(tg):
			var parts := tg.split("/")
			var par: Node = root
			if parts.size() > 1:
				if not groups.has(parts[0]):
					var gc := Node3D.new()
					gc.name = parts[0]
					root.add_child(gc)
					groups[parts[0]] = gc
				par = groups[parts[0]]
			var g := Node3D.new()
			g.name = parts[parts.size() - 1]
			par.add_child(g)
			groups[tg] = g
		var s: float = it.get("s", 1.0)
		var node := Node3D.new()
		node.name = "%03d_%s" % [n_i, id]
		node.transform = Transform3D(Basis(Vector3.UP, float(it["yaw"])).scaled(Vector3(s, s, s)), Vector3((it["p"] as Vector2).x, float(it["y"]), (it["p"] as Vector2).y))
		node.set_meta("env_id", id)
		node.set_meta("env_cluster", tg)
		node.set_meta("env_role", String(it.get("role", "")))
		(groups[tg] as Node).add_child(node)
		for lod in 2:
			var path := mesh_path(id, lod)
			if not meshes.has(path):
				meshes[path] = load(path)
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % lod
			mi.mesh = meshes[path]
			mi.visibility_range_begin = 0.0 if lod == 0 else LOD_SWITCH
			mi.visibility_range_end = LOD_SWITCH if lod == 0 else 200.0
			if lod == 1:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
		if not (id in NO_COLLIDE) and float(box(id)[2]) * s > 0.3:
			var b := box(id)
			var bx := BoxShape3D.new()
			bx.size = Vector3(float(b[0]) * 2.0 * s, float(b[2]) * s, float(b[1]) * 2.0 * s)
			var cs := CollisionShape3D.new()
			cs.name = "%s_c" % node.name
			cs.shape = bx
			var ba := Basis(Vector3.UP, float(it["yaw"]))
			cs.transform = Transform3D(ba, node.transform.origin + ba * Vector3(float(b[4]) * s, float(b[2]) * s * 0.5, float(b[3]) * s))
			col.add_child(cs)
			ns += 1
		n_i += 1
	root.set_meta("items", n_i)
	root.set_meta("shapes", ns)
	root.set_meta("art_revision", ART_REVISION)
	return root


static func own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		if c.scene_file_path == "":
			own(c, owner)
