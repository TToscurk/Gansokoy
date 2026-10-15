extends RefCounted
## 人間之里 V2 P13 W9 Phase 3 第一批（使用者 2026-10-15「停止以細微技術修補為主、優先創造玩家一眼可見的場景差異」）の環境生成器（source of truth）。
##   B3 住宅巷 MidLane：宅間の板塀・木戸・庭木、棟の背後の樹冠（巷の軸から見える屋根の上の緑と高さの変化）
##   C3 農家 A1／A2：屋敷林（欅・椎・楢・榎・紅葉）＋屋敷竹、庭先の生垣（躑躅・低木・笹の混植）、家庭菜園（畝 4＋竹垣）、果樹ふうの庭木 3、
##      柴棚・農具小屋（新規 1・B_P_FARM_SHED）、農路の路肩の木・低木の群れ
## overlay `EnrichW9P3`（root 直下・ArchW9R2P13 の次）→ gen/enrich_w9p3.scn。ビルド／掛載：tools/p13/w9/build_w9p3.gd。
## 方針：W9 R1 の plan／why（道・建物・戸口・水・田・封存物・NPC 動線への不侵入）をそのまま使う。重用優先：樹・竹・低木・垣・畝は承認済み Kit（veg_kit／bamboo_kit／w9_kit／humanuse_exp_kit）。
##   新規は柴棚だけ（Blender build_w9r2_arch.py の B_P_FARM_SHED）。樹は幹の足元だけを占有として置く（樹冠は他の物の上に出てよい）。
const W9 := preload("res://tools/p13/w9/w9_lib.gd")
const HU := preload("res://tools/village_v2_human_use_lib.gd")

const NODE_NAME := "EnrichW9P3"
const OUTPUT := "res://maps/village_v2/gen/enrich_w9p3.scn"
const SCENE := "res://maps/village_v2/village_v2.tscn"
const AFTER := "ArchW9R2P13"
const ART_REVISION := "P13 W9 Phase 3 第一批 r1（ART_REVIEW）"
const ARCH_MESH := "res://assets/village_v2/w9r2_arch/mesh/"
const VEG_DIR := "res://assets/village_v2/veg_kit/mesh/"
const BAMBOO_DIR := "res://assets/village_v2/bamboo_kit/mesh/"
const ZONE_NAME := {"B3": "住宅巷 MidLane（宅間の板塀・庭木・棟の背後の樹冠）", "C3": "農家 A1／A2（屋敷林・生垣・菜園・柴棚・農路の路肩）"}

## 樹：id → [高さ（scale 1・m）, 幹の半径（m）]。足元占有は幹だけ
const TREES := {"keyaki_a": [18.4, 0.60], "konara_a": [14.5, 0.50], "konara_b": [10.9, 0.45], "shii_a": [13.6, 0.55], "enoki_a": [12.2, 0.55],
	"kuromatsu_a": [12.2, 0.45], "akamatsu_a": [16.9, 0.45]}
const BAMBOO := {"take_mature": [13.1, 0.10], "take_thin": [9.3, 0.07], "take_young": [11.6, 0.07]}
## 低木（veg_kit・W9.VEG に無い分）：足元の半径
const SHRUB2 := {"tsutsuji_a": 0.45}
## 小屋の足元（B_P_FARM_SHED・局部）と碰撞箱 [x, z, 幅, 高さ]（局部。奥壁 z＝−1.4、前＝+1.4、西壁 x＝−1.8）
const SHED_DIMS := [-1.8, 0.0, -1.4, 1.8, 2.75, 2.15]
const SHED_COLL := [[-1.35, -1.30, 0.96, 2.4], [-0.45, -1.30, 0.96, 2.4], [0.45, -1.30, 0.96, 2.4], [1.35, -1.30, 0.96, 2.4],
	[-1.74, -0.40, 0.2, 2.2], [-1.74, 0.50, 0.2, 2.2], [-1.68, 1.30, 0.20, 2.2], [0.0, 1.30, 0.20, 2.2], [1.68, 1.30, 0.20, 2.2],
	[-1.30, 1.88, 0.82, 1.25], [-0.50, 1.88, 0.82, 1.25]]
## 碰撞を付けない（植物・低い物）
const NO_COLLIDE := ["tsutsuji_a", "take_mature", "take_thin", "take_young"]


# ─────────────────────────── 資産 ───────────────────────────

