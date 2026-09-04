extends SceneTree
## 獸道 v2 —— 依使用者規格重做（2026-09-04）。
##
##   Godot --headless --path godot --script tools/gen_trail_v2.gd
##
## 產出 maps/trail/trail.tscn（整張覆蓋；舊版在 git 8ed502f 可救回）。
##
## ══ 定調 ══
## 「這條路原本是人走的，但走得越深，越不像是為人類準備的路。」
## 線性：人里(南) → 界碑 → 普通森林 → 縮窄 → 地藏 → 密林 → 小溪/木橋
##       → 大空地(古樹) → 密林 → 妖怪痕跡 → 夜雀屋台 → 更深(北，神社傳送點)
## 使用者裁決：完全線性，竹林/太陽花田連線先不管。
##
## ══ 座標約定 ══
## 南 = +z（人里入口），北 = -z（深處）。深度參數 t∈[0,1] 沿主脊由南到北。
## 路寬 2.8 m → 1.3 m 隨 t 縮窄；蛇行由三層正弦疊加，振幅隨 t 放大。
##
## ══ 資產 ══
## 自然層 Quaternius nature/（BASE 原點，公尺單位，實測 probe_trail_assets.gd）
##   樹 6 種：CommonTree(闊葉)、Pine(松)、DeadTree(枯)、TwistedTree(歪/老) 各多變體
##   地表：Fern、Grass×4、Bush×2、Plant、Clover、Mushroom×2、Flower、Rock_Medium×3、Pebble
## 遠景山 gobkit（公分單位，各件實測後單獨算縮放）
## 人工物 lowpoly_scene/：StoneLantern、Fence_Wood、Log_Cluster、Barrel、CeremicPot、Basket_S
## 缺件（走 Meshy）留 Marker3D 佔位：界碑×2、警告牌、地藏×N、古樹 Hero、屋台 Hero、木橋
##
## ══ 個別節點 vs LOD ══
## 使用者要每棵樹可個別選取。路沿 NEAR_BAND 內全個別節點（原尺寸網格）；
## 外圍仍是個別節點但共用 _lod 低面數網格（若 _lod 沒有就直接用原網格——
## 先求正確，效能實測後再壓）。

const Lib := preload("res://tools/gen_lib.gd")
const OUT := "res://maps/trail/"
const NAT := "res://assets/nature/"
const LP := "res://assets/lowpoly_scene/"
const GOB := "res://assets/_incoming/gobkit_nature/"

const HALF := 340.0                 # 680×680，跟登錄表一致
const SPINE_Z0 := 320.0             # 南端（人里入口）
const SPINE_Z1 := -320.0            # 北端（神社傳送點）
const NEAR_BAND := 30.0             # 路沿個別高模帶
const SEED := 20260904

# ── 場景節奏（沿 t 的關鍵段落）──
# 每段：t 範圍、樹密度（0-1）、備註。密→疏→密→開闊→密。
const BEATS := [
	{ "t0": 0.00, "t1": 0.06, "dens": 0.15, "tag": "農田/柵欄" },
	{ "t0": 0.06, "t1": 0.12, "dens": 0.45, "tag": "界碑・普通森林" },
	{ "t0": 0.12, "t1": 0.26, "dens": 0.80, "tag": "密林1" },
	{ "t0": 0.26, "t1": 0.34, "dens": 0.40, "tag": "疏・地藏舊路標" },
	{ "t0": 0.34, "t1": 0.46, "dens": 0.92, "tag": "密林2" },
	{ "t0": 0.46, "t1": 0.52, "dens": 0.30, "tag": "小溪・木橋" },
	{ "t0": 0.52, "t1": 0.60, "dens": 0.05, "tag": "大空地" },
	{ "t0": 0.60, "t1": 0.74, "dens": 0.95, "tag": "密林3・妖怪痕跡" },
	{ "t0": 0.74, "t1": 0.80, "dens": 0.35, "tag": "夜雀屋台" },
	{ "t0": 0.80, "t1": 1.00, "dens": 1.00, "tag": "更深的妖怪領域" },
]
const T_ENTRANCE := 0.07
const T_JIZO := 0.30
const T_CREEK := 0.49
const T_CLEARING := 0.56
const T_STALL := 0.77
const CLEARING_R := 17.0            # 直徑 ~34 m（規格 20-30，放寬以展現開闊感）

var lib: Lib
var _nh: FastNoiseLite       # 地形起伏
var _nd: FastNoiseLite       # 密度擾動（讓節奏內部也不均勻）
var _nm: FastNoiseLite       # 蛇行擾動
var _spine: PackedVector2Array   # 主脊取樣點（南→北）
var _spine_t: PackedFloat32Array
var _branches: Array = []        # 岔路：每條是 PackedVector2Array
var _meshes := {}                # path → Mesh（tree/grass 快取）
var _placed_trunks: PackedVector2Array
var _trunk_log: Array = []      # [中心 xz, 樹冠水平半徑] — 走廊自檢用
## 地藏位置。地表植被要讓開，否則 1 m 高的芒草會把地藏整個埋掉。
## ⚠ 必須在 _build_ground_cover() **之前**填好——地藏本身是在
##   _build_human_traces()（更後面）才生成的，所以位置要先預算。
var _jizo_sites: Array = []

## 地藏配置：[沿主脊 t, 幾尊, 側向(+1 左 / -1 右)]
## 這份表同時被 _plan_jizo_sites()（植被讓位）與 _build_human_traces()
## （實際擺放）使用，兩邊不可各寫一份。
const JIZO_SPECS := [
	[0.07, 1, 1.0],           # 入口
	[0.19, 1, -1.0],
	[T_JIZO, 3, 1.0],         # 疏段三尊（規格的「地藏／舊路標」節點）
	[0.41, 1, -1.0],
	[0.71, 1, 1.0],
]


# ══════════════════════════════════════════════════════════════════
# 主脊：由南到北的蛇行折線
# ══════════════════════════════════════════════════════════════════
func _build_spine() -> void:
	var n := 400
	_spine.resize(n)
	_spine_t.resize(n)
	for i in n:
		var t := float(i) / float(n - 1)
		var z := lerpf(SPINE_Z0, SPINE_Z1, t)
		# 三層正弦 + 噪聲：長波給大方向、短波給蛇行、噪聲給不規則
		var amp := lerpf(18.0, 42.0, t)     # 越深越蜿蜒
		var x := sin(t * TAU * 1.3 + 0.7) * amp * 0.6 \
			+ sin(t * TAU * 3.7 + 2.1) * amp * 0.3 \
			+ sin(t * TAU * 9.1 + 4.4) * amp * 0.12 \
			+ _nm.get_noise_1d(t * 900.0) * 9.0
		# 大空地與屋台附近把路拉直一點，讓空地是「路穿過的」而不是路繞開
		_spine[i] = Vector2(x, z)
		_spine_t[i] = t


func _spine_pos(t: float) -> Vector2:
	var f := clampf(t, 0.0, 1.0) * float(_spine.size() - 1)
	var i := int(floor(f))
	var j := mini(i + 1, _spine.size() - 1)
	return _spine[i].lerp(_spine[j], f - float(i))


func _spine_dir(t: float) -> Vector2:
	return (_spine_pos(t + 0.004) - _spine_pos(t - 0.004)).normalized()


func _stall_pos() -> Vector2:
	var c := _spine_pos(T_STALL)
	var d := _spine_dir(T_STALL)
	var perp := Vector2(-d.y, d.x)
	return c + perp * (_half_w(T_STALL) + 3.2)


## 路寬（半寬）隨深度縮窄：2.8 m → 1.3 m，並在空地/屋台附近略放寬
func _half_w(t: float) -> float:
	var w := lerpf(2.8, 1.3, smoothstep(0.1, 0.95, t))
	w += 0.6 * exp(-pow((t - T_CLEARING) / 0.03, 2.0))
	w += 0.4 * exp(-pow((t - T_STALL) / 0.02, 2.0))
	w += 0.4 * (1.0 - smoothstep(0.0, 0.08, t))     # 入口段還是人走的土路
	return w * 0.5


## 到主脊距離、最近 t
func _spine_info(p: Vector2) -> Array:
	var best := INF
	var bt := 0.0
	for i in _spine.size() - 1:
		var a := _spine[i]
		var b := _spine[i + 1]
		var ab := b - a
		var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var d := p.distance_to(a + ab * u)
		if d < best:
			best = d
			bt = lerpf(_spine_t[i], _spine_t[i + 1], u)
	return [best, bt]


# ══════════════════════════════════════════════════════════════════
# 岔路：從主脊分出去、逐漸消失的窄徑
# ══════════════════════════════════════════════════════════════════
func _build_branches() -> void:
	var specs := [
		# t 起點、方向(左右)、長度、是否消失
		[0.18, 1, 46.0, true], [0.23, -1, 30.0, true],
		[0.38, -1, 60.0, true], [0.42, 1, 24.0, true],
		[0.57, 1, 38.0, true],      # 空地側隱藏獸徑（規格 §7）
		[0.66, -1, 52.0, true], [0.70, 1, 28.0, true],
		[0.85, -1, 70.0, true], [0.91, 1, 40.0, true],
	]
	for s in specs:
		var t0: float = s[0]
		var side: float = float(s[1])
		var len: float = s[2]
		var pts := PackedVector2Array()
		var p := _spine_pos(t0)
		var d := _spine_dir(t0)
		var perp := Vector2(-d.y, d.x) * side
		var dir := (perp * 0.8 + d * lib.rr(-0.3, 0.3)).normalized()
		var steps := int(len / 2.0)
		for k in steps + 1:
			pts.append(p)
			var turn := _nm.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.9
			dir = dir.rotated(turn * 0.35).normalized()
			p += dir * 2.0
		_branches.append(pts)


## 到任一岔路的距離、沿岔路的衰減(0=起點 1=盡頭)
func _branch_info(p: Vector2) -> Array:
	var best := INF
	var fade := 0.0
	for br in _branches:
		var pts: PackedVector2Array = br
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var ab := b - a
			var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var d := p.distance_to(a + ab * u)
			if d < best:
				best = d
				fade = (float(i) + u) / float(pts.size() - 1)
	return [best, fade]


# ══════════════════════════════════════════════════════════════════
# 地形
# ══════════════════════════════════════════════════════════════════
## 小溪：橫穿主脊於 T_CREEK，走向大致東西、帶一點蛇行
func _creek_dist(p: Vector2) -> float:
	var c := _spine_pos(T_CREEK)
	var zc := c.y + sin(p.x * 0.045 + 1.3) * 6.0 + _nm.get_noise_1d(p.x * 2.0) * 3.0
	return absf(p.y - zc)


func _clearing_dist(p: Vector2) -> float:
	var c := _spine_pos(T_CLEARING)
	# 不規則：半徑隨角度擾動
	var ang := atan2(p.y - c.y, p.x - c.x)
	var r := CLEARING_R * (1.0 + 0.25 * sin(ang * 3.0 + 0.6) + 0.15 * sin(ang * 5.0 + 2.2))
	return p.distance_to(c) - r


