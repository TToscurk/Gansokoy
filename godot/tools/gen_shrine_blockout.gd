extends SceneTree
## 博麗神社 P0 blockout —— 地形 + 空間骨架 + 建築佔位量體。
##
##   Godot --headless --path godot --script tools/gen_shrine_blockout.gd
##
## 產出 maps/shrine/shrine.tscn。
##
## ══ 這一支只做 P0（規格 §20）══
##   Terrain / Main Torii / Approach / Courtyard / Haiden
## 建築一律是**灰色量體**，不是美術資產。目的是把規格 §2/§3/§4/§13 的
## 尺寸錨點立成可量測的實體，讓使用者出 Meshy 圖時有確定數字：
## 拜殿要多大、石階幾階、鳥居多高、境內留多空。
##
## 規格 §20 明訂「不得在 P0/P1 未完成前大量製作 P3」——所以這裡沒有
## 小物、沒有陰陽玉、沒有磨損細節。
##
## ══ 座標約定 ══
## 地圖 150 × 110 m（mapRegistry playSize）。南 = +z（來自獸道），北 = -z。
## 主軸沿 x=0，玩家從南端傳送進來，往北穿過鳥居 → 參道 → 石階 → 境內 → 拜殿。

const Lib := preload("res://tools/gen_lib.gd")
const OUT := "res://maps/shrine/"

const HALF_X := 75.0
const HALF_Z := 55.0
const SEED := 20260905

# ── §2 Scale Anchors ──
const TORII_H := 6.8              # 規格 6.0–7.5
const TORII_OPEN := 5.2           # 規格 4.5–6.0
const APPROACH_W := 3.0           # 規格 2.5–3.5

# ── §23 Stairs ──
const STEP_RISE := 0.16           # 規格 0.14–0.18
const STEP_TREAD := 0.38          # 規格 0.32–0.45
const STEP_W := 3.2               # 規格 2.8–3.8
const LANDING_D := 1.8            # 規格 1.2–2.5

# ── §3 Courtyard ──
const COURT_W := 27.0             # 規格 22–32
const COURT_D := 22.0             # 規格 18–28

# ── §4 Buildings ──
const HAIDEN_W := 10.5            # 規格 9–12
const HAIDEN_D := 7.0             # 規格 6–8
const HAIDEN_H := 7.0             # 規格 6–8（屋高）
const HONDEN_W := 6.5             # 規格 5–8
const HONDEN_D := 5.0             # 規格 4–6
const HONDEN_H := 5.0

# ── 主軸關鍵 z（由北往南排，見 _init 的試算）──
const Z_ENTRY := 53.0             # 南端傳送點
const Z_TORII := 44.0
const Z_HONDEN := -38.0
const Z_HAIDEN := -28.0
const Z_COURT_N := -31.5          # 境內北緣＝拜殿正面
const Z_COURT_S := -9.5           # 境內南緣＝石階頂
const COURT_Y := 3.2              # 境內平台高度（石階總爬升）

var lib: Lib
var _nh: FastNoiseLite
var _nd: FastNoiseLite
var _stair_plan: Array = []       # [{y0, y1, z0, z1, steps, is_landing}]


# ══════════════════════════════════════════════════════════════════
# 地形高度：南低北高，境內是削平的平台
# ══════════════════════════════════════════════════════════════════

## 石階分段計畫。總爬升 COURT_Y，依 §23 拆成 5–12 階一段 + landing。
func _plan_stairs() -> void:
	var n_total := int(round(COURT_Y / STEP_RISE))
	var segs := 1 if n_total <= 12 else (2 if n_total <= 24 else 3)
	var per := n_total / segs
	var extra := n_total % segs
	# 由下往上鋪：石階起點在境內南緣往南推
	var run := float(n_total) * STEP_TREAD + float(segs - 1) * LANDING_D
	var z := Z_COURT_S + run          # 最低階的南端
	var y := 0.0
	_stair_plan.clear()
	for s in segs:
		var cnt := per + (1 if s < extra else 0)
		for i in cnt:
			_stair_plan.append({
				"z0": z - STEP_TREAD, "z1": z,
				"y0": y, "y1": y + STEP_RISE, "landing": false,
			})
			z -= STEP_TREAD
			y += STEP_RISE
		if s < segs - 1:
			_stair_plan.append({
				"z0": z - LANDING_D, "z1": z, "y0": y, "y1": y, "landing": true,
			})
			z -= LANDING_D
	print("[SHRINE] 石階：總爬升 %.2f m ÷ %.2f = %d 階，分 %d 段（每段 %d 階）+ %d 個 landing"
		% [COURT_Y, STEP_RISE, n_total, segs, per, segs - 1])
	print("[SHRINE]   水平長 %.1f m，佔 z %+.1f ~ %+.1f" % [run, Z_COURT_S, Z_COURT_S + run])


