extends RefCounted
## 人間之里 V2 P9 R3 Bamboo／Village Edge：竹林擺放規劃＋烘焙（竹 Kit＝P9 R3 ART_APPROVED 資產本體）。
##
## 位置（ART-FIRST；R2 林帶 forest_p9.scn 封存不動，竹只放進 R2 留下的空間）：
##   - 西林竹林 A（入口竹林）：R2 西林中段橫斷草地（WEST_CUTS z −30）的下坡半段，背靠町家後方，入口面向 WestLane 盡頭的空地；
##     竹林內一條踏跡小徑＋一個林內空洞；上坡半段保留 R2 草地（西林仍是「林分－竹－草地」交替，不連成一整條）。
##   - 西林竹林 B（溪畔竹林）：WestStream 出林處（R2 橫斷 z −150）沿溪兩岸的竹藪，南半段保留草地。
##   - 村緣竹叢：林緣（溪口北、西林南段 C 段林緣）與村西南角 WestStream 兩岸的小竹叢（屋敷林／溪畔竹藪）。
## 空間結構：竹林強度場 s（多個不規則 blob＋雜訊扭曲邊界，0＝外、1＝核心）決定密度、樹種、高度：
##   核心（s > 0.6）密、成竹／孟宗竹為主、林內暗；林緣（s < 0.45）疏、若竹／淡竹／傾き竹外傾、筍；
##   與 R2 林帶交界：s 0.12–0.35 的「侵入帶」只在 R2 樹幹之間疏植細竹（竹往雜木林裡長，不切直線）。
##   高度：林緣低、核心高，但再乘低頻群落雜訊與 6 % 突出高稈，避免整片圓頂（R3 審圖的遠景圓頂樹籬問題）。
## 與 R2 共存：竹稈離 R2 樹幹 ≥ 樹幹半徑＋0.6 m、離 R2 灌木地被 ≥ 0.6 m；核心竹不放在 R2 林冠樹冠半徑 0.6 倍以內（竹稈不穿樹冠）。
## 烘焙：竹稈＝近級（LOD0／1）逐稈節點（可單獨選取）＋遠級（LOD2／3）MultiMesh 分塊；落葉地被／筍＝全部 MultiMesh 分塊；
##   碰撞＝每 32 m 塊一個 StaticBody3D、每稈一根圓柱。色調走 instance uniform（leaf_tint／leaf_sat），依低頻場分組。

const FLib := preload("res://tools/village_v2_forest_lib.gd")
const TLib := preload("res://tools/village_v2_terrain_lib.gd")
const VLib := preload("res://tools/village_v2_veg_lib.gd")
const BLib := preload("res://tools/village_v2_bamboo_lib.gd")

const KIT := "res://assets/village_v2/bamboo_kit"
const OUTPUT := "res://maps/village_v2/gen/bamboo_p9.scn"
const NODE_NAME := "BambooP9"
const CHUNK := 32.0
const NEAR_LODS := 2
const SEED := 9303