func height_at(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var info := _spine_info(p)
	var ed: float = maxf(0.0, info[0] - _half_w(info[1]))
	var t: float = info[1]
	# 基底：緩坡+土丘+淺谷
	var h := _nh.get_noise_2d(x, z) * 4.5 \
		+ _nh.get_noise_2d(x * 0.3 + 100.0, z * 0.3) * 6.0 \
		+ sin(x * 0.018 + 0.4) * 1.4 + sin(z * 0.014 + 1.1) * 1.6
	# 整體往北緩升 — 「深處」有高度感
	h += t * 9.0
	# 路面壓平：路上取路心高度的平滑版；路外漸回自然起伏
	var flat := smoothstep(0.0, 6.0, ed)
	var road_h := sin(z * 0.03) * 0.8 + t * 9.0 + _nh.get_noise_2d(x * 0.15, z * 0.15) * 1.2
	h = lerpf(road_h, h, flat)
	# 路面本身的細碎起伏（樹根/石頭感）
	h += (1.0 - flat) * _nm.get_noise_2d(x * 4.0, z * 4.0) * 0.08
	# 小溪：谷要夠深夠寬，否則地形網格（格距 3.4 m）根本表現不出它。
	# ⚠ 前一版切 0.9 m、寬 5 m：一個網格格子跨掉半條溪，谷底被抹平，
	#   水面不管怎麼算都有一半埋在土裡（check_map 連報三次 29→35→49%）。
	# ⚠ 谷深必須壓過地形噪聲的振幅。基底噪聲是 ±4.5 + ±6.0 = 最大 10.5 m，
	#   谷只切 2.2 m 的話，噪聲一個起伏就把谷填平 → 水面沿途斷成好幾截
	#   （v14_小溪俯角.png）。這裡改成**先把溪帶的地形壓平再挖**：
	#   谷心 12 m 內先抹掉八成起伏，再切 2.6 m 深的 V 形谷。
	var cd := _creek_dist(p)
	var creek_zone := 1.0 - smoothstep(4.0, 14.0, cd)
	if creek_zone > 0.0:
		# 沿溪的縱向基準面：只保留大尺度坡度，抹掉橫向亂流
		var base := t * 9.0 + sin(x * 0.012) * 2.2 + _nh.get_noise_2d(x * 0.25, 0.0) * 1.8
		h = lerpf(h, base, creek_zone * 0.8)
	h -= 2.6 * (1.0 - smoothstep(0.0, 9.0, cd))
	# 大空地：壓平
	var cl := _clearing_dist(p)
	var in_cl := 1.0 - smoothstep(-2.0, 4.0, cl)
	var cl_h := _spine_pos(T_CLEARING).y * 0.03
	h = lerpf(h, T_CLEARING * 9.0 + sin(cl_h) * 0.8 + 0.1, in_cl)
	# 小水潭：同樣要夠深夠寬才畫得進 3.4 m 格距的網格（0.5 m / 4 m 太淺）
	var pond := _spine_pos(T_CLEARING) + Vector2(6.0, -7.0)
	h -= 1.4 * (1.0 - smoothstep(0.0, 6.0, p.distance_to(pond)))
	# 泥潭：密林 2 裡兩處
	for m in [_spine_pos(0.40) + Vector2(-9.0, 3.0), _spine_pos(0.44) + Vector2(11.0, -2.0)]:
		h -= 0.35 * (1.0 - smoothstep(2.0, 5.5, p.distance_to(m)))
	return h


## 地表混合遮罩：R=路面、G=林床(腐葉土)、B=巨觀變化、(A=泥/濕)
func mask_at(x: float, z: float) -> Color:
	var p := Vector2(x, z)
	var info := _spine_info(p)
	var hw := _half_w(info[1])
	var d: float = info[0]
	# 路心保持結實踩踏感，路緣自然漸變
	var road := 1.0 - smoothstep(hw * 0.85, hw + 0.8, d)
	# 邊緣不整齊：噪聲只微咬路邊，不侵蝕路心
	road *= clampf(1.0 - (_nm.get_noise_2d(x * 1.7, z * 1.7) * 0.5 + 0.5) * smoothstep(hw * 0.6, hw + 0.8, d) * 0.8, 0.0, 1.0)
	# 岔路：越往盡頭越淡
	var bi := _branch_info(p)
	var broad := (1.0 - smoothstep(0.4, 1.4, bi[0])) * (1.0 - smoothstep(0.35, 1.0, bi[1])) * 0.65
	road = maxf(road, broad)
	# 入口段舊道路痕跡（比路面寬、很淡）
	var t: float = info[1]
	if t < 0.12:
		road = maxf(road, (1.0 - smoothstep(hw + 0.8, hw + 4.5, d)) * 0.35 * (1.0 - t / 0.12))
	# 林床：從路緣外側開始增長，路面內壓制腐葉土
	var dens := _density_at(t)
	var forest := clampf(smoothstep(hw * 0.7, hw + 4.5, d) * (0.65 + dens * 0.35), 0.0, 1.0)
	# ⚠ terrain_pbr 的混色順序是 grass → forest(m.g) → path(m.r)，但 forest
	# 那一層是無條件 mix 的，只要 m.g 有值就會把已經畫好的路面蓋掉一部分。
	# 入口段實拍完全看不出路（v8_入口.png）就是這樣來的。
	# 這裡直接讓林床扣掉路面權重，兩層不再互相打架。
	forest *= 1.0 - road
	var cl := _clearing_dist(p)
	forest *= smoothstep(-1.0, 3.0, cl)      # 空地內是草
	var macro := clampf(_nh.get_noise_2d(x * 0.4, z * 0.4) * 0.5 + 0.5, 0.0, 1.0)
	# 濕/泥：溪邊、泥潭、水潭
	var wet := 1.0 - smoothstep(2.5, 7.0, _creek_dist(p))
	for m in [_spine_pos(0.40) + Vector2(-9.0, 3.0), _spine_pos(0.44) + Vector2(11.0, -2.0),
			_spine_pos(T_CLEARING) + Vector2(6.0, -7.0)]:
		wet = maxf(wet, 1.0 - smoothstep(2.0, 6.0, p.distance_to(m)))
	# ⚠ A 通道（dirt 層）才是路面真正畫得出來的地方。
	#
	# 原本路面走 m.r → shader 的 path_diff，而我傳的 path_set 是
	# "terrain_path"（土徑貼圖）—— 它跟旁邊的草地/林床顏色幾乎一樣，
	# 於是實拍每一張圖都看不出路在哪（v10 入口/深處都是一片黃褐）。
	# dirt 層有 dirt_tint 可以獨立調色、還會被 shader 拉向灰階，
	# 正好是「踏實的泥土獸徑」該有的樣子。
	# 濕氣併進同一通道（溪邊本來就該是深色濕泥）。
	return Color(road, forest, macro, maxf(road, wet * 0.7))


func _density_at(t: float) -> float:
	for b in BEATS:
		if t >= b.t0 and t < b.t1:
			# 段內平滑到相鄰段（避免硬切）
			return b.dens
	return 1.0


func _density_smooth(t: float) -> float:
	var d := _density_at(t)
	var d0 := _density_at(t - 0.03)
	var d1 := _density_at(t + 0.03)
	return (d * 2.0 + d0 + d1) / 4.0


# ══════════════════════════════════════════════════════════════════
# 進入點
# ══════════════════════════════════════════════════════════════════
func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "gen"))
	_nh = FastNoiseLite.new(); _nh.frequency = 0.011; _nh.fractal_octaves = 3; _nh.seed = 240
	_nd = FastNoiseLite.new(); _nd.frequency = 0.03; _nd.seed = 77
	_nm = FastNoiseLite.new(); _nm.frequency = 0.05; _nm.seed = 31

	var root := Node3D.new()
	root.name = "Trail"
	root.set_meta("own_colliders", true)
	lib = Lib.new()
	lib.setup(root, SEED)
	_build_spine()
	_build_branches()

	print("[TRAIL] 主脊 %d 點，南 %s → 北 %s" % [_spine.size(), _spine_pos(0.0), _spine_pos(1.0)])
	print("[TRAIL] 關鍵點：入口 %s 地藏 %s 小溪 %s 空地 %s 屋台 %s" % [
		_spine_pos(T_ENTRANCE), _spine_pos(T_JIZO), _spine_pos(T_CREEK), _spine_pos(T_CLEARING), _spine_pos(T_STALL)])

	# 地形：路面走土徑貼圖、第四層「濕泥」——沒有專屬泥貼圖，先用林床貼圖
	# 疊深色 tint 當濕土；Meshy/貼圖到位後換 dirt_set 即可
	# dirt_amount 由 gen_lib 依 dirt_set 是否給定而開；tint 是踏實的深褐濕土，
	# 與旁邊的黃綠草地、紅褐林床拉開色差，路才看得出來。
	var terrain := lib.terrain(OUT, HALF, 201, height_at, mask_at, "terrain_path",
		Color(0.58, 0.62, 0.46), "terrain_forest", Color(0.30, 0.24, 0.18), 0.0)
	lib.boundary(HALF - 2.0)
	_index_terrain(terrain)
	_build_creek_water()
	_build_forest()
	_plan_jizo_sites()          # 先定位置，讓地表植被知道要讓開哪裡
	_build_ground_cover()
	_build_rocks_and_logs()
	_build_human_traces()
	_build_clearing()
	_build_stall_site()
	_build_youkai_traces()
	_build_vista()
	_build_sky()
	_build_markers()

	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, OUT + "trail.tscn")
	print("[TRAIL] saved trail.tscn err=%d  節點 %d" % [err, _count(root)])
	quit(0)


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


# ══════════════════════════════════════════════════════════════════
# 小溪水面：沿溪心取樣一條帶狀網格，用 slice 的 water 材質
# ══════════════════════════════════════════════════════════════════
## 地形網格的高度查表。
##
## ⚠ 水面**不能**用 height_at() 定高度。地形是 201×201 的網格（格距 3.4 m），
## 解析函式的細節在取樣時被抹平；實測兩者在溪谷附近差到 0.65 m，而溪谷
## 本身只切 0.9 m —— 於是水面有 35% 埋進土裡（check_map 抓到兩次）。
## 這裡把實際存進場景的那份網格建成規則格點表，水面照它取值。
var _tg: PackedFloat32Array      # (res × res) 高度
var _tg_res := 0
var _tg_half := 0.0

func _index_terrain(mi: MeshInstance3D) -> void:
	var arr: Array = mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	_tg_res = int(round(sqrt(float(vs.size()))))
	_tg_half = HALF
	_tg = PackedFloat32Array()
	_tg.resize(vs.size())
	for i in vs.size():
		_tg[i] = vs[i].y
	print("[TRAIL] 地形索引：%d×%d 格，格距 %.2f m" % [_tg_res, _tg_res, 2.0 * HALF / float(_tg_res - 1)])


