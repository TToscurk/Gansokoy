# 人間之里 全鎮・參數化產生器（第二階段：批量鋪全鎮）
#
#   godot --headless --path godot --script tools/gen_town.gd
#
# 分工（開工前定案）：Blender 只做模組（make_town.py → machiya_*/bridge_*/
# unomitei.glb + data/town_modules.json 尺寸表）；**佈局邏輯全在這裡**，
# 資料驅動、MultiMesh 批次實例。
#
# ── 水系優先 ──
# RIVER_SPINE 是城鎮的結構脊椎：先定河，街區跟著水走。臨河的十個街區
# 臨街線是**沿著河的樣條**取的（法線方向偏移 11.9m＝河畔道外緣），
# 不是格線；內陸街區才回到街道格線。
#
# ── 這一版取代的舊決策（都在 gen_village.gd 的註解裡）──
#   ・「水道直直的就好不要轉彎」→ 使用者看空拍參考後推翻，改蜿蜒脊椎。
#   ・「主街 8m，11m 像機場跑道」→ 那是對南北本通說的，本通維持 8m。
#     12m 軸放在**過河的東西向主路**（兩側有 9~10m 町家壓著、12m 橋收束）。
#   ・前排町家 4.5m（使用者本輪定案：階梯天際線選 (c)，只壓前排）。
#   ・鵜呑亭**不搬遷**，改成臨河食堂（使用者本輪定案）。
#
# ⚠ 輸出到 **maps/sato/**，不碰 maps/village/。整合（換掉 village、改 trail
# 與 kourindou 的回程 portal、check_map/walk_test 的地圖清單）是下一個
# 明確步驟，要使用者點頭 —— gen_village.gd 裡還有大量本輪範圍外的東西
# （地標內裝、雜物、動物、村人路線），不能靜靜蓋掉。
extends SceneTree

const OUT_DIR := "res://maps/sato/"
const MAP_ID := "sato"
const MODULES := "res://data/town_modules.json"
const SEED := 20260806

const HALF := 300.0
const PLAZA := Vector2(0, 30)
const CORE := 196.0

# ── 河道脊椎（村座標：-z = 北）──
const RIVER_SPINE := [
	Vector2(108, -300), Vector2(96, -236), Vector2(74, -168), Vector2(86, -108),
	Vector2(64, -50), Vector2(62, -6), Vector2(66, 30), Vector2(78, 72),
	Vector2(64, 120), Vector2(56, 168), Vector2(72, 224), Vector2(64, 300),
]
const RIVER_HALF := 7.0
const RIVER_DEPTH := 2.5
const BANK_PATH := 11.4          # 岸 7.0 + 護岸 1.2 + 河畔道 3.2

const MAIN_EW_Z := 30.0
const MAIN_EW_W := 12.0

# 橋：主橋 12m 在 12m 主路上；兩座小橋在 z=-80 / z=140 的橫街上。
# （八條東西街都會碰到河，但規格只給 1~2 座小橋 —— 其餘東西街在西岸
#  河畔道收尾，不硬蓋橋。選這兩條是因為它們是東西兩側唯二需要的連通。）
const BRIDGES := [
	{"kind": "bridge_main", "x": 66.0, "z": 30.0, "yaw": 0.0},
	{"kind": "bridge_small", "x": 76.8, "z": -80.0, "yaw": 0.0},
	{"kind": "bridge_small", "x": 58.9, "z": 140.0, "yaw": 0.0},
]

# ── 超現實地標塔（使用者本輪指令）──
# **只有這幾座**推到 15~20m；一般町家的階梯天際線（前排 4.5 / 後排 9~10）
# 維持不動 —— 對比才是重點，這個手法不准擴散。
# 三座都放在**街道視線的終點**，高度才會被框住而不是隨機散落：
#   火見櫓 → 本通北端（從廣場往北 162m 的直線走廊底）
#   鐘楼   → 本通南端（往南 166m）
#   水車櫓 → z=85 橫街的河岸終點；從主橋往北看也在視線裡
# 三座都刻意偏離路心 6~10m：要被框住，不是擋住路。
const TOWERS := [
	{"kind": "tower_fire", "x": 9.5, "z": -132.0, "yaw": 0.20,
	 "why": "本通北端終點"},
	{"kind": "tower_bell", "x": 8.5, "z": 196.0, "yaw": -0.15,
	 "why": "本通南端終點"},
	{"kind": "tower_mill", "x": 62.5, "z": 89.0, "yaw": 1.5708,
	 "why": "z=85 橫街的河岸終點；水輪朝河"},
]

# 鵜呑亭（臨河食堂）：正面朝河，離主橋西橋頭約 13m。
# ⚠ 錨點要離主橋夠遠：模組**含川床深 17.5m**（不是主屋的 10.9m），
# 放在 z=19 時東北角壓到橋的西引道（實測 20 處 3D 互穿，最深 0.78m）。
const UNOMITEI_ANCHOR := Vector2(50.0, 2.0)

# 既有地標街區：本輪**不重做**（不在街區重設計的範圍內），
# 但要把地佔起來，街區才不會排到它們身上。佔位量體也一起畫出來，
# 不然評圖時會看到八個空洞，讀不出城鎮的完整度。
# w/d = **佔地**（保留區，不准蓋町家的範圍）
# bw/bd = 佔位量體（沒寫就等於 w/d）。兩者要分開的原因見稗田邸那條。
const LANDMARKS := [
	{"n": "寺子屋", "x": -26.0, "z": -52.0, "w": 26.0, "d": 16.0, "h": 6.1},
	{"n": "鈴奈庵", "x": 11.6, "z": -52.0, "w": 13.0, "d": 9.5, "h": 5.4},
	# ⚠ 稗田邸搬到村緣（使用者定案・方案 B）。舊位置 (-78, 2) 是沿用舊格線
	# 來的，離廣場只有 83m、離鎮守之杜 52m、離市場 76m —— 埋在商業核心裡，
	# 跟「私密、安靜、避世」的設定矛盾。新位置在北門西側：離北門（主入口、
	# portals[0]、玩家從 trail 進村的落點）79m，離最近商業設施 122m。
	# ⚠ 佔地從 27.7×18.7 改成 **40.7×43.7** —— 那是 village.tscn 裡**實際
	# 蓋出來**的院落（築地塀＋腰石垣＋主屋＋庭池）量出來的尺寸。舊值小了
	# 13×25m，等於保留區根本框不住真正的院落；現在沒撞到純粹是運氣好
	# （實測舊框內外都是 0 棟町家），不是護欄有效。
	# 量體（bw/bd）維持主屋大小：整塊 40.7×43.7 拉成 12.8m 高的實心箱會讀成
	# 城砦，而真正的稗田邸是「牆圍著院子、主屋在中間」。
	{"n": "稗田邸", "x": -78.0, "z": -164.0, "w": 40.7, "d": 43.7, "h": 12.8,
		"bw": 27.7, "bd": 18.7},
	{"n": "鎮守之杜", "x": -26.0, "z": 2.0, "w": 34.0, "d": 36.0, "h": 14.0},
	{"n": "市場", "x": -26.0, "z": 57.0, "w": 30.0, "d": 34.0, "h": 4.6},
	{"n": "足洗邸", "x": 26.0, "z": 112.0, "w": 24.0, "d": 18.0, "h": 6.4},
]

var lib = preload("res://tools/gen_lib.gd").new()
var _root: Node3D
var _mods := {}
var _batch := {}                 # 模組名 → Array[Transform3D]
var _audit: Array[String] = []
var _dump := []                  # [kind, x, y, z, yaw]
var _nh: FastNoiseLite
var _n2: FastNoiseLite
var _river_pts := PackedVector2Array()
var _roads := []                 # [{pts:[Vector2...], w:float}]
var _uno_pos := Vector2(1e9, 1e9)   # 鵜呑亭位置（護岸在這段要讓開）
var _reserved := []                 # 不准蓋町家的 OBB（地標／鵜呑亭／橋）