static func register_dims() -> void:
	W9.dims("_probe")                    # 先に Kit の寸法表を読ませる（_dims が空だと読まれなくなる）
	for id: String in TREES:
		var t: Array = TREES[id]
		W9._dims[id] = [-float(t[1]), 0.0, -float(t[1]), float(t[1]), float(t[0]), float(t[1])]
	for id: String in BAMBOO:
		var b: Array = BAMBOO[id]
		W9._dims[id] = [-float(b[1]), 0.0, -float(b[1]), float(b[1]), float(b[0]), float(b[1])]
	for id: String in SHRUB2:
		var r: float = SHRUB2[id]
		W9._dims[id] = [-r, 0.0, -r, r, 0.9, r]
	W9._dims["farm_shed"] = SHED_DIMS.duplicate()


static func is_tree(id: String) -> bool:
	return TREES.has(id)


static func is_bamboo(id: String) -> bool:
	return BAMBOO.has(id)


static func is_plant(id: String) -> bool:
	return TREES.has(id) or BAMBOO.has(id) or SHRUB2.has(id) or W9.is_veg(id)


static func tree_h(id: String) -> float:
	return float((TREES[id] as Array)[0]) if TREES.has(id) else (float((BAMBOO[id] as Array)[0]) if BAMBOO.has(id) else 0.0)


## [[mesh path, begin, end, cast shadow]]
static func bundle(id: String, sc: float) -> Array:
	if id == "farm_shed":
		return [[ARCH_MESH + "B_P_FARM_SHED_L0.res", 0.0, W9.LOD_SWITCH, true], [ARCH_MESH + "B_P_FARM_SHED_L1.res", W9.LOD_SWITCH, 200.0, false]]
	var dir := ""
	if BAMBOO.has(id):
		dir = BAMBOO_DIR
	elif TREES.has(id) or SHRUB2.has(id) or W9.is_veg(id):
		dir = VEG_DIR
	else:
		return W9.bundle(id)
	var n := 0
	while n < 4 and ResourceLoader.exists("%s%s_LOD%d.res" % [dir, id, n]):
		n += 1
	var big := tree_h(id) * sc >= 7.5
	var rg: Array = [[0.0, 52.0], [52.0, 110.0], [110.0, 190.0], [190.0, 340.0]] if big else W9.VEG_RANGES
	var out: Array = []
	for k in n:
		var r: Array = rg[k]
		out.append(["%s%s_LOD%d.res" % [dir, id, k], r[0], (r[1] if k < n - 1 else 340.0 if big else 200.0), k < 2])
	return out


# ─────────────────────────── 置く道具 ───────────────────────────