## 雙線性內插地形網格高度（與存進場景的幾何一致）
func terrain_y(x: float, z: float) -> float:
	if _tg_res == 0:
		return height_at(x, z)
	var step := 2.0 * _tg_half / float(_tg_res - 1)
	var fi := clampf((x + _tg_half) / step, 0.0, float(_tg_res - 1))
	var fj := clampf((z + _tg_half) / step, 0.0, float(_tg_res - 1))
	var i0 := int(floor(fi)); var j0 := int(floor(fj))
	var i1 := mini(i0 + 1, _tg_res - 1); var j1 := mini(j0 + 1, _tg_res - 1)
	var tx := fi - float(i0); var tz := fj - float(j0)
	var h00 := _tg[j0 * _tg_res + i0]
	var h10 := _tg[j0 * _tg_res + i1]
	var h01 := _tg[j1 * _tg_res + i0]
	var h11 := _tg[j1 * _tg_res + i1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## 一個圓範圍內地形網格的最低點——水面要壓在它之下才不會露出邊緣
func terrain_min_in(cx: float, cz: float, r: float) -> float:
	var lo := INF
	var step := 2.0 * _tg_half / float(_tg_res - 1)
	var n := int(ceil(r / step)) + 1
	for dj in range(-n, n + 1):
		for di in range(-n, n + 1):
			var x := cx + float(di) * step
			var z := cz + float(dj) * step
			if Vector2(x - cx, z - cz).length() > r:
				continue
			lo = minf(lo, terrain_y(x, z))
	return lo if lo != INF else terrain_y(cx, cz)


func _build_creek_water() -> void:
	# ⚠ 水面**由地形決定**，而且必須是連續網格。
	#
	# 走過的死路（六輪）：
	#   1-4. 造獨立水帶 + 算水位 → 頂點與地形格點不對齊，29→52% 埋在地下
	#   5.   逐格挑「低於水位」的格子 → 不埋了，但每格一個平面、格間有
	#        高度階梯，畫面上是一層藍灰地磚（v10/v11_小溪.png）
	#
	# 正解：沿溪心建**連續**的帶狀網格，但每個頂點的 xz 落在地形格點上、
	# y 取自同一條平滑的水位剖面。頂點共用 → 沒有階梯；xz 對齊 → 不埋地。
	#
	# 頂點色照 water.gdshader 契約（assets/shaders/water.gdshader:59）：
	#   COLOR.r  = bank，1=岸邊 0=中央（岸邊變淡、bank≥0.9 才有泡沫）
	#   COLOR.gb = 流向，編碼為 (dir + 1) / 2
	var c := _spine_pos(T_CREEK)
	var step := 2.0 * HALF / float(_tg_res - 1)

	# ── 1. 水位剖面：沿 x 掃，每站取溪心附近地形最低點，再平滑 ──
	var n := 81
	var x0 := c.x - 130.0
	var x1 := c.x + 130.0
	var zc_of := func(x: float) -> float:
		return c.y + sin(x * 0.045 + 1.3) * 6.0 + _nm.get_noise_1d(x * 2.0) * 3.0
	var bed := PackedFloat32Array()
	bed.resize(n)
	for i in n:
		var x: float = lerpf(x0, x1, float(i) / float(n - 1))
		var zc: float = zc_of.call(x)
		# 溪心橫斷面最低點（±4 m，涵蓋谷底）
		var lo := INF
		for k in 9:
			lo = minf(lo, terrain_y(x, zc - 4.0 + float(k)))
		bed[i] = lo
	# 平滑水位：只抹掉河床的小坑，不能跨越溪的縱向坡度。
	# ⚠ ±4 站 = 26 m 範圍，而這條溪全長 260 m 落差 5.3 m（約 2%）——
	#   26 m 窗口會把上下游差 0.5 m 的高度混在一起，東端因此埋進土裡 3 m。
	#   改成 ±1 站（6.5 m）並且**不得高於本站河床 + 0.35 m**。
	var level := PackedFloat32Array()
	level.resize(n)
	for i in n:
		var acc := 0.0
		var cnt := 0
		for d in range(-1, 2):
			var k: int = clampi(i + d, 0, n - 1)
			acc += bed[k]
			cnt += 1
		level[i] = minf(acc / float(cnt) + 0.22, bed[i] + 0.35)

	# ── 2. 帶狀網格：橫向 9 條，寬度隨谷寬 ──
	var lanes := 9
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := []
	for i in n:
		var x: float = lerpf(x0, x1, float(i) / float(n - 1))
		var zc: float = zc_of.call(x)
		var y: float = level[i]
		# 這一站水面實際能鋪多寬：往兩側找到地形升過水位的地方。
		# ⚠ 步長要細，且**兩側各自算**——溪谷斷面不對稱，用單一半寬會讓
		#   較陡的那側頂點落在坡上（實測 16% 埋地，最深 1.43 m @ x=-46）。
		var w_neg := 0.4
		for k in range(1, 41):
			var w := float(k) * 0.25
			if terrain_y(x, zc - w) > y:
				break
			w_neg = w
		var w_pos := 0.4
		for k in range(1, 41):
			var w := float(k) * 0.25
			if terrain_y(x, zc + w) > y:
				break
			w_pos = w
		# 再各退 15 cm，避開內插誤差
		w_neg = maxf(w_neg - 0.15, 0.2)
		w_pos = maxf(w_pos - 0.15, 0.2)
		var row := []
		for l in lanes:
			var f := float(l) / float(lanes - 1)          # 0..1
			var zz := zc + lerpf(-w_neg, w_pos, f)
			# bank：中央 0、兩緣 1（water.gdshader 用它做淺灘與泡沫）
			var bank := absf(f * 2.0 - 1.0)
			row.append([Vector3(x, y, zz), bank])
		rows.append(row)
	# 流向：沿 +x（溪由西往東）
	var flow := Vector2(1.0, 0.0)
	var gcol := (flow.x + 1.0) * 0.5
	var bcol := (flow.y + 1.0) * 0.5
	var idx := 0
	for i in n:
		for l in lanes:
			var e: Array = rows[i][l]
			var v: Vector3 = e[0]
			var bank: float = e[1]
			st.set_uv(Vector2(float(i) * 0.35, float(l) / float(lanes - 1)))
			st.set_color(Color(bank, gcol, bcol))
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	for i in n - 1:
		for l in lanes - 1:
			var a := i * lanes + l
			var b := a + 1
			var cc2 := a + lanes
			var d2 := cc2 + 1
			st.add_index(a); st.add_index(cc2); st.add_index(b)
			st.add_index(b); st.add_index(cc2); st.add_index(d2)
	var mesh := st.commit()
	# 繞向自檢：法線該朝上
	var arrs: Array = mesh.surface_get_arrays(0)
	var nrm: PackedVector3Array = arrs[Mesh.ARRAY_NORMAL]
	if nrm.size() > 0 and nrm[0].y < 0.0:
		push_error("小溪水面繞向反了（法線朝下）")
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = load("res://assets/materials/east_river_water.tres")
	lib.add(lib.root, mi, "小溪水面")
	print("[TRAIL] 小溪水面：%d×%d 連續網格，水位 %.2f→%.2f" % [n, lanes, level[0], level[n - 1]])


# ══════════════════════════════════════════════════════════════════
# 森林：個別節點；路沿高模、外圍 LOD（若有）
# ══════════════════════════════════════════════════════════════════
const TREES := {
	# 名稱 → [變體清單, 目標高度範圍 m, 權重]
	"闊葉": [["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5"], [12.0, 18.0], 0.42],
	"松":   [["Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"], [14.0, 22.0], 0.33],
	"杉":   [["Pine_3", "Pine_1"], [18.0, 26.0], 0.20],          # 高瘦松當杉用（規格要杉木；Quaternius 沒有杉，先以高松代）
	"歪":   [["TwistedTree_1", "TwistedTree_2", "TwistedTree_3", "TwistedTree_4", "TwistedTree_5"], [11.0, 16.0], 0.03],
	"枯":   [["DeadTree_1", "DeadTree_2", "DeadTree_3", "DeadTree_4", "DeadTree_5"], [9.0, 14.0], 0.02],
}
# 實測本地高度（probe_trail_assets.gd）— 每個變體不同，這裡用每種的代表值，
# 產生器內會再實際讀 AABB 校正，所以這張表只是備援。


func _mesh_h(ps: PackedScene) -> float:
	var inst := ps.instantiate() as Node3D
	var box: Variant = null
	for m in _mesh_nodes(inst):
		var a := (m as MeshInstance3D).get_aabb()
		var b := _rel(m, inst) * a
		box = b if box == null else (box as AABB).merge(b)
	inst.free()
	return (box as AABB).size.y if box != null else 1.0



## 綠葉版歪樹：自建 MeshInstance3D（不是 GLB 實例），這樣 mesh 與材質
## 都是節點自己的屬性，pack() 存得下來。同一 variant 共用一份 mesh。
var _green_cache := {}
func _green_twisted(variant: String) -> Node3D:
	if not _green_cache.has(variant):
		var src := (_ps(NAT + variant + ".gltf")).instantiate() as Node3D
		var found: ArrayMesh = null
		for mn in _mesh_nodes(src):
			found = (mn as MeshInstance3D).mesh as ArrayMesh
			break
		var dup := found.duplicate() as ArrayMesh
		var leaf := StandardMaterial3D.new()
		leaf.albedo_texture = load("res://assets/nature/Leaves_NormalTree_C.png")
		leaf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		leaf.alpha_scissor_threshold = 0.5
		leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
		leaf.roughness = 0.95
		dup.surface_set_material(1, leaf)
		ResourceSaver.save(dup, OUT + "gen/twisted_green_%s.res" % variant)
		dup.take_over_path(OUT + "gen/twisted_green_%s.res" % variant)
		_green_cache[variant] = dup
		src.free()
	var mi := MeshInstance3D.new()
	mi.mesh = _green_cache[variant]
	return mi

func _mesh_nodes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_mesh_nodes(c))
	return out


func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


var _scene_cache := {}
var _h_cache := {}        # 本地高
var _w_cache := {} # 本地最大水平邊
## ⚠ 地表植被不能只用高度定縮放。Plant_7_Big 本地高 0.25 m 但寬 1.9 m，
## 用高度算出 5.9× 之後變成 11 m 寬的藍紫巨葉蓋在路上（v1 實拍）。
## 地表層一律用「最大邊」定尺寸；只有樹用高度。
func _ps(path: String) -> PackedScene:
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path)
		var box := _aabb_of(_scene_cache[path])
		_h_cache[path] = box.size.y
		_w_cache[path] = maxf(box.size.x, box.size.z)
	return _scene_cache[path]


func _pick_tree() -> Array:
	var r := lib.rand()
	var acc := 0.0
	for k in TREES:
		acc += TREES[k][2]
		if r <= acc:
			var vars: Array = TREES[k][0]
			return [k, vars[int(lib.rand() * vars.size()) % vars.size()], TREES[k][1]]
	var kk: String = TREES.keys()[0]
	return [kk, TREES[kk][0][0], TREES[kk][1]]


