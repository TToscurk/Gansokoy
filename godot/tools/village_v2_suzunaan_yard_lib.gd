extends RefCounted
## 人間之里 V2 P9 R4-6 Hero Surroundings：鈴奈庵周邊（ART-FIRST）。
##   規劃（plan）＋烘焙（bake）→ maps/village_v2/gen/suzunaan_p9.scn → village_v2.tscn 掛 Vegetation/SuzunaanP9
##   （ForestP9 → BambooP9 → HiedaGardenP9 → ShrineGroveP9 → SchoolYardP9 → WatersideP9 → TowerYardP9 → SuzunaanP9）。
##   讀感＝「書店／貸本屋：借りに来た人が立ち止まって使う」：庭園でも市集でもない。
##   鈴奈庵 Hero 本體（P5 R1：踏石・縁台・花盆・木箱・竪樋・勝手口踏石を含む）不動；P3 地塊／道路／地形、R1–R4-5 封存內容不動。
##   新構件＝suzu_kit（置き看板「貸本」／掲示板／本箱／書冊束／腰掛け／虫干しの縁台／背負い本箱／鉢植え）；
##   只讀重用：garden_kit 飛石（竪樋の雨受け石）、waterside_kit 菅（牆腳草）、R1 蕨・灌木 prefab、
##   R4-2 sg_ground shader（COLOR＝碎石, 苔, 踏み固め土, 落葉；UV2＝濕潤, 淡出）。
## 座標：Hero 局部（lx＝間口方向、+lx＝北妻側；lz＝奥行、+lz＝MainStreet 側正面）。Hero yaw 71.565°、原點 (247.18, −6.21)。
##   台基 lx ±4.55、lz ±4.095；庇の下の通路 lz 4.745–5.305；入口 lx 0；勝手口 lx 2.0（背面 lz −4.3）。
## 構成：
##   1 門前：入口の軸（lx ±1.0、店先→道）は空ける。三和土の踏み固め、庇の雨落ち（碎石、入口で切る）、竪樋の雨受け石＋濕り。
##     門前に足す構件は北の角の置き看板「貸本」だけ（Hero の縁台・木箱・花盆が既に店先を作っている）。
##   2 北側（主街から北へ来る人と横丁から見える「側面」）：壁の掲示板（新刊の表紙）→ 鉢植え・腰掛け（書冊束）→
##     虫干しの縁台 → 本箱 2＋1（勝手口への搬入）→ 勝手口の脇に背負い本箱。立ち止まる踏み固めと、横丁・主街から勝手口への踏み跡。
##   3 南側（隣家と狭い路地）：構件なし、牆腳の碎石と草だけ（留白）。
##   4 植生：牆腳の菅、背面日陰の蕨、北西の灌木 1、落葉は角だけ；看板・門面・二階の看板を遮らない。

