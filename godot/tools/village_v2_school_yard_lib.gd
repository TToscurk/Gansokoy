extends RefCounted
## 人間之里 V2 P9 R4-3 Hero Surroundings：寺子屋周邊（ART-FIRST）。
##   規劃（plan）＋烘焙（bake）→ maps/village_v2/gen/school_yard_p9.scn → village_v2.tscn 掛 Vegetation/SchoolYardP9
##   （ForestP9 → BambooP9 → HiedaGardenP9 → ShrineGroveP9 → SchoolYardP9）。
##   寺子屋 Hero 本體（P5 R3 ART_APPROVED：幟、告示 2、立看板、石燈籠、花壇 2 已在本體內）不動；本包只加「每天有人上課、進出、停留」的痕跡。
##   重用（只讀）：R1 樹 prefab（落葉闊葉／楓／櫻／幼樹／灌木；不用杉檜）、R4 garden_kit 雨落ち縁石、R4-2 神社周邊的地面 shader
##   （sg_ground.gdshader：玉砂利／苔／踏み固め土／落葉＋外緣淡出）與 prefab 展開工具；新構件＝school_kit（build_school_kit.py）。
## 構成（寺子屋正面＝+x、朝西巷 WestAlley；台基 x 183–193、z 15.5–32.5；屋根外緣 x 181.6、z 14.1／33.9；踏石 x 193–195.2、z 21.3–26.8）：
##   1 入口動線：西巷 (208, 24) → 踏石；踏み固め土の道＋前庭の活動場（裸土、端は草へ崩れる）。
##   2 鞋：踏石の上に脱ぎ揃えた草履、一足だけ地面に脱ぎ散らかし；下駄箱は向拝北側の裳階下。
##   3 告示：西巷側の入口に木札「手習所」、南側に掃除当番板。
##   4 生活痕跡：習字の干し竿（南側、半紙 5 枚）、手毬、竹の輪、石蹴りの線（前庭南の空地）、縁台＋木箱（日陰）、手桶。
##   5 樹：日陰の主木＝榎（前庭北東、縁台の上）＋欅（南側院の奥）、楓 2、櫻 1（前庭南東、少量）、幼樹・小楢（後方、雑然）。
##   6 低木・地被：北側牆腳（日陰）＝蕨・灌木、後方＝笹・灌木、前庭角＝躑躅。
##   7 接地：側面・背面の雨落ち（縁石＋砂利帯、濕）、牆腳の苔、天水桶、薪棚（背面裳階下）。
##   正面入口と前庭は空けておく（樹冠も facade の識別を隠さない）。側面・後方は雑に。