## 竹林 blob：[cx, cz, rx, rz, 旋轉(度)]；line：沿折線的膠囊 [pts, 半徑]
const GROVES := [
	# A：小徑從村側斜穿竹林中段（兩側都是竹），途中開一個林內空洞再往上坡出林；南側 blob 讓小徑不是貼著林緣走
	{"name": "A_入口竹林", "blobs": [[90.0, -28.0, 26.0, 15.0, -12.0], [72.0, -24.0, 13.0, 11.0, 0.0], [104.0, -16.0, 11.0, 9.0, 30.0],
		[98.0, -40.0, 12.0, 8.0, -20.0], [101.0, -4.0, 13.0, 7.5, -32.0], [86.0, -8.0, 9.0, 7.0, 0.0]], "lines": []},
	{"name": "B_溪畔竹林", "blobs": [[101.0, -151.0, 8.0, 8.0, 0.0], [72.0, -182.0, 11.0, 8.0, 15.0]],
		"lines": [[[[58.0, -181.0], [86.0, -174.0], [110.0, -167.0]], 7.5]]},
	{"name": "C_村緣竹叢", "blobs": [[106.0, -136.0, 7.0, 6.0, 0.0], [107.0, 74.0, 7.0, 11.0, 0.0], [118.0, 102.0, 5.5, 13.0, 8.0],
		[141.0, 108.0, 6.0, 5.0, -10.0]], "lines": []},
]
## 竹林內踏跡小徑（不鋪面，只保持無竹）：[pts, 半寬]
const PATHS := [
	[[[120.6, 2.4], [112.4, -3.4], [93.0, -15.5], [90.0, -19.0], [86.0, -23.5], [74.0, -27.0], [57.0, -36.0]], 1.3],
	[[[114.0, -148.0], [100.0, -146.5], [88.0, -154.0], [76.0, -163.0]], 1.0],
]
## 林內空洞：[cx, cz, r]
const CLEARINGS := [[96.0, -20.5, 7.0], [64.0, -19.0, 3.0]]
## 竹林入口（踏跡小徑起點）：喇叭口（只清竹稈、保留落葉）＋兩側各一根孟宗竹當門柱：[cx, cz, r, 門柱 A, 門柱 B]
const MOUTHS := [[112.0, -3.7, 3.4, [110.6, -1.6], [113.0, -6.3]]]
## 入口視廊：從 WestLane 盡頭（相機）沿小徑前 18 m 看進去，視廊半寬內不放竹稈（入口讀得出「開口」，不只是一道竹牆）
const MOUTH_VIEW := [[Vector2(124.0, 4.9), Vector2(93.0, -15.5), 2.0]]

const S_MIN := 0.12          # 低於此＝竹林外
const S_INVADE := 0.35       # s 0.12–0.35＝侵入帶（只在 R2 樹之間疏植細竹）
const S_CORE := 0.6
const SPACING := [0.78, 1.9]  # 核心／林緣最小稈距（m）
const R2_TRUNK_PAD := 0.6
const R2_UNDER_PAD := 0.6
const R2_CROWN_CORE := 0.6   # 核心竹離 R2 林冠樹（canopy／sub／slope）≥ 冠半徑 × 此值
const R2_CROWN_INV := 0.35   # 侵入帶 ≥ 冠半徑 × 此值
const SLOPE_MAX := 35.0
const EMERGENT := 0.09

const CORE_MIX := {"take_mature": 56, "take_thick": 24, "take_thin": 9, "take_young": 5, "take_dead": 3.5, "take_broken": 2.5}
const EDGE_MIX := {"take_young": 26, "take_thin": 30, "take_lean": 16, "take_mature": 22, "take_dead": 4, "take_broken": 2}
const INVADE_MIX := {"take_thin": 45, "take_young": 35, "take_lean": 12, "take_dead": 8}
## 竹林色調：比 R2 闊葉／杉明亮偏黃綠（竹林在遠景靠色相分辨）；落葉地被壓暗、降彩（不要稻草黃補丁）
const PRESETS := ["mature", "young", "mature", "yellow", "deep"]
const LITTER_PRESET := {"core": "litter_core", "edge": "litter_edge"}
## 落葉地被色調（擺放層自己的 instance uniform；R1 COLOR_PRESETS 封存不動）：乾竹葉在林床偏灰褐、不要稻草黃
const OWN_PRESETS := {"litter_core": [Vector3(0.62, 0.58, 0.54), 0.62], "litter_edge": [Vector3(0.7, 0.66, 0.6), 0.7]}
## 竹林 LOD 換檔距離倍率（擺放層：竹稈 prefab 25／60／140 m → ×1.5；遠景少變團塊，成本記 P12）
const LOD_SCALE := 1.5


static func modules() -> Dictionary:
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT + "/src/modules_blender.json"))
	return (m as Dictionary)["trees"] if m is Dictionary else {}


# ─────────────────────────── 強度場 ───────────────────────────

