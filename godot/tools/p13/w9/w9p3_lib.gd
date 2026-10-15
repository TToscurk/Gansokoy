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
const ART_REVISION := "P13 W9 Phase 3 第一批 r2（ART_REVIEW ACCEPTED 後の局所調整：cT4 前景樹・cT7 南の路肩）"
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


# ─────────────────────────── 検査用の純関数（gate と反向案例で共用・使用者 2026-10-15 の C 区の二点） ───────────────────────────
## ① cT4（農路の入口から南を見る正式 TPS）：前景の樹が農舎と運河を隠さない。
##    樹冠は高さ 0.32–1.0 H・水平半径 crown_r(id)×scale（AABB の平均半幅）の楕円体で近似。
## ② cT7（農路を東から西へ見る正式 TPS）の左（南）の路肩：同じ配合の群れが一続きの帯にならない（高さ・間隔・種類）。
## 樹冠の水平半径 = p3_dims の AABB の平均半幅 × scale（係数 1.0）。R2 の初版は 0.7 倍の『密な部分』で近似し、gate は『遮蔽 0 %』と言ったが、
##   ID パスの実測では黒松（scale 0.7）が農舎の見える面積の 18.5 % を覆っていた（描画上の樹冠は AABB の平均半幅いっぱいまで張り出す）→ 1.0 倍に較正
static var _crown_cache := {}


static func crown_r(id: String) -> float:
	if _crown_cache.has(id):
		return float(_crown_cache[id])
	var r := 0.0
	var m := load(W9.veg_path(id, 0)) as Mesh      # Kit の LOD0 の実メッシュ（register_dims は足元占有のため幹だけの寸法に差し替えている＝使えない）
	if m != null:
		var a := m.get_aabb()
		r = 0.25 * (a.size.x + a.size.z)
	_crown_cache[id] = r
	return r


const CT4_CAM := Vector3(316.40, 3.25, 57.66)
const CT4_FARM_BOX := Rect2(313.2, 0.5, 9.6, 5.3)       # 農舎 A1（中心 (318, 82)・FarmsteadP13 の A1_noka の包絡 x ±5.3・z ±3.35・棟 5.85 m）の北の壁面の見える範囲：x 313.2–322.8・y 0.5–5.8（壁＋屋根）
const CT4_FARM_Z := 78.65                                # A1 の北の壁面 = 82 − 3.35
const CT4_CANAL := [Vector3(311.3, 0.0, 64.3), Vector3(310.1, 0.0, 68.6), Vector3(307.8, 0.0, 76.2)]     # 運河の水面の折れ線（ID パスで水路と確認した画素 (0.80,0.70)(0.74,0.58)(0.70,0.50) を地面へ投影）
const CT4_BLOCK_MAX := 0.10        # 相機から農舎（7×5 の視線）・運河（9 点）への視線が樹冠・幹に遮られる割合の上限（R1 の榎は農舎への視線の過半を遮っていた）
const CAM_CROWN_MARGIN := 1.0      # 相機が樹冠の水平半径＋この値より近い（かつ樹冠の下端より上）なら『相機が樹冠の中』
const VERGE_BOX := Rect2(333.0, 72.4, 26.0, 5.1)      # 南の路肩：x 333–359・z 72.4–77.5
const VERGE_LINK := 0.7            # 足元の外周どうしがこれ未満なら同じ群れ
const VERGE_GAP_MIN := 2.5         # 『切れ目』と数える群れ間の隙間
const VERGE_WIDE_MAX := 6.5        # 一つの群れの幅の上限（R1：11.3 m の帯）


static func tree_height(id: String, sy: float) -> float:
	if TREES.has(id):
		return float((TREES[id] as Array)[0]) * sy
	var d: Array = W9.dims(id)
	return float(d[4]) * sy


static func is_crown_tree(id: String) -> bool:
	return TREES.has(id) or id.begins_with("young_broad")