## 石階在某 z 的高度；不在石階範圍回 -INF
func _stair_y(z: float) -> float:
	for e in _stair_plan:
		if z >= e.z0 and z <= e.z1:
			if e.landing:
				return e.y0
			# 階梯內線性（實際幾何是方塊，這裡給地形一個平滑近似）
			var t: float = (e.z1 - z) / maxf(e.z1 - e.z0, 0.0001)
			return lerpf(e.y0, e.y1, t)
	return -INF


func height_at(x: float, z: float) -> float:
	# ── 1. 主軸縱向基準：南端 0 → 境內平台 COURT_Y ──
	# 石階負責 z ∈ [Z_COURT_S, Z_COURT_S+run] 的爬升，其餘是緩坡。
	var stair_south: float = _stair_plan[0].z1 if not _stair_plan.is_empty() else Z_COURT_S
	var base := 0.0
	if z <= Z_COURT_S:
		base = COURT_Y                       # 境內平台以北，全平
	elif z <= stair_south:
		var sy := _stair_y(z)
		base = sy if sy != -INF else COURT_Y  # 石階帶
	else:
		# 石階底以南：緩坡由入口的 −1.2 m 升到石階最低階（0），
		# 讓玩家有「一路走上來」的感覺，而不是一馬平川。
		# ⚠ 不能用 _stair_plan[0].y0（= 0）當終點，那樣整段就是平的。
		var t := clampf((Z_ENTRY - z) / maxf(Z_ENTRY - stair_south, 0.001), 0.0, 1.0)
		base = lerpf(-1.2, 0.0, smoothstep(0.0, 1.0, t))

	# ── 2. 境內平台：完全平（§3 要開闊負空間）──
	var court_pad := 4.0
	var in_court := absf(x) < COURT_W * 0.5 + court_pad \
		and z > Z_COURT_N - 10.0 and z < Z_COURT_S
	if in_court:
		return COURT_Y

	# ── 3. 石階走廊：階梯本身由實體方塊提供，地形給一個貼合的斜面 ──
	# ⚠ 石階帶與境內判定**不能重疊**。前一版兩者範圍交叉互相覆蓋，
	#   實測 z=−5 的高度 1.60 比 z=0 的 2.65 還低 1.05 m —— 主軸中間凹了一個坑。
	if z > Z_COURT_S and z <= stair_south and absf(x) < STEP_W * 0.5 + 3.0:
		var sy2 := _stair_y(z)
		if sy2 != -INF:
			var edge := smoothstep(STEP_W * 0.5, STEP_W * 0.5 + 3.0, absf(x))
			return lerpf(sy2, sy2 + 0.6, edge)

	# ── 4. 一般地形 ──
	var h := base
	h += _nh.get_noise_2d(x, z) * 1.1
	h += _nh.get_noise_2d(x * 0.35 + 60.0, z * 0.35) * 1.8

	# 山勢：把神社包在谷地裡（§0「偏僻」）。
	# ⚠ 抬升必須夠緩，否則在 0.94 m 格距的網格上會變成梯田階梯。
	#   歷次實測：×16 m 的 smoothstep(30,70) → 87° 斷崖、10.7% 格點超標；
	#   改成三個 smoothstep² 相加後反而 20.7%（角落三項疊加）。
	#   正解是**單一徑向距離場**：算「離神社核心多遠」一次，只抬一次。
	var core := Vector2(0.0, (Z_COURT_N + Z_ENTRY) * 0.5)
	var d := Vector2(x * 0.62, z - core.y).length()   # x 方向壓縮 → 谷地呈南北長橢圓
	var rise := smoothstep(42.0, 76.0, d)
	h += rise * rise * 15.0

	# ── 5. 參道走廊：**只壓平，不挖溝** ──
	# ⚠ 前一版把路面設成 road_h − 0.06 但兩側保留全部噪聲與山勢，
	#   實測邊坡落差 0.7–2.2 m —— 走起來像戰壕，違反 §0「開闊」。
	#   改成整條走廊連同兩側一起收斂到基準面，只留 6 cm 踩踏下陷。
	if z > Z_COURT_S and z < Z_ENTRY + 4.0:
		var corr := 1.0 - smoothstep(APPROACH_W * 0.5, APPROACH_W * 0.5 + 7.0, absf(x))
		var flat := base + _nh.get_noise_2d(x * 0.2, z * 0.2) * 0.35
		h = lerpf(h, flat - 0.06 * corr, corr)

	# ── 6. 境內外圍緩降，避免平台像浮空方塊 ──
	var d_court := maxf(absf(x) - (COURT_W * 0.5 + court_pad),
		maxf((Z_COURT_N - 10.0) - z, z - Z_COURT_S))
	if d_court > 0.0 and d_court < 14.0:
		h = lerpf(COURT_Y, h, smoothstep(0.0, 14.0, d_court))
	return h


