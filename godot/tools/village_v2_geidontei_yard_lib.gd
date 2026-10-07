extends RefCounted
## 人間之里 V2 P9 R4-7 Hero Surroundings：鯢吞亭周邊（ART-FIRST）。
##   規劃（plan）＋烘焙（bake）→ maps/village_v2/gen/geidontei_p9.scn → village_v2.tscn 掛 Vegetation/GeidonteiP9
##   （… → TowerYardP9 → SuzunaanP9 → GeidonteiP9）。
##   讀感＝「居酒屋：飲みに来た人が腰を下ろす、店の裏で仕込みをする」：庭園でも市集でもない。
##   鯢吞亭 Hero 本體（P5 R2：踏石・石燈籠・紅提燈・山椒魚の門・勝手口踏石を含む）不動；P3 地塊／道路／地形、R1–R4-6 封存內容不動。
##   新構件＝geidon_kit（菰樽積み／樽卓／緋毛氈の床几／盆と徳利／品書き／盛り塩）；
##   只讀重用：school_kit 手桶（打ち水）・薪棚・天水桶・木箱、waterside_kit 俵（仕入れ）・菅、suzu_kit 腰掛け、
##   garden_kit 雨落ち縁石、R1 蕨 prefab、R4-2 sg_ground。
## 座標：Hero 局部（lx＝間口、+lx＝南妻側〔開けた側〕；lz＝奥行、+lz＝MainStreet 側正面）。Hero yaw −106.7°、原點 (285.15, −61.84)。
##   台基 lx ±5.46、lz ±4.55；庇の下の通路 lz 5.20–5.76；入口 lx 0（扉 2.75 m）；石燈籠 lx ±4.75 lz 5.55；勝手口 lx 2.0（背面）。
## 構成：
##   1 門前：入口軸（|lx| < 1.4）と庇下の通路は空ける。打ち水で濕った三和土、雨落ちの碎石＋道側の縁石（入口と石燈籠で切る）、
##     入口の両脇に盛り塩、南の角に菰樽積み（主街の南から來る人に見せる）、北の軒下に打ち水の手桶。
##   2 南側（開けた側＝外の席）：南妻の壁に品書き → 緋毛氈の床几（盆・徳利）→ 樽卓（盆）＋腰掛け → 踏み跡（裏の勝手口へ）。
##   3 背面（仕込み場）：薪棚・木箱・俵 3・天水桶、勝手口前は踏み固め。
##   4 北側（隣の附屬地と狹い）：構件なし（牆腳の碎石と草だけ＝留白）。