static func _plant(C: Dictionary, items: Array, id: String, x: float, z: float, s: float, meta: Dictionary, rmax := 1.5, extra := {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(x) * 131.0 + absf(z) * 71.0)
	var m := meta.duplicate()
	m.merge({"sx": s, "sy": s * rng.randf_range(0.94, 1.06), "sz": s, "soft": true, "kind": "reuse", "mode": "soft", "on_frontage": false, "relief_max": 0.5, "meadow_ok": true}, true)
	m.merge(extra, true)
	return W9.place(C, items, id, Vector2(x, z), Vector2.from_angle(rng.randf_range(0.0, TAU)), m, "soft", rmax)


## 地面の物（畝・垣・小屋）：face＝+z の向き
static func _ground(C: Dictionary, items: Array, id: String, x: float, z: float, face: Vector2, meta: Dictionary, rmax := 0.8, extra := {}) -> Dictionary:
	var m := meta.duplicate()
	m.merge({"kind": "new" if id == "farm_shed" else "reuse", "mode": "ground", "meadow_ok": true, "relief_max": 0.45}, true)
	m.merge(extra, true)
	return W9.place(C, items, id, Vector2(x, z), face, m, "ground", rmax)


## a→b に沿って ids を step おきに（太さ・ずれ・向きを決定的にばらす）。skip＝[[t0,t1]] の区間は空ける
static func _row(C: Dictionary, items: Array, ids: Array, a: Vector2, b: Vector2, step: float, smin: float, smax: float, seed_i: int, meta: Dictionary, skip := [], jit := 0.22, rmax := 0.5) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41000 + seed_i
	var L := a.distance_to(b)
	var n := maxi(1, int(L / step))
	var d := (b - a).normalized()
	var pp := Vector2(-d.y, d.x)
	var cnt := 0
	for k in n + 1:
		var t := float(k) / float(n)
		var open := false
		for sk in skip:
			if t >= float(sk[0]) and t <= float(sk[1]):
				open = true
		if open:
			continue
		var p := a.lerp(b, t) + pp * rng.randf_range(-jit, jit) + d * rng.randf_range(-step * 0.18, step * 0.18)
		var id: String = ids[rng.randi() % ids.size()]
		if not _plant(C, items, id, p.x, p.y, rng.randf_range(smin, smax), meta, rmax).is_empty():
			cnt += 1
	return cnt


## 群れ：中心の周りに n 株（ids をばらし、大きさも不均一）
static func _clump(C: Dictionary, items: Array, c: Vector2, n: int, ids: Array, smin: float, smax: float, spread: float, seed_i: int, meta: Dictionary, rmax := 0.6) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 43000 + seed_i
	var cnt := 0
	for k in n:
		var a := rng.randf_range(0.0, TAU)
		var r := spread * sqrt(rng.randf())
		var p := c + Vector2(cos(a), sin(a)) * r
		var id: String = ids[rng.randi() % ids.size()]
		if not _plant(C, items, id, p.x, p.y, rng.randf_range(smin, smax), meta, rmax).is_empty():
			cnt += 1
	return cnt


## 垣：a→b に沿って 2 m ごとの板塀／竹垣。face は線に直交（局部 x が線に沿う）。skip＝[[t0,t1]] を空ける
static func _fence(C: Dictionary, items: Array, id: String, a: Vector2, b: Vector2, meta: Dictionary, skip := [], rmax := 0.3) -> int:
	var L := a.distance_to(b)
	var n := maxi(1, int(round(L / 2.0)))
	var d := (b - a).normalized()
	var face := Vector2(-d.y, d.x)
	var cnt := 0
	for k in n:
		var t := (float(k) + 0.5) / float(n)
		var open := false
		for sk in skip:
			if t >= float(sk[0]) and t <= float(sk[1]):
				open = true
		if open:
			continue
		var p := a.lerp(b, t)
		if not _ground(C, items, id, p.x, p.y, face, meta, rmax, {"gap": true, "nov": false}).is_empty():
			cnt += 1
	return cnt


# ─────────────────────────── 設計 B3：住宅巷 MidLane ───────────────────────────
## 巷のフレーム：原点 O＝(234.8, −87.8)、s＝東へ（0.97, 0.24）、o＝北へ（−0.24, 0.97）。南列の正面は o≈−2.3、北列の正面は o≈+2.4
static func lane(s: float, o: float) -> Vector2:
	return Vector2(234.8 + 0.97 * s - 0.24 * o, -87.8 + 0.24 * s + 0.97 * o)


## 巷の軸 d＝(0.97, 0.24)（東向き）、南列（074/075/076）の正面は北向き nS＝(−0.24, 0.97)
## 実測（W9 survey）：南列の背後 z −104 以北・北列の背後 z −73 以南は空き。宅間は 073|074＝x 224–227、075|076＝x 242–244、071|072＝x 237–238

static func design_B3(_C: Dictionary) -> Array:
	var D: Array = []
	D.append({"id": "B3_back_south", "zone": "B3", "desc": "南列（073–076）の背後の樹冠：巷から見上げた屋根の上に緑と高さの変化（紅葉・楢・欅ふう）", "center": Vector2(235.0, -106.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "宅地を持つ家々", "why": "南列の家々の裏手に残された庭木（屋根の背後に樹冠が重なり、一続きの屋根並みにならない）"}, true)
		_plant(C2, items, "shii_a", 219.0, -105.0, 0.70, m, 2.5)
		_plant(C2, items, "konara_b", 231.0, -106.5, 0.88, m, 2.5)
		_plant(C2, items, "kuromatsu_a", 240.5, -107.0, 0.62, m, 2.5)
		_plant(C2, items, "young_broad_b", 249.5, -106.0, 1.35, m, 2.5)
		_plant(C2, items, "konara_b", 225.0, -107.5, 0.70, m, 2.5)})
	D.append({"id": "B3_back_north", "zone": "B3", "desc": "北列（071・072）の背後の樹冠：巷を西から見ると屋根の上に枝が重なる", "center": Vector2(233.0, -70.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "宅地を持つ家々", "why": "北列の家々の裏手の庭木（巷の奥行を作り、屋根並みの背景を緑にする）"}, true)
		_plant(C2, items, "konara_a", 224.5, -70.5, 0.62, m, 2.5)
		_plant(C2, items, "enoki_a", 233.0, -70.0, 0.76, m, 2.5)
		_plant(C2, items, "konara_b", 243.0, -70.5, 0.80, m, 2.5)})
	D.append({"id": "B3_gap_075_076", "zone": "B3", "desc": "075｜076 の宅間：板塀＋躑躅の植え込み（隣家との私領域の境。樹冠は両側の屋根に掛かるので置かない）", "center": Vector2(243.2, -92.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "隣り合う二戸", "why": "板葺きの家と瓦の母屋の間に板塀を立て、足元に躑躅を植える（宅間を『それぞれの庭』にする）"}, true)
		_fence(C2, items, "w9_itabei_a", lane(4.55, -3.0), lane(6.75, -3.0), m)
		var s1 := lane(4.7, -4.4)
		_plant(C2, items, "tsutsuji_a", s1.x, s1.y, 1.2, m, 0.6)
		var s2 := lane(6.6, -4.6)
		_plant(C2, items, "tsutsuji_a", s2.x, s2.y, 1.0, m, 0.6)})
	D.append({"id": "B3_gap_073_074", "zone": "B3", "desc": "073｜074 の宅間：木戸＋板塀＋庭木（裏の畑・井戸への入口）", "center": Vector2(225.6, -94.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "裏の畑を持つ家", "why": "宅間の入口に木戸を立て、その奥に庭木（巷から裏へ抜ける私道の気配）"}, true)
		_ground(C2, items, "w9_kido", 225.7, -94.0, Vector2(-0.24, 0.97), m, 0.5, {"gap": true})
		_plant(C2, items, "young_broad_a", 225.7, -99.0, 1.35, m, 1.2)
		_plant(C2, items, "shrub_a", 224.7, -96.2, 1.3, m, 0.6)})
	D.append({"id": "B3_gap_071_072", "zone": "B3", "desc": "071｜072 の宅間：板塀＋庭木", "center": Vector2(237.6, -80.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "北列の二戸", "why": "板葺きの家と隣家の間の板塀と庭木"}, true)
		_fence(C2, items, "w9_itabei_b", Vector2(236.8, -83.0), Vector2(238.6, -82.8), m)
		_plant(C2, items, "young_broad_a", 237.6, -77.0, 1.3, m, 1.2)
		_plant(C2, items, "sasa_a", 237.0, -80.5, 1.5, m, 0.6)})
	return D