## 地表混合遮罩：R=參道/踩踏、G=林床、B=巨觀、A=石鋪
func mask_at(x: float, z: float) -> Color:
	var t := clampf((Z_ENTRY - z) / (Z_ENTRY - Z_COURT_S), 0.0, 1.0)
	# §29 踩踏圖：主軸 = 高流量
	var axis := 1.0 - smoothstep(APPROACH_W * 0.5, APPROACH_W * 0.5 + 2.2, absf(x))
	var on_path := axis * (1.0 if (z > Z_COURT_N and z < Z_TORII + 8.0) else 0.0)
	# 境內：中央乾淨、邊緣半維護（§6）
	var in_court := absf(x) < COURT_W * 0.5 and z > Z_COURT_N and z < Z_COURT_S
	var court_core := 0.0
	if in_court:
		var dx := absf(x) / (COURT_W * 0.5)
		var dz := absf((z - (Z_COURT_N + Z_COURT_S) * 0.5)) / (COURT_D * 0.5)
		court_core = 1.0 - smoothstep(0.45, 0.95, maxf(dx, dz))
	var packed := clampf(maxf(on_path, court_core), 0.0, 1.0)
	# 林床：離主軸與境內越遠越濃（§17 密度梯度）
	var d_axis := absf(x)
	var forest := clampf(smoothstep(8.0, 34.0, d_axis) * 0.9, 0.0, 1.0)
	forest = maxf(forest, smoothstep(Z_COURT_N, Z_COURT_N - 16.0, z) * 0.8)
	forest *= 1.0 - packed
	var macro := clampf(_nh.get_noise_2d(x * 0.4, z * 0.4) * 0.5 + 0.5, 0.0, 1.0)
	# §21 鋪石：參道 45–70%、近拜殿 60–80%、境內 5–20%
	var stone := 0.0
	if z > Z_COURT_S and z < Z_TORII:
		stone = axis * 0.6
	elif in_court:
		var to_haiden := 1.0 - smoothstep(0.0, 10.0, absf(z - Z_COURT_N))
		stone = axis * (0.15 + to_haiden * 0.55)
	return Color(packed, forest, macro, stone)