class Field:
	var groves: Array = GROVES
	var warp: FastNoiseLite
	var clump: FastNoiseLite
	var tone: FastNoiseLite

	func _init() -> void:
		warp = FLib._noise(SEED, 0.09)
		clump = FLib._noise(SEED + 1, 0.06)
		tone = FLib._noise(SEED + 2, 0.025)

	## 回傳 [s, grove 索引, 往林外方向（離最強 blob 中心／折線）]
	func at(p: Vector2) -> Array:
		var best := 0.0
		var gi := -1
		var outv := Vector2.ZERO
		var w := 0.78 + 0.44 * FLib._n01(warp, p.x, p.y)
		for g in groves.size():
			var G: Dictionary = groves[g]
			for b: Array in G["blobs"]:
				var a := deg_to_rad(float(b[4]))
				var d := (p - Vector2(float(b[0]), float(b[1]))).rotated(-a)
				var e := sqrt(pow(d.x / float(b[2]), 2.0) + pow(d.y / float(b[3]), 2.0)) * w
				# 竹林不是一整塊：中頻雜訊讓林分內部疏密成叢（俯瞰不成一顆封閉圓頂、林緣有凹凸）
				var s := (1.0 - smoothstep(0.35, 1.45, e)) * lerpf(0.62, 1.0, smoothstep(0.32, 0.6, FLib._n01(clump, p.x * 1.3 + 17.0, p.y * 1.3)))
				if s > best:
					best = s
					gi = g
					outv = p - Vector2(float(b[0]), float(b[1]))
			for ln: Array in G["lines"]:
				var pts := PackedVector2Array()
				for q: Array in ln[0]:
					pts.append(Vector2(float(q[0]), float(q[1])))
				var nr := FLib._near(pts, p)
				var e := nr.x / float(ln[1]) * w
				# 溪畔竹藪沿溪斷成數叢（低頻雜訊 → 叢與叢之間留空，看得到後方雜木林），不連成一條竹牆
				var s := (1.0 - smoothstep(0.35, 1.45, e)) * smoothstep(0.3, 0.55, FLib._n01(clump, p.x * 1.6, p.y * 1.6))
				if s > best:
					best = s
					gi = g
					var i := int(nr.y)
					outv = p - pts[i].lerp(pts[i + 1], nr.z)
		return [best, gi, outv.normalized() if outv.length() > 1e-4 else Vector2.RIGHT]

	func grad(p: Vector2) -> Vector2:
		var h := 1.0
		return Vector2(float(at(p + Vector2(h, 0))[0]) - float(at(p - Vector2(h, 0))[0]),
			float(at(p + Vector2(0, h))[0]) - float(at(p - Vector2(0, h))[0])) / (2.0 * h)


static func path_d(p: Vector2) -> float:
	var best := INF
	for pa: Array in PATHS:
		var pts := PackedVector2Array()
		for q: Array in pa[0]:
			pts.append(Vector2(float(q[0]), float(q[1])))
		best = minf(best, FLib._near(pts, p).x - float(pa[1]))
	return best


## 村緣：建成區外框（+M_BUILT 已是禁區）往外 8–14 m 漸弱（雜訊抖動），竹林朝村子那側不會沿外框切出一道直線
static func village_fade(C: FLib.Ctx, F: Field, p: Vector2) -> float:
	var d := -TLib.outline_sd(C.outlines, p)
	return smoothstep(FLib.M_BUILT, FLib.M_BUILT + 8.0 + 6.0 * FLib._n01(F.warp, p.x * 2.3, p.y * 2.3), d)


## 林內空洞外圈（r–r+4 m）：竹稈矮化＋背向空洞外傾 → 從空洞看得到天空開口
static func clearing_ring(p: Vector2) -> Array:
	for c: Array in CLEARINGS:
		var cc := Vector2(float(c[0]), float(c[1]))
		var d := p.distance_to(cc) - float(c[2])
		if d >= 0.0 and d < 4.0:
			return [1.0 - d / 4.0, (p - cc).normalized()]
	return [0.0, Vector2.ZERO]


static func in_clearing(p: Vector2) -> bool:
	for c: Array in CLEARINGS:
		if p.distance_to(Vector2(float(c[0]), float(c[1]))) < float(c[2]):
			return true
	return false


static func in_mouth(p: Vector2) -> bool:
	for m: Array in MOUTHS:
		if p.distance_to(Vector2(float(m[0]), float(m[1]))) < float(m[2]):
			return true
	for mv: Array in MOUTH_VIEW:
		var a: Vector2 = mv[0]
		var b: Vector2 = mv[1]
		var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		if p.distance_to(a.lerp(b, t)) < float(mv[2]):
			return true
	return false