func _init() -> void:
	var f := FileAccess.open(MODULES, FileAccess.READ)
	if f == null:
		push_error("讀不到 %s —— 先跑 make_town.py" % MODULES)
		quit(1)
		return
	_mods = JSON.parse_string(f.get_as_text())["modules"]
	f.close()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + "gen"))
	# 地形噪聲：照抄 gen_village 已驗收的那組（種子也一樣），
	# 換圖的時候地貌才不會整個變一個樣。
	_nh = FastNoiseLite.new(); _nh.frequency = 0.011; _nh.seed = 500
	_n2 = FastNoiseLite.new(); _n2.frequency = 0.03; _n2.seed = 77

	_root = Node3D.new()
	_root.name = "Sato"
	_root.set_meta("own_colliders", true)
	lib.setup(_root, SEED)
	_build_roads()

	lib.terrain(OUT_DIR, HALF, 221, height_at, mask_at, "cobble",
		Color(0.60, 0.94, 0.55), "terrain_path", Color(0.80, 0.75, 0.66))
	lib.boundary(HALF - 2.0)
	_plug_river_mouths()
	# sink 0.35 → 0.20：0.35 的話護岸頂離水面 0.98m，整條河讀成水泥排水渠
	# （引擎內低視角截圖看出來的）。0.20 之後只差 0.60m，水是滿的。
	lib.river_water(OUT_DIR, _river(), RIVER_HALF * 0.86, RIVER_DEPTH * 0.20, bank_h)
	_build_unomitei()          # 先算位置：護岸要在這一段讓開
	_build_revetment()
	_build_bridges()
	_build_landmark_stubs()
	_build_towers()
	_build_blocks()
	_assert_no_overlap()
	_emit_batches()
	_build_collision()
	_build_density()
	lib.vista(OUT_DIR, HALF, 900.0, height_at,
		[{"x": 620.0, "z": -680.0, "h": 260.0, "r": 300.0},
		 {"x": 430.0, "z": -520.0, "h": 110.0, "r": 170.0},
		 {"x": -560.0, "z": -600.0, "h": 70.0, "r": 220.0},
		 {"x": 520.0, "z": 560.0, "h": 90.0, "r": 180.0}],
		"res://assets/models/tree_round_b.glb", 420,
		[{"glb": "res://assets/models/bamboo_a.glb", "count": 300, "cx": -430.0,
		  "cz": 470.0, "r": 240.0, "smin": 1.3, "smax": 2.2},
		 {"glb": "res://assets/models/bamboo_b.glb", "count": 220, "cx": -540.0,
		  "cz": 350.0, "r": 200.0, "smin": 1.4, "smax": 2.4}])
	_build_env()
	_perf_pass(_root)

	for line in _audit:
		print(line)

	var packed := PackedScene.new()
	packed.pack(_root)
	var err := ResourceSaver.save(packed, OUT_DIR + "%s.tscn" % MAP_ID)
	print("saved %s.tscn err=%d  節點 %d" % [MAP_ID, err, _count(_root)])
	_write_meta()
	_write_dump()
	quit()


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


# ── 河道 ──

func _spline(ctrl: Array, per_seg: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in ctrl.size() - 1:
		var p0: Vector2 = ctrl[max(i - 1, 0)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[min(i + 2, ctrl.size() - 1)]
		for k in per_seg:
			var t := float(k) / per_seg
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t))
	out.append(ctrl[ctrl.size() - 1])
	return out


func _river() -> PackedVector2Array:
	if _river_pts.is_empty():
		_river_pts = _spline(RIVER_SPINE, 14)
	return _river_pts


func _nearest_river_pt(at: Vector2) -> Vector2:
	var best := _river()[0]
	var bd := 1e18
	for p in _river():
		var d := p.distance_squared_to(at)
		if d < bd:
			bd = d
			best = p
	return best


func river_tangent(at: Vector2) -> Vector2:
	var pts := _river()
	var bi := 0
	var bd := 1e18
	for i in pts.size():
		var d := pts[i].distance_squared_to(at)
		if d < bd:
			bd = d
			bi = i
	return (pts[min(bi + 1, pts.size() - 1)] - pts[max(bi - 1, 0)]).normalized()


# ── 地形 ──
# bank_h = 岸的高度（不含河道下切）。水面一律用它 —— 用 height_at 的話
# 水面會跟著河床沉下去（gen_village 的註解點名過）。

func bank_h(x: float, z: float) -> float:
	var r := Vector2(x, z - 30.0).length()
	return _nh.get_noise_2d(x, z) * 2.4 * (0.06 + 0.94 * smoothstep(176.0, 266.0, r)) \
		+ sin(x * 0.46 + z * 0.33) * 0.04


func height_at(x: float, z: float) -> float:
	var h := bank_h(x, z)
	h += lib.river_carve(_river(), RIVER_HALF, RIVER_DEPTH, x, z)
	var d: float = lib.poly_dist(_river(), x, z)
	# 下切影響半徑收斂：river_carve 的緩坡拖到 2.2×half=15.4m，房子的基石
	# 會浮在坡上、路在橋前先陷再爬上橋台。岸外 1.2m 起 2.8m 內收到 0。
	if d > RIVER_HALF + 1.2:
		var k := clampf(1.0 - (d - (RIVER_HALF + 1.2)) / 2.8, 0.0, 1.0)
		h = bank_h(x, z) + (h - bank_h(x, z)) * k
	# 橋頭把路廊拉平，才平接橋台
	for b in BRIDGES:
		if absf(x - b.x) < 16.0 and absf(z - b.z) < 8.0 and d > RIVER_HALF + 0.6:
			h = bank_h(x, z) + (h - bank_h(x, z)) \
				* clampf((absf(z - b.z) - 6.0) / 1.5, 0.0, 1.0)
	return h


func _road_info(x: float, z: float) -> float:
	## 回傳 0~1 的路面遮罩（1 = 路心）
	var best := 0.0
	for r in _roads:
		var d: float = lib.poly_dist(r.pts, x, z) - r.w * 0.5
		best = maxf(best, clampf(1.0 - maxf(d, 0.0) / 0.9, 0.0, 1.0))
	return best


## 店前鋪面：路緣到建物正面之間那條帶。
## ⚠ 這條帶原本是**草**，於是商業核心讀成郊區而不是密集市街（使用者指出）。
## 實測 164 棟臨街町家的正面離路緣：中位 3.85m、57 棟 ≤3m、43 棟 3~6m ——
## 所以鋪面寬度取 4.2m 就能把大部分的縫補起來，再往外就會鋪到院子裡。
## 只在村心生效：村緣的房子門口本來就該是土與草。
const APRON_W := 4.2

func _road_apron(x: float, z: float) -> float:
	# ⚠ 一定要**限村心**。第一版沒加這個閘門（註解寫了「只在村心生效」，
	# 程式碼卻沒寫）→ 全鎮每條路都外擴 4.2m，空拍下整個路網糊成一片淺色。
	# 村緣的房子門口本來就該是土與草。
	var core_k := 1.0 - smoothstep(96.0, 150.0, Vector2(x, z - PLAZA.y).length())
	if core_k <= 0.0:
		return 0.0
	var best := 0.0
	for r in _roads:
		var d: float = lib.poly_dist(r.pts, x, z) - r.w * 0.5
		if d <= 0.0:
			continue
		best = maxf(best, clampf(1.0 - d / APRON_W, 0.0, 1.0))
	return best * core_k


