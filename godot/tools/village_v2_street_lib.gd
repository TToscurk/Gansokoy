extends RefCounted
## 人間之里 V2 P10 R2：主街 Street Life（Main Street / Street Life）——主街を歩く玩家が「人が住み・売り買いし・働いている聚落」と感じる中大型の生活物。
##   範圍：①主街沿いの店頭外溢（店の前の路縁帯 0–1.25 m、店ごとに「商い」を決めて平台・雛壇・俵・樽・看板・行灯・幟・提灯）
##         ②住まいの前の小物（鉢植え・天水桶・用水桶・腰掛け）③道端の小さな作業場（桶屋・大工・藁細工；空き地・角地）
##         ④巷口／路口の用途提示（道標＋その先の用途を示す物）⑤市の入口 spillover（中橫街の 12 m の口へ：大看板・提灯・荷・荷車・幟）
##         ⑥農田→住宅の境（農具掛け・稲架・藁塚・柴垣・俵）。MarketP10（P10 R1 封存）は動かさない・重ねない。地面は描かない。
##   通行：主街 7.2 m のうち中央 ≥ 4.6 m を常に空ける（路縁帯は片側 1.25 m まで）；戸口の前（門口 ±0.75 m・奥 1.8 m）は空ける。
##   Generator＝source of truth：配置はここだけで決める（Editor で動かさない）。overlay＝Props/StreetP10（gen/street_p10.scn）。
## 座標：建物の局部＝Kit と同じ（x＝間口方向、+z＝通り側、牆線 z＝d/2）；店頭の帯の位置 u＝路縁からの距離（+＝路面側）。

const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const ML := preload("res://tools/village_v2_groundcover_macro.gd")
const MK := preload("res://tools/village_v2_market_lib.gd")
const GC := preload("res://tools/village_v2_groundcover_lib.gd")
const OUTPUT := "res://maps/village_v2/gen/street_p10.scn"
const LAYOUT := "res://maps/village_v2/layout_v2.json"
const NODE_NAME := "StreetP10"
const PARENT := "Props"
const LOD_SWITCH := 34.0
const SEED := 10020
const DIRS := {"st_": "res://assets/village_v2/street_kit/mesh/", "mk_": "res://assets/village_v2/market_kit/mesh/",
	"gd_": "res://assets/village_v2/geidon_kit/mesh/", "sz_": "res://assets/village_v2/suzu_kit/mesh/",
	"sk_": "res://assets/village_v2/school_kit/mesh/", "kr_": "res://assets/village_v2/kiri_kit/mesh/",
	"wk_": "res://assets/village_v2/waterside_kit/mesh/", "tk_": "res://assets/village_v2/tower_kit/mesh/",
	"gk_": "res://assets/village_v2/garden_kit/mesh/"}
## 局部の足元（半幅 x、半奥 z、高さ、奥の中心ずれ z、横の中心ずれ x）——碰撞・擺放檢查の共通定義（manifest dims から）
const BOX := {
	"st_hiradai_yasai": [1.0, 0.39, 0.78, -0.03, 0.145], "st_hiradai_zakka": [1.0, 0.47, 1.45, -0.045, -0.015],
	"st_hinadan_seto": [0.65, 0.555, 1.02, 0.205, 0.0], "st_hiradai_kashi": [0.7, 0.3, 0.75, 0.0, 0.0],
	"st_kome_tsumi": [0.79, 0.605, 1.31, 0.155, 0.04],
	"st_andon_meshi": [0.2, 0.2, 1.04, 0.0, 0.0], "st_andon_yasumi": [0.2, 0.2, 1.04, 0.0, 0.0], "st_andon_kusuri": [0.2, 0.2, 1.04, 0.0, 0.0],
	"st_kanban_sake": [0.33, 0.3, 1.78, 0.0, 0.0], "st_kanban_kome": [0.33, 0.3, 1.78, 0.0, 0.0],
	"st_kanban_kusuri": [0.33, 0.3, 1.78, 0.0, 0.0], "st_kanban_abura": [0.33, 0.3, 1.78, 0.0, 0.0],
	"st_nobori_sake": [0.1, 0.1, 3.7, 0.0, 0.0], "st_nobori_kome": [0.1, 0.1, 3.7, 0.0, 0.0], "st_nobori_meshi": [0.1, 0.1, 3.7, 0.0, 0.0],
	"st_chochin_aka": [0.15, 0.15, 2.4, 0.0, 0.0], "st_chochin_shiro": [0.15, 0.15, 2.4, 0.0, 0.0],
	"st_okeya": [1.09, 0.735, 0.62, 0.015, -0.13], "st_daiku": [1.16, 0.6, 1.55, -0.015, 0.0], "st_wara": [0.7, 0.45, 1.4, 0.0, 0.0],
	"st_fuda_ichi": [0.16, 0.13, 1.74, 0.06, 0.0], "st_fuda_ta": [0.16, 0.13, 1.74, 0.06, 0.0],
	"st_fuda_kawa": [0.16, 0.13, 1.74, 0.06, 0.0], "st_fuda_yashiro": [0.16, 0.13, 1.74, 0.06, 0.0],
	"st_ichi_kanban": [0.62, 0.17, 2.45, 0.0, 0.0], "st_onobori_ichi": [0.2, 0.2, 7.6, 0.0, 0.0], "st_kago_tsumi": [0.84, 0.45, 0.62, -0.055, 0.0],
	"st_kuwa": [0.84, 0.34, 1.5, 0.04, 0.18], "st_warazuka": [0.7, 0.7, 1.78, 0.0, 0.0], "st_hasa": [1.84, 0.34, 1.9, 0.0, 0.0],
	"st_shibagaki": [1.5, 0.09, 1.15, 0.0, 0.0],
	# 重用（只讀）
	"mk_kanban_yasai": [0.27, 0.31, 1.15, 0.0, 0.0], "mk_kanban_dango": [0.27, 0.31, 1.15, 0.0, 0.0], "mk_kanban_seto": [0.27, 0.31, 1.15, 0.0, 0.0],
	"mk_nobori_yasai": [0.1, 0.1, 3.7, 0.0, 0.0], "mk_nobori_cha": [0.1, 0.1, 3.7, 0.0, 0.0], "mk_nobori_ichi": [0.1, 0.1, 3.7, 0.0, 0.0],
	"mk_bangasa": [0.16, 0.16, 2.4, 0.0, 0.0], "mk_kame": [0.6, 0.5, 1.06, -0.09, 0.25], "mk_tenbin": [0.86, 0.22, 0.62, 0.0, 0.0],
	"mk_kuruma_ni": [0.56, 1.46, 1.21, 0.56, 0.0], "mk_chochin_line": [2.55, 0.1, 3.3, 0.0, 0.0], "mk_tsumini": [1.08, 0.59, 0.83, -0.21, 0.03],
	"gd_taruzumi": [0.725, 0.28, 1.24, 0.0, 0.0], "gd_shogi": [0.8, 0.29, 0.42, 0.0, 0.0], "gd_taru": [0.24, 0.24, 0.64, 0.0, 0.0],
	"kr_kuruma": [0.56, 1.37, 0.92, 0.645, 0.0], "kr_hakozumi": [0.63, 0.3, 0.92, -0.015, 0.0], "kr_fukuro": [0.74, 0.19, 0.58, 0.01, 0.08],
	"kr_okeyama": [0.475, 0.31, 0.88, 0.0, 0.0], "kr_zaimoku": [1.06, 0.32, 0.18, -0.015, 0.025],
	"sz_hachi": [0.245, 0.245, 0.62, 0.0, 0.0], "sz_stool": [0.21, 0.13, 0.4, 0.0, 0.0],
	"sk_tensui": [0.31, 0.31, 0.745, 0.0, 0.0], "sk_teoke": [0.27, 0.15, 0.46, 0.0, 0.13], "sk_bench": [0.9, 0.245, 0.42, 0.0, 0.0],
	"sk_woodpile": [0.88, 0.29, 0.98, 0.015, 0.0], "wk_tawara3": [0.41, 0.46, 0.84, 0.0, 0.0], "tk_okeyama": [0.525, 0.275, 1.21, 0.0, 0.0],
	"gk_yotsume": [0.93, 0.06, 0.98, 0.0, 0.0], "st_ido": [1.115, 0.86, 2.36, 0.27, 0.165], "mk_hoshimono": [1.72, 0.14, 1.95, 0.0, 0.0],
	"sk_box": [0.305, 0.21, 0.38, 0.0, 0.0],
}
const LINE := ["mk_chochin_line"]
const NO_COLLIDE := []
const TALL := 2.2
## 商い（店頭の主役）——同じ側で隣り合う店に同じ商いを置かない
const TRADES := ["yaoya", "sake", "zakka", "meshi", "seto", "kome", "chaya", "kusuri", "kashi", "abura", "tofu", "hakimono", "sakana"]
const DISPLAY := ["st_hiradai_yasai", "st_hiradai_zakka", "st_hinadan_seto", "st_hiradai_kashi", "st_kome_tsumi", "gd_taruzumi",
	"gd_shogi", "kr_okeyama", "st_wara", "mk_tenbin", "sk_bench", "mk_kame"]