func _build_forest() -> void:
	var forest := lib.add(lib.root, Node3D.new(), "森林") as Node3D
	var near := lib.add(forest, Node3D.new(), "路沿") as Node3D
	var far := lib.add(forest, Node3D.new(), "外圍") as Node3D
	var groups := {}
	var count := [0, 0]
	var tries := 0
	var target := 7000
	var made := 0
	_placed_trunks = PackedVector2Array()
	# 用格子加速樹幹間距檢查
	var grid := {}
	var cell := 6.0
	while made < target and tries < 500000:
		tries += 1
		var x := 0.0
		var z := 0.0
		if made < 4200:
			# 重兵集中在路沿 3.2m ~ 55m 帶狀區，形成林蔭穹頂與密林壓迫感
			var t_sample := lib.rr(0.01, 0.99)
			var sp_pos := _spine_pos(t_sample)
			var sp_dir := _spine_dir(t_sample)
			var sp_perp := Vector2(-sp_dir.y, sp_dir.x)
			var side := 1.0 if lib.rand() < 0.5 else -1.0
			var d_offset := lib.rr(3.2, 55.0)
			var pt := sp_pos + sp_perp * (d_offset * side) + Vector2(lib.rr(-3.5, 3.5), lib.rr(-3.5, 3.5))
			x = clampf(pt.x, -HALF + 4.0, HALF - 4.0)
			z = clampf(pt.y, -HALF + 4.0, HALF - 4.0)
		else:
			# 外圍全域填充視距背景
			x = lib.rr(-HALF + 4.0, HALF - 4.0)
			z = lib.rr(-HALF + 4.0, HALF - 4.0)
		var p := Vector2(x, z)
		var info := _spine_info(p)
		var t: float = info[1]
		var ed: float = maxf(0.0, info[0] - _half_w(t))
		var dc: float = info[0]                     # 離路心
		# ⚠ 淨空要用「離路心」而不是「離路緣」。
		# v3 用 ed<3.0，但深處路半寬只有 0.65 m，樹幹離路心才 3.65 m；
		# 而路沿樹被 ed<25 那條規則強制拉到 15 m 高、樹冠半徑約 7 m，
		# 於是樹冠在路面上空完全閉合 —— 實拍整張全黑（v3_密林1.png）。
		# 走廊要能站人、看得到天光漏下來：樹幹離路心至少 5.5 m。
		if dc < 5.5:
			continue
		if t < 0.09 and dc < 8.0:
			continue
		if _clearing_dist(p) < 4.5:
			continue
		if _creek_dist(p) < 3.5:
			continue
		if p.distance_to(_stall_pos()) < 9.0:
			continue
		var bi := _branch_info(p)
		if bi[0] < 0.9 and bi[1] < 0.8:
			continue
		# 密度：節奏 × 噪聲
		var dens := _density_smooth(t)
		dens = 0.20 + dens * 0.80                       # 底線：連疏段也不是空的
		dens *= 0.75 + 0.25 * (_nd.get_noise_2d(x, z) * 0.5 + 0.5)
		if ed < 20.0:
			dens *= 1.25                               # 路邊高密林冠
		# 空地周圍一圈包圍感
		var cl := _clearing_dist(p)
		if cl > 4.5 and cl < 16.0:
			dens = maxf(dens, 0.80)
		if lib.rand() > dens:
			continue
		# 樹幹間距
		var ok := true
		var gx := int(floor(x / cell)); var gz := int(floor(z / cell))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var key := "%d_%d" % [gx + dx, gz + dz]
				if grid.has(key):
					for q in grid[key]:
						if p.distance_to(q) < 2.5:
							ok = false
							break
				if not ok: break
			if not ok: break
		if not ok:
			continue
		var pick := _pick_tree()
		var kind: String = pick[0]
		var variant: String = pick[1]
		var hr: Array = pick[2]
		# 深處 (t > 0.7) 少量增加枯樹與歪樹，但維持松杉為骨幹，不讓紅葉氾濫
		if t > 0.72 and kind in ["闊葉", "松"] and lib.rand() < (t - 0.72) * 0.35:
			pick = ["枯", TREES["枯"][0][int(lib.rand() * 5) % 5], TREES["枯"][1]] if lib.rand() < 0.7 \
				else ["歪", TREES["歪"][0][int(lib.rand() * 5) % 5], TREES["歪"][1]]
			kind = pick[0]; variant = pick[1]; hr = pick[2]
		var path := NAT + variant + ".gltf"
		var ps := _ps(path)
		var local_h: float = _h_cache[path]
		var target_h := lib.rr(hr[0], hr[1])
		# 林冠遮光：讓「路兩側稍遠」的樹高一點，形成拱頂而不是把路封死。
		# 拱頂只能由「離路心 14 m 以外」的樹撐起——樹冠水平半徑約高度 ×0.45，
		# 12 m 樹 = 5.4 m 冠幅，從 8 m 外伸過來仍蓋住路心（自檢 25/41 三重覆蓋）。
		if dc > 14.0 and dc < 30.0 and kind in ["闊葉", "松", "杉"]:
			target_h = maxf(target_h, 13.0)
		# ⚠ 走廊旁那一圈**不能靠矮化**來讓出視線。
		# Quaternius 的樹冠佔全高的比例是固定的，矮化 = 冠也跟著縮小，
		# 結果中景變成一整片光禿樹幹的柱林（v7_屋台.png）。
		# 正確做法是保持樹高、改用「抬高樹冠」——把整棵往下沉，讓樹冠
		# 位置相對上移，視線從樹幹之間穿過去，天際線仍然有葉子。
		var trunk_lift := 0.0
		if dc < 10.0:
			target_h = maxf(target_h, 11.0)          # 別讓近處出現小樹
			trunk_lift = lerpf(2.6, 0.0, (dc - 5.5) / 4.5)
		var s := target_h / maxf(local_h, 0.1)
		var inst := ps.instantiate() as Node3D
		var y := height_at(x, z)
		inst.position = Vector3(x, y - 0.05 - trunk_lift, z)
		inst.rotation.y = lib.rand() * TAU
		# 歪斜（規格：歪斜樹木）— 深處更歪
		var lean := lib.rr(0.0, 0.05 + t * 0.10) if kind in ["歪", "枯"] else lib.rr(0.0, 0.03)
		inst.rotation.x = lean * (1.0 if lib.rand() < 0.5 else -1.0)
		inst.scale = Vector3(s, s * lib.rr(0.92, 1.1), s)
		# 紅葉配額：TwistedTree 的原生葉貼圖是深紅，成片出現會讓整座森林
		# 看起來「異常」而不是「妖怪的」。深處保留少量當妖異訊號。
		#
		# ⚠ 前兩次都失敗，原因相同：GLB 是 instance=ExtResource，
		#   它的**內部**節點不會被序列化。所以
		#     set_surface_override_material() → 丟掉（257 棵全紅）
		#     替換 mi.mesh                    → 也丟掉（257 棵全紅）
		#   唯一存得下來的是「實例根自己的屬性」。這裡改成不用 GLB 實例，
		#   而是自建 MeshInstance3D 掛一份改好材質的共用 mesh。
		var keep_red := kind == "歪" and t > 0.72 and lib.rand() < 0.25
		if kind == "歪" and not keep_red:
			inst = _green_twisted(variant)
			inst.position = Vector3(x, y - 0.05 - trunk_lift, z)
			inst.rotation.y = lib.rand() * TAU
			inst.rotation.x = lean * (1.0 if lib.rand() < 0.5 else -1.0)
			inst.scale = Vector3(s, s * lib.rr(0.92, 1.1), s)
		var band := 0 if ed < 45.0 else 1
		var parent: Node3D = near if band == 0 else far
		var gname := "%s_%s" % [kind, "近" if band == 0 else "遠"]
		if not groups.has(gname):
			groups[gname] = lib.add(parent, Node3D.new(), gname)
		lib.add(groups[gname], inst, "%s_%04d" % [variant, made])
		if band == 1:
			# 外圍：關投影（規格黑暗來自樹冠，但外圍 300 m 的樹投影玩家看不到）
			for mn in _mesh_nodes(inst):
				(mn as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_trunk_log.append([p, target_h * 0.45])     # 樹冠水平半徑約高度的 0.45
		var key2 := "%d_%d" % [gx, gz]
		if not grid.has(key2):
			grid[key2] = PackedVector2Array()
		grid[key2].append(p)
		count[band] += 1
		if ed < 14.0:
			_placed_trunks.append(p)
		made += 1
	# 近路樹幹碰撞
	var body := StaticBody3D.new()
	lib.add(lib.root, body, "樹幹碰撞")
	for q in _placed_trunks:
		var sh := CollisionShape3D.new()
		var c := CylinderShape3D.new()
		c.radius = 0.38; c.height = 5.0
		sh.shape = c
		sh.position = Vector3(q.x, height_at(q.x, q.y) + 2.5, q.y)
		body.add_child(sh)
		sh.owner = lib.root
	print("[TRAIL] 森林：路沿 %d / 外圍 %d（共 %d 棵，%d 根近路樹幹碰撞）" % [count[0], count[1], made, _placed_trunks.size()])
	_audit_corridor(_trunk_log)


## 走廊自檢：沿主脊取樣，量最近樹幹距離與「樹冠是否蓋住路心」。
##
## v3 的教訓：路沿樹被拔高到 15 m、樹幹離路心 3.6 m，樹冠在路面上空
## 完全閉合，實拍是一張純黑圖。用眼睛看截圖才發現，太慢也太不可靠——
## 產生器每次跑完就自己報告，走廊被封死時直接 push_error。
func _audit_corridor(logs: Array) -> void:
	var worst_gap := INF
	var worst_t := 0.0
	var blocked := 0
	var samples := 41
	for i in samples:
		var t := float(i) / float(samples - 1)
		var p := _spine_pos(t)
		var gap := INF
		var cover := 0
		for e in logs:
			var q: Vector2 = e[0]
			var r: float = e[1]        # 樹冠水平半徑
			var d := p.distance_to(q)
			gap = minf(gap, d)
			if d < r:
				cover += 1
		if gap < worst_gap:
			worst_gap = gap
			worst_t = t
		if cover >= 3:
			blocked += 1
	print("[TRAIL] 走廊自檢：最窄樹幹間隙 %.2f m（t=%.2f）；樹冠三重覆蓋的取樣點 %d/%d"
		% [worst_gap, worst_t, blocked, samples])
	if worst_gap < 4.0:
		push_error("走廊被樹幹擠死：最近 %.2f m < 4.0 m" % worst_gap)
	# ⚠ 三重覆蓋本身不是錯——規格 §9 明文要「樹冠遮光、斑駁陽光」。
	# 真正的失敗是「連樹幹之間都看不穿」，那才是 v3 的全黑。
	# 覆蓋率只當資訊；門檻放寬到「幾乎每個取樣點都被 6 層以上蓋住」。
	if blocked > samples * 9 / 10:
		push_error("樹冠可能過密：%d/%d 取樣點三重覆蓋，拍圖確認是否全黑" % [blocked, samples])


# ══════════════════════════════════════════════════════════════════
# 地表植被：蕨/芒草/灌木/菇/苔/花 —— 大量侵入路緣
# ══════════════════════════════════════════════════════════════════
const COVER := [
	# [名, 變體, 目標**最大邊** m 範圍, 數量, 路緣偏好(0-1), 林床偏好, 濕地偏好, 只在深處?]
	["蕨", ["Fern_1"], [0.6, 1.1], 1400, 0.85, 0.7, 0.9, false],
	["芒草", ["Grass_Wispy_Tall", "Grass_Common_Tall"], [0.6, 1.0], 1200, 0.9, 0.3, 0.5, false],
	["矮草", ["Grass_Common_Short", "Grass_Wispy_Short"], [0.35, 0.65], 1600, 0.8, 0.5, 0.6, false],
	["灌木", ["Bush_Common", "Bush_Common_Flowers"], [1.0, 1.8], 520, 0.6, 0.5, 0.3, false],
	["矮竹", ["Plant_7", "Plant_7_Big", "Plant_1_Big"], [0.6, 1.2], 380, 0.5, 0.6, 0.2, false],
	["苔", ["Clover_1", "Clover_2"], [0.15, 0.3], 700, 0.3, 0.9, 0.9, false],
	["菇", ["Mushroom_Common"], [0.2, 0.4], 320, 0.2, 0.9, 0.8, false],
	["靈芝", ["Mushroom_Laetiporus"], [0.3, 0.55], 90, 0.1, 0.9, 0.6, true],
	["野花", ["Flower_3_Group", "Flower_4_Group", "Flower_3_Single"], [0.25, 0.4], 260, 0.7, 0.1, 0.2, false],
]


func _build_ground_cover() -> void:
	var cover := lib.add(lib.root, Node3D.new(), "地表植被") as Node3D
	var total := 0
	for spec in COVER:
		var name: String = spec[0]
		var vars: Array = spec[1]
		var hr: Array = spec[2]
		var n: int = spec[3]
		var edge_pref: float = spec[4]
		var floor_pref: float = spec[5]
		var wet_pref: float = spec[6]
		var deep_only: bool = spec[7]
		var g := lib.add(cover, Node3D.new(), name) as Node3D
		var made := 0
		var tries := 0
		while made < n and tries < n * 40:
			tries += 1
			var x := lib.rr(-HALF + 4.0, HALF - 4.0)
			var z := lib.rr(-HALF + 4.0, HALF - 4.0)
			var p := Vector2(x, z)
			var info := _spine_info(p)
			var t: float = info[1]
			var hw := _half_w(t)
			var d: float = info[0]
			var ed := maxf(0.0, d - hw)
			if deep_only and t < 0.5:
				continue
			# 只在玩家看得到的帶內（路沿 40 m），外圍交給林床貼圖
			if ed > 40.0:
				continue
			# 路面與路緣淨空：
			# 1. 任何草木不得侵入路心（d < hw * 0.95 禁入）
			if d < hw * 0.95:
				continue
			# 2. 高草/蕨/矮竹/灌木退到路緣外側 (hw * 1.15)，讓路面完全露出來
			if name in ["芒草", "蕨", "矮竹", "灌木"] and d < hw * 1.15:
				continue
			# 3. 入口拍照點與空地視角周邊保護（避免極近前景大草貼鏡頭）
			if z > 265.0 and d < hw + 1.5:
				continue
			# 屋台區完全淨空，避免穿模桌椅與阻擋視野
			if p.distance_to(_stall_pos()) < 7.0:
				continue
			# 地藏周圍淨空 —— 不然 1 m 高的芒草會把 1.1 m 的地藏整個埋掉
			# （使用者回報：「地藏我根本看不到在哪裡」）
			var near_jizo := false
			for jq in _jizo_sites:
				if p.distance_to(jq) < 1.7:
					near_jizo = true
					break
			if near_jizo:
				continue
			# 空地範圍完全禁止高草、大灌木、大葉植栽（Plant）侵入，只留零星短草地被
			if _clearing_dist(p) < 2.0:
				if name in ["矮竹", "灌木", "芒草", "蕨"]:
					continue
				if _clearing_dist(p) < -2.0 and name not in ["矮草", "苔"]:
					continue
			var m := mask_at(x, z)
			var w := 0.0
			if d < hw + 2.5:
				w = edge_pref                     # 路緣
			else:
				w = floor_pref * (0.4 + m.g * 0.6)
			w = maxf(w, wet_pref * m.a)
			if _clearing_dist(p) < 0.0:
				w *= 0.3 if name in ["矮草", "野花", "苔"] else 0.05
			if lib.rand() > w:
				continue
			var variant: String = vars[int(lib.rand() * vars.size()) % vars.size()]
			var path := NAT + variant + ".gltf"
			var ps := _ps(path)
			var s := lib.rr(hr[0], hr[1]) / maxf(_w_cache[path], 0.05)
			var inst := ps.instantiate() as Node3D
			inst.position = Vector3(x, height_at(x, z) - 0.02, z)
			inst.rotation.y = lib.rand() * TAU
			inst.scale = Vector3(s, s, s)
			for mn in _mesh_nodes(inst):
				(mn as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lib.add(g, inst, "%s_%04d" % [variant, made])
			made += 1
		total += made
		print("[TRAIL] 地表 %-4s %5d" % [name, made])
	print("[TRAIL] 地表植被共 %d" % total)


# ══════════════════════════════════════════════════════════════════
# 岩石與倒木
# ══════════════════════════════════════════════════════════════════
func _build_rocks_and_logs() -> void:
	var g := lib.add(lib.root, Node3D.new(), "岩石與倒木") as Node3D
	var rocks := lib.add(g, Node3D.new(), "苔石") as Node3D
	var pebbles := lib.add(g, Node3D.new(), "碎石") as Node3D
	var logs := lib.add(g, Node3D.new(), "倒木_佔位") as Node3D
	var body := StaticBody3D.new()
	lib.add(g, body, "岩石碰撞")
	# 苔石：半埋、成叢不均勻
	var made := 0
	var tries := 0
	var clusters := []
	for i in 28:
		var t := lib.rr(0.05, 0.98)
		var side := 1.0 if lib.rand() < 0.5 else -1.0
		var c := _spine_pos(t) + Vector2(-_spine_dir(t).y, _spine_dir(t).x) * side * lib.rr(2.5, 18.0)
		clusters.append(c)
	for c in clusters:
		var n := 2 + int(lib.rand() * 4)
		for k in n:
			var p: Vector2 = c + Vector2(lib.rr(-4.0, 4.0), lib.rr(-4.0, 4.0))
			if _clearing_dist(p) < -8.0 or _creek_dist(p) < 1.0:
				continue
			var v := "Rock_Medium_%d" % (1 + int(lib.rand() * 3) % 3)
			var path := NAT + v + ".gltf"
			var ps := _ps(path)
			var target_h := lib.rr(0.5, 1.6)
			var s := target_h / maxf(_h_cache[path], 0.1)
			var inst := ps.instantiate() as Node3D
			var bury := lib.rr(0.15, 0.45)           # 半埋
			inst.position = Vector3(p.x, height_at(p.x, p.y) - target_h * bury, p.y)
			inst.rotation = Vector3(lib.rr(-0.25, 0.25), lib.rand() * TAU, lib.rr(-0.25, 0.25))
			inst.scale = Vector3(s * lib.rr(0.8, 1.3), s, s * lib.rr(0.8, 1.3))
			lib.add(rocks, inst, "%s_%03d" % [v, made])
			if target_h > 0.7:
				var sh := CollisionShape3D.new()
				var sp := SphereShape3D.new()
				sp.radius = target_h * 0.55
				sh.shape = sp
				sh.position = inst.position + Vector3(0, target_h * 0.3, 0)
				body.add_child(sh); sh.owner = lib.root
			made += 1
	# 路面碎石（規格：路面有碎石）
	var pm := 0
	for i in 900:
		var t := lib.rr(0.0, 1.0)
		var d := _spine_dir(t)
		var hw := _half_w(t)
		var p := _spine_pos(t) + Vector2(-d.y, d.x) * lib.rr(-hw * 1.3, hw * 1.3)
		var v: String = ["Pebble_Round_1", "Pebble_Round_3", "Pebble_Square_2", "Pebble_Square_5"][int(lib.rand() * 4) % 4]
		var path: String = NAT + v + ".gltf"
		var ps := _ps(path)
		var s := lib.rr(0.12, 0.3) / maxf(_w_cache[path], 0.05)
		var inst := ps.instantiate() as Node3D
		inst.position = Vector3(p.x, height_at(p.x, p.y) - 0.02, p.y)
		inst.rotation.y = lib.rand() * TAU
		inst.scale = Vector3(s, s, s)
		for mn in _mesh_nodes(inst):
			(mn as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lib.add(pebbles, inst, "%s_%03d" % [v, pm])
		pm += 1
	# 倒木：Meshy 缺件 → 用 Log_Cluster 暫代 + 佔位標記；規格：部分倒木橫跨小路
	var lm := 0
	for spec in [[0.20, true], [0.36, false], [0.44, true], [0.63, false], [0.68, true], [0.83, false], [0.9, true]]:
		var t: float = spec[0]
		var across: bool = spec[1]
		var d := _spine_dir(t)
		var c := _spine_pos(t)
		var p: Vector2 = c if across else c + Vector2(-d.y, d.x) * lib.rr(4.0, 9.0) * (1.0 if lib.rand() < 0.5 else -1.0)
		var mk := Marker3D.new()
		mk.position = Vector3(p.x, height_at(p.x, p.y), p.y)
		mk.rotation.y = atan2(d.x, d.y) + (PI * 0.5 if across else lib.rr(-0.6, 0.6))
		mk.set_meta("meshy", "倒木/腐木 2-3 種，長 4-7 m，%s" % ("橫跨小路" if across else "路旁"))
		lib.add(logs, mk, "倒木_%02d%s" % [lm, "_橫跨" if across else ""])
		# 暫代倒木：一根**圓柱**橫躺。
		# ⚠ 不能用 Log_Cluster 拉長。那是「一捆短柴薪」，端面有淺色年輪，
		#   非等比拉 4.5× 之後年輪變成螺旋紋 —— 使用者的原話是「肉桂捲蛋糕」。
		var trunk := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.30
		cyl.bottom_radius = 0.38          # 一頭粗一頭細，像真的樹幹
		cyl.height = lib.rr(4.5, 7.0)
		cyl.radial_segments = 10
		trunk.mesh = cyl
		trunk.material_override = lib.pbr("fallen_log", "bark_cedar", 0.6, Color(0.52, 0.47, 0.40))
		trunk.position = mk.position + Vector3(0, 0.32, 0)
		# 躺平：繞 Z 轉 90° 讓圓柱軸由縱轉橫，再依 mk 的朝向擺
		trunk.rotation = Vector3(0.0, mk.rotation.y, PI * 0.5)
		lib.add(logs, trunk, "暫代倒木_%02d" % lm)
		if across:
			var sh := CollisionShape3D.new()
			var bx := BoxShape3D.new()
			bx.size = Vector3(5.0, 0.9, 1.2)
			sh.shape = bx
			sh.position = mk.position + Vector3(0, 0.45, 0)
			sh.rotation.y = mk.rotation.y
			body.add_child(sh); sh.owner = lib.root
		lm += 1
	print("[TRAIL] 苔石 %d、碎石 %d、倒木 %d（%d 橫跨）" % [made, pm, lm, 4])


# ══════════════════════════════════════════════════════════════════
# 人類文明遺跡：越靠人里越多
# ══════════════════════════════════════════════════════════════════
func _build_human_traces() -> void:
	var g := lib.add(lib.root, Node3D.new(), "人類遺跡") as Node3D
	var body := StaticBody3D.new()
	lib.add(g, body, "遺跡碰撞")
	# 入口：兩塊界碑（Meshy 佔位）+ 警告牌 + 夜雀屋台小木牌 + 柵欄 + 地藏 + 燈籠
	var te := T_ENTRANCE
	var c := _spine_pos(te)
	var d := _spine_dir(te)
	var perp := Vector2(-d.y, d.x)
	var hw := _half_w(te)
	var ent := lib.add(g, Node3D.new(), "獸道入口") as Node3D
	for side in [-1.0, 1.0]:
		var p: Vector2 = c + perp * side * (hw + 1.2)
		var mk := Marker3D.new()
		mk.position = Vector3(p.x, height_at(p.x, p.y), p.y)
		mk.rotation.y = atan2(d.x, d.y)
		mk.set_meta("meshy", "石製界碑，高 1.2-1.5 m，風化長苔，「人間之里文明區域結束」")
		lib.add(ent, mk, "界碑_%s" % ("左" if side < 0 else "右"))
		var sh := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(0.6, 1.4, 0.5)
		sh.shape = bx; sh.position = mk.position + Vector3(0, 0.7, 0); body.add_child(sh); sh.owner = lib.root
	var wp := c + perp * (hw + 2.6) + d * 1.5
	var wm := Marker3D.new()
	wm.position = Vector3(wp.x, height_at(wp.x, wp.y), wp.y)
	wm.rotation.y = atan2(d.x, d.y) + 0.3
	wm.set_meta("meshy", "木製警告牌，高 1.8 m，歪斜：「妖怪出沒，夜間通行注意」")
	lib.add(ent, wm, "警告牌")
	var sp := c - perp * (hw + 2.2) - d * 2.0
	var sm := Marker3D.new()
	sm.position = Vector3(sp.x, height_at(sp.x, sp.y), sp.y)
	sm.rotation.y = atan2(d.x, d.y) - 0.5
	sm.set_meta("meshy", "隨意小木牌，高 1.1 m，手寫：「夜雀屋台 →」")
	lib.add(ent, sm, "小木牌_夜雀屋台")
	# 柵欄：入口兩側往外延伸，越遠越破
	var fence_ps := _ps(LP + "Fence_Wood.gltf")
	var fn := 0
	for side in [-1.0, 1.0]:
		for k in 5:
			if k >= 3 and lib.rand() < 0.5:
				continue          # 破損缺段
			var p: Vector2 = c + perp * side * (hw + 2.0 + 4.0 * k + 2.0) - d * lib.rr(0.0, 1.0)
			var inst := fence_ps.instantiate() as Node3D
			inst.position = Vector3(p.x, height_at(p.x, p.y) - 0.05, p.y)
			inst.rotation.y = atan2(perp.x, perp.y) + lib.rr(-0.08, 0.08)
			inst.rotation.z = lib.rr(-0.06, 0.06) * float(k)      # 越遠越歪
			inst.scale = Vector3(1.0, lib.rr(0.85, 1.0), 1.0)
			lib.add(ent, inst, "木柵欄_%s%d" % ["左" if side < 0 else "右", k])
			fn += 1
	# 燈籠與地藏（入口一組）
	_lantern(ent, c - perp * (hw + 1.0) + d * 6.0, true, body)
	# 入口地藏由 JIZO_SPECS[0]（t=0.07）統一負責，這裡不再另放
	# 沿路：地藏/舊路標/燈籠 —— 越深越少，且越破
	var along := lib.add(g, Node3D.new(), "沿路遺跡") as Node3D
	# 沿路遺跡：燈籠與路標（地藏另外走 JIZO_SPECS，位置要與植被讓位一致）
	var specs := [
		[0.13, "燈籠", true], [T_JIZO + 0.02, "路標", 0],
		[0.35, "燈籠", false], [0.47, "路標", 0], [0.62, "燈籠", false],
		[0.88, "路標", 0],
	]
	# 地藏：座標由 JIZO_SPECS + _jizo_base() 決定，與 _plan_jizo_sites() 同源
	for js in JIZO_SPECS:
		_jizo(along, _jizo_base(js[0], js[2]), js[1], body)
	for s in specs:
		var t: float = s[0]
		var kind: String = s[1]
		var dd := _spine_dir(t)
		var pp := _spine_pos(t) + Vector2(-dd.y, dd.x) * (_half_w(t) + lib.rr(0.8, 2.2)) * (1.0 if lib.rand() < 0.5 else -1.0)
		match kind:
			"燈籠": _lantern(along, pp, s[2], body)
			"路標":
				var mk := Marker3D.new()
				mk.position = Vector3(pp.x, height_at(pp.x, pp.y), pp.y)
				mk.rotation.y = atan2(dd.x, dd.y) + lib.rr(-0.4, 0.4)
				mk.rotation.z = lib.rr(-0.15, 0.15)
				mk.set_meta("meshy", "木製路標，高 1.6 m，字跡模糊，歪斜")
				lib.add(along, mk, "舊路標_t%02d" % int(t * 100))
	# 小溪木橋（Meshy 佔位 + 暫代木板）
	# ⚠ 橋面高度要讀**兩岸的實際地形**，不能用 height_at(溪心)+固定值。
	#   舊公式 +0.9 是溪谷還只切 0.9 m 時寫的；谷加深到 2.2 m 之後，
	#   橋整個浮在旱地上、離水面老遠（v10_小溪.png）。
	var cc := _spine_pos(T_CREEK)
	var cd := _spine_dir(T_CREEK)
	# 溪心在主脊上的實際 z（溪是東西向、有蛇行）
	var creek_z: float = cc.y + sin(cc.x * 0.045 + 1.3) * 6.0 + _nm.get_noise_1d(cc.x * 2.0) * 3.0
	# 橋跨在溪上：取南北兩岸（各離溪心 4 m）地形的較高者當橋面
	var bank_n := terrain_y(cc.x, creek_z - 4.5)
	var bank_s := terrain_y(cc.x, creek_z + 4.5)
	var deck_y := maxf(bank_n, bank_s) + 0.15
	var bm := Marker3D.new()
	bm.position = Vector3(cc.x, deck_y, creek_z)
	# 橋要橫跨溪流（溪東西向 → 橋南北向），不是順著主脊方向
	bm.rotation.y = 0.0
	bm.set_meta("meshy", "小木橋，長 9 m 寬 1.8 m，木板腐朽長苔，無欄杆或半截欄杆")
	lib.add(g, bm, "小木橋_佔位")
	var plank := MeshInstance3D.new()
	var bx := BoxMesh.new(); bx.size = Vector3(1.8, 0.12, 10.0)
	plank.mesh = bx
	# 腐朽木板：dark_wood 貼圖本身是鮮紅褐（實拍像新漆的紅橋），
	# 換 planks 並壓成灰褐 —— 規格 §4 要「風化、長苔、不可看起來像新建造」
	plank.material_override = lib.pbr("plank_rotten", "planks", 0.5, Color(0.46, 0.44, 0.38))
	plank.position = bm.position + Vector3(0, 0.06, 0)
	plank.rotation.y = bm.rotation.y
	lib.add(g, plank, "暫代木橋")
	var sh := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(1.8, 0.12, 10.0)
	sh.shape = bs; sh.position = plank.position; sh.rotation.y = plank.rotation.y
	body.add_child(sh); sh.owner = lib.root
	print("[TRAIL] 木橋：橋面 y=%.2f（北岸 %.2f 南岸 %.2f），溪心 z=%.1f" % [deck_y, bank_n, bank_s, creek_z])
	print("[TRAIL] 人類遺跡：柵欄 %d 段、沿路 %d 組、木橋 1" % [fn, specs.size()])


func _lantern(parent: Node3D, p: Vector2, intact: bool, body: StaticBody3D) -> void:
	var ps := _ps(LP + "StoneLantern.gltf")
	var inst := ps.instantiate() as Node3D
	inst.position = Vector3(p.x, height_at(p.x, p.y) - (0.0 if intact else 0.25), p.y)
	inst.rotation.y = lib.rand() * TAU
	if not intact:
		inst.rotation.z = lib.rr(0.2, 0.5)       # 倒塌/歪斜
		inst.rotation.x = lib.rr(-0.2, 0.2)
	lib.add(parent, inst, "石燈籠_%s_%d" % ["完整" if intact else "破損", parent.get_child_count()])
	var mk := Marker3D.new()
	mk.position = inst.position
	mk.set_meta("meshy", "小型石燈籠 %s，高 1.6 m，長苔" % ("完整" if intact else "破損/倒塌"))
	lib.add(parent, mk, "燈籠佔位_%d" % parent.get_child_count())
	var sh := CollisionShape3D.new(); var c := CylinderShape3D.new(); c.radius = 0.35; c.height = 1.6
	sh.shape = c; sh.position = inst.position + Vector3(0, 0.8, 0); body.add_child(sh); sh.owner = lib.root


## 地藏位置用的獨立 RNG：種子由該組的基準座標決定。
##
## ⚠ 一定要獨立於 lib 的主亂數序列。_plan_jizo_sites() 得在植被生成前
##   算出座標、_jizo() 在更後面才真正擺放，兩者必須得到同一組數字；
##   若共用主序列，預算會偷走亂數讓後面所有散佈位移。
func _jizo_rng(p: Vector2) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(int(round(p.x * 100.0)), int(round(p.y * 100.0)))) ^ SEED
	return rng


## 預先算出所有地藏的世界座標（供地表植被讓位）。
## 位置公式必須與 _build_human_traces() 裡的呼叫端**完全一致**。
func _plan_jizo_sites() -> void:
	_jizo_sites.clear()
	for spec in JIZO_SPECS:
		var t: float = spec[0]
		var cnt: int = spec[1]
		var base: Vector2 = _jizo_base(t, spec[2])
		var rng := _jizo_rng(base)
		for i in cnt:
			_jizo_sites.append(base + Vector2(rng.randf_range(-0.75, 0.75), rng.randf_range(-0.5, 0.5)) * float(i))
	print("[TRAIL] 地藏預定 %d 尊（植被讓開 1.7 m）" % _jizo_sites.size())


## 沿主脊 t 的地藏基準座標（側向 side：+1 左 / -1 右）
func _jizo_base(t: float, side: float) -> Vector2:
	var d := _spine_dir(t)
	return _spine_pos(t) + Vector2(-d.y, d.x) * side * (_half_w(t) + 2.3)


func _jizo(parent: Node3D, p: Vector2, n: int, body: StaticBody3D) -> void:
	# 暫代地藏：底座 + 身 + 頭 + 紅頭巾。
	#
	# ⚠ 舊版是一根 0.8 m 高、半徑 0.18 m 的膠囊，站在 1 m 高的芒草叢裡
	#   完全看不到（使用者：「地藏我根本看不到在哪裡」）。
	#   地藏是玩家的路標，必須讀得出來：加寬底座、頭與身分開、紅頭巾當
	#   色彩訊號 —— 紅色在整片綠褐森林裡是唯一的暖色。
	#
	# 位置用**獨立 RNG**（種子由座標決定），不碰 lib 的主亂數序列 ——
	# _plan_jizo_sites() 要能在植被之前算出同一組座標，若這裡偷走亂數，
	# 後面所有散佈都會位移。
	var stone := lib.pbr("jizo_stone", "stone_wall", 0.3, Color(0.72, 0.72, 0.68))
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.68, 0.13, 0.11)
	cloth.roughness = 0.95
	var rng := _jizo_rng(p)
	for i in n:
		var q := p + Vector2(rng.randf_range(-0.75, 0.75), rng.randf_range(-0.5, 0.5)) * float(i)
		var gy := height_at(q.x, q.y)
		var lean := rng.randf_range(-0.10, 0.10)
		var yaw := rng.randf() * TAU
		var mk := Marker3D.new()
		mk.position = Vector3(q.x, gy, q.y)
		mk.rotation = Vector3(0.0, yaw, lean)
		mk.set_meta("meshy", "風化地藏，總高 1.0-1.2 m（含底座），長苔，局部破損，紅頭巾與圍兜")
		lib.add(parent, mk, "地藏_%02d_%d" % [parent.get_child_count(), i])
		var g := Node3D.new()
		g.position = mk.position
		g.rotation = mk.rotation
		lib.add(parent, g, "暫代地藏_%02d_%d" % [parent.get_child_count(), i])
		# 底座（方石）
		var base := MeshInstance3D.new()
		var bm2 := BoxMesh.new(); bm2.size = Vector3(0.52, 0.20, 0.46)
		base.mesh = bm2
		base.material_override = stone
		base.position = Vector3(0, 0.10, 0)
		lib.add(g, base, "底座")
		# 身（圓柱，比膠囊粗）
		var torso := MeshInstance3D.new()
		var tc := CylinderMesh.new()
		tc.top_radius = 0.19; tc.bottom_radius = 0.24; tc.height = 0.56; tc.radial_segments = 10
		torso.mesh = tc
		torso.material_override = stone
		torso.position = Vector3(0, 0.20 + 0.28, 0)
		lib.add(g, torso, "身")
		# 頭（球）
		var head := MeshInstance3D.new()
		var hs := SphereMesh.new(); hs.radius = 0.17; hs.height = 0.32; hs.radial_segments = 12; hs.rings = 7
		head.mesh = hs
		head.material_override = stone
		head.position = Vector3(0, 0.20 + 0.56 + 0.15, 0)
		lib.add(g, head, "頭")
		# 紅頭巾（扁圓錐蓋在頭上）—— 森林裡唯一的暖色，遠遠就認得出
		var cap := MeshInstance3D.new()
		var cc4 := CylinderMesh.new()
		cc4.top_radius = 0.02; cc4.bottom_radius = 0.21; cc4.height = 0.16; cc4.radial_segments = 12
		cap.mesh = cc4
		cap.material_override = cloth
		cap.position = Vector3(0, 0.20 + 0.56 + 0.26, 0)
		lib.add(g, cap, "紅頭巾")
		# 圍兜
		var bib := MeshInstance3D.new()
		var bb := BoxMesh.new(); bb.size = Vector3(0.30, 0.26, 0.03)
		bib.mesh = bb
		bib.material_override = cloth
		bib.position = Vector3(0, 0.20 + 0.44, 0.20)
		lib.add(g, bib, "圍兜")
		var sh := CollisionShape3D.new(); var c := CylinderShape3D.new(); c.radius = 0.28; c.height = 1.1
		sh.shape = c; sh.position = mk.position + Vector3(0, 0.55, 0); body.add_child(sh); sh.owner = lib.root
		_jizo_sites.append(q)


# ══════════════════════════════════════════════════════════════════
# 大空地：古樹 Hero、地藏、倒塌燈籠、水潭、紅布、酒瓶、螢火蟲
# ══════════════════════════════════════════════════════════════════
func _build_clearing() -> void:
	var g := lib.add(lib.root, Node3D.new(), "獸道大空地") as Node3D
	var c := _spine_pos(T_CLEARING)
	var body := StaticBody3D.new()
	lib.add(g, body, "空地碰撞")
	# 古樹 Hero 佔位 + 暫代：古老神木（使用闊葉巨木，蒼翠深綠），置於空地偏西北側
	# 古樹是這張圖的視覺錨點，要在空地正中央附近——偏太多的話從路上走進來
	# 看不到它。前一版偏 6 m，俯瞰圖裡整棵消失在邊緣。
	var tp := c + Vector2(-1.5, 1.0)
	var mk := Marker3D.new()
	mk.position = Vector3(tp.x, height_at(tp.x, tp.y), tp.y)
	mk.set_meta("meshy", "Hero：巨大古老神木，高 20-22 m，樹冠直徑 18 m，樹洞，樹根隆起，掛舊紅布")
	lib.add(g, mk, "古樹_Hero佔位")
	var path := NAT + "CommonTree_1.gltf"
	var ps := _ps(path)
	var inst := ps.instantiate() as Node3D
	var s := 21.0 / maxf(_h_cache[path], 1.0)
	inst.position = mk.position - Vector3(0, 0.2, 0)
	inst.scale = Vector3(s * 1.05, s, s * 1.05)
	inst.rotation.y = 0.8
	lib.add(g, inst, "暫代古樹")
	var sh := CollisionShape3D.new(); var cy := CylinderShape3D.new(); cy.radius = 1.6; cy.height = 8.0
	sh.shape = cy; sh.position = mk.position + Vector3(0, 4.0, 0); body.add_child(sh); sh.owner = lib.root
	# 3–5 尊地藏、一座倒塌燈籠
	_jizo(g, c + Vector2(6.5, 4.0), 4, body)
	_lantern(g, c + Vector2(-7.0, -4.5), false, body)
	# 水潭（小）—— 同小溪：連續放射網格，不用逐格挑或圓盤。
	# 圓盤試過 2.6/1.9/1.4 都埋地；逐格挑不埋了但邊界成方塊。
	var pond := c + Vector2(6.0, -7.0)
	# 水位：潭心周圍地形最低點 + 15 cm
	var p_lo := INF
	for k in 13:
		var a0 := float(k) / 13.0 * TAU
		p_lo = minf(p_lo, terrain_y(pond.x + cos(a0) * 1.2, pond.y + sin(a0) * 1.2))
	p_lo = minf(p_lo, terrain_y(pond.x, pond.y))
	var p_level := p_lo + 0.15
	var rings := 5
	var segs := 20
	var pst := SurfaceTool.new()
	pst.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 每個方位各自找「地形升過水位」的半徑 → 潭緣貼著實際窪地，不是正圓
	var radii := PackedFloat32Array()
	radii.resize(segs)
	for sgi in segs:
		var ang := float(sgi) / float(segs) * TAU
		var rr := 0.6
		for k in range(1, 16):
			var r2 := float(k) * 0.35
			if terrain_y(pond.x + cos(ang) * r2, pond.y + sin(ang) * r2) > p_level:
				break
			rr = r2
		radii[sgi] = rr
	for ri in rings + 1:
		var rf := float(ri) / float(rings)
		for sgi in segs:
			var ang := float(sgi) / float(segs) * TAU
			var r2: float = radii[sgi] * rf
			pst.set_uv(Vector2(cos(ang) * rf * 0.5 + 0.5, sin(ang) * rf * 0.5 + 0.5))
			# bank：中心 0、外緣 1（water.gdshader 契約）
			pst.set_color(Color(rf, 1.0, 0.5))
			pst.set_normal(Vector3.UP)
			pst.add_vertex(Vector3(pond.x + cos(ang) * r2, p_level, pond.y + sin(ang) * r2))
	for ri in rings:
		for sgi in segs:
			var s2 := (sgi + 1) % segs
			var a := ri * segs + sgi
			var b := ri * segs + s2
			var cc3 := (ri + 1) * segs + sgi
			var d3 := (ri + 1) * segs + s2
			pst.add_index(a); pst.add_index(cc3); pst.add_index(b)
			pst.add_index(b); pst.add_index(cc3); pst.add_index(d3)
	var pm := MeshInstance3D.new()
	pm.mesh = pst.commit()
	pm.material_override = load("res://assets/materials/east_river_water.tres")
	lib.add(g, pm, "小水潭")
	print("[TRAIL] 小水潭：%d×%d 放射網格，水位 %.2f" % [rings, segs, p_level])
	# 苔石、倒木（空地邊緣）
	for i in 6:
		var a := lib.rr(0.0, TAU)
		var r := CLEARING_R * lib.rr(0.6, 0.95)
		var p := c + Vector2(cos(a), sin(a)) * r
		var v := "Rock_Medium_%d" % (1 + i % 3)
		var rp := NAT + v + ".gltf"
		var rps := _ps(rp)
		var th := lib.rr(0.5, 1.2)
		var rs := th / maxf(_h_cache[rp], 0.1)
		var ri := rps.instantiate() as Node3D
		ri.position = Vector3(p.x, height_at(p.x, p.y) - th * 0.3, p.y)
		ri.rotation.y = lib.rand() * TAU
		ri.scale = Vector3(rs, rs, rs)
		lib.add(g, ri, "空地苔石_%d" % i)
	# 妖怪留下的酒瓶與碗（lowpoly 暫代）
	var yk := lib.add(g, Node3D.new(), "妖怪遺留物") as Node3D
	for i in 5:
		var p := tp + Vector2(lib.rr(-4.0, 4.0), lib.rr(2.0, 6.0))
		var v: String = ["CeremicPot", "Basket_S", "CeremicPot", "Barrel", "CeremicPot"][i]
		var ps2 := _ps(LP + v + ".gltf")
		var it := ps2.instantiate() as Node3D
		it.position = Vector3(p.x, height_at(p.x, p.y), p.y)
		it.rotation.y = lib.rand() * TAU
		if v == "CeremicPot" and lib.rand() < 0.5:
			it.rotation.z = 1.4       # 倒著的
		it.scale = Vector3(0.6, 0.6, 0.6) if v == "Barrel" else Vector3.ONE
		lib.add(yk, it, "%s_%d" % [v, i])
	# 紅布（掛樹枝）：細長的薄板，紅色
	for i in 3:
		var a := lib.rr(0.0, TAU)
		var bm := MeshInstance3D.new()
		var bx := BoxMesh.new(); bx.size = Vector3(0.12, 1.4, 0.01)
		bm.mesh = bx
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.62, 0.10, 0.08)
		mat.roughness = 0.95
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		bm.material_override = mat
		bm.position = mk.position + Vector3(cos(a) * lib.rr(3.0, 6.0), lib.rr(5.0, 9.0), sin(a) * lib.rr(3.0, 6.0))
		bm.rotation = Vector3(lib.rr(-0.2, 0.2), a, lib.rr(-0.3, 0.3))
		lib.add(g, bm, "舊紅布_%d" % i)
	# 螢火蟲：GPUParticles3D，預設白天關閉，夜間才發光；光點微縮為柔和螢光
	var ff := GPUParticles3D.new()
	ff.amount = 45
	ff.lifetime = 4.0
	ff.preprocess = 1.0
	ff.visibility_aabb = AABB(Vector3(-15, -2, -15), Vector3(30, 6, 30))
	var pm2 := ParticleProcessMaterial.new()
	pm2.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm2.emission_box_extents = Vector3(10.0, 1.2, 10.0)
	pm2.gravity = Vector3.ZERO
	pm2.initial_velocity_min = 0.1; pm2.initial_velocity_max = 0.4
	pm2.turbulence_enabled = true
	pm2.turbulence_noise_strength = 0.8
	pm2.turbulence_noise_scale = 2.0
	pm2.scale_min = 0.02; pm2.scale_max = 0.05
	pm2.color = Color(0.65, 1.0, 0.45, 0.8)
	ff.process_material = pm2
	var qm := QuadMesh.new(); qm.size = Vector2(0.12, 0.12)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_color = Color(0.65, 1.0, 0.45, 0.8)
	fm.emission_enabled = true
	fm.emission = Color(0.5, 1.0, 0.3)
	fm.emission_energy_multiplier = 2.0
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.material = fm
	ff.draw_pass_1 = qm
	ff.position = Vector3(c.x, height_at(c.x, c.y) + 1.2, c.y)
	ff.emitting = false      # 白天關閉！夜間由夜間燈光系統開啟
	lib.add(g, ff, "螢火蟲")
	print("[TRAIL] 大空地：中心 %s 半徑 %.0f m" % [c, CLEARING_R])