const SG := preload("res://tools/village_v2_shrine_grove_lib.gd")
const GL := preload("res://tools/village_v2_hieda_garden_lib.gd")
const TreeLib := preload("res://tools/village_v2_veg_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const FLib := preload("res://tools/village_v2_forest_lib.gd")

const OUTPUT := "res://maps/village_v2/gen/school_yard_p9.scn"
const NODE_NAME := "SchoolYardP9"
const SK := "res://assets/village_v2/school_kit/mesh/"
const GK := "res://assets/village_v2/garden_kit/mesh/"
const SEED := 4431
const LOD_SWITCH := 34.0

## 寺子屋幾何（world；asset.json gate_spec＋Hero collision＋LOD0 AABB 實測）
const BODY := Rect2(182.95, 15.45, 10.66, 17.1)       # Hero Collision/Body 實測（MCP runtime AABB：x 182.95–193.61、z 15.45–32.55）
const ROOF := Rect2(181.58, 14.08, 14.5, 19.85)       # 屋根外緣（前 x 196.1 含前庭 Hero 小物）
const STEP := Rect2(193.0, 21.25, 2.15, 5.5)          # 踏石
const DOOR := Vector2(194.8, 24.0)
const PARCEL := Rect2(176.0, 9.0, 24.0, 30.0)
## Hero 前庭小物（碰撞實測）：幟、告示 L／R、石燈籠、向拝柱 2
const HERO_PROPS := [Vector2(195.9, 27.7), Vector2(195.7, 29.7), Vector2(195.7, 19.4), Vector2(195.4, 16.6),
	Vector2(194.8, 26.3), Vector2(194.8, 21.7)]
const BEDS := [Rect2(193.05, 29.3, 0.45, 3.0), Rect2(193.05, 15.7, 0.45, 3.0)]
const QUEST := [Vector2(199.0, 24.0), Vector2(199.0, 30.0)]
## 入口動線（西巷 → 踏石）
const ENTRY := [Vector2(208.4, 24.3), Vector2(202.0, 24.1), Vector2(195.2, 24.0)]
const ENTRY_HW := 1.3
## 前庭活動場（留白）
const YARD := [Vector2(196.2, 17.4), Vector2(202.6, 17.2), Vector2(203.4, 24.0), Vector2(202.6, 31.6), Vector2(196.4, 32.0)]
const YARD_MAX := 0.08
## 視線（眼高 1.7）：西巷側
const SIGHT_CAMS := [Vector2(213.0, 24.0), Vector2(208.5, 15.0), Vector2(208.5, 33.0), Vector2(220.0, 12.0)]
const FACADE := [Vector3(195.0, 4.6, 24.0), Vector3(194.6, 6.4, 24.0), Vector3(193.6, 3.0, 16.4), Vector3(193.6, 3.0, 31.6),
	Vector3(188.0, 9.4, 24.0), Vector3(193.4, 7.4, 19.0), Vector3(193.4, 7.4, 29.0)]
const REGION := Rect2(166.0, 4.0, 46.0, 46.0)

const CANOPY_OK := ["enoki_a", "keyaki_a", "konara_a", "konara_b", "momiji_a", "momiji_b", "momiji_c", "sakura_somei",
	"sakura_yama", "young_broad_a", "young_broad_b"]
const UNDER_IDS := ["fern_a", "sasa_a", "shrub_a", "tsutsuji_a"]
## 構件外框（local xz 半寬、高）＝碰撞箱；空＝無碰撞（踏める／小物）
const PROP_BOX := {"sk_getabako": [0.60, 0.19, 0.93], "sk_bench": [0.90, 0.25, 0.42], "sk_box": [0.31, 0.21, 0.38],
	"sk_teoke": [0.15, 0.15, 0.46], "sk_tensui": [0.31, 0.31, 0.75], "sk_woodpile": [0.88, 0.28, 0.98],
	"sk_fuda": [0.06, 0.06, 1.3], "sk_toban": [0.46, 0.06, 1.55]}
const POSTS := {"sk_hanshi": [Vector2(-2.8, 0.0), Vector2(2.8, 0.0)]}


static func item(S: RLib.TriSampler, kind: String, id: String, p: Vector2, yaw: float, sc: float, tag: String,
		extra := {}) -> Dictionary:
	var r := 0.25
	if kind == "tree" and not (id in UNDER_IDS):
		r = maxf(SG.trunk_r(id, sc, FLib.modules()) * 0.7, 0.12)
	elif PROP_BOX.has(id):
		r = minf(float(PROP_BOX[id][0]), float(PROP_BOX[id][1]))
	var y := GL.ground(S, p, r) - (0.05 if kind == "tree" else 0.0)
	var it := {"kind": kind, "id": id, "p": p, "y": y, "yaw": yaw, "sc": Vector3.ONE * sc, "tag": tag}
	it.merge(extra, true)
	return it


## 構件外框（world 4 角）
static func prop_corners(it: Dictionary) -> PackedVector2Array:
	var b: Array = PROP_BOX.get(String(it["id"]), [0.12, 0.12, 0.1])
	var s: float = (it["sc"] as Vector3).x
	var yaw: float = it["yaw"]
	var c := cos(yaw)
	var sn := sin(yaw)
	var out := PackedVector2Array()
	for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var lx := q.x * float(b[0]) * s
		var lz := q.y * float(b[1]) * s
		out.append((it["p"] as Vector2) + Vector2(lx * c + lz * sn, -lx * sn + lz * c))
	return out


## 建物 footprint（Districts 有體積的網格）
static func building_rects(v: Node3D) -> Array:
	var out: Array = []
	var root := v.get_node_or_null("Districts")
	if root:
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if not g.is_visible_in_tree():
				continue
			var a := g.global_transform * g.get_aabb()
			if a.size.y < 1.2 or a.size.x > 40.0 or a.size.z > 40.0:
				continue
			var r := Rect2(a.position.x, a.position.z, a.size.x, a.size.z)
			if REGION.grow(8.0).intersects(r):
				out.append(r)
	return out


static func surface_y(v: Node3D, p: Vector2) -> float:
	## 物理表面（地形或寺子屋踏石／台基）最高點
	var space := v.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 6.0, p.y), Vector3(p.x, -3.0, p.y))
	var r := space.intersect_ray(q)
	return float((r["position"] as Vector3).y) if not r.is_empty() else NAN