func mask_at(x: float, z: float) -> Color:
	## 遮罩通道的意義由 terrain_pbr.gdshader 定：
	##   R = 鋪石板　G = 田（農地）　B = 巨觀明暗　A = 夯土
	## ⚠ 第一版把 G 拿去當「森林」用，結果全鎮外圈鋪成一圈黃田 ——
	## 而**農田系統是規格裡明確延後的獨立階段**，這輪不該有田。G 一律 0。
	##
	## 石板範圍在整合輪重新定案（使用者：商業核心讀成郊區）。
	## 舊規則「只留村心 r<38」實測**只涵蓋 169 棟町家裡的 4 棟** —— 等於
	## 整個市街都是夯土，難怪不密。新規則綁 `_commerce()`：**有店的地方
	## 就有石板**，跟暖簾／提灯同一條梯度，過渡才有理由（住宅帶轉夯土、
	## 村緣轉土與草），而不是一個任意半徑。
	var road := _road_info(x, z)
	# 店前鋪面：把路緣到建物正面之間的草帶補成鋪面
	road = maxf(road, _road_apron(x, z) * 0.92)
	# 河畔道：沿岸 3.2m 的步道（街區讓出來的濱水公共空間）
	var dr: float = lib.poly_dist(_river(), x, z) - (RIVER_HALF + 1.2)
	if dr > 0.0 and dr < 3.2:
		road = maxf(road, 0.72)
	# 河灘：水邊一圈砂石，水面與草地之間要有過渡
	var rd: float = lib.poly_dist(_river(), x, z)
	var shore := 1.0 - smoothstep(RIVER_HALF * 0.7, RIVER_HALF * 1.9, rd)
	var r := Vector2(x, z - PLAZA.y).length()
	var stone_k := clampf(_commerce(Vector2(x, z)) * 1.55 - 0.16, 0.0, 1.0)
	var path_w: float = maxf(road, shore)
	var dirt: float = path_w * (1.0 - stone_k)
	path_w *= stone_k
	var macro := clampf(_nh.get_noise_2d(x * 0.4, z * 0.4) * 0.5 + 0.5, 0.0, 1.0)
	# 街區內側（房子與房子之間的院子）也是踏實的土
	var court := 0.0
	if road < 0.15 and r < CORE:
		court = clampf(0.34 - r / 700.0, 0.0, 0.34) \
			* clampf(_n2.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	return Color(path_w, 0.0, macro, maxf(dirt, court))


func _build_roads() -> void:
	var rv := _river()
	# 主要道路。東西向橫街碰到河就在西岸河畔道收尾（除了有橋的兩條）。
	_roads.append({"pts": [Vector2(0, -240), Vector2(0, 250)], "w": 8.0})       # 本通
	_roads.append({"pts": [Vector2(-190, 30), Vector2(200, 30)], "w": MAIN_EW_W})
	for spec in [[-135.0, false], [-80.0, true], [85.0, false], [140.0, true]]:
		var z: float = spec[0]
		var bridged: bool = spec[1]
		var rx := _nearest_river_pt(Vector2(0, z)).x
		for p in rv:
			if absf(p.y - z) < 2.5:
				rx = p.x
				break
		if bridged:
			_roads.append({"pts": [Vector2(-150, z), Vector2(150, z)], "w": 5.0})
		else:
			_roads.append({"pts": [Vector2(-150, z), Vector2(rx - BANK_PATH, z)], "w": 5.0})
			_roads.append({"pts": [Vector2(rx + BANK_PATH, z), Vector2(150, z)], "w": 5.0})
	for x in [-156.0, -104.0, -52.0, 104.0]:
		_roads.append({"pts": [Vector2(x, -190), Vector2(x, 195)], "w": 4.5})
	# x=52 在 z∈[125,190] 整段落在河裡（最近 3.85m，河半寬 7）→ 截斷在 118，
	# 南段的通行由西岸河畔道接手。
	_roads.append({"pts": [Vector2(52, -190), Vector2(52, 118)], "w": 4.5})
	# 西南門引道
	_roads.append({"pts": [Vector2(-104, 92), Vector2(-172, 92)], "w": 4.0})
	# 北門引道（本通往北出村）
	_roads.append({"pts": [Vector2(0, -240), Vector2(0, -215)], "w": 6.0})


# ── 護岸（MultiMesh）──
# 全長 619m、154 段 × 2 岸 = 308 個候選；扣掉橋位、鵜呑亭與村外之後
# 實際約 119 個實例。一段一個 MeshInstance3D 的話就是 119 個節點。

func _build_revetment() -> void:
	var pts := _river()
	var list: Array = []
	var bm := BoxMesh.new()
	# ⚠ 高度要夠深才埋得住。護岸擺在離河心 7.25m，而 river_carve 的坡在
	# 那裡已經把地面挖到 bank_h - 1.37m —— 第一版用 1.15m 高、錨在 bank_h，
	# 結果整條護岸**浮在被挖空的岸坡上方**，1.15m 全露出來，讀成水泥擋牆。
	# 改成「頂緣固定在 bank_h + 0.08、往下埋 2.2m」，底一定在碎坡之下。
	bm.size = Vector3(0.5, 2.2, 4.2)
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var tv := b - a
		var ln := tv.length()
		if ln < 0.01:
			continue
		tv /= ln
		var nrm := Vector2(-tv.y, tv.x)
		for sd in [-1.0, 1.0]:
			var mid: Vector2 = (a + b) * 0.5 + nrm * sd * (RIVER_HALF + 0.25)
			var skip := false
			for br in BRIDGES:
				if absf(mid.x - br.x) < 8.0 and absf(mid.y - br.z) < 8.0:
					skip = true
			# 鵜呑亭自帶石垣（川床底下那段），產生器的護岸讓開免得兩片共面
			if mid.distance_to(_uno_pos) < 22.0:
				skip = true
			# 砌石護岸是**城鎮裡的河**才有的東西；出了村心就是自然土岸。
			# 一路砌到圖緣會讓整條河讀成人工渠道。
			if Vector2(mid.x, mid.y - PLAZA.y).length() > 132.0:
				skip = true
			if skip:
				continue
			var bs := Basis(Vector3.UP, atan2(tv.x, tv.y))
			bs = bs * Basis.from_scale(Vector3(1.0, 1.0, (ln + 0.25) / 4.2))
			list.append(Transform3D(bs,
				Vector3(mid.x, bank_h(mid.x, mid.y) - 1.02, mid.y)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = lib.make_multimesh(bm, list, [], OUT_DIR + "gen/mm_revetment.res")
	# ⚠ 0.42 的灰在直射陽光下讀成水泥防洪牆（引擎內截圖看出來的）。
	# 砌石護岸要暗、要偏冷；只露出 0.22m，其餘埋進岸裡。
	mmi.material_override = lib.flat_mat("岸石", Color(0.205, 0.198, 0.183), 0.96)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 160.0
	lib.add(_root, mmi, "護岸")
	_audit.append("護岸 %d 段 → 1 個 MultiMesh（一段一節點的話是 %d 個節點）"
		% [list.size(), list.size()])


func _plug_river_mouths() -> void:
	## lib.boundary 的空氣牆只擋 y∈[0,40]，河床在圖緣是 -2.5~-3.5m ——
	## 玩家可以從河口走出地圖。兩片小牆把河口補起來。
	var body := StaticBody3D.new()
	body.name = "河口封堵"
	_root.add_child(body)
	body.owner = _root
	for p in [_river()[0], _river()[_river().size() - 1]]:
		var sh := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(RIVER_HALF * 2.0 + 10.0, 10.0, 1.0)
		sh.shape = bx
		sh.position = Vector3(p.x, -3.0, clampf(p.y, -(HALF - 1.5), HALF - 1.5))
		body.add_child(sh)
		sh.owner = _root


# ── 橋 ──

func _build_bridges() -> void:
	var g := lib.add(_root, Node3D.new(), "橋")
	for b in BRIDGES:
		var mesh: Mesh = lib.prop_mesh(String(_mods[b.kind]["glb"]))
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(b.x, bank_h(b.x, b.z) + 0.02, b.z)
		mi.rotation.y = b.yaw
		# ⚠ own_colliders=true 之下，main.gd 只給名為 "Terrain" 或帶
		# needs_trimesh 的 MeshInstance3D 做碰撞 —— 沒這行的話橋是可以穿的
		# （上一輪的 townlab 就是這樣，全場只有一個空氣牆 StaticBody3D）。
		mi.set_meta("needs_trimesh", true)
		lib.add(g, mi, "%s_%d" % [b.kind, int(b.z)])
		_dump.append([b.kind, b.x, mi.position.y, b.z, b.yaw])
		_reserved.append(_obb_of([b.kind, b.x, 0.0, b.z, b.yaw]))
	_audit.append("橋 %d 座（主橋 12m + 小橋 4.2m ×2），全部帶 needs_trimesh" % BRIDGES.size())


# ── 地標佔位 + 鵜呑亭 ──

func _build_landmark_stubs() -> void:
	## ⚠ 第一版是無屋頂的素色方塊 —— 引擎內截圖讀成一排倉庫，把整個
	## 天際線壓垮。佔位也要有屋頂：切妻 + 瓦色，剪影才跟町家同一個語彙。
	## （內容仍然不做 —— 地標不在街區重設計的範圍內。）
	var g := lib.add(_root, Node3D.new(), "地標佔位")
	var lm_body := StaticBody3D.new()
	lm_body.name = "地標碰撞"
	_root.add_child(lm_body)
	lm_body.owner = _root
	var mw := lib.flat_mat("佔位牆", Color(0.575, 0.560, 0.520), 0.92)
	var mr := lib.flat_mat("佔位瓦", Color(0.150, 0.163, 0.192), 0.88)
	for L in LANDMARKS:
		var y: float = bank_h(L.x, L.z)
		# 量體與佔地分開：佔地（w/d）是保留區，量體（bw/bd）才是畫出來的箱。
		var bw: float = float(L.get("bw", L.w))
		var bd: float = float(L.get("bd", L.d))
		var wall_h: float = maxf(L.h * 0.62, L.h - bd * 0.30)
		# 每座地標**自己一個子群組**，牆體命名「屋身」：
		# (a) check_map 的建物判定看「群組直下有沒有貼地構件」——
		#     以前七座全掛在同一個群組、名字又不含關鍵字 → 佔位對體檢隱形；
		#     而且就算命中，七座會被併成一棟橫跨全鎮的巨型 AABB。
		# (b) gable_roof 的子節點名是固定的（屋根坡_0…），同一個父節點下
		#     蓋七次會被 Godot 自動改名成 @MeshInstance3D@8 之類 —— 分開的
		#     父節點各自命名空間，名字保得住。
		var gl := lib.add(g, Node3D.new(), L.n)
		lib.box(gl, "屋身", Vector3(bw, wall_h, bd), mw,
			Vector3(L.x, y + wall_h * 0.5, L.z))
		lib.gable_roof(gl, y + wall_h, bw + 1.6, bd + 1.6,
			atan2(L.h - wall_h, bd * 0.5), 0.22, mr, mr,
			Vector3(L.x, 0.0, L.z))
		# 保留區用**佔地**（w/d）：町家不准蓋進院子，不是只避開主屋
		_reserved.append([Vector2(L.x, L.z), Vector2(1, 0), Vector2(0, 1),
			(L.w + 1.6) * 0.5, (L.d + 1.6) * 0.5, L.n])
		# 佔位也要有碰撞 —— 沒有的話玩家直接穿過地標
		var sh := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(bw, wall_h, bd)
		sh.shape = bx
		sh.position = Vector3(L.x, y + wall_h * 0.5, L.z)
		lm_body.add_child(sh)
		sh.owner = _root
	_audit.append("地標佔位 %d 座（本輪不重做內容，只佔地 + 給天際線量體）"
		% LANDMARKS.size())


func _build_unomitei() -> void:
	## 使用者決策：鵜呑亭不搬遷，改成臨河食堂。
	## 正面（-y 面）朝河，屋身往河延伸 → 川床懸在水面上。
	var rp := _nearest_river_pt(UNOMITEI_ANCHOR)
	var t := river_tangent(rp)
	var n := Vector2(-t.y, t.x)
	if n.dot(UNOMITEI_ANCHOR - rp) < 0.0:
		n = -n                                   # 法線朝陸地（西岸）
	# ⚠ 模組的 **-y 面是街側**（正面），屋身往 +y 長，川床在最遠端。
	# 所以正面要朝**離開河的方向**（= n），屋身才會往河長、川床才會懸到
	# 水上。第一版寫成 atan2(-n.x,-n.y)（正面朝河），屋身整個往陸地長，
	# 川床落在離河 20m 的草地上 —— 引擎內截圖才看出來。
	# 距離：原點（街側正面）離河心 18.5m
	#   → 主屋河側牆 18.5-9.2 = 9.3（岸 7.0 外側 2.3m）
	#   → 川床 7.9 ~ 2.5（水面半寬 6.02，外側 3.5m 懸在水上）
	var pos: Vector2 = rp + n * 18.5
	var mesh: Mesh = lib.prop_mesh(String(_mods["unomitei"]["glb"]))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var yaw := atan2(n.x, n.y)                   # 正面（街側）朝 n = 背對河
	mi.position = Vector3(pos.x, bank_h(pos.x, pos.y), pos.y)
	mi.rotation.y = yaw
	mi.set_meta("needs_trimesh", true)
	lib.add(_root, mi, "鵜呑亭")
	_dump.append(["unomitei", pos.x, mi.position.y, pos.y, yaw])
	_reserved.append(_obb_of(["unomitei", pos.x, 0.0, pos.y, yaw]))
	var deck_out: Vector2 = pos - n * 16.0
	_audit.append("鵜呑亭（臨河食堂）@(%.1f,%.1f) yaw %.1f°　川床外緣離河心 %.1fm"
		% [pos.x, pos.y, rad_to_deg(yaw), deck_out.distance_to(rp)]
		+ "（水面半寬 %.1f → 懸在水上 %.1fm）、離主橋 %.0fm"
		% [RIVER_HALF * 0.86, RIVER_HALF * 0.86 - deck_out.distance_to(rp),
		   pos.distance_to(Vector2(66, 30))])
	_uno_pos = pos


# ── 複合街區產生器 ──
#
# 參數：
#   frontage {a,b}   臨街線（河邊的街區這條線是**沿河樣條**取的）
#   into             進深方向（街的反向）
#   rows             [{kinds, setback|gap, jog, lateral, gap_after}]
#   wrap "L"/"U"     端部轉 90° 包角（打破矩形排排站）
#   river_end        靠河端補一棟正對河畔道的
#   spacing          鄰棟間隔（村緣帶要放大 —— 疏才是村緣）
#
# 鄰棟前後錯位 jog 逐棟累進 = 「打破格線」的最小機制：排的方向仍順著
# 街／河，但沒有兩棟真正對齊。

func _on_road(pos: Vector2, face_dir: Vector2, kind: String) -> bool:
	## 屋身（不含出簷）有沒有壓到任何路面。取四個角點對每條路量距離。
	var m: Dictionary = _mods[kind]
	var fwd := face_dir.normalized()
	var side := Vector2(fwd.y, -fwd.x)
	var hw: float = float(m["w"]) * 0.5
	var dd: float = float(m["d"])
	for sx in [-1.0, 1.0]:
		for sy in [0.0, 1.0]:
			var q: Vector2 = pos + side * sx * hw - fwd * (dd * sy)
			for r in _roads:
				if lib.poly_dist(r.pts, q.x, q.y) < r.w * 0.5 + 0.9:
					return true
	return false


func _in_reserved(kind: String, pos: Vector2, face_dir: Vector2) -> bool:
	## 這棟會不會壓到地標／鵜呑亭／橋。用跟自檢同一個 OBB 建法，
	## 所以「產生時擋掉」跟「事後檢查」量的是同一件事。
	var yaw := atan2(face_dir.x, face_dir.y)
	var r := _obb_of([kind, pos.x, 0.0, pos.y, yaw])
	for q in _reserved:
		if _obb_pen(r, q) > 0.05:
			return true
	return false


func _house(kind: String, pos: Vector2, face_dir: Vector2) -> void:
	## 村緣降級的**單一收口點**。排屋迴圈裡也做了一次（那裡要早一步做，
	## 才算得出正確的中心），但包角棟與河畔棟是直接呼叫這裡的 —— 只在
	## 迴圈裡做的話它們會漏掉（實測 r≥155 還剩兩棟 4.5m 的 f_a）。
	if kind != "machiya_e_a" and kind.begins_with("machiya") \
			and Vector2(pos.x, pos.y - PLAZA.y).length() >= 155.0:
		kind = "machiya_e_a"
	## 保留區／道路的檢查也收在這裡。排屋迴圈裡也有一份（那裡要早一步做，
	## 才知道要不要跳過這個位置繼續往前排），但**包角棟與河畔棟是直接
	## 呼叫這裡的** —— 只在迴圈裡擋的話它們會漏掉（實測一棟包角的村緣屋
	## 直接長在火見櫓的塔腳裡，穿插 2.33m）。
	if _in_reserved(kind, pos, face_dir) or _on_road(pos, face_dir, kind):
		return
	var yaw := atan2(face_dir.x, face_dir.y)
	var y := bank_h(pos.x, pos.y)
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, y, pos.y))
	if not _batch.has(kind):
		_batch[kind] = []
	_batch[kind].append(xf)
	_dump.append([kind, pos.x, y, pos.y, yaw])


func _block(seed_i: int, cfg: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i
	var a: Vector2 = cfg["frontage"]["a"]
	var b: Vector2 = cfg["frontage"]["b"]
	var along := (b - a).normalized()
	var into: Vector2 = cfg.get("into", Vector2(-along.y, along.x))
	var face := -into
	var span := a.distance_to(b)
	var rows: Array = cfg["rows"]
	var name: String = cfg.get("name", "block")
	var spacing: Array = cfg.get("spacing", [1.9, 3.0])

	# ── 角落預留 ──
	# 包角棟／河畔棟不是事後硬塞：先把端部的地讓出來，前排排到預留線就停。
	# 沒有預留的那一版，五棟包角棟全數跟排屋穿插 0.5~6.2m。
	var wrap: String = cfg.get("wrap", "")
	var wrap_kind: String = cfg.get("wrap_kind", "machiya_f_a")
	var wrap_end: String = cfg.get("wrap_end", "b")
	var reserve_a := 0.0
	var reserve_b := 0.0
	if wrap == "U" or (wrap == "L" and wrap_end == "a"):
		reserve_a = float(_mods[wrap_kind]["d"]) + 1.6
	if wrap == "U" or (wrap == "L" and wrap_end == "b"):
		reserve_b = float(_mods[wrap_kind]["d"]) + 1.6
	var river_reserve := 0.0
	if cfg.get("river_end", false):
		# 河畔棟的**屋身**朝街區內伸（正面朝河），佔掉的是 fd（含出簷進深），
		# 用面寬算會少留 ~2.5m。而且每一排都要讓，不只前排。
		river_reserve = float(_mods[cfg.get("river_kind", "machiya_f_b")]["fd"]) + 2.6
		reserve_b = maxf(reserve_b, river_reserve)

	var front_depth := 0.0
	var row_i := 0
	for row in rows:
		var kinds: Array = row["kinds"]
		var jog: Array = row.get("jog", [1.0, 2.0])
		var base_set: float = row.get("setback", 0.8)
		if row_i > 0:
			base_set = front_depth + rng.randf_range(row["gap"][0], row["gap"][1])
		var s: float = row.get("start", 0.6) + float(row.get("lateral", 0.0))
		if row_i == 0:
			s += reserve_a
		var gap_after: int = row.get("gap_after", -1)
		var set_prev := base_set
		var deepest := base_set
		var hn := 0
		while true:
			var kind: String = kinds[(hn + seed_i) % kinds.size()]
			var m: Dictionary = _mods[kind]
			var w: float = m["w"]
			var limit: float = span - 0.4 - (reserve_b if row_i == 0 else river_reserve)
			if s + w > limit:
				break
			var setb := base_set
			if hn > 0:
				var d := rng.randf_range(jog[0], jog[1]) * (1.0 if hn % 2 == 1 else -1.0)
				setb = clampf(set_prev + d, base_set, base_set + 2.2)
			set_prev = setb
			# 村緣規則在這裡收口：r≥155 一律換成 3.5m 的村緣小屋，不管街區
			# 怎麼配（規格：village-edge extreme downscale to 3.5m）。
			# ⚠ 換模組要在**算中心之前**做 —— 先用舊 w 算中心再換模組的話，
			# 房子會偏掉半個面寬差，實測造成鄰棟互穿 0.78m。
			var prov: Vector2 = a + along * (s + w * 0.5) + into * setb
			if Vector2(prov.x, prov.y - PLAZA.y).length() >= 155.0 \
					and kind != "machiya_e_a":
				kind = "machiya_e_a"
				m = _mods[kind]
				w = m["w"]
			var center: Vector2 = a + along * (s + w * 0.5) + into * setb
			# ⚠ 產生器原本從來沒把房子跟**路**或**保留區**比對過 —— 實測
			# 4 棟屋身壓在路面上（最深的前牆離 x=52 路心只有 0.70m），
			# 還有町家長進鵜呑亭與主橋裡。這裡逐棟擋掉，擋掉就跳過這個位置。
			if _on_road(center, face, kind) or _in_reserved(kind, center, face):
				s += w + rng.randf_range(spacing[0], spacing[1])
				hn += 1
				continue
			_house(kind, center, face)
			deepest = maxf(deepest, setb + float(m["d"]) + 1.0)
			# 鄰棟間隔 ≥1.9：兩側出簷各 0.85，1.7 以下屋簷互相穿插，
			# 同模組鄰棟的簷還同高共面（本專案的老病）。
			s += w + rng.randf_range(spacing[0], spacing[1])
			if hn == gap_after:
				s += rng.randf_range(6.5, 8.0)      # 視線缺口
			hn += 1
		front_depth = deepest
		row_i += 1

	if wrap != "":
		var ends: Array = []
		if wrap == "U":
			ends = [[a, -1.0], [b, 1.0]]
		else:
			ends = [[b, 1.0]] if wrap_end == "b" else [[a, -1.0]]
		for epair in ends:
			var e: Vector2 = epair[0]
			var sgn: float = epair[1]
			if sgn > 0 and cfg.get("river_end", false):
				continue                              # b 端讓給河畔棟
			var mw: Dictionary = _mods[wrap_kind]
			var setb0: float = rows[0].get("setback", 0.8)
			var pos: Vector2 = e + along * sgn * 0.3 + into * (setb0 + float(mw["w"]) * 0.5)
			_house(wrap_kind, pos, along * sgn)

	if cfg.get("river_end", false):
		# ⚠ 從**河道最近點**起算，不是從錨點 —— 錨點本身離河 4.7~9.1m，
		# 從錨點加偏移會把房子推到離河 16~21m 還壓進後排。
		var kind2: String = cfg.get("river_kind", "machiya_f_b")
		var rp := _nearest_river_pt(cfg["river_anchor"])
		var t := river_tangent(rp)
		var n := Vector2(-t.y, t.x)
		if n.dot(Vector2(cfg["river_anchor"]) - rp) < 0.0:
			n = -n
		_house(kind2, rp + n * (RIVER_HALF + 4.9), -n)


func _build_towers() -> void:
	## 超現實地標塔。一次性、單一實例 → MeshInstance3D（不是 MultiMesh）。
	## 一併登記成保留區，町家才不會排到塔腳下。
	var g := lib.add(_root, Node3D.new(), "地標塔")
	var body := StaticBody3D.new()
	body.name = "地標塔碰撞"
	_root.add_child(body)
	body.owner = _root
	for t in TOWERS:
		var m: Dictionary = _mods[t.kind]
		var mi := MeshInstance3D.new()
		mi.mesh = lib.prop_mesh(String(m["glb"]))
		mi.position = Vector3(t.x, bank_h(t.x, t.z), t.z)
		mi.rotation.y = t.yaw
		mi.set_meta("needs_trimesh", true)
		lib.add(g, mi, t.kind)
		_dump.append([t.kind, t.x, mi.position.y, t.z, t.yaw])
		_reserved.append(_obb_of([t.kind, t.x, 0.0, t.z, t.yaw]))
		# 塔身太細，trimesh 之外再給一個實心碰撞箱（不然玩家會卡進格柵裡）
		var sh := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(float(m["fw"]) * 0.55, float(m["h"]), float(m["fd"]) * 0.55)
		sh.shape = bx
		sh.position = Vector3(t.x, mi.position.y + float(m["h"]) * 0.5, t.z)
		sh.rotation.y = t.yaw
		body.add_child(sh)
		sh.owner = _root
		_audit.append("地標塔 %s @(%.1f,%.1f) 高 %.1fm（%s）"
			% [t.kind, t.x, t.z, float(m["h"]), t.why])


func _build_blocks() -> void:
	_block(201, {
		"name": "西外・本通北",
		"frontage": {"a": Vector2(-109.00, 22.80), "b": Vector2(-151.00, 22.80)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "b",
	})
	_block(202, {
		"name": "西外・本通南",
		"frontage": {"a": Vector2(-151.00, 37.20), "b": Vector2(-109.00, 37.20)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "a",
	})
	_block(203, {
		"name": "稗田南町",
		"frontage": {"a": Vector2(-99.00, 37.20), "b": Vector2(-57.00, 37.20)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "b",
	})
	_block(101, {
		"name": "西北(R1)",
		"frontage": {"a": Vector2(10.00, 22.80), "b": Vector2(52.00, 22.80)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		# river_end 拿掉：這段西岸已經給鵜呑亭了（兩者都被推到同一條河法線上，
		# 彼此完全不知道對方存在 → 實測互穿 6.8m）。臨河的門面由鵜呑亭擔。
		"wrap": "L", "wrap_end": "a",
	})
	_block(103, {
		"name": "東北・高壓",
		"frontage": {"a": Vector2(77.60, 23.40), "b": Vector2(100.60, 23.40)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_b_a", "machiya_b_b"], "setback": 0.4, "jog": [1.0, 1.8]},
				{"kinds": ["machiya_f_a", "machiya_f_b"], "gap": [2.6, 3.6], "lateral": 4.2},
		],
	})
	_block(206, {
		"name": "東・本通北",
		"frontage": {"a": Vector2(107.65, 22.80), "b": Vector2(151.50, 22.80)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "b",
	})
	_block(208, {
		"name": "東・本通南",
		"frontage": {"a": Vector2(107.65, 37.20), "b": Vector2(151.50, 37.20)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "b",
	})
	_block(209, {
		"name": "本通西・北",
		"frontage": {"a": Vector2(-5.50, -129.90), "b": Vector2(-5.50, -83.90)},
		"into": Vector2(-1.0000, 0.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "a",
	})
	_block(210, {
		"name": "本通東・北",
		"frontage": {"a": Vector2(5.50, -83.90), "b": Vector2(5.50, -129.70)},
		"into": Vector2(1.0000, 0.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "b",
	})
	_block(211, {
		"name": "本通西・南",
		"frontage": {"a": Vector2(-5.50, 90.10), "b": Vector2(-5.50, 136.10)},
		"into": Vector2(-1.0000, 0.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "a",
	})
	_block(212, {
		"name": "本通西・南外",
		"frontage": {"a": Vector2(-5.50, 143.90), "b": Vector2(-5.50, 186.00)},
		"into": Vector2(-1.0000, 0.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
	})
	_block(213, {
		"name": "本通東・南外",
		"frontage": {"a": Vector2(5.50, 186.00), "b": Vector2(5.50, 143.90)},
		"into": Vector2(1.0000, 0.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
		],
	})
	_block(214, {
		"name": "本通西・北端",
		"frontage": {"a": Vector2(-5.50, -162.00), "b": Vector2(-5.50, -138.90)},
		"into": Vector2(-1.0000, 0.0000),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.8]},
		],
	})
	_block(215, {
		"name": "本通東・北端",
		"frontage": {"a": Vector2(5.50, -138.90), "b": Vector2(5.50, -162.00)},
		"into": Vector2(1.0000, 0.0000),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.8]},
		],
	})
	_block(216, {
		"name": "北在・西",
		"frontage": {"a": Vector2(-55.65, -83.90), "b": Vector2(-97.00, -83.90)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.8]},
		],
	})
	_block(217, {
		"name": "北在・西外",
		"frontage": {"a": Vector2(-107.65, -83.90), "b": Vector2(-142.00, -83.90)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.8]},
		],
	})
	_block(218, {
		"name": "寺子屋西町",
		"frontage": {"a": Vector2(-97.00, -76.10), "b": Vector2(-57.00, -76.10)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "b",
	})
	_block(219, {
		"name": "西外・北町",
		"frontage": {"a": Vector2(-107.65, -28.65), "b": Vector2(-145.00, -28.65)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
		],
	})
	_block(220, {
		"name": "西外・南町",
		"frontage": {"a": Vector2(-145.00, -21.35), "b": Vector2(-107.65, -21.35)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
		],
	})
	_block(221, {
		"name": "市場西・北",
		"frontage": {"a": Vector2(-55.65, 81.10), "b": Vector2(-97.00, 81.10)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
		],
	})
	_block(222, {
		"name": "市場西・南",
		"frontage": {"a": Vector2(-97.00, 88.90), "b": Vector2(-55.65, 88.90)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "a",
	})
	_block(223, {
		"name": "西外・南",
		"frontage": {"a": Vector2(-107.65, 136.10), "b": Vector2(-149.00, 136.10)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.8]},
		],
	})
	_block(224, {
		"name": "西外・在",
		"frontage": {"a": Vector2(-142.00, 143.90), "b": Vector2(-107.65, 143.90)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.8]},
		],
	})
	_block(225, {
		"name": "南町・西北",
		"frontage": {"a": Vector2(-55.65, 136.10), "b": Vector2(-97.00, 136.10)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
		],
	})
	_block(226, {
		"name": "南在・西",
		"frontage": {"a": Vector2(-97.00, 143.90), "b": Vector2(-55.65, 143.90)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.8]},
		],
	})
	_block(227, {
		"name": "東外・北町",
		"frontage": {"a": Vector2(107.65, -28.65), "b": Vector2(149.00, -28.65)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
		],
	})
	_block(228, {
		"name": "東外・南町",
		"frontage": {"a": Vector2(149.00, -21.35), "b": Vector2(107.65, -21.35)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
		],
	})
	_block(229, {
		"name": "東外・北",
		"frontage": {"a": Vector2(107.65, 81.10), "b": Vector2(149.00, 81.10)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
		],
	})
	_block(230, {
		"name": "東外・南",
		"frontage": {"a": Vector2(149.00, 88.90), "b": Vector2(107.65, 88.90)},
		"into": Vector2(0.0000, 1.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
		],
	})
	_block(231, {
		"name": "東外・在",
		"frontage": {"a": Vector2(107.65, 136.10), "b": Vector2(145.00, 136.10)},
		"into": Vector2(0.0000, -1.0000),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.8]},
		],
	})
	_block(302, {
		"name": "河西・北町",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(70.29, -129.00), "b": Vector2(65.55, -84.00)},
		"into": Vector2(-0.9945, -0.1048),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.6]},
		],
		"riverside": true,
	})
	_block(303, {
		"name": "河西・橋北",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(49.51, -21.35), "b": Vector2(50.32, 1.00)},
		"into": Vector2(-0.9993, 0.0364),
		"rows": [
				{"kinds": ["machiya_f_a"], "setback": 0.8, "jog": [1.0, 1.6]},
		],
		"riverside": true,
	})
	_block(305, {
		"name": "河西・橋南",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(63.30, 58.00), "b": Vector2(64.28, 82.00)},
		"into": Vector2(-0.9992, 0.0407),
		"rows": [
				{"kinds": ["machiya_f_a"], "setback": 0.8, "jog": [1.0, 1.6]},
		],
		"riverside": true,
	})
	_block(104, {
		"name": "東南・低開",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(83.32, 41.80), "b": Vector2(90.03, 63.80)},
		"into": Vector2(0.9565, -0.2917),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 2.2, "jog": [1.2, 2.0]},
		],
		"riverside": true,
	})
	_block(307, {
		"name": "河東・橋南",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(90.02, 64.01), "b": Vector2(89.78, 80.01)},
		"into": Vector2(0.9999, 0.0154),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.6]},
		],
		"riverside": true,
	})
	_block(308, {
		"name": "河東・南",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(87.17, 88.94), "b": Vector2(75.89, 122.04)},
		"into": Vector2(0.9465, 0.3227),
		"rows": [
				{"kinds": ["machiya_f_a"], "setback": 0.8, "jog": [1.0, 1.6]},
		],
		"riverside": true,
	})
	_block(309, {
		"name": "河西・最南",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(44.30, 145.97), "b": Vector2(43.59, 173.97)},
		"into": Vector2(-0.9997, -0.0255),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.6]},
		],
		"riverside": true,
	})
	_block(310, {
		"name": "河東・最南",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(70.24, 143.90), "b": Vector2(68.67, 172.00)},
		"into": Vector2(0.9984, 0.0557),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.6]},
		],
		"riverside": true,
	})
	_block(311, {
		"name": "河東・鈴奈庵對岸",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(88.15, -76.10), "b": Vector2(74.53, -42.00)},
		"into": Vector2(0.9287, 0.3707),
		"rows": [
				{"kinds": ["machiya_f_a"], "setback": 0.8, "jog": [1.0, 1.6]},
		],
		"riverside": true,
	})
	_block(312, {
		"name": "河東・橋北",   # 臨河：frontage ∥ 河脊
		"frontage": {"a": Vector2(73.36, -21.35), "b": Vector2(73.92, -6.00)},
		"into": Vector2(0.9993, -0.0370),
		"rows": [
				{"kinds": ["machiya_f_a"], "setback": 0.8, "jog": [1.0, 1.6]},
		],
		"riverside": true,
	})
	var nh := 0
	for e in _dump:
		if String(e[0]).begins_with("machiya"):
			nh += 1
	_audit.append("街區 → 町家 %d 棟" % nh)