## R2 林帶（封存 overlay）裡的樹：[Vector2, tid, sc, layer, trunk_r, crown_r]
static func r2_trees(v: Node3D) -> Array:
	var out: Array = []
	var fo := v.get_node_or_null("Vegetation/" + FLib.NODE_NAME)
	if fo == null:
		return out
	var M := FLib.modules()
	for t in fo.get_node("Near").find_children("*", "Node3D", true, false):
		if not t.has_meta("veg_id"):
			continue
		var n := t as Node3D
		var tid := String(n.get_meta("veg_id"))
		var sc := n.transform.basis.get_scale().x
		var col: Array = M[tid].get("collision", [])
		var tr := float(col[0]["r"]) * sc if not col.is_empty() else 0.0
		out.append([Vector2(n.position.x, n.position.z), tid, sc, String(n.get_meta("layer")), tr,
			float(M[tid]["crown_w"]) * 0.5 * sc])
	return out


class Grid:
	var cell := 4.0
	var bins := {}

	func add(p: Vector2, v: Variant) -> void:
		var k := Vector2i(floori(p.x / cell), floori(p.y / cell))
		if not bins.has(k):
			bins[k] = []
		(bins[k] as Array).append(v)

	func near(p: Vector2, r: float) -> Array:
		var out: Array = []
		var n := int(ceil(r / cell))
		var k0 := Vector2i(floori(p.x / cell), floori(p.y / cell))
		for j in range(-n, n + 1):
			for i in range(-n, n + 1):
				var k := k0 + Vector2i(i, j)
				if bins.has(k):
					out.append_array(bins[k])
		return out


## R2 衝突原因（空字串＝可種）
static func r2_conflict(r2g: Grid, p: Vector2, s: float, culm_r: float) -> String:
	for t: Array in r2g.near(p, 8.0):
		var d := p.distance_to(t[0])
		var lay := String(t[3])
		var tid := String(t[1])
		if float(t[4]) > 0.0 and d < float(t[4]) + culm_r + R2_TRUNK_PAD:
			return "trunk"
		if tid in FLib.UNDER_IDS and d < R2_UNDER_PAD:
			return "under"
		if lay in ["canopy", "sub", "slope", "edge"] and not (tid in FLib.YOUNG_IDS):
			var k := R2_CROWN_CORE if s >= S_INVADE else R2_CROWN_INV
			if d < float(t[5]) * k:
				return "crown"
	return ""


# ─────────────────────────── 規劃 ───────────────────────────