const SG := preload("res://tools/village_v2_shrine_grove_lib.gd")
const GL := preload("res://tools/village_v2_hieda_garden_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const FLib := preload("res://tools/village_v2_forest_lib.gd")

const OUTPUT := "res://maps/village_v2/gen/suzunaan_p9.scn"
const NODE_NAME := "SuzunaanP9"
const ZK := "res://assets/village_v2/suzu_kit/mesh/"
const GK := "res://assets/village_v2/garden_kit/mesh/"
const WK := "res://assets/village_v2/waterside_kit/mesh/"
const PARCELS := "res://maps/village_v2/gen/parcels.json"
const ASSET := "res://assets/village_v2/suzunaan/asset.json"
const HERO_PATH := "Landmarks/LANDMARK_SUZUNAAN/Hero"
const SEED := 4661
const LOD_SWITCH := 30.0

## Hero 局部座標系（場景同源：plan() で Hero の global_transform と照合、ずれ > 1 cm は gate FAIL）
const HO := Vector2(247.1825, -6.205828)
const BX := Vector2(0.316228, -0.948683)
const BZ := Vector2(0.948683, 0.316228)
const HALF := Vector2(4.55, 4.095)
const PARCEL_ID := "P_LM_SUZUNAAN"
## 動線（局部）：入口の軸、庇の下の通路、北側の踏み跡（主街の角 → 掲示板前 → 北西角 → 勝手口）、横丁からの踏み跡
const ENTRY := [Vector2(0.0, 6.6), Vector2(0.0, 4.6)]
const ENTRY_HW := 1.0
const WALK := Rect2(-4.55, 4.745, 9.1, 0.56)
const PATH_N := [Vector2(6.7, 6.6), Vector2(6.8, 3.0), Vector2(6.7, -1.5), Vector2(6.3, -4.3), Vector2(5.2, -5.6), Vector2(2.6, -5.35), Vector2(2.0, -4.9)]
const PATH_X := [Vector2(11.5, 2.2), Vector2(6.9, 1.4)]
const PATH_HW := 0.45
const BACKDOOR := Rect2(1.4, -5.3, 1.2, 1.2)
## 立ち止まる場所（掲示板・腰掛け・縁台の前）
const STAY := Vector2(6.4, 0.9)
const STAY_R := Vector2(1.5, 2.1)
## 北側の留白ゾーン（局部）：構件・植生の占有 ≤ 25 %
const NORTH_YARD := Rect2(4.55, -4.1, 5.45, 8.2)
const REGION := Rect2(238.0, -18.0, 19.0, 22.0)

const UNDER_IDS := ["fern_a", "shrub_a"]
const PLANT_IDS := ["wk_sedge"]
const GROUND_IDS := ["gk_tobi_d", "gk_amaochi"]
const LOW_MAX_H := 1.3
## 構件外框（model 半寬 x、半奥 z、高、z 中心オフセット）＝碰撞箱
const PROP_BOX := {"sz_kanban": [0.33, 0.25, 1.84, 0.0], "sz_keiji": [0.78, 0.185, 1.85, 0.12], "sz_hako": [0.314, 0.2, 0.34, 0.0],
	"sz_hako2": [0.33, 0.24, 0.68, 0.0], "sz_bundle": [0.11, 0.15, 0.13, 0.0], "sz_stool": [0.21, 0.13, 0.40, 0.0],
	"sz_dai": [0.70, 0.30, 0.47, 0.0], "sz_seoi": [0.25, 0.25, 1.10, -0.08], "sz_hachi": [0.15, 0.15, 0.62, 0.0],
	"gk_tobi_d": [0.24, 0.2, 0.07, 0.0], "gk_amaochi": [0.44, 0.05, 0.05, 0.0]}
const NO_COLLIDE := ["sz_bundle", "sz_hachi", "gk_tobi_d", "gk_amaochi"]


static func W(lx: float, lz: float) -> Vector2:
	return HO + BX * lx + BZ * lz


static func Lc(p: Vector2) -> Vector2:
	return Vector2((p - HO).dot(BX), (p - HO).dot(BZ))


## 局部の向き（dlx, dlz）に model +z を向ける yaw
static func yaw_l(d: Vector2) -> float:
	var w := BX * d.x + BZ * d.y
	return atan2(w.x, w.y)


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
	var b: Array = PROP_BOX.get(String(it["id"]), [0.12, 0.12, 0.1, 0.0])
	var s: float = (it["sc"] as Vector3).x
	var c := cos(float(it["yaw"]))
	var sn := sin(float(it["yaw"]))
	var out := PackedVector2Array()
	for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var lx := q.x * float(b[0]) * s
		var lz := (q.y * float(b[1]) + float(b[3])) * s
		out.append((it["p"] as Vector2) + Vector2(lx * c + lz * sn, -lx * sn + lz * c))
	return out


static func rect_d(r: Rect2, p: Vector2) -> float:
	var dx := maxf(r.position.x - p.x, p.x - r.end.x)
	var dz := maxf(r.position.y - p.y, p.y - r.end.y)
	if dx <= 0.0 and dz <= 0.0:
		return maxf(dx, dz)
	return Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length()


static func foot_d(q: Vector2) -> float:
	## 台基（局部 ±HALF）までの符號距離（外＋）
	return rect_d(Rect2(-HALF, HALF * 2.0), q)


## Hero（場景同源）：Collision の BoxShape を OBB で、asset.json の地面部品（竪樋・花盆…）を局部矩形で
static func hero_obbs(v: Node3D) -> Array:
	var out: Array = []
	for cs in v.get_node(HERO_PATH).get_parent().find_children("*", "CollisionShape3D", true, false):
		var sh := (cs as CollisionShape3D).shape
		if not (sh is BoxShape3D) or not (cs as Node3D).is_inside_tree():
			continue
		if not String(v.get_path_to(cs)).begins_with(HERO_PATH):
			continue
		out.append([String(cs.name), (cs as Node3D).global_transform, (sh as BoxShape3D).size * 0.5])
	return out


static func hero_parts() -> Array:
	var A: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSET))
	var out: Array = []
	for g: Dictionary in A["gate_spec"]["ground"]:
		var r: Array = g["rect"]
		out.append([String(g["name"]), Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1]))])
	return out