## 線分 a→b（相機→目標）が樹 it の樹冠（楕円体）を『目標の手前で』通るか。目標が樹冠の奥（ray が樹冠に入る点が目標より CROWN_BEHIND m 以上手前にない）なら、
## その樹は目標の背後か脇にいるだけで遮らない（農舎の裏の樹を『農舎を隠す』と数えない）。相機が樹冠の中なら遮る。
const CROWN_BEHIND := 0.5


static func crown_hits(it: Dictionary, a: Vector3, b: Vector3) -> bool:
	var id := String(it["id"])
	if not is_crown_tree(id):
		return false
	var h := tree_height(id, float(it["sy"]))
	var rr: float = crown_r(id) * float(it["sx"])
	var c := Vector3((it["p"] as Vector2).x, float(it["y"]) + 0.66 * h, (it["p"] as Vector2).y)
	var rad := Vector3(rr, 0.34 * h, rr)
	var a2 := (a - c) / rad
	var b2 := (b - c) / rad
	var d := b2 - a2
	var qa := d.dot(d)
	if qa < 1e-9:
		return false
	var qb := 2.0 * a2.dot(d)
	var qc := a2.dot(a2) - 1.0
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return false
	var sq := sqrt(disc)
	var t_in := (-qb - sq) / (2.0 * qa)
	var t_out := (-qb + sq) / (2.0 * qa)
	if t_out < 0.0 or t_in > 1.0:
		return false                      # 線分が樹冠に触れない
	var seg_len := maxf(a.distance_to(b), 1e-6)
	return t_in <= 1.0 - CROWN_BEHIND / seg_len


## 線分 a→b を遮る樹（樹冠の楕円体 または 幹の円柱）。戻り値＝"id@(x,z)" の配列
static func seg_blockers(items: Array, a: Vector3, b: Vector3) -> Array:
	var out: Array = []
	for it: Dictionary in items:
		var id := String(it["id"])
		if not is_crown_tree(id):
			continue
		var hit := crown_hits(it, a, b)
		if not hit and TREES.has(id):
			# 幹：XZ で線分と幹の軸の距離 ≤ 幹の半径×scale、かつその点の高さが幹の範囲（地面〜0.45 H）
			var tr: float = float((TREES[id] as Array)[1]) * float(it["sx"])
			var pa := Vector2(a.x, a.z)
			var pb := Vector2(b.x, b.z)
			var q := Geometry2D.get_closest_point_to_segment(it["p"] as Vector2, pa, pb)
			if q.distance_to(it["p"] as Vector2) <= tr:
				var t := 0.0 if pa.distance_to(pb) < 1e-6 else pa.distance_to(q) / pa.distance_to(pb)
				var yy := a.y + (b.y - a.y) * t
				if yy >= float(it["y"]) - 0.2 and yy <= float(it["y"]) + 0.45 * tree_height(id, float(it["sy"])):
					hit = true
		if hit:
			out.append("%s@(%.1f,%.1f)" % [id, (it["p"] as Vector2).x, (it["p"] as Vector2).y])
	return out


## cT4 の相機から見た農舎・運河の『遮られ率』：農舎＝北の壁面の 7×5 点・運河＝折れ線上の 9 点への視線のうち樹に遮られる割合
static func ct4_view(items: Array, cam := CT4_CAM) -> Dictionary:
	var farm_n := 0
	var farm_b := 0
	var who := {}
	for kx in 7:
		for ky in 5:
			var tgt := Vector3(CT4_FARM_BOX.position.x + CT4_FARM_BOX.size.x * float(kx) / 6.0, CT4_FARM_BOX.position.y + CT4_FARM_BOX.size.y * float(ky) / 4.0, CT4_FARM_Z)
			var bl := seg_blockers(items, cam, tgt)
			farm_n += 1
			if not bl.is_empty():
				farm_b += 1
				for w in bl:
					who[w] = int(who.get(w, 0)) + 1
	var pts: Array = []
	for j in range(CT4_CANAL.size() - 1):
		for t in 4:
			pts.append((CT4_CANAL[j] as Vector3).lerp(CT4_CANAL[j + 1] as Vector3, float(t) / 4.0))
	pts.append(CT4_CANAL[CT4_CANAL.size() - 1])
	var can_b := 0
	for tgt: Vector3 in pts:
		var bl2 := seg_blockers(items, cam, tgt)
		if not bl2.is_empty():
			can_b += 1
			for w2 in bl2:
				who[w2] = int(who.get(w2, 0)) + 1
	return {"farm": float(farm_b) / float(farm_n), "canal": float(can_b) / float(pts.size()), "who": who, "farm_n": farm_n, "canal_n": pts.size()}