# ══════════════════════════════════════════════════════════════════
func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "gen"))
	_nh = FastNoiseLite.new(); _nh.frequency = 0.014; _nh.fractal_octaves = 3; _nh.seed = 855
	_nd = FastNoiseLite.new(); _nd.frequency = 0.03; _nd.seed = 175

	var root := Node3D.new()
	root.name = "Shrine"
	root.set_meta("own_colliders", true)
	lib = Lib.new()
	lib.setup(root, SEED)
	_plan_stairs()

	lib.terrain(OUT, maxf(HALF_X, HALF_Z), 161, height_at, mask_at, "terrain_path",
		Color(0.62, 0.66, 0.48), "terrain_forest", Color(0.36, 0.30, 0.24), 0.0)
	lib.boundary(HALF_Z - 2.0)

	_build_stairs()
	_build_torii()
	_build_massing()
	_build_sky()
	_build_markers()

	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, OUT + "shrine.tscn")
	print("[SHRINE] saved shrine.tscn err=%d  節點 %d" % [err, _count(root)])
	quit(0)


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


# ══════════════════════════════════════════════════════════════════
# 石階：實體方塊，一階一個節點（可個別選取，與獸道同慣例）
# ══════════════════════════════════════════════════════════════════
func _build_stairs() -> void:
	var g := lib.add(lib.root, Node3D.new(), "參道石階") as Node3D
	var body := StaticBody3D.new()
	lib.add(g, body, "石階碰撞")
	var mat := lib.pbr("shrine_step", "stone_wall", 0.4, Color(0.74, 0.73, 0.69))
	var n := 0
	for e in _stair_plan:
		var depth: float = e.z1 - e.z0
		var top: float = e.y1
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		# 每一階是實心到地面的塊：高度 = 台面高 + 0.4 埋深，避免懸空
		var blk_h: float = top + 0.5
		bm.size = Vector3(STEP_W, blk_h, depth)
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(0.0, top - blk_h * 0.5, (e.z0 + e.z1) * 0.5)
		lib.add(g, mi, "%s_%02d" % ["平台" if e.landing else "階", n])
		var sh := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bm.size
		sh.shape = bs
		sh.position = mi.position
		body.add_child(sh); sh.owner = lib.root
		n += 1
	print("[SHRINE] 石階實體 %d 塊（含 landing）" % n)


# ══════════════════════════════════════════════════════════════════
# 主鳥居：用委製資產 landmark/大鳥居.glb，依 §2 縮到 6.0–7.5 m
# ══════════════════════════════════════════════════════════════════
func _build_torii() -> void:
	var path := "res://assets/landmark/大鳥居.glb"
	if not ResourceLoader.exists(path):
		push_error("找不到 %s" % path)
		return
	var ps := load(path) as PackedScene
	var inst := ps.instantiate() as Node3D
	var box := _aabb_of(ps)
	# ⚠ 委製資產不改比例，只調 scale（憲法第 1、3 條 + bank_railing.gd 判準）。
	#   slice 用 scale=20 → 高 14.6 m，遠超 §2 的 6.0–7.5 m 上限。
	#
	# ⚠ 這個鳥居**等比縮放無法同時滿足 §2 的高與寬**（probe_torii_fit.gd 實測）：
	#     資產寬高比 1.376，柱間淨距只佔整體寬 42.4%
	#     高=6.80 m → 淨開口 3.97 m（規格要 4.5–6.0）✗
	#     淨開口=5.20 m → 高 8.91 m（規格要 6.0–7.5）✗
	#     臨界：淨開口 4.5 m 時 scale=10.62、高 7.72 m（僅超上限 0.22 m）
	#   blockout 先照高度取，把落差記進 meta 等使用者裁決——
	#   非等比拉寬會破壞委製資產比例，那是憲法第 1 條禁止的。
	var s := TORII_H / maxf(box.size.y, 0.01)
	var y := height_at(0.0, Z_TORII)
	inst.scale = Vector3(s, s, s)
	# Meshy 原點多半在幾何中心，抬到底貼地
	inst.position = Vector3(0.0, y - box.position.y * s, Z_TORII)
	lib.add(lib.root, inst, "主鳥居")
	inst.set_meta("spec_conflict",
		"§2 要求高 6.0-7.5 m 且淨開口 4.5-6.0 m，本資產寬高比 1.376 無法兼顧。"
		+ "現取高 %.2f m（淨開口 %.2f m，短少 %.2f m）。"
		% [box.size.y * s, box.size.x * 0.424 * s, 4.5 - box.size.x * 0.424 * s]
		+ "選項：(a) 放寬高度到 7.72 m 換取淨開口 4.5 m；(b) 走 Meshy 重出符合比例的鳥居；"
		+ "(c) 接受目前的窄開口。待使用者裁決。")
	var open_w := box.size.x * s
	var clear_w := box.size.x * 0.424 * s
	print("[SHRINE] 主鳥居：scale %.3f → 高 %.2f m、整體寬 %.2f m、淨開口 %.2f m"
		% [s, box.size.y * s, open_w, clear_w])
	print("[SHRINE]   ⚠ §2 要淨開口 4.5-6.0 m，短少 %.2f m —— 已記入節點 meta 待裁決"
		% (4.5 - clear_w))
	# 兩根柱子的碰撞
	var body := StaticBody3D.new()
	lib.add(lib.root, body, "鳥居碰撞")
	for side in [-1.0, 1.0]:
		var sh := CollisionShape3D.new()
		var c := CylinderShape3D.new()
		c.radius = 0.26; c.height = TORII_H
		sh.shape = c
		sh.position = Vector3(side * open_w * 0.42, y + TORII_H * 0.5, Z_TORII)
		body.add_child(sh); sh.owner = lib.root