static func in_obb(p: Vector2, o: Array, grow: float) -> bool:
	var xf: Transform3D = o[1]
	var h: Vector3 = o[2]
	var l := xf.affine_inverse() * Vector3(p.x, xf.origin.y, p.y)
	return absf(l.x) <= h.x + grow and absf(l.z) <= h.z + grow


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
		if REGION.grow(4.0).intersects(r):
			out.append(r)
	return out


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
	var yo := yaw_l(Vector2(1.0, 0.0))      # 北妻の外へ向く
	# ── 門前：北の角に置き看板「貸本」（主街の両方向から読める斜め向き）；竪樋の雨受け石 2
	# 板面は主街と南（日の来る側）の間へ向ける：東向きだと日が當たらず黒い板になる（太陽は南の高所）
	items.append(item(S, "mesh", "sz_kanban", W(5.55, 5.2), yaw_l(Vector2(-0.585, 0.811)), 1.0, "front"))
	for sx: float in [-1.0, 1.0]:
		var it := item(S, "mesh", "gk_tobi_d", W(sx * 4.75, 4.98), yaw_l(Vector2(0.0, 1.0)) + rng.randf_range(-0.3, 0.3), 1.0, "drain")
		it["y"] = S.h((it["p"] as Vector2).x, (it["p"] as Vector2).y) - 0.03
		items.append(it)
	# 庇の雨落ち：道側の縁を縁石で切る（入口 |lx| < 1.1 と竪樋の雨受け石の所は空ける）
	for sx: float in [-1.0, 1.0]:
		for k in 4:
			var lx := sx * (1.55 + k * 0.8)
			var it := item(S, "mesh", "gk_amaochi", W(lx, 5.27), yaw_l(Vector2(0.0, 1.0)) + rng.randf_range(-0.03, 0.03), 1.0, "drain")
			it["y"] = S.h((it["p"] as Vector2).x, (it["p"] as Vector2).y) + 0.02
			items.append(it)
	# ── 北側：掲示板（壁際）→ 鉢植え・腰掛け＋書冊束 → 虫干しの縁台 → 本箱 → 勝手口の背負い本箱
	items.append(item(S, "mesh", "sz_keiji", W(4.68, 1.9), yo, 1.0, "side"))
	items.append(item(S, "mesh", "sz_hachi", W(4.85, 0.75), rng.randf() * TAU, 1.0, "side"))
	var st := item(S, "mesh", "sz_stool", W(5.75, 0.25), yaw_l(Vector2(0.8, -0.6)), 1.0, "side")
	items.append(st)
	var bd := item(S, "mesh", "sz_bundle", W(5.76, 0.27), yaw_l(Vector2(0.7, -0.7)) + 0.25, 1.0, "side", {"on": "sz_stool", "on_h": 0.40})
	bd["y"] = float(st["y"]) + 0.40
	items.append(bd)
	# 虫干しの縁台は壁と屋根の影（北へ 2.5–3 m、F5 實測）の外、踏み跡の向こうの日の當たる所へ
	items.append(item(S, "mesh", "sz_dai", W(8.1, -0.6), -yo, 1.0, "side"))
	items.append(item(S, "mesh", "sz_hako2", W(5.0, -3.0), yo + 0.06, 1.0, "side"))
	items.append(item(S, "mesh", "sz_hako", W(5.55, -3.75), yo - 0.42, 1.0, "side"))
	items.append(item(S, "mesh", "sz_seoi", W(3.35, -4.47), yaw_l(Vector2(0.0, -1.0)), 1.0, "back"))
	# ── 低い植生：背面日陰の蕨、北の壁際の蕨 1、北西の灌木 1（看板・門面から離す）
	for q: Array in [["fern_a", Vector2(-2.6, -4.6), 0.7], ["fern_a", Vector2(0.0, -4.7), 0.6], ["fern_a", Vector2(4.85, -2.2), 0.55],
			["shrub_a", Vector2(9.6, -3.0), 0.55]]:
		items.append(item(S, "tree", String(q[0]), W((q[1] as Vector2).x, (q[1] as Vector2).y), rng.randf() * TAU, float(q[2]),
			"low", {"preset": "mature"}))
	# 牆腳の菅（叢；道と入口には置かない）
	for q: Vector2 in [Vector2(4.72, 3.55), Vector2(4.75, -3.75), Vector2(-0.9, -4.35), Vector2(-3.6, -4.35), Vector2(4.3, -4.35),
			Vector2(-4.75, 2.6), Vector2(-4.8, -0.4), Vector2(-4.75, -2.8), Vector2(9.4, 2.8), Vector2(9.3, 0.9), Vector2(9.5, -1.9),
			Vector2(-4.95, 4.0)]:
		var it := item(S, "plant", "wk_sedge", W(q.x, q.y) + Vector2(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.08, 0.08)),
			rng.randf() * TAU, rng.randf_range(0.7, 1.0), "weed")
		it["y"] = S.h((it["p"] as Vector2).x, (it["p"] as Vector2).y) - 0.03
		items.append(it)
	var hx := (v.get_node(HERO_PATH) as Node3D).global_transform
	return {"items": items, "S": S, "R": R, "M": M, "obb": hero_obbs(v), "parts": hero_parts(), "bld": building_rects(v),
		"pp": other_parcels(), "hero_xf": hx, "ms": Time.get_ticks_msec() - t0}