## 相機が樹冠の中・すぐ脇にある樹（幹からの水平距離 < 樹冠の半径＋margin、かつ相機が樹冠の下端より上）
static func cam_in_crown(items: Array, cam: Vector3, margin := CAM_CROWN_MARGIN) -> Array:
	var out: Array = []
	for it: Dictionary in items:
		var id := String(it["id"])
		if not is_crown_tree(id):
			continue
		var h := tree_height(id, float(it["sy"]))
		var rr: float = crown_r(id) * float(it["sx"])
		var d := Vector2(cam.x, cam.z).distance_to(it["p"] as Vector2)
		if d < rr + margin and cam.y > float(it["y"]) + 0.32 * h:
			out.append("%s@(%.1f,%.1f) 幹まで %.1f m < 樹冠 %.1f m＋%.1f" % [id, (it["p"] as Vector2).x, (it["p"] as Vector2).y, d, rr, margin])
	return out


## 足元の外周の半径 [m]：低木＝AABB の平均半幅×scale、木＝幹の半径 0.45×scale（樹冠は頭の上＝低木の帯の連続には数えない）
static func foot_radius(id: String, sx: float) -> float:
	if is_crown_tree(id):
		return 0.45 * sx
	var d: Array = W9.dims(id)
	return 0.25 * ((float(d[3]) - float(d[0])) + (float(d[5]) - float(d[2]))) * sx


static func _uf_find(par: Array, x: int) -> int:
	while int(par[x]) != x:
		par[x] = par[int(par[x])]
		x = int(par[x])
	return x


## 路肩の群れ分け：items＝[{id, p, sx, sy}]（VERGE_BOX の中だけ）→ x 順の群れ [{x0, x1, w, ids(重複なしの並び), sigs, tall, n}]
static func verge_groups(items: Array) -> Array:
	var its: Array = []
	for it: Dictionary in items:
		if VERGE_BOX.has_point(it["p"] as Vector2):
			its.append(it)
	its.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["p"] as Vector2).x < (b["p"] as Vector2).x)
	var par: Array = []
	for i in its.size():
		par.append(i)
	for i in its.size():
		for j in range(i + 1, its.size()):
			var a: Dictionary = its[i]
			var b: Dictionary = its[j]
			var dd := (a["p"] as Vector2).distance_to(b["p"] as Vector2) - foot_radius(String(a["id"]), float(a["sx"])) - foot_radius(String(b["id"]), float(b["sx"]))
			if dd < VERGE_LINK:
				par[_uf_find(par, i)] = _uf_find(par, j)
	var by := {}
	for i in its.size():
		var r := _uf_find(par, i)
		if not by.has(r):
			by[r] = []
		(by[r] as Array).append(its[i])
	var out: Array = []
	for r in by:
		var m: Array = by[r]
		var x0 := 1.0e9
		var x1 := -1.0e9
		var tall := 0.0
		var ids := {}
		for it: Dictionary in m:
			var rf := foot_radius(String(it["id"]), float(it["sx"]))
			x0 = minf(x0, (it["p"] as Vector2).x - rf)
			x1 = maxf(x1, (it["p"] as Vector2).x + rf)
			var hh := tree_height(String(it["id"]), float(it["sy"])) if is_crown_tree(String(it["id"])) else float(W9.dims(String(it["id"]))[4]) * float(it["sy"])
			tall = maxf(tall, hh)
			ids[String(it["id"])] = true
		var keys: Array = ids.keys()
		keys.sort()
		out.append({"x0": x0, "x1": x1, "w": x1 - x0, "ids": keys, "sigs": ",".join(keys), "tall": tall, "n": m.size()})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["x0"]) < float(b["x0"]))
	return out