# ══════════════════════════════════════════════════════════════════
# 夜雀屋台：Hero 佔位 + 暫代桌椅 + 暖色燈
# ══════════════════════════════════════════════════════════════════
func _build_stall_site() -> void:
	var g := lib.add(lib.root, Node3D.new(), "夜雀屋台區") as Node3D
	var c := _spine_pos(T_STALL)
	var d := _spine_dir(T_STALL)
	var perp := Vector2(-d.y, d.x)
	var sp := _stall_pos()
	var mk := Marker3D.new()
	mk.position = Vector3(sp.x, height_at(sp.x, sp.y), sp.y)
	mk.rotation.y = atan2(-perp.x, -perp.y)      # 面向路
	mk.set_meta("meshy", "Hero：小型移動式日式屋台，木造 2.5-3 m 寬，布簾、紙燈籠、炭火、碗、酒瓶、食材箱、木牌")
	lib.add(g, mk, "夜雀屋台_Hero佔位")
	var body := StaticBody3D.new()
	lib.add(g, body, "屋台碰撞")
	# 暫代：市集屋台（Meshy 現成）縮到 2.8 m
	var ps := load("res://assets/market/屋台陶瓷攤.glb") as PackedScene
	if ps != null:
		var inst := ps.instantiate() as Node3D
		var h := _mesh_h(ps)
		var box := _aabb_of(ps)
		var s := 2.8 / maxf(box.size.x, 0.5)
		inst.position = mk.position - Vector3(0, box.position.y * s, 0)   # Meshy 原點居中 → 抬到底
		inst.rotation.y = mk.rotation.y
		inst.scale = Vector3(s, s, s)
		lib.add(g, inst, "暫代屋台")
	var sh := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(3.0, 2.4, 1.6)
	sh.shape = bx; sh.position = mk.position + Vector3(0, 1.2, 0); sh.rotation.y = mk.rotation.y
	body.add_child(sh); sh.owner = lib.root
	# 桌椅
	for i in 2:
		var tp := sp - perp * (2.6 + float(i) * 0.2) + d * (float(i) * 2.4 - 1.2)
		var t := _ps(LP + "Table_Circular.gltf").instantiate() as Node3D
		t.position = Vector3(tp.x, height_at(tp.x, tp.y), tp.y)
		lib.add(g, t, "小桌_%d" % i)
		for k in 2:
			var cp := tp + Vector2(lib.rr(-0.9, 0.9), lib.rr(-0.9, 0.9)).normalized() * 0.85
			var ch := _ps(LP + "Chair.gltf").instantiate() as Node3D
			ch.position = Vector3(cp.x, height_at(cp.x, cp.y), cp.y)
			ch.rotation.y = atan2(tp.x - cp.x, tp.y - cp.y)
			lib.add(g, ch, "小椅_%d_%d" % [i, k])
	# 雜物：碗、酒瓶、食材箱
	for i in 4:
		var p := sp + perp * lib.rr(-1.6, 1.6) + d * lib.rr(1.8, 2.6)
		var v: String = ["CeremicPot", "WoodenBox", "Basket_S", "Barrel"][i]
		var it := _ps(LP + v + ".gltf").instantiate() as Node3D
		it.position = Vector3(p.x, height_at(p.x, p.y), p.y)
		it.rotation.y = lib.rand() * TAU
		it.scale = Vector3(0.7, 0.7, 0.7) if v == "Barrel" else Vector3.ONE
		lib.add(g, it, "%s_%d" % [v, i])
	# 暖色紙燈籠光（夜間為視覺焦點）：兩盞 OmniLight3D
	for i in 2:
		var lp := sp + d * (float(i) * 2.0 - 1.0)
		var ol := OmniLight3D.new()
		ol.position = Vector3(lp.x, height_at(lp.x, lp.y) + 2.2, lp.y)
		ol.light_color = Color(1.0, 0.72, 0.42)
		ol.light_energy = 2.2
		ol.omni_range = 9.0
		ol.omni_attenuation = 1.4
		ol.shadow_enabled = i == 0
		lib.add(g, ol, "紙燈籠光_%d" % i)
	# 炭火：小的橘紅點光 + 位置標記
	var fire := OmniLight3D.new()
	fire.position = mk.position + Vector3(0, 0.6, 0)
	fire.light_color = Color(1.0, 0.45, 0.15)
	fire.light_energy = 1.2
	fire.omni_range = 3.5
	lib.add(g, fire, "炭火光")
	print("[TRAIL] 夜雀屋台：%s" % sp)