# ─────────────────────────── 地面 overlay（sg_ground：COLOR＝碎石, 苔, 踏み固め土, 落葉；UV2＝濕潤, 淡出） ───────────────────────────

const G_STEP := 0.4


static func _n(p: Vector2, a: float) -> float:
	return 0.5 + 0.35 * sin(p.x * 0.83 * a + p.y * 0.37) * sin(p.y * 0.71 * a - p.x * 0.29) + 0.15 * sin(p.x * 2.3 * a - p.y * 1.9)


static func ground_w(P: Dictionary, p: Vector2) -> Variant:
	var q := Lc(p)
	var nz := _n(p, 1.0)
	var warp := 0.9 * (nz - 0.5) + 0.35 * sin(p.x * 1.1 - p.y * 0.7)
	# 範囲：台基の周り（南 1.6 m・背面 2.2 m・正面は道まで・北は横丁側 4.6 m）＋横丁からの踏み跡；外へ 2.0 m で淡出
	var zone := Rect2(-6.2, -6.5, 16.4, 13.4)
	var dz := rect_d(zone, q)
	var dx := GL.line_d(PATH_X, q).x - 1.0
	var dmin := minf(dz, dx) + warp * 0.7
	var f := 1.0 - smoothstep(0.0, 2.0, dmin)
	if f <= 0.0:
		return null
	var gv := 0.0
	var mo := 0.0
	var so := 0.0
	var li := 0.0
	var wet := 0.06
	var fd := foot_d(q)
	# 雜草斑（shader の殘り＝草）：ゾーン縁と南の路地・背面の奥だけ、低周波雜訊の高いところ
	var gr := 0.0
	var nw := _n(p * 0.6 + Vector2(31.0, 7.0), 1.7)
	var edge := -dz
	if (edge < 1.6 or q.x < -5.0 or q.y < -5.4) and nw > 0.5:
		gr = 0.75 * smoothstep(0.5, 0.72, nw)
	# 地塊全体：薄い踏み固め土（ただし特徴のない所は overlay を透明にして地形の土と草をそのまま見せる：fm）
	so = 0.3 + 0.2 * nz
	var fm := 0.0
	# 牆腳：台基の外 0.45 m は碎石まじりの濕った土（北妻・背面は苔）
	if fd < 0.5:
		var kw := 1.0 - smoothstep(0.12, 0.5, fd + 0.12 * (nz - 0.5))
		gv = maxf(gv, 0.55 * kw)
		so = maxf(so, 0.5 * kw)
		wet = maxf(wet, 0.14 * kw)
		fm = maxf(fm, 0.8 * kw)
		gr *= 1.0 - kw
		if q.x > HALF.x - 0.05:
			mo = maxf(mo, 0.38 * kw)
		elif q.y < -HALF.y + 0.05:
			mo = maxf(mo, 0.25 * kw)
	# 門前：三和土（道まで、台基の間口＋0.7）、入口の軸はもっと固い
	if q.y > HALF.y - 0.05 and absf(q.x) < HALF.x + 0.7:
		var kf := 1.0 - smoothstep(HALF.x, HALF.x + 0.7, absf(q.x))
		so = maxf(so, 0.62 * kf)
		gv = maxf(gv, 0.38 * kf)
		fm = maxf(fm, kf)
		gr *= 1.0 - kf
		if absf(q.x) < ENTRY_HW + 0.3:
			so = maxf(so, 0.9 * (1.0 - smoothstep(ENTRY_HW - 0.2, ENTRY_HW + 0.3, absf(q.x))))
			gr = 0.0
	# 庇の雨落ち（碎石の線、入口では切る）
	var dd := absf(q.y - 5.05)
	if dd < 0.22 and absf(q.x) < HALF.x + 0.1 and absf(q.x) > ENTRY_HW - 0.1:
		var kd := (1.0 - smoothstep(0.07, 0.22, dd)) * smoothstep(ENTRY_HW - 0.1, ENTRY_HW + 0.25, absf(q.x))
		gv = maxf(gv, 0.95 * kd)
		wet = maxf(wet, 0.35 * kd)
		fm = maxf(fm, kd)
	# 背面の雨落ち（勝手口の前は踏み固め）
	var db := absf(q.y + 4.55)
	if db < 0.22 and absf(q.x) < HALF.x + 0.1:
		var kb := (1.0 - smoothstep(0.07, 0.22, db)) * smoothstep(0.35, 0.7, absf(q.x - 2.0))
		gv = maxf(gv, 0.75 * kb)
		wet = maxf(wet, 0.3 * kb)
		fm = maxf(fm, kb)
	# 竪樋の雨受け：濕り＋碎石
	for sx: float in [-1.0, 1.0]:
		var ds := q.distance_to(Vector2(sx * 4.75, 4.9))
		if ds < 0.85:
			var ks := 1.0 - smoothstep(0.2, 0.85, ds)
			wet = maxf(wet, 0.85 * ks)
			gv = maxf(gv, 0.45 * ks)
			fm = maxf(fm, ks)
			gr *= 1.0 - ks
	# 踏み跡：北の角 → 掲示板前 → 北西角 → 勝手口、横丁から立ち止まる場所へ
	var dpn := minf(GL.line_d(PATH_N, q).x, GL.line_d(PATH_X, q).x)
	var pw := 0.55 + 0.18 * (nz - 0.5)
	if dpn < pw + 0.6:
		var kp := 1.0 - smoothstep(pw * 0.5, pw + 0.6, dpn)
		so = maxf(so, 0.6 * kp)
		gv = maxf(gv, 0.48 * (1.0 - smoothstep(pw * 0.25, pw + 0.2, dpn)))
		fm = maxf(fm, kp)
		gr *= 1.0 - kp
	# 立ち止まる場所（掲示板・腰掛け・縁台の前）と看板の角
	var e := ((q - STAY) / STAY_R).length()
	if e < 1.3:
		var ke := 1.0 - smoothstep(0.5, 1.3, e + 0.2 * (nz - 0.5))
		so = maxf(so, 0.62 * ke)
		gv = maxf(gv, 0.4 * ke)
		fm = maxf(fm, ke)
		gr *= smoothstep(0.6, 1.3, e)
	var dk := q.distance_to(Vector2(5.7, 5.4))
	if dk < 1.6:
		so = maxf(so, 0.75 * (1.0 - smoothstep(0.6, 1.6, dk)))
		fm = maxf(fm, 1.0 - smoothstep(0.6, 1.6, dk))
		gr *= smoothstep(0.6, 1.6, dk)
	# 勝手口の前
	var dbk := rect_d(BACKDOOR, q)
	if dbk < 0.6:
		so = maxf(so, 0.85 * (1.0 - smoothstep(0.0, 0.6, dbk)))
		fm = maxf(fm, 1.0 - smoothstep(0.0, 0.6, dbk))
		gr = 0.0
	# 落葉：北西の角・南の路地の奥・背面の角だけ
	for lc: Vector2 in [Vector2(6.0, -4.9), Vector2(-5.4, -3.6), Vector2(-4.2, -5.2)]:
		var dl := q.distance_to(lc)
		if dl < 1.6:
			li = maxf(li, 0.35 * (1.0 - smoothstep(0.5, 1.6, dl)) * smoothstep(0.35, 0.6, _n(p * 2.1, 1.3)))
			fm = maxf(fm, li * 2.0)
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
	f *= smoothstep(0.0, 0.1, tot) * smoothstep(0.02, 0.4, fm)
	return [Color(gv, mo, so, li), Vector2(wet, f)]