# ── 重疊自驗（OBB / SAT，含出簷）──

func _obb_of(e: Array) -> Array:
	## 從模組的 **Godot 局部 bbox（gbox）** 建世界 OBB。
	## ⚠ 舊版只吃 fw/fd 又假設「原點在正面、往後長 fd」—— 那只對町家成立。
	## 橋的原點在中心、鵜呑亭的川床往後伸 16m 而 fd 當時還寫成 10.9，
	## 於是自檢對它們**結構性全盲**：印著「0 穿插 ✓」，實際有 3 對互穿
	## （鵜呑亭 × 河畔町家 6.8m、鵜呑亭 × 主橋 2.3m）。gbox 一律照實量。
	var m: Dictionary = _mods[e[0]]
	var gb: Array = m.get("gbox", [-float(m["fw"]) * 0.5, float(m["fw"]) * 0.5,
		-float(m["fd"]) + 0.85, 0.85])
	var yaw: float = e[4]
	var ax := Vector2(cos(yaw), -sin(yaw))          # Basis(UP,yaw).x 在 XZ 上
	var az := Vector2(sin(yaw), cos(yaw))           # Basis(UP,yaw).z
	var cx: float = (float(gb[0]) + float(gb[1])) * 0.5
	var cz: float = (float(gb[2]) + float(gb[3])) * 0.5
	var c := Vector2(e[1], e[3]) + ax * cx + az * cz
	return [c, ax, az, (float(gb[1]) - float(gb[0])) * 0.5,
		(float(gb[3]) - float(gb[2])) * 0.5, e[0]]