const WORKS := ["st_okeya", "st_daiku", "st_wara", "sk_woodpile"]
const LANTERN := ["st_chochin_aka", "st_chochin_shiro", "st_andon_meshi", "st_andon_yasumi", "st_andon_kusuri", "mk_chochin_line"]
## 主街の路縁帯（u＝路縁から路面側へ）：片側 BAND m まで
const BAND := 1.25
const DOOR_HW := 0.75
const DOOR_D := 1.8
## 市の入口（中橫街の口：MarketP10 の口 x 240–252）と主街の辻
const CROSS_MID := Vector2(262.0, -20.0)
const MOUTH := Rect2(240.0, -31.0, 12.0, 8.0)
## Hero の正面（店頭帯を置かない）：鈴奈庵・鯢吞亭・霧雨店・火見櫓の前は封存 R4 周邊
const ROADS_MAIN := ["MainStreet"]


static func yaw_to(d: Vector2) -> float:
	var n := d.normalized()
	return atan2(n.x, n.y)


static func local_to_world(it: Dictionary, l: Vector2) -> Vector2:
	var yaw: float = it["yaw"]
	var ax := Vector2(cos(yaw), -sin(yaw))
	var az := Vector2(sin(yaw), cos(yaw))
	return (it["p"] as Vector2) + ax * l.x + az * l.y


static func corners(it: Dictionary) -> PackedVector2Array:
	var b: Array = BOX[String(it["id"])]
	var out := PackedVector2Array()
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		out.append(local_to_world(it, Vector2(float(b[4]) + s.x * float(b[0]), float(b[3]) + s.y * float(b[1]))))
	return out


## 足元の多角形（線状＝竿 2 本だけ）
static func polys(it: Dictionary) -> Array:
	if String(it["id"]) in LINE:
		var out: Array = []
		for sx in [-2.5, 2.5]:
			var c := local_to_world(it, Vector2(sx, 0.0))
			out.append(PackedVector2Array([c + Vector2(-0.08, -0.08), c + Vector2(0.08, -0.08), c + Vector2(0.08, 0.08), c + Vector2(-0.08, 0.08)]))
		return out
	return [corners(it)]


## 見えている地表の最上面：地形・路面・P4 院子地面（可見最上面 build rule）
static func top_h(C: Dictionary, p: Vector2) -> float:
	var h := (C["S"] as RLib.TriSampler).h(p.x, p.y)
	for k: String in ["R", "Y"]:
		var v := (C[k] as RLib.TriSampler).h(p.x, p.y)
		if not is_nan(v):
			h = maxf(h, v)
	return h


static func item(C: Dictionary, id: String, p: Vector2, face: Vector2, tag: String, extra := {}) -> Dictionary:
	var it := {"id": id, "p": p, "yaw": yaw_to(face), "tag": tag, "y": 0.0}
	it.merge(extra, true)
	ground(C, it)
	return it


static func ground(C: Dictionary, it: Dictionary) -> void:
	var hs: Array = [top_h(C, it["p"])]
	for poly: PackedVector2Array in polys(it):
		for q: Vector2 in poly:
			hs.append(top_h(C, q))
	it["y"] = hs.min()


static func mesh_dir(id: String) -> String:
	return DIRS[id.substr(0, 3)]


# ─────────────────────────── 文脈 ───────────────────────────

static func _seg_proj(a: Vector2, b: Vector2, p: Vector2) -> Array:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return [(a + ab * t).distance_to(p), t]


## 折れ線上の位置：[距離, 弧長 s, 符號付き側（+＝進行方向の右）, 接線]
static func pl_param(pts: PackedVector2Array, p: Vector2) -> Array:
	var best := [1e9, 0.0, 0.0, Vector2.ZERO]
	var acc := 0.0
	for i in pts.size() - 1:
		var r := _seg_proj(pts[i], pts[i + 1], p)
		var tg := (pts[i + 1] - pts[i]).normalized()
		if float(r[0]) < float(best[0]):
			var side := signf(tg.cross(p - pts[i]))
			best = [r[0], acc + float(r[1]) * pts[i].distance_to(pts[i + 1]), side, tg]
		acc += pts[i].distance_to(pts[i + 1])
	return best