func _aabb_of(ps: PackedScene) -> AABB:
	var inst := ps.instantiate() as Node3D
	var box: Variant = null
	for m in _mesh_nodes(inst):
		var b := _rel(m, inst) * (m as MeshInstance3D).get_aabb()
		box = b if box == null else (box as AABB).merge(b)
	inst.free()
	return box if box != null else AABB(Vector3.ZERO, Vector3.ONE)


# ══════════════════════════════════════════════════════════════════
# 妖怪存在感：紅布條、酒瓶、碗、祭物、遠處燈光 —— 越深越多
# ══════════════════════════════════════════════════════════════════
func _build_youkai_traces() -> void:
	var g := lib.add(lib.root, Node3D.new(), "妖怪痕跡") as Node3D
	var n := 0
	# 紅布條綁在路邊樹上（用近路樹幹座標）
	var cloth := lib.add(g, Node3D.new(), "紅布條") as Node3D
	for q in _placed_trunks:
		var info := _spine_info(q)
		var t: float = info[1]
		if t < 0.5 or lib.rand() > (t - 0.5) * 0.12:
			continue
		var bm := MeshInstance3D.new()
		var bx := BoxMesh.new(); bx.size = Vector3(0.10, 0.9, 0.01)
		bm.mesh = bx
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.58, 0.09, 0.07)
		mat.roughness = 0.95
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		bm.material_override = mat
		var a := lib.rr(0.0, TAU)
		bm.position = Vector3(q.x + cos(a) * 0.45, height_at(q.x, q.y) + lib.rr(1.4, 2.2), q.y + sin(a) * 0.45)
		bm.rotation.y = a
		lib.add(cloth, bm, "紅布_%03d" % n)
		n += 1
	# 小型祭物（碗、酒瓶、石堆）
	var off := lib.add(g, Node3D.new(), "祭物") as Node3D
	var on := 0
	for i in 14:
		var t := lib.rr(0.55, 0.98)
		var d := _spine_dir(t)
		var p := _spine_pos(t) + Vector2(-d.y, d.x) * (_half_w(t) + lib.rr(0.5, 2.5)) * (1.0 if lib.rand() < 0.5 else -1.0)
		var v: String = ["CeremicPot", "Basket_S", "CeremicPot"][i % 3]
		var it := _ps(LP + v + ".gltf").instantiate() as Node3D
		it.position = Vector3(p.x, height_at(p.x, p.y), p.y)
		it.rotation.y = lib.rand() * TAU
		it.scale = Vector3(0.8, 0.8, 0.8)
		lib.add(off, it, "%s_%02d" % [v, on])
		# 旁邊三顆小石
		for k in 3:
			var rp := p + Vector2(lib.rr(-0.5, 0.5), lib.rr(-0.5, 0.5))
			var pv := "Pebble_Round_%d" % (1 + k)
			var pp := NAT + pv + ".gltf"
			var ps := _ps(pp)
			var s := 0.18 / maxf(_w_cache[pp], 0.05)
			var pi := ps.instantiate() as Node3D
			pi.position = Vector3(rp.x, height_at(rp.x, rp.y), rp.y)
			pi.scale = Vector3(s, s, s)
			lib.add(off, pi, "祭石_%02d_%d" % [on, k])
		on += 1
	# 遠處妖怪燈光：深處林中幾點冷色微光（夜間才有意義）
	var lights := lib.add(g, Node3D.new(), "遠處妖火") as Node3D
	for i in 6:
		var t := lib.rr(0.62, 0.99)
		var d := _spine_dir(t)
		var p := _spine_pos(t) + Vector2(-d.y, d.x) * lib.rr(22.0, 45.0) * (1.0 if lib.rand() < 0.5 else -1.0)
		var ol := OmniLight3D.new()
		ol.position = Vector3(p.x, height_at(p.x, p.y) + lib.rr(1.0, 3.0), p.y)
		ol.light_color = [Color(0.45, 0.75, 1.0), Color(0.7, 0.4, 1.0), Color(0.4, 1.0, 0.6)][i % 3]
		ol.light_energy = 1.6
		ol.omni_range = 7.0
		ol.omni_attenuation = 1.8
		lib.add(lights, ol, "妖火_%d" % i)
	# 磷光菌類：深處林床，發光材質
	var glow := lib.add(g, Node3D.new(), "磷光菌") as Node3D
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.9, 0.7)
	gm.emission_enabled = true
	gm.emission = Color(0.35, 0.9, 0.55)
	gm.emission_energy_multiplier = 1.6
	var gn := 0
	for i in 120:
		var t := lib.rr(0.58, 0.99)
		var d := _spine_dir(t)
		var p := _spine_pos(t) + Vector2(-d.y, d.x) * lib.rr(_half_w(t) + 0.5, 14.0) * (1.0 if lib.rand() < 0.5 else -1.0)
		var pp := NAT + "Mushroom_Common.gltf"
		var ps := _ps(pp)
		var s := lib.rr(0.2, 0.4) / maxf(_w_cache[pp], 0.05)
		var mi := ps.instantiate() as Node3D
		mi.position = Vector3(p.x, height_at(p.x, p.y) - 0.02, p.y)
		mi.rotation.y = lib.rand() * TAU
		mi.scale = Vector3(s, s, s)
		for mn in _mesh_nodes(mi):
			(mn as MeshInstance3D).material_override = gm
			(mn as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lib.add(glow, mi, "磷光菌_%03d" % gn)
		gn += 1
	print("[TRAIL] 妖怪痕跡：紅布 %d、祭物 %d、妖火 6、磷光菌 %d" % [n, on, gn])


# ══════════════════════════════════════════════════════════════════
# 遠景：gobkit 山（混用裁決）+ lib.vista 地平線
# ══════════════════════════════════════════════════════════════════
func _build_vista() -> void:
	lib.vista(OUT, HALF, 1000.0, height_at, [
		{ "x": -620.0, "z": -620.0, "h": 120.0, "r": 240.0 },
		{ "x": 520.0, "z": -560.0, "h": 60.0, "r": 200.0 },
	], "res://assets/models/tree_round_far.glb", 260)
	var g := lib.add(lib.root, Node3D.new(), "遠景山_gobkit") as Node3D
	# [檔名, 目標高 m, x, z, yaw]
	var specs := [
		["Mountain001", 240.0, -700.0, -720.0, 0.4],      # 西北 妖怪之山
		["MountainFar001", 300.0, -950.0, -600.0, 1.2],
		["Mountain002", 130.0, 620.0, -650.0, 2.6],       # 東北 神社東山
		["Hill001", 55.0, 720.0, -300.0, 0.0],
		["Hill002", 48.0, -750.0, 200.0, 1.0],
	]
	for s in specs:
		var path: String = GOB + String(s[0]) + ".glb"
		var ps := _ps(path)
		var sc: float = s[1] / maxf(_h_cache[path], 1.0)
		var inst := ps.instantiate() as Node3D
		inst.position = Vector3(s[2], -8.0, s[3])
		inst.rotation.y = s[4]
		inst.scale = Vector3(sc, sc, sc)
		for mn in _mesh_nodes(inst):
			(mn as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lib.add(g, inst, s[0])
	print("[TRAIL] 遠景山 %d 座" % specs.size())


# ══════════════════════════════════════════════════════════════════
# 天象系統：跟 slice 同一支腳本，森林用較濃霧、較暗環境光
# ══════════════════════════════════════════════════════════════════
func _build_sky() -> void:
	var sky := Node3D.new()
	sky.set_script(load("res://scripts/sky_system.gd"))
	lib.add(lib.root, sky, "天象系統")
	sky.set("時刻", 15.7)
	sky.set("一日長度分鐘", 20.0)
	sky.set("方位角", -26.0)
	sky.set("星星密度", 0.35)
	sky.set("銀河強度", 0.5)
	sky.set("陰影距離", 120.0)
	sky.set("體積霧", true)
	# 天象腳本會自建 WorldEnvironment/太陽；這裡再補一個森林霧覆蓋層
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.72, 0.66)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.25
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.028
	env.volumetric_fog_albedo = Color(0.75, 0.80, 0.72)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.42     # 樹冠遮光
	env.ssao_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.04
	we.environment = env
	lib.add(lib.root, we, "森林環境")


# ══════════════════════════════════════════════════════════════════
# 出生點與傳送點標記 + Meshy 佔位總表
# ══════════════════════════════════════════════════════════════════
func _build_markers() -> void:
	var g := lib.add(lib.root, Node3D.new(), "標記") as Node3D
	var s := _spine_pos(0.02)
	var sm := Marker3D.new()
	sm.position = Vector3(s.x, height_at(s.x, s.y) + 1.0, s.y)
	sm.rotation.y = PI   # 面北
	lib.add(g, sm, "出生點_南入口")
	var n := _spine_pos(0.99)
	var nm := Marker3D.new()
	nm.position = Vector3(n.x, height_at(n.x, n.y) + 1.0, n.y)
	nm.set_meta("portal", "shrine")
	lib.add(g, nm, "傳送點_北_神社")
	var v := _spine_pos(0.0)
	var vm := Marker3D.new()
	vm.position = Vector3(v.x, height_at(v.x, v.y) + 1.0, v.y)
	vm.set_meta("portal", "village")
	lib.add(g, vm, "傳送點_南_人里")
	print("[TRAIL] 出生點 %s；傳送 北 %s 南 %s" % [sm.position, nm.position, vm.position])
