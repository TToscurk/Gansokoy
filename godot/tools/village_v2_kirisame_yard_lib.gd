extends RefCounted
## 人間之里 V2 P9 R4-8 Hero Surroundings：霧雨店周邊（ART-FIRST）。
##   規劃（plan）＋烘焙（bake）→ maps/village_v2/gen/kirisame_p9.scn → village_v2.tscn 掛 Vegetation/KirisameP9
##   （… → SuzunaanP9 → GeidonteiP9 → KirisameP9）。
##   讀感＝「奇物雜貨店＋魔法材料工作坊」：東西很多、類型很雜、有人在分類・曬乾・搬運・研究；入口與動線清楚、亂中有呼吸。
##   霧雨店 Hero 本體（P5 R2：展示台・花桶・A 字黑板・木箱・「魔」大提燈・勝手口踏石を含む）不動；P3 地塊／道路／地形、R1–R4-7 封存內容不動。
##   新構件＝kiri_kit（build_kiri_kit.py）；只讀重用：suzu_kit 腰掛け、waterside_kit 菅・花菖蒲、R1 蕨・低木 prefab、R4-2 sg_ground。
## 座標：Hero 局部（lx＝間口、+lx＝北妻側〔南橫街側〕；lz＝奥行、+lz＝MainStreet 側正面）。Hero yaw 81.5°、原點 (229.95, 62.04)。
##   台基 lx ±4.095、lz ±3.64；庇の下の通路 lz 4.29–4.85；主街の路肩 lz 5.1；入口 lx 0（扉 1.75 m）；勝手口 lx 2.0（背面）。
##   南側は日の当たる未區劃の空地（lx −4.1〜−11）；北妻は 10:00 に壁から約 3 m が影（ortho 實測）；背面は町家 P_MKT_045 まで約 2.5 m、南西角は開けている。
## 構成（大件は壁際、中件は組、小件は點綴；空地を残す）：
##   1 門前（控えめ、市集にしない）：入口脇に瓶と壺の小台、表の両角に茸の籠・奇石の開け箱、南角に魔女の楕円札の立て札。
##   2 側院＝南の日向（主な作業場、5–10 m で「普通の雜貨屋ではない」と分かる 3 つの印）：
##     印 1 藥草・茸の干し棚（空地に自立、日に当てる）／印 2 奇石・鉱物の棚（壁際）／印 3 箒＋作業台（薬研・帳面・瓶）の作業角；
##     腰掛け・縄の束、周りに藥草の株と野の花。空地の外側（lx < −9）は空ける。
##   3 後院（倉庫、側院より乱雜）：背面の壁際（日陰）に古い棚・麻袋；日の入る南西角を倉庫に（使わない大八車・板材の山・桶・積んだ材料箱・空き瓶・荷）；
##     勝手口 → 南西角 → 側院の搬運路は空ける。
##   4 北側（南橫街、日陰）：構件なし、牆腳の茸と草だけ（静かな側）。