static func pl_point(pts: PackedVector2Array, s: float) -> Array:
	var acc := 0.0
	for i in pts.size() - 1:
		var L := pts[i].distance_to(pts[i + 1])
		if s <= acc + L or i == pts.size() - 2:
			var t := clampf((s - acc) / L, 0.0, 1.0)
			return [pts[i].lerp(pts[i + 1], t), (pts[i + 1] - pts[i]).normalized()]
		acc += L
	return [pts[-1], Vector2.ZERO]


static func pl_len(pts: PackedVector2Array) -> float:
	var acc := 0.0
	for i in pts.size() - 1:
		acc += pts[i].distance_to(pts[i + 1])
	return acc


static func context(v: Node3D) -> Dictionary:
	var C := {"S": RLib.terrain_sampler(v), "R": RLib.road_sampler(v), "Y": ML.yard_sampler(v)}
	# 店先帯（P6 R4 Frontage、LOD0 の面）：上に置かない判定用
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
	# 水面（本川・水渠・西溪）と P7 河岸構件・橋（AABB +0.6 m）——水の中・護岸・橋の上には置かない
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
				rb.append(Rect2(a.position.x, a.position.z, a.size.x, a.size.z).grow(0.6))
	C["rb"] = rb
	# 道路（layout）：主街・横街・巷
	var LY: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var roads := {}
	for r: Dictionary in LY["roads"] + LY["lanes"]:
		var pts := PackedVector2Array()
		for q: Array in r["pts"]:
			pts.append(Vector2(float(q[0]), float(q[1])))
		roads[String(r["name"])] = {"pts": pts, "hw": float(r["half_w"]), "class": String(r.get("class", "lane"))}
	C["roads"] = roads
	# 建物（全 B_*；主街沿いは Kit の開間・戸口も）
	var bl: Array = []
	for b in v.get_node("Districts").find_children("B_*", "", true, false):
		var n3 := b as Node3D
		if n3 == null or not n3.has_meta("width_m"):
			continue
		var xf := RLib.rel_xf(n3, v)
		var o := Vector2(xf.origin.x, xf.origin.z)
		var ax := Vector2(xf.basis.x.x, xf.basis.x.z).normalized()
		var az := Vector2(xf.basis.z.x, xf.basis.z.z).normalized()
		var kit := n3.get_node_or_null("Kit")
		bl.append({"name": String(n3.name), "o": o, "ax": ax, "az": az, "w": float(n3.get_meta("width_m")), "d": float(n3.get_meta("depth_m")),
			"road": String(n3.get_meta("road", "")), "type": String(n3.get_meta("type", "")), "kind": String(n3.get_meta("kind", "")),
			"kinds": kit.get_meta("bay_kind", []) if kit else [], "bay_x": kit.get_meta("bay_x", []) if kit else [],
			"door_cx": float(kit.get_meta("door_cx", 0.0)) if kit else 0.0})
	C["bld"] = bl
	# 封存 overlay（R4 Hero 周邊・稗田邸庭園・鎮守之森…）の構件 AABB（+1 m、地面は +0.5 m）——置かない
	var blk: Array = []
	for nm: String in GC.SEALED_OVERLAYS:
		var ov := v.get_node_or_null("Vegetation/" + nm)
		if ov == null:
			continue
		for mi in ov.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null:
				continue
			var a := RLib.rel_xf(g, v) * g.get_aabb()
			blk.append(Rect2(a.position.x, a.position.z, a.size.x, a.size.z).grow(0.5 if String(g.name) == "Ground" else 1.0))
	C["block"] = blk
	# P10 R1 市集（封存）：構件の足元と歩く通り——重ねない・塞がない
	var MP := MK.plan(v)
	C["market"] = MP["items"]
	for ln: String in MK.LANES:
		blk.append(MK.LANES[ln])
	return C


## 建物の局部（lx, lz）→ 世界
static func bw(b: Dictionary, lx: float, lz: float) -> Vector2:
	return (b["o"] as Vector2) + (b["ax"] as Vector2) * lx + (b["az"] as Vector2) * lz


## 牆線から路縁までの距離（局部 lx で、0.05 m 刻みで路面に入るまで）
static func gap_at(C: Dictionary, b: Dictionary, lx: float) -> float:
	var R: RLib.TriSampler = C["R"]
	var zw := float(b["d"]) * 0.5
	for k in 60:
		var q := bw(b, lx, zw + k * 0.05)
		if not is_nan(R.h(q.x, q.y)):
			return k * 0.05
	return NAN


## 店頭の帯の点：局部 lx、路縁から u（＋＝路面側）
static func band(C: Dictionary, b: Dictionary, lx: float, u: float) -> Vector2:
	var g := gap_at(C, b, lx)
	if is_nan(g):
		g = 0.5
	return bw(b, lx, float(b["d"]) * 0.5 + g + u)


## 開間（局部 x 範圍・種類）
static func bays(b: Dictionary) -> Array:
	var out: Array = []
	var xs: Array = b["bay_x"]
	var ks: Array = b["kinds"]
	for i in ks.size():
		out.append({"x0": float(xs[i]), "x1": float(xs[i + 1]), "k": String(ks[i]), "c": (float(xs[i]) + float(xs[i + 1])) * 0.5})
	return out


static func is_shop(b: Dictionary) -> bool:
	return (b["kinds"] as Array).any(func(k: String) -> bool: return k.begins_with("shop"))


## 戸口の前の空け帯（世界の多角形）：門口 ±DOOR_HW、牆線から DOOR_D
static func door_poly(b: Dictionary) -> PackedVector2Array:
	var cx := float(b["door_cx"])
	var zw := float(b["d"]) * 0.5
	return PackedVector2Array([bw(b, cx - DOOR_HW, zw), bw(b, cx + DOOR_HW, zw), bw(b, cx + DOOR_HW, zw + DOOR_D), bw(b, cx - DOOR_HW, zw + DOOR_D)])


# ─────────────────────────── 規劃 ───────────────────────────