func _assert_no_overlap() -> void:
	## 逐對 OBB（SAT）—— **不再只檢查町家**：橋與鵜呑亭一起進來。
	var rects: Array = []
	for e in _dump:
		rects.append(_obb_of(e))
	var cell := 26.0
	var grid := {}
	for i in rects.size():
		var c: Vector2 = rects[i][0]
		var rr: float = maxf(rects[i][3], rects[i][4])
		var span := int(ceil(rr / cell))
		var gx := int(floor(c.x / cell))
		var gz := int(floor(c.y / cell))
		for dx in range(-span - 1, span + 2):
			for dz in range(-span - 1, span + 2):
				var k := "%d,%d" % [gx + dx, gz + dz]
				if not grid.has(k):
					grid[k] = []
				grid[k].append(i)
	var bad := 0
	var seen := {}
	for k in grid:
		var ids: Array = grid[k]
		for ii in ids.size():
			for jj in range(ii + 1, ids.size()):
				var i: int = ids[ii]
				var j: int = ids[jj]
				var pk := "%d_%d" % [min(i, j), max(i, j)]
				if seen.has(pk):
					continue
				seen[pk] = true
				var pen := _obb_pen(rects[i], rects[j])
				if pen > 0.05:
					bad += 1
					if bad <= 8:
						push_error("重疊：%s#%d × %s#%d 穿插 %.2fm"
							% [rects[i][5], i, rects[j][5], j, pen])
	if bad == 0:
		_audit.append("重疊檢查：%d 件（町家＋橋＋鵜呑亭，含出簷 OBB）—— 0 穿插 ✓"
			% rects.size())
	else:
		_audit.append("⚠ 重疊檢查：%d 對穿插 —— 佈局有 bug" % bad)