const SG := preload("res://tools/village_v2_shrine_grove_lib.gd")
const GL := preload("res://tools/village_v2_hieda_garden_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const FLib := preload("res://tools/village_v2_forest_lib.gd")

const OUTPUT := "res://maps/village_v2/gen/kirisame_p9.scn"
const NODE_NAME := "KirisameP9"
const DK := "res://assets/village_v2/kiri_kit/mesh/"
const SK := "res://assets/village_v2/school_kit/mesh/"
const ZK := "res://assets/village_v2/suzu_kit/mesh/"
const GK := "res://assets/village_v2/garden_kit/mesh/"
const WK := "res://assets/village_v2/waterside_kit/mesh/"
const PARCELS := "res://maps/village_v2/gen/parcels.json"
const ASSET := "res://assets/village_v2/kirisame/asset.json"
const HERO_PATH := "Landmarks/LANDMARK_KIRISAME/Hero"
const SEED := 4881
const LOD_SWITCH := 30.0

## Hero 局部座標系（場景同源：gate で Hero の global_transform と照合、ずれ > 1 cm は FAIL）
const HO := Vector2(229.9476, 62.03715)
const BX := Vector2(0.14834, -0.988936)
const BZ := Vector2(0.988936, 0.14834)
const HALF := Vector2(4.095, 3.64)
const PARCEL_ID := "P_LM_KIRISAME"
## 動線（局部）：入口の軸、庇下の通路、北の踏み跡（南橫街 → 荷車の脇 → 勝手口）、表の角 → 側院、搬運路（勝手口 → 南西角 → 側院）
const ENTRY := [Vector2(0.0, 6.0), Vector2(0.0, 4.0)]
const ENTRY_HW := 1.0
const WALK := Rect2(-4.1, 4.29, 8.2, 0.56)
const PATH_N := [Vector2(10.6, 2.6), Vector2(6.2, 1.0), Vector2(5.9, -3.3), Vector2(4.8, -4.85), Vector2(2.6, -4.9), Vector2(2.0, -4.3)]
const PATH_X := [Vector2(-4.4, 4.75), Vector2(-5.9, 4.2), Vector2(-5.85, -1.4)]
const PATH_B := [Vector2(2.0, -4.3), Vector2(1.5, -5.15), Vector2(-3.9, -5.3), Vector2(-5.7, -4.1), Vector2(-5.85, -1.4)]
const PATH_HW := 0.45
const BACKDOOR := Rect2(1.3, -5.0, 1.4, 0.95)
## 側院の空地（構件・植生の占有 ≤ 30 %）；その外側 lx < −9 は構件 0（呼吸）
const NORTH_YARD := Rect2(-9.0, -3.5, 4.9, 8.0)
const OUTER_LX := -9.0
const REGION := Rect2(219.5, 49.5, 19.0, 23.5)

const UNDER_IDS := ["fern_a", "shrub_a"]
const PLANT_IDS := ["wk_sedge", "wk_iris", "kr_yakuso", "kr_kinoko"]
const GROUND_IDS := ["gk_amaochi"]
const LOW_MAX_H := 1.3
## 大件（高 ≥ 1.2 m）は壁際（台基から ≤ 0.8 m）。例外＝日に当てる干し棚
const BIG_H := 1.2
const BIG_FREE := ["kr_hoshidana"]
## 構件外框（model 半寬 x、半奥 z、高、z 中心オフセット）＝碰撞箱（build_kiri_kit.py の dims から）
const PROP_BOX := {"kr_fuda_ma": [0.52, 0.06, 1.3, 0.0], "kr_hako_ishi": [0.28, 0.19, 0.54, 0.0], "kr_kago": [0.21, 0.21, 0.47, 0.0],
	"kr_bin": [0.22, 0.15, 0.595, 0.0], "kr_hoshidana": [1.18, 0.47, 1.907, 0.0], "kr_ishidana": [0.987, 0.208, 1.3, 0.018],
	"kr_sagyo": [0.575, 0.258, 0.89, 0.008], "kr_houki": [0.143, 0.25, 1.466, -0.109], "kr_nawa": [0.432, 0.233, 0.143, 0.0],
	"kr_hakozumi": [0.632, 0.296, 0.921, -0.015], "kr_fukuro": [0.818, 0.19, 0.58, 0.01], "kr_akibin": [0.636, 0.278, 0.324, -0.067],
	"kr_zaimoku": [1.078, 0.313, 0.184, -0.015], "kr_furudana": [0.5, 0.17, 1.5, 0.0], "kr_kuruma": [0.56, 1.369, 0.919, 0.646],
	"kr_okeyama": [0.475, 0.312, 0.88, 0.0], "kr_ni": [0.322, 0.192, 0.692, 0.0],
	"sz_stool": [0.21, 0.13, 0.40, 0.0], "gk_amaochi": [0.44, 0.05, 0.05, 0.0]}
const NO_COLLIDE := ["gk_amaochi", "kr_nawa", "kr_fuda_ma"]
## 載せ物（なし）
const ON_IDS := []


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
	var ys := yaw_l(Vector2(-1.0, 0.0))     # 南妻の外（側院）へ向く
	var yb := yaw_l(Vector2(0.0, -1.0))     # 背面の外へ向く
	# ── 1 門前（控えめ）：入口脇の瓶の小台、表の両角に茸の籠・奇石の開け箱、南角の立て札（腕は壁側へ）
	items.append(item(S, "mesh", "kr_bin", W(-1.47, 4.07), yaw_l(Vector2(0.25, 1.0)), 1.0, "front"))
	items.append(item(S, "mesh", "kr_kago", W(4.45, 3.95), 0.7, 1.0, "front"))
	items.append(item(S, "mesh", "kr_hako_ishi", W(-4.6, 3.85), yaw_l(Vector2(-0.3, 1.0)), 1.0, "front"))
	items.append(item(S, "mesh", "kr_fuda_ma", W(-4.85, 3.05), yaw_l(Vector2(-0.35, 1.0)), 1.0, "side"))
	# ── 2 側院（南の日向）：壁際に奇石の棚（印 2）、箒（印 3）＋作業台・腰掛け・縄、空地に干し棚（印 1）
	items.append(item(S, "mesh", "kr_ishidana", W(-4.42, 1.95), ys, 1.0, "side"))
	items.append(item(S, "mesh", "kr_houki", W(-4.5, 0.62), ys + 0.1, 1.0, "side"))
	items.append(item(S, "mesh", "kr_sagyo", W(-4.4, -0.62), ys, 1.0, "side"))
	items.append(item(S, "mesh", "sz_stool", W(-5.2, -0.25), yaw_l(Vector2(1.0, 0.3)), 1.0, "side"))
	items.append(item(S, "mesh", "kr_nawa", W(-4.75, -1.75), 0.0, 1.0, "side"))
	items.append(item(S, "mesh", "kr_hoshidana", W(-7.45, 0.8), yaw_l(Vector2(-0.85, 0.5)), 1.0, "side"))
	# ── 3 後院：背面の壁際（日陰）に古い棚と麻袋；日の入る南西角を倉庫に——使わない大八車・板材の山・桶・積んだ材料箱・空き瓶・荷
	items.append(item(S, "mesh", "kr_furudana", W(0.35, -3.95), yb, 1.0, "back"))
	items.append(item(S, "mesh", "kr_akibin", W(3.45, -4.05), yb + 0.05, 1.0, "back"))
	items.append(item(S, "mesh", "kr_fukuro", W(-1.55, -4.02), yb - 0.1, 1.0, "back"))
	items.append(item(S, "mesh", "kr_hakozumi", W(-3.3, -4.2), yb + 0.08, 1.0, "back"))
	items.append(item(S, "mesh", "kr_kuruma", W(-8.35, -6.0), yaw_l(Vector2(0.05, 1.0)), 1.0, "back"))
	items.append(item(S, "mesh", "kr_zaimoku", W(-6.9, -7.3), yaw_l(Vector2(-0.12, 1.0)), 1.0, "back"))
	items.append(item(S, "mesh", "kr_okeyama", W(-6.85, -5.75), yaw_l(Vector2(0.25, 1.0)), 1.0, "back"))
	items.append(item(S, "mesh", "kr_hakozumi", W(-6.95, -4.05), yaw_l(Vector2(0.45, 1.0)), 1.0, "back"))
	items.append(item(S, "mesh", "kr_akibin", W(-5.45, -6.3), yaw_l(Vector2(1.0, 0.1)), 1.0, "back"))
	# ── 植生（主人は整理しないが、いくつかは材料）：藥草の株・野の花・茸・雜草・蕨・低木
	# 藥草は 2 つの群れ（干し棚の奥・空地の南端）＋壁際 1；野の花は群れの縁に 1
	for q: Vector2 in [Vector2(-8.3, 2.7), Vector2(-8.05, 3.35), Vector2(-7.55, 3.85), Vector2(-8.65, -0.9), Vector2(-8.85, -1.65),
			Vector2(-8.2, -2.2), Vector2(-4.45, -2.5)]:
		var it := item(S, "plant", "kr_yakuso", W(q.x, q.y), rng.randf() * TAU, rng.randf_range(0.85, 1.15), "herb")
		it["y"] = S.h((it["p"] as Vector2).x, (it["p"] as Vector2).y) - 0.03
		items.append(it)
	for q: Vector2 in [Vector2(-9.25, -2.6), Vector2(-9.0, 1.9)]:
		var it := item(S, "plant", "kr_yakuso", W(q.x, q.y), rng.randf() * TAU, rng.randf_range(0.7, 0.9), "flower")
		it["y"] = S.h((it["p"] as Vector2).x, (it["p"] as Vector2).y) - 0.03
		items.append(it)
	for q: Vector2 in [Vector2(4.35, 1.6), Vector2(4.4, -1.9), Vector2(0.95, -3.86), Vector2(-5.9, -7.3)]:
		var it := item(S, "plant", "kr_kinoko", W(q.x, q.y), rng.randf() * TAU, rng.randf_range(0.9, 1.2), "kinoko")
		it["y"] = S.h((it["p"] as Vector2).x, (it["p"] as Vector2).y) - 0.03
		items.append(it)
	for q: Array in [["fern_a", Vector2(4.6, 3.0), 0.5], ["fern_a", Vector2(-9.25, -6.5), 0.5], ["shrub_a", Vector2(-9.3, -4.6), 0.6]]:
		items.append(item(S, "tree", String(q[0]), W((q[1] as Vector2).x, (q[1] as Vector2).y), rng.randf() * TAU, float(q[2]),
			"low", {"preset": "mature"}))
	for q: Vector2 in [Vector2(4.4, 0.4), Vector2(4.4, -0.9), Vector2(4.3, -2.6), Vector2(-4.4, -1.6), Vector2(-4.3, -3.2), Vector2(-3.85, -3.85),
			Vector2(4.3, -3.5), Vector2(-7.3, -2.7), Vector2(-8.6, 0.6), Vector2(-5.5, -6.3), Vector2(9.3, -3.6), Vector2(-6.75, 4.15)]:
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
	## Suzunaan／Geidontei より破碎：地形の土と同じ「踏み固め土」だけでは差が出ない（ortho A/B 實測）→
	##   斑ごとに 草の穴（殘餘重み＝草層）／碎石の斑／濕った染み／落葉・木屑 を混ぜ、整面にしない
	var q := Lc(p)
	var nz := _n(p, 1.0)
	var warp := 0.9 * (nz - 0.5) + 0.35 * sin(p.x * 1.1 - p.y * 0.7)
	var zone := Rect2(-10.0, -8.0, 21.4, 13.3)
	var f := 1.0 - smoothstep(0.0, 2.0, rect_d(zone, q) + warp * 0.7)
	if f <= 0.0:
		return null
	var pn := _n(p * 1.9 + Vector2(7.0, 3.0), 1.4)       # 大きい斑
	var pb := _n(p * 3.1 + Vector2(19.0, 41.0), 1.1)     # 細かい斑
	var pw2 := _n(p * 2.4 + Vector2(53.0, 11.0), 1.2)    # 濕り
	var fd := foot_d(q)
	# ── 使われている範囲（特徴マスク）
	var m_front := 0.0
	if q.y > HALF.y - 0.05 and absf(q.x) < HALF.x + 0.7:
		m_front = 1.0 - smoothstep(HALF.x, HALF.x + 0.7, absf(q.x))
	var dpn := minf(minf(GL.line_d(PATH_N, q).x, GL.line_d(PATH_X, q).x), GL.line_d(PATH_B, q).x)
	var pwd := 0.5 + 0.25 * (pn - 0.5)
	var m_path := 1.0 - smoothstep(pwd * 0.4, pwd + 0.5, dpn)
	var dside := rect_d(Rect2(-9.3, -3.6, 5.2, 7.6), q)
	var m_side := 1.0 - smoothstep(-0.2, 0.9, dside + 0.6 * (nz - 0.5))
	var dbk := rect_d(Rect2(-9.3, -7.8, 13.6, 4.15), q)
	var m_back := 1.0 - smoothstep(-0.2, 0.8, dbk + 0.5 * (nz - 0.5))
	var m_wall := 1.0 - smoothstep(0.1, 0.55, fd + 0.15 * (nz - 0.5))
	var m_use := maxf(maxf(m_front, m_path), maxf(maxf(m_side, m_back), m_wall))
	if m_use <= 0.01:
		return null
	# ── 基本：踏み固め土（地形と同色）＋斑
	var gv := 0.0
	var mo := 0.0
	var so := 0.6
	var li := 0.0
	var wet := 0.05
	# 草の穴（使う所の中にも草が残る；殘餘重み＝草層）
	var hole := (1.0 - smoothstep(0.22, 0.34, pn)) * (1.0 - m_path) * (1.0 - m_front)
	# 碎石の斑（作業場・後院・踏み跡）
	var grav := smoothstep(0.48, 0.62, pb) * maxf(maxf(m_side, m_back), m_path * 0.8)
	gv = maxf(gv, 0.85 * grav)
	# 濕った染み（作業台・桶・干し棚の足元の水仕事）
	var wsp := smoothstep(0.55, 0.7, pw2) * maxf(m_side, m_back)
	wet = maxf(wet, 0.8 * wsp)
	# 落葉・木屑（後院、側院の奥）
	var lit := smoothstep(0.5, 0.68, _n(p * 2.6 + Vector2(3.0, 77.0), 1.3)) * maxf(m_back, m_side * 0.5)
	li = maxf(li, 0.65 * lit)
	# 牆腳：碎石＋苔（日陰の北妻・背面は苔多め）
	if m_wall > 0.0:
		gv = maxf(gv, 0.4 * m_wall * smoothstep(0.3, 0.5, pn))
		if q.x > HALF.x - 0.05:
			mo = maxf(mo, 0.55 * m_wall)
		elif q.y < -HALF.y + 0.05:
			mo = maxf(mo, 0.35 * m_wall)
		else:
			mo = maxf(mo, 0.15 * m_wall * smoothstep(0.5, 0.7, pb))
	# 踏み跡・門前：草なし、碎石は控えめ
	so = maxf(so, 0.75 * maxf(m_path, m_front))
	# 重みの正規化：草の穴は殘餘を草に（土で埋めない）
	var tot := gv + mo + so + li
	if tot > 1.0:
		gv /= tot
		mo /= tot
		so /= tot
		li /= tot
	var keep := 1.0 - hole * 0.9
	gv *= keep
	mo *= keep
	so *= keep
	li *= keep
	tot = gv + mo + so + li
	f *= m_use * smoothstep(0.0, 0.1, tot + hole)
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
	m.resource_name = "KR_Ground"
	# R4-2 sg_ground（只讀）の instance 參數：玉砂利 → 灰色の碎石（白く光らせない）
	m.set_shader_parameter("gravel_tint", Vector3(1.16, 1.11, 1.03))
	m.set_shader_parameter("gravel_contrast", 0.95)
	m.set_shader_parameter("gravel_sat", 0.4)
	m.set_shader_parameter("gravel_tile", 0.55)
	am.surface_set_material(0, m)
	am.resource_name = "kr_ground"
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
			t.set_meta("kr_tag", String(it["tag"]))
			(groups["Low"] as Node).add_child(t)
			n_i += 1
			continue
		var node := Node3D.new()
		node.name = "%03d_%s" % [n_i, id]
		node.transform = xf
		node.set_meta("kr_id", id)
		node.set_meta("kr_tag", String(it["tag"]))
		var grp := "Weeds" if id in PLANT_IDS else ("Stones" if id in GROUND_IDS else "Props")
		(groups[grp] as Node).add_child(node)
		var dir := DK if id.begins_with("kr_") else (SK if id.begins_with("sk_") else (ZK if id.begins_with("sz_") else (GK if id.begins_with("gk_") else WK)))
		for lod in 2:
			var key := id + ("_l1" if lod == 1 else "")
			if not meshes.has(key):
				meshes[key] = load(dir + key + ".res")
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % lod
			mi.mesh = meshes[key]
			mi.visibility_range_begin = 0.0 if lod == 0 else LOD_SWITCH
			mi.visibility_range_end = LOD_SWITCH if lod == 0 else (80.0 if id in PLANT_IDS or id in GROUND_IDS else 180.0)
			if lod == 1 or id in PLANT_IDS or id in GROUND_IDS:
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
	root.set_meta("art_revision", "P9 R4-8 霧雨店周邊 r8（ART_REVIEW：奇物雜貨店＋魔法材料工作坊）")
	return root


static func own(n: Node, owner: Node) -> void:
	SG.own(n, owner)