static func plan(v: Node3D) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var C := context(v)
	C["dropped"] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var items: Array = []
	var anchors: Array = []
	var shops: Array = []
	var ms: PackedVector2Array = C["roads"]["MainStreet"]["pts"]
	# ── 主街沿いの建物（road=MainStreet）を側ごとに s 順
	var sides := {-1.0: [], 1.0: []}
	for b: Dictionary in C["bld"]:
		if String(b["road"]) != "MainStreet":
			continue
		var pr := pl_param(ms, b["o"])
		if float(pr[0]) > 14.0:
			continue
		b["s"] = float(pr[1])
		b["side"] = float(pr[2])
		(sides[float(pr[2])] as Array).append(b)
	for sd: float in sides:
		(sides[sd] as Array).sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return float(a["s"]) < float(c["s"]))
	# ── 商いの割り当て：店（shop 開間あり）を側ごとに順に、隣と同じにしない・全体で偏らない
	var counts := {}
	for t: String in TRADES:
		counts[t] = 0
	var res_i := 0
	for sd: float in sides:
		var prev := ""
		for b: Dictionary in sides[sd]:
			if not is_shop(b):
				b["trade"] = "res" if res_i % 3 != 2 else "res_work"
				res_i += 1
				continue
			var cands: Array = TRADES.filter(func(t: String) -> bool: return t != prev)
			cands.sort_custom(func(a: String, c: String) -> bool:
				return int(counts[a]) * 100 + hash(a + String(b["name"])) % 97 < int(counts[c]) * 100 + hash(c + String(b["name"])) % 97)
			var tr: String = cands[0]
			b["trade"] = tr
			counts[tr] = int(counts[tr]) + 1
			prev = tr
	# ── 市の入口：主街側の角店（MKT_023）の店先帯に「市」の大看板・幟・提灯を先に置く（南北どちらから来ても主街上で見える）
	_market_corner(C, items, anchors)
	# ── 店頭外溢（主街）
	for sd: float in sides:
		var last_fire := -100.0
		for b: Dictionary in sides[sd]:
			var tr := String(b["trade"])
			var before := items.size()
			if tr.begins_with("res"):
				_residence(C, b, items, anchors, rng, tr == "res_work")
			else:
				_shopfront(C, b, tr, items, anchors, rng)
				shops.append({"name": b["name"], "trade": tr, "n": items.size() - before, "side": sd, "s": b["s"], "level": b.get("level", "")})
			# 用水桶（町の防火）：同じ側で 38 m おきに建物の端へ
			if float(b["s"]) - last_fire > 38.0:
				var fit := _put(C, b, items, "fire", "tk_okeyama", float(b["w"]) * 0.5 - 0.6, 0.35)
				if not fit.is_empty():
					last_fire = float(b["s"])
	# ── 路口・巷口の用途提示
	_crossings(C, items, anchors)
	# ── 市の入口 spillover（中橫街の口へ導く）
	_market_lead(C, items, anchors)
	# ── 道端の作業場（空き地・角地）
	_workspaces(C, items, anchors, rng)
	# ── 暮らしの点景（井戸端・干し竿）
	_life(C, items, anchors)
	# ── 農田→住宅の境
	_farm_edges(C, items, anchors)
	return {"items": items, "anchors": anchors, "shops": shops, "C": C, "sides": sides, "dropped": C["dropped"], "ms": Time.get_ticks_msec() - t0}


## 置けるか（足元が建物・店先帯・他の物・路面に入らない、戸口を塞がない）——規劃側の判定。""＝可、それ以外＝理由
static func why(C: Dictionary, it: Dictionary, items: Array, allow_road := true) -> String:
	var F: RLib.TriSampler = C["F"]
	var R: RLib.TriSampler = C["R"]
	for poly: PackedVector2Array in polys(it):
		for q in _poly_samples(poly):
			if is_nan((C["S"] as RLib.TriSampler).h(q.x, q.y)):
				return "terrain"
			if not is_nan(F.h(q.x, q.y)):
				return "frontage"
			if not allow_road and not is_nan(R.h(q.x, q.y)):
				return "road"
			for b: Dictionary in C["bld"]:
				if (b["o"] as Vector2).distance_to(q) < 12.0 and obb_d(b, q) < 0.3:
					return "building:" + String(b["name"])
			if (C.get("block", []) as Array).any(func(r: Rect2) -> bool: return r.has_point(q)):
				return "sealed"
			if in_water(C, q):
				return "water"
		for b: Dictionary in C["bld"]:
			if (b["o"] as Vector2).distance_to(it["p"]) < 14.0 and not Geometry2D.intersect_polygons(poly, door_poly(b)).is_empty():
				return "door:" + String(b["name"])
		for o: Dictionary in items + (C.get("market", []) as Array):
			if (o["p"] as Vector2).distance_to(it["p"]) > 8.0:
				continue
			for op: PackedVector2Array in (polys(o) if BOX.has(String(o["id"])) else [MK.corners(o)]):
				if not Geometry2D.intersect_polygons(poly, op).is_empty():
					return "overlap:" + String(o["id"])
	return ""


static func _free(C: Dictionary, it: Dictionary, items: Array, allow_road := true) -> bool:
	var r := why(C, it, items, allow_road)
	if r != "":
		(C["dropped"] as Array).append("%s@(%.1f,%.1f) %s [%s]" % [it["id"], (it["p"] as Vector2).x, (it["p"] as Vector2).y, r, it["tag"]])
	return r == ""


static func _poly_samples(poly: PackedVector2Array, step := 0.25) -> PackedVector2Array:
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


## 水の中・水際 0.8 m・P7 河岸構件／橋の AABB の内
static func in_water(C: Dictionary, q: Vector2) -> bool:
	var WS: RLib.TriSampler = C["WS"]
	var S: RLib.TriSampler = C["S"]
	for o: Vector2 in [Vector2.ZERO, Vector2(0.8, 0), Vector2(-0.8, 0), Vector2(0, 0.8), Vector2(0, -0.8)]:
		var p := q + o
		var wh := WS.h(p.x, p.y)
		if not is_nan(wh) and wh > S.h(p.x, p.y) - 0.02:
			return true
	return (C["rb"] as Array).any(func(r: Rect2) -> bool: return r.has_point(q))


## 建物 OBB までの距離（負＝内側）
static func obb_d(b: Dictionary, p: Vector2) -> float:
	var d := p - (b["o"] as Vector2)
	var lx := absf(d.dot(b["ax"])) - float(b["w"]) * 0.5
	var lz := absf(d.dot(b["az"])) - float(b["d"]) * 0.5
	if lx <= 0.0 and lz <= 0.0:
		return maxf(lx, lz)
	return Vector2(maxf(lx, 0.0), maxf(lz, 0.0)).length()


## 店の賑わいの強さ：quiet（看板だけ・暖簾だけ）／normal（陳列＋脇の看板）／rich（陳列＋看板＋副え物＋幟・提灯・腰掛け）
static func intensity(b: Dictionary) -> String:
	return ["normal", "rich", "quiet", "normal", "rich", "normal", "quiet", "rich"][absi(hash(String(b["name"]) + "i")) % 8]


