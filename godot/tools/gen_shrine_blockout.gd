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
const TORII_H := 6.8              # 規格 6.0–7.5（舊灰量體時期的目標值，保留供參考）
const TORII_OPEN := 5.2           # 規格 4.5–6.0
const APPROACH_W := 3.0           # 規格 2.5–3.5
# 博麗鳥居.glb 實測：單位化 1.00 × 0.747 × 0.193，柱間淨空佔總寬 48.1%
const TORII_SCALE := 9.6          # → 高 7.17 m、淨開口 4.61 m
const TORII_CLEAR_RATIO := 0.481

# ── 委製資產 scale（probe_shrine_kit / probe_shrine_fit 實測，原點皆 BASE）──
# 單位化尺寸 → scale 反推自 §4 footprint：
const HAIDEN_SCALE := 9.0         # 1.00×0.68×0.85 → 9.00 寬 / 7.65 深 / 6.12 高
const SHAMUSHO_SCALE := 7.0       # 0.98×0.46×0.83 → 6.86 / 5.81 / 3.22
const TEMIZUYA_SCALE := 3.2       # 1.00×0.83×0.91 → 3.20 / 2.91 / 2.66
const ORB_D := 0.26               # §26 LEVEL 3 直徑 0.18–0.35

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
	# §13 西北展望走廊：谷壁在這個扇形裡不抬，讓視線能出去看妖怪之山。
	# 走廊邊緣 8° 內平滑過渡，不然會切出一道垂直牆。
	var rel := Vector2(x, z) - Vector2(0.0, (Z_COURT_N + Z_COURT_S) * 0.5)
	if rel.length() > 4.0:
		var ang := rad_to_deg(acos(clampf(rel.normalized().dot(VISTA_DIR), -1.0, 1.0)))
		rise *= smoothstep(VISTA_HALF_ANGLE_DEG, VISTA_HALF_ANGLE_DEG + 8.0, ang)
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
	_build_vista()

	_build_stairs()
	_build_torii()
	_build_massing()
	_build_paving()
	_build_vegetation()
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
# 遠景（§13 secondary sightline「courtyard → mountain / sky / boundary」、
# §14 邊界異常 1–2/10、docs/border-vistas.md 神社條目）
#
# 地理（border-vistas.md）：神社在幻想鄉**最東端高地**。
#   西  = 俯瞰整個盆地，遠處妖怪之山（全遊戲最好的展望）
#   東  = 結界之外，白霧吞掉一切（什麼都不給看，設定正確且省工）
#   北  = 白玉樓／天界方向的淡色遠山 + 雲
#   南  = 太陽花田方向的黃色帶
#
# 三層（border-vistas.md 實作備忘）：遠景地形（lib.vista 高斯山包）→
# 遠景樹帶（MultiMesh，無陰影）→ 地標山 GLB。
#
# ⚠ `landmark/遠景山.glb` 使用者明令**不用於博麗神社**（保留給其他圖）。
#   本圖用 `vista/妖怪之山.glb`（帶雪主峰，全域方位錨點）與
#   `vista/遠景山2.glb`（矮丘），兩件都是 Meshy、原點偏移不一致，見實測：
#     妖怪之山  1.78×0.79×1.80  min.y +0.135  ← 底邊懸在原點之上
#     遠景山2   1.88×0.64×1.01  min.y −0.088  ctr.z −0.44 ← 幾何偏一側
#   一律用 `y − box.position.y × s` 落到 vista 高度，不能直接放 y。
#
# ⚠ §14 東側「白霧」不是另做一面牆，是**不放任何地標 + 霧密度**。
#   fog_density 已在 _build_sky；東側 vista 地形壓平，讓霧把它吃掉。
# ══════════════════════════════════════════════════════════════════

const VISTA_EXT := 900.0         # 遠景網格半徑（地圖半徑 75 → 12 倍）