## 判定：群れ ≥ 4・一つの帯 ≤ VERGE_WIDE_MAX・切れ目（≥ VERGE_GAP_MIN）≥ 3・隣り合う群れの配合が違う・種類 ≥ 5・高い群（≥ 4 m）と低い群（≤ 1.5 m）が両方ある
static func verge_check(items: Array) -> Dictionary:
	var G := verge_groups(items)
	var why: Array = []
	var gaps: Array = []
	for k in range(G.size() - 1):
		gaps.append(float(G[k + 1]["x0"]) - float(G[k]["x1"]))
	var widest := 0.0
	var species := {}
	var tall_n := 0
	var low_n := 0
	var same_adj := 0
	for k in G.size():
		var g: Dictionary = G[k]
		widest = maxf(widest, float(g["w"]))
		for sp in (g["ids"] as Array):
			species[sp] = true
		if float(g["tall"]) >= 4.0:
			tall_n += 1
		if float(g["tall"]) <= 1.5:
			low_n += 1
		if k > 0 and String(g["sigs"]) == String(G[k - 1]["sigs"]):
			same_adj += 1
	var open_gaps := 0
	for gp in gaps:
		if float(gp) >= VERGE_GAP_MIN:
			open_gaps += 1
	if G.size() < 4:
		why.append("群れ %d < 4" % G.size())
	if widest > VERGE_WIDE_MAX:
		why.append("一続きの帯 %.1f m > %.1f m" % [widest, VERGE_WIDE_MAX])
	if open_gaps < 3:
		why.append("切れ目（≥ %.1f m）%d < 3" % [VERGE_GAP_MIN, open_gaps])
	if same_adj > 0:
		why.append("隣り合う群れの配合が同じ %d" % same_adj)
	if species.size() < 5:
		why.append("種類 %d < 5" % species.size())
	if tall_n < 1:
		why.append("高い群（≥ 4 m）が無い")
	if low_n < 1:
		why.append("低い群（≤ 1.5 m）が無い")
	return {"ok": why.is_empty(), "why": why, "groups": G.size(), "widest": widest, "gaps": gaps, "open_gaps": open_gaps, "species": species.size(), "tall": tall_n, "low": low_n, "same_adj": same_adj, "G": G}


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


## 農路の南の路肩（相機 cT7 の左）：R1 は『同じ配合（低木・躑躅・笹・羊歯）の群れ 4 つ』を並べ、手前の 2 群は 11 m 続く一つの帯になって形が反復した（使用者 2026-10-15）。
##   → 高さ・間隔・種類の違う 4 つの群落にし、群落の間を空ける（足元の外周どうしで 3 m 前後）：
##   A 小高木＋笹・羊歯の下草（高い）／B 躑躅の低い塊 2（道の縁・低い）／C 笹の叢＋小高木 young_broad_b（畦寄り）／D 低木＋躑躅（手前・中背）。
##   各群の足元の幅は 2.4–5.2 m、道の縁からの距離も群落ごとに変える（B は縁・A と C は畦寄り）。小高木 young_broad_b は C3_road の先頭で置く。
const VERGE_SOUTH := [
	# [id, x, z, scale]  A（x 333–337）
	["young_broad_a", 335.2, 75.6, 1.25], ["sasa_a", 336.0, 73.9, 0.95], ["fern_a", 334.3, 74.4, 1.00],
	# B（x 341–344・道の縁）
	["tsutsuji_a", 342.4, 73.3, 1.20], ["tsutsuji_a", 343.2, 74.5, 0.80],
	# C（x 347–352・畦寄り）
	["sasa_a", 349.4, 74.7, 1.35], ["sasa_a", 351.0, 73.5, 1.10], ["fern_a", 348.2, 75.3, 1.00],
	# D（x 355–358・手前）
	["shrub_a", 356.6, 74.6, 1.30], ["tsutsuji_a", 357.4, 75.7, 0.90],
]