## 店頭：主役の陳列（戸口から遠い店の開間の前）を中心に、看板・副え物を「隣に寄せて」一塊にする（ばらまかない）
static func _shopfront(C: Dictionary, b: Dictionary, tr: String, items: Array, anchors: Array, rng: RandomNumberGenerator) -> void:
	var w := float(b["w"])
	var dcx := float(b["door_cx"])
	var az: Vector2 = b["az"]
	var tag := "shop:" + tr
	var lvl := intensity(b)
	b["level"] = lvl
	var slots: Array = []
	for by: Dictionary in bays(b):
		if String(by["k"]).begins_with("shop") and absf(float(by["c"]) - dcx) > 0.2:
			slots.append(float(by["c"]))
	if slots.is_empty():
		for by: Dictionary in bays(b):
			if absf(float(by["c"]) - dcx) > 1.2:
				slots.append(float(by["c"]))
	slots.sort_custom(func(a: float, c: float) -> bool: return absf(a - dcx) > absf(c - dcx))
	var main_id: String = {"yaoya": "st_hiradai_yasai", "sake": "gd_taruzumi", "zakka": "st_hiradai_zakka", "meshi": "sk_bench",
		"seto": "st_hinadan_seto", "kome": "st_kome_tsumi", "chaya": "gd_shogi", "kusuri": "st_kanban_kusuri", "kashi": "st_hiradai_kashi",
		"abura": "mk_kame", "tofu": "kr_okeyama", "hakimono": "st_wara", "sakana": "mk_tenbin"}[tr]
	var sign_id: String = {"yaoya": "mk_kanban_yasai", "sake": "st_kanban_sake", "zakka": "sk_teoke", "meshi": "st_andon_meshi", "seto": "mk_kanban_seto",
		"kome": "st_kanban_kome", "chaya": "st_andon_yasumi", "kusuri": "st_andon_kusuri", "kashi": "mk_kanban_dango", "abura": "st_kanban_abura",
		"tofu": "sk_teoke", "hakimono": "sk_teoke", "sakana": "kr_okeyama"}[tr]
	var b0: Array = BOX[main_id]
	var mx: float = slots[0] if not slots.is_empty() else (w * 0.25 if dcx < 0.0 else -w * 0.25)
	var away := 1.0 if mx >= dcx else -1.0          # 戸口から離れる向き
	var u_main := float(b0[1]) - float(b0[3]) + 0.08
	if lvl == "quiet":
		# 静かな店：暖簾（Kit に既にある）だけ——食・茶・薬は置行灯ひとつ、看板の無い商い（荒物・豆腐・履物・魚）は小さく主役だけ。
		# 白い置き看板を全部の店に立てない（「看板の行列」に見える：vision 講評 r2）
		if sign_id.begins_with("st_andon"):
			_put(C, b, items, tag, sign_id, dcx + away * (DOOR_HW + 0.45), 0.35)
			return
		if sign_id.begins_with("st_") or sign_id.begins_with("mk_kanban"):
			return
	var mi: Dictionary = _put(C, b, items, tag, main_id, mx, u_main)
	if mi.is_empty():
		return
	var mlx := ((mi["p"] as Vector2) - (b["o"] as Vector2)).dot(b["ax"])
	var mhx := float(b0[0])
	# 看板は主役の「戸口側」の隣（客の動線に向けて）、副え物は外側の隣——一塊
	var s0: Array = BOX[sign_id]
	if lvl != "quiet":
		_put(C, b, items, tag, sign_id, mlx - away * (mhx + float(s0[0]) + 0.12), float(s0[1]) + 0.12)
	var nob_id: String = {"yaoya": "mk_nobori_yasai", "sake": "st_nobori_sake", "meshi": "st_nobori_meshi", "kome": "st_nobori_kome",
		"chaya": "mk_nobori_cha", "kashi": "st_nobori_meshi"}.get(tr, "")
	if nob_id != "" and (lvl == "rich" or tr in ["sake", "kome", "chaya"]):
		if _put(C, b, items, tag, nob_id, away * (w * 0.5 - 0.25), 0.2).is_empty():
			_put(C, b, items, tag, nob_id, -away * (w * 0.5 - 0.25), 0.2)
	if lvl == "quiet":
		pass
	elif lvl == "rich":
		var sub: String = {"yaoya": "kr_hakozumi", "sake": "gd_taru", "zakka": "kr_okeyama", "meshi": "gd_taru", "seto": "mk_kame", "kome": "wk_tawara3",
			"chaya": "mk_bangasa", "kusuri": "sz_hachi", "kashi": "sz_stool", "abura": "kr_okeyama", "tofu": "sk_tensui", "hakimono": "kr_houki_none", "sakana": "sk_teoke"}[tr]
		if BOX.has(sub):
			var sb: Array = BOX[sub]
			_put(C, b, items, tag, sub, mlx + away * (mhx + float(sb[0]) + 0.12), float(sb[1]) + 0.12)
		if tr in ["meshi", "sake", "chaya", "kashi"]:
			_put(C, b, items, tag, "st_chochin_aka" if tr != "sake" else "st_chochin_shiro", dcx - away * (DOOR_HW + 0.3), 0.25, -az)
	# anchors：売り手（陳列の後ろ＝店先帯の上）＋客（陳列の前）
	var vp := band(C, b, mlx, -0.3)
	anchors.append({"id": "st_vendor_%s" % String(b["name"]).trim_prefix("B_P_"), "activity": "vendor_stand", "p": vp, "yaw": yaw_to(az), "ref": main_id})
	var cp := local_to_world(mi, Vector2(0.4, float(b0[3]) + float(b0[1]) + 0.55))
	anchors.append({"id": "st_customer_%s" % String(b["name"]).trim_prefix("B_P_"), "activity": "customer_browse", "p": cp, "yaw": yaw_to(-az), "ref": main_id})


static func _put(C: Dictionary, b: Dictionary, items: Array, tag: String, id: String, lx: float, u: float, face := Vector2.ZERO) -> Dictionary:
	var az: Vector2 = b["az"]
	var w := float(b["w"])
	var fc := az if face == Vector2.ZERO else face
	var hx := float(BOX[id][0])
	for dx in [0.0, 0.35, -0.35, 0.7, -0.7, 1.05, -1.05, 1.4, -1.4, 1.75, -1.75, 2.1, -2.1]:
		if absf(lx + dx) > w * 0.5 - minf(hx, 0.6) * 0.5:
			continue
		var it := item(C, id, band(C, b, lx + dx, u), fc, tag, {"b": b["name"]})
		if why(C, it, items) == "":
			items.append(it)
			return it
	var it0 := item(C, id, band(C, b, lx, u), fc, tag, {"b": b["name"]})
	_free(C, it0, items)
	return {}