func _obb_pen(ra: Array, rb: Array) -> float:
	var pen := 1e18
	for r in [ra, rb]:
		for k in [1, 2]:
			var axis: Vector2 = r[k]
			var ca: float = Vector2(ra[0]).dot(axis)
			var cb: float = Vector2(rb[0]).dot(axis)
			var ea: float = absf(Vector2(ra[1]).dot(axis)) * ra[3] \
				+ absf(Vector2(ra[2]).dot(axis)) * ra[4]
			var eb: float = absf(Vector2(rb[1]).dot(axis)) * rb[3] \
				+ absf(Vector2(rb[2]).dot(axis)) * rb[4]
			var ov := ea + eb - absf(ca - cb)
			if ov <= 0.0:
				return 0.0
			pen = minf(pen, ov)
	return pen


func _emit_batches() -> void:
	var g := lib.add(_root, Node3D.new(), "町家")
	var total := 0
	var names := _batch.keys()
	names.sort()
	for kind in names:
		var list: Array = _batch[kind]
		var mesh: Mesh = lib.prop_mesh(String(_mods[kind]["glb"]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(mesh, list, [], OUT_DIR + "gen/mm_%s.res" % kind)
		lib.add(g, mmi, "MM_%s" % kind)
		total += list.size()
	_audit.append("町家 %d 棟 / %d 種模組（%d draw call）" % [total, names.size(), names.size()])


func _build_collision() -> void:
	## ⚠ MultiMeshInstance3D **不是** MeshInstance3D，永遠拿不到 trimesh 碰撞。
	## 上一輪的 townlab 全場只有一個空氣牆 StaticBody3D，21 棟町家全部可以穿。
	## 這裡逐棟給一個旋轉過的 BoxShape3D：300 棟 = 1 個 StaticBody3D +
	## 300 個 CollisionShape3D，0 draw call。
	var body := StaticBody3D.new()
	body.name = "町家碰撞"
	_root.add_child(body)
	body.owner = _root
	var n := 0
	for e in _dump:
		if not String(e[0]).begins_with("machiya"):
			continue
		var m: Dictionary = _mods[e[0]]
		var yaw: float = e[4]
		var fwd := Vector2(sin(yaw), cos(yaw))
		var c := Vector2(e[1], e[3]) - fwd * (float(m["d"]) * 0.5)
		var sh := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(float(m["w"]), float(m["h"]), float(m["d"]))
		sh.shape = bx
		sh.position = Vector3(c.x, float(e[2]) + float(m["h"]) * 0.5, c.y)
		sh.rotation.y = yaw
		body.add_child(sh)
		sh.owner = _root                      # ADR-017：沒 owner 就不會存進 .tscn
		n += 1
	_audit.append("町家碰撞箱 %d 個（1 個 StaticBody3D）" % n)


func _build_env() -> void:
	## 照抄 gen_village 已驗收的環境（sky shader、曝光、glow、飽和）——
	## 換圖時氛圍要一致，不然評圖看到的是「另一個遊戲」。
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	if ResourceLoader.exists("res://assets/shaders/sky_cumulus.gdshader"):
		sm.shader = load("res://assets/shaders/sky_cumulus.gdshader")
		sky.sky_material = sm
	else:
		sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.02
	env.glow_enabled = true
	env.glow_intensity = 0.72
	env.glow_hdr_threshold = 1.25
	env.ssao_enabled = true
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.24
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_energy = 0.72
	env.fog_enabled = true
	env.fog_density = 0.0016
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.sdfgi_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	lib.add(_root, we, "WorldEnvironment")


func _perf_pass(n: Node) -> void:
	## 照抄 gen_village 的剔除／陰影分級。⚠ 那支只處理 MeshInstance3D，
	## MultiMeshInstance3D 完全不碰 —— 新鎮的 MM 要另外設（見 _build_revetment）。
	if n is MeshInstance3D and n.mesh != null:
		var nm := String(n.name)
		if not (nm.contains("Terrain") or nm.contains("Water") or nm.contains("水面")):
			var ab: AABB = n.mesh.get_aabb()
			var sc: Vector3 = n.scale.abs()
			var mx: float = maxf(maxf(ab.size.x * sc.x, ab.size.y * sc.y), ab.size.z * sc.z)
			if mx < 1.35:
				n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if mx < 0.9:
				n.visibility_range_end = 55.0
				n.visibility_range_end_margin = 8.0
				n.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			elif mx < 2.8:
				n.visibility_range_end = 100.0
				n.visibility_range_end_margin = 10.0
				n.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for c in n.get_children():
		_perf_pass(c)


# ══════════════════ 街道生活密度層（規格 §5，使用者選 B 後開工）══════════════
# 三件事：簷下吊掛（暖簾／提灯／招牌，商業→住宅梯度）、地面雜物
# （樽／籃／木箱／縁台，「商品溢到街上」）、花樹同種大群聚（稗田邸教訓）。
# ⚠ 隨機數用**自己的 RNG**，不碰 lib.rand —— 密度層在佈局之後跑，
# 消耗 lib.rand 會把 vista 的散佈整個換一副面孔（佈局本身則不受影響）。

const SAKURA_SITES := [
	{"c": Vector2(-16, -160), "r": 11.0, "n": 9},    # 北門內・西
	{"c": Vector2(20, -152), "r": 8.0, "n": 6},      # 北門內・東
	# ⚠ 舊點 (-52,34)/(148,34) 實測只塞得下 1/7 與 3/8 棵 —— 這兩區被街區
	# 填滿了。新點是從 instances.json 掃出來的實際空地（離屋/河/路 ≥10m）。
	{"c": Vector2(-86, -36), "r": 10.0, "n": 7},     # 寺子屋西・街區間空地
	{"c": Vector2(14, 226), "r": 12.0, "n": 9},      # 南口
	{"c": Vector2(-148, 84), "r": 13.0, "n": 8},     # 西南門道旁
	{"c": Vector2(174, 112), "r": 12.0, "n": 8},     # 東南岸・小橋南望
]
const GREEN_SITES := [
	{"c": Vector2(-168, -40), "r": 12.0, "n": 7},    # 西緣
	{"c": Vector2(122, 182), "r": 12.0, "n": 7},     # 東南緣
]

var _drng := RandomNumberGenerator.new()
var _dbatch := {}                # 道具名 → Array[Transform3D]
var _ddump := []                 # [kind, x, y, z, yaw]（驗證腳本用）

func _dxf(kind: String, p: Vector2, y: float, yaw: float, s: float = 1.0) -> void:
	var b := Basis(Vector3.UP, yaw)
	if s != 1.0:
		b = b * Basis.from_scale(Vector3(s, s, s))
	if not _dbatch.has(kind):
		_dbatch[kind] = []
	_dbatch[kind].append(Transform3D(b, Vector3(p.x, y, p.y)))
	_ddump.append([kind, p.x, y, p.y, yaw])

## 商業權重 0~1：廣場輻射 + 本通／主東西街走廊 + 市場周邊。
## 吊掛與雜物的密度都吃它 —— 村緣自然安靜、橋頭與本通自然熱鬧。
func _commerce(p: Vector2) -> float:
	# 第一版全圖中位數只有 0.09、>0.35 的僅 17 棟 —— 暖簾靠底率四處亂撒，
	# 「梯度」讀不出來。走廊項加寬加重、補鵜呑亭川床一帶，底率壓低
	# （梯度來自權重差，不是來自到處都有一點）。
	var w := clampf(1.0 - (p - PLAZA).length() / 120.0, 0.0, 1.0) * 0.45
	if absf(p.x) < 26.0 and p.y > -150.0 and p.y < 210.0:
		w += 0.42 * (1.0 - absf(p.x) / 26.0)
	if absf(p.y - MAIN_EW_Z) < 24.0 and p.x > -60.0 and p.x < 110.0:
		w += 0.40 * (1.0 - absf(p.y - MAIN_EW_Z) / 24.0)
	w += clampf(1.0 - (p - Vector2(-26, 57)).length() / 46.0, 0.0, 1.0) * 0.32
	w += clampf(1.0 - (p - Vector2(50, 2)).length() / 40.0, 0.0, 1.0) * 0.30
	return clampf(w, 0.0, 1.0)

func _pt_reserved(p: Vector2, margin: float) -> bool:
	for q in _reserved:
		var d: Vector2 = p - q[0]
		if absf(d.dot(q[1])) < q[3] + margin and absf(d.dot(q[2])) < q[4] + margin:
			return true
	return false

## 點離最近道路**中線帶**多近。雜物允許溢進路緣 1.3m（規格就是要
## 「商品溢到街上」），但路中要留通行走廊。
func _pt_on_road_core(p: Vector2, spill: float) -> bool:
	for r in _roads:
		if lib.poly_dist(r.pts, p.x, p.y) < r.w * 0.5 - spill:
			return true
	return false

func _river_dist(p: Vector2) -> float:
	return (_nearest_river_pt(p) - p).length()

func _build_density() -> void:
	_drng.seed = SEED + 77
	var n_noren := 0
	var n_cho := 0
	var n_kan := 0
	var n_clut := 0
	# ── 逐棟：吊掛 + 門前雜物（位置全部從立面錨點推，錨點是從 glb 量的）──
	for e in _dump:
		var kind := String(e[0])
		if not kind.begins_with("machiya"):
			continue
		var m: Dictionary = _mods[kind]
		var fac: Dictionary = m.get("facade", {})
		if fac.is_empty():
			continue
		var pos := Vector2(e[1], e[3])
		var hy: float = e[2]
		var yaw: float = e[4]
		var fwd := Vector2(sin(yaw), cos(yaw))       # 局部 +z（正面朝外）
		var ax := Vector2(cos(yaw), -sin(yaw))       # 局部 +x
		var wgt := _commerce(pos)
		var door_x: float = fac["door_x"]
		var door_w: float = fac["door_w"]
		var beam_y: float = hy + float(fac["beam_z"])
		var half_w: float = float(m["w"]) * 0.5
		# 村緣小屋是住家：吊掛機率砍半，招牌不掛
		var shop := 1.0 if kind != "machiya_e_a" else 0.45
		# 暖簾：門楣下。寬的門掛五巾藍染，窄的掛四巾柿渋
		if _drng.randf() < (0.06 + 0.85 * wgt) * shop:
			var nk := "prop_noren_a" if (door_w > 1.9 and _drng.randf() < 0.7) \
				else "prop_noren_b"
			_dxf(nk, pos + ax * door_x + fwd * 0.14, beam_y, yaw)
			n_noren += 1
		# 提灯：門兩側成對（食堂／酒屋的訊號，跟商業權重走）
		if _drng.randf() < (0.04 + 0.62 * wgt) * shop:
			for sx in [-1.0, 1.0]:
				var cx: float = door_x + sx * (door_w * 0.5 + 0.28)
				if absf(cx) > half_w - 0.35:
					continue
				_dxf("prop_chochin", pos + ax * cx + fwd * 0.24, beam_y - 0.02, yaw)
				n_cho += 1
		# 招牌：掛在離門遠的那半邊；只有商業帶掛
		if wgt > 0.28 and _drng.randf() < 0.72 * wgt * shop:
			var ks: float = 1.0 if door_x < 0.0 else -1.0
			_dxf("prop_kanban", pos + ax * (ks * (half_w - 0.6)) + fwd * 0.18,
				beam_y, yaw)
			n_kan += 1
		# 門前雜物：樽／籃堆／木箱溢到門面前 0.45~1.25m，避開門口帶。
		# 縁台靠牆擺（跟牆平行），住宅帶也會有 —— 老人家坐門口那種。
		var picks: Array[String] = []
		if _drng.randf() < 0.12 + 0.72 * wgt:
			picks.append(["prop_barrel", "prop_basket", "prop_crate"][_drng.randi() % 3])
		if _drng.randf() < 0.45 * wgt:
			picks.append(["prop_barrel", "prop_basket"][_drng.randi() % 2])
		if _drng.randf() < 0.16:
			picks.append("prop_bench")
		for pk in picks:
			var placed := false
			for _try in 6:
				var sx2: float = _drng.randf_range(-(half_w - 0.8), half_w - 0.8)
				if absf(sx2 - door_x) < door_w * 0.5 + 0.45:
					continue
				var lz: float = 0.55 if pk == "prop_bench" else _drng.randf_range(0.45, 1.25)
				var wp: Vector2 = pos + ax * sx2 + fwd * lz
				if _pt_on_road_core(wp, 1.3) or _pt_reserved(wp, 0.4) \
						or _river_dist(wp) < BANK_PATH + 0.8:
					continue
				var pyaw: float = yaw if pk == "prop_bench" \
					else _drng.randf_range(0.0, TAU)
				_dxf(pk, wp, height_at(wp.x, wp.y), pyaw)
				n_clut += 1
				placed = true
				break
			if not placed:
				continue
	# ── 花樹群聚：同種大群聚做色塊（散點單株是稗田邸點名過的反面教材）──
	var house_obbs: Array = []
	for e2 in _dump:
		if String(e2[0]).begins_with("machiya"):
			house_obbs.append(_obb_of(e2))
	var n_tree := 0
	for grp in [{"sites": SAKURA_SITES, "kinds": ["tree_sakura_a", "tree_sakura_b"]},
			{"sites": GREEN_SITES, "kinds": ["tree_round_a", "tree_round_a"]}]:
		for site in grp.sites:
			var got: Array[Vector2] = []
			var tries := 0
			while got.size() < int(site.n) and tries < int(site.n) * 10:
				tries += 1
				var ang := _drng.randf_range(0.0, TAU)
				var rad: float = sqrt(_drng.randf()) * float(site.r)
				var p: Vector2 = site.c + Vector2(cos(ang), sin(ang)) * rad
				if absf(p.x) > HALF - 6.0 or absf(p.y) > HALF - 6.0:
					continue
				if _pt_reserved(p, 1.2) or _pt_on_road_core(p, -1.6) \
						or _river_dist(p) < BANK_PATH + 1.8:
					continue
				var near_house := false
				for hb in house_obbs:
					var d: Vector2 = p - hb[0]
					if absf(d.dot(hb[1])) < hb[3] + 2.6 and absf(d.dot(hb[2])) < hb[4] + 2.6:
						near_house = true
						break
				if near_house:
					continue
				var too_close := false
				for q in got:
					if (q - p).length() < 3.4:
						too_close = true
						break
				if too_close:
					continue
				got.append(p)
				var tk: String = grp.kinds[0] if _drng.randf() < 0.65 else grp.kinds[1]
				_dxf(tk, p, height_at(p.x, p.y), _drng.randf_range(0.0, TAU),
					_drng.randf_range(0.85, 1.2))
				n_tree += 1
			if got.size() < int(site.n):
				_audit.append("⚠ 花樹群聚 (%d,%d) 只放進 %d/%d 棵（空間不夠）"
					% [int(site.c.x), int(site.c.y), got.size(), int(site.n)])
	_emit_density()
	_audit.append("密度層：暖簾 %d、提灯 %d、招牌 %d、地面雜物 %d、花樹 %d（%d draw call）"
		% [n_noren, n_cho, n_kan, n_clut, n_tree, _dbatch.size()])

## 花樹的樹冠材質：**不能**走 lib.tree_mesh 的 canopy_mat —— 那個會拿
## terrain_forest_diff 貼圖乘頂點色，粉色 × 綠貼圖 = 濁褐色。
## 花冠用無貼圖的雙面頂點色材質，樹幹照用 bark PBR。
func _sakura_mesh(glb: String) -> Mesh:
	var packed: PackedScene = load(glb)
	var node: Node = packed.instantiate()
	var mesh: Mesh = null
	var stack: Array[Node] = [node]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D:
			mesh = n.mesh
			break
	node.free()
	var petal := lib.foliage_vc_mat()
	if mesh.get_surface_count() >= 2:
		mesh.surface_set_material(0, lib.pbr("bark", "bark_cedar", 0.7))
		for s in range(1, mesh.get_surface_count()):
			mesh.surface_set_material(s, petal)
	else:
		mesh.surface_set_material(0, petal)
	return mesh

func _emit_density() -> void:
	var g := lib.add(_root, Node3D.new(), "密度層")
	var names := _dbatch.keys()
	names.sort()
	for kind in names:
		var k := String(kind)
		var mesh: Mesh
		if k.begins_with("tree_sakura"):
			mesh = _sakura_mesh("res://assets/models/%s.glb" % k)
		elif k.begins_with("tree_"):
			mesh = lib.tree_mesh("res://assets/models/%s.glb" % k)
		else:
			mesh = lib.prop_mesh("res://assets/models/%s.glb" % k, lib.vc_mat())
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(mesh, _dbatch[kind], [],
			OUT_DIR + "gen/mm_%s.res" % k)
		if not k.begins_with("tree_"):
			# 小道具：60~110m 外淡出、吊掛不投影 —— 密度層不能反過來吃掉幀率
			mmi.visibility_range_end = 110.0
			mmi.visibility_range_end_margin = 12.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if k in ["prop_noren_a", "prop_noren_b", "prop_chochin", "prop_kanban"]:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lib.add(g, mmi, "MM_%s" % k)


func _write_meta() -> void:
	## portals[0] 必須是北門：main.gd 的 _place_player 在 from_id=="" 時
	## 落在 portals[0]，所以 `--map=sato` 會站在本通上而不是村角。
	## y 由 height_at 量出來，不手抄 —— 地形換了數值就會變。
	var ports := [
		{"x": 0.0, "y": snappedf(height_at(0, -174), 0.01), "z": -174.0, "target": "trail"},
		{"x": -132.0, "y": snappedf(height_at(-132, 100), 0.01), "z": 100.0,
		 "target": "kourindou"},
		# 河畔道北端出圖 → 未來的霧之湖。target 留 null = 保留中的觸發區
		# （Area3D 照建、不畫光柱、不切場景），填上目的地就自動生效。
		_bank_portal(-286.0),
	]
	var meta := {
		"id": MAP_ID,
		"note": "人間之里 全鎮版（gen_town.gd 批量產出）。尚未取代 village —— "
			+ "trail/kourindou 的回程 portal 仍指向 village，整合是下一步。",
		"playSize": [460, 460],
		"safe": true,
		# myouren 還沒有 portal（那張圖也還沒蓋）—— 先不宣告，免得連通圖說謊
		"connections": ["trail", "kourindou", "lake"],
		"portals": ports,
		"colliders": [],
	}
	var f := FileAccess.open("res://data/%s.meta.json" % MAP_ID, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, " "))
	f.close()
	print("wrote data/%s.meta.json" % MAP_ID)


func _bank_portal(z: float) -> Dictionary:
	## 河畔道上的保留觸發區。⚠ x 要用**該 z 的河道最近點**算，不是隨手挑
	## 一個樣條索引（舊版拿 _river()[2]，那點在 z=-294，差了 8m）。
	var rp := _nearest_river_pt(Vector2(0, z))
	var best := rp
	var bd := 1e18
	for p in _river():
		var d: float = absf(p.y - z)
		if d < bd:
			bd = d
			best = p
	var x: float = best.x - BANK_PATH
	return {"x": snappedf(x, 0.1), "y": snappedf(height_at(x, z), 0.01),
		"z": z, "target": null}


func _write_dump() -> void:
	var out := {"note": "sato 擺位表（gen_town.gd 產出，驗證腳本用）",
		"river": [], "instances": _dump, "density": _ddump}
	for p in _river():
		out["river"].append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
	var f := FileAccess.open("res://data/%s.instances.json" % MAP_ID, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	print("wrote data/%s.instances.json（%d 實例）" % [MAP_ID, _dump.size()])