# ─────────────────────────── 設計 C3：農家 A1／A2 ───────────────────────────
## 実測（W9 survey）：A1 x 314.8–321.2・z 77.5–86.5（戸口＝東）、A2 x 321.2–324.8・z 68.3–73.8、庭先＝x 324.5–328.5・z 76–92、P8 の田＝x≥329、
## 農路 FarmPath_5＝z≈70（x≥331）の北路肩 z 63–68・南路肩 z 72–77、運河＝x≤310、南（z≥88）は MeadowP9 の草地＋ EnvironmentP9（x 314–326・z≥92）

static func design_C3(_C: Dictionary) -> Array:
	var D: Array = []
	D.append({"id": "C3_belt", "zone": "C3", "desc": "屋敷林：主屋の背後（西・北西の運河の土手沿い）に欅・赤松・椎・楢・榎・黒松を不揃いに（茅葺き屋根の背景になる緑の高さ。北から来る道と庭先の見通しの帯は空ける）", "center": Vector2(314.5, 76.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "農家", "why": "冬の北西風を防ぐ屋敷林（欅・椎・楢の高木。茅葺きの背後に樹冠の層をつくる）"}, true)
		_plant(C2, items, "keyaki_a", 312.2, 70.0, 0.72, m, 3.0)
		_plant(C2, items, "akamatsu_a", 311.6, 76.0, 0.52, m, 3.0)
		_plant(C2, items, "shii_a", 312.6, 81.5, 0.84, m, 3.0)
		_plant(C2, items, "konara_a", 312.8, 90.0, 0.70, m, 3.0)
		_plant(C2, items, "enoki_a", 317.2, 61.2, 0.80, m, 2.0)
		_plant(C2, items, "kuromatsu_a", 311.8, 66.6, 0.70, m, 2.0)})
	D.append({"id": "C3_bamboo", "zone": "C3", "desc": "屋敷竹：主屋の南西の竹叢（太い竹＋細い竹＋若竹の混生。林と違い、家の脇の小さな叢）", "center": Vector2(311.6, 94.5), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "農家", "why": "竹籠・垣・支柱の材を採る屋敷の竹叢（家の南西、運河の土手際）"}, true)
		_clump(C2, items, Vector2(311.8, 94.5), 12, ["take_mature", "take_mature", "take_thin", "take_young", "take_thin"], 0.92, 1.12, 1.7, 7, m, 0.8)})
	D.append({"id": "C3_orchard", "zone": "C3", "desc": "庭木・果樹ふう：菜園の南西に小ぶりの庭木 2（樹形も大きさも違う。庭の南端 x≥322 と主屋への見通しの帯は空ける）", "center": Vector2(319.5, 95.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "農家", "why": "菜園の南の果樹ふうの庭木（実のなる木・日陰をつくる木）"}, true)
		_plant(C2, items, "young_broad_b", 314.0, 97.4, 1.15, m, 2.0)
		_plant(C2, items, "konara_b", 318.8, 99.8, 0.50, m, 2.0)})
	D.append({"id": "C3_garden", "zone": "C3", "desc": "家庭菜園：主屋の南西の畝 3＋竹垣（庭の南端への通り道は東に空ける）", "center": Vector2(318.4, 90.5), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "畑仕事をする家族", "why": "主屋の南の日当たりに作る家庭菜園（畝を並べ、竹垣で鶏・獣から守る）"}, true)
		var E := Vector2(0.0, 1.0)
		_ground(C2, items, "hx_hatake", 314.8, 89.8, E, m, 1.0)
		_ground(C2, items, "hx_hatake", 318.0, 89.8, E, m, 1.0)
		_ground(C2, items, "hx_hatake", 314.8, 91.8, E, m, 1.0)
		_fence(C2, items, "w9_takegaki", Vector2(313.4, 93.4), Vector2(317.6, 93.4), m, [], 0.4)
		_fence(C2, items, "w9_takegaki", Vector2(313.2, 88.4), Vector2(313.2, 93.0), m, [], 0.4)})
	D.append({"id": "C3_shed", "zone": "C3", "desc": "柴棚・農具小屋：納屋 A2 の北に独立した片流れの板葺き小屋（薪・柴束・農具・割り台）", "center": Vector2(321.6, 64.3), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "農家", "why": "炊事・風呂の薪と柴、農具を雨から守る小屋（納屋 A2 の北、農路から見える）", "relief_max": 0.5}, true)
		_ground(C2, items, "farm_shed", 321.6, 64.3, Vector2(1.0, 0.0), m, 0.6)})
	D.append({"id": "C3_hedge", "zone": "C3", "desc": "庭先の生垣：庭の東縁（田との境）に躑躅・低木・笹の混植（途中を空けて、茅葺きの正面は隠さない）", "center": Vector2(327.5, 85.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "農家", "why": "庭先と田の境の生垣（高さ 1.2–1.6 m・混植。出入りの切れ目を空ける）"}, true)
		_row(C2, items, ["tsutsuji_a", "shrub_a", "tsutsuji_a", "sasa_a"], Vector2(327.3, 79.0), Vector2(327.5, 89.0), 1.15, 1.05, 1.4, 3, m, [[0.42, 0.58]], 0.20, 0.5)})
	D.append({"id": "C3_road", "zone": "C3", "desc": "農路の路肩：田の角の木 3 と低木・笹の群れ（北・南の路肩に不均一に。路面と NPC の動線は空ける）", "center": Vector2(345.0, 70.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "農家", "why": "田の角に残された木と、畦・路肩に自然に育った低木と笹（均一な草地にしない）"}, true)
		_plant(C2, items, "young_broad_a", 338.6, 64.0, 1.15, m, 2.0)
		_plant(C2, items, "young_broad_b", 348.5, 76.0, 1.10, m, 2.0)
		_plant(C2, items, "konara_b", 356.5, 64.0, 0.60, m, 2.0)
		var ids: Array = ["shrub_a", "tsutsuji_a", "sasa_a", "shrub_a", "fern_a"]
		_clump(C2, items, Vector2(334.8, 66.0), 7, ids, 1.0, 1.5, 1.7, 11, m)
		_clump(C2, items, Vector2(343.0, 66.4), 6, ids, 1.0, 1.4, 1.5, 12, m)
		_clump(C2, items, Vector2(351.0, 65.6), 7, ids, 1.0, 1.5, 1.8, 13, m)
		_clump(C2, items, Vector2(335.6, 74.2), 7, ids, 1.0, 1.5, 1.7, 14, m)
		_clump(C2, items, Vector2(341.5, 74.8), 6, ids, 1.0, 1.4, 1.5, 15, m)
		_clump(C2, items, Vector2(350.2, 74.4), 7, ids, 1.0, 1.5, 1.8, 16, m)
		_clump(C2, items, Vector2(356.4, 73.8), 6, ids, 1.0, 1.4, 1.5, 17, m)})
	return D