func _aabb_of(ps: PackedScene) -> AABB:
	var inst := ps.instantiate() as Node3D
	var box: Variant = null
	for m in _mesh_nodes(inst):
		var b: AABB = _rel(m, inst) * (m as MeshInstance3D).get_aabb()
		box = b if box == null else (box as AABB).merge(b)
	inst.free()
	return box if box != null else AABB(Vector3.ZERO, Vector3.ONE)


func _mesh_nodes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		o.append(n)
	for c in n.get_children():
		o.append_array(_mesh_nodes(c))
	return o


func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


# ══════════════════════════════════════════════════════════════════
# 建築佔位量體（§20 P0/P1）：灰盒子 + Marker3D 帶 meshy 規格
# ══════════════════════════════════════════════════════════════════
func _build_massing() -> void:
	var g := lib.add(lib.root, Node3D.new(), "建築佔位") as Node3D
	var body := StaticBody3D.new()
	lib.add(g, body, "建築碰撞")
	var mat := lib.pbr("blockout_grey", "plaster", 0.5, Color(0.62, 0.60, 0.57))
	# [名稱, 寬, 深, 高, x, z, meshy 規格]
	var specs := [
		["拜殿", HAIDEN_W, HAIDEN_D, HAIDEN_H, 0.0, Z_HAIDEN,
			"Haiden 拜殿：寬 9-12 m、深 6-8 m、可見屋高 6-8 m。風化木 45-60%、"
			+ "灰泥牆 15-25%、屋頂 20-30%（暗灰炭色、低飽和、消光）、紅色 ≤10%。"
			+ "是境內主體但不得像寺院大殿。正面入口 2-4 階、階寬為立面 60-85%。"],
		["本殿", HONDEN_W, HONDEN_D, HONDEN_H, 0.0, Z_HONDEN,
			"Honden 本殿：寬 5-8 m、深 4-6 m。比拜殿更小更封閉，不得搶走拜殿正面視覺重心。"],
		["社務所", 8.0, 5.5, 4.2, -13.5, -22.0,
			"社務所／靈夢住居：境內側區，有生活感。緣側、木板牆、掛物晾曬處。"],
		["倉庫", 3.6, 3.0, 3.0, -14.5, -13.0,
			"small storage 小倉庫：木造、風化、簡樸。"],
		["手水舍", 2.6, 2.6, 2.8, 11.0, -14.5,
			"Temizuya 手水舍：四柱小亭 + 水盤。石與木，長苔，不華麗。"],
	]
	for s in specs:
		var w: float = s[1]
		var d: float = s[2]
		var h: float = s[3]
		var x: float = s[4]
		var z: float = s[5]
		var y := height_at(x, z)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, h, d)
		mi.mesh = bm
		mi.material_override = mat
		mi.position = Vector3(x, y + h * 0.5, z)
		lib.add(g, mi, "量體_%s" % s[0])
		var mk := Marker3D.new()
		mk.position = Vector3(x, y, z)
		mk.set_meta("meshy", s[6])
		mk.set_meta("footprint", "%.1f x %.1f x %.1f m" % [w, d, h])
		lib.add(g, mk, "%s_Meshy佔位" % s[0])
		var sh := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bm.size
		sh.shape = bs
		sh.position = mi.position
		body.add_child(sh); sh.owner = lib.root
		print("[SHRINE] 量體 %-6s %5.1f x %4.1f x %4.1f m @ (%.1f, %.1f)" % [s[0], w, d, h, x, z])