## 住まい：静かに——鉢植え・天水桶（3 軒に 1 軒は何も置かない）；職の家（res_work）は戸口の脇に小さな仕事場（藁細工／板材と道具箱／洗い桶）
static func _residence(C: Dictionary, b: Dictionary, items: Array, anchors: Array, rng: RandomNumberGenerator, work: bool) -> void:
	var w := float(b["w"])
	var dcx := float(b["door_cx"])
	var az: Vector2 = b["az"]
	var side := 1.0 if dcx < 0.0 else -1.0
	var hv := absi(hash(String(b["name"])))
	var ids: Array = [["sz_hachi", 0.5], ["sk_tensui", 1.1]] if hv % 3 == 0 else ([["sz_hachi", 0.5], ["sz_hachi", 1.05]] if hv % 3 == 1 else [])
	if work:
		ids = [[["st_wara", 1.55], ["kr_zaimoku", 1.85], ["kr_okeyama", 1.3]][hv % 3]]
		if hv % 3 == 1:
			ids.append(["sk_box", 0.6])
	for e: Array in ids:
		var id: String = e[0]
		var lx := dcx + side * (DOOR_HW + float(e[1]))
		if absf(lx) > w * 0.5 - 0.2:
			lx = dcx - side * (DOOR_HW + float(e[1]))
		var it := _put(C, b, items, "res_work" if work else "res", id, lx, float(BOX[id][1]) - float(BOX[id][3]) + 0.08)
		if work and not it.is_empty() and id != "sk_box":
			var b1: Array = BOX[id]
			anchors.append({"id": "st_worker_%s" % String(b["name"]).trim_prefix("B_P_"), "activity": "worker_craft",
				"p": local_to_world(it, Vector2(0.0, float(b1[3]) + float(b1[1]) + 0.45)), "yaw": float(it["yaw"]) + PI, "ref": id})


## 暮らしの点景：井戸端（井戸＋盥）と干し竿——路口・巷口の脇の空き地（平らな空きを探して置く）
static func _life(C: Dictionary, items: Array, anchors: Array) -> void:
	var spots := [
		["ido_south", "st_ido", Vector2(236.2, 41.7), Vector2(0.99, 0.15)],
		["ido_midlane", "st_ido", Vector2(269.3, -88.2), Vector2(0.93, 0.37)],
		["hoshi_gate", "mk_hoshimono", Vector2(230.4, 80.6), Vector2(1, 0.08)],
		["hoshi_north", "mk_hoshimono", Vector2(274.0, -79.6), Vector2(0.96, 0.29)],
	]
	for sp: Array in spots:
		var r := 0.0
		var done := false
		while r <= 2.5 and not done:
			for k in (1 if r == 0.0 else 12):
				var a := TAU * k / 12.0
				var it := item(C, sp[1], (sp[2] as Vector2) + Vector2(cos(a), sin(a)) * r, sp[3], "life:" + String(sp[0]))
				if relief(C, it) <= 0.15 and why(C, it, items, false) == "":
					items.append(it)
					if String(sp[1]) == "st_ido":
						anchors.append({"id": "st_well_" + String(sp[0]), "activity": "draw_water", "p": local_to_world(it, Vector2(-0.2, -1.0)), "yaw": float(it["yaw"]), "ref": "st_ido"})
					done = true
					break
			r += 0.5
		if not done:
			(C["dropped"] as Array).append("%s near %s 平らな空きなし [life:%s]" % [sp[1], str(sp[2]), sp[0]])


## 路口・巷口：道標（行き先）＋その先の用途を示す物
static func _crossings(C: Dictionary, items: Array, anchors: Array) -> void:
	var roads: Dictionary = C["roads"]
	# [道標の id、置く点（主街の路縁の角）、向き（道標の表＝主街側）、用途の物 [id, 位置ずれ, 向き]…]
	var spots := [
		# 中橫街 東：水車・稗田邸・田へ
		{"tag": "cross_mid_e", "fuda": "st_fuda_kawa", "p": Vector2(266.6, -16.6), "face": Vector2(-0.9, -0.45),
			"use": [["sk_teoke", Vector2(268.6, -17.2), Vector2(-1, -0.3)], ["wk_tawara3", Vector2(270.6, -16.9), Vector2(-0.3, -1)]]},
		# 南橫街 東：田畑
		{"tag": "cross_south_e", "fuda": "st_fuda_ta", "p": Vector2(246.2, 50.6), "face": Vector2(-0.95, 0.3),
			"use": [["st_kuwa", Vector2(249.6, 51.4), Vector2(0.05, -1)]]},
		# 丘腳街・參道：御社
		{"tag": "hillfoot", "fuda": "st_fuda_yashiro", "p": Vector2(295.6, -129.2), "face": Vector2(0.6, 0.8),
			"use": [["tk_okeyama", Vector2(293.6, -128.0), Vector2(0.8, 0.6)]]},
		# 中巷の口（主街西）：住まいの路地——天水桶・手桶
		{"tag": "midlane", "fuda": "", "p": Vector2(275.7, -86.4), "face": Vector2(1, -0.2),
			"use": [["sk_tensui", Vector2(277.0, -87.7), Vector2(1, -0.2)], ["sk_teoke", Vector2(275.4, -88.0), Vector2(1, -0.2)]]},
	]
	for sp: Dictionary in spots:
		if String(sp["fuda"]) != "":
			var it := item(C, sp["fuda"], sp["p"], sp["face"], "cross:" + String(sp["tag"]))
			if _free(C, it, items):
				items.append(it)
		for u: Array in sp["use"]:
			var it2 := item(C, u[0], u[1], u[2], "cross:" + String(sp["tag"]))
			if _free(C, it2, items):
				items.append(it2)


## 市の入口（主街側）：辻の北西の角店 MKT_023 の店先帯（主街に面する）——南の角に大看板（主街へ向く）、角の路縁に幟「市」、北の端に赤提灯
static func _market_corner(C: Dictionary, items: Array, anchors: Array) -> void:
	var b: Dictionary = {}
	for x: Dictionary in C["bld"]:
		if String(x["name"]) == "B_P_MKT_023":
			b = x
	if b.is_empty():
		return
	var w := float(b["w"])
	var south := signf((b["ax"] as Vector2).y)            # +lx が南（中橫街）側なら +1
	var tag := "market_lead"
	# 赤提灯の吊り綱を主街の路縁に沿って（高さ 2.6–3.2 m の赤い帯＝南北どちらからも見える）→ 角を回って中橫街の口まで続く
	var ln := item(C, "mk_chochin_line", band(C, b, 0.0, 0.45), b["az"], tag, {"b": b["name"]})
	if _free(C, ln, items):
		items.append(ln)
	_put(C, b, items, tag, "st_ichi_kanban", south * 1.45, 0.32)
	# 角（主街の路縁×中橫街）に大幟「市 此方」（布 3.0–7.4 m＝軒より上、主街の南北どちらからも正面に読める向き；布は路面側へ出す）
	var az: Vector2 = b["az"]
	var nb := item(C, "st_onobori_ichi", band(C, b, south * (w * 0.5 + 0.35), 0.35), Vector2(-az.y, az.x), tag, {"b": b["name"]})
	if _free(C, nb, items):
		items.append(nb)