static func _verge_south(C: Dictionary, items: Array, meta: Dictionary) -> int:
	var cnt := 0
	for e: Array in VERGE_SOUTH:
		if not _plant(C, items, String(e[0]), float(e[1]), float(e[2]), float(e[3]), meta, 0.5).is_empty():
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
## 巷のフレーム：原点 O＝(234.8, −87.8)、s＝東へ（0.97, 0.24）、o＝南へ（−0.24, 0.97）＝+z 側（村の北は −z）。北側の列（073–076）の正面は o≈−2.3、南側の列（071・072）の正面は o≈+2.4
static func lane(s: float, o: float) -> Vector2:
	return Vector2(234.8 + 0.97 * s - 0.24 * o, -87.8 + 0.24 * s + 0.97 * o)


## 巷の軸 d＝(0.97, 0.24)（東向き）、北側の列（074/075/076）の正面は南向き nS＝(−0.24, 0.97)
## 実測（W9 survey）：北側の列の背後 z −104 以北・南側の列の背後 z −73 以南は空き。宅間は 073|074＝x 224–227、075|076＝x 242–244、071|072＝x 237–238

static func design_B3(_C: Dictionary) -> Array:
	var D: Array = []
	# 注：id の south／north は当初の取り違えの名残り（B3_back_south＝実際は北側の列 073–076、B3_back_north＝南側の列 071・072）。ノード名を変えるとシーンが変わるので据え置き
	D.append({"id": "B3_back_south", "zone": "B3", "desc": "北側の列（073–076）の背後の樹冠：巷から見上げた屋根の上に緑と高さの変化（紅葉・楢・欅ふう）", "center": Vector2(235.0, -106.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "宅地を持つ家々", "why": "北側の列の家々の裏手に残された庭木（屋根の背後に樹冠が重なり、一続きの屋根並みにならない）"}, true)
		_plant(C2, items, "shii_a", 219.0, -105.0, 0.70, m, 2.5)
		_plant(C2, items, "konara_b", 231.0, -106.5, 0.88, m, 2.5)
		_plant(C2, items, "kuromatsu_a", 240.5, -107.0, 0.62, m, 2.5)
		_plant(C2, items, "young_broad_b", 249.5, -106.0, 1.35, m, 2.5)
		_plant(C2, items, "konara_b", 225.0, -107.5, 0.70, m, 2.5)})
	D.append({"id": "B3_back_north", "zone": "B3", "desc": "南側の列（071・072）の背後の樹冠：巷を西から見ると屋根の上に枝が重なる", "center": Vector2(233.0, -70.0), "run": func(C2: Dictionary, items: Array, meta: Dictionary) -> void:
		var m := meta.duplicate()
		m.merge({"who": "宅地を持つ家々", "why": "南側の列の家々の裏手の庭木（巷の奥行を作り、屋根並みの背景を緑にする）"}, true)
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
		m.merge({"who": "南側の列の二戸", "why": "板葺きの家と隣家の間の板塀と庭木"}, true)
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
		# R2（使用者 2026-10-15・cT4）：榎を農路の入口（相機の 3.6 m 前＝画面の 19 %・農舎と水路を隠していた）から、主屋の背後の列（椎と楢の間）へ移す。
		# 屋敷林は『主屋の背後の西の列』という設計に戻り、北から来る道と庭先の見通しの帯（x 316–324）は空く
		_plant(C2, items, "enoki_a", 311.0, 85.8, 0.74, m, 2.5)
		# R2b：榎を外すと次に大きい黒松（北西の角・相機の 9.9 m 前）が農舎の見える面積の 18.5 % を覆った（ID パス実測）。黒松も主屋の背後の列（赤松と椎の間）へ移す
		_plant(C2, items, "kuromatsu_a", 310.6, 79.4, 0.70, m, 2.0)})
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
		_verge_south(C2, items, m)})
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