# ══════════════════════════════════════════════════════════════════
# 天象：§16 白天、中低對比、柔和陰影
# ══════════════════════════════════════════════════════════════════
func _build_sky() -> void:
	var sky := Node3D.new()
	sky.set_script(load("res://scripts/sky_system.gd"))
	lib.add(lib.root, sky, "天象系統")
	sky.set("時刻", 10.5)              # §16 late morning
	sky.set("一日長度分鐘", 20.0)
	sky.set("方位角", -26.0)
	sky.set("星星密度", 0.35)
	sky.set("陰影距離", 120.0)
	sky.set("體積霧", true)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.78, 0.76)
	env.fog_density = 0.0025          # §14 遠景略不自然的霧，強度 1-2/10
	env.fog_sky_affect = 0.15
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.62   # §16 中低對比、柔和陰影
	env.ssao_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.02
	env.adjustment_saturation = 1.02
	we.environment = env
	lib.add(lib.root, we, "神社環境")


func _build_markers() -> void:
	var g := lib.add(lib.root, Node3D.new(), "標記") as Node3D
	var y := height_at(0.0, Z_ENTRY)
	var sm := Marker3D.new()
	sm.position = Vector3(0.0, y + 1.0, Z_ENTRY)
	sm.rotation.y = PI          # 面北，望向鳥居
	lib.add(g, sm, "出生點_南")
	var pm := Marker3D.new()
	pm.position = Vector3(0.0, y + 1.0, Z_ENTRY)
	pm.set_meta("portal", "trail")
	lib.add(g, pm, "傳送點_南_獸道")
	print("[SHRINE] 出生／傳送點 (0.0, %.2f, %.1f) → trail" % [y, Z_ENTRY])
	_write_meta(y)


## 直接寫出 data/shrine.meta.json 的 portals。
##
## ⚠ 傳送點座標同時存在產生器與 meta.json，人工同步一定會脫節：
##   地形一改，入口地面從 +1.69 掉到 −1.35，playtest 立刻報「離地 +4.04 m」。
##   由產生器輸出，兩邊永遠一致。
##   arrival_* 的意義見 main.gd:_arrival_for_portal（玩家落在傳送點往圖心
##   退 4 m 處，該處地面可能與傳送點不同高）。
func _write_meta(entry_y: float) -> void:
	var path := "res://data/shrine.meta.json"
	var meta := {}
	if FileAccess.file_exists(path):
		var txt := FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(txt)
		if parsed is Dictionary:
			meta = parsed
	# 到達點：往圖心（原點）退 4 m
	var arrival_z := Z_ENTRY - 4.0
	meta["id"] = "shrine"
	meta["playSize"] = [150, 110]
	meta["safe"] = true
	meta["connections"] = ["trail"]
	meta["portals"] = [{
		"x": 0.0, "y": snappedf(entry_y, 0.01), "z": Z_ENTRY, "target": "trail",
		"arrival_ground_y": snappedf(height_at(0.0, arrival_z), 0.01),
		"arrival_y_offset": 1.2,
	}]
	meta["colliders"] = []       # 場景 own_colliders=true
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("寫不了 %s" % path)
		return
	f.store_string(JSON.stringify(meta, "  "))
	f.close()
	print("[SHRINE] 寫出 data/shrine.meta.json：傳送點 y=%.2f、到達地面 y=%.2f"
		% [entry_y, height_at(0.0, arrival_z)])