## 市の入口：主街の辻（中橫街）→ 中橫街の北の縁 → 12 m の口。大看板・道標・赤提灯・吊り提灯・幟・荷車・届いた荷
static func _market_lead(C: Dictionary, items: Array, anchors: Array) -> void:
	var tag := "market_lead"
	var add := func(id: String, p: Vector2, face: Vector2) -> Dictionary:
		var it := item(C, id, p, face, tag)
		if _free(C, it, items):
			items.append(it)
			return it
		return {}
	# 辻の北西角（主街の西縁・中橫街の北縁）：大看板を主街へ向け、道標「市此方」
	add.call("st_fuda_ichi", Vector2(260.6, -25.4), Vector2(1, 0.3))
	# 中橫街の北の縁に沿って赤提灯の竿 2（腕木は建物側）と吊り提灯の綱（口の東の角の上）
	add.call("mk_chochin_line", Vector2(256.0, -23.6), Vector2(0, 1))
	add.call("mk_chochin_line", Vector2(250.6, -23.6), Vector2(0, 1))
	# 口の東の角：荷を積んだ大八車（中橫街に沿って駐める）と届いた荷・俵・麻袋
	var kur: Dictionary = add.call("mk_kuruma_ni", Vector2(253.6, -24.6), Vector2(-1, 0.02))
	add.call("st_kago_tsumi", Vector2(250.6, -25.3), Vector2(0, 1))
	add.call("wk_tawara3", Vector2(249.0, -25.7), Vector2(0.2, 1))
	var ki: Dictionary = {}
	for it: Dictionary in items:
		if String(it["id"]) == "st_ichi_kanban" and String(it["tag"]) == "market_lead":
			ki = it
	if not ki.is_empty():
		anchors.append({"id": "st_barker_ichi", "activity": "barker_call", "p": local_to_world(ki, Vector2(-0.9, 0.8)), "yaw": float(ki["yaw"]), "ref": "st_ichi_kanban"})
	if not kur.is_empty():
		anchors.append({"id": "st_porter_ichi", "activity": "porter_unload", "p": local_to_world(kur, Vector2(-0.95, 0.4)), "yaw": float(kur["yaw"]) + PI * 0.5, "ref": "mk_kuruma_ni"})


## 道端の作業場：主街から見える空き地・角地に、桶屋・大工・藁細工・薪（固定の候補点を規劃で検証）
static func _workspaces(C: Dictionary, items: Array, anchors: Array, rng: RandomNumberGenerator) -> void:
	var cands := [
		["st_okeya", Vector2(247.4, 41.3), Vector2(-0.95, -0.32)],
		["st_daiku", Vector2(229.4, 92.6), Vector2(1, 0.08)],
		["st_wara", Vector2(230.3, 43.8), Vector2(0.99, 0.15)],
		["st_daiku", Vector2(284.6, -76.1), Vector2(-0.96, -0.29)],
	]
	for c: Array in cands:
		var it := item(C, c[0], c[1], c[2], "work")
		if _free(C, it, items, false):
			items.append(it)
			var b0: Array = BOX[String(c[0])]
			anchors.append({"id": "st_worker_%d" % items.size(), "activity": "worker_craft", "p": local_to_world(it, Vector2(0.0, float(b0[3]) + float(b0[1]) + 0.45)),
				"yaw": float(it["yaw"]) + PI, "ref": c[0]})


## 足元の起伏（可見最上面の最大−最小）
static func relief(C: Dictionary, it: Dictionary) -> float:
	var hs: Array = [top_h(C, it["p"])]
	for poly: PackedVector2Array in polys(it):
		for q: Vector2 in poly:
			hs.append(top_h(C, q))
	return float(hs.max()) - float(hs.min())


## 田までの距離（48 方向 × 1.5 m 刻み、24 m まで；田の中＝0、見つからない＝99）——田と村の間は水渠（P2／P7）なので村側の段に置く
static func farm_dist(C: Dictionary, p: Vector2) -> float:
	var FS: RLib.TriSampler = C["FS"]
	if not is_nan(FS.h(p.x, p.y)):
		return 0.0
	var rr := 1.5
	while rr <= 24.0:
		for k in 48:
			var a := TAU * k / 48.0
			var q := p + Vector2(cos(a), sin(a)) * rr
			if not is_nan(FS.h(q.x, q.y)):
				return rr
		rr += 1.5
	return 99.0


## 中心 c のまわり（0.5 m 刻みの輪、16 方向）で、空き・平ら（起伏 ≤ 0.12 m）・田の外の置き場所を探す
static func _spot(C: Dictionary, items: Array, id: String, c: Vector2, face: Vector2, tag: String, rmax := 7.0, yref := NAN) -> Dictionary:
	var FS: RLib.TriSampler = C["FS"]
	var r := 0.0
	while r <= rmax:
		var n := 1 if r == 0.0 else 16
		for k in n:
			var a := TAU * k / 16.0
			var it := item(C, id, c + Vector2(cos(a), sin(a)) * r, face, tag)
			if relief(C, it) > 0.12 or (not is_nan(yref) and absf(float(it["y"]) - yref) > 0.6) or farm_dist(C, it["p"]) > 24.0:
				continue
			var on_farm := false
			for poly: PackedVector2Array in polys(it):
				for q in _poly_samples(poly, 0.3):
					if not is_nan(FS.h(q.x, q.y)):
						on_farm = true
			if on_farm or why(C, it, items, false) != "":
				continue
			items.append(it)
			return it
		r += 0.5
	(C["dropped"] as Array).append("%s near (%.1f,%.1f) 平らな空きなし [%s]" % [id, c.x, c.y, tag])
	return {}