const SG := preload("res://tools/village_v2_shrine_grove_lib.gd")
const GL := preload("res://tools/village_v2_hieda_garden_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const FLib := preload("res://tools/village_v2_forest_lib.gd")

const OUTPUT := "res://maps/village_v2/gen/geidontei_p9.scn"
const NODE_NAME := "GeidonteiP9"
const DK := "res://assets/village_v2/geidon_kit/mesh/"
const SK := "res://assets/village_v2/school_kit/mesh/"
const ZK := "res://assets/village_v2/suzu_kit/mesh/"
const GK := "res://assets/village_v2/garden_kit/mesh/"
const WK := "res://assets/village_v2/waterside_kit/mesh/"
const PARCELS := "res://maps/village_v2/gen/parcels.json"
const ASSET := "res://assets/village_v2/geidontei/asset.json"
const HERO_PATH := "Landmarks/LANDMARK_GEIDONTEI/Hero"
const SEED := 4771
const LOD_SWITCH := 30.0

## Hero 局部座標系（場景同源：gate で Hero の global_transform と照合、ずれ > 1 cm は FAIL）
const HO := Vector2(285.1476, -61.8357)
const BX := Vector2(-0.287348, 0.957826)
const BZ := Vector2(-0.957826, -0.287348)
const HALF := Vector2(5.46, 4.55)
const PARCEL_ID := "P_LM_GEIDONTEI"
## 動線（局部）：入口の軸、庇下の通路、南側の踏み跡（主街の南角 → 外の席 → 裏の勝手口）
const ENTRY := [Vector2(0.0, 7.0), Vector2(0.0, 5.0)]
const ENTRY_HW := 1.4
const WALK := Rect2(-3.95, 5.2, 7.9, 0.56)
const PATH_N := [Vector2(7.6, 6.5), Vector2(9.3, 2.5), Vector2(9.3, -2.5), Vector2(7.4, -6.4), Vector2(2.6, -6.4), Vector2(2.0, -5.3)]
const PATH_X := [Vector2(9.3, 2.2), Vector2(8.6, 2.4)]
const PATH_HW := 0.45
const BACKDOOR := Rect2(1.3, -6.0, 1.4, 1.4)
## 外の席（床几・樽卓の前）
const STAY := Vector2(7.6, 1.2)
const STAY_R := Vector2(1.3, 2.0)
## 南側の留白ゾーン（局部）：構件・植生の占有 ≤ 25 %
const NORTH_YARD := Rect2(5.46, -4.55, 4.5, 9.1)
const REGION := Rect2(272.0, -76.0, 24.0, 28.0)

const UNDER_IDS := ["fern_a", "shrub_a"]
const PLANT_IDS := ["wk_sedge"]
const GROUND_IDS := ["gk_amaochi"]
const LOW_MAX_H := 1.3
## 構件外框（model 半寬 x、半奥 z、高、z 中心オフセット）＝碰撞箱
const PROP_BOX := {"gd_taruzumi": [0.73, 0.28, 1.24, 0.0], "gd_taru": [0.245, 0.245, 0.635, 0.0], "gd_shogi": [0.80, 0.29, 0.42, 0.0],
	"gd_tray": [0.17, 0.12, 0.18, 0.0], "gd_fuda": [0.58, 0.17, 1.59, 0.08], "gd_morijio": [0.065, 0.065, 0.10, 0.0],
	"sk_teoke": [0.41, 0.15, 0.46, 0.0], "sk_woodpile": [0.88, 0.29, 0.98, 0.015], "sk_tensui": [0.31, 0.31, 0.75, 0.0],
	"sk_box": [0.31, 0.21, 0.38, 0.0], "wk_tawara3": [0.41, 0.46, 0.84, 0.0], "sz_stool": [0.21, 0.13, 0.40, 0.0],
	"gk_amaochi": [0.44, 0.05, 0.05, 0.0], "gd_chochin": [0.2, 0.3, 2.05, 0.2]}
const NO_COLLIDE := ["gd_tray", "gd_morijio", "sk_teoke", "gk_amaochi"]
## 載せ物は支えと重なってよい・道具の淨空検査は支えで代表
const ON_IDS := ["gd_tray"]


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
	var ys := yaw_l(Vector2(1.0, 0.0))      # 南妻の外へ向く
	# ── 門前：雨落ちの縁石（入口 |lx| < 1.6 と石燈籠 |lx| > 4.3 で切る）、盛り塩 2、南の角の菰樽積み、北の軒下の打ち水手桶
	for sx: float in [-1.0, 1.0]:
		for k in 3:
			var it := item(S, "mesh", "gk_amaochi", W(sx * (2.05 + k * 0.88), 5.86), yaw_l(Vector2(0.0, 1.0)) + rng.randf_range(-0.03, 0.03), 1.0, "drain")
			it["y"] = S.h((it["p"] as Vector2).x, (it["p"] as Vector2).y) + 0.02
			items.append(it)
	for sx: float in [-1.0, 1.0]:
		items.append(item(S, "mesh", "gd_morijio", W(sx * 1.62, 4.95), 0.0, 1.0, "front"))
	items.append(item(S, "mesh", "gd_taruzumi", W(6.55, 4.35), yaw_l(Vector2(0.35, 1.0)), 1.0, "front"))
	items.append(item(S, "mesh", "sk_teoke", W(-6.05, 4.7), yaw_l(Vector2(-0.4, 1.0)), 1.0, "front"))
	# ── 南側（外の席）：品書き（壁際）→ 緋毛氈の床几＋盆 → 樽卓＋盆＋腰掛け
	items.append(item(S, "mesh", "gd_fuda", W(5.64, 3.25), ys, 1.0, "side"))
	var sh := item(S, "mesh", "gd_shogi", W(6.15, 0.9), ys, 1.0, "side")
	items.append(sh)
	var t1 := item(S, "mesh", "gd_tray", W(6.18, 1.35), ys + 0.2, 1.0, "side", {"on": "gd_shogi", "on_h": 0.42})
	t1["y"] = float(sh["y"]) + 0.42
	items.append(t1)
	var tr := item(S, "mesh", "gd_taru", W(7.55, 0.6), rng.randf() * TAU, 1.0, "side")
	items.append(tr)
	var t2 := item(S, "mesh", "gd_tray", W(7.56, 0.6), ys - 0.5, 1.0, "side", {"on": "gd_taru", "on_h": 0.635})
	t2["y"] = float(tr["y"]) + 0.635
	items.append(t2)
	items.append(item(S, "mesh", "sz_stool", W(8.25, 1.15), yaw_l(Vector2(-0.8, -0.5)), 1.0, "side"))
	# 外の席の目印：赤提灯の柱（主街の南から來る人に「ここで飲める」と見せる；提灯は席の側へ張り出す）
	items.append(item(S, "mesh", "gd_chochin", W(7.6, 3.5), yaw_l(Vector2(-0.6, -1.0)), 1.0, "side"))
	# ── 背面（仕込み場）：薪棚・木箱・俵 3・天水桶（勝手口 lx 2.0 の前は空ける）
	var yb := yaw_l(Vector2(0.0, -1.0))
	items.append(item(S, "mesh", "sk_woodpile", W(-2.7, -5.0), yb, 1.0, "back"))
	items.append(item(S, "mesh", "sk_box", W(0.35, -5.15), yb + 0.25, 1.0, "back"))
	items.append(item(S, "mesh", "wk_tawara3", W(3.75, -5.2), yb + 0.1, 1.0, "back"))
	items.append(item(S, "mesh", "sk_tensui", W(5.35, -5.2), 0.6, 1.0, "back"))
	# ── 低い植生：北の狹い路地と背面の角だけ（看板・門面・席から離す）
	for q: Array in [["fern_a", Vector2(-5.95, -4.95), 0.6], ["fern_a", Vector2(-6.0, 0.8), 0.5]]:
		items.append(item(S, "tree", String(q[0]), W((q[1] as Vector2).x, (q[1] as Vector2).y), rng.randf() * TAU, float(q[2]),
			"low", {"preset": "mature"}))
	for q: Vector2 in [Vector2(-5.7, 3.4), Vector2(-5.75, -1.6), Vector2(-5.7, -3.4), Vector2(-4.6, -4.9), Vector2(-0.9, -4.85),
			Vector2(5.7, -2.4), Vector2(5.75, -3.9), Vector2(10.2, -1.5), Vector2(10.1, 3.2), Vector2(-5.9, 4.6)]:
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
	# 範囲：台基の周り（北 1.6 m・背面 2.2 m・正面は道まで・南は外の席と踏み跡まで）；外へ 2.0 m で淡出
	var zone := Rect2(-7.2, -6.9, 17.6, 14.4)
	var dz := rect_d(zone, q)
	var dmin := dz + warp * 0.7
	var f := 1.0 - smoothstep(0.0, 2.0, dmin)
	if f <= 0.0:
		return null
	var gv := 0.0
	var mo := 0.0
	var so := 0.3 + 0.2 * nz
	var li := 0.0
	var wet := 0.06
	var fm := 0.0
	var fd := foot_d(q)
	var gr := 0.0
	var nw := _n(p * 0.6 + Vector2(13.0, 29.0), 1.7)
	if (-dz < 1.6 or q.x < -6.0) and nw > 0.5:
		gr = 0.75 * smoothstep(0.5, 0.72, nw)
	# 牆腳：台基の外 0.45 m は碎石まじりの濕った土（北妻・背面は苔）
	if fd < 0.5:
		var kw := 1.0 - smoothstep(0.12, 0.5, fd + 0.12 * (nz - 0.5))
		gv = maxf(gv, 0.55 * kw)
		so = maxf(so, 0.5 * kw)
		wet = maxf(wet, 0.14 * kw)
		fm = maxf(fm, 0.8 * kw)
		gr *= 1.0 - kw
		if q.x < -HALF.x + 0.05:
			mo = maxf(mo, 0.38 * kw)
		elif q.y < -HALF.y + 0.05:
			mo = maxf(mo, 0.25 * kw)
	# 門前：三和土（道まで、台基の間口＋0.6）、入口の前は打ち水で濕る
	if q.y > HALF.y - 0.05 and absf(q.x) < HALF.x + 0.6:
		var kf := 1.0 - smoothstep(HALF.x, HALF.x + 0.6, absf(q.x))
		so = maxf(so, 0.62 * kf)
		gv = maxf(gv, 0.38 * kf)
		gr *= 1.0 - kf
		fm = maxf(fm, kf)
		var dw := Vector2(q.x / 2.6, (q.y - 5.6) / 1.1).length() + 0.25 * (nz - 0.5)
		if dw < 1.2:
			wet = maxf(wet, 0.75 * (1.0 - smoothstep(0.45, 1.2, dw)))
	# 庇の雨落ち（碎石の線、入口では切る）
	var dd := absf(q.y - 5.52)
	if dd < 0.22 and absf(q.x) < HALF.x - 0.6 and absf(q.x) > ENTRY_HW + 0.1:
		var kd := (1.0 - smoothstep(0.07, 0.22, dd)) * smoothstep(ENTRY_HW + 0.1, ENTRY_HW + 0.4, absf(q.x))
		gv = maxf(gv, 0.95 * kd)
		wet = maxf(wet, 0.35 * kd)
		fm = maxf(fm, kd)
	# 背面の雨落ち（勝手口の前は踏み固め）
	var db := absf(q.y + 5.0)
	if db < 0.22 and absf(q.x) < HALF.x + 0.1:
		var kb := (1.0 - smoothstep(0.07, 0.22, db)) * smoothstep(0.4, 0.8, absf(q.x - 2.0))
		gv = maxf(gv, 0.75 * kb)
		wet = maxf(wet, 0.3 * kb)
		fm = maxf(fm, kb)
	# 踏み跡：主街の南角 → 外の席の脇 → 裏の勝手口
	var dpn := minf(GL.line_d(PATH_N, q).x, GL.line_d(PATH_X, q).x)
	var pw := 0.55 + 0.18 * (nz - 0.5)
	if dpn < pw + 0.6:
		var kp := 1.0 - smoothstep(pw * 0.5, pw + 0.6, dpn)
		so = maxf(so, 0.6 * kp)
		gv = maxf(gv, 0.48 * (1.0 - smoothstep(pw * 0.25, pw + 0.2, dpn)))
		gr *= 1.0 - kp
		fm = maxf(fm, kp)
	# 外の席：踏み固め（床几・樽卓の前）
	var e := ((q - STAY) / STAY_R).length()
	if e < 1.3:
		var ke := 1.0 - smoothstep(0.5, 1.3, e + 0.2 * (nz - 0.5))
		so = maxf(so, 0.62 * ke)
		gv = maxf(gv, 0.4 * ke)
		gr *= smoothstep(0.6, 1.3, e)
		fm = maxf(fm, ke)
	# 仕込み場（背面）：勝手口の前〜薪棚の前の踏み固め、天水桶の足元のぬかるみ
	var dbk := rect_d(Rect2(-3.6, -6.4, 9.6, 1.6), q)
	if dbk < 0.6:
		var kk := 1.0 - smoothstep(0.0, 0.6, dbk + 0.3 * (nz - 0.5))
		so = maxf(so, 0.72 * kk)
		gv = maxf(gv, 0.25 * kk)
		gr *= 1.0 - kk
		fm = maxf(fm, kk)
	var dt := q.distance_to(Vector2(5.35, -5.2))
	if dt < 1.2:
		wet = maxf(wet, 0.7 * (1.0 - smoothstep(0.35, 1.2, dt)))
		fm = maxf(fm, 1.0 - smoothstep(0.35, 1.2, dt))
	# 落葉：北の路地の奥・背面の北角だけ
	for lc: Vector2 in [Vector2(-6.2, -4.6), Vector2(-6.3, 2.0)]:
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
	m.resource_name = "GD_Ground"
	# R4-2 sg_ground（只讀）の instance 參數：玉砂利 → 灰色の碎石（白く光らせない）
	m.set_shader_parameter("gravel_tint", Vector3(1.16, 1.11, 1.03))
	m.set_shader_parameter("gravel_contrast", 0.95)
	m.set_shader_parameter("gravel_sat", 0.4)
	m.set_shader_parameter("gravel_tile", 0.55)
	am.surface_set_material(0, m)
	am.resource_name = "gd_ground"
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
			t.set_meta("gd_tag", String(it["tag"]))
			(groups["Low"] as Node).add_child(t)
			n_i += 1
			continue
		var node := Node3D.new()
		node.name = "%03d_%s" % [n_i, id]
		node.transform = xf
		node.set_meta("gd_id", id)
		node.set_meta("gd_tag", String(it["tag"]))
		var grp := "Weeds" if id in PLANT_IDS else ("Stones" if id in GROUND_IDS else "Props")
		(groups[grp] as Node).add_child(node)
		var dir := DK if id.begins_with("gd_") else (SK if id.begins_with("sk_") else (ZK if id.begins_with("sz_") else (GK if id.begins_with("gk_") else WK)))
		for lod in 2:
			var key := id + ("_l1" if lod == 1 else "")
			if not meshes.has(key):
				meshes[key] = load(dir + key + ".res")
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % lod
			mi.mesh = meshes[key]
			mi.visibility_range_begin = 0.0 if lod == 0 else LOD_SWITCH
			mi.visibility_range_end = LOD_SWITCH if lod == 0 else (80.0 if id in PLANT_IDS or id in GROUND_IDS else 180.0)
			if lod == 1 or id in ["wk_sedge", "gk_amaochi", "gd_tray", "gd_morijio"]:
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
	root.set_meta("art_revision", "P9 R4-7 鯢吞亭周邊 r2（ART_REVIEW）")
	return root


static func own(n: Node, owner: Node) -> void:
	SG.own(n, owner)