static func plan(v: Node3D, L: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var C := FLib.context(v, L)
	var F := Field.new()
	var M := modules()
	var r2 := r2_trees(v)
	var r2g := Grid.new()
	for t: Array in r2:
		r2g.add(t[0], t)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	# 候選：所有 grove 的外框（blob 外接）內 0.5 m 抖動格、打亂
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for G: Dictionary in GROVES:
		for b: Array in G["blobs"]:
			var r := maxf(float(b[2]), float(b[3])) * 1.5
			lo = Vector2(minf(lo.x, float(b[0]) - r), minf(lo.y, float(b[1]) - r))
			hi = Vector2(maxf(hi.x, float(b[0]) + r), maxf(hi.y, float(b[1]) + r))
		for ln: Array in G["lines"]:
			for q: Array in ln[0]:
				var r := float(ln[1]) * 1.5
				lo = Vector2(minf(lo.x, float(q[0]) - r), minf(lo.y, float(q[1]) - r))
				hi = Vector2(maxf(hi.x, float(q[0]) + r), maxf(hi.y, float(q[1]) + r))
	var cand: Array = []
	var step := 0.5
	var x := lo.x
	while x < hi.x:
		var z := lo.y
		while z < hi.y:
			cand.append(Vector2(x + rng.randf() * step, z + rng.randf() * step))
			z += step
		x += step
	FLib._shuffle(rng, cand)
	var items: Array = []
	var ig := Grid.new()
	var why := {}
	for p: Vector2 in cand:
		var sg: Array = F.at(p)
		var s: float = sg[0]
		if s < S_MIN:
			continue
		s *= village_fade(C, F, p)
		if s < S_MIN:
			continue
		# 接受機率：核心 1、林緣遞減、侵入帶 0.3
		var acc := lerpf(0.25, 1.0, smoothstep(S_INVADE, 0.75, s)) if s >= S_INVADE else 0.22
		if rng.randf() > acc:
			continue
		var b := FLib.blocked(C, p)
		if b != "":
			why[b] = int(why.get(b, 0)) + 1
			continue
		if path_d(p) < 0.15 or in_clearing(p) or in_mouth(p):
			why["path"] = int(why.get("path", 0)) + 1
			continue
		if FLib.slope_deg(C, p) > SLOPE_MAX:
			why["slope"] = int(why.get("slope", 0)) + 1
			continue
		# 種別
		var tid: String
		var mix: Dictionary = CORE_MIX if s >= S_CORE else (EDGE_MIX if s >= S_INVADE else INVADE_MIX)
		tid = FLib._pick(rng, mix)
		var dbh := float(M[tid]["dbh_m"])
		var rc := r2_conflict(r2g, p, s, dbh * 0.5)
		if rc != "":
			why["r2_" + rc] = int(why.get("r2_" + rc, 0)) + 1
			continue
		var sp := lerpf(SPACING[1], SPACING[0], smoothstep(0.2, 0.85, s))
		var ok := true
		for q: Dictionary in ig.near(p, sp + 0.1):
			if (q["p"] as Vector2).distance_to(p) < sp:
				ok = false
				break
		if not ok:
			continue
		var y := FLib.ground(C, p, 0.12)
		if is_nan(y):
			continue
		# 高度：核心高、林緣低 × 低頻群落 × 少數突出高稈（不做整片圓頂）
		var cl := (0.8 + 0.32 * FLib._n01(F.clump, p.x, p.y)) * (0.88 + 0.24 * FLib._n01(F.clump, p.x * 3.1 + 40.0, p.y * 3.1))
		# 稈高主要由群落雜訊決定（同齡叢），林緣只略矮（0.82）：「中心高、外圍低」的包絡就是遠景圓頂的來源
		var sc := lerpf(0.82, 1.0, smoothstep(0.2, 0.6, s)) * cl * rng.randf_range(0.9, 1.08)
		var ring: Array = clearing_ring(p)
		sc *= 1.0 - 0.35 * float(ring[0])
		if rng.randf() < EMERGENT:
			sc *= 1.25
		sc = clampf(sc, 0.5, 1.2)
		var out_dir: Vector2 = sg[2] if float(ring[0]) <= 0.0 else (ring[1] as Vector2)
		# 竹稈傾向（Blender 本地 +x）一律朝林外：傾き竹 ±20°、其他 ±50°（竹林往光處外傾、稈不互相交叉）；核心深處（s > 0.9）隨機
		var spread := 0.35 if tid == "take_lean" else (0.9 if s < 0.9 else PI)
		var yaw := atan2(-out_dir.y, out_dir.x) + rng.randf_range(-spread, spread)
		var tn := FLib._n01(F.tone, p.x, p.y)
		var preset: String = PRESETS[clampi(int(tn * 4.0), 0, 3)]
		if tid in ["take_dead", "take_broken"]:
			preset = "mature"
		var it := {"id": tid, "p": p, "y": y, "yaw": yaw, "sc": sc, "tilt": Vector3(rng.randf_range(-0.012, 0.012), 0.0,
			rng.randf_range(-0.012, 0.012)), "layer": "core" if s >= S_CORE else ("edge" if s >= S_INVADE else "invade"),
			"grove": GROVES[int(sg[1])]["name"], "s": s, "out": out_dir, "preset": preset, "r": dbh * 0.5}
		items.append(it)
		ig.add(p, it)
	# 入口門柱：喇叭口兩側各一根孟宗竹（照常過禁區／R2／稈距檢查，不過就不放）
	for m: Array in MOUTHS:
		for gp: Array in [m[3], m[4]]:
			var p := Vector2(float(gp[0]), float(gp[1]))
			if FLib.blocked(C, p) != "" or r2_conflict(r2g, p, 1.0, 0.085) != "":
				why["gate"] = int(why.get("gate", 0)) + 1
				continue
			for q: Dictionary in ig.near(p, 1.0):
				if (q["p"] as Vector2).distance_to(p) < 0.8:
					items.erase(q)
			var y := FLib.ground(C, p, 0.12)
			var sg: Array = F.at(p)
			var it := {"id": "take_thick", "p": p, "y": y, "yaw": rng.randf() * TAU, "sc": 1.05, "tilt": Vector3.ZERO,
				"layer": "edge", "grove": GROVES[maxi(0, int(sg[1]))]["name"], "s": float(sg[0]), "out": sg[2],
				"preset": "yellow", "r": float(M["take_thick"]["dbh_m"]) * 0.5, "gate": true}
			items.append(it)
			ig.add(p, it)
	# 筍：林緣與核心的若竹附近（決定性）；落葉地被：s > 0.2 處 1.5 m 抖動格（核心近連續、外緣漸疏）
	var extras: Array = []
	for it: Dictionary in items:
		if String(it["id"]) == "take_young" and rng.randf() < 0.45:
			var q: Vector2 = (it["p"] as Vector2) + Vector2(rng.randf_range(0.5, 1.6), 0).rotated(rng.randf() * TAU)
			if FLib.blocked(C, q) == "" and path_d(q) > 0.3 and r2_conflict(r2g, q, 1.0, 0.1) != "trunk":
				var ok := true
				for o: Dictionary in ig.near(q, 0.6):
					if (o["p"] as Vector2).distance_to(q) < 0.45:
						ok = false
				if ok:
					extras.append({"id": "takenoko", "p": q, "y": FLib.ground(C, q, 0.12) + FLib.EMBED - 0.03, "yaw": rng.randf() * TAU,
						"sc": rng.randf_range(0.6, 1.4), "tilt": Vector3.ZERO, "layer": "shoot", "grove": it["grove"], "s": it["s"],
						"out": Vector2.ZERO, "preset": "mature", "r": 0.0})
	var xx := lo.x
	while xx < hi.x:
		var zz := lo.y
		while zz < hi.y:
			var q := Vector2(xx + rng.randf() * 1.5, zz + rng.randf() * 1.5)
			var s: float = float(F.at(q)[0]) * village_fade(C, F, q)
			var lsc := rng.randf_range(0.75, 1.25)
			# 踏跡小徑＝落葉被踩開的裸土帶（patch 半徑 1.75 m × 縮放不得蓋到路寬）
			if s > 0.2 and rng.randf() < lerpf(0.1, 1.0, smoothstep(0.2, 0.65, s)) and FLib.blocked(C, q) == "" \
					and path_d(q) > 1.75 * lsc - 0.5 and not in_mouth(q):
				var h := C.S.h(q.x, q.y)
				if not is_nan(h):
					var d := 0.8
					var nx := C.S.h(q.x + d, q.y) - C.S.h(q.x - d, q.y)
					var nz := C.S.h(q.x, q.y + d) - C.S.h(q.x, q.y - d)
					var nrm := Vector3(-nx, 2.0 * d, -nz).normalized()
					if not (is_nan(nx) or is_nan(nz)):
						extras.append({"id": "take_litter", "p": q, "y": h - 0.004, "yaw": rng.randf() * TAU,
							"sc": lsc, "tilt": Vector3.ZERO, "normal": nrm, "layer": "litter",
							"grove": GROVES[int(F.at(q)[1])]["name"], "s": s, "out": Vector2.ZERO,
							"preset": LITTER_PRESET["core" if s >= S_CORE else "edge"], "r": 0.0})
			zz += 1.5
		xx += 1.5
	items.append_array(extras)
	return {"items": items, "ctx": C, "field": F, "r2": r2, "r2_grid": r2g, "rejected": why,
		"ms": Time.get_ticks_msec() - t0}


# ─────────────────────────── 變換／烘焙 ───────────────────────────

static func xf_of(it: Dictionary) -> Transform3D:
	var sc := float(it["sc"])
	var b := Basis(Vector3.UP, float(it["yaw"]))
	if it.has("normal"):
		var n: Vector3 = it["normal"]
		var ax := Vector3.UP.cross(n)
		if ax.length() > 1e-5:
			b = Basis(ax.normalized(), Vector3.UP.angle_to(n)) * b
	else:
		var tl: Vector3 = it["tilt"]
		b = Basis.from_euler(Vector3(tl.x, 0.0, tl.z)) * b
	b = b.scaled(Vector3(sc, sc, sc))
	var p: Vector2 = it["p"]
	return Transform3D(b, Vector3(p.x, float(it["y"]), p.y))


static func chunk_key(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))