static func plan(v: Node3D, L: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var S := RLib.terrain_sampler(v)
	var M := FLib.modules()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var items: Array = []
	var bld := building_rects(v)
	# ── 樹（日陰の主木 2、楓 2、櫻 1、後方の幼樹・小楢）
	for q: Array in [["enoki_a", Vector2(200.9, 10.0), 0.9, "shade_tree", "mature"],
			["keyaki_a", Vector2(185.0, 45.4), 0.68, "shade_tree", "mature"],
			["sakura_somei", Vector2(193.2, 43.6), 0.55, "accent_tree", "muted"],
			["momiji_a", Vector2(173.6, 18.8), 0.85, "side_tree", "muted"],
			["momiji_c", Vector2(175.6, 37.8), 0.8, "side_tree", "muted"],
			["young_broad_a", Vector2(174.8, 22.6), 0.95, "back_tree", "young"],
			["young_broad_b", Vector2(172.4, 29.4), 1.0, "back_tree", "mature"],
			["konara_b", Vector2(170.4, 16.6), 0.66, "back_tree", "mature"]]:
		items.append(item(S, "tree", String(q[0]), q[1], rng.randf() * TAU, float(q[2]), String(q[3]), {"preset": String(q[4])}))
	# ── 低木・地被：北側牆腳（日陰）＝蕨・灌木、後方＝笹・灌木（叢）、前庭角＝躑躅
	for q: Array in [["fern_a", Vector2(184.2, 13.1), 1.0], ["shrub_a", Vector2(186.6, 12.7), 0.95], ["fern_a", Vector2(188.3, 13.2), 0.9],
			["shrub_a", Vector2(190.8, 12.8), 0.8], ["fern_a", Vector2(191.9, 13.3), 0.8],
			["sasa_a", Vector2(177.0, 19.6), 0.95], ["shrub_a", Vector2(178.9, 24.6), 1.1], ["fern_a", Vector2(179.9, 26.0), 0.9],
			["sasa_a", Vector2(179.4, 31.3), 0.85], ["shrub_a", Vector2(176.6, 33.4), 0.9], ["fern_a", Vector2(176.4, 13.9), 0.9],
			["tsutsuji_a", Vector2(197.0, 14.9), 0.8], ["tsutsuji_a", Vector2(197.6, 35.3), 0.75], 
			["sasa_a", Vector2(170.9, 23.8), 1.0], ["fern_a", Vector2(173.6, 26.2), 0.9], ["shrub_a", Vector2(169.4, 31.9), 1.0]]:
		items.append(item(S, "tree", String(q[0]), q[1], rng.randf() * TAU, float(q[2]), "under", {"preset": "mature"}))
	# ── 入口：下駄箱（向拝北側、裳階下）、草履（踏石上に脱ぎ揃え 2、地面に 1 足脱ぎ散らかし）、手桶
	# 下駄箱：放在踏石上、玄關門側（門 z≈22.6–25.4 與向拝左柱 z 26.15 之間）靠牆（Hero Body x≤193.61）；
	#         原位在告示 NoticeR 後方＋簷下陰影，MCP 實機 TPS 從前庭完全看不到
	var gk := item(S, "mesh", "sk_getabako", Vector2(193.98, 25.98), PI * 0.5, 1.0, "entry", {"on_step": true})
	gk["y"] = surface_y(v, Vector2(193.98, 25.98)) + 0.01
	items.append(gk)
	for q: Array in [[Vector2(194.35, 25.15), PI * 0.5 + 0.05], [Vector2(194.4, 22.95), PI * 0.5 - 0.12]]:
		var it := item(S, "mesh", "sk_zori", q[0], float(q[1]), 1.0, "entry_zori", {"on_step": true})
		it["y"] = surface_y(v, q[0])
		items.append(it)
	items.append(item(S, "mesh", "sk_zori", Vector2(195.45, 25.7), 2.3, 1.0, "entry_zori"))
	items.append(item(S, "mesh", "sk_teoke", Vector2(195.75, 25.95), 0.3, 1.0, "entry"))
	# ── 告示：西巷側の木札「手習所」、南側の掃除当番板
	items.append(item(S, "mesh", "sk_fuda", Vector2(205.6, 21.2), PI * 0.5 - 0.3, 1.2, "sign"))
	items.append(item(S, "mesh", "sk_toban", Vector2(199.4, 35.9), PI * 0.5 + 0.35, 1.0, "sign"))
	# ── 日陰：縁台＋木箱（榎の下）
	items.append(item(S, "mesh", "sk_bench", Vector2(202.4, 11.6), 0.25, 1.0, "rest"))
	items.append(item(S, "mesh", "sk_box", Vector2(204.1, 10.5), 0.4, 1.0, "rest"))
	# ── 生活痕跡：習字の干し竿（南側）、手毬、竹の輪、石蹴り
	items.append(item(S, "mesh", "sk_hanshi", Vector2(188.0, 35.6), 0.0, 1.0, "trace"))
	items.append(item(S, "mesh", "sk_temari", Vector2(198.7, 33.2), 0.6, 1.0, "trace"))
	items.append(item(S, "mesh", "sk_hoop", Vector2(196.5, 35.65), 0.35, 1.0, "trace"))
	var hop := item(S, "mesh", "sk_ishikeri", Vector2(201.8, 31.2), 0.14, 1.0, "trace_ground")
	hop["y"] = S.h(201.8, 31.2) + 0.006
	items.append(hop)
	# ── 背面：天水桶（北西角、雨落ち）、薪棚（背面裳階下）、古い手桶
	items.append(item(S, "mesh", "sk_tensui", Vector2(182.05, 14.95), 0.2, 1.0, "back"))
	items.append(item(S, "mesh", "sk_woodpile", Vector2(182.2, 21.0), PI * 0.5, 1.0, "back"))
	items.append(item(S, "mesh", "sk_teoke", Vector2(181.95, 27.6), 2.1, 0.95, "back"))
	# ── 雨落ち縁石（側面・背面；正面は向拝・花壇があるので無し）
	var runs: Array = [[Vector2(182.1, 13.92), Vector2(193.6, 13.92)], [Vector2(182.1, 34.08), Vector2(193.6, 34.08)],
		[Vector2(181.42, 14.5), Vector2(181.42, 33.5)]]
	for run: Array in runs:
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var n := int(floor(a.distance_to(b) / 0.92))
		var d := (b - a).normalized()
		for k in n:
			var p := a + d * (0.46 + k * 0.92)
			var skip := false
			for it: Dictionary in items:
				if String(it["id"]) in ["sk_tensui", "sk_woodpile", "sk_teoke"] and (it["p"] as Vector2).distance_to(p) < 0.95:
					skip = true
			if skip:
				continue
			items.append(item(S, "mesh", "gk_amaochi", p, atan2(-d.y, d.x), 1.0, "amaochi"))
	return {"items": items, "S": S, "M": M, "bld": bld, "ms": Time.get_ticks_msec() - t0}


# ─────────────────────────── 地面 overlay（sg_ground：COLOR＝砂利, 苔, 土, 落葉；UV2＝濕潤, 淡出） ───────────────────────────

const G_STEP := 0.4


static func _n(p: Vector2, a: float) -> float:
	return 0.5 + 0.5 * sin(p.x * 0.83 * a + p.y * 0.37) * sin(p.y * 0.71 * a - p.x * 0.29) * 0.7 + 0.15 * sin(p.x * 2.3 * a - p.y * 1.9)


static func ground_w(P: Dictionary, p: Vector2) -> Variant:
	var gv := 0.0
	var mo := 0.0
	var so := 0.0
	var li := 0.0
	var wet := 0.08
	# 淡出：敷地＋前面の空地まで
	var dpar := Vector2(maxf(maxf(PARCEL.position.x - 6.0 - p.x, p.x - 205.0), 0.0),
		maxf(maxf(PARCEL.position.y - 3.0 - p.y, p.y - 47.0), 0.0)).length()
	var de := GL.line_d(ENTRY, p).x
	var f := maxf(clampf((3.5 - dpar) / 3.5, 0.0, 1.0), clampf((ENTRY_HW + 3.0 - de) / 2.0, 0.0, 1.0))
	if f <= 0.0:
		return null
	var nz := _n(p, 1.0)
	var gr := 0.0   # 雜草（＝shader 預設草層）：只在牆腳・後方・地塊邊緣；其他沒有權重的地方不出 overlay（露出 P7 地面）
	# 玄關前の土間口（踏石〜前庭）：踏み固め
	var apron := Vector2((p.x - 196.4) / 3.6, (p.y - 24.0) / 9.4).length() + 0.25 * (nz - 0.5)
	if apron < 1.25:
		var ak := 1.0 - smoothstep(0.6, 1.25, apron)
		gv = maxf(gv, 0.8 * ak)
		so = maxf(so, 0.4 * ak)
	# 前庭外緣留一圈雜草（讓踏み固め的前庭有對比、不是整片裸地）
	if apron > 1.15 and apron < 1.9 and p.x > 194.0 and de > ENTRY_HW + 0.6:
		gr = maxf(gr, 0.55 * (1.0 - absf(apron - 1.5) / 0.4) * (0.6 + 0.6 * nz))
	# 入口の道：踏み固め土（幅は雜訊で揺れる）
	var dw := ENTRY_HW + 0.7 * (nz - 0.5) + 0.35 * sin(p.x * 1.3 - p.y * 0.8)
	if de < dw:
		gv = maxf(gv, 0.65 * (1.0 - smoothstep(dw * 0.4, dw, de)) + 0.2)
		so = maxf(so, 0.45)
	elif de < dw + 1.4:
		so = maxf(so, 0.6 * (1.0 - (de - dw) / 1.4))
	# 前庭の活動場：裸土（草の島が少し残る）
	var yd := GL.poly_d(PackedVector2Array(YARD), p) * (1.0 if Geometry2D.is_point_in_polygon(p, PackedVector2Array(YARD)) else -1.0)
	yd += 0.9 * (nz - 0.5) + 0.4 * sin(p.x * 1.7 + p.y * 1.3)
	if yd > -1.2:
		var yk := clampf((yd + 1.2) / 1.6, 0.0, 1.0)
		so = maxf(so, yk * (0.55 if _n(p * 1.9, 1.3) > 0.22 else 0.4))
		gv = maxf(gv, yk * (0.45 + 0.25 * _n(p * 0.7, 2.1)))
	# 縁台の足元・石蹴りの場
	for c: Array in [[Vector2(202.6, 11.2), 2.2], [Vector2(201.8, 31.2), 2.0], [Vector2(196.4, 35.4), 1.4]]:
		var dd := p.distance_to(c[0])
		if dd < float(c[1]):
			so = maxf(so, 0.85 * (1.0 - smoothstep(float(c[1]) * 0.5, float(c[1]), dd)))
	# 南側を回る踏み跡（前庭 → 干し竿 → 裏）
	var dsp := GL.line_d([Vector2(197.2, 33.2), Vector2(195.6, 35.0), Vector2(192.6, 37.4), Vector2(186.0, 37.6), Vector2(180.0, 35.6), Vector2(178.4, 30.0)], p).x
	if dsp < 0.75 + 0.3 * (nz - 0.5):
		so = maxf(so, 0.6)
	# 前庭 → 榎の縁台 の踏み跡
	var dbn := GL.line_d([Vector2(198.6, 17.6), Vector2(200.6, 13.2), Vector2(202.0, 10.4)], p).x
	if dbn < 0.7 + 0.3 * (nz - 0.5):
		so = maxf(so, 0.7)
	# 雜草：後方（x < 181.6）・牆腳帶・地塊南北緣（雜訊で斑）
	var dbody := _rect_d(BODY, p)
	var warp := 1.6 * (nz - 0.5) + 0.7 * sin(p.x * 0.9 - p.y * 0.6)
	gr = (0.3 + 0.35 * nz) * smoothstep(0.0, 2.5, 181.0 - p.x + warp)
	if dbody > 0.0 and dbody < 0.9 and p.x < 193.0:
		gr = maxf(gr, 0.7 * (1.0 - dbody / 0.9))
	var edge := maxf(smoothstep(0.0, 2.5, 11.8 - p.y + warp), smoothstep(0.0, 2.5, p.y - 36.2 + warp)) * smoothstep(0.0, 2.0, 197.5 - p.x + warp)
	gr = maxf(gr, (0.18 + 0.35 * nz) * edge)
	# 樹の下：落葉
	for it: Dictionary in P["items"]:
		if String(it["kind"]) != "tree" or String(it["id"]) in UNDER_IDS:
			continue
		var cr := float((P["M"] as Dictionary)[it["id"]]["crown_w"]) * 0.42 * (it["sc"] as Vector3).x
		var dt := p.distance_to(it["p"])
		if dt < cr:
			li = maxf(li, 0.55 * (1.0 - dt / cr) + 0.15)
	# 雨落ち：屋根外緣の下 ±0.3 m＝砂利（濕）、壁際＝土＋苔（北側は苔多め）
	var dr := _rect_d(ROOF, p)
	var inside_roof := ROOF.has_point(p)
	if not BODY.grow(0.05).has_point(p) and p.x < 194.0:
		if absf(dr) < 0.32 and (p.x < 193.8):
			gv = 0.0
			so = 0.8
			mo = 0.15
			li = 0.0
			wet = 0.4
		elif inside_roof:
			so = maxf(so, 0.45)
			mo = maxf(mo, 0.65 if p.y < 20.0 else 0.35)
			wet = 0.22
	# 北側の日陰：苔
	if p.y < 15.0 and p.y > 10.0 and p.x > 181.0 and p.x < 194.0:
		mo = maxf(mo, 0.5 * (1.0 - (15.0 - p.y) / 5.0) + 0.1)
	var tot := gv + mo + so + li
	f *= clampf(maxf(tot, gr) * 1.5, 0.0, 1.0)
	if f <= 0.02:
		return null
	# 殘餘權重：shader 的「剩下＝純草」比 P7 地面綠得多 → 只有 gr（牆腳・後方・緣）留草，其餘補土（避免草皮色塊）
	if tot < 1.0:
		so += (1.0 - tot) * (1.0 - clampf(gr * 1.2, 0.0, 1.0)) * 0.9
		tot = gv + mo + so + li
	if tot > 1.0:
		gv /= tot
		mo /= tot
		so /= tot
		li /= tot
	return [Color(gv, mo, so, li), Vector2(wet, f)]


static func _rect_d(r: Rect2, p: Vector2) -> float:
	## 符號距離（外＋）
	var dx := maxf(r.position.x - p.x, p.x - r.end.x)
	var dz := maxf(r.position.y - p.y, p.y - r.end.y)
	if dx <= 0.0 and dz <= 0.0:
		return maxf(dx, dz)
	return Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length()


static func ground_mesh(P: Dictionary) -> ArrayMesh:
	var S: RLib.TriSampler = P["S"]
	var bld: Array = P["bld"]
	var nx := int(ceil(REGION.size.x / G_STEP))
	var nz := int(ceil(REGION.size.y / G_STEP))
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var Cc := PackedColorArray()
	var U2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var vid := {}
	for j in nz + 1:
		for i in nx + 1:
			var p := REGION.position + Vector2(i * G_STEP, j * G_STEP)
			var h := S.h(p.x, p.y)
			if is_nan(h):
				continue
			var w: Variant = ground_w(P, p)
			if w == null:
				continue
			var d := 0.4
			var nrm := Vector3(S.h(p.x - d, p.y) - S.h(p.x + d, p.y), 2.0 * d, S.h(p.x, p.y - d) - S.h(p.x, p.y + d))
			vid[Vector2i(i, j)] = V.size()
			V.append(Vector3(p.x, h + 0.011, p.y))
			N.append(nrm.normalized() if nrm.is_finite() else Vector3.UP)
			Cc.append((w as Array)[0])
			U2.append((w as Array)[1])
	for j in nz:
		for i in nx:
			var k00: Variant = vid.get(Vector2i(i, j))
			var k10: Variant = vid.get(Vector2i(i + 1, j))
			var k01: Variant = vid.get(Vector2i(i, j + 1))
			var k11: Variant = vid.get(Vector2i(i + 1, j + 1))
			if k00 == null or k10 == null or k01 == null or k11 == null:
				continue
			var c := REGION.position + Vector2((i + 0.5) * G_STEP, (j + 0.5) * G_STEP)
			if BODY.grow(-0.2).has_point(c) or STEP.grow(-0.1).has_point(c):
				continue
			var skip := false
			for r: Rect2 in bld:
				if r.size.x > 0.8 and r.size.y > 0.8 and r.grow(-0.3).has_point(c):
					skip = true
					break
			if skip:
				continue
			idx.append_array([k00, k10, k11, k00, k11, k01])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_COLOR] = Cc
	arr[Mesh.ARRAY_TEX_UV2] = U2
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var m := SG.sg_material()
	m.shader = load("res://assets/village_v2/school_kit/sy_ground.gdshader")
	m.resource_name = "SY_Ground"
	# R 通道＝P7 street 道土（school_kit/sy_ground.gdshader；R4-2 封存的 sg_ground.gdshader 不動）
	m.set_shader_parameter("gravel_tile", 2.6)
	m.set_shader_parameter("gravel_contrast", 0.85)
	m.set_shader_parameter("gravel_sat", 0.95)
	m.set_shader_parameter("gravel_tint", Vector3(1.24, 1.15, 1.0))
	am.surface_set_material(0, m)
	am.resource_name = "sy_ground"
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
	var trees := Node3D.new()
	trees.name = "Trees"
	root.add_child(trees)
	var under := Node3D.new()
	under.name = "Under"
	root.add_child(under)
	var props := Node3D.new()
	props.name = "Props"
	root.add_child(props)
	var col := StaticBody3D.new()
	col.name = "Collision"
	root.add_child(col)
	var n := 0
	var ns := 0
	var meshes := {}
	for it: Dictionary in P["items"]:
		var id := String(it["id"])
		var xf := SG.xf_of(it)
		if String(it["kind"]) == "tree":
			var t := SG.tree_expanded(id, String(it.get("preset", "mature")))
			t.name = "%03d_%s" % [n, id]
			t.transform = xf
			t.set_meta("yard_tag", String(it["tag"]))
			(under if id in UNDER_IDS else trees).add_child(t)
			n += 1
			continue
		var node := Node3D.new()
		node.name = "%03d_%s" % [n, id]
		node.transform = xf
		node.set_meta("yard_id", id)
		node.set_meta("yard_tag", String(it["tag"]))
		node.set_meta("on_step", bool(it.get("on_step", false)))
		props.add_child(node)
		var dir := GK if id.begins_with("gk_") else SK
		for lod in 2:
			var key := id + ("_l1" if lod == 1 else "")
			if not meshes.has(key):
				meshes[key] = load(dir + key + ".res")
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % lod
			mi.mesh = meshes[key]
			mi.visibility_range_begin = 0.0 if lod == 0 else LOD_SWITCH
			mi.visibility_range_end = LOD_SWITCH if lod == 0 else 220.0
			if lod == 1 or id in ["sk_zori", "sk_temari", "sk_ishikeri", "gk_amaochi"]:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
		if PROP_BOX.has(id):
			var b: Array = PROP_BOX[id]
			var bx := BoxShape3D.new()
			bx.size = Vector3(float(b[0]) * 2.0, float(b[2]), float(b[1]) * 2.0) * (it["sc"] as Vector3).x
			var cs := CollisionShape3D.new()
			cs.name = "%s_c" % node.name
			cs.shape = bx
			cs.transform = Transform3D(Basis(Vector3.UP, float(it["yaw"])), xf.origin + Vector3(0, float(b[2]) * 0.5, 0))
			cs.set_meta("yard_id", id)
			col.add_child(cs)
			ns += 1
		for pp: Vector2 in POSTS.get(id, []):
			var cy := CylinderShape3D.new()
			cy.radius = 0.04
			cy.height = 1.62
			var cs := CollisionShape3D.new()
			cs.name = "%s_post%d" % [node.name, ns]
			cs.shape = cy
			cs.transform = Transform3D(Basis.IDENTITY, xf * Vector3(pp.x, 0.81, pp.y))
			cs.set_meta("yard_id", id)
			col.add_child(cs)
			ns += 1
		n += 1
	root.set_meta("items", (P["items"] as Array).size())
	root.set_meta("shapes", ns)
	root.set_meta("art_revision", "P9 R4-3 寺子屋周邊 r1（ART_REVIEW）")
	return root


static func own(n: Node, owner: Node) -> void:
	SG.own(n, owner)