func _build_vista() -> void:
	# 遠景地形：西側**下沉**成盆地（神社在高地俯瞰）、西北抬成妖怪之山山腳、
	# 北側遠山帶、東側平（霧）、南側緩丘。
	# ⚠ lib.vista 的 landmark.h 可以是負的 → 高斯凹陷。第一版全用正值 +
	#   50-90 m 的小山包，實拍 900 m 的遠景網格是一片平綠，山包看不出來。
	#   幅度要跟網格半徑同一個量級。
	var half := maxf(HALF_X, HALF_Z)
	var lms: Array = []
	for lm in VISTA_LANDMARKS:
		lms.append({ "x": lm[0], "z": lm[1], "h": lm[2], "r": lm[3] })
	lib.vista(OUT, half, VISTA_EXT, height_at, lms,
		"res://assets/models/tree_round_far.glb", 700)

	# 遠景地形的草色要接得上本圖 terrain（0.62,0.66,0.48 偏乾黃），
	# lib.vista 寫死 (0.50,0.72,0.46) 是村圖的青草，接縫處一條色差線。
	var vista_mi := lib.root.find_child("Vista", false, false) as MeshInstance3D
	if vista_mi != null and vista_mi.material_override is StandardMaterial3D:
		(vista_mi.material_override as StandardMaterial3D).albedo_color = Color(0.56, 0.62, 0.42)

	var g := lib.add(lib.root, Node3D.new(), "遠景地標") as Node3D
	# [檔名, 目標高 m, x, z, yaw]
	# 妖怪之山：西北，全域最高、要壓過所有東西。
	# 遠景山2 ×2：北面兩座矮丘互相錯開，形成「淡色遠山帶」。
	var specs := [
		["妖怪之山", 380.0, -640.0, -580.0, 0.55],
		["遠景山2", 150.0, 120.0, -860.0, 0.0],
		["遠景山2", 120.0, -330.0, -880.0, 2.4],
	]
	var i := 0
	for s in specs:
		var path := "res://assets/vista/%s.glb" % s[0]
		var ps := load(path) as PackedScene
		if ps == null:
			push_error("遠景資產載入失敗 %s" % path)
			continue
		var box := _aabb_of(ps)
		var sc: float = s[1] / maxf(box.size.y, 0.01)
		var inst := ps.instantiate() as Node3D
		var x: float = s[2]
		var z: float = s[3]
		# 落在 vista 地形上。lib.vista 沒回傳 height_fn，這裡重算同一組高斯：
		# base = 邊緣 height_at + Σ landmark 高斯（噪聲項省略，±34 m 對 380 m 的山無感）
		var vy := _vista_y(x, z, half)
		# ⚠ 埋深要吃掉 lib.vista 的邊緣抬升（t²×46，900 m 處 ≈ +46 m），
		#   否則矮丘的山底會浮在 y=60 高處（_audit_vista_seat 實測 4.0°）。
		#   用「網格高 − 目標山底高」直接算，不用固定比例。
		#   目標山底 = 讓從境內看的仰角 ≈ 1°。
		var eye_y := COURT_Y + 1.7
		var dist_eye := Vector2(x, z - (Z_COURT_N + Z_COURT_S) * 0.5).length()
		var want_base := eye_y + dist_eye * tan(deg_to_rad(1.0))
		inst.position = Vector3(x, want_base - box.position.y * sc, z)
		inst.rotation.y = s[4]
		inst.scale = Vector3(sc, sc, sc)
		for mn in _mesh_nodes(inst):
			(mn as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lib.add(g, inst, "%s_%d" % [s[0], i])
		i += 1
	print("[SHRINE] 遠景：vista 半徑 %.0f m、地標山 %d 座（東側無地標 = §14 結界白霧）"
		% [VISTA_EXT, specs.size()])
	_audit_vista_seat(specs, half)


## 遠景山「浮在天上」自檢：從境內眼高看每座山的**山底仰角**。
## 真實遠山的山腳應該落在地平線附近（≤ 3°）；再高就會讀成飄浮物。
## 前一版山腳高斯 150 m 把妖怪之山頂到 10.3°，實拍是一座浮空島。
func _audit_vista_seat(specs: Array, half: float) -> void:
	var eye := Vector3(0.0, COURT_Y + 1.7, (Z_COURT_N + Z_COURT_S) * 0.5)
	var bad := 0
	for s in specs:
		var x: float = s[2]
		var z: float = s[3]
		var h: float = s[1]
		var dist_e := Vector2(x, z - (Z_COURT_N + Z_COURT_S) * 0.5).length()
		var base_y := COURT_Y + 1.7 + dist_e * tan(deg_to_rad(1.0))
		var dist := Vector2(x - eye.x, z - eye.z).length()
		var deg := rad_to_deg(atan2(base_y - eye.y, dist))
		var ok := deg <= 3.0
		if not ok:
			bad += 1
		print("[SHRINE]   %-8s 距 %.0f m、山底 y %.0f → 仰角 %.1f° %s"
			% [s[0], dist, base_y, deg, "✓" if ok else "✗ 浮空"])
	if bad > 0:
		push_error("%d 座遠景山的山底仰角 > 3°，會讀成飄在天上" % bad)


## 遠景地形高斯山包 [x, z, h, r]。負 h = 凹陷。
## 同時餵給 lib.vista（建網格）與 _vista_y（放地標山），只此一份。
##
## ⚠ 幅度**必須遠小於地標山本身的高度**。前一版山腳給 150 m，加上
##   lib.vista 的邊緣抬升 t²×46 與噪聲，妖怪之山底邊被頂到 y=158、
##   而境內眼高只有 4.9 → 山底仰角 10.3°，整座山飄在半空
##   （audit_vista_seat.gd 實測，13_vista_nw.png 實拍）。
##   地形只負責「不是一片平板」，海拔感由山的 GLB 自己撐。
##   山腳一律 ≤ 25 m，且山要坐在**離境內夠遠**的位置讓仰角落到 ~2°。
const VISTA_LANDMARKS := [
	[-520.0, 60.0, -38.0, 420.0],     # 西 盆地（神社高地俯瞰）
	[-600.0, -540.0, 22.0, 340.0],    # 西北 妖怪之山山腳台地
	[80.0, -760.0, 14.0, 380.0],      # 北 遠山帶
	[-340.0, -800.0, 11.0, 280.0],    # 北偏西 第二層
	[500.0, -600.0, 10.0, 300.0],     # 東北 收邊（霧會吃掉）
	[40.0, 640.0, 12.0, 340.0],       # 南 太陽花田方向的緩丘
	[560.0, 500.0, 8.0, 280.0],       # 東南
]

func _vista_y(x: float, z: float, half: float) -> float:
	var d := maxf(absf(x), absf(z)) - half
	var t := clampf(d / (VISTA_EXT - half - 20.0), 0.0, 1.0)
	var y := height_at(clampf(x, -half, half), clampf(z, -half, half)) + t * t * 46.0
	for lm in VISTA_LANDMARKS:
		var dx := x - float(lm[0])
		var dz := z - float(lm[1])
		y += float(lm[2]) * exp(-(dx * dx + dz * dz) / (float(lm[3]) * float(lm[3])))
	return y


## 邊界遮蔽林：緊貼遊玩區外緣一圈的密林，把地圖的長方形硬邊藏進林線。
## 西北 34° 走廊那一段**刻意留空**，讓妖怪之山看得到。
##
## ⚠ 不走 lib.vista 的 groves：那條路徑用 lib.tree_mesh()，會把 surface 0
##   換成頂點色 canopy_mat —— 那是給 Blender 低模樹用的，Meshy GLB 沒有
##   頂點色，實拍是一圈灰白光禿桿子（vista2/15_overview_high.png）。
##   這裡照 Zone C 同一套：個別 MeshInstance3D 共用 GLB 原生 mesh + 材質。
##   個別節點在 75 m 外沒有互動需求，但跟 Zone C 同構、材質保證正確。
func _build_boundary_forest(parent: Node3D, half: float) -> void:
	var g := lib.add(parent, Node3D.new(), "邊界遮蔽林") as Node3D
	var pool := ["針葉樹1", "針葉樹2glb", "針葉林樹3", "針葉林樹4", "普通樹"]
	var made := 0
	var tries := 0
	# 兩圈：內圈 half+8..+30 密、外圈 +30..+60 疏，高度往外遞增形成林冠線
	while made < 1100 and tries < 40000:
		tries += 1
		var ang := lib.rand() * TAU
		var dir := Vector2(cos(ang), sin(ang))
		if dir.dot(VISTA_DIR) > cos(deg_to_rad(VISTA_HALF_ANGLE_DEG + 10.0)):
			continue
		var dist := half + lib.rr(6.0, 62.0)
		# 內圈密：距離越遠越容易被丟掉
		var keep := 1.0 - smoothstep(half + 26.0, half + 62.0, dist) * 0.7
		if lib.rand() > keep:
			continue
		var p := dir * dist
		var ok := true
		for e in _tree_log:
			if p.distance_to(e[0]) < 3.2:
				ok = false
				break
		if not ok:
			continue
		var name: String = pool[int(lib.rand() * pool.size()) % pool.size()]
		var tall := lib.rr(11.0, 17.0) + (dist - half) * 0.08
		# 站在 vista 網格上（噪聲項 lib.vista 內部才有，這裡少算 ±3 m，
		# 用 −0.05 微沉 + 樹根本來就被林床蓋住，可接受）
		_tree(g, LS + name + ".glb", p, tall, false, _vista_y(p.x, p.y, half))
		made += 1
	print("[SHRINE] 邊界遮蔽林 %d 棵（西北走廊留空）" % made)


## 西北展望走廊的疏林（使用者 2026-09-05 指定「這個方位再增加一點點樹」）。
##
## ⚠ 走廊當初為了看妖怪之山挖得太乾淨，0–60 m 一棵樹都沒有
##   （audit_vista_corridor.gd 實測），變成一條突兀的空帶。
##   這裡補回**疏林**，但受兩個硬約束：
##     1. 樹冠仰角 < 9°（妖怪之山佔 1.0°–24.9°，留出山體）
##     2. 不進中軸視線錐（_axis_clear）與建築 keepout
##   從境內 (0,−20.5) 算，仰角 = atan(樹高 / 距離)：
##     距 40 m → 樹高上限 ~6 m
##     距 55 m → ~8.5 m
##     距 70 m → ~11 m
##   所以走廊裡是「越遠越高」的漸進疏林，近處只放小樹。
##   數量刻意少（§0「開闊」）：34 棵，不是補成密林。
func _build_corridor_trees(parent: Node3D) -> void:
	var g := lib.add(parent, Node3D.new(), "走廊疏林") as Node3D
	var origin := Vector2(0.0, (Z_COURT_N + Z_COURT_S) * 0.5)
	var eye_y := COURT_Y + 1.7
	var pool := ["針葉樹1", "針葉樹2glb", "針葉林樹3", "針葉林樹4", "普通樹"]
	var made := 0
	var tries := 0
	while made < 34 and tries < 4000:
		tries += 1
		# 只在走廊內、28–72 m 這一段（更近會擋前景、更遠已經有邊界林）
		var ang := lib.rr(-VISTA_HALF_ANGLE_DEG + 2.0, VISTA_HALF_ANGLE_DEG - 2.0)
		var dir := VISTA_DIR.rotated(deg_to_rad(ang))
		var dist := lib.rr(28.0, 72.0)
		var p := origin + dir * dist
		if absf(p.x) > HALF_X - 6.0 or absf(p.y) > HALF_Z - 6.0:
			continue
		if _blocked(p, 3.0) or _axis_clear(p, 1.5) or _in_dais(p, 1.2):
			continue
		var ok := true
		for e in _tree_log:
			if p.distance_to(e[0]) < 5.0:
				ok = false
				break
		if not ok:
			continue
		# 仰角上限 9° 反推樹高，再留 15% 餘裕
		var max_h := (dist * tan(deg_to_rad(9.0)) + eye_y - height_at(p.x, p.y)) * 0.85
		if max_h < 4.5:
			continue
		var tall := lib.rr(4.5, minf(max_h, 11.0))
		var name: String = pool[int(lib.rand() * pool.size()) % pool.size()]
		_tree(g, LS + name + ".glb", p, tall, true)
		made += 1
	print("[SHRINE] 走廊疏林 %d 棵（仰角上限 9°，不遮妖怪之山）" % made)


## §13「至少保留一個明顯遠景出口」：從境內中央往四方看，
## 檢查哪些方向的地平線被本圖森林（Zone C 樹冠）擋死。
## 只能量「樹冠仰角」代理值：扇形內最高樹冠頂的仰角 < 12° 算有出口。
## 由 _build_vegetation 尾端呼叫（要等 _tree_log 填好）。
func _audit_vista_openings() -> void:
	var eye := Vector3(0.0, COURT_Y + 1.7, (Z_COURT_N + Z_COURT_S) * 0.5)
	var dirs := [["西北(走廊)", VISTA_DIR], ["北", Vector2(0, -1)], ["東", Vector2(1, 0)], ["南", Vector2(0, 1)]]
	var open_count := 0
	for d in dirs:
		var dir: Vector2 = d[1]
		var worst_deg := 0.0
		# 沿方向掃 20°扇形，找最擋的樹
		for e in _tree_log:
			var c: Vector2 = e[0]
			var rel := c - Vector2(eye.x, eye.z)
			var dist := rel.length()
			if dist < 6.0 or dist > 80.0:
				continue
			# 掃描扇形略窄於走廊（15° vs 17°），走廊邊緣的樹不算擋
			if rel.normalized().dot(dir) < cos(deg_to_rad(15.0)):
				continue
			# 樹冠頂高 ≈ 地面 + 2×冠半徑（冠幅≈高）
			var top_y := height_at(c.x, c.y) + float(e[1]) * 2.0
			var deg := rad_to_deg(atan2(top_y - eye.y, dist))
			worst_deg = maxf(worst_deg, deg)
		var is_open := worst_deg < 12.0
		if is_open:
			open_count += 1
		print("[SHRINE] 遠景出口 %s：最高樹冠仰角 %.1f°  %s" % [d[0], worst_deg, "開" if is_open else "封"])
	if open_count == 0:
		push_error("§13 境內沒有任何遠景出口，四面都被樹冠封死")
	else:
		print("[SHRINE] §13 遠景出口 %d/4 方向 ✓" % open_count)


# ══════════════════════════════════════════════════════════════════
# 參道石階：委製件組裝（踏石／平台石／袖石垣／收頭石）
#
# ⚠ 這四件的原點是 CENTRE（probe_shrine_kit 實測 min.y 為負），跟前五件
#   建築的 BASE 不同 —— 落地公式必須用 `y − box.position.y × scale`，
#   直接把 position.y 設成地面高會沉進土裡一半。
#
# ⚠ 每件都是「單位長 1.90 m」的模組，非等比縮到 §23 的級高／級深：
#     踏石   1.90 × 0.21 × 0.31  → 1.60 寬 × 0.16 高 × 0.38 深
#     平台石 1.90 × 0.27 × 1.61  → 1.60 寬 × 0.16 高 × 1.80 深
#     袖石垣 1.90 × 0.73 × 0.42  → 0.45 寬 × 0.55 高 × 0.38 深
#     收頭石 1.90 × 0.31 × 0.54  → 1.60 寬 × 0.20 高 × 0.55 深
#   踏石／平台石／收頭石都是**兩塊並排**湊 3.2 m 可行走寬，接縫刻意偏離
#   中軸 ±0.03，不讓縫落在玩家正前方。
#
# ⚠ 碰撞仍用 BoxShape3D 實心塊（一階一個），不用 GLB 的凹凸網格：
#   踏面凹凸只是視覺，走起來要平；凹面碰撞也會讓角色卡住。
# ══════════════════════════════════════════════════════════════════

# ⚠ 一律用 _lod：石階構件每件 30k tris，主石階 88 塊全走高模 = 250 萬面。
#   gltfpack -si 0.05（**不加 -sa**，加了 UV 會崩成金屬渦紋，轉台圖驗過）
#   → 4-8k tris。石階構件是簡單塊體，不像樹有葉片，輪廓與貼圖幾乎無差。
const STEP_KIT := {
	"踏石": ["res://assets/_lod/踏石.glb", Vector3(1.60, 0.16, 0.38)],
	"平台石": ["res://assets/_lod/平台石.glb", Vector3(1.60, 0.16, 1.80)],
	"袖石垣": ["res://assets/_lod/袖石垣.glb", Vector3(0.45, 0.55, 0.38)],
	"收頭石": ["res://assets/_lod/收頭石.glb", Vector3(1.60, 0.20, 0.55)],
}


func _build_stairs() -> void:
	var g := lib.add(lib.root, Node3D.new(), "參道石階") as Node3D
	var body := StaticBody3D.new()
	lib.add(g, body, "石階碰撞")
	var tread := lib.add(g, Node3D.new(), "踏石") as Node3D
	var sode := lib.add(g, Node3D.new(), "袖石垣") as Node3D
	var n := 0
	var stones := 0
	for e in _stair_plan:
		var depth: float = e.z1 - e.z0
		var top: float = e.y1
		var cz: float = (e.z0 + e.z1) * 0.5
		var kit: String = "平台石" if e.landing else "踏石"
		# 兩塊並排：接縫偏離中軸，避免正中一條直縫
		var seam := 0.06 if n % 2 == 0 else -0.06
		for side in [-1.0, 1.0]:
			var half_w := STEP_W * 0.5
			var cx: float = side * (half_w * 0.5) + seam
			var sz := Vector3(half_w, STEP_KIT[kit][1].y, depth)
			_step_stone(tread, STEP_KIT[kit][0], Vector3(cx, top, cz), sz,
				"%s_%02d_%s" % [kit, n, "L" if side < 0.0 else "R"])
			stones += 1
		# 側邊袖石垣：每階兩側各疊一段，高度隨階梯上升
		for side in [-1.0, 1.0]:
			var kw: float = STEP_KIT["袖石垣"][1].x
			var kx: float = side * (STEP_W * 0.5 + kw * 0.5)
			var kh: float = STEP_KIT["袖石垣"][1].y
			# 擋土牆頂緣比踏面高一階多，形成側向收邊
			_step_stone(sode, STEP_KIT["袖石垣"][0],
				Vector3(kx, top + kh * 0.45, cz), Vector3(kw, kh, depth),
				"袖石_%02d_%s" % [n, "L" if side < 0.0 else "R"])
			stones += 1
		# 碰撞：實心塊到地面（凹凸網格會卡角色）
		var blk_h: float = top + 0.5
		var sh := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(STEP_W, blk_h, depth)
		sh.shape = bs
		sh.position = Vector3(0.0, top - blk_h * 0.5, cz)
		body.add_child(sh); sh.owner = lib.root
		n += 1
	# 收頭石：最下階南端、最上階北端各一組（兩塊並排）
	var z_bot: float = _stair_plan[0].z1
	var z_top: float = _stair_plan[_stair_plan.size() - 1].z0
	var cap := lib.add(g, Node3D.new(), "收頭石") as Node3D
	for spec in [[z_bot + 0.30, 0.0, "南"], [z_top - 0.30, COURT_Y, "北"]]:
		var cz2: float = spec[0]
		var cy: float = spec[1]
		for side in [-1.0, 1.0]:
			var half_w2 := STEP_W * 0.5
			_step_stone(cap, STEP_KIT["收頭石"][0],
				Vector3(side * half_w2 * 0.5, cy + 0.02, cz2),
				Vector3(half_w2, STEP_KIT["收頭石"][1].y, STEP_KIT["收頭石"][1].z),
				"收頭_%s_%s" % [spec[2], "L" if side < 0.0 else "R"])
			stones += 1
	print("[SHRINE] 石階：%d 階（含 landing）、石件 %d 塊（踏石／平台石／袖石垣／收頭石）"
		% [n, stones])


## 放一塊石階構件：非等比縮到 size，頂面對齊 top_y。CENTRE 原點。
func _step_stone(parent: Node3D, path: String, pos: Vector3, size: Vector3,
		name: String) -> void:
	var ps := load(path) as PackedScene
	if ps == null:
		push_error("石階資產載入失敗 %s" % path)
		return
	var box := _aabb_of(ps)
	var s := Vector3(size.x / maxf(box.size.x, 0.01), size.y / maxf(box.size.y, 0.01),
		size.z / maxf(box.size.z, 0.01))
	var inst := ps.instantiate() as Node3D
	inst.scale = s
	# ⚠ CENTRE 原點：頂面 = pos.y → 節點 y = 頂面 − 高 − AABB 下緣偏移
	inst.position = Vector3(pos.x, pos.y - size.y - box.position.y * s.y, pos.z)
	# §24 老化不得均勻：微幅隨機偏擺
	inst.rotation.y = lib.rr(-0.02, 0.02)
	lib.add(parent, inst, name)


# ══════════════════════════════════════════════════════════════════
# 主鳥居：委製資產 assets/shrine/博麗鳥居.glb，依 §2 縮到 6.0–7.5 m
# ══════════════════════════════════════════════════════════════════
func _build_torii() -> void:
	var path := "res://assets/shrine/博麗鳥居.glb"
	if not ResourceLoader.exists(path):
		push_error("找不到 %s" % path)
		return
	var ps := load(path) as PackedScene
	var inst := ps.instantiate() as Node3D
	var box := _aabb_of(ps)
	# ⚠ 委製資產不改比例，只調 scale（憲法第 1、3 條 + bank_railing.gd 判準）。
	#
	# 舊的 landmark/大鳥居.glb 柱間淨距只佔整體寬 42.4%，等比縮放無法同時滿足
	# §2 的高 6.0–7.5 與淨開口 4.5–6.0。新的博麗鳥居.glb 好一點但仍有夾擠
	# （probe_shrine_fit.gd 實測淨開口佔總寬 48.1%）：
	#     高 6.0 m → 淨開口 3.86 m ✗   高 7.5 m → 淨開口 4.82 m ✓
	#   兩邊都滿足的區間只有 scale 9.38–10.04，落在 §2 高度的上緣。
	#   取 TORII_SCALE 9.6 → 高 7.17 m、淨開口 4.61 m，兩項都在規格內。
	var s := TORII_SCALE
	var y := height_at(0.0, Z_TORII)
	inst.scale = Vector3(s, s, s)
	# 原點在 BASE（probe_shrine_kit 實測 min.y = 0.000），直接落地。
	inst.position = Vector3(0.0, y - box.position.y * s, Z_TORII)
	lib.add(lib.root, inst, "主鳥居")
	var open_w := box.size.x * s
	var clear_w := TORII_CLEAR_RATIO * open_w
	inst.set_meta("spec_fit",
		"§2 高 6.0-7.5 / 淨開口 4.5-6.0。本資產淨開口佔總寬 %.1f%%，"
		% (TORII_CLEAR_RATIO * 100.0)
		+ "可用 scale 區間 9.38-10.04。現取 %.2f → 高 %.2f m、淨開口 %.2f m。"
		% [s, box.size.y * s, clear_w])
	print("[SHRINE] 主鳥居：scale %.2f → 高 %.2f m、整體寬 %.2f m、淨開口 %.2f m（§2 皆達標）"
		% [s, box.size.y * s, open_w, clear_w])
	# 兩根柱子的碰撞：柱心在淨開口外緣 + 柱半徑
	var body := StaticBody3D.new()
	lib.add(lib.root, body, "鳥居碰撞")
	var col_r := 0.30
	for side in [-1.0, 1.0]:
		var sh := CollisionShape3D.new()
		var c := CylinderShape3D.new()
		c.radius = col_r; c.height = box.size.y * s
		sh.shape = c
		sh.position = Vector3(side * (clear_w * 0.5 + col_r),
			y + box.size.y * s * 0.5, Z_TORII)
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
# 建築：委製資產進場（拜殿／本殿／社務所／手水舍）
#
# ⚠ 建築四件的原點都在 BASE（min.y = 0.000，probe_shrine_kit.gd），不是
#   Meshy 常見的幾何中心 —— position.y 直接給地面高即可，不必補偏移。
#   （石階四件則是 CENTRE，見 _step_stone。同一批交付裡兩種原點都有。）
#   單位化（最長邊 = 1.0），所以尺寸完全由 scale 決定，見檔頭常數的反推。
#
# ⚠ 朝向：render_shrine_turntable.gd 四向渲圖確認正面都朝 +z。
#   本圖南 = +z = 玩家來向，所以一律不旋轉。
#   （幾何重心法分不出來 —— probe_shrine_facing.gd 實測底/頂薄片偏移都 < 2 cm。）
#
# ⚠ 碰撞取**網格世界 AABB**，不取節點原點（村圖 road_lamp 曾因此錯 1.42 m）。
#
# 倉庫：使用者 2026-09-05 決定不做，佔位與 keepout 一併移除。
# ══════════════════════════════════════════════════════════════════
func _build_massing() -> void:
	var g := lib.add(lib.root, Node3D.new(), "建築") as Node3D
	var body := StaticBody3D.new()
	lib.add(g, body, "建築碰撞")

	# ── 委製資產 ──
	# [名稱, glb, scale, x, z, 碰撞內縮比例]
	# 本殿 0.67×1.00×0.76 單位化 → scale 6.5：寬 4.36 / 深 4.94 / 高 6.50。
	# §4 要寬 5–8、深 4–6；等比縮放下寬與高不能兼顧（資產是高瘦型），
	# 取深度達標、寬 4.36 略低於 5.0 —— 但 §4 也要求「比拜殿更小更封閉、
	# 不得搶走拜殿正面視覺重心」，窄一點反而正確，記進 meta。
	# ⚠ 站在白石庭院上的建築要抬 DAIS_H，否則陷進鋪面 0.72 m。
	#   第一版只手動抬了拜殿，庭院從 13 m 擴到 34 m 之後社務所與手水舍
	#   也進了鋪面範圍，卻還留在地面高度 —— 使用者用 MCP 抓到三件陷入。
	#   改成 _place() 內部用 _in_dais() 自動判定，不再手動傳偏移。
	var built := [
		["拜殿", "res://assets/shrine/拜殿.glb", HAIDEN_SCALE, 0.0, Z_HAIDEN, 0.94],
		["本殿", "res://assets/shrine/本殿.glb", 6.5, 0.0, Z_HONDEN, 0.94],
		["社務所", "res://assets/shrine/社務所.glb", SHAMUSHO_SCALE, -13.5, -22.0, 0.94],
		["手水舍", "res://assets/shrine/手水舍.glb", TEMIZUYA_SCALE, 11.0, -14.5, 0.55],
	]
	for b in built:
		_place(g, body, b[0], b[1], b[2], b[3], b[4], b[5])

	_build_orb(g)


## 放一件委製資產：BASE 原點落地、量 AABB 出碰撞。
func _place(parent: Node3D, body: StaticBody3D, name: String, path: String,
		s: float, x: float, z: float, col_shrink: float) -> void:
	if not ResourceLoader.exists(path):
		push_error("找不到 %s" % path)
		return
	var ps := load(path) as PackedScene
	var inst := ps.instantiate() as Node3D
	var box := _aabb_of(ps)
	# 站在白石庭院上 → 地面是鋪面頂，不是地形
	var on_dais := _in_dais(Vector2(x, z))
	var y := height_at(x, z) + (DAIS_H if on_dais else 0.0)
	inst.scale = Vector3(s, s, s)
	inst.position = Vector3(x, y - box.position.y * s, z)
	lib.add(parent, inst, name)
	var w := box.size.x * s
	var h := box.size.y * s
	var d := box.size.z * s
	inst.set_meta("scale_source",
		"單位化 %.3f x %.3f x %.3f × scale %.2f = %.2f 寬 / %.2f 深 / %.2f 高 m"
		% [box.size.x, box.size.y, box.size.z, s, w, d, h])
	# 碰撞：AABB 中心（世界）而不是節點原點
	var ctr := Vector3(x + (box.position.x + box.size.x * 0.5) * s,
		y + box.size.y * s * 0.5,
		z + (box.position.z + box.size.z * 0.5) * s)
	var sh := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	# 手水舍是四柱敞亭，用整塊 AABB 會擋住走不進去 —— 縮到柱圈。
	bs.size = Vector3(w * col_shrink, h, d * col_shrink)
	sh.shape = bs
	sh.position = ctr
	body.add_child(sh); sh.owner = lib.root
	print("[SHRINE] 資產 %-4s scale %.2f → %.2f 寬 x %.2f 深 x %.2f 高 m @ (%.1f, %.1f) 底 y=%.2f%s"
		% [name, s, w, d, h, x, z, y, "  ← 站在白石庭院上" if on_dais else ""])


## §25-27 陰陽玉：EASTER EGG，可見度 LOW，數量 0-1。
## §26 LEVEL 3 明訂位置要像「靈夢真的把東西放在那裡」——社務所側面／緣側下／
## 木箱旁／倉庫角落，且**禁止放在參道中央當裝飾品**。
## 倉庫取消後改放**社務所東南角外側 1.5 m**（緣側轉角的地面），
## 仍在側區、不在主軸視線（§13 Torii→Courtyard→Haiden）上。
func _build_orb(parent: Node3D) -> void:
	var path := "res://assets/shrine/陰陽玉.glb"
	if not ResourceLoader.exists(path):
		push_error("找不到 %s" % path)
		return
	var ps := load(path) as PackedScene
	var inst := ps.instantiate() as Node3D
	var box := _aabb_of(ps)
	var s := ORB_D / maxf(box.size.y, 0.01)
	# 社務所在 (-13.5, -22.0)、實測 6.87 寬 × 5.81 深 → 東南角約 (-10.1, -19.1)
	var x := -9.6
	var z := -18.6
	# 陰陽玉在社務所東南角，庭院擴大後也落在鋪面上
	var y := height_at(x, z) + (DAIS_H if _in_dais(Vector2(x, z)) else 0.0)
	inst.scale = Vector3(s, s, s)
	inst.position = Vector3(x, y - box.position.y * s, z)
	inst.rotation.y = 0.6
	lib.add(parent, inst, "陰陽玉")
	inst.set_meta("easter_egg",
		"§25-27 LEVEL 3 實體陰陽玉，全圖僅此 1 顆。直徑 %.2f m（規格 0.18-0.35）。"
		% (box.size.y * s)
		+ "位置：社務所東南角外側地面，不在主軸視線上。")
	print("[SHRINE] 陰陽玉 直徑 %.2f m @ (%.1f, %.1f)（§26 LEVEL 3，全圖唯一）"
		% [box.size.y * s, x, z])


# ══════════════════════════════════════════════════════════════════
# §21 Ground Stone / Paving + §22 Stone Aging + §29 Ground Storytelling
#
# 程序化個別石板，不用 nature/RockPath_*：那些是固定排列的多石叢
# （probe_paving_assets.gd：1–2 m 一組、青綠 H=83），重複擺就是 §21 禁的
# 「明顯 procedural tiling」。§21 是純數值規則（尺寸、變異、縫隙），
# 與石階、bank_railing.gd 同判準——規則線性構件，程序化自建不涉美術判斷。
#
# 每塊石板 = 一個 MeshInstance3D（可個別選取，與獸道/石階同慣例），
# 共用少數幾個 BoxMesh 變體 + 兩種材質（乾／濕苔）。
#
# 覆蓋率不是「擺滿再抽掉」，而是沿參道中軸鋪一條**帶狀不規則路面**：
# 石板順著路向排列、留縫，帶寬隨 §21 的覆蓋率目標收放。
# ══════════════════════════════════════════════════════════════════

# §21 石板尺寸（2026-09-05 使用者補充規格：approach paving）
const SLAB_W := [0.35, 0.70]         # 寬（垂直路向）
const SLAB_L := [0.45, 0.90]         # 長（沿路向）
const SLAB_T := [0.08, 0.16]         # 厚
const SLAB_GAP := [0.03, 0.12]       # 縫
const SLAB_ROT_DEG := [3.0, 8.0]     # ±旋轉
const SLAB_DY := [0.01, 0.025]       # ±高度變異
const PAVE_HW := 1.4                 # 鋪石帶半寬 → 路寬 2.8（規格 2.4–3.2）
const PAVE_COVER := [45.0, 60.0]     # 視覺覆蓋率 %
const EDGE_MOSS := [10.0, 25.0]      # 邊緣帶苔石比例 %
const EDGE_GRASS := [10.0, 20.0]     # 邊緣帶草侵入 %

var _slab_kits: Array = []            # [PackedScene, AABB] — Quaternius Pebble_* 11 顆
var _slab_log: Array = []             # [Vector2 中心, 半寬, 半長] — 覆蓋率自檢用
var _slab_mat_dry: StandardMaterial3D
var _slab_mat_moss: StandardMaterial3D
var _slab_mat_wet: StandardMaterial3D

## 石板池：nature/Pebble_Square_1..6 + Pebble_Round_1..5。
## probe_paving_assets.gd 實測：0.26–0.50 m、厚 9–17 cm、BASE 原點、48–136 tris。
## 有斜切邊與不規則輪廓，非等比拉到 §21 的 0.35–0.70 × 0.45–0.90 後就是
## 「不規則石板」。RockPath_* 不用（是固定排列的多石叢 = procedural tiling）。
const SLAB_KIT := ["Pebble_Square_1", "Pebble_Square_2", "Pebble_Square_3",
	"Pebble_Square_4", "Pebble_Square_5", "Pebble_Square_6",
	"Pebble_Round_1", "Pebble_Round_2", "Pebble_Round_3", "Pebble_Round_4", "Pebble_Round_5"]


func _build_paving() -> void:
	var g := lib.add(lib.root, Node3D.new(), "鋪石") as Node3D
	# ⚠ 前三版都是 BoxMesh + 貼圖：實拍一律是瓷磚／方塊，使用者判不及格。
	#   石板的「石感」來自輪廓與斜切邊，貼圖救不了方盒子。改用 Pebble 網格。
	#
	# ⚠ Pebble 的 PathRocks_Diffuse 是 H=83 的青綠（Quaternius 卡通調），
	#   直接用就是綠石頭。用 material_override 蓋掉：stone_wall 花崗岩貼圖 +
	#   world triplanar（每塊依世界座標取樣，不會 11 顆同花紋）+ 中灰 tint。
	_slab_mat_dry = lib.pbr("shrine_slab", "stone_wall", 0.33, Color(0.60, 0.59, 0.56), true, 0.4)
	_slab_mat_moss = lib.pbr("shrine_slab_moss", "stone_wall", 0.33, Color(0.46, 0.53, 0.40), true, 0.4)
	_slab_mat_wet = lib.pbr("shrine_slab_wet", "stone_wall", 0.33, Color(0.42, 0.42, 0.41), true, 0.4)
	for m in [_slab_mat_dry, _slab_mat_moss, _slab_mat_wet]:
		m.roughness = 0.92
		m.specular = 0.12
		m.uv1_world_triplanar = true
		# pbr() 在回傳前就已存成 .tres；上面改的是記憶體裡的物件，
		# 不再存一次就只活在這個 headless 程序裡。
		ResourceSaver.save(m, m.resource_path)
	_slab_kits.clear()
	for k in SLAB_KIT:
		var ps := load(NAT + k + ".gltf") as PackedScene
		if ps == null:
			push_error("石板資產載入失敗 %s" % k)
			continue
		_slab_kits.append([ps, _aabb_of(ps)])
	_slab_log.clear()
	var mats := [_slab_mat_dry, _slab_mat_moss, _slab_mat_wet]

	# ── 參道：鳥居 → 石階底，使用者規格 路寬 2.4–3.2、視覺覆蓋 45–60% ──
	var n1 := _pave_strip(g, "參道鋪石", Z_TORII + 3.0, Z_COURT_S + 9.4 + 0.6,
		0.52, mats, 0.0, PAVE_HW)
	# ── 境內：石階頂 → 白石磚月台南緣 ──
	# 境內只鋪中軸一條，其餘保持踏實土（§21「Courtyard 不得整片鋪石」）。
	var n2 := _pave_strip(g, "境內鋪石", Z_COURT_S - 0.3, DAIS_Z_S,
		0.55, mats, 1.0, PAVE_HW)
	# ── §29 Medium traffic 飛石 ──
	# ⚠ 白石庭院擴到 34 × 23 m 之後，社務所與手水舍**都站在鋪面上**，
	#   原本從拜殿走過去的飛石整條被鋪面蓋掉（起點 z=−22.5 在庭院內）。
	#   改成從庭院**外緣**往外走的短徑：手水舍北側 → 本殿參拜路，
	#   以及庭院東南角 → 境內鋪石帶。兩條都在鋪面之外。
	var n3 := _stepping_stones(g, "飛石_本殿", Vector2(2.0, DAIS_Z_N - 0.6),
		Vector2(3.0, -37.0), mats)
	var n4 := _stepping_stones(g, "飛石_東側", Vector2(DAIS_W * 0.5 + 0.6, -16.0),
		Vector2(21.0, -13.0), mats)
	print("[SHRINE] 鋪石：參道 %d、境內 %d、飛石 %d + %d = %d 塊" % [n1, n2, n3, n4, n1 + n2 + n3 + n4])
	_build_dais(g)
	_audit_paving()


# ══════════════════════════════════════════════════════════════════
# 拜殿前白石磚月台（使用者概念圖「神社白色石磚鋪設示意」，2026-09-05）
#
# ⚠ 概念圖畫的是「整個境內鋪滿白石磚」，與 HAKUREI_SHRINE_AREA_SPEC §21
#   「Courtyard 不得整片鋪石、境內石材 5–20%」直接衝突。
#   使用者裁決：**只做拜殿前面**。所以這裡是一塊有邊界的月台，
#   不是整片境內 —— 兩份規格都不違反。
#
# 概念圖參數（全部照做）：
#   平台高度      0.6–1.0 m（高出周圍地面）→ 取 0.72
#   石磚單塊      0.6–1.2 (長) × 0.4–0.8 m (寬)
#   厚度          0.08–0.15 m
#   縫隙          0.02–0.08 m 不規則
#   高度差/不平整  0.01–0.03 m 隨機
#   顏色          白色～淡灰、略帶青苔污漬
#   磨損          輕度～中度
#   原點          地面 Y = 0，與平台高度對齊
#
# ⚠ 概念圖建議「一張大面積無縫貼圖」。這裡走**單一 BoxMesh 平台 + 三平面
#   貼圖**（不是幾千塊個別石板）：27×22 m 鋪滿要 900+ 塊，個別節點沒有
#   意義（玩家不會去選其中一塊），而且面數會再爆一次。石磚的「塊感」
#   由 stone_flag 貼圖提供 —— 那張本來就是石板拼圖
#   （probe_paving_texture.gd：384², 飽和 0.09 中性灰，tint 提亮即可）。
#   側面石垣另做，才有概念圖剖面圖那圈砌石。
# ══════════════════════════════════════════════════════════════════

# ⚠ 第一版 13 × 12.5 m：實測拜殿佔鋪面可見寬 **69%**，讀成「拜殿的基座」
#   而不是「神社的地面」。使用者指定改為 LARGE WHITE-STONE COURTYARD：
#   拜殿只能佔可見寬的 20–30%，前方要留大片空白，石階直接接上鋪面。
#
#   反推：庭院寬 = 拜殿寬 9.00 / 0.25 ≈ 36 m。但社務所東緣 x=−10.06、
#   手水舍西緣 x=9.40（audit_courtyard_dims.gd 實測），寬度超過 ~19 m
#   就會吃到它們。使用者裁決：兩棟**站在鋪面邊緣上**，取 34 m。
#
#   34 × 23 m：拜殿佔 26% ✓、拜殿前留白 13.2 m（1.7 個拜殿深）、
#   南緣 z=−11.0 接石階頂 z=−9.5、本殿(z −35.55) 仍在鋪面外的土地上。
const DAIS_W := 34.0             # 庭院寬（拜殿 9.0 佔 26%，規格 20–30%）
const DAIS_H := 0.72             # 概念圖 0.6–1.0
const DAIS_Z_N := -34.0          # 北緣（拜殿背面 −31.83 之後 2.2 m）
const DAIS_Z_S := -11.0          # 南緣（石階頂 −9.5，直接相接）
const DAIS_STEP_RISE := 0.18     # 上庭院的踏步，§23 上限


func _build_dais(parent: Node3D) -> void:
	var g := lib.add(parent, Node3D.new(), "拜殿白石磚月台") as Node3D
	var y0 := height_at(0.0, Z_HAIDEN)          # 周圍地面
	var top := y0 + DAIS_H                      # 月台面
	var depth := DAIS_Z_S - DAIS_Z_N
	var cz := (DAIS_Z_N + DAIS_Z_S) * 0.5

	# ── 台面：委製踏石實鋪 ──
	# ⚠ 第一版用 BoxMesh + stone_flag 貼圖，實拍是一片規則六角磁磚，
	#   跟旁邊實體砌石的石垣完全不同世界（使用者截圖指出）。
	#   貼圖救不了 —— 石垣是 baked 2048² 貼在自己 UV 上的，
	#   拿去做 triplanar 會抓到烘焙接縫與 UV 島外的黑底
	#   （probe_paving_texture.gd：baked 圖平均亮度 0.24，含大片黑）。
	#   正解是**用同一套委製件實鋪**：踏石.glb 鋪滿台面，
	#   石垣與台面共用同一組 baked 材質，材質必然一致。
	#
	# 台體本身仍是 BoxMesh（要有實心側面與碰撞），但**藏在踏石底下**，
	# 只當基座；玩家看到的是上面那層石板。
	var base_mat := lib.pbr("shrine_dais_base", "stone_wall", 0.33,
		Color(0.55, 0.54, 0.51), true, 0.4)
	base_mat.roughness = 0.95
	base_mat.uv1_world_triplanar = true
	ResourceSaver.save(base_mat, base_mat.resource_path)
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	# 比實鋪面低 6 cm，讓石板浮在上面（石板厚 8 cm，露出 2 cm 唇口）
	bm.size = Vector3(DAIS_W, DAIS_H - 0.06, depth)
	slab.mesh = bm
	slab.material_override = base_mat
	slab.position = Vector3(0.0, top - 0.06 - (DAIS_H - 0.06) * 0.5, cz)
	lib.add(g, slab, "月台_基座")
	slab.set_meta("concept",
		"概念圖『神社白色石磚鋪設示意』：平台高 %.2f m（規格 0.6-1.0）。"
		% DAIS_H + "範圍限拜殿前（使用者裁決不做整片境內）。台面由踏石實鋪。")

	# 台面實鋪：踏石.glb 排成網格，每塊尺寸/旋轉/高度都有變異
	_build_dais_floor(g, top, cz, depth)

	# ── 側面石垣：實體砌石（野面積み）──
	# ⚠ 第一版用四片 ishizumi 貼圖平板，實拍像貼磁磚的擋土牆，使用者判不及格。
	#   改成一塊塊疊：用**石階同一件** assets/shrine/袖石垣.glb，
	#   全神社的砌石才是同一套語彙（石階兩側已經在用它）。
	#
	# 野面積み的四個特徵，全部照做：
	#   1. 兩皮（course），每皮 0.36 m，接縫上下**交錯**不對齊
	#   2. 每塊寬度不等（0.8–1.4 m）
	#   3. 有「返り」= 往上內縮（batter），每皮縮 4 cm
	#   4. 微幅偏擺 ±2.5°、高度 ±1.5 cm，不是尺規排出來的
	_build_dais_masonry(g, y0, cz, depth)

	# ── 正面踏步：從境內地面上到月台，§23 級高 0.14–0.18 ──
	# 0.72 m ÷ 0.18 = 4 階（§23 Haiden Entrance Steps 允許 2–4 階）
	var n_step := int(ceil(DAIS_H / DAIS_STEP_RISE))
	# ⚠ 庭院擴到 34 m 後，DAIS_W × 0.62 = 21 m 的階梯是宮殿規模，
	#   §0 明禁。階寬改成對齊**主石階**（實測踏石 3.33 / 袖石垣 4.12 m），
	#   取 6.0 m：比主石階寬一點（人流在此散開），但仍是「一道階梯」。
	#   規格 5「石階視覺上直接連進鋪面」靠的是位置對齊，不是階梯寬度。
	var step_w := 6.0
	var tread := 0.36
	# 踏步用委製收頭石（與參道石階同一套件）
	var cap_path := "res://assets/_lod/收頭石.glb"
	for i in n_step:
		var sy := y0 + DAIS_H * float(i + 1) / float(n_step)
		var sz := DAIS_Z_S + tread * float(n_step - i)
		# 兩塊並排，與參道石階同慣例
		for side in [-1.0, 1.0]:
			_step_stone(g, cap_path,
				Vector3(side * step_w * 0.25, sy, sz),
				Vector3(step_w * 0.5, 0.20, tread + 0.04),
				"月台_踏步_%d_%s" % [i, "L" if side < 0.0 else "R"])

	# ── 碰撞：台體 + 踏步（實心塊，凹凸交給視覺）──
	var body := StaticBody3D.new()
	lib.add(g, body, "月台碰撞")
	var sh := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(DAIS_W, DAIS_H, depth)
	sh.shape = bs
	sh.position = Vector3(0.0, top - DAIS_H * 0.5, cz)
	body.add_child(sh); sh.owner = lib.root
	for i in n_step:
		var sy := y0 + DAIS_H * float(i + 1) / float(n_step)
		var sz := DAIS_Z_S + tread * float(n_step - i)
		var sh2 := CollisionShape3D.new()
		var bs2 := BoxShape3D.new()
		var bh2 := sy - y0 + 0.35
		bs2.size = Vector3(step_w, bh2, tread + 0.04)
		sh2.shape = bs2
		sh2.position = Vector3(0.0, sy - bh2 * 0.5, sz)
		body.add_child(sh2); sh2.owner = lib.root

	print("[SHRINE] 白石庭院：%.1f × %.1f m、高 %.2f m；拜殿佔可見寬 %.0f%%（規格 20-30%%）"
		% [DAIS_W, depth, DAIS_H, 9.0 / DAIS_W * 100.0])
	print("[SHRINE]   正面 %d 階、階寬 %.1f m；拜殿前留白 %.1f m；南緣 z=%.1f 接石階頂 z=%.1f"
		% [n_step, step_w, absf(-24.17 - DAIS_Z_S), DAIS_Z_S, -9.5])


## 月台台面實鋪：踏石.glb 排成不規則網格。
##
## 概念圖參數：單塊 0.6–1.2 (長) × 0.4–0.8 m (寬)、厚 0.08–0.15、
## 縫 0.02–0.08、高度差 0.01–0.03。
##
## ⚠ 用**列掃描**而不是規則網格：每列的橫向起點抖動、每塊寬度隨機，
##   縫才不會在列與列之間對齊成十字（概念圖禁「棋盤格」）。
##   13 × 12.5 m ÷ 每塊約 0.7 × 0.9 → 約 250 塊。
func _build_dais_floor(parent: Node3D, top: float, cz: float, depth: float) -> void:
	var g := lib.add(parent, Node3D.new(), "月台鋪面") as Node3D
	# ⚠ 面數：庭院 34×23 = 782 m²，實鋪要 1300 塊。原版踏石 30,510 tris/塊
	#   → 4650 萬面，比改造前整張圖還多。改用 _lod/踏石.glb（gltfpack
	#   -si 0.05，4,109 tris，砍 87%）：轉台圖比對輪廓幾乎無差，
	#   地面石板本來就不需要 3 萬面。1300 × 4.1k ≈ 540 萬面。
	var path := "res://assets/_lod/踏石.glb"
	if not ResourceLoader.exists(path):
		path = "res://assets/shrine/踏石.glb"
		push_warning("_lod/踏石.glb 不存在，退回高模（面數會爆）")
	var ps := load(path) as PackedScene
	var box := _aabb_of(ps)
	# 規格 8：warm off-white / pale gray，不是純白。
	# 踏石的 baked 貼圖偏暖褐（實測平均 0.28,0.25,0.22），
	# tint 提亮同時往冷推一點點，得到暖調灰白。
	var floor_mat := StandardMaterial3D.new()
	var src_mat: StandardMaterial3D = null
	for m in _mesh_nodes(ps.instantiate() as Node3D):
		src_mat = (m as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
		break
	if src_mat != null:
		floor_mat = src_mat.duplicate() as StandardMaterial3D
	# ⚠ 第一版 tint 1.62 過曝：把 baked 貼圖的紋理全洗白，實拍是純白磁磚
	#   （規格 9 明禁 modern tiled-plaza）。1.05 只微提亮，保留石紋與髒污。
	floor_mat.albedo_color = Color(1.06, 1.03, 0.97)
	floor_mat.roughness = 0.88
	floor_mat.metallic = 0.0
	ResourceSaver.save(floor_mat, OUT + "gen/dais_floor_mat.tres")
	floor_mat.take_over_path(OUT + "gen/dais_floor_mat.tres")
	var z0 := cz - depth * 0.5
	var z1 := cz + depth * 0.5
	var half_w := DAIS_W * 0.5
	var n := 0
	var z := z0
	var row := 0
	while z < z1:
		# ⚠ 第一版每列同長 → 橫向連續條紋，像鋪磚。長度改成大幅變異，
		#   且每隔幾列插一條窄列，打斷「一條一條」的節奏。
		# ⚠ 塊數直接決定面數：1127 塊 × 4109 tris = 463 萬面（全場 21.5%）。
		#   概念圖給的單塊上限是 1.2 (長) × 0.8 m (寬)，第一版取 0.5-1.5 ×
		#   0.45-1.15 平均只有 0.75 m，碎得沒必要。往上限靠 → 塊數減半。
		var l := lib.rr(0.85, 1.45) if row % 3 != 2 else lib.rr(0.55, 0.85)
		if z + l > z1:
			l = z1 - z
		if l < 0.35:
			break
		# 每列起點抖動，避免縱縫連成直線
		var x := -half_w + lib.rr(-0.1, 0.1)
		while x < half_w - 0.15:
			var w := lib.rr(0.62, 1.30)           # 沿 x 的寬（往概念圖上限靠）
			if x + w > half_w:
				w = half_w - x
			if w < 0.3:
				break
			var t := lib.rr(0.08, 0.15)           # 厚
			# 不平整加大到 ±2.5 cm（概念圖 0.01-0.03），另有 8% 明顯下陷
			var dy := lib.rr(-0.025, 0.025)
			if lib.rand() < 0.08:
				dy -= lib.rr(0.02, 0.045)
			var s := Vector3(w / maxf(box.size.x, 0.01), t / maxf(box.size.y, 0.01),
				l / maxf(box.size.z, 0.01))
			var inst := ps.instantiate() as Node3D
			inst.scale = s
			# CENTRE 原點：頂面對齊 top + dy
			inst.position = Vector3(x + w * 0.5, top + dy - t - box.position.y * s.y,
				z + l * 0.5)
			inst.rotation.y = lib.rr(-0.055, 0.055)   # ±3.2°，古舊鋪面不是尺規排的
			# 暖灰白：material_override 設在實例根存不下來，要拆成自建節點
			var built := _rebuild_as_own_mesh(inst, floor_mat)
			built.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			lib.add(g, built, "鋪石_%04d" % n)
			n += 1
			x += w + lib.rr(0.02, 0.08)             # 縫
		z += l + lib.rr(0.02, 0.08)
		row += 1
	print("[SHRINE] 月台鋪面 %d 塊踏石（%d 列，與石垣同套件同材質）" % [n, row])


## 月台側面的實體砌石（野面積み）。用 assets/shrine/袖石垣.glb 一塊塊疊。
## ⚠ 這件的原點是 CENTRE（min.y −0.363），單位長 1.90 × 0.73 × 0.42。
##   非等比縮到每塊的目標尺寸，落地公式與 _step_stone 同。
##
## ⚠ 石垣**不能只是一排等寬方塊**——那跟貼圖平板一樣假。四個變因：
##   寬度隨機、上下皮接縫交錯、往上內縮（返り）、微幅偏擺。
func _build_dais_masonry(parent: Node3D, y0: float, cz: float, depth: float) -> void:
	var g := lib.add(parent, Node3D.new(), "月台石垣") as Node3D
	# 庭院擴大後周長 114 m、石垣 205 塊；原版 31k tris/塊 = 640 萬面。
	# 用 _lod（7.8k tris，砍 75%）→ 160 萬。石垣在腰部以下，細節看不到。
	var path := "res://assets/_lod/袖石垣.glb"
	if not ResourceLoader.exists(path):
		path = "res://assets/shrine/袖石垣.glb"
		push_warning("_lod/袖石垣.glb 不存在，退回高模")
	var courses := 2
	var course_h := DAIS_H / float(courses)
	var n := 0
	# 四個邊：[名稱, 沿邊方向, 外法線, 邊長, 邊中心]
	var edges := [
		["南", Vector3(1, 0, 0), Vector3(0, 0, 1), DAIS_W, Vector3(0.0, 0.0, DAIS_Z_S)],
		["北", Vector3(1, 0, 0), Vector3(0, 0, -1), DAIS_W, Vector3(0.0, 0.0, DAIS_Z_N)],
		["西", Vector3(0, 0, 1), Vector3(-1, 0, 0), depth, Vector3(-DAIS_W * 0.5, 0.0, cz)],
		["東", Vector3(0, 0, 1), Vector3(1, 0, 0), depth, Vector3(DAIS_W * 0.5, 0.0, cz)],
	]
	for e in edges:
		var along: Vector3 = e[1]
		var outward: Vector3 = e[2]
		var length: float = e[3]
		var centre: Vector3 = e[4]
		for c in courses:
			# 返り：越上面越往內縮
			var inset := 0.04 * float(c)
			var cy := y0 + course_h * (float(c) + 1.0)      # 這一皮的頂面
			# 上下皮接縫交錯：奇數皮起點偏移半塊
			var t := -length * 0.5 + (0.0 if c % 2 == 0 else lib.rr(0.35, 0.6))
			while t < length * 0.5 - 0.15:
				var w := lib.rr(0.8, 1.4)
				if t + w > length * 0.5:
					w = length * 0.5 - t
				if w < 0.35:
					break
				var pos := centre + along * (t + w * 0.5) \
					+ outward * (0.055 - inset)
				# 高度微差 ±1.5 cm（概念圖：不平整 0.01–0.03）
				var h := course_h + lib.rr(-0.015, 0.015)
				_masonry_block(g, path, Vector3(pos.x, cy, pos.z),
					Vector3(w, h, 0.30), atan2(outward.x, outward.z), n)
				n += 1
				t += w + lib.rr(0.01, 0.04)
	print("[SHRINE] 月台石垣 %d 塊（袖石垣，%d 皮、接縫交錯、返り %.0f cm/皮）"
		% [n, courses, 4.0])


## 放一塊砌石：非等比縮到 size、頂面對齊 top_y、面朝 yaw。
func _masonry_block(parent: Node3D, path: String, pos: Vector3, size: Vector3,
		yaw: float, idx: int) -> void:
	var ps := load(path) as PackedScene
	var box := _aabb_of(ps)
	var s := Vector3(size.x / maxf(box.size.x, 0.01), size.y / maxf(box.size.y, 0.01),
		size.z / maxf(box.size.z, 0.01))
	var inst := ps.instantiate() as Node3D
	inst.scale = s
	inst.position = Vector3(pos.x, pos.y - size.y - box.position.y * s.y, pos.z)
	inst.rotation.y = yaw + lib.rr(-0.045, 0.045)     # ±2.5°
	inst.rotation.x = lib.rr(-0.02, 0.02)
	lib.add(parent, inst, "砌石_%03d" % idx)


## 抽一塊石板：回傳 [PackedScene, AABB, 目標寬 w, 目標長 l, 目標厚 t]
func _pick_slab() -> Array:
	var kit: Array = _slab_kits[int(lib.rand() * _slab_kits.size()) % _slab_kits.size()]
	return [kit[0], kit[1], lib.rr(SLAB_W[0], SLAB_W[1]), lib.rr(SLAB_L[0], SLAB_L[1]),
		lib.rr(SLAB_T[0], SLAB_T[1])]


## 實例化一塊石板：非等比縮到目標 w×t×l，BASE 原點落地。
func _slab_inst(pick: Array, p: Vector2, y_top: float, rot_y: float) -> Node3D:
	var ps: PackedScene = pick[0]
	var box: AABB = pick[1]
	var s := Vector3(pick[2] / maxf(box.size.x, 0.01), pick[4] / maxf(box.size.y, 0.01),
		pick[3] / maxf(box.size.z, 0.01))
	var inst := ps.instantiate() as Node3D
	inst.scale = s
	# 頂面對齊 y_top：原點在 BASE，所以 位置 = 頂面 − 厚
	inst.position = Vector3(p.x, y_top - pick[4] - box.position.y * s.y, p.y)
	inst.rotation.y = rot_y
	return inst


## 沿 x=0 中軸從 z0 鋪到 z1 的帶狀石板路。
## cover = 目標覆蓋率（帶內），用 (1) 帶寬 (2) 每列隨機缺塊 兩個旋鈕達成。
## court = 1 時是境內段：帶更窄、缺塊更多、苔比例低（高流量 §29）。
func _pave_strip(parent: Node3D, name: String, z0: float, z1: float,
		cover: float, mats: Array, court: float, band_hw: float, edge_keep := 0.30) -> int:
	var g := lib.add(parent, Node3D.new(), name) as Node3D
	var made := 0
	var z := maxf(z0, z1)
	var z_end := minf(z0, z1)
	var row := 0
	while z > z_end:
		# 一列：從左到右塞石板，寬度隨機，縫隨機。
		# 每列起點抖 ±0.12，不然縫會在列與列之間對齊成直線（§21 禁棋盤格）。
		var x := -band_hw + lib.rr(-0.12, 0.12)
		var row_len := 0.0
		while x < band_hw - 0.15:
			var pick := _pick_slab()
			var w: float = pick[2]
			var l: float = pick[3]
			row_len = maxf(row_len, l)
			var cx := x + w * 0.5
			# 最後一塊允許稍微出帶 12 cm（不然帶邊永遠是一條直線）
			if cx + w * 0.5 > band_hw + 0.12:
				break
			# 缺塊：讓覆蓋率落到目標、也做 §21「禁完全等距」。
			#
			# ⚠ 使用者規格（2026-09-05 補充）：「禁 random isolated stones that
			#   fail to read as a path」。前一版每塊獨立擲骰，缺塊均勻散在整條
			#   帶上，實拍是一地散石不是路。改成**中央連續、邊緣剝落**：
			#   中軸 ±0.55 m 內幾乎不缺（keep≈0.97），往帶邊線性掉到 ~0.35。
			#   路感來自中央那條連續帶，覆蓋率靠邊緣剝落調。
			var lateral := clampf(absf(cx) / band_hw, 0.0, 1.0)
			var core := 1.0 - smoothstep(0.35, 1.0, lateral)     # 中央 1 → 邊緣 0
			var keep := lerpf(edge_keep, 0.97, core)
			# cover 當整體增益：0.5 → ×1.0，0.6 → ×1.2
			keep *= cover / 0.5
			keep = clampf(keep, 0.0, 0.99)
			if lib.rand() < keep:
				_slab(g, pick, Vector2(cx, z - l * 0.5), mats, lateral, court, made)
				made += 1
			x += w + lib.rr(SLAB_GAP[0], SLAB_GAP[1] if court < 1.0 or band_hw < 2.0 else 0.06)
		z -= row_len + lib.rr(SLAB_GAP[0], SLAB_GAP[1] if court < 1.0 or band_hw < 2.0 else 0.06)
		row += 1
	return made


## 放一塊石板：位置、±3–8° 旋轉、±1–3.5 cm 高度、§22 老化分配。
func _slab(parent: Node3D, pick: Array, p: Vector2, mats: Array,
		lateral: float, court: float, idx: int) -> void:
	var y := height_at(p.x, p.y)
	# §21 height variation ±0.01–0.035；§22 sunken stones 3–10% 再多沉 2–4 cm
	var dy := lib.rr(SLAB_DY[0], SLAB_DY[1]) * (1.0 if lib.rand() < 0.5 else -1.0)
	var sunken := lib.rand() < 0.07
	if sunken:
		dy -= lib.rr(0.02, 0.04)
	# §22 broken/chipped 5–12%：縮短一側模擬缺角
	if lib.rand() < 0.08:
		pick[2] *= lib.rr(0.72, 0.9)
		pick[3] *= lib.rr(0.72, 0.9)
	var rot := deg_to_rad(lib.rr(SLAB_ROT_DEG[0], SLAB_ROT_DEG[1])) * (1.0 if lib.rand() < 0.5 else -1.0)
	# 石板頂面 ≈ 地面 + 2 cm（微凸出土面，不是整塊浮在上面）
	var inst := _slab_inst(pick, p, y + 0.02 + dy, rot)
	# 微傾（沉陷的石板會歪）
	if sunken:
		inst.rotation.x = lib.rr(-0.03, 0.03)
		inst.rotation.z = lib.rr(-0.03, 0.03)
	# 老化分配（使用者規格）：中央流量帶 low moss；邊緣帶苔 10–25%。
	# lateral ≥ 0.6 算邊緣帶。中央 4%、邊緣 18%（目標中值）。濕暗另加。
	var is_edge := lateral >= 0.6
	var r := lib.rand()
	# 邊緣帶樣本只有 ~40 塊，0.18 的期望值在這個樣本數下實測會落到 5%。
	# 提到 0.30 讓實測落在規格 10-25% 的中段。
	var moss_p := (0.30 if is_edge else 0.04) * lerpf(1.0, 0.8, court)
	var wet_p := 0.10 if is_edge else 0.05
	var mat: Material = mats[0]
	var kind := 0
	if r < moss_p:
		mat = mats[1]
		kind = 1
	elif r < moss_p + wet_p:
		mat = mats[2]
		kind = 2
	# ⚠ GLB 實例的內部 MeshInstance3D 不會被序列化（獸道紅葉那次的教訓），
	#   但 material_override 設在**內部節點**也一樣存不下來。這裡的 inst 是
	#   實例根，把子網格拆出來自建 MeshInstance3D 掛同一份 mesh 才存得住。
	var built := _rebuild_as_own_mesh(inst, mat)
	lib.add(parent, built, "石板_%04d" % idx)
	_slab_log.append([p, pick[2] * 0.5, pick[3] * 0.5, is_edge, kind])


## 把 GLB 實例的第一個 MeshInstance3D 抄成自己的節點（mesh 共用、材質覆蓋），
## 保留實例的 transform。這樣 material_override 才會進 .tscn。
func _rebuild_as_own_mesh(inst: Node3D, mat: Material) -> MeshInstance3D:
	var src: MeshInstance3D = null
	for m in _mesh_nodes(inst):
		src = m as MeshInstance3D
		break
	var mi := MeshInstance3D.new()
	mi.mesh = src.mesh
	mi.transform = inst.transform * _rel(src, inst)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.free()
	return mi


## §29 Medium traffic：從 a 走到 b 的飛石（間距一步 0.55–0.75 m，略蛇行）。
func _stepping_stones(parent: Node3D, name: String, a: Vector2, b: Vector2,
		mats: Array) -> int:
	var g := lib.add(parent, Node3D.new(), name) as Node3D
	var made := 0
	var dir := (b - a).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var total := a.distance_to(b)
	var d := 0.0
	while d < total:
		var p := a + dir * d + perp * sin(d * 1.7) * 0.25 + perp * lib.rr(-0.12, 0.12)
		var pick := _pick_slab()
		# 飛石之間刻意留土，不是連續路面：跳過 25%
		if lib.rand() > 0.25:
			var rot := atan2(dir.x, dir.y) + deg_to_rad(lib.rr(-25.0, 25.0))
			var inst := _slab_inst(pick, p, height_at(p.x, p.y) + 0.02, rot)
			# 飛石苔多一點（§29 medium traffic）
			var mat: Material = mats[1] if lib.rand() < 0.22 else mats[0]
			lib.add(g, _rebuild_as_own_mesh(inst, mat), "飛石_%03d" % made)
			_slab_log.append([p, pick[2] * 0.5, pick[3] * 0.5, true, 1 if mat == mats[1] else 0])
			made += 1
		d += lib.rr(0.55, 0.75) + pick[3] * 0.5
	return made


## 點 p 是否落在任何石板（軸對齊近似，忽略 ±8° 旋轉）上。
func _on_slab(p: Vector2, pad: float) -> bool:
	# 只有主軸帶與飛石帶附近才可能有石板，先粗篩省時間
	if absf(p.x) > 12.0:
		return false
	for e in _slab_log:
		var c: Vector2 = e[0]
		if absf(p.x - c.x) <= float(e[1]) + pad and absf(p.y - c.y) <= float(e[2]) + pad:
			return true
	return false


## 覆蓋率自檢：三段各自量「路面帶內被石板蓋住的取樣點比例」。
## 「境內整體 5–20%」量整個 27×22 境內面積。
## 參道段依使用者補充規格：帶寬 2.8 m、覆蓋 45–60%。
func _audit_paving() -> void:
	var zones := [
		["參道 45-60%", -PAVE_HW, PAVE_HW, Z_COURT_S + 10.0, Z_TORII + 3.0, PAVE_COVER[0], PAVE_COVER[1]],
		# 近拜殿區已改成白石磚月台（概念圖），是實心平台不是散石板，
		# 覆蓋率恆為 100%，不再用石板取樣量 —— 改由 _audit_dais 驗尺寸。
		["境內鋪石帶", -PAVE_HW, PAVE_HW, DAIS_Z_S, Z_COURT_S, 40.0, 70.0],
		# 境內整體：§21 要 5–20%。含白石磚月台（拜殿前，概念圖）與中軸鋪石帶。
		# 月台 13×12.5 = 163 m² 佔境內 27×22 = 594 m² 的 27%，單獨就超標，
		# 但 §21 的 5–20% 講的是「散置石材」；成片的拜殿基座是建築的一部分
		# （§4 Haiden footprint），不是 courtyard paving。所以量測範圍排除
		# 月台佔地，只驗「月台以外的境內」還是不是 packed earth 為主。
		["境內(月台以南) 5-20%", -COURT_W * 0.5, COURT_W * 0.5, DAIS_Z_S, Z_COURT_S, 5.0, 20.0],
	]
	for zn in zones:
		var hit := 0
		var n := 0
		var step := 0.12
		var x: float = zn[1]
		while x <= zn[2]:
			var z: float = zn[3]
			while z <= zn[4]:
				n += 1
				var p := Vector2(x, z)
				# 白石磚月台是實心鋪面，不在 _slab_log 裡，要單獨算
				if absf(p.x) <= DAIS_W * 0.5 and p.y >= DAIS_Z_N and p.y <= DAIS_Z_S:
					hit += 1
					z += step
					continue
				for e in _slab_log:
					var c: Vector2 = e[0]
					if absf(p.x - c.x) <= float(e[1]) and absf(p.y - c.y) <= float(e[2]):
						hit += 1
						break
				z += step
			x += step
		var pct := 100.0 * float(hit) / maxf(float(n), 1.0)
		var ok := pct >= float(zn[5]) and pct <= float(zn[6])
		print("[SHRINE] 鋪石覆蓋 %-14s %5.1f%%  %s" % [zn[0], pct, "✓" if ok else "✗ 超出規格"])
		if not ok:
			push_warning("§21 %s 實測 %.1f%%" % [zn[0], pct])
	# 邊緣帶苔比例（使用者規格 10–25%）、中央帶苔比例（low）
	var edge_n := 0
	var edge_moss := 0
	var core_n := 0
	var core_moss := 0
	for e in _slab_log:
		var c: Vector2 = e[0]
		if c.y < Z_COURT_S + 10.0 or c.y > Z_TORII + 3.0:
			continue
		if bool(e[3]):
			edge_n += 1
			if int(e[4]) == 1: edge_moss += 1
		else:
			core_n += 1
			if int(e[4]) == 1: core_moss += 1
	var ep := 100.0 * float(edge_moss) / maxf(float(edge_n), 1.0)
	var cp := 100.0 * float(core_moss) / maxf(float(core_n), 1.0)
	var eok := ep >= EDGE_MOSS[0] and ep <= EDGE_MOSS[1]
	print("[SHRINE] 參道苔石：邊緣帶 %.1f%%（%d/%d，規格 10-25%%）%s ／ 中央帶 %.1f%%（%d/%d，low）"
		% [ep, edge_moss, edge_n, "✓" if eok else "✗", cp, core_moss, core_n])
	if not eok:
		push_warning("參道邊緣苔石 %.1f%% 超出 10-25%%" % ep)
	# 路徑連續性自檢：沿中軸每 0.5 m 取樣，中央 ±0.55 m 內找不到石板 = 斷點。
	# 「random isolated stones that fail to read as a path」的可量化版本。
	var gaps := 0
	var run := 0
	var worst_run := 0
	var samples := 0
	var z := Z_TORII + 3.0
	while z > Z_COURT_S + 10.0:
		samples += 1
		var found := false
		for e in _slab_log:
			var c: Vector2 = e[0]
			if absf(c.x) > 0.55 + float(e[1]):
				continue
			if absf(z - c.y) <= float(e[2]) + 0.06:
				found = true
				break
		if found:
			run = 0
		else:
			gaps += 1
			run += 1
			worst_run = maxi(worst_run, run)
		z -= 0.5
	print("[SHRINE] 參道連續性：%d/%d 取樣中央無石板，最長斷段 %.1f m（>1.5 m 即不像路）%s"
		% [gaps, samples, worst_run * 0.5, "✓" if worst_run * 0.5 <= 1.5 else "✗"])
	if worst_run * 0.5 > 1.5:
		push_warning("參道中央有 %.1f m 斷段，讀不出是路" % (worst_run * 0.5))


# ══════════════════════════════════════════════════════════════════
# §7 Vegetation Structure / §8 Tree Composition / §17 Density Gradient
#
# 三帶：Zone A 核心 LOW → Zone B 境內邊緣 MEDIUM → Zone C 外圍森林 HIGH。
#
# ⚠ §7 明訂「禁止 uniform scatter，使用 MASS / CLUSTER」——所以外圍樹不是
#   全域均勻亂灑，而是先撒 cluster 種子再繞著種子長，中間留出空隙。
#
# ⚠ 原點不一致，兩種資產不能共用落地公式（probe_shrine_flora.gd 實測）：
#     assets/landscape/*.glb（Meshy）  單位化、原點 CENTRE，min.y = −0.500
#     assets/nature/*.gltf（Quaternius）公尺單位、多半 BASE，少數帶小 offset
#   統一用 `y − box.position.y × scale`，兩種都對。
#
# ⚠ 樹用高度定 scale、地被用**最大水平邊**。獸道踩過這個雷：
#   Plant_7_Big 本地高 0.25 m 但寬 1.9 m，用高度算出來是 11 m 寬的巨葉。
#
# ⚠ 面數預算（GTX 1070）：Meshy 樹 11-14k tris / 棵，Quaternius 4-6k。
#   近景與 Hero 用 Meshy，外圍 mass 一律 Quaternius，否則光植被就破千萬面。
# ══════════════════════════════════════════════════════════════════

const LS := "res://assets/landscape/"
const NAT := "res://assets/nature/"

## 淨空清單：[x, z, 半徑]。建築 footprint + 主軸視線另外處理。
var _keepout: Array = []

## §8 Hero Tree 12–18 m、背景樹 8–14 m。
##
## ⚠ `landscape/松樹.glb` 名字叫松，實際是**橘紅楓樹**（probe_flora_color.gd
##   實測葉面平均 H=17.1、S=0.68，轉台圖確認整棵橘紅）。§0 明列「禁止過度
##   櫻花化」，成片出現會把神社變成賞楓景點——所以整批樹池不收它。
##   檔名不是資產的權威，貼圖平均色才是。
##
## ⚠ 全圖只用 Meshy landscape 樹，**不混 Quaternius**。兩套的葉色飽和度差
##   兩倍多（probe_flora_color.gd 實測）：
##       Meshy 大衫      S=0.37  V=0.35   灰綠、PBR、與神社建築同世界
##       Quaternius Pine S=1.00  V=0.35   純色高飽和卡通綠
##       Quaternius 樹幹 H=17.6 S=0.52    粉褐色
##   第一版外圍用 Quaternius，實拍時穿過鳥居的瞬間綠色整片跳掉，前景是
##   粉紅樹幹的卡通林、後景是灰綠寫實林。省下的面數不值這個代價。
##   （地被仍用 Quaternius —— 尺寸小、離鏡頭遠，色差不成立體。）
const HERO_TREES := ["大衫", "2大衫", "針葉林樹3"]
const MID_TREES := ["普通樹", "針葉樹1", "針葉樹2glb", "針葉林樹3", "針葉林樹4"]
const FAR_TREES := ["針葉樹1", "針葉樹2glb", "針葉林樹3", "針葉林樹4",
	"普通樹", "大衫", "2大衫"]

var _tree_log: Array = []      # [Vector2 中心, 樹冠半徑] — 視線自檢用
var _edge_grass_log: Array = []   # [Vector2, 半徑] — 參道邊緣帶草侵入自檢用


func _build_vegetation() -> void:
	var g := lib.add(lib.root, Node3D.new(), "植被") as Node3D
	_collect_keepout()
	_build_hero_trees(g)
	_build_zone_b(g)
	_build_zone_c(g)
	_build_boundary_forest(g, maxf(HALF_X, HALF_Z))
	_build_corridor_trees(g)
	_build_ground_cover(g)
	_audit_sightline()
	_audit_vista_openings()


## 建築與主軸不可被樹侵入。
func _collect_keepout() -> void:
	_keepout = [
		[0.0, Z_HAIDEN, 9.5],          # 拜殿 9.0 寬 → 半徑 + 餘裕
		[0.0, Z_HONDEN, 6.5],          # 本殿
		[-13.5, -22.0, 6.5],           # 社務所
		[11.0, -14.5, 4.0],            # 手水舍
		[-9.6, -18.6, 1.8],            # 陰陽玉（彩蛋要看得到）
		[0.0, Z_TORII, 8.0],           # 鳥居
	]


func _blocked(p: Vector2, extra: float) -> bool:
	for k in _keepout:
		if p.distance_to(Vector2(k[0], k[1])) < float(k[2]) + extra:
			return true
	return false


## §13 主軸視線 Torii → Courtyard → Haiden 必須清楚。
## 參道 §2 寬 2.5–3.5 m，但「看得到」比「走得過」需要更寬的錐形淨空：
## 從入口 z=+53 到拜殿 z=−28，半寬由 6 m 收到 5 m。
func _axis_clear(p: Vector2, pad: float) -> bool:
	if p.y < Z_HAIDEN - 2.0 or p.y > Z_ENTRY + 4.0:
		return false
	var t := clampf((Z_ENTRY - p.y) / (Z_ENTRY - Z_HAIDEN), 0.0, 1.0)
	return absf(p.x) < lerpf(6.0, 5.0, t) + pad


## 白石庭院佔地：樹、地被、飛石一律不得進入（使用者：蓋到的樹林要刪掉）。
## pad > 0 時往外擴，用來讓樹幹離鋪面邊緣再遠一點。
func _in_dais(p: Vector2, pad: float = 0.0) -> bool:
	return absf(p.x) <= DAIS_W * 0.5 + pad 		and p.y >= DAIS_Z_N - pad and p.y <= DAIS_Z_S + pad


func _in_court(p: Vector2) -> bool:
	return absf(p.x) < COURT_W * 0.5 and p.y > Z_COURT_N and p.y < Z_COURT_S


## §13 secondary sightline「courtyard → mountain」＋ border-vistas.md
## 「神社西側 = 俯瞰整個盆地、遠處妖怪之山，全遊戲最好的展望」。
## 從境內中央往西北開一道 34° 的扇形走廊，Zone B/C 樹不進來；
## 地形在這個扇形裡也不抬（見 height_at 的谷壁抬升）。
## 第一版沒有這條，_audit_vista_openings 實測四面樹冠仰角 15–27°，
## 放了妖怪之山也一片葉子看不到。
const VISTA_DIR := Vector2(-0.92, -0.39)   # 西偏北 23°，對準妖怪之山 (−640, −580)
const VISTA_HALF_ANGLE_DEG := 17.0

func _in_vista_corridor(p: Vector2) -> bool:
	var origin := Vector2(0.0, (Z_COURT_N + Z_COURT_S) * 0.5)
	var rel := p - origin
	var d := rel.length()
	if d < 4.0:
		return false
	return rel.normalized().dot(VISTA_DIR) > cos(deg_to_rad(VISTA_HALF_ANGLE_DEG))


## 放一棵樹。tall = 目標高（公尺）。回傳實際樹冠水平半徑。
## 樹的 LOD 距離門檻（m，離境內中心）。境內看得到的近景保高模，
## 遠處換 _lod（gltfpack -si 0.30 -sa：11.5k → 2.9k tris，砍 75%）。
##
## ⚠ -sa（aggressive）會讓葉片破碎、樹幹變暗一階，轉台圖看得出來。
##   所以**不能全場替換** —— 只用在 LOD_DIST 以外，那個距離下差異
##   被大氣與樹冠重疊蓋掉。近處 120 棵維持原模。
##   （-si 不加 -sa 只砍得掉 10-15%：葉片是分離小面片，簡化器動不了。）
const TREE_LOD_DIST := 46.0

func _tree(parent: Node3D, path: String, p: Vector2, tall: float,
		shadow: bool, ground_y: float = NAN) -> float:
	# 依距離換 LOD。境內中心 (0, −20.5)。
	var d_eye := p.distance_to(Vector2(0.0, (Z_COURT_N + Z_COURT_S) * 0.5))
	if d_eye > TREE_LOD_DIST and path.begins_with(LS):
		var lod := path.replace(LS, "res://assets/_lod/")
		if ResourceLoader.exists(lod):
			path = lod
	var ps := load(path) as PackedScene
	if ps == null:
		push_error("樹資產載入失敗 %s" % path)
		return 0.0
	var box := _aabb_of(ps)
	var s := tall / maxf(box.size.y, 0.01)
	var inst := ps.instantiate() as Node3D
	# 遊玩區外的樹站在 vista 網格上，不是 terrain —— 呼叫端傳 ground_y
	var y := height_at(p.x, p.y) if is_nan(ground_y) else ground_y
	# 原點 CENTRE 或 BASE 都吃這一條：把 AABB 底邊拉到地面。
	# −0.05 是刻意的微沉，避免根部與地形起伏之間露出縫。
	inst.position = Vector3(p.x, y - box.position.y * s - 0.05, p.y)
	inst.rotation.y = lib.rand() * TAU
	inst.rotation.x = lib.rr(-0.025, 0.025)
	inst.rotation.z = lib.rr(-0.025, 0.025)
	inst.scale = Vector3(s, s * lib.rr(0.92, 1.10), s)
	lib.add(parent, inst, "%s_%04d" % [path.get_file().get_basename(), _tree_log.size()])
	if not shadow:
		for mn in _mesh_nodes(inst):
			(mn as GeometryInstance3D).cast_shadow = \
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var crown := maxf(box.size.x, box.size.z) * s * 0.5
	_tree_log.append([p, crown])
	return crown


## §8：境內主要樹 2–5 棵，其中 1–2 棵 Hero（12–18 m）。
## §7 Zone A「不得遮住拜殿主立面」——所以全部推到境內側後方與角落，
## 且不進入主軸淨空錐。
func _build_hero_trees(parent: Node3D) -> void:
	var g := lib.add(parent, Node3D.new(), "境內主要樹") as Node3D
	# [x, z, 高, 是否 Hero]。位置手選而非亂數：§8 要用 canopy overlap /
	# sightline 判斷，不是固定 spacing。
	#
	# ⚠ 冠幅要當成硬約束。大衫的水平最大邊 = 高度 ×1.00，16.5 m 的 Hero
	#   冠幅就是 16.5 m（半徑 8.25）。第一版放在 x=±11~12.5、離拜殿只有
	#   11 m，實拍時樹冠從畫面左右兩側整片壓進來，境內看起來不是「開闊」
	#   而是被兩棵樹夾住。§0 關鍵詞是「開闊 / 大量天空」，所以往外推到
	#   ±17~19、並退到拜殿背後，讓它們當背景天際線而不是前景框。
	var sites := [
		# ⚠ 前兩版放 (−18,−34)、(−22,−27)，離走廊軸線只有 14° / 7°，16.5 m 的
		#   Hero 樹冠把西北展望封到 33° 仰角。走廊軸是西偏北 23°，所以 Hero
		#   要往「正北偏西」退：(−14, −40) 夾角 30°，在拜殿正後方偏西，
		#   仍撐得起境內北面天際線。
		[-14.0, -40.0, 16.5, true],    # 拜殿西後方，Hero，撐起境內天際線
		[19.0, -31.0, 14.0, true],     # 拜殿東後方，第二棵 Hero，不對稱
		[17.5, -18.0, 10.5, false],    # 東側中景，替手水舍作背景
		[-11.5, -11.0, 9.5, false],    # 西南角，石階頂的側向 framing
	]
	var body := StaticBody3D.new()
	lib.add(g, body, "主要樹碰撞")
	for i in sites.size():
		var st: Array = sites[i]
		var p := Vector2(st[0], st[1])
		var tall: float = st[2]
		if _in_dais(p, 1.0):
			push_warning("主要樹 @ (%.1f, %.1f) 落在白石庭院內，已略過" % [p.x, p.y])
			continue
		var pool: Array = HERO_TREES if st[3] else MID_TREES
		var name: String = pool[i % pool.size()]
		var crown := _tree(g, LS + name + ".glb", p, tall, true)
		var sh := CollisionShape3D.new()
		var c := CylinderShape3D.new()
		c.radius = 0.45
		c.height = tall * 0.6
		sh.shape = c
		sh.position = Vector3(p.x, height_at(p.x, p.y) + tall * 0.3, p.y)
		body.add_child(sh); sh.owner = lib.root
		print("[SHRINE] 主要樹 %-8s 高 %.1f m 冠幅 %.1f m @ (%.1f, %.1f)%s"
			% [name, tall, crown * 2.0, p.x, p.y, "  ← Hero" if st[3] else ""])


## Zone B 境內邊緣：MEDIUM。old trees / shrubs / ferns / grass / rocks。
## §7「形成不對稱 framing」——西側刻意比東側密。
func _build_zone_b(parent: Node3D) -> void:
	var g := lib.add(parent, Node3D.new(), "境內邊緣林") as Node3D
	var made := 0
	var tries := 0
	while made < 46 and tries < 6000:
		tries += 1
		var x := lib.rr(-40.0, 40.0)
		var z := lib.rr(Z_HONDEN - 8.0, Z_COURT_S + 12.0)
		var p := Vector2(x, z)
		# 境內內部不種（那是 Zone A），只在境內外緣一圈 4–18 m 的環帶
		var d_court := maxf(absf(x) - COURT_W * 0.5,
			maxf(Z_COURT_N - z, z - Z_COURT_S))
		if d_court < 3.0 or d_court > 18.0:
			continue
		if _blocked(p, 2.5) or _axis_clear(p, 1.0) or _in_vista_corridor(p) 				or _in_dais(p, 1.2):
			continue
		# 不對稱：西（x<0）密、東疏
		var w := 0.85 if x < 0.0 else 0.45
		if lib.rand() > w:
			continue
		var ok := true
		for e in _tree_log:
			if p.distance_to(e[0]) < 4.0:
				ok = false
				break
		if not ok:
			continue
		var tall := lib.rr(8.0, 13.5)
		var name: String = MID_TREES[int(lib.rand() * MID_TREES.size()) % MID_TREES.size()]
		_tree(g, LS + name + ".glb", p, tall, true)
		made += 1
	print("[SHRINE] Zone B 境內邊緣林 %d 棵（MEDIUM，西密東疏）" % made)


## Zone C 外圍森林：HIGH，把神社包在谷地裡（§0「偏僻」）。
## §7「不要逐棵平均排列」→ 先撒 cluster 種子，樹繞著種子長。
func _build_zone_c(parent: Node3D) -> void:
	var g := lib.add(parent, Node3D.new(), "外圍森林") as Node3D
	# cluster 種子
	var seeds: Array = []
	for i in 70:
		var sx := lib.rr(-HALF_X + 6.0, HALF_X - 6.0)
		var sz := lib.rr(-HALF_Z + 6.0, HALF_Z - 6.0)
		var sp := Vector2(sx, sz)
		# 種子本身要離境內夠遠
		if absf(sx) < 26.0 and sz > Z_HONDEN - 6.0 and sz < Z_COURT_S + 14.0:
			continue
		seeds.append([sp, lib.rr(7.0, 17.0)])
	var groups := {}
	var made := 0
	var tries := 0
	while made < 760 and tries < 60000:
		tries += 1
		var sd: Array = seeds[int(lib.rand() * seeds.size()) % seeds.size()]
		var c: Vector2 = sd[0]
		var r: float = sd[1]
		var a := lib.rand() * TAU
		# sqrt 讓分布往邊緣散，不是全擠在種子上
		var rr := sqrt(lib.rand()) * r
		var p := c + Vector2(cos(a), sin(a)) * rr
		if absf(p.x) > HALF_X - 5.0 or absf(p.y) > HALF_Z - 5.0:
			continue
		if _blocked(p, 4.0) or _axis_clear(p, 2.5) or _in_vista_corridor(p) 				or _in_dais(p, 1.2):
			continue
		# 境內與其外緣 18 m 內是 Zone A/B 的地盤
		var d_court := maxf(absf(p.x) - COURT_W * 0.5,
			maxf(Z_COURT_N - p.y, p.y - Z_COURT_S))
		if d_court < 17.0:
			continue
		# 參道兩側：留出 §2 的路寬 + 視覺餘裕，但外側要密（§17 梯度）
		if p.y > Z_COURT_S and p.y < Z_ENTRY + 4.0 and absf(p.x) < 8.5:
			continue
		var ok := true
		for e in _tree_log:
			if p.distance_to(e[0]) < 3.0:
				ok = false
				break
		if not ok:
			continue
		var name: String = FAR_TREES[int(lib.rand() * FAR_TREES.size()) % FAR_TREES.size()]
		var tall := lib.rr(9.0, 15.0)
		# 離境內越遠越高，形成谷壁的林冠線
		var far := clampf(Vector2(p.x * 0.62, p.y + 20.0).length() / 60.0, 0.0, 1.0)
		tall = lerpf(tall, tall * 1.25, far)
		if not groups.has(name):
			groups[name] = lib.add(g, Node3D.new(), name)
		# 40 m 外關投影：玩家看不到，但陰影是 GTX 1070 上最貴的一項
		var near_enough := d_court < 40.0
		_tree(groups[name], LS + name + ".glb", p, tall, near_enough)
		made += 1
	print("[SHRINE] Zone C 外圍森林 %d 棵（%d 個 cluster 種子）" % [made, seeds.size()])


## §6 Ground：境內中央 vegetation intrusion <10%、境內邊緣 25–45%。
## §7 Zone A「低草 + 少量青苔」。
## 地被一律用最大水平邊定 scale（見檔頭警告），且全部關投影。
func _build_ground_cover(parent: Node3D) -> void:
	var g := lib.add(parent, Node3D.new(), "地表植被") as Node3D
	# [名稱, 變體, 目標最大水平邊 m, 目標數量, 境內中央權重, 邊緣權重, 外圍權重]
	#
	# ⚠ 尺寸是「最大水平邊」不是高度（見檔頭）。第一版矮草給到 0.95 m、
	#   小植栽 1.1 m，實拍在人眼高度是一叢一叢貼著鏡頭的巨大卡通葉片
	#   （03_stairs 那張，前景幾乎被葉子佔滿）。真實草叢的水平幅寬在
	#   0.25-0.6 m 這個量級，照著收。
	var specs := [
		["矮草", ["Grass_Common_Short", "Grass_Wispy_Short"], [0.28, 0.55], 2600, 0.10, 0.85, 0.75],
		["高草", ["Grass_Common_Tall", "Grass_Wispy_Tall"], [0.40, 0.75], 1300, 0.00, 0.45, 0.85],
		["苜蓿", ["Clover_1", "Clover_2"], [0.22, 0.42], 900, 0.16, 0.60, 0.35],
		["蕨", ["Fern_1"], [0.55, 0.95], 420, 0.00, 0.35, 0.70],
		# ⚠ Bush_Common 的葉貼圖是 Leaves_TwistedTree_C（實測 H=0.4、S=0.87
		#   的深紅），成叢出現就是一片紅點。只收 _Flowers 版（葉面是
		#   Leaves_NormalTree_C，H=77 綠）。
		["灌木", ["Bush_Common_Flowers"], [0.8, 1.5], 260, 0.00, 0.30, 0.65],
		# 野花的 Flowers.png 是 H=18 的橘紅，但單株尺寸小、數量少，
		# 是 §6 允許的 misc ≤10%，不構成「過度櫻花化」。
		["野花", ["Flower_3_Group", "Flower_4_Group", "Flower_3_Single"], [0.25, 0.5], 300, 0.06, 0.35, 0.25],
		["小植栽", ["Plant_1", "Plant_7"], [0.35, 0.7], 300, 0.00, 0.35, 0.45],
		["苔石", ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"], [0.6, 1.8], 130, 0.00, 0.25, 0.55],
		["菇", ["Mushroom_Common", "Mushroom_Laetiporus"], [0.18, 0.35], 90, 0.00, 0.10, 0.40],
	]
	var total := 0
	for sp in specs:
		var name: String = sp[0]
		var vars: Array = sp[1]
		var sr: Array = sp[2]
		var n: int = sp[3]
		var w_core: float = sp[4]
		var w_edge: float = sp[5]
		var w_out: float = sp[6]
		var sub := lib.add(g, Node3D.new(), name) as Node3D
		var made := 0
		var tries := 0
		while made < n and tries < n * 30:
			tries += 1
			var x := lib.rr(-HALF_X + 4.0, HALF_X - 4.0)
			var z := lib.rr(-HALF_Z + 4.0, HALF_Z - 4.0)
			var p := Vector2(x, z)
			if _blocked(p, 0.8) or _in_dais(p, 0.15):
				continue
			# 參道路面：中央流量帶 ±0.85 m 完全淨空（使用者規格 low vegetation）；
			# 邊緣帶 0.85–1.4 m 只允許矮草／苜蓿低機率侵入（grass intrusion 10–20%），
			# 帶外 +0.4 m 再回到一般密度。
			var on_approach := p.y > Z_COURT_S and p.y < Z_ENTRY + 4.0
			var approach_edge := false
			if on_approach:
				if absf(x) < PAVE_HW * 0.6:
					continue
				if absf(x) < PAVE_HW + 0.4:
					if name not in ["矮草", "苜蓿"]:
						continue
					approach_edge = true
			if p.y > Z_COURT_S - 0.5 and p.y < Z_COURT_S + 10.5 and absf(x) < STEP_W * 0.5 + 0.5:
				continue
			# 石板上不長草（縫裡可以，所以只擋石板本體 + 3 cm）
			if _on_slab(p, 0.03):
				continue
			var d_court := maxf(absf(x) - COURT_W * 0.5,
				maxf(Z_COURT_N - z, z - Z_COURT_S))
			var w := 0.0
			if _in_court(p):
				# §6 CLEAN CENTER → SEMI-MAINTAINED EDGE
				var dx := absf(x) / (COURT_W * 0.5)
				var dz := absf(z - (Z_COURT_N + Z_COURT_S) * 0.5) / (COURT_D * 0.5)
				var edge := smoothstep(0.55, 1.0, maxf(dx, dz))
				w = lerpf(w_core, w_edge, edge)
			elif d_court < 20.0:
				w = w_edge
			else:
				w = w_out
			# §29 踩踏：主軸高流量處不長草
			if _axis_clear(p, -2.0):
				w *= 0.12
			# 參道邊緣帶：固定低機率，讓密度可量（目標草侵入 10–20%）
			if approach_edge:
				w = 0.045
			if lib.rand() > w:
				continue
			var variant: String = vars[int(lib.rand() * vars.size()) % vars.size()]
			var path := NAT + variant + ".gltf"
			var ps := load(path) as PackedScene
			if ps == null:
				continue
			var box := _aabb_of(ps)
			# ⚠ 最大水平邊，不是高度
			var s := lib.rr(sr[0], sr[1]) / maxf(maxf(box.size.x, box.size.z), 0.05)
			var inst := ps.instantiate() as Node3D
			inst.position = Vector3(x, height_at(x, z) - box.position.y * s - 0.02, z)
			inst.rotation.y = lib.rand() * TAU
			inst.scale = Vector3(s, s * lib.rr(0.9, 1.15), s)
			for mn in _mesh_nodes(inst):
				(mn as GeometryInstance3D).cast_shadow = \
					GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lib.add(sub, inst, "%s_%04d" % [variant, made])
			if approach_edge:
				_edge_grass_log.append([p, lib.rr(sr[0], sr[1]) * 0.5])
			made += 1
		total += made
		print("[SHRINE] 地被 %-4s %5d" % [name, made])
	print("[SHRINE] 地表植被共 %d 件" % total)
	# ── 參道邊緣帶專屬撒種 ──
	# 全域亂數取樣落在 0.55 m 寬的邊緣帶機率太低（實測只有 4 叢），
	# 直接沿帶內獨立撒：每 0.5 m 一格、每格 22% 機率放一叢矮草／苜蓿。
	var eg := lib.add(g, Node3D.new(), "參道邊緣草") as Node3D
	var eg_n := 0
	for side in [-1.0, 1.0]:
		var sd: float = side
		var z := Z_COURT_S + 10.0
		while z <= Z_TORII + 3.0:
			if lib.rand() < 0.70:
				var x: float = lib.rr(PAVE_HW * 0.6 + 0.05, PAVE_HW + 0.35) * sd
				var p := Vector2(x, z + lib.rr(-0.2, 0.2))
				if not _on_slab(p, 0.03):
					var variant: String = ["Grass_Common_Short", "Grass_Wispy_Short", "Clover_1", "Clover_2"][int(lib.rand() * 4) % 4]
					var ps := load(NAT + variant + ".gltf") as PackedScene
					var box := _aabb_of(ps)
					var target := lib.rr(0.28, 0.5)
					var s := target / maxf(maxf(box.size.x, box.size.z), 0.05)
					var inst := ps.instantiate() as Node3D
					inst.position = Vector3(p.x, height_at(p.x, p.y) - box.position.y * s - 0.02, p.y)
					inst.rotation.y = lib.rand() * TAU
					inst.scale = Vector3(s, s * lib.rr(0.9, 1.1), s)
					for mn in _mesh_nodes(inst):
						(mn as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					lib.add(eg, inst, "%s_%04d" % [variant, eg_n])
					_edge_grass_log.append([p, target * 0.5])
					eg_n += 1
			z += 0.5
	# 參道邊緣帶草侵入（使用者規格 10–20%）：邊緣帶 0.85–1.4 m × 兩側，
	# 量取樣點被草叢水平投影蓋住的比例。
	var hit := 0
	var n := 0
	var step := 0.1
	for side in [-1.0, 1.0]:
		var x := PAVE_HW * 0.6
		while x <= PAVE_HW + 0.4:
			var z := Z_COURT_S + 10.0
			while z <= Z_TORII + 3.0:
				n += 1
				var p := Vector2(x * side, z)
				for e in _edge_grass_log:
					if p.distance_to(e[0]) < float(e[1]):
						hit += 1
						break
				z += step
			x += step
	var gp := 100.0 * float(hit) / maxf(float(n), 1.0)
	var gok := gp >= EDGE_GRASS[0] and gp <= EDGE_GRASS[1]
	print("[SHRINE] 參道邊緣草侵入 %.1f%%（%d 叢，規格 10-20%%）%s" % [gp, _edge_grass_log.size(), "✓" if gok else "✗"])
	if not gok:
		push_warning("參道邊緣草侵入 %.1f%% 超出 10-20%%" % gp)


## §13 主軸視線自檢：沿中軸取樣，看有沒有樹冠蓋住。
## 獸道的教訓——靠眼睛看截圖太慢也不可靠，產生器自己報告。
func _audit_sightline() -> void:
	var blocked := 0
	var worst := INF
	var worst_z := 0.0
	var n := 60
	for i in n:
		var z := lerpf(Z_ENTRY, Z_HAIDEN, float(i) / float(n - 1))
		var p := Vector2(0.0, z)
		for e in _tree_log:
			var d: float = p.distance_to(e[0]) - float(e[1])
			if d < worst:
				worst = d
				worst_z = z
			if d < 0.0:
				blocked += 1
				break
	print("[SHRINE] 主軸視線自檢：%d/%d 取樣被樹冠覆蓋，最窄餘裕 %.2f m @ z=%.1f"
		% [blocked, n, worst, worst_z])
	if blocked > 0:
		push_error("§13 主軸視線 Torii→Courtyard→Haiden 被樹冠擋住 %d 處" % blocked)
	_audit_canopy()


## §8「建築不能完全被樹冠包死」、境內主要觀看方向 sky visibility 25–45%。
## 天空可見度要靠渲染才量得準；這裡量一個可計算的代理指標：
## 境內平面上有多少比例的取樣點被樹冠的水平投影蓋住。
## 覆蓋率高 = 抬頭全是葉子。目標保守設在 ≤ 35%。
func _audit_canopy() -> void:
	var covered := 0
	var n := 0
	var step := 1.5
	var x := -COURT_W * 0.5
	while x <= COURT_W * 0.5:
		var z := Z_COURT_N
		while z <= Z_COURT_S:
			var p := Vector2(x, z)
			n += 1
			for e in _tree_log:
				if p.distance_to(e[0]) < float(e[1]):
					covered += 1
					break
			z += step
		x += step
	var pct := 100.0 * float(covered) / maxf(float(n), 1.0)
	print("[SHRINE] 境內樹冠覆蓋率 %.1f%%（%d/%d 取樣，§8 目標 ≤35%%）" % [pct, covered, n])
	if pct > 35.0:
		push_warning("§8 境內樹冠覆蓋 %.1f%% 過高，天空可見度會低於 25-45%% 下限" % pct)
	_audit_tris()


## 面數預算自檢。GTX 1070 上 slice 的實測：4400 萬面時街景 43 fps、
## 俯瞰 31，其中陰影就佔 3000 萬。神社圖小很多，但全部改用 Meshy 樹
## （11-14k tris/棵，是 Quaternius 的 2.5 倍）之後值得每次跑完就報一次。
func _audit_tris() -> void:
	var per := {}
	var total := 0
	for m in _mesh_nodes(lib.root):
		var mi := m as MeshInstance3D
		var t := 0
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			t += (idx.size() if idx.size() > 0
				else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		total += t
		# 歸給最近的「有名字的」祖先分組
		var cur: Node = mi
		var tag := "其他"
		while cur != null and cur != lib.root:
			var pn := cur.get_parent()
			if pn == lib.root:
				tag = cur.name
				break
			cur = pn
		per[tag] = per.get(tag, 0) + t
	var keys := per.keys()
	keys.sort_custom(func(a, b): return per[a] > per[b])
	for k in keys:
		print("[SHRINE] 面數 %-12s %10d（%.1f%%）"
			% [k, per[k], 100.0 * float(per[k]) / maxf(float(total), 1.0)])
	print("[SHRINE] 場景總三角面 %d" % total)


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