static func bake(items: Array) -> Node3D:
	var M := modules()
	var root := Node3D.new()
	root.name = NODE_NAME
	var protos := {}
	for it: Dictionary in items:
		var tid := String(it["id"])
		if not protos.has(tid):
			protos[tid] = (load(BLib.TREE_DIR + "/%s.tscn" % tid) as PackedScene).instantiate()
	var culms: Array = items.filter(func(it: Dictionary) -> bool: return String(M[it["id"]]["cls"]) == "bamboo")
	# 1) 近級：Near/C_<塊>/<編號>_<種>（擺放變換）→ LOD0、LOD1
	var near := Node3D.new()
	near.name = "Near"
	root.add_child(near)
	var near_chunks := {}
	var n_near := 0
	for k in culms.size():
		var it: Dictionary = culms[k]
		var tid := String(it["id"])
		var ck := chunk_key(it["p"])
		if not near_chunks.has(ck):
			var cn := Node3D.new()
			cn.name = "C_%d_%d" % [ck.x, ck.y]
			near.add_child(cn)
			near_chunks[ck] = cn
		var t := Node3D.new()
		t.name = "%04d_%s" % [k, tid]
		t.transform = xf_of(it)
		t.set_meta("veg_id", tid)
		t.set_meta("layer", it["layer"])
		t.set_meta("grove", it["grove"])
		t.set_meta("preset", it["preset"])
		(near_chunks[ck] as Node).add_child(t)
		var pr: Array = VLib.COLOR_PRESETS.get(it["preset"], VLib.COLOR_PRESETS["mature"])
		for lod in NEAR_LODS:
			var src := (protos[tid] as Node).get_node("LOD%d" % lod) as MeshInstance3D
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % lod
			mi.mesh = src.mesh
			for prop in ["visibility_range_begin_margin", "visibility_range_end_margin", "visibility_range_fade_mode", "cast_shadow"]:
				mi.set(prop, src.get(prop))
			mi.visibility_range_begin = src.visibility_range_begin * LOD_SCALE
			mi.visibility_range_end = src.visibility_range_end * LOD_SCALE
			mi.set_instance_shader_parameter("lod_band", (src.get_instance_shader_parameter("lod_band") as Vector4) * LOD_SCALE)
			mi.set_instance_shader_parameter("lod_ref", src.get_instance_shader_parameter("lod_ref"))
			mi.set_instance_shader_parameter("leaf_tint", pr[0])
			mi.set_instance_shader_parameter("leaf_sat", pr[1])
			t.add_child(mi)
			n_near += 1
	# 2) MultiMesh：竹稈 LOD2／3；落葉地被與筍全部級（Far/LODk/C_<塊>/<種_色調>）
	var far := Node3D.new()
	far.name = "Far"
	root.add_child(far)
	var n_mmi := 0
	var n_inst := 0
	for lod in 4:
		var groups := {}
		for it: Dictionary in items:
			var tid := String(it["id"])
			var is_culm := String(M[tid]["cls"]) == "bamboo"
			if lod >= (M[tid]["lods"] as Array).size() or (is_culm and lod < NEAR_LODS):
				continue
			var ck := chunk_key(it["p"])
			var gk := "%d_%d|%s|%s" % [ck.x, ck.y, tid, it["preset"]]
			if not groups.has(gk):
				groups[gk] = []
			(groups[gk] as Array).append(it)
		if groups.is_empty():
			continue
		var ln := Node3D.new()
		ln.name = "LOD%d" % lod
		far.add_child(ln)
		var gkeys := groups.keys()
		gkeys.sort()
		var chunk_nodes := {}
		for gk: String in gkeys:
			var parts := gk.split("|")
			var tid := parts[1]
			var src := (protos[tid] as Node).get_node("LOD%d" % lod) as MeshInstance3D
			var arr: Array = groups[gk]
			if not chunk_nodes.has(parts[0]):
				var cn := Node3D.new()
				cn.name = "C_" + parts[0]
				ln.add_child(cn)
				chunk_nodes[parts[0]] = cn
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = src.mesh
			mm.instance_count = arr.size()
			var ab := AABB()
			for k in arr.size():
				var xf := xf_of(arr[k])
				mm.set_instance_transform(k, xf)
				var wb: AABB = xf * src.mesh.get_aabb()
				ab = wb if k == 0 else ab.merge(wb)
			mm.custom_aabb = ab
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%s" % [tid, parts[2]]
			mmi.multimesh = mm
			var ls := LOD_SCALE if String(M[tid]["cls"]) == "bamboo" else 1.0
			mmi.set_instance_shader_parameter("lod_band", (src.get_instance_shader_parameter("lod_band") as Vector4) * ls)
			mmi.set_instance_shader_parameter("lod_ref", src.get_instance_shader_parameter("lod_ref"))
			var pr: Array = OWN_PRESETS.get(parts[2], VLib.COLOR_PRESETS.get(parts[2], VLib.COLOR_PRESETS["mature"]))
			mmi.set_instance_shader_parameter("leaf_tint", pr[0])
			mmi.set_instance_shader_parameter("leaf_sat", pr[1])
			var hd := Vector2(ab.size.x, ab.size.z).length() * 0.5
			mmi.visibility_range_begin = maxf(0.0, src.visibility_range_begin * ls - hd) if src.visibility_range_begin > 0.0 else 0.0
			mmi.visibility_range_end = src.visibility_range_end * ls + hd if src.visibility_range_end > 0.0 else 0.0
			mmi.cast_shadow = src.cast_shadow
			mmi.set_meta("veg_id", tid)
			mmi.set_meta("instances", arr.size())
			(chunk_nodes[parts[0]] as Node).add_child(mmi)
			n_mmi += 1
			n_inst += arr.size()
	# 3) 竹稈碰撞：每 32 m 塊一個 StaticBody3D、每稈一根圓柱（prefab 碰撞＝稈基到 3 m 高）
	var col_root := Node3D.new()
	col_root.name = "Collision"
	root.add_child(col_root)
	var bodies := {}
	var n_shape := 0
	for it: Dictionary in culms:
		var col: Array = M[it["id"]].get("collision", [])
		if col.is_empty():
			continue
		var ck := chunk_key(it["p"])
		if not bodies.has(ck):
			var sb := StaticBody3D.new()
			sb.name = "C_%d_%d" % [ck.x, ck.y]
			sb.set_meta("bamboo", true)
			col_root.add_child(sb)
			bodies[ck] = sb
		var xf := xf_of(it)
		for c: Dictionary in col:
			var pa := xf * VLib._v(c["a"])
			var pb := xf * VLib._v(c["b"])
			var cs := CollisionShape3D.new()
			cs.name = "T%d" % n_shape
			var sh := CylinderShape3D.new()
			sh.radius = float(c["r"]) * float(it["sc"])
			sh.height = pa.distance_to(pb)
			cs.shape = sh
			var up := (pb - pa).normalized()
			var x := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
			var z := x.cross(up).normalized()
			cs.transform = Transform3D(Basis(x, up, z), (pa + pb) * 0.5)
			(bodies[ck] as Node).add_child(cs)
			n_shape += 1
	for tid in protos:
		(protos[tid] as Node).free()
	root.set_meta("culms", culms.size())
	root.set_meta("items", items.size())
	root.set_meta("near_mesh_nodes", n_near)
	root.set_meta("multimesh_nodes", n_mmi)
	root.set_meta("multimesh_instances", n_inst)
	root.set_meta("culm_shapes", n_shape)
	root.set_meta("art_revision", "P9 R3 Bamboo／Village Edge：西林竹林 A／B＋村緣竹叢（竹 Kit ART_APPROVED；擺放 ART_REVIEW）")
	return root


static func own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		own(c, owner)