# ─────────────────────────── 計画・烘焙 ───────────────────────────

static func plan(v: Node3D, meadow_pts: PackedVector2Array, zones: Array = ["B3", "C3"]) -> Dictionary:
	register_dims()
	var C := W9.context(v, meadow_pts)
	# W9 R1（EnrichW9P13）の構件も占有として扱う（根元の地面物）
	var r1 := v.get_node_or_null("EnrichW9P13")
	var n_r1 := 0
	if r1 != null:
		for mi in r1.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null or g.visibility_range_begin > 0.001:
				continue
			var pn := String(g.get_parent().name)
			var is_plant_item := false
			for pk in ["w9_hana", "shrub_a", "fern_a", "sasa_a", "young_broad", "niwamatsu", "young_sugi"]:
				if pn.contains(pk):
					is_plant_item = true
			if is_plant_item:
				continue
			var r: Rect2 = HU._rect_of(g, v)
			if r.size.x > 12.0 or r.size.y > 12.0:
				continue
			(C["rootp_g"] as HU.Grid).add(r.grow(0.15), r.grow(0.15))
			n_r1 += 1
	C["n_r1"] = n_r1
	var items: Array = []
	var clusters: Array = []
	var des: Array = []
	for z: String in zones:
		match z:
			"B3":
				des.append_array(design_B3(C))
			"C3":
				des.append_array(design_C3(C))
	for cl: Dictionary in des:
		var n0 := items.size()
		var meta := W9._cl_meta(cl)
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
		n.position = Vector3(c2.x, W9.top_h(C, c2), c2.y)
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
		node.set_meta("w9_b", "")
		node.set_meta("w9_mode", String(it.get("mode", "ground")))
		var fl := PackedStringArray()
		for fk in ["hang", "band", "recess", "meadow_ok", "allow_rootp", "soft", "gap", "nov", "on_frontage"]:
			if bool(it.get(fk, false)):
				fl.append(fk)
		node.set_meta("w9_flags", ",".join(fl))
		parent.add_child(node)
		for lv in bundle(id, sc.y):
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
		# 碰撞
		if id == "farm_shed":
			var ba := Basis(Vector3.UP, yaw)
			for sh: Array in SHED_COLL:
				var bx := BoxShape3D.new()
				bx.size = Vector3(float(sh[2]) + 0.06, float(sh[3]), float(sh[2]) + 0.06)
				var cs := CollisionShape3D.new()
				cs.name = "%s_c%d" % [node.name, ns]
				cs.shape = bx
				cs.transform = Transform3D(ba, wxf.origin + ba * Vector3(float(sh[0]), float(sh[3]) * 0.5, float(sh[1])))
				col.add_child(cs)
				ns += 1
		elif TREES.has(id):
			var cy := CylinderShape3D.new()
			cy.radius = float((TREES[id] as Array)[1]) * sc.x * 0.9
			cy.height = 3.2
			var cs2 := CollisionShape3D.new()
			cs2.name = "%s_c" % node.name
			cs2.shape = cy
			cs2.transform = Transform3D(Basis.IDENTITY, wxf.origin + Vector3(0.0, 1.6, 0.0))
			col.add_child(cs2)
			ns += 1
		elif not (id in NO_COLLIDE) and not (id in W9.NO_COLLIDE) and not bool(it.get("hang", false)):
			var d: Array = W9.dims(id)
			if float(d[4]) * sc.y >= 0.35:
				var bx2 := BoxShape3D.new()
				bx2.size = Vector3((float(d[3]) - float(d[0])) * absf(sc.x), float(d[4]) * sc.y, (float(d[5]) - float(d[2])) * absf(sc.z))
				var cs3 := CollisionShape3D.new()
				cs3.name = "%s_c" % node.name
				cs3.shape = bx2
				var ba2 := Basis(Vector3.UP, yaw)
				cs3.transform = Transform3D(ba2, wxf.origin + ba2 * Vector3((float(d[0]) + float(d[3])) * 0.5 * sc.x, float(d[4]) * sc.y * 0.5, (float(d[2]) + float(d[5])) * 0.5 * sc.z))
				col.add_child(cs3)
				ns += 1
		n_i += 1
	root.set_meta("items", (P["items"] as Array).size())
	root.set_meta("clusters", cl_nodes.size())
	root.set_meta("shapes", ns)
	root.set_meta("art_revision", ART_REVISION)
	return root