## R4-4 で確立した格子縁なしの組み方：footprint 頂點排除＋網格邊緣 BFS 淡出＋權重 3×3 平滑；道路側の縁は淡出しない
static func ground_mesh(P: Dictionary) -> ArrayMesh:
	var S: RLib.TriSampler = P["S"]
	var R: RLib.TriSampler = P["R"]
	var boxes: Array = (P["bld"] as Array).duplicate()
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
			if foot_d(Lc(p)) < -0.08:
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
			var w2: Vector2 = (w as Array)[1]
			if roadx.has(Vector2i(i, j)):
				w2.y = 0.0          # 道路の上は透明：道路側の縁が 0.4 m で柔らかく消える（格子の段にしない）
			WG[Vector2i(i, j)] = [(w as Array)[0], w2]
	var NB := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
	var N4 := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
	var bd := {}
	var front: Array = []
	for g: Vector2i in WG:
		for d: Vector2i in NB:
			if roadx.has(g):
				continue
			if not WG.has(g + d) and not roadx.has(g + d):
				# 台基の際は淡出しない（壁腳の碎石を壁まで届かせる）
				var pq := REGION.position + Vector2((g + d).x * G_STEP, (g + d).y * G_STEP)
				if foot_d(Lc(pq)) < -0.08:
					continue
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
	m.resource_name = "SZ_Ground"
	# R4-2 sg_ground（只讀）の instance 參數：玉砂利 → 灰色の碎石（白く光らせない）
	m.set_shader_parameter("gravel_tint", Vector3(1.16, 1.11, 1.03))
	m.set_shader_parameter("gravel_contrast", 0.95)
	m.set_shader_parameter("gravel_sat", 0.4)
	m.set_shader_parameter("gravel_tile", 0.55)
	am.surface_set_material(0, m)
	am.resource_name = "sz_ground"
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
	for nm: String in ["Low", "Weeds", "Props", "Stones"]:
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
			t.set_meta("sz_tag", String(it["tag"]))
			(groups["Low"] as Node).add_child(t)
			n_i += 1
			continue
		var node := Node3D.new()
		node.name = "%03d_%s" % [n_i, id]
		node.transform = xf
		node.set_meta("sz_id", id)
		node.set_meta("sz_tag", String(it["tag"]))
		var grp := "Weeds" if id in PLANT_IDS else ("Stones" if id in GROUND_IDS else "Props")
		(groups[grp] as Node).add_child(node)
		var dir := ZK if id.begins_with("sz_") else (GK if id.begins_with("gk_") else WK)
		for lod in 2:
			var key := id + ("_l1" if lod == 1 else "")
			if not meshes.has(key):
				meshes[key] = load(dir + key + ".res")
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % lod
			mi.mesh = meshes[key]
			mi.visibility_range_begin = 0.0 if lod == 0 else LOD_SWITCH
			mi.visibility_range_end = LOD_SWITCH if lod == 0 else (80.0 if id in PLANT_IDS or id in GROUND_IDS else 180.0)
			if lod == 1 or id in ["wk_sedge", "gk_tobi_d", "sz_bundle"]:
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
			var ba := Basis(Vector3.UP, float(it["yaw"]))
			cs.transform = Transform3D(ba, xf.origin + ba * Vector3(0, float(b[2]) * s * 0.5, float(b[3]) * s))
			col.add_child(cs)
			ns += 1
		n_i += 1
	root.set_meta("items", (P["items"] as Array).size())
	root.set_meta("shapes", ns)
	root.set_meta("art_revision", "P9 R4-6 鈴奈庵周邊 r7（ART_REVIEW）")
	return root


static func own(n: Node, owner: Node) -> void:
	SG.own(n, owner)