## 農田→住宅の境：農具掛け・稲架・藁塚・柴垣・俵（4 か所；田の縁の平らな所を探して置く）
static func _farm_edges(C: Dictionary, items: Array, anchors: Array) -> void:
	# [名, 中心, 向き（住宅側を向く面）, [[id, 中心からのずれ（田に沿う x・住宅側 z）]…]]——水渠の村側の段（実測：起伏 ≤ 0.1 m、田まで 16–24 m、家の裏 8–14 m）
	var spots := [
		["farm_mid", Vector2(320.5, -23.0), Vector2(-1, 0), [["st_hasa", Vector2(0, 0)], ["st_warazuka", Vector2(3.4, 1.8)], ["st_kuwa", Vector2(-3.0, 1.6)], ["st_shibagaki", Vector2(0.4, -1.8)]]],
		["farm_hill", Vector2(331.0, -104.0), Vector2(-1, 0), [["st_hasa", Vector2(0, 0)], ["st_warazuka", Vector2(3.4, 1.6)], ["st_kuwa", Vector2(-2.8, 1.4)], ["st_shibagaki", Vector2(0.4, -1.8)]]],
		["farm_east", Vector2(323.5, -88.0), Vector2(-1, 0), [["st_hasa", Vector2(0, 0)], ["st_warazuka", Vector2(-3.4, 1.6)], ["wk_tawara3", Vector2(2.6, 1.4)]]],
		["farm_south", Vector2(311.0, 23.0), Vector2(-1, 0), [["st_hasa", Vector2(0, 0)], ["st_warazuka", Vector2(3.4, 1.8)], ["wk_tawara3", Vector2(-2.6, 1.5)], ["st_shibagaki", Vector2(0.2, -1.8)]]],
	]
	for sp: Array in spots:
		var face: Vector2 = (sp[2] as Vector2).normalized()
		var along := Vector2(-face.y, face.x)
		var first: Dictionary = {}
		for e: Array in sp[3]:
			var off: Vector2 = e[1]
			var c: Vector2 = (sp[1] as Vector2) + along * off.x + face * off.y
			var it := _spot(C, items, e[0], c, face, "farm:" + String(sp[0]), 4.0, NAN if first.is_empty() else float(first["y"]))
			if first.is_empty() and not it.is_empty():
				first = it
		if not first.is_empty():
			var b0: Array = BOX[String(first["id"])]
			for t: Vector2 in [Vector2(0.0, 1.0), Vector2(1.2, 1.0), Vector2(-1.2, 1.0), Vector2(0.0, 1.6), Vector2(2.4, 0.8)]:
				var ap := local_to_world(first, Vector2(t.x, float(b0[1]) + t.y))
				if not items.any(func(o: Dictionary) -> bool: return polys(o).any(func(pl: PackedVector2Array) -> bool: return Geometry2D.is_point_in_polygon(ap, pl))):
					anchors.append({"id": "st_farmer_" + String(sp[0]), "activity": "farmer_work", "p": ap, "yaw": float(first["yaw"]) + PI, "ref": first["id"]})
					break


# ─────────────────────────── 烘焙 ───────────────────────────

static func bake(P: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = NODE_NAME
	var groups := {}
	for nm: String in ["Shopfront", "Signs", "Residence", "Crossings", "MarketLead", "Work", "FarmEdge", "Anchors"]:
		var n := Node3D.new()
		n.name = nm
		root.add_child(n)
		groups[nm] = n
	var col := StaticBody3D.new()
	col.name = "Collision"
	root.add_child(col)
	var meshes := {}
	var n_i := 0
	var ns := 0
	for it: Dictionary in P["items"]:
		var id := String(it["id"])
		var tg := String(it["tag"])
		var node := Node3D.new()
		node.name = "%03d_%s" % [n_i, id]
		node.transform = Transform3D(Basis(Vector3.UP, float(it["yaw"])), Vector3((it["p"] as Vector2).x, float(it["y"]), (it["p"] as Vector2).y))
		node.set_meta("st_id", id)
		node.set_meta("st_tag", tg)
		if it.has("b"):
			node.set_meta("building", String(it["b"]))
		var grp := "Shopfront"
		if tg == "market_lead":
			grp = "MarketLead"
		elif tg.begins_with("cross"):
			grp = "Crossings"
		elif tg == "work":
			grp = "Work"
		elif tg.begins_with("farm"):
			grp = "FarmEdge"
		elif tg == "res" or tg == "fire" or tg == "res_work" or tg.begins_with("life"):
			grp = "Residence"
		elif id.contains("nobori") or id.contains("kanban") or id.contains("andon") or id.contains("chochin") or id == "mk_bangasa":
			grp = "Signs"
		(groups[grp] as Node).add_child(node)
		for lod in 2:
			var key := id + ("_l1" if lod == 1 else "")
			if not meshes.has(key):
				meshes[key] = load(mesh_dir(id) + key + ".res")
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % lod
			mi.mesh = meshes[key]
			mi.visibility_range_begin = 0.0 if lod == 0 else LOD_SWITCH
			mi.visibility_range_end = LOD_SWITCH if lod == 0 else 200.0
			if lod == 1:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
		if id in LINE:
			for sx in [-2.5, 2.5]:
				var pb := BoxShape3D.new()
				pb.size = Vector3(0.12, 3.3, 0.12)
				var pcs := CollisionShape3D.new()
				pcs.name = "%s_c%d" % [node.name, 0 if sx < 0 else 1]
				pcs.shape = pb
				var pba := Basis(Vector3.UP, float(it["yaw"]))
				pcs.transform = Transform3D(pba, node.transform.origin + pba * Vector3(sx, 1.65, 0.0))
				col.add_child(pcs)
				ns += 1
		elif not (id in NO_COLLIDE):
			var b: Array = BOX[id]
			var bx := BoxShape3D.new()
			bx.size = Vector3(float(b[0]) * 2.0, float(b[2]), float(b[1]) * 2.0)
			var cs := CollisionShape3D.new()
			cs.name = "%s_c" % node.name
			cs.shape = bx
			var ba := Basis(Vector3.UP, float(it["yaw"]))
			cs.transform = Transform3D(ba, node.transform.origin + ba * Vector3(float(b[4]), float(b[2]) * 0.5, float(b[3])))
			col.add_child(cs)
			ns += 1
		n_i += 1
	var C: Dictionary = P["C"]
	for a: Dictionary in P["anchors"]:
		var mk := Marker3D.new()
		mk.name = String(a["id"])
		var p: Vector2 = a["p"]
		mk.transform = Transform3D(Basis(Vector3.UP, float(a["yaw"])), Vector3(p.x, top_h(C, p), p.y))
		mk.set_meta("activity", String(a["activity"]))
		mk.set_meta("ref", String(a["ref"]))
		mk.add_to_group("npc_activity_anchor", true)
		(groups["Anchors"] as Node).add_child(mk)
	root.set_meta("items", (P["items"] as Array).size())
	root.set_meta("anchors", (P["anchors"] as Array).size())
	root.set_meta("shapes", ns)
	root.set_meta("art_revision", "P10 R2 主街 Street Life r1（ART_REVIEW 前）")
	return root


static func own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		if c.scene_file_path == "":
			own(c, owner)
