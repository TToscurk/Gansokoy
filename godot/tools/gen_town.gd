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
# ✅ 整合 Stage 2 已完成：輸出到 **maps/village/**，這支就是 village 的
# 產生器（見下面 OUT_DIR 的說明）。中繼用的 maps/sato/ 已退場。
extends SceneTree

const TownGeometry := preload("res://tools/town/town_geometry.gd")
const TownValidation := preload("res://tools/town/town_validation.gd")
const TownAssets := preload("res://tools/town/town_assets.gd")
const TownHydrography := preload("res://tools/town/town_hydrography.gd")
const TownOutput := preload("res://tools/town/town_output.gd")
const TownEnvironment := preload("res://tools/town/town_environment.gd")
const TownConfig := preload("res://tools/town/town_config.gd")
const TownTerrain := preload("res://tools/town/town_terrain.gd")

# ══════════ 整合 Stage 2：這支現在就是 village 的產生器（2026-08-06）══════════
# 使用者定案方案 (a)：sato 產生器**直接輸出到 maps/village/**，而不是把 sato 的
# 佈局搬進 gen_village.gd。理由：這支已經帶著完整的護欄（gbox OBB 自檢、
# _on_road、_in_reserved、村緣降級、單一收口點 _house），而 gen_village.gd 的
# 佈局程式碼在換圖之後幾乎全部作廢 —— 把新護欄搬進舊架構的風險高得多。
#
# ⚠ `gen_village.gd` 從此**不可再執行**（跑了會蓋掉這裡的產出）。它留著是
# 當 MIGRATE 清單的來源：地標內容、雜物、動物、草層都還在那支裡面。
const OUT_DIR := TownConfig.OUT_DIR
const MAP_ID := TownConfig.MAP_ID
const MODULES := TownConfig.MODULES
const SEED := TownConfig.SEED

const HALF := TownConfig.HALF
const PLAZA := TownConfig.PLAZA
const CORE := TownConfig.CORE

# ── 河道脊椎（村座標：-z = 北）──
const RIVER_SPINE := TownConfig.RIVER_SPINE
const RIVER_HALF := TownConfig.RIVER_HALF
const RIVER_DEPTH := TownConfig.RIVER_DEPTH
const BANK_PATH := TownConfig.BANK_PATH          # 岸 7.0 + 護岸 1.2 + 河畔道 3.2

const MAIN_EW_Z := TownConfig.MAIN_EW_Z
const MAIN_EW_W := TownConfig.MAIN_EW_W

# 橋：主橋 12m 在 12m 主路上；兩座小橋在 z=-80 / z=140 的橫街上。
# （八條東西街都會碰到河，但規格只給 1~2 座小橋 —— 其餘東西街在西岸
#  河畔道收尾，不硬蓋橋。選這兩條是因為它們是東西兩側唯二需要的連通。）
const BRIDGES := TownConfig.BRIDGES

# ── 超現實地標塔（使用者本輪指令）──
# **只有這幾座**推到 15~20m；一般町家的階梯天際線（前排 4.5 / 後排 9~10）
# 維持不動 —— 對比才是重點，這個手法不准擴散。
# 三座都放在**街道視線的終點**，高度才會被框住而不是隨機散落：
#   火見櫓 → 本通北端（從廣場往北 162m 的直線走廊底）
#   鐘楼   → 本通南端（往南 166m）
#   水車櫓 → z=85 橫街的河岸終點；從主橋往北看也在視線裡
# 三座都刻意偏離路心 6~10m：要被框住，不是擋住路。
const TOWERS := TownConfig.TOWERS

# 鵜呑亭（臨河食堂）：正面朝河，離主橋西橋頭約 13m。
# ⚠ 錨點要離主橋夠遠：模組**含川床深 17.5m**（不是主屋的 10.9m），
# 放在 z=19 時東北角壓到橋的西引道（實測 20 處 3D 互穿，最深 0.78m）。
const UNOMITEI_ANCHOR := TownConfig.UNOMITEI_ANCHOR

# 既有地標街區：本輪**不重做**（不在街區重設計的範圍內），
# 但要把地佔起來，街區才不會排到它們身上。佔位量體也一起畫出來，
# 不然評圖時會看到八個空洞，讀不出城鎮的完整度。
# w/d = **佔地**（保留區，不准蓋町家的範圍）
# bw/bd = 佔位量體（沒寫就等於 w/d）。兩者要分開的原因見稗田邸那條。
#
# ⚠⚠ 佔地一律是**從舊 village.tscn 實測**的院落尺寸，不是估的。
# 稗田邸那次發現保留區小了 13×25m 之後，把六座全部量了一遍 —— 結果
# **四座都不夠**（鈴奈庵 −1.1、市場 −4.3、鎮守之杜 −8.4、足洗邸 −14.0×−6.5）。
# 這張表原本是憑印象填的，不是量出來的，所以錯得很一致。
# 量法：從舊 tscn 沿父鏈累加出**世界座標**再取包絡（子節點的 transform 是
# 相對父節點的，直接拿來當世界座標會量出「足洗邸 45×132m」這種鬼數字）。
# 改大保留區**不必犧牲任何町家**（實測 0 棟）—— 這是免費的修正。
# 量體（bw/bd）維持原值：佔位方塊只是暫時的，把它一起放大會讓天際線
# 在搬入真內容前先亂一次。
const LANDMARKS := TownConfig.LANDMARKS

var lib = preload("res://tools/gen_lib.gd").new()
var _root: Node3D
var _mods := {}
var _batch := {}                 # 模組名 → Array[Transform3D]
var _audit: Array[String] = []
var _dump := []                  # [kind, x, y, z, yaw]
var _ghost := []                 # PHASE 3：pilot ブロックの legacy 版（RNG 整列専用）
var _ghost_run2 := 0             # _ghost 内で 2 本目の run が始まる位置
var _ghosting := false
var _nh: FastNoiseLite
var _n2: FastNoiseLite
var _river_pts := PackedVector2Array()
var _roads := []                 # [{pts:[Vector2...], w:float}]
var _uno_pos := Vector2(1e9, 1e9)   # 鵜呑亭位置（護岸在這段要讓開）
var _reserved := []                 # 不准蓋町家的 OBB（地標／鵜呑亭／橋）

const PHASE5A_FAMILIES := TownAssets.PHASE5A_FAMILIES


func _init() -> void:
	var f := FileAccess.open(MODULES, FileAccess.READ)
	if f == null:
		push_error("讀不到 %s —— 先跑 make_town.py" % MODULES)
		quit(1)
		return
	_mods = JSON.parse_string(f.get_as_text())["modules"]
	f.close()
	for family in PHASE5A_FAMILIES:
		_mods[family] = PHASE5A_FAMILIES[family].duplicate(true)

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
	_street_rng.seed = STREET_SEED   # 街緣設施專用序列，不動地標／街區／草
	_build_gates()             # 要在鋪街區之前：門洞得先登記成保留區
	_build_landmark_stubs()
	_build_hieda_grove()
	_build_towers()
	_build_blocks()
	_apply_phase5a_pilot()
	_assert_no_overlap()
	_emit_batches()
	_build_collision()
	_build_density()
	_build_gutters()           # 要在街區之後：溝要避開橫街，也吃商業梯度
	_build_pilot_edge()        # PHASE 3.1A：回廊だけの縁石と踏石
	_build_lamps()             # 要在街區之後：燈要避開町家的 OBB
	_build_fauna()
	_build_water_plants()
	# 草層要在密度層之後：它要避開的保留區（地標／橋／鵜呑亭／門樓）到這裡才齊
	_build_grass()
	# ⚠ PHASE 3.1B：辻は**草層のあと**に建てる。_reserved に足してから草を
	#   撒くと、棄却が変わって抽選列がずれる（実測：葦が 1495→1494）。
	#   代わりに草を撒いたあとで辻の足元だけ**フィルタ**で抜く ——
	#   乱数を消費しないので、村の他の場所の草は一本も動かない。
	_build_pilot_node()        # PHASE 3.1B：北門の最初の辻（火の番の辻）
	_build_sight_nodes()       # PHASE 3.2A：本通の視線を割る 3 つの civic node
	_build_mainstreet()        # Main Street batch：塀・門・鳥居・幟・蔵・街路樹
	_build_market_quarter()    # PHASE 5A-V：市場區の機能的な設え
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
	return TownHydrography.spline(ctrl, per_seg)


func _river() -> PackedVector2Array:
	if _river_pts.is_empty():
		_river_pts = _spline(RIVER_SPINE, 14)
	return _river_pts


func _nearest_river_pt(at: Vector2) -> Vector2:
	return TownHydrography.nearest_point(_river(), at)


func river_tangent(at: Vector2) -> Vector2:
	return TownHydrography.tangent(_river(), at)


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
	# ⚠ 稗田邸的庭池以前在這裡挖碗。換成完整獨立版之後，水池是 blockout 自己
	# 烘進去的幾何（連同枯山水、飛石一起），地形不需要也不可以再挖 —— 挖了
	# 就是在一片已經有池底的網格下面再挖一個坑。
	return _flatten_yards(x, z, h)


## 院落整平：把指定地標的佔地壓成一個水平面，邊緣平滑收斂回原地形。
## ⚠ 稗田邸搬到 (−78,−164) 之後那塊地的高差是 **0.98m**（舊址只有 0.21m）——
## 40×44m 的築地塀圍牆＋庭池擺在 1m 的坡上會有一邊浮、一邊埋。
## 使用者定案方案 1：整平地形，不換位置、不加基壇。
## 手法沿用橋頭路廊那招（同一個檔案裡已驗收過的做法），只是改成矩形區域。
const YARD_FLATTEN := TownConfig.YARD_FLATTEN

func _flatten_yards(x: float, z: float, h: float) -> float:
	for y in YARD_FLATTEN:
		var hw: float = float(y.w) * 0.5
		var hd: float = float(y.d) * 0.5
		var fade: float = float(y.fade)
		var dx: float = absf(x - float(y.x)) - hw
		var dz: float = absf(z - float(y.z)) - hd
		var outside: float = maxf(maxf(dx, dz), 0.0)
		if outside > fade:
			continue
		# 目標高度 = 院落中心的原始地面（不含整平，避免遞迴）
		var target: float = bank_h(float(y.x), float(y.z))
		var k: float = 1.0 - smoothstep(0.0, fade, outside)
		h = h + (target - h) * k
	return h


func _road_info(x: float, z: float) -> float:
	## 回傳 0~1 的路面遮罩（1 = 路心）
	var best := 0.0
	for r in _roads:
		# Keep the authored road centreline and width intact, but break the perfectly
		# parallel material boundary with a slow, deterministic packed-earth wobble.
		# The perturbation only affects the 0.9 m visual blend outside the road core.
		var edge_wobble: float = _n2.get_noise_2d(x * 0.075 + 31.0,
			z * 0.075 - 19.0) * 0.42
		var d: float = lib.poly_dist(r.pts, x, z) - r.w * 0.5 - edge_wobble
		best = maxf(best, clampf(1.0 - maxf(d, 0.0) / 0.9, 0.0, 1.0))
	return best


## 店前鋪面：路緣到建物正面之間那條帶。
## ⚠ 這條帶原本是**草**，於是商業核心讀成郊區而不是密集市街（使用者指出）。
## 實測 164 棟臨街町家的正面離路緣：中位 3.85m、57 棟 ≤3m、43 棟 3~6m ——
## 所以鋪面寬度取 4.2m 就能把大部分的縫補起來，再往外就會鋪到院子裡。
## 只在村心生效：村緣的房子門口本來就該是土與草。
const APRON_W := TownConfig.APRON_W

func _road_apron(x: float, z: float) -> float:
	# ⚠ 一定要**限村心**。第一版沒加這個閘門（註解寫了「只在村心生效」，
	# 程式碼卻沒寫）→ 全鎮每條路都外擴 4.2m，空拍下整個路網糊成一片淺色。
	# 村緣的房子門口本來就該是土與草。
	var core_k := 1.0 - smoothstep(96.0, 150.0, Vector2(x, z - PLAZA.y).length())
	# PHASE 3.1A：北門回廊は広場から 114~192m 離れているので core_k が
	# 0 に落ち、**門から 55m ぶんの路肩が草のまま**だった（診断の実測）。
	# 「村縁の家の前は土と草」という元の意図は正しいが、その効き目が
	# ちょうどプレイヤーの第一印象に当たっていた。回廊だけ通す。
	if _in_pilot_xz(x, z):
		core_k = maxf(core_k, 0.92)
	if core_k <= 0.0:
		return 0.0
	var best := 0.0
	for r in _roads:
		var d: float = lib.poly_dist(r.pts, x, z) - r.w * 0.5
		if d <= 0.0:
			continue
		best = maxf(best, clampf(1.0 - d / APRON_W, 0.0, 1.0))
	return best * core_k


## PHASE 5A-V：市場區の地面。
## 診断（`shots2/market_quarter/before/mq_interior.png`）：屋台十二座が
## **芝生の上**に立っていた。市が毎日立つ場所に草は生えない —— 3.1A で
## 回廊に持ち込んだのと同じ規則を、今度は広場そのものに適用する。
## 石は広場全面には敷かない（それは近代の舗装広場になる）。本通からの
## 入口と店先の**閾**だけを石で締め、広場の本体は踏み固めた土のまま。
## 角の丸い矩形の内外判定。境界は低周波ノイズで揺らす —— 揺らさないと
## 空撮で「地面に貼った長方形のシール」に読める。
func _rrect_k(x: float, z: float, c: Vector2, h: Vector2, fade: float,
		wobble: float) -> float:
	return TownTerrain.rounded_rect(_n2, x, z, c, h, fade, wobble)


## ⚠ 修正ラウンド：一枚の大きな矩形（48×40）は空撮で「地面に貼った褐色の
## シール」に読め、北西の隅が**緑の空地から褐色の空地に変わっただけ**だった
## （round 1 の mq_elevated / market_context）。活動のある三つの帯の**和**に
## 変え、誰も歩かない隅は芝へ戻す。
func _market_ground(x: float, z: float) -> float:
	return TownTerrain.market_ground(_n2, x, z)


func _market_paving(x: float, z: float) -> float:
	return TownTerrain.market_paving(_n2, x, z)


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
	# Street hierarchy is a surface treatment, not a route change: the two civic
	# axes retain the most durable stone, secondary streets mix stone and earth,
	# and alleys read predominantly as packed earth.
	var ns_d: float = absf(x) - 4.0
	var ew_d: float = absf(z - MAIN_EW_Z) - MAIN_EW_W * 0.5
	var primary_k: float = maxf(1.0 - smoothstep(0.0, 4.5, ns_d),
		1.0 - smoothstep(0.0, 4.5, ew_d))
	var civic_stone: float = clampf(_commerce(Vector2(x, z)) * 1.30 - 0.22, 0.0, 1.0)
	var stone_k := clampf(civic_stone * 0.68 + primary_k * 0.46, 0.0, 1.0)
	var path_w: float = maxf(road, shore)
	var dirt: float = path_w * (1.0 - stone_k)
	path_w *= stone_k
	var macro := clampf(_nh.get_noise_2d(x * 0.4, z * 0.4) * 0.5 + 0.5, 0.0, 1.0)
	# 街區內側（房子與房子之間的院子）也是踏實的土
	var court := 0.0
	if road < 0.15 and r < CORE:
		court = clampf(0.34 - r / 700.0, 0.0, 0.34) \
			* clampf(_n2.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	# ── PHASE 3.1A：回廊の「踏み固め」帯 ──
	# apron だけでは足りなかった：線形の落ちが 4.2m なので、建物の足元は
	# 実測 dirt 0.23 ＝ ほぼ芝のまま（1 枚目の 3.1A レンダで判明）。
	# slice が使っている規則を持ち込む —— **毎日踏まれる所に草は生えない**。
	# 路縁（4.0）から建物列（~6.1）を越えて 9.0 まで踏み固め、11.0 で草へ。
	# ⚠ 地形は街区より先に生成されるので家の位置は参照できない。だから
	#   本通の**幾何**（frontage は x=±5.5 固定）から静的に引く。
	if _in_pilot_xz(x, z):
		dirt = maxf(dirt, 0.95 * (1.0 - smoothstep(9.0, 11.0, absf(x))))
	# ── PHASE 5A-V：市場區の土間と閾 ──
	var mk: float = _market_ground(x, z)
	if mk > 0.0:
		var mp: float = _market_paving(x, z) * mk
		dirt = maxf(dirt, mk * 0.96 * (1.0 - mp))
		path_w = maxf(path_w, mp * 0.90)
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
	# ⚠ x=−104 與 x=−52 兩條南北側街的北段截到 z=−130（原本鋪到 −190）。
	# 稗田邸換成完整獨立版之後保留區是 97×118，橫跨兩個街廓（街網東西向間距
	# 52m），這兩條會從庭院正中央穿過去。截掉的那 60m 服務 **0 棟町家**
	# ——西北象限（x<−40 且 z<−120）實測一棟都沒有，那兩段只是畫在草地上的
	# 空路。街廓是 `_block()` 用明確的 frontage 座標擺的、不吃 `_roads`，
	# 所以截這兩段不會動到任何一棟町家。
	for x in [-156.0, 104.0]:
		_roads.append({"pts": [Vector2(x, -190), Vector2(x, 195)], "w": 4.5})
	for x in [-104.0, -52.0]:
		_roads.append({"pts": [Vector2(x, -130), Vector2(x, 195)], "w": 4.5})
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
	_lm_rng.seed = SEED + 4177        # 地標內容專用序列，不動街區排列
	var n_stub := 0
	var n_real := 0
	for L in LANDMARKS:
		# 保留區**不論搬入與否都要登記** —— 它是「町家不准蓋進來」的依據
		_reserved.append([Vector2(L.x, L.z), Vector2(1, 0), Vector2(0, 1),
			(L.w + 1.6) * 0.5, (L.d + 1.6) * 0.5, L.n])
		# ⚠ 有 `build` 的地標已經搬入真內容 —— **這裡就完全不碰它**：
		# 不畫佔位方塊、不掛佔位碰撞箱。使用者明確要求驗證「舊的空殼碰撞
		# 箱真的被移除，不留殘影碰撞」，而最可靠的作法不是事後刪，是
		# **一開始就不要生**：只要 build 存在，這個迴圈連 StaticBody 都不建。
		if L.has("build"):
			var gr := lib.add(g, Node3D.new(), L.n)
			var gu := _ground_under(L.x, L.z, L.w, L.d)
			gr.position = Vector3(L.x, float(gu[0]), L.z)
			call(String(L.build), gr, float(gu[1]))
			n_real += 1
			continue
		n_stub += 1
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
		# 佔位也要有碰撞 —— 沒有的話玩家直接穿過地標
		var sh := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(bw, wall_h, bd)
		sh.shape = bx
		sh.position = Vector3(L.x, y + wall_h * 0.5, L.z)
		lm_body.add_child(sh)
		sh.owner = _root
	_audit.append("地標：真內容 %d 座、佔位 %d 座（佔位才有空殼碰撞箱）"
		% [n_real, n_stub])


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


# ══════ PHASE 3 Architecture Consolidation：legacy house の置き換え ══════
## legacy blockout（1 surface・テクスチャ 0 枚）→ production kit（6 surface）。
## 置き換え先の fw/fd は相手に合わせて作ってあるので**配置は動かない**
## （e_p 7.90/7.84 ↔ e_a 7.94/7.90、n_a 11.16/9.33 ↔ b_a 11.14/9.30、
##   n_o 12.36/9.80 ↔ b_b 12.34/9.70）。
##
## 村全体に適用（PRODUCTION MODE：Human Village — Architecture Complete）。
## `machiya_f_b` は当初「既存 kit で吸収できる」と判断したが、`_kit_pick` に
## 流すと面寬が 9.56〜11.76 でばらつき、前列の詰め込みが変わって棟数と
## 保留区の当たり判定が動く。**配置は保護対象**なので、fw 10.74 に合わせた
## `machiya_f_m` を一戸足すほうが安全側 —— 判断を変えた理由を残しておく。
const CONSOLIDATE := TownConfig.CONSOLIDATE
const CONSOLIDATE_ALL := TownConfig.CONSOLIDATE_ALL


func _consolidate(kind: String, p: Vector2) -> String:
	# ⚠ ghost pass では**絶対に**置き換えない。ghost は「pilot が無かった頃の
	#   家並み」を共有 RNG に流し直すためのものなので、ここで新モジュール
	#   （面寬が 0.2m 違う）を混ぜると ghost の家の位置がずれ、密度層と
	#   草層の抽選が村中で動く。実測：入れ忘れて葦 615 株・花樹 53 株が
	#   回廊の外で移動した。
	if _ghosting:
		return kind
	if not CONSOLIDATE.has(kind):
		return kind
	if not CONSOLIDATE_ALL and not (absf(p.x) < 40.0 and p.y >= -165.0 and p.y <= -80.0):
		return kind
	return String(CONSOLIDATE[kind])


func _house(kind: String, pos: Vector2, face_dir: Vector2) -> void:
	## 村緣降級的**單一收口點**。排屋迴圈裡也做了一次（那裡要早一步做，
	## 才算得出正確的中心），但包角棟與河畔棟是直接呼叫這裡的 —— 只在
	## 迴圈裡做的話它們會漏掉（實測 r≥155 還剩兩棟 4.5m 的 f_a）。
	if kind != "machiya_e_a" and kind.begins_with("machiya") \
			and Vector2(pos.x, pos.y - PLAZA.y).length() >= 155.0:
		kind = _consolidate("machiya_e_a", pos)
	kind = _consolidate(kind, pos)
	## 保留區／道路的檢查也收在這裡。排屋迴圈裡也有一份（那裡要早一步做，
	## 才知道要不要跳過這個位置繼續往前排），但**包角棟與河畔棟是直接
	## 呼叫這裡的** —— 只在迴圈裡擋的話它們會漏掉（實測一棟包角的村緣屋
	## 直接長在火見櫓的塔腳裡，穿插 2.33m）。
	if _in_reserved(kind, pos, face_dir) or _on_road(pos, face_dir, kind):
		return
	var yaw := atan2(face_dir.x, face_dir.y)
	var y := bank_h(pos.x, pos.y)
	if _ghosting:
		_ghost.append([kind, pos.x, y, pos.y, yaw])
		return
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, y, pos.y))
	if not _batch.has(kind):
		_batch[kind] = []
	_batch[kind].append(xf)
	_dump.append([kind, pos.x, y, pos.y, yaw])


# ══════════════════════════════════════════════════════════════════════
# PHASE 3 pilot：production kit の配分規則
# ══════════════════════════════════════════════════════════════════════
#
# slice の `LOTS` は一区画ずつ手で書いた明表。169 棟には持ち込めないので、
# ここは**規則**にする。入力は既にある `_commerce()`（広場・本通・市場の
# 商業勾配）だけ —— 新しい手動テーブルは作らない。
#
# ⚠ Phase 2 の「同一文化・不同家庭」比を守る：どの帯でも標準形 f_a が
#   過半。全部違う家を並べると町並みではなく見本市になる。
# ⚠ 後排（b_a 9.4m / b_b 9.9m）は**置き換えない**。kit の最高は f_n 6.42m で、
#   差し替えると村の第二層の天際線が 3m 下がる —— それは「kit に合わせて
#   村を作り直す」ことになり、人間の制約 1 が禁じている。kit 側の欠落として
#   報告する（9~10m の総二階／大型町家が要る）。
## PHASE 3.1A：回廊の帯（地面処理・石溝・縁石が共有する唯一の定義）。
## 本通の apron は路縁から 4.2m しか伸びないので |x|<14 で十分足り、
## z=−135 の横街まで巻き込まない（辻の設計は 3.1B の仕事）。
func _in_pilot_xz(x: float, z: float) -> bool:
	return absf(x) < 14.0 and z >= -168.0 and z <= -80.0


## pilot 回廊：本通・北門側（ブロック 209/210/214/215 の範囲）。
## ブロック ID は _dump に残らないので、幾何で判定する。
func _is_pilot(e: Array) -> bool:
	return _is_house_kind(String(e[0])) \
		and absf(float(e[1])) < 40.0 \
		and float(e[3]) >= -165.0 and float(e[3]) <= -80.0


## PHASE 3.1A：pilot ブロックの上書き。
## ⚠ **元の cfg は綺麗なまま残す**こと。ghost pass は legacy の設えを
##   そのまま再現しないと _drng の消費が変わり、zero-drift が崩れる。
##   だから「kit 化した cfg」は複製の上に作り、ghost には原本を渡す。
##
## 断面の是正（診断より）：
##   setback 0.8 → 0.0、jog の振れ幅 ±2.2 → ±0.6。
##   前排の軒先を路縁（±4.0）へ寄せ、草の帯を潰す。
##   道路幅（_roads の 8.0m）は**触らない** —— あれは本通 490m 全体、
##   つまり他の 36 ブロックに効いてしまう。街を締めるのは建物側の仕事。
func _kitify(cfg: Dictionary) -> Dictionary:
	var c: Dictionary = cfg.duplicate(true)
	c["kit"] = true
	var r0: Dictionary = c["rows"][0]
	r0["setback"] = 0.15
	r0["jog"] = [0.35, 1.1]
	r0["jog_max"] = 1.35
	return c


const KIT_FRONT := TownConfig.KIT_FRONT

func _kit_pick(p: Vector2, rng: RandomNumberGenerator) -> String:
	var w := _commerce(p)
	var r := rng.randf()
	if w > 0.55:                      # 商業核心：店が並ぶ。大店は稀
		if r < 0.18:
			return "machiya_f_o"
		if r < 0.36:
			return "machiya_w_a"
		if r < 0.48:
			return "machiya_f_n"
		if r < 0.58:
			return "machiya_f_s"
		return "machiya_f_a"
	if w > 0.30:                      # 中間帯：新しい家・妻入り・工房が混じる
		if r < 0.15:
			return "machiya_t_a"
		if r < 0.29:
			return "machiya_f_n"
		if r < 0.40:                  # 工房は商業核心ではなく縁に立つ
			return "machiya_w_a"
		return "machiya_f_a"
	if r < 0.34:                      # 外縁：仕舞屋が増える
		return "machiya_f_s"
	return "machiya_f_a"


func _frontage_pick(base_kind: String, p: Vector2,
		rng: RandomNumberGenerator) -> String:
	## Controlled family-scale variation for ordinary first-row frontages.
	## Main-street blocks already opt into the stronger `_kit_pick()` mix; this
	## quieter mix prevents secondary streets from becoming copied f_a/f_m runs.
	## Rear rows and village-edge e_p rows remain stable silhouettes.
	if base_kind != "machiya_f_a":
		return base_kind
	var r := rng.randf()
	var commerce: float = _commerce(p)
	if r < 0.12:
		return "machiya_f_s"
	if r < 0.22:
		return "machiya_w_a"
	if r < 0.29 and commerce > 0.22:
		return "machiya_t_a"
	if r < 0.36 and commerce > 0.30:
		return "machiya_f_n"
	return base_kind


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
			# PHASE 3 pilot：kit ブロックの**前排のみ**規則で選ぶ。
			# 後排は legacy のまま（上の KIT_FRONT の注記を参照）。
			var pick_pos: Vector2 = a + along * s + into * base_set
			var kind: String = _kit_pick(pick_pos, rng) \
				if (cfg.get("kit", false) and row_i == 0) \
				else kinds[(hn + seed_i) % kinds.size()]
			if row_i == 0 and not cfg.get("kit", false):
				kind = _frontage_pick(kind, pick_pos, rng)
			# PHASE 3 Consolidation：中心を算出する**前**に差し替える
			# （後だと面寬差ぶん家が偏る —— 下の村緣規則と同じ罠）
			kind = _consolidate(kind, a + along * s + into * base_set)
			var m: Dictionary = _mods[kind]
			var w: float = m["w"]
			var limit: float = span - 0.4 - (reserve_b if row_i == 0 else river_reserve)
			if s + w > limit:
				break
			var setb := base_set
			if hn > 0:
				var d := rng.randf_range(jog[0], jog[1]) * (1.0 if hn % 2 == 1 else -1.0)
				setb = clampf(set_prev + d, base_set,
					base_set + float(row.get("jog_max", 2.2)))
			set_prev = setb
			# 村緣規則在這裡收口：r≥155 一律換成 3.5m 的村緣小屋，不管街區
			# 怎麼配（規格：village-edge extreme downscale to 3.5m）。
			# ⚠ 換模組要在**算中心之前**做 —— 先用舊 w 算中心再換模組的話，
			# 房子會偏掉半個面寬差，實測造成鄰棟互穿 0.78m。
			var prov: Vector2 = a + along * (s + w * 0.5) + into * setb
			if Vector2(prov.x, prov.y - PLAZA.y).length() >= 155.0 \
					and kind != "machiya_e_a" and kind != "machiya_e_p":
				# Predominantly low edge farmhouses, punctuated by compact machiya.
				kind = "machiya_f_s" if rng.randf() < 0.26 \
					else _consolidate("machiya_e_a", prov)
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
	var c209 := {
		"name": "本通西・北",
		"frontage": {"a": Vector2(-5.50, -129.90), "b": Vector2(-5.50, -83.90)},
		"into": Vector2(-1.0000, 0.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "a",
	}
	_block(209, _kitify(c209))
	var c210 := {
		"name": "本通東・北",
		"frontage": {"a": Vector2(5.50, -83.90), "b": Vector2(5.50, -129.70)},
		"into": Vector2(1.0000, 0.0000),
		"rows": [
				{"kinds": ["machiya_f_a", "machiya_f_b"], "setback": 0.8},
				{"kinds": ["machiya_b_a", "machiya_b_b"], "gap": [2.6, 4.0], "lateral": 3.8},
		],
		"wrap": "L", "wrap_end": "b",
	}
	_block(210, _kitify(c210))
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
	var c214 := {
		"name": "本通西・北端",
		"frontage": {"a": Vector2(-5.50, -162.00), "b": Vector2(-5.50, -138.90)},
		"into": Vector2(-1.0000, 0.0000),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.8]},
		],
	}
	_block(214, _kitify(c214))
	var c215 := {
		"name": "本通東・北端",
		"frontage": {"a": Vector2(5.50, -138.90), "b": Vector2(5.50, -162.00)},
		"into": Vector2(1.0000, 0.0000),
		"rows": [
				{"kinds": ["machiya_e_a"], "setback": 0.8, "jog": [1.0, 1.8]},
		],
	}
	_block(215, _kitify(c215))
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
	# Replay the four Phase 3 pilot configs with their legacy kinds so the
	# established density RNG stream remains stable after consolidation.
	_ghosting = true
	_block(209, c209)
	_block(210, c210)
	_ghost_run2 = _ghost.size()
	_block(214, c214)
	_block(215, c215)
	_ghosting = false


func _is_house_kind(kind: String) -> bool:
	return kind.begins_with("machiya") or PHASE5A_FAMILIES.has(kind)


func _apply_phase5a_pilot() -> void:
	var replacements := [
		{"lot": Vector2(-69.6973, 78.6869), "kind": "family_small_merchant_01"},
		{"lot": Vector2(-78.8831, 80.2153), "kind": "family_small_merchant_03"},
		# ⚠ PHASE 5A-V：`asset_proof_workshop` の glb は壊れている（実測
		#   1.40×0.55×0.10）。この区画は市場區の視界（market_rows / mq_service）
		#   に入るので、見えない建物＋見えない衝突箱のまま残せない。
		#   検証済みの Phase 2A 家族に差し替える —— `family_*` は密度層が
		#   読み飛ばす kind なので、村全体の _drng は 1 回もずれない。
		{"lot": Vector2(-89.0626, 78.7573), "kind": "family_standard_machiya_02", "move": Vector2(-1.0, 0.0)},
		{"lot": Vector2(-83.2000, 89.7000), "kind": "family_standard_machiya_02"},
		{"lot": Vector2(-61.6623, 90.1261), "kind": "family_standard_machiya_03"},
		{"lot": Vector2(-75.6838, 104.7178), "kind": "family_kura_compact"},
		# ⚠ The `move` here is **along the street**, so the setback, the side of
		#   本通 and the orientation — the parts that were reviewed — are
		#   untouched. Only the along-street position shifts, by 0.8 m each,
		#   to absorb the buildings' true width: the 旅籠 is 9.90 m wide and the
		#   酒屋 13.20 m, not the 9.10 / 12.20 the table used to claim. At the
		#   old (understated) sizes these two cleared their neighbouring
		#   machiya_e_p; at the real sizes they cut into it by 0.21 m and
		#   0.29 m. That is the OBB check finally seeing the real building.
		{"lot": Vector2(-6.1034, -150.3902), "kind": "asset_proof_hatago", "move": Vector2(0.0, 1.1)},
		{"lot": Vector2(6.7199, -150.0819), "kind": "asset_proof_sake_shop", "move": Vector2(0.0, -3.5)},
		{"lot": Vector2(-5.6500, -116.7000), "kind": "family_small_merchant_01"},
	]
	var changed := 0
	for spec in replacements:
		var best := -1
		var best_d := 0.35
		for i in _dump.size():
			if not String(_dump[i][0]).begins_with("machiya"):
				continue
			var p := Vector2(float(_dump[i][1]), float(_dump[i][3]))
			var d: float = p.distance_to(spec["lot"])
			if d < best_d:
				best = i
				best_d = d
		if best < 0:
			push_error("PHASE 5A lot missing near %s" % str(spec["lot"]))
			continue
		var e: Array = _dump[best]
		var new_kind: String = spec["kind"]
		var yaw: float = float(e[4])
		if bool(_mods[new_kind].get("centered", false)):
			var fwd := Vector2(sin(yaw), cos(yaw))
			var shift: float = float(_mods[new_kind]["d"]) * 0.5 - 0.85
			e[1] = float(e[1]) - fwd.x * shift
			e[3] = float(e[3]) - fwd.y * shift
			e[2] = bank_h(float(e[1]), float(e[3]))
		var move: Vector2 = spec.get("move", Vector2.ZERO)
		e[1] = float(e[1]) + move.x
		e[3] = float(e[3]) + move.y
		e[2] = bank_h(float(e[1]), float(e[3]))
		e[0] = new_kind
		changed += 1
	var added := _market_quarter_lots()
	_batch.clear()
	for e in _dump:
		var kind := String(e[0])
		if not _is_house_kind(kind):
			continue
		var xf := Transform3D(Basis(Vector3.UP, float(e[4])),
			Vector3(float(e[1]), float(e[2]), float(e[3])))
		if not _batch.has(kind):
			_batch[kind] = []
		_batch[kind].append(xf)
	_audit.append("PHASE 5A curated pilot: %d lots replaced" % changed)
	_audit.append("PHASE 5A-V market quarter: %d permanent commercial lots added" % added)


## ══════════════════════════════════════════════════════════════════════
## PHASE 5A-V：市場區の常設商業縁
## ══════════════════════════════════════════════════════════════════════
##
## 診断：市場は「原っぱに屋台を置いた」構図で、囲いが一つも無かった。
## 南は横街まで 13m の空地、西は突き当たりが無く地平線が抜ける。
##
## 直し方は**建物家族を増やすことではない**（それは 5A で済んでいる）。
## 既承認の Phase 2A 家族だけで、市場に **縁と役割** を与える：
##
##   本通 ── 市木戸（既設）── 石の口 ── 広場 ── 西縁の突き当たり
##                                  └ 南縁：店 → 作業場 → 蔵（服務側）
##
## ⚠ 中心は空けたまま。屋台・道・portal・地標は一つも動かさない。
## ⚠ 深さは横街の路縁（z=82.5）と屋台の南端（z≈69.4）に挟まれた 13m で
##   決まる。だから南縁は **浅い三棟**（9.7 / 9.6 / 8.1m）しか入らない ——
##   標準町家（11.6〜12.6m）は西縁に回す。
const MARKET_QUARTER_LOTS := TownConfig.MARKET_QUARTER_LOTS


func _market_quarter_lots() -> int:
	for spec in MARKET_QUARTER_LOTS:
		var x: float = float(spec["x"])
		var z: float = float(spec["z"])
		_dump.append([String(spec["kind"]), x, bank_h(x, z), z, float(spec["yaw"])])
	return MARKET_QUARTER_LOTS.size()


# ── 重疊自驗（OBB / SAT，含出簷）──

	# ── PHASE 3 pilot：RNG 整列用の ghost pass ──
	# pilot の 4 ブロックを **legacy の kinds のまま**もう一度走らせて、
	# その結果を `_ghost` に貯める。密度層はこれを流して _drng を legacy と
	# 同じだけ消費する（`_dxf_mute` の注記を参照）。
	# ⚠ ブロックは互いに独立（各 _block が自前の RNG、_house は _reserved に
	#   何も足さない）ので、ここで再実行しても他のブロックには影響しない。
	# ⚠ ghost には **原本の cfg** をそのまま渡す（_kitify を通さない）。
	#   setback も jog も kinds も legacy のまま再現しないと、_drng の
	#   消費数が legacy と一致せず zero-drift が崩れる。
func _obb_of(e: Array) -> Array:
	## 從模組的 **Godot 局部 bbox（gbox）** 建世界 OBB。
	## ⚠ 舊版只吃 fw/fd 又假設「原點在正面、往後長 fd」—— 那只對町家成立。
	## 橋的原點在中心、鵜呑亭的川床往後伸 16m 而 fd 當時還寫成 10.9，
	## 於是自檢對它們**結構性全盲**：印著「0 穿插 ✓」，實際有 3 對互穿
	## （鵜呑亭 × 河畔町家 6.8m、鵜呑亭 × 主橋 2.3m）。gbox 一律照實量。
	return TownGeometry.obb_of(e, _mods)


func _assert_no_overlap() -> void:
	## 逐對 OBB（SAT）—— **不再只檢查町家**：橋與鵜呑亭一起進來。
	TownValidation.assert_no_overlap(_dump, _mods, _audit)


func _obb_pen(ra: Array, rb: Array) -> float:
	return TownGeometry.penetration(ra, rb)


func _emit_batches() -> void:
	var g := lib.add(_root, Node3D.new(), "町家")
	var total := 0
	var names := _batch.keys()
	names.sort()
	for kind in names:
		var list: Array = _batch[kind]
		# ⚠ PHASE 1：帶語意材質的 production 模組要走 `semantic_mesh()`，
		# 逐 surface 依 Blender 材質名掛專案的 PBR 材質；legacy blockout 模組
		# 仍是單一頂點色 mesh，走舊路徑。判斷依據是 **surface 數**（>1 就是
		# 分過材質的），不是寫死模組名 —— Phase 2 加新模組時不用再改這裡。
		var probe: Array = lib.semantic_mesh(String(_mods[kind]["glb"]))
		var mesh: Mesh = probe[0]
		if mesh.get_surface_count() > 1:
			_audit.append("　%s：語意材質 %d surface %s" % [kind, mesh.get_surface_count(),
				str(probe[1])])
		else:
			mesh = lib.prop_mesh(String(_mods[kind]["glb"]))
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
		if not _is_house_kind(String(e[0])):
			continue
		var m: Dictionary = _mods[e[0]]
		var yaw: float = e[4]
		var fwd := Vector2(sin(yaw), cos(yaw))
		var c := Vector2(e[1], e[3])
		if not bool(m.get("centered", false)):
			c -= fwd * (float(m["d"]) * 0.5)
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
	TownEnvironment.build(lib, _root)


func _perf_pass(n: Node) -> void:
	## 照抄 gen_village 的剔除／陰影分級。⚠ 那支只處理 MeshInstance3D，
	## MultiMeshInstance3D 完全不碰 —— 新鎮的 MM 要另外設（見 _build_revetment）。
	TownEnvironment.apply_performance_pass(n)


# ══════════════════ 街道生活密度層（規格 §5，使用者選 B 後開工）══════════════
# 三件事：簷下吊掛（暖簾／提灯／招牌，商業→住宅梯度）、地面雜物
# （樽／籃／木箱／縁台，「商品溢到街上」）、花樹同種大群聚（稗田邸教訓）。
# ⚠ 隨機數用**自己的 RNG**，不碰 lib.rand —— 密度層在佈局之後跑，
# 消耗 lib.rand 會把 vista 的散佈整個換一副面孔（佈局本身則不受影響）。

const SAKURA_SITES := TownConfig.SAKURA_SITES
const GREEN_SITES := TownConfig.GREEN_SITES

var _drng := RandomNumberGenerator.new()
var _dbatch := {}                # 道具名 → Array[Transform3D]
var _ddump := []                 # [kind, x, y, z, yaw]（驗證腳本用）

## PHASE 3 pilot：RNG 整列用のミュート。
## 密度層は **_dump 順に一本の _drng を消費する**ので、pilot ブロックの
## 棟数や間口が変わると、その後ろの全戸の抽選がずれる（実測 103 件）。
## 対策：pilot の位置には legacy の家（ghost）を流して _drng を**同じだけ**
## 消費させ、出力だけ捨てる。pilot 本体は別 RNG（_prng）で後段に回す。
var _dxf_mute := false
var _prng := RandomNumberGenerator.new()

func _dxf(kind: String, p: Vector2, y: float, yaw: float, s: float = 1.0) -> void:
	if _dxf_mute:
		return
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


func _identity_role(kind: String, p: Vector2) -> String:
	## Stable business identity from the existing household and lot coordinate.
	## This consumes no shared RNG, so vegetation and unrelated dressing do not drift.
	var trade: float = _commerce(p)
	if trade < 0.34:
		return ""
	var hx: int = int(round(p.x * 10.0)) * 73856093
	var hz: int = int(round(p.y * 10.0)) * 19349663
	var h: int = absi(hx ^ hz)
	if kind == "machiya_w_a":
		return "workshop"
	if kind == "machiya_f_o" or (kind == "machiya_n_o" and trade > 0.62):
		return "inn"
	if kind == "machiya_f_m" and h % 3 == 0:
		return "rice"
	if h % 100 >= 68:
		return ""
	var roles: Array[String] = ["sake", "rice", "dye", "goods", "closed", "inn", "workshop"]
	return roles[h % roles.size()]


func _roofline_role(kind: String, p: Vector2) -> String:
	## Large-form identity is reserved for civic streets and market context.
	## Coordinate hashing is independent of shared dressing/vegetation RNG.
	var on_ns: bool = absf(p.x) < 18.0 and p.y > -166.0 and p.y < 176.0
	var on_ew: bool = absf(p.y - MAIN_EW_Z) < 18.0 and p.x > -76.0 and p.x < 112.0
	var market_context: bool = p.distance_to(Vector2(-26.0, 57.0)) < 58.0
	if not (on_ns or on_ew or market_context):
		return ""
	var hx: int = int(round(p.x * 10.0)) * 83492791
	var hz: int = int(round(p.y * 10.0)) * 2971215073
	var h: int = absi(hx ^ hz)
	if h % 100 >= 62:
		return ""
	var roles: Array[String] = ["gable", "udatsu", "balcony", "store"]
	if kind == "machiya_w_a":
		return "store"
	if kind == "machiya_f_o" or kind == "machiya_n_o":
		return "udatsu"
	return roles[h % roles.size()]

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
	# ── PHASE 3 pilot：RNG 整列ストリーム ──
	# pilot の位置には legacy の ghost を差し込む。ghost は `_dxf_mute` で
	# 出力を捨てつつ _drng を **legacy と同じだけ**消費するので、
	# pilot より後ろの全戸の抽選が一切ずれない（実測 drift 103 → 0）。
	var stream: Array = []
	var pilots: Array = []
	var run := 0
	var i := 0
	while i < _dump.size():
		if _is_pilot(_dump[i]):
			while i < _dump.size() and _is_pilot(_dump[i]):
				pilots.append(_dump[i])
				i += 1
			var lo := 0 if run == 0 else _ghost_run2
			var hi := _ghost_run2 if run == 0 else _ghost.size()
			for k in range(lo, hi):
				stream.append(_ghost[k])
			run += 1
		else:
			stream.append(_dump[i])
			i += 1

	# ── 逐棟：吊掛 + 門前雜物（位置全部從立面錨點推，錨點是從 glb 量的）──
	for e in stream:
		_dxf_mute = _is_pilot(e)
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
		var identity: String = _identity_role(kind, pos)
		if identity != "":
			_dxf("facade_%s" % identity, pos + ax * door_x + fwd * 0.45, hy, yaw)
			continue
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
	_dxf_mute = false
	# ⚠ 花樹の排除判定も **legacy の家**（stream）で行う。新しい pilot の家で
	# 判定すると、採否が変わった瞬間にその後ろの木が全部ずれる。
	# 新しい家と当たる木は、抽選のあとで**フィルタ**して落とす（乱数を
	# 消費しないので後続に影響しない）。
	var house_obbs: Array = []
	for e2 in stream:
		if _is_house_kind(String(e2[0])):
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
	# ── PHASE 3：新しい pilot の家に当たる木を落とす（乱数は使わない）──
	var new_obbs: Array = []
	for e3 in pilots:
		new_obbs.append(_obb_of(e3))
	var culled := 0
	for kk in _dbatch.keys():
		if not String(kk).begins_with("tree"):
			continue
		var keep: Array = []
		for t3 in _dbatch[kk]:
			var q := Vector2(t3.origin.x, t3.origin.z)
			var hit := false
			for hb2 in new_obbs:
				var dd: Vector2 = q - hb2[0]
				if absf(dd.dot(hb2[1])) < hb2[3] + 2.6 \
						and absf(dd.dot(hb2[2])) < hb2[4] + 2.6:
					hit = true
					break
			if hit:
				culled += 1
			else:
				keep.append(t3)
		_dbatch[kk] = keep
	if culled > 0:
		_audit.append("PHASE 3：pilot の新しい家と当たる花樹 %d 本を除去" % culled)
	# ══════════════════════════════════════════════════════════════
	# PHASE 3 pilot：店先の設え（Phase 2.5/2.6b の規則を村へ移す）
	# ══════════════════════════════════════════════════════════════
	# slice は一区画ずつ手で座標を書いたが、ここは**規則**：
	#   ・役割はモジュール自身＋商業勾配から決まる（新しい手動表は作らない）
	#   ・吊り高さは manifest の facade.hisashi から**計算**する
	#     （Phase 2.6b の承認済み規則。絶対高さを手で書かない）
	#   ・階層を守る：主役 1・脇役 1~2・それ以上は置かない
	_prng.seed = SEED + 3001
	var n_dress := 0
	for e4 in pilots:
		var k4 := String(e4[0])
		var m4: Dictionary = _mods[k4]
		var f4: Dictionary = m4.get("facade", {})
		var hs: Dictionary = f4.get("hisashi", {})
		if hs.is_empty() and not f4.has("door_x"):
			continue                      # legacy（machiya_e_a）は対象外
		var p4 := Vector2(float(e4[1]), float(e4[3]))
		var y4: float = float(e4[2])
		var yw: float = float(e4[4])
		var fw4 := Vector2(sin(yw), cos(yw))
		var ax4 := Vector2(cos(yw), -sin(yw))
		var hw4: float = float(m4["w"]) * 0.5
		var dx4: float = float(f4["door_x"])
		var w4 := _commerce(p4)
		var identity4: String = _identity_role(k4, p4)
		if identity4 != "":
			_dxf("facade_%s" % identity4, p4 + ax4 * dx4 + fw4 * 0.45,
				y4, yw)
			n_dress += 1
			continue
		# 庇の下端＝吊り物の天井。前桁より内側に寄せる
		if hs.is_empty():
			continue
		var hz: float = minf(0.84, float(hs["proj"]) - float(hs["beam_back"]))
		var ceil_y: float = y4 + float(hs["z"]) \
			- hz * tan(deg_to_rad(float(hs["slope"]))) - float(hs["thick"]) - 0.035
		# 役割：モジュールが語る（工房は板戸、大店は 5 開間）＋商業勾配
		# ⚠ 役割の閾値を**発明しない**。村の密度層は昔から
		# `0.06 + 0.85*wgt` で暖簾を掛けるか決めている。同じ式を使う ——
		# ここで独自の閾値を切ると、pilot だけ商業の濃さが村とずれる。
		var role := "house"
		if k4 == "machiya_w_a":
			role = "work"
		elif k4 == "machiya_f_o" or _prng.randf() < 0.06 + 0.85 * w4:
			role = "shop"
		# ── 吊り物（主役の一段）──
		if role != "house":
			var nk4 := "prop_noren_ai" if float(f4["door_w"]) > 1.7 else "prop_noren_kaki"
			_dxf(nk4, p4 + ax4 * dx4 + fw4 * hz, ceil_y, yw)
			n_dress += 1
		if role == "shop" and _prng.randf() < 0.55 + 0.4 * w4:
			for sx4 in [-1.0, 1.0]:
				var cx4: float = dx4 + sx4 * 1.55
				if absf(cx4) < hw4 - 0.35:
					_dxf("prop_chochin", p4 + ax4 * cx4 + fw4 * 0.62,
						ceil_y - 0.16 - 0.035, yw)
					n_dress += 1
		# ── 地面（脇役）：役割ごとに一種類だけ。散らかさない ──
		var ground: Array[String] = []
		if role == "shop":
			ground.append_array(["prop_misedai", "prop_zaru", "prop_taru"])
		elif role == "work":
			ground.append_array(["prop_aigame", "prop_aigame", "prop_takigi"])
		elif _prng.randf() < 0.45:
			ground.append("prop_taru")
		var gi4 := 0
		for gk in ground:
			var lat4: float = (float(gi4) - float(ground.size() - 1) * 0.5) * 1.05
			var sx5: float = dx4 + (2.05 + lat4) * (1.0 if dx4 < 0.0 else -1.0)
			if absf(sx5) > hw4 - 0.45:
				gi4 += 1
				continue
			var lz4: float = 1.05 if gk == "prop_misedai" else 0.72
			var wp4: Vector2 = p4 + ax4 * sx5 + fw4 * lz4
			if _pt_on_road_core(wp4, 1.3) or _pt_reserved(wp4, 0.4):
				gi4 += 1
				continue
			var dy4: float = 0.44 if gk == "prop_zaru" else 0.0
			_dxf(gk, wp4, height_at(wp4.x, wp4.y) + dy4,
				yw + _prng.randf_range(-0.14, 0.14))
			n_dress += 1
			gi4 += 1
	if n_dress > 0:
		_audit.append("PHASE 3 pilot：店先の設え %d 件（%d 棟）" % [n_dress, pilots.size()])

	# 集計は _ddump から数え直す（ghost は _dxf で捨てているので入らない）
	n_noren = 0; n_cho = 0; n_kan = 0; n_clut = 0
	var n_tree2 := 0
	for d3 in _ddump:
		var dk := String(d3[0])
		if dk.begins_with("prop_noren"): n_noren += 1
		elif dk == "prop_chochin": n_cho += 1
		elif dk == "prop_kanban": n_kan += 1
		elif dk.begins_with("tree"): n_tree2 += 1
		else: n_clut += 1
	n_tree = n_tree2
	# Roof/upper-front overlays are architectural batches, not scattered props.
	# They sit on existing origins and therefore preserve every lot OBB/setback.
	for e5 in _dump:
		var k5 := String(e5[0])
		if not k5.begins_with("machiya"):
			continue
		var p5 := Vector2(float(e5[1]), float(e5[3]))
		var roofline: String = _roofline_role(k5, p5)
		if roofline == "":
			continue
		_dxf("roofline_%s" % roofline, p5, float(e5[2]), float(e5[4]))
	_emit_density()
	_audit.append("密度層：暖簾 %d、提灯 %d、招牌 %d、地面雜物 %d、花樹 %d（%d draw call）"
		% [n_noren, n_cho, n_kan, n_clut, n_tree, _dbatch.size()])

## 花樹的樹冠材質：**不能**走 lib.tree_mesh 的 canopy_mat —— 那個會拿
## terrain_forest_diff 貼圖乘頂點色，粉色 × 綠貼圖 = 濁褐色。
## 花冠用無貼圖的雙面頂點色材質，樹幹照用 bark PBR。
func _sakura_mesh(glb: String) -> Mesh:
	return TownAssets.sakura_mesh(lib, glb)

var _village_canopy: StandardMaterial3D = null

func _village_canopy_mat() -> StandardMaterial3D:
	if _village_canopy != null:
		return _village_canopy
	_village_canopy = StandardMaterial3D.new()
	_village_canopy.vertex_color_use_as_albedo = true
	_village_canopy.albedo_color = Color(0.82, 0.95, 0.76)
	_village_canopy.cull_mode = BaseMaterial3D.CULL_DISABLED
	_village_canopy.roughness = 1.0
	_village_canopy.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_village_canopy.disable_receive_shadows = true
	return _village_canopy

## Village-only tree material path. The shared canopy texture multiplies the
## already dark vertex colours until nearby crowns read as black spikes. Keep
## the existing meshes, but use a brighter, shadow-resistant vertex-colour
## material in this map only.
func _village_tree_mesh(glb_path: String) -> Mesh:
	return TownAssets.village_tree_mesh(lib, glb_path, _village_canopy_mat())


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
			mesh = _village_tree_mesh("res://assets/models/%s.glb" % k)
		else:
			mesh = lib.prop_mesh("res://assets/models/%s.glb" % k, lib.vc_mat())
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(mesh, _dbatch[kind], [],
			OUT_DIR + "gen/mm_%s.res" % k)
		if not k.begins_with("tree_"):
			# ⚠ 這裡原本設了 visibility_range_end = 110 —— 跟草層那個是**同一個
			# bug**（見 _build_grass）：距離是拿整個 MMI 的 AABB 算的，而道具
			# 鋪滿整個鎮，所以玩家走到村緣時整層道具會一次消失。
			# 之前沒發現是因為截圖機位都在鎮中心，離 AABB 中心夠近。
			# 拿掉；吊掛物不投影仍然保留（那是真的省）。
			if k in ["prop_noren_a", "prop_noren_b", "prop_chochin", "prop_kanban"]:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lib.add(g, mmi, "MM_%s" % k)


# ══════════════════ 草層（MIGRATE：從 gen_village.gd 搬過來重寫）══════════════
# 舊圖有六組草，新圖一組都沒有 —— 換完佈局後整張圖只剩地形貼圖，是目前最
# 明顯的視覺退步。這裡不是照抄，因為舊實作綁著三樣**新圖沒有的東西**：
#
#  1. `rice_rows`（3,600 株）走 `_field_w()` = **農田權重**。農田是規格裡
#     「🚫 獨立階段，未開工」的項目，第二輪還為了它把遮罩 G 通道清零過
#     （不然全鎮外圈會鋪一圈黃田）。照抄等於把已經明確延後的系統偷渡回來 ——
#     **這一組不搬**。
#  2. `reeds` 沿舊 RIVER + CANAL 取樣，兩條都已在 Stage 1 移除 → 改沿新河道。
#  3. 「避開路面」舊版自己重算 `_path_info`。新圖直接問 `mask_at()` ——
#     那就是地形著色器吃的同一份遮罩，草與地面貼圖因此永遠一致，
#     不會出現「貼圖是石板、上面卻長草」。
#
# 密度梯度沿用舊圖驗收過的直覺：**村心踏實、村外茂盛**（村心通過率 10%、
# 村外 60%），這是「有人住」讀得出來的關鍵。

const GRASS_SEED := TownConfig.GRASS_SEED

## 草能不能長在這裡：不在建物／保留區內、不在鋪面上、不在河裡。
func _grass_free(x: float, z: float, need: float, hgrid: Dictionary) -> bool:
	# 鋪面（石板 R + 夯土 A）—— 用地形著色器同一份遮罩
	var m := mask_at(x, z)
	if m.r + m.a > 0.30:
		return false
	if _river_dist_xy(x, z) < RIVER_HALF + 1.6:
		return false
	var p := Vector2(x, z)
	for q in _reserved:
		var d: Vector2 = p - q[0]
		if absf(d.dot(q[1])) < q[3] + need and absf(d.dot(q[2])) < q[4] + need:
			return false
	var key := Vector2i(int(floor(x / 24.0)), int(floor(z / 24.0)))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var k := Vector2i(key.x + dx, key.y + dz)
			if not hgrid.has(k):
				continue
			for r in hgrid[k]:
				var d2: Vector2 = p - r[0]
				if absf(d2.dot(r[1])) < r[3] + need and absf(d2.dot(r[2])) < r[4] + need:
					return false
	return true

## 離最近路緣多遠（0 = 站在路面上）。草的密度吃這個值。
func _road_dist(x: float, z: float) -> float:
	var best := 1e9
	for r in _roads:
		best = minf(best, lib.poly_dist(r.pts, x, z) - r.w * 0.5)
	return maxf(best, 0.0)

func _river_dist_xy(x: float, z: float) -> float:
	## ⚠ 一定要用 poly_dist（點到**線段**）而不是 `_nearest_river_pt` 的
	## 點到**取樣點**距離 —— 後者永遠 ≥ 真實距離，於是產生器以為在岸上的
	## 蘆葦，實測有 17/747 落在水裡。產生器量得比驗證腳本粗，就會出現
	## 「自檢過了、複驗抓到」這種假綠燈。mask_at 的水際帶也是用 poly_dist，
	## 兩邊要用同一把尺。
	return lib.poly_dist(_river(), x, z)

## 蘆葦：**沿著河道走**，不是在全圖亂撒後篩掉。
## 水際帶只佔全圖約 1.7%，用拒絕取樣的話 800 叢就要撞 48,000 次還撞不滿
## （實測只拿到 740/800，卡在 tries 上限）。沿線取樣是 ~100% 命中，
## 而且沿岸分佈均勻，不會這一段擠成一團、那一段空著。
func _reed_along_river(rng: RandomNumberGenerator, target: int) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var rv := _river()
	var total_len := 0.0
	for k in range(rv.size() - 1):
		total_len += rv[k].distance_to(rv[k + 1])
	if total_len <= 0.0:
		return out
	var per_m := float(target) / total_len          # 兩岸合計的每公尺株數
	for k in range(rv.size() - 1):
		var a: Vector2 = rv[k]
		var b: Vector2 = rv[k + 1]
		var seg := b - a
		var ln := seg.length()
		if ln <= 0.0001:
			continue
		var nrm := Vector2(seg.y, -seg.x) / ln       # 河道法線
		var n := int(round(ln * per_m))
		for i in n:
			var p: Vector2 = a + seg * rng.randf()
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var off := rng.randf_range(RIVER_HALF * 0.82, RIVER_HALF * 1.52)
			var q: Vector2 = p + nrm * side * off
			if absf(q.x) > HALF - 4.0 or absf(q.y) > HALF - 4.0:
				continue
			# 橋下與鵜呑亭川床下不長（踩踏區與陰影）
			var skip := false
			for br in BRIDGES:
				if q.distance_to(Vector2(float(br.x), float(br.z))) < 16.0:
					skip = true
					break
			if skip or q.distance_to(_uno_pos) < 20.0:
				continue
			var s := rng.randf_range(0.7, 1.4)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
			out.append(Transform3D(basis, Vector3(q.x, height_at(q.x, q.y), q.y)))
	return out


func _build_grass() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GRASS_SEED
	var patch_noise := FastNoiseLite.new()
	patch_noise.seed = GRASS_SEED + 41
	patch_noise.frequency = 0.018
	patch_noise.fractal_octaves = 3
	# 町家 OBB 的空間索引 —— 5,700 次取樣 × 169 棟是 O(n²)，會慢到不能接受
	var hgrid := {}
	for e in _dump:
		var r := _obb_of(e)
		var c: Vector2 = r[0]
		var rad: float = maxf(r[3], r[4]) + 3.0
		var i0 := int(floor((c.x - rad) / 24.0))
		var i1 := int(floor((c.x + rad) / 24.0))
		var j0 := int(floor((c.y - rad) / 24.0))
		var j1 := int(floor((c.y + rad) / 24.0))
		for i in range(i0, i1 + 1):
			for j in range(j0, j1 + 1):
				var k := Vector2i(i, j)
				if not hgrid.has(k):
					hgrid[k] = []
				hgrid[k].append(r)

	# 草色照舊圖驗收過的那組：葉根深、葉尖亮，別再用橄欖色（整片會發黃）
	var tall := lib.tuft_mesh(7, 0.40, 0.20, Color(0.11, 0.21, 0.08), Color(0.29, 0.48, 0.18))
	tall.surface_set_material(0, lib.grass_wind_mat(0.10))
	var flower := lib.tuft_mesh(5, 0.34, 0.16, Color(0.12, 0.22, 0.09), Color(0.28, 0.46, 0.18), true)
	flower.surface_set_material(0, lib.grass_wind_mat(0.08))
	var reed := lib.tuft_mesh(6, 0.62, 0.14, Color(0.18, 0.28, 0.12), Color(0.52, 0.56, 0.28))
	reed.surface_set_material(0, lib.grass_wind_mat(0.13))
	# 灌木層：介於草與樹之間的中層。只有「草 + 樹」兩層時，地面到樹冠之間
	# 是空的，遠看就是一片綠地上插著棒棒糖。
	var shrub := lib.tuft_mesh(9, 1.05, 0.55, Color(0.10, 0.20, 0.08), Color(0.26, 0.42, 0.16))
	shrub.surface_set_material(0, lib.grass_wind_mat(0.05))
	var fern := lib.tuft_mesh(7, 0.55, 0.40, Color(0.13, 0.24, 0.10), Color(0.32, 0.50, 0.20))
	fern.surface_set_material(0, lib.grass_wind_mat(0.06))

	# ⚠ 數量比舊圖大幅提高。舊圖的 2,600 叢長草攤在 600×600 上是
	# **每 57m² 一叢**（約每 7.5m 才一叢）—— 第一版照抄之後引擎內截圖
	# 根本看不出有草層，只有地形貼圖的綠。tuft_mesh 一叢只有 5~9 個三角形
	# （一片葉一張三角形），所以提高到 2.4 萬叢也才 ~19 萬三角形，
	# 比樹便宜得多；再加上不投影 + 距離淡出，這個量是划算的。
	var groups := [
		{"mesh": shrub, "n": 2400, "file": "shrubs", "node": "Shrubs",
			"mode": "wild", "need": 2.6, "patch": 0.48, "edge": 0.78},
		{"mesh": fern, "n": 5000, "file": "ferns", "node": "Ferns",
			"mode": "wild", "need": 1.6, "patch": 0.42, "edge": 0.66},
		{"mesh": tall, "n": 14000, "file": "grass_tall", "node": "GrassTall",
			"mode": "wild", "need": 1.6, "patch": 0.38, "edge": 0.58},
		{"mesh": flower, "n": 1000, "file": "grass_flower", "node": "GrassFlower",
			"mode": "wild", "need": 1.6, "patch": 0.58, "edge": 0.72},
		{"mesh": reed, "n": 1800, "file": "reeds", "node": "Reeds",
			"mode": "shore", "need": 0.0},
	]
	var total := 0
	var parts: Array[String] = []
	for group_i in range(groups.size()):
		var grp: Dictionary = groups[group_i]
		var list: Array[Transform3D] = []
		var target: int = int(grp.n)
		if String(grp.mode) == "shore":
			list = _reed_along_river(rng, target)
		else:
			var tries := 0
			while list.size() < target and tries < target * 30:
				tries += 1
				var x := rng.randf_range(-HALF + 4.0, HALF - 4.0)
				var z := rng.randf_range(-HALF + 4.0, HALF - 4.0)
				if not _grass_free(x, z, float(grp.need), hgrid):
					continue
				# 「有人住」的關鍵是**踩踏**，不是離廣場多遠。
				# ⚠ 舊圖用 `r < CORE ? 10% : 60%` 的硬半徑。照抄到新圖之後
				# 引擎內截圖整個村子都是光禿的綠地 —— 因為 CORE=196 幾乎涵蓋
				# 整座城鎮（最外圈町家在 r≈189），玩家在鎮上走的每一格都吃
				# 那個 10%。改成看**離路緣多遠**：路邊被踩禿、屋與屋之間的
				# 縫隙長得起來、出了村就茂盛。
				var dr := _road_dist(x, z)
				var pos := Vector2(x, z)
				# Daily activity suppresses vegetation continuously instead of using
				# one arbitrary core radius. Roads/frontages, market and shrine stay
				# sparse; the village edge receives coherent colonies rather than an
				# even salt-and-pepper scatter.
				var activity := maxf(_commerce(pos), 1.0 - smoothstep(2.5, 14.0, dr))
				activity = maxf(activity,
					1.0 - smoothstep(28.0, 48.0, pos.distance_to(Vector2(-26, 57))))
				activity = maxf(activity * 0.82,
					1.0 - smoothstep(22.0, 38.0, pos.distance_to(Vector2(-26, 2))))
				var edge_dist := maxf(absf(x), absf(z))
				var edge_k := smoothstep(105.0, 225.0, edge_dist)
				var zone := lerpf(1.0 - float(grp.edge), 1.0, edge_k)
				var noise_value := patch_noise.get_noise_2d(
					x + float(group_i) * 137.0, z - float(group_i) * 83.0) * 0.5 + 0.5
				var colony := smoothstep(float(grp.patch), 0.82, noise_value)
				var p := colony * zone * lerpf(0.10, 1.0, 1.0 - activity)
				if rng.randf() > p:
					continue
				var s := rng.randf_range(0.7, 1.4)
				var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s))
				list.append(Transform3D(basis, Vector3(x, height_at(x, z), z)))
		total += list.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(grp.mesh, list, [],
			OUT_DIR + "gen/%s.res" % String(grp.file))
		# 幾千叢草不能投影
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# ⚠⚠ **不准對「鋪滿全圖」的 MultiMesh 設 visibility_range**。
		# 那個距離是拿**整個 MultiMeshInstance 的 AABB**去算的，不是逐實例 ——
		# 草的 AABB 涵蓋整張 600×600 的圖，中心在地圖原點。相機站在
		# (−30, 230) 時離該中心 232m > 120m，於是**整層草一次全部消失**。
		#
		# 這個 bug 的症狀極度誤導：節點在、instance_count 對、mesh 與材質
		# 都在、座標驗證 4 項全過，就是畫面上一根都沒有。是從 9m 高垂直
		# 俯瞰一個「明明有 49 叢」的格子、一根都看不到才確定的。
		# （香霖堂的草沒事，因為那張圖只有 140×140，AABB 中心永遠在範圍內。）
		#
		# MultiMesh 本來就是一個 draw call，24,000 叢 × 7 三角形 ≈ 17 萬面，
		# 不設距離剔除也划算。要真的做 LOD 得切成多個分區 MultiMesh。
		lib.add(_root, mmi, String(grp.node))
		parts.append("%s %d" % [String(grp.node), list.size()])
	_audit.append("草層：%s —— 共 %d 叢 / %d draw call（稻田不搬：農田是延後項目）"
		% [", ".join(parts), total, groups.size()])




# ══════════════════ 地標內容搬遷（MIGRATE，來源 gen_village.gd）═══════════
# 搬遷用的共用基礎設施。四個 helper 從舊產生器搬過來，因為六座地標都用它們：
#   _lmat()          材質色調變體（同一種建材四個色調，全村才不是同色積木）
#   _ground_under()  一塊 footprint 的最低地面 + 起伏量（牆腳要埋進坡裡）
#   _lm_collide()    建物碰撞箱
#   _lm_rng          **地標專用亂數**
#
# ⚠ 最後一項是必要的，不是潔癖：舊 builder 大量呼叫 `lib.rr()`／`lib.rand()`。
# 那是 gen_lib 的共用 RNG，街區排列（jog／lateral／模組挑選）與 vista 散佈
# 也吃同一條序列。地標內容一旦動用它，**整座城鎮的町家排列會跟著位移**，
# diff 會變成「搬一座地標順便重排全鎮」，看不出真正改了什麼。
# 密度層與草層已經各自帶自己的 RNG，這裡沿用同一條規矩。
const MAT_TONES := TownAssets.MAT_TONES
const MAT_SET := TownAssets.MAT_SET


var _lm_rng := RandomNumberGenerator.new()

## 材質：同一種建材四個色調。舊 `_mat()` 的搬遷版。
func _lmat(key: String, v := -1) -> StandardMaterial3D:
	return TownAssets.material(lib, _lm_rng, key, v)

## 水面以下不算地面 —— 拿 height_at 的話院內有池就整棟沉下去。
func _lm_ground_sample(x: float, z: float) -> float:
	var y := height_at(x, z)
	if lib.poly_dist(_river(), x, z) < RIVER_HALF:
		y = maxf(y, bank_h(x, z) - RIVER_DEPTH * 0.20)
	return y

## 一塊 footprint 的 [最低地面, 起伏量]。取樣約每 4m 一點 ——
## 3×3 對 40m 長的土塀太稀，中段有坑就整段浮空（舊圖體檢抓過）。
func _ground_under(cx: float, cz: float, w: float, d: float) -> Array:
	var lo := INF
	var hi := -INF
	var nx := clampi(int(ceil(w / 4.0)) + 1, 3, 9)
	var nz := clampi(int(ceil(d / 4.0)) + 1, 3, 9)
	for i in nx:
		for j in nz:
			var ox := float(i) / float(nx - 1) - 0.5
			var oz := float(j) / float(nz - 1) - 0.5
			var y := _lm_ground_sample(cx + ox * w, cz + oz * d)
			lo = minf(lo, y)
			hi = maxf(hi, y)
	return [lo, hi - lo]

## 建物碰撞箱。⚠ owner 一定要是 _root，否則不會存進 .tscn（ADR-017）。
func _lm_collide(g: Node3D, size: Vector3, off := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	g.add_child(body)
	body.owner = _root
	var shape := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	shape.shape = bx
	shape.position = off + Vector3(0, size.y * 0.5, 0)
	body.add_child(shape)
	shape.owner = _root


## 石垣基壇（寺子屋等地標坐在其上，正面切石階）。搬自 gen_village。
func _dais_in(g: Node3D, w: float, d: float, h: float, face: Vector2, spread: float) -> void:
	var stone := _lmat("stone")
	var foot: float = spread + 0.3
	# 石垣是**下寬上窄**的（扇の勾配），直上直下看起來像水泥擋土牆
	var steps := 3
	for i in steps:
		var t := float(i) / float(steps)
		var sw: float = w - t * 0.9
		var sd: float = d - t * 0.9
		var sh: float = (h + foot) / float(steps)
		lib.box(g, "石垣_%d" % i, Vector3(sw, sh + 0.04, sd), stone,
			Vector3(0, -h - foot + sh * (float(i) + 0.5), 0))
	lib.box(g, "天端石", Vector3(w - 0.9, 0.16, d - 0.9), stone, Vector3(0, -0.08, 0))
	# 正面的石階
	var nsteps := maxi(int(h / 0.24), 3)
	var tan := face.orthogonal()
	for i in nsteps:
		var t2 := (float(i) + 0.5) / float(nsteps)
		var sy: float = -h + h * t2
		var out: float = (1.0 - t2) * 1.9
		lib.box(g, "石階_%d" % i, Vector3(3.4, h / float(nsteps) + 0.05, 0.42), stone,
			Vector3(face.x * (d * 0.5 + out), sy - h / float(nsteps) * 0.5,
				face.y * (d * 0.5 + out)))
	# 階梯兩側的親柱
	for sd2 in [-1.0, 1.0]:
		lib.box(g, "親柱_%d" % int(float(sd2) + 1), Vector3(0.34, h + 0.5, 0.34), stone,
			Vector3(face.x * (d * 0.5 + 0.3) + tan.x * float(sd2) * 1.9, -h * 0.5 + 0.05,
				face.y * (d * 0.5 + 0.3) + tan.y * float(sd2) * 1.9))
	_lm_collide(g, Vector3(w, h, d), Vector3(0, -h, 0))

## 生垣（樹籬）＋竹垣：村緣的「圍牆」。
##
## 在（農家那一環）用土塀是錯的 —— 土塀是町方的東西，要人力與瓦。
## 村緣圍的是樹籬與竹垣，而且矮，看得到裡面的曬場。
## 這也是「密度不一樣的街區不要混在一起」的一部分：材質本身就要換。


## ── 足洗邸（第一座搬入）──
## 荒廢的宅邸：崩れ塀三段 + 母屋（茅葺）。牆腳要埋進坡裡，不然整段浮著。
func _lm_ashiarai(g: Node3D, spread: float) -> void:
	# ⚠ 舊 builder 的崩れ塀在 z 上是**不對稱**的（−20.5 / −6 / +4），整組偏北
	# 8.2m。保留區是對稱的，所以內容要往南推回來對齊中心 —— 不然牆會伸出
	# 保留區外，草就長進牆裡（check_map 抓到 10 叢）。
	var c := lib.add(g, Node3D.new(), "本體")
	c.position.z = 4.25
	g = c
	var hw := 42.0 * 0.5 - 2.0        # 舊 BLOCK_W/D：崩れ塀鋪到街區邊
	var hd := 45.0 * 0.5 - 2.0
	for w in [[0.0, -hd, hw * 1.4, true], [-hw, -6.0, hd * 0.9, false],
			[hw, 4.0, hd * 0.8, false]]:
		var kh := _lm_rng.randf_range(1.2, 1.9)
		var kfoot := spread + 0.4
		lib.box(g, "崩れ塀_%d" % int(w[0]),
			Vector3(w[2] if w[3] else 0.36, kh + kfoot, 0.36 if w[3] else w[2]),
			_lmat("mud"), Vector3(w[0], kh * 0.5 - kfoot * 0.5, w[1]))
	var afoot := spread + 0.4
	lib.box(g, "母屋基壇", Vector3(16.0, 0.5 + afoot, 12.0), _lmat("stone"),
		Vector3(0, 0.25 - afoot * 0.5, -2.0))
	lib.box(g, "母屋", Vector3(14.5, 3.6, 10.5), _lmat("dark"), Vector3(0, 2.3, -2.0))
	lib.gable_roof(g, 4.1, 17.0, 13.0, 0.62, 0.5, _lmat("thatch"), _lmat("dark"),
		Vector3(0, 0, -2.0))
	_lm_collide(g, Vector3(14.9, 5.4, 10.9), Vector3(0, 0, -2.0))


## ── 鈴奈庵（貸本屋）──
## ⚠ 整棟旋轉 −90°：正面（局部 +z）要朝西對著本通。舊 builder 的
## `bx + face_dir*(hw−6.6)` 與 `lib.rr(-4,4)` 抖動都已經烘進 LANDMARKS 的
## 座標了，搬過來之後直接以保留區中心為原點，不再重算偏移（也不再抖動 ——
## 抖動會讓保留區跟實際位置每次產生都對不上）。
func _lm_suzunaan(g: Node3D, _spread: float) -> void:
	g.rotation.y = -PI / 2.0
	var w := 13.0
	var d := 9.5
	lib.box(g, "基石", Vector3(w + 0.5, 0.35, d + 0.5), _lmat("stone"), Vector3(0, 0.18, 0))
	lib.box(g, "屋身", Vector3(w, 5.4, d), _lmat("plaster"), Vector3(0, 3.05, 0))
	lib.box(g, "腰板", Vector3(w + 0.05, 1.0, 0.08), _lmat("dark"),
		Vector3(0, 0.85, d * 0.5 + 0.05))
	lib.box(g, "格子戶", Vector3(w * 0.62, 2.1, 0.1), _lmat("dark"),
		Vector3(0, 1.75, d * 0.5 + 0.06))
	lib.box(g, "二階窗", Vector3(w * 0.72, 1.3, 0.08), _lmat("dark"),
		Vector3(0, 4.3, d * 0.5 + 0.06))
	lib.box(g, "庇", Vector3(w + 1.0, 0.16, 1.4), _lmat("kawara"),
		Vector3(0, 3.35, d * 0.5 + 0.6))
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.28, 0.24, 0.34)      # 鈴奈庵的藍紫暖簾
	cloth.roughness = 1.0
	for k in [-1, 0, 1]:
		lib.box(g, "暖簾_%d" % (k + 1), Vector3(2.0, 0.9, 0.05), cloth,
			Vector3(float(k) * 2.2, 2.55, d * 0.5 + 0.66))
	lib.box(g, "看板", Vector3(0.6, 2.4, 0.14), _lmat("wood"),
		Vector3(w * 0.44, 3.0, d * 0.5 + 0.5))
	lib.box(g, "書架", Vector3(4.2, 1.3, 0.9), _lmat("wood"),
		Vector3(-2.6, 1.0, d * 0.5 + 1.1))
	lib.gable_roof(g, 5.75, w + 1.4, d + 1.6, 0.5, 0.24, _lmat("kawara"), _lmat("plaster"))
	_lm_collide(g, Vector3(w + 0.5, 7.0, d + 0.5))


## ── 寺子屋（慧音的私塾）──
## 大屋頂主屋 + 外廊 + 向拜 + 梵鐘。坐在 1.5m 石垣基壇上。
## ⚠ 內容對齊保留區中心（舊版是街區中心往南 6m，會戳出保留區）。
func _lm_terakoya(g: Node3D, spread: float) -> void:
	const DAIS_H := 1.5
	g.position.y += DAIS_H
	# 內容整體偏東南（梵鐘 +x、向拜與手水缽 +z）—— 推回保留區中心
	var c := lib.add(g, Node3D.new(), "本體")
	c.position = Vector3(-0.55, 0.0, -1.35)
	g = c
	_dais_in(g, 26.0, 16.0, DAIS_H, Vector2(0, 1), spread)
	lib.box(g, "土台", Vector3(24.0, 0.5, 14.0), _lmat("stone"), Vector3(0, 0.25, 0))
	lib.box(g, "屋身", Vector3(22.0, 4.6, 12.0), _lmat("plaster", 0), Vector3(0, 2.9, 0))
	lib.box(g, "外廊", Vector3(23.4, 0.34, 3.0), _lmat("wood"), Vector3(0, 0.85, 7.2))
	lib.box(g, "高欄", Vector3(23.4, 0.14, 0.14), _lmat("dark"), Vector3(0, 1.62, 8.6))
	for i in 14:
		lib.box(g, "高欄束_%d" % i, Vector3(0.1, 0.62, 0.1), _lmat("dark"),
			Vector3(-11.2 + float(i) * 1.72, 1.32, 8.6))
	for i in 8:
		lib.cyl(g, "廊柱_%d" % i, 0.19, 0.19, 3.6, _lmat("dark"),
			Vector3(-10.0 + float(i) * 2.85, 2.8, 8.4), 6)
	for i in 5:
		lib.box(g, "障子_%d" % i, Vector3(3.4, 2.8, 0.08),
			lib.flat_mat("shoji", Color(0.94, 0.93, 0.88), 0.9),
			Vector3(-8.6 + float(i) * 4.3, 2.25, 6.05))
		lib.box(g, "障子框_%d" % i, Vector3(3.6, 0.14, 0.12), _lmat("dark"),
			Vector3(-8.6 + float(i) * 4.3, 3.72, 6.05))
	lib.gable_roof(g, 5.2, 26.0, 16.0, 0.52, 0.4, _lmat("kawara"), _lmat("plaster", 0))
	# 向拜（正面突出的門廊）—— 參考圖最有辨識度的一件
	lib.box(g, "向拜屋根", Vector3(7.4, 0.3, 3.4), _lmat("kawara"), Vector3(0, 4.6, 8.0))
	for sd in [-1.0, 1.0]:
		lib.cyl(g, "向拜柱_%d" % int(sd + 1), 0.22, 0.24, 4.4, _lmat("dark"),
			Vector3(sd * 3.2, 2.2, 9.2), 8)
	lib.box(g, "梵鐘架", Vector3(2.6, 0.3, 2.6), _lmat("dark"), Vector3(13.0, 3.4, 6.0))
	lib.cyl(g, "梵鐘", 0.62, 0.78, 1.5,
		lib.pbr("bonsho", "stone_wall", 0.6, Color(0.52, 0.58, 0.52)),
		Vector3(13.0, 2.4, 6.0), 12)
	lib.box(g, "立札", Vector3(1.6, 1.1, 0.1), _lmat("wood"), Vector3(-8.0, 1.3, 10.5))
	lib.cyl(g, "手水缽", 0.7, 0.75, 0.7, _lmat("stone"), Vector3(9.0, 0.35, 10.0), 10)
	_lm_collide(g, Vector3(22.4, 7.0, 12.4))


## ── 鎮守之杜（村社的神木與境內）──
## 神木（放大的闊葉樹）＋土壇＋注連縄＋紙垂＋玉垣一圈＋石燈籠一對＋杜木。
## ⚠ 舊 builder 全程用**世界座標**寫（因為它的 g 掛在原點）。搬過來之後 g
## 已經被擺到地標位置了，所以每一件都要換算成群組**區域座標**：
## 區域 = 世界 − 群組原點；y 則是 height_at(世界) − 群組原點 y。
## 直接照抄世界座標的話整組會位移一個地標座標的量。
func _lm_grove(g: Node3D, _spread: float) -> void:
	var wc := Vector2(g.position.x, g.position.z)
	var y0: float = g.position.y
	var lp := func(wx: float, wz: float, dy: float) -> Vector3:
		return Vector3(wx - wc.x, height_at(wx, wz) - y0 + dy, wz - wc.y)

	var post_m := _lmat("stone", 1)
	lib.cyl(g, "土壇", 5.6, 6.4, 0.7, _lmat("stone", 2), lp.call(wc.x, wc.y, 0.25), 16)
	# 神木：比一般樹高兩倍以上，剪影才會從屋頂上冒出來。
	# ⚠ 用 tree_round_a（近景款）而不是舊版的 tree_round_b —— b 在新的
	# tree_lib 裡是 vista 精簡款（ntuft 只有一半），放大 4 倍會稀得看得出來。
	var big := MeshInstance3D.new()
	big.mesh = _village_tree_mesh("res://assets/models/tree_round_a.glb")
	big.position = lp.call(wc.x, wc.y, 0.6)
	big.scale = Vector3(3.0, 3.6, 3.0)
	lib.add(g, big, "神木")
	var tb := StaticBody3D.new()
	big.add_child(tb)
	tb.owner = _root
	var tsh := CollisionShape3D.new()
	var tcy := CylinderShape3D.new()
	tcy.radius = 1.6 / 3.0          # 母節點有 3.0 倍縮放，形狀要除回去
	tcy.height = 8.0 / 3.6
	tsh.shape = tcy
	tsh.position = Vector3(0, 1.2 / 3.6, 0)
	tb.add_child(tsh)
	tsh.owner = _root
	# 注連縄（繞樹一圈的粗繩）＋紙垂 —— 一眼看出這是神木不是路樹
	var rope_m := lib.pbr("shimenawa", "terrain_grass", 1.6, Color(0.88, 0.84, 0.66))
	var seg := 20
	for i in seg:
		var mid := (float(i) + 0.5) / float(seg) * TAU
		var r_in := 1.75
		var link := lib.cyl(g, "注連縄_%d" % i, 0.17, 0.17,
			r_in * TAU / float(seg) * 1.12, rope_m,
			lp.call(wc.x + cos(mid) * r_in, wc.y + sin(mid) * r_in, 3.1), 6)
		link.rotation.y = -mid
		link.rotation.z = PI * 0.5
	for i in 6:
		var a3 := float(i) / 6.0 * TAU + 0.25
		lib.box(g, "紙垂_%d" % i, Vector3(0.16, 0.5, 0.03),
			lib.flat_mat("shide", Color(0.96, 0.96, 0.94), 0.9),
			lp.call(wc.x + cos(a3) * 1.78, wc.y + sin(a3) * 1.78, 2.72))
	# 玉垣（圍住神木的矮石欄）—— 給中心一個明確的邊界
	for i in 16:
		var a4 := float(i) / 16.0 * TAU
		lib.box(g, "玉垣柱_%d" % i, Vector3(0.22, 1.05, 0.22), post_m,
			lp.call(wc.x + cos(a4) * 5.4, wc.y + sin(a4) * 5.4, 0.5))
		var a5 := (float(i) + 0.5) / 16.0 * TAU
		var rail := lib.box(g, "玉垣貫_%d" % i, Vector3(2.15, 0.13, 0.10), post_m,
			lp.call(wc.x + cos(a5) * 5.4, wc.y + sin(a5) * 5.4, 0.78))
		rail.rotation.y = -a5
	# 石燈籠一對、有人來拜的痕跡
	for sd in [-1.0, 1.0]:
		var lx: float = wc.x + 6.6
		var lz2: float = wc.y + sd * 2.6
		var tag := int(sd + 1)
		lib.cyl(g, "獻燈基_%d" % tag, 0.34, 0.40, 0.22, post_m, lp.call(lx, lz2, 0.11), 8)
		lib.cyl(g, "獻燈竿_%d" % tag, 0.13, 0.15, 1.15, post_m, lp.call(lx, lz2, 0.8), 8)
		lib.cyl(g, "獻燈袋_%d" % tag, 0.30, 0.28, 0.42, post_m, lp.call(lx, lz2, 1.58), 6)
		lib.cyl(g, "獻燈笠_%d" % tag, 0.08, 0.56, 0.26, post_m, lp.call(lx, lz2, 1.92), 6)
	# 杜：神木周圍再種一圈較小的樹（「杜」是樹叢，不是一棵樹）。
	# ⚠ 橢圓排布並收在保留區內 —— 舊版是 wr 8.5~18 的圓，那會戳出保留區
	# 南北緣（d/2 只有 18），重演足洗邸外溢。樹冠半徑再留 3.5m。
	var TREES := ["res://assets/models/tree_round_a.glb",
		"res://assets/models/tree_round_c.glb", "res://assets/models/tree_pine_a.glb"]
	for i in 14:
		var wa := _lm_rng.randf_range(0.0, TAU)
		var t := sqrt(_lm_rng.randf_range(0.30, 1.0))
		var wx: float = wc.x + cos(wa) * (7.0 + t * 10.0)
		var wz: float = wc.y + sin(wa) * (7.0 + t * 7.5)
		if _road_dist(wx, wz) < 1.6:
			continue
		var sub := MeshInstance3D.new()
		sub.mesh = _village_tree_mesh(TREES[_lm_rng.randi() % TREES.size()])
		sub.position = lp.call(wx, wz, 0.0)
		sub.scale = Vector3.ONE * _lm_rng.randf_range(1.05, 1.5)
		sub.rotation.y = _lm_rng.randf_range(0.0, TAU)
		lib.add(g, sub, "杜木_%d" % i)


## ── 市場（開放廣場：龍神像＋屋台十二座＋水井＋高札場）──
## ⚠ 跟鎮守之杜一樣，舊 builder 全用世界座標寫，搬過來要換算成區域座標。
const SHRINE_R := TownConfig.SHRINE_R

func _lm_dragon(g: Node3D, ox: float, oz: float) -> void:
	var stone := _lmat("stone")
	var dark := _lmat("dark")
	var sg := lib.add(g, Node3D.new(), "龍神像")
	sg.position = Vector3(ox, 0.0, oz)
	lib.cyl(sg, "砂利敷", SHRINE_R, SHRINE_R, 0.12,
		lib.pbr("shrine_gravel", "cobble", 0.9, Color(0.88, 0.86, 0.80)),
		Vector3(0, 0.06, 0), 24)
	var tiers := [[6.0, 0.42], [4.9, 0.40], [4.0, 0.38]]
	var y := 0.1
	for i in tiers.size():
		var tw: float = tiers[i][0]
		var th: float = tiers[i][1]
		lib.box(sg, "石壇_%d" % i, Vector3(tw, th, tw), stone, Vector3(0, y + th * 0.5, 0))
		lib.box(sg, "壇緣_%d" % i, Vector3(tw + 0.22, 0.1, tw + 0.22), stone,
			Vector3(0, y + th - 0.02, 0))
		y += th
	var dstat := MeshInstance3D.new()
	dstat.mesh = lib.prop_mesh("res://assets/models/dragon_statue.glb", stone)
	dstat.position = Vector3(0, y, 0)
	dstat.rotation.y = 0.6
	lib.add(sg, dstat, "像")
	var posts := 16
	for i in posts:
		var a := float(i) / float(posts) * TAU
		var px := cos(a) * SHRINE_R * 0.86
		var pz := sin(a) * SHRINE_R * 0.86
		var pl := lib.box(sg, "玉垣柱_%d" % i, Vector3(0.24, 1.25, 0.24), stone,
			Vector3(px, 0.72, pz))
		pl.rotation.y = -a
		lib.box(sg, "玉垣笠_%d" % i, Vector3(0.34, 0.1, 0.34), stone, Vector3(px, 1.39, pz))
		var a2 := float(i + 1) / float(posts) * TAU
		lib.strut(sg, "玉垣貫_%d" % i, Vector3(px, 1.02, pz),
			Vector3(cos(a2) * SHRINE_R * 0.86, 1.02, sin(a2) * SHRINE_R * 0.86),
			0.055, stone, 4)
	# 正面（朝 −z＝廣場中心）留缺口當入口
	for sd in [-1.0, 1.0]:
		var tag := int(sd + 1)
		lib.box(sg, "門柱_%d" % tag, Vector3(0.34, 2.4, 0.34), stone,
			Vector3(sd * 1.5, 1.2, -SHRINE_R * 0.86))
		lib.cyl(sg, "門柱頭_%d" % tag, 0.0, 0.26, 0.3, stone,
			Vector3(sd * 1.5, 2.5, -SHRINE_R * 0.86), 8)
	var rope := lib.pbr("shimenawa", "terrain_grass", 1.6, Color(0.86, 0.80, 0.60))
	for i in 8:
		var t0 := float(i) / 8.0
		var t1 := float(i + 1) / 8.0
		lib.strut(sg, "注連縄_%d" % i,
			Vector3(lerpf(-1.5, 1.5, t0), 2.2 - sin(t0 * PI) * 0.42, -SHRINE_R * 0.86),
			Vector3(lerpf(-1.5, 1.5, t1), 2.2 - sin(t1 * PI) * 0.42, -SHRINE_R * 0.86),
			0.13 - absf(t0 - 0.5) * 0.08, rope, 6)
	for i in 3:
		lib.box(sg, "紙垂_%d" % i, Vector3(0.16, 0.42, 0.02),
			lib.flat_mat("shide", Color(0.97, 0.97, 0.95), 0.9),
			Vector3(-0.9 + float(i) * 0.9, 1.62, -SHRINE_R * 0.86 - 0.06))
	# 常夜燈一對
	for sd2 in [-1.0, 1.0]:
		var lx: float = sd2 * 4.6
		var lz := -SHRINE_R * 0.55
		var tg := int(sd2 + 1)
		lib.box(sg, "燈籠基_%d" % tg, Vector3(0.9, 0.24, 0.9), stone, Vector3(lx, 0.24, lz))
		lib.cyl(sg, "燈籠竿_%d" % tg, 0.16, 0.19, 1.25, stone, Vector3(lx, 0.98, lz), 8)
		lib.box(sg, "燈籠中台_%d" % tg, Vector3(0.62, 0.16, 0.62), stone, Vector3(lx, 1.68, lz))
		lib.box(sg, "火袋_%d" % tg, Vector3(0.52, 0.6, 0.52),
			lib.flat_mat("toro_light", Color(0.98, 0.88, 0.62), 0.8, Color(0.9, 0.66, 0.34)),
			Vector3(lx, 2.06, lz))
		for ci in 4:
			var ca := float(ci) / 4.0 * TAU + PI * 0.25
			lib.box(sg, "火袋柱_%d_%d" % [tg, ci], Vector3(0.1, 0.62, 0.1), dark,
				Vector3(lx + cos(ca) * 0.26, 2.06, lz + sin(ca) * 0.26))
		lib.cyl(sg, "燈籠笠_%d" % tg, 0.12, 0.62, 0.34, stone, Vector3(lx, 2.53, lz), 6)
		lib.cyl(sg, "寶珠_%d" % tg, 0.0, 0.14, 0.24, stone, Vector3(lx, 2.8, lz), 8)
	# 供物台
	lib.box(sg, "供物台", Vector3(1.5, 0.16, 0.7), stone,
		Vector3(0, 0.72, -SHRINE_R * 0.86 - 0.9))
	for sd3 in [-1.0, 1.0]:
		lib.box(sg, "供物台脚_%d" % int(sd3 + 1), Vector3(0.22, 0.64, 0.5), stone,
			Vector3(sd3 * 0.55, 0.34, -SHRINE_R * 0.86 - 0.9))
	for i in 2:
		lib.cyl(sg, "御神酒_%d" % i, 0.06, 0.11, 0.34,
			lib.flat_mat("sake_bottle", Color(0.90, 0.90, 0.86), 0.35),
			Vector3(-0.3 + float(i) * 0.6, 0.97, -SHRINE_R * 0.86 - 0.9), 8)
	# 碰撞只給像與石壇 —— 玉垣要讓人走得過去，不然廣場被切成兩半
	_lm_collide(sg, Vector3(4.2, 8.4, 4.2))


func _lm_market(g: Node3D, _spread: float) -> void:
	# 內容整體偏西南，推回保留區中心（實測後定的偏移）
	# 偏移由**實測**定：第一版用 2.35 估，量出來中心偏東 1.1m，修正為 1.25。
	var c := lib.add(g, Node3D.new(), "本體")
	c.position = Vector3(1.25, 0.0, 3.95)
	var wc := Vector2(g.position.x, g.position.z)
	var y0: float = g.position.y
	var wood := _lmat("wood")
	var stone := _lmat("stone")
	_lm_dragon(c, -12.0, -10.0)
	var cloths := [Color(0.52, 0.30, 0.27), Color(0.30, 0.35, 0.45),
		Color(0.58, 0.50, 0.32), Color(0.34, 0.42, 0.33), Color(0.46, 0.40, 0.50)]
	var goods := [Color(0.78, 0.62, 0.34), Color(0.52, 0.30, 0.24), Color(0.40, 0.52, 0.30),
		Color(0.86, 0.80, 0.62), Color(0.30, 0.34, 0.40)]
	var earth := lib.pbr("市場土間", "terrain_path", 0.30, Color(0.92, 0.88, 0.80))
	# ⚠ 攤位不能撒成方陣（從空中看是停車場）。市集是「兩排面對面夾一條走道」，
	# 客人走中間、攤販站兩側；正面（+z）一律朝走道。
	const AISLE_Z := 2.0
	const AISLE_HALF := 4.6
	# ⚠ PHASE 5A-V 修正ラウンド：等間隔 5.4m の 6 スパンは空撮で**定規で引いた
	#   格子**に読めた（round 1 の mq_elevated）。市は島ごとに寄って立つもの
	#   なので、間隔を 4.55m に詰めたうえで島の頭に段差を入れ、三つの塊に割る。
	#   通路の幅は島の間で広がる。⚠ _lm_rng の**消費回数は一つも変えない**
	#   （地標の抽選列がずれると水井・高札場・龍神像まで動く）。
	const STALL_ISLAND_DX := [0.0, 0.0, 2.10, 2.10, 4.60, 4.60]
	const STALL_ISLAND_DZ := [0.0, 0.35, -0.45]
	for i in 12:
		var row := i % 2
		var k0: int = i / 2
		var ox: float = -13.0 + float(k0) * 4.55 + float(STALL_ISLAND_DX[k0]) \
			+ _lm_rng.randf_range(-0.9, 0.9)
		var oz: float = AISLE_Z + (AISLE_HALF if row == 1 else -AISLE_HALF) \
			+ float(STALL_ISLAND_DZ[k0 / 2]) * (1.0 if row == 1 else -1.0) \
			+ _lm_rng.randf_range(-0.4, 0.4)
		var gu := _ground_under(wc.x + ox, wc.y + oz, 3.6, 3.0)
		var st := Node3D.new()
		st.position = Vector3(ox, float(gu[0]) - y0, oz)
		st.rotation.y = (PI if row == 1 else 0.0) + _lm_rng.randf_range(-0.18, 0.18)
		lib.add(c, st, "屋台_%d" % i)
		lib.box(st, "土間", Vector3(4.4, 0.10, 3.6), earth, Vector3(0, 0.03, 0.2))
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				lib.strut(st, "腳_%d%d" % [int(sx + 1), int(sz + 1)],
					Vector3(sx * 1.3, 0.06, sz * 0.85), Vector3(sx * 1.3, 0.95, sz * 0.85),
					0.055, wood, 5)
			lib.strut(st, "貫_%d" % int(sx + 1), Vector3(sx * 1.3, 0.34, -0.85),
				Vector3(sx * 1.3, 0.34, 0.85), 0.04, wood, 4)
		lib.box(st, "檯面", Vector3(2.9, 0.10, 1.9), _lmat("wood", i % 4), Vector3(0, 1.0, 0))
		var back_h := 2.45
		var front_h := 2.05
		for sx2 in [-1.0, 1.0]:
			lib.strut(st, "篷柱後_%d" % int(sx2 + 1), Vector3(sx2 * 1.35, 0.95, -0.95),
				Vector3(sx2 * 1.4, back_h, -1.05), 0.05, wood, 5)
			lib.strut(st, "篷柱前_%d" % int(sx2 + 1), Vector3(sx2 * 1.35, 0.95, 0.95),
				Vector3(sx2 * 1.4, front_h, 1.15), 0.05, wood, 5)
		var base_c: Color = cloths[i % cloths.size()]
		var cm := lib.pbr("屋台布_%d" % (i % 5), "plaster", 1.8, base_c)
		var cm2 := lib.pbr("屋台布縞_%d" % (i % 5), "plaster", 1.8,
			Color(base_c.r * 0.62 + 0.30, base_c.g * 0.62 + 0.30, base_c.b * 0.62 + 0.30))
		var strips := 6
		for k in 2:
			var t := float(k)
			var sag := -0.10 if k == 0 else 0.0
			for sI in strips:
				var sw := 3.3 / float(strips)
				var cloth := lib.box(st, "篷_%d_%d" % [k, sI],
					Vector3(sw * 0.99, 0.05, 1.25), cm if sI % 2 == 0 else cm2,
					Vector3(-1.65 + (float(sI) + 0.5) * sw,
						lerpf(back_h, front_h, 0.25 + t * 0.5) + sag, -0.55 + t * 1.1))
				cloth.rotation.x = 0.20 + t * 0.06
		var skirt := lib.box(st, "篷垂", Vector3(3.3, 0.34, 0.04), cm2,
			Vector3(0, front_h - 0.12, 1.18))
		skirt.rotation.x = 0.1
		for k2 in 3:
			var gmat := lib.flat_mat("貨_%d" % ((i + k2) % 5), goods[(i + k2) % goods.size()], 0.9)
			var gx2 := -0.95 + float(k2) * 0.95
			if _lm_rng.randf() < 0.5:
				for k3 in 3:
					lib.cyl(st, "貨_%d_%d" % [k2, k3], 0.16, 0.18, 0.12, gmat,
						Vector3(gx2 + _lm_rng.randf_range(-0.05, 0.05), 1.11 + float(k3) * 0.12,
							_lm_rng.randf_range(-0.3, 0.3)), 8)
			else:
				lib.box(st, "貨箱_%d" % k2, Vector3(0.6, 0.26, 0.5), gmat,
					Vector3(gx2, 1.18, _lm_rng.randf_range(-0.25, 0.25)))
		if _lm_rng.randf() < 0.6:
			var nx := 1.42 * (1.0 if _lm_rng.randf() < 0.5 else -1.0)
			for k4 in 3:
				lib.box(st, "暖簾_%d" % k4, Vector3(0.04, 0.6, 0.42),
					cm if k4 % 2 == 0 else cm2, Vector3(nx, 1.72, -0.5 + float(k4) * 0.5))
		lib.box(st, "木箱", Vector3(0.75, 0.48, 0.58), _lmat("wood", (i + 1) % 4),
			Vector3(_lm_rng.randf_range(-1.1, 1.1), 0.29, 1.45))
		if _lm_rng.randf() < 0.5:
			lib.box(st, "莚", Vector3(1.5, 0.05, 1.0),
				lib.pbr("莚", "terrain_grass", 1.5, Color(0.80, 0.70, 0.46)),
				Vector3(_lm_rng.randf_range(-0.6, 0.6), 0.09, 1.7))
		_lm_collide(st, Vector3(3.0, 1.1, 2.2))
	# 水井（有屋頂與吊桶架）
	var wo := Vector2(13.0, 8.0)
	var well := Node3D.new()
	well.position = Vector3(wo.x, height_at(wc.x + wo.x, wc.y + wo.y) - y0, wo.y)
	lib.add(c, well, "水井")
	lib.cyl(well, "井筒", 1.15, 1.25, 1.0, stone, Vector3(0, 0.5, 0), 12)
	lib.cyl(well, "井口", 0.95, 0.95, 0.05,
		lib.flat_mat("water_dark", Color(0.07, 0.12, 0.15), 0.1), Vector3(0, 1.0, 0), 12)
	for sd in [-1, 1]:
		lib.cyl(well, "支柱_%d" % (sd + 1), 0.09, 0.09, 2.6, _lmat("dark"),
			Vector3(float(sd) * 1.0, 1.3, 0), 6)
	lib.box(well, "橫木", Vector3(2.4, 0.14, 0.14), _lmat("dark"), Vector3(0, 2.55, 0))
	lib.box(well, "桶", Vector3(0.4, 0.4, 0.4), wood, Vector3(0, 1.9, 0))
	lib.gable_roof(well, 2.62, 3.0, 2.6, 0.5, 0.16, _lmat("kawara"), wood)
	lib.cyl(well, "滑車", 0.16, 0.16, 0.12, _lmat("dark"), Vector3(0, 2.42, 0), 8)
	_lm_collide(well, Vector3(2.5, 1.2, 2.5))
	# 高札場
	var no := Vector2(14.0, -12.0)
	var notice := Node3D.new()
	notice.position = Vector3(no.x, height_at(wc.x + no.x, wc.y + no.y) - y0, no.y)
	notice.rotation.y = -0.5
	lib.add(c, notice, "高札場")
	for sd2 in [-1, 1]:
		lib.box(notice, "柱_%d" % (sd2 + 1), Vector3(0.18, 2.6, 0.18), _lmat("dark"),
			Vector3(float(sd2) * 1.2, 1.3, 0))
	lib.box(notice, "板", Vector3(2.7, 1.5, 0.1), wood, Vector3(0, 2.0, 0))
	lib.box(notice, "屋根", Vector3(3.1, 0.12, 0.6), _lmat("kawara"), Vector3(0, 2.85, 0))
	_lm_collide(notice, Vector3(2.8, 2.8, 0.6))


# ══════════════ 稗田邸：完整獨立版直接落地 ══════════════
#
# 使用者定案（完整版遷移改善書 v1）：**放棄村內縮小版**，把
# `assets/blender/make_hieda.py` 產出的完整獨立版整組搬到人間之里北緣。
# 搬的是**成品幾何本身**，不是照規格重蓋一次：
#
#   hieda_blockout.glb   22,600 面 / 1 surface / 1 draw call
#                        （主屋含唐破風玄関、格子塀、棟門、切石參道、狛犬、
#                          石燈籠、框景巨樹、水池、涸れ滝、枯山水、飛石、木戶）
#   植栽 136 實例        10 種模組 → MultiMesh，由 tools/gen_hieda.gd 發
#
# 這是 `gen_hieda.gd` 從第一天就在等的那個呼叫點；`maps/hieda/gen/*.res`
# 與 `hieda_garden.instances.json` 因此不再是孤兒。
#
# ⚠ blockout 是 Blender 那邊 join 成一份的烘焙網格：**沒有分件、沒有碰撞、
# 沒有地形、材質只有頂點色**。所以這裡要補三件事，缺一件就是放了一團看得到
# 走不進去的東西：
#   1. 地形整平（YARD_FLATTEN 97×118）—— 它假設腳下是一片水平地
#   2. `needs_trimesh` meta —— main.gd／walk_test／portal_test 都是看
#      「名字是 Terrain 或掛了這個 meta」+ 跨度 ≥15m 才建 trimesh 碰撞
#   3. 頂點色材質（`lib.vc_mat`）—— glb 自帶的材質不吃專案的材質庫
#
# ⚠ 本地座標＝blockout 自己的座標系：**+z 朝表門（朝村子）、−z 是後院**。
# 保留區中心取的是**包絡中心**，跟 blockout 的原點差 (2.45, 17.8)。
const HIEDA_OFF := TownConfig.HIEDA_OFF


## 緩衝疏林：沿保留區外緣一圈（改善書 §4）。
##
## ⚠ 改善書假設「邊界空曠處目前只有樹木與河川」，要我**保留**外緣一圈疏林
## 當過渡帶。實測不是那樣：人間之里的北緣是**空曠草地**，playable 範圍內
## 的樹只有密度層那 61 株花樹（全在街區旁），新保留區裡一株都沒有。
## 也就是說 §4 的「清林」是空操作，而「野生林地 → 精緻人工造景的生硬斷層」
## 這個問題在這個落點上根本不存在 —— 存在的是**另一個**斷層：97×118 的
## 精緻庭院直接坐在一片剃平的草地上，四周什麼都沒有。
## 所以這裡做的是規格的**意圖**而不是字面：在保留區外緣 3~9m 的環帶上撒
## 一圈疏林，把庭院的外牆接進地景，密度刻意低（環帶面積的 ~1.4 株/100㎡）。
## 讓開的地方：z=−135 那條橫街（庭院的門面動線）、南北兩條被截斷的側街。
const GROVE_SEED := TownConfig.GROVE_SEED

func _build_hieda_grove() -> void:
	var lm: Dictionary = {}
	for L in LANDMARKS:
		if L.n == "稗田邸":
			lm = L
	if lm.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = GROVE_SEED
	var hw: float = float(lm.w) * 0.5
	var hd: float = float(lm.d) * 0.5
	var cx: float = float(lm.x)
	var cz: float = float(lm.z)
	var kinds := ["res://assets/models/tree_round_a.glb",
		"res://assets/models/tree_round_c.glb", "res://assets/models/tree_pine_a.glb"]
	var batch := {}
	var tries := 0
	var n := 0
	while n < 46 and tries < 3000:
		tries += 1
		var x := rng.randf_range(cx - hw - 9.0, cx + hw + 9.0)
		var z := rng.randf_range(cz - hd - 9.0, cz + hd + 9.0)
		# 只留環帶：保留區內不種（那是庭院自己的地），環帶外也不種
		var ox: float = absf(x - cx) - hw
		var oz: float = absf(z - cz) - hd
		var out: float = maxf(ox, oz)
		if out < 3.0 or out > 9.0:
			continue
		# 門面動線讓開：橫街（z=−135，含路寬）與外參道的正前方
		if absf(z + 135.0) < 9.0:
			continue
		if absf(x - (cx + HIEDA_OFF.x)) < 9.0 and z > cz:
			continue
		if _road_info(x, z) > 0.02:
			continue
		var k: String = kinds[n % kinds.size()]
		if not batch.has(k):
			batch[k] = [] as Array[Transform3D]
		var s := rng.randf_range(0.72, 1.15)
		batch[k].append(Transform3D(
			Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis.from_scale(Vector3(s, s, s)),
			Vector3(x, height_at(x, z), z)))
		n += 1
	var g := lib.add(_root, Node3D.new(), "稗田邸緩衝林")
	var ks: Array = batch.keys()
	ks.sort()
	for k in ks:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(_village_tree_mesh(String(k)), batch[k], [],
			OUT_DIR + "gen/mm_hieda_grove_%s.res" % String(k).get_file().get_basename())
		lib.add(g, mmi, "MM_%s" % String(k).get_file().get_basename())
	_audit.append("稗田邸緩衝疏林：%d 株 / %d 種（保留區外緣 3~9m 環帶，門面動線讓開）"
		% [n, ks.size()])


## blockout 專用材質：頂點色 + **關掉背面剔除**。
##
## ⚠ 這不是「順手保險一下」，是修一個實際炸出來的洞。Blender/Cycles 預設
## **雙面渲染**，所以 make_hieda.py 那邊繞序寫錯的面在 Blender 的算圖裡看起來
## 完全正常；Godot 預設剔背面，同一批面就整片消失。第一次落地實測：整條
## 6m 切石參道（`build_avenue` 的 quad，`flip=(y1 > y0)` 在這個呼叫方向下
## 恆為 false）在引擎裡**一塊都看不到**，前庭只剩草地 —— 而後院的枯山水、
## 水池同樣是貼地 quad 卻好好的，因為那批的繞序剛好是對的。
## 逐面去修 Blender 端的繞序要重跑整條匯出鏈，而且下次加東西還會再犯；
## 關掉剔除是一次解決。代價只有背面的片段著色，blockout 才 22,600 面。
func _hieda_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.88
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.resource_name = "hieda_blockout_vc"
	return m


func _lm_hieda(g: Node3D, _spread: float) -> void:
	# 院子被 _flatten_yards 壓平；群組原點取保留區內的最低點 —— 整平之後
	# 兩者相等，仍然照算不寫死 0（哪天整平規則再改，這裡會自己跟著走）。
	var yard: float = _flatten_yards(g.position.x, g.position.z,
		bank_h(g.position.x, g.position.z)) - g.position.y
	var off := Vector3(HIEDA_OFF.x, yard, HIEDA_OFF.y)
	var body := MeshInstance3D.new()
	body.mesh = lib.prop_mesh("res://assets/models/hieda_blockout.glb", _hieda_mat())
	body.position = off
	body.set_meta("needs_trimesh", true)
	lib.add(g, body, "本體")
	# 植栽：擺位表的座標是 blockout 的本地座標，所以要掛在同一個偏移下面
	var holder := lib.add(g, Node3D.new(), "植栽") as Node3D
	holder.position = off
	var n: int = preload("res://tools/gen_hieda.gd").new().emit(lib, holder)
	_audit.append("稗田邸（完整獨立版）：blockout 22,600 面 + 植栽 %d 實例 / 10 模組" % n)


# ══════════════ 街緣設施 MIGRATE：門樓／石溝／街燈 ══════════════
#
# 舊 gen_village 的 `_build_gates` / `_build_floor_decor`（石溝）/ `_build_lamps`。
# ⚠ 這三樣的**座標一個都不能照抄** —— 舊值全綁在舊格線上（街燈吃 ST_X/ST_Z、
# 石溝寫死本通 x=±6.2、北門寫死 z=-215）。新鎮的路是 `_roads` 的折線、門在
# portal 上。搬的是**做法與比例**，位置一律從新路網重新推。照抄會撒進田裡。
#
# ⚠ 亂數：這一批一律用 `_street_rng`，而且材質全部指定色調索引（v ≥ 0）——
# 只要碰一次 `_lm_rng.randf()`，六座地標的庭園散佈就會整組換位置。
# （驗證方式：搬完之後把稗田邸子樹跟搬之前逐節點比對，位移必須是 0。）
const STREET_SEED := TownConfig.STREET_SEED

var _street_rng := RandomNumberGenerator.new()

## 門樓：擺在 portal 上，玩家一落地就是**穿門進村**。
## 舊值 (0,-215)/(-172,92) 是舊圖的村界，新圖的 portal 在 (0,-174)/(-132,100)。
const GATES := TownConfig.GATES

func _build_gates() -> void:
	var dark := _lmat("dark", 1)
	var kawara := _lmat("kawara", 1)
	var g0 := lib.add(_root, Node3D.new(), "門樓")
	for d in GATES:
		var yaw: float = float(d.yaw)
		var ax := Vector2(cos(yaw), -sin(yaw))
		var az := Vector2(sin(yaw), cos(yaw))
		# 佔地是「沿門寬 13m × 進深 2.4m」，量地面要照這個方向取樣
		var gu := _ground_under(float(d.x), float(d.z),
			absf(ax.x) * 13.0 + absf(az.x) * 2.4, absf(ax.y) * 13.0 + absf(az.y) * 2.4)
		var foot: float = float(gu[1]) + 0.35
		var g := Node3D.new()
		g.position = Vector3(float(d.x), float(gu[0]), float(d.z))
		g.rotation.y = yaw
		lib.add(g0, g, String(d.n))
		for s in [-1, 1]:
			# 柱腳往下埋「高差 + 0.35」，門跨在路上，兩側地面不會一樣高
			lib.box(g, "柱_%d" % (s + 1), Vector3(0.7, 5.0 + foot, 0.7), dark,
				Vector3(float(s) * 5.2, 2.5 - foot * 0.5, 0))
			lib.box(g, "礎石_%d" % (s + 1), Vector3(1.05, 0.3, 1.05), _lmat("stone", 0),
				Vector3(float(s) * 5.2, 0.12, 0))
			_lm_collide(g, Vector3(0.95, 5.2, 0.95), Vector3(float(s) * 5.2, 0, 0))
		lib.box(g, "樑", Vector3(12.0, 0.55, 0.9), dark, Vector3(0, 5.0, 0))
		# 貫（柱間的橫木）：舊版只有樑與簷，剪影是「兩根柱撐一片板」。
		# 補一根低位的貫，才讀得出是門而不是招牌架。
		lib.box(g, "貫", Vector3(11.0, 0.3, 0.55), dark, Vector3(0, 3.6, 0))
		lib.box(g, "簷", Vector3(13.2, 0.24, 1.8), kawara, Vector3(0, 5.5, 0))
		lib.box(g, "棟", Vector3(13.2, 0.22, 0.4), kawara, Vector3(0, 5.68, 0))
		# 保留區：町家不准蓋在門洞裡，草也不長進來
		_reserved.append([Vector2(float(d.x), float(d.z)), ax, az, 7.6, 2.4, String(d.n)])
	_audit.append("門樓 %d 座（北門在 trail 落點內側、西南門在 kourindou 引道上）" % GATES.size())


## 石溝：本通與東西大街兩側的排水溝（町方的地面語彙）。
## ⚠ 舊版一節一個 Node3D 帶 3~4 個 box —— 光本通就 150 節 = 500+ 個節點。
## 這裡照護岸的做法收成 3 個 MultiMesh（溝壁／溝底／溝蓋）。
## ⚠ 一節 3m 不是 6m，而且**每一節錨在自己中心的地面**，不是錨在
## footprint 的最低點。舊版錨最低點是為了「斜坡上不要翹起來」，但那只治了
## 一半：溝壁是沉的、埋掉沒人看得見，**溝蓋是浮的**（+0.04）—— 6m 長一片
## 壓在 0.2m 落差上，遠端就架空 0.2m。Stage 4 的本通街景截圖裡是一片
## 「掉在石板路上的板子」，還帶影子。節短一半 + 各自取樣就貼得住了。
const GUTTER_SEG := TownConfig.GUTTER_SEG
const GUTTER_COMMERCE := TownConfig.GUTTER_COMMERCE     # 石溝是町方的東西，村緣的排水是土溝

# ══════════════════════════════════════════════════════════════════════
# PHASE 3.1A：回廊の「路 → 建物」の移行層
# ══════════════════════════════════════════════════════════════════════
#
# slice で検証済みの語彙のうち、村に無かった二つを回廊にだけ足す：
#   ・縁石（路邊石）—— 石溝の外側に一列。路と路肩の境界を線として立てる
#   ・踏石 —— 各戸の**門前**から街へ。門の位置は manifest の facade.door_x
# 犬走りはモジュール側の基礎に既に入っているので足さない。
#
# ⚠ 専用 RNG。密度層の `_drng` には一切触らない（順序依存で村中がずれる）。
func _build_pilot_edge() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 4101
	var kerbs: Array[Transform3D] = []
	var steps: Array[Transform3D] = []
	# 縁石：石溝の外側（路半寬 4.0 + 溝 0.6 + 0.5）
	var t := -166.0
	while t < -80.0:
		for side in [-1.0, 1.0]:
			var px: float = side * 5.1
			kerbs.append(Transform3D(Basis(),
				Vector3(px, height_at(px, t) + 0.02, t)))
		t += 1.0
	# 踏石：門前から街へ三枚
	for e in _dump:
		if not _is_pilot(e):
			continue
		var m: Dictionary = _mods[String(e[0])]
		var fac: Dictionary = m.get("facade", {})
		if fac.is_empty():
			continue
		var pos := Vector2(float(e[1]), float(e[3]))
		var yaw: float = float(e[4])
		var fwd := Vector2(sin(yaw), cos(yaw))
		var ax := Vector2(cos(yaw), -sin(yaw))
		var dx: float = float(fac["door_x"])
		for k in 3:
			var q: Vector2 = pos + ax * (dx - 0.9 + float(k) * 0.9) \
				+ fwd * (0.55 + float(k % 2) * 0.22)
			if _pt_on_road_core(q, 1.0):
				continue
			steps.append(Transform3D(
				Basis(Vector3.UP, yaw + rng.randf_range(-0.08, 0.08)),
				Vector3(q.x, height_at(q.x, q.y) + 0.03, q.y)))
	if kerbs.is_empty() and steps.is_empty():
		return
	var g := lib.add(_root, Node3D.new(), "回廊路縁")
	# 色は石溝と同じ系統（濡れて暗い石）。明るい石は白い軌条に読める
	var kmat := lib.pbr("回廊縁石", "stone_wall", 0.42, Color(0.58, 0.58, 0.56))
	var smat := lib.pbr("回廊踏石", "stone_flag", 0.30, Color(0.62, 0.61, 0.57))
	for spec in [{"size": Vector3(1.0, 0.22, 0.16), "list": kerbs,
			"mat": kmat, "n": "路邊石"},
			{"size": Vector3(0.72, 0.11, 0.62), "list": steps,
			"mat": smat, "n": "踏石"}]:
		if (spec["list"] as Array).is_empty():
			continue
		var bm := BoxMesh.new()
		bm.size = spec["size"]
		bm.material = spec["mat"]
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(bm, spec["list"], [],
			OUT_DIR + "gen/pedge_%s.res" % String(spec["n"]))
		lib.add(g, mmi, "MM_%s" % String(spec["n"]))
	_audit.append("PHASE 3.1A：回廊の縁石 %d・踏石 %d" % [kerbs.size(), steps.size()])


# ══════════════════════════════════════════════════════════════════════
# PHASE 3.1B：北門の最初の辻 —— 「火の番の辻」
# ══════════════════════════════════════════════════════════════════════
#
# 火見櫓は最初から本通北端の**視線終点**として置かれている
# （TOWERS の "why"：本通北端終点／「框住，不是擋住路」）。
# 問題は位置ではなく、**足元に何も無いこと**だった —— 19.5m の櫓が芝の上に
# 単体で立っていると、村の設備ではなく鉄塔に読める。
#
# だからこの辻は「25m の空隙を埋める」仕事ではない。櫓に**一階を与える**
# 仕事。文字を読まなくても「この櫓は村のもので、火と警報のためにある」と
# 判るようにする。
#
# 置くもの（優先順）：半鐘 → 天水桶 → 番小屋 → 高札場 → 地蔵。
# ⚠ 交差点そのものは**空けたまま**にする。道具置き場にしない。
# ⚠ 番小屋は櫓に従属：低く・小さく・実用的に。二軒目の町家にしない。
#
# ⚠ RNG：この関数は乱数を一切使わない（全て決め打ち）。密度層の `_drng`
#   にも `_lm_rng` にも触らない —— `_lmat()` は必ず tone を明示で渡すこと
#   （省略すると `_lm_rng` を消費して地標の中身がずれる）。
func _build_pilot_node() -> void:
	var TX := 9.5                       # 火見櫓の中心
	var TZ := -132.0
	var g := lib.add(_root, Node3D.new(), "火の番の辻") as Node3D
	var dark := _lmat("dark", 1)
	var kawara := _lmat("kawara", 1)
	var wood := _lmat("wood", 0) if MAT_SET.has("wood") else _lmat("dark", 0)
	var stone := lib.pbr("辻石", "stone_wall", 0.5, Color(0.62, 0.61, 0.58))
	var placed: Array[String] = []

	# ── 1. 半鐘 ──────────────────────────────────────────────
	# 櫓の西面（本通側）に腕木を出して吊る。火事も妖怪も、まずこれが鳴る。
	# 縄は下まで垂らす —— 「人が引く物」だと判るのはこの一本のおかげ。
	# ⚠ 一度目は小さすぎ・明るすぎで、櫓の格子に紛れて**茶色い棒**に読めた
	# （t3 の近景で発覚）。鐘は「離れて見て鐘と判る」大きさが要る ——
	# 腕木を街側へ 1.9m 出し、格子ではなく**空を背に**吊る。
	var by := height_at(TX - 3.6, TZ) + 3.15
	lib.box(g, "半鐘腕木", Vector3(2.1, 0.17, 0.19), dark,
		Vector3(TX - 2.6, by + 0.46, TZ))
	lib.box(g, "半鐘方杖", Vector3(0.9, 0.13, 0.13), dark,
		Vector3(TX - 2.2, by + 0.02, TZ))
	lib.cyl(g, "半鐘吊環", 0.06, 0.06, 0.16, dark,
		Vector3(TX - 3.6, by + 0.30, TZ), 6)
	lib.cyl(g, "半鐘笠", 0.30, 0.42, 0.18,
		lib.flat_mat("半鐘銅", Color(0.155, 0.135, 0.095), 0.38),
		Vector3(TX - 3.6, by + 0.12, TZ), 14)
	lib.cyl(g, "半鐘", 0.42, 0.50, 0.66,
		lib.flat_mat("半鐘銅", Color(0.155, 0.135, 0.095), 0.38),
		Vector3(TX - 3.6, by - 0.30, TZ), 14)
	lib.cyl(g, "半鐘縄", 0.018, 0.018, 1.55,
		lib.flat_mat("辻縄", Color(0.22, 0.18, 0.12), 0.95),
		Vector3(TX - 3.6, by - 1.40, TZ), 5)
	placed.append("半鐘")

	# ── 2. 天水桶 ────────────────────────────────────────────
	# L 字に並べる：西面（本通から見える）3、南面（辻から見える）2。
	# 火消しの水は雨水を溜めておく —— 蓋を少しずらして水面を見せる。
	var tw: Array[Transform3D] = []
	for spec in [[TX - 2.6, TZ + 0.9], [TX - 2.6, TZ + 2.0], [TX - 2.6, TZ + 3.1],
			[TX - 1.3, TZ + 3.9], [TX - 0.1, TZ + 3.9]]:
		var px: float = float(spec[0])
		var pz: float = float(spec[1])
		tw.append(Transform3D(Basis(Vector3.UP, 0.2)
			* Basis.from_scale(Vector3(1.28, 1.32, 1.28)),
			Vector3(px, height_at(px, pz), pz)))
	var tmi := MultiMeshInstance3D.new()
	tmi.multimesh = lib.make_multimesh(
		lib.prop_mesh("res://assets/models/prop_taru.glb", lib.vc_mat()), tw, [],
		OUT_DIR + "gen/tsuji_tensuioke.res")
	lib.add(g, tmi, "MM_天水桶")
	placed.append("天水桶 %d" % tw.size())

	# ── 3. 番小屋 ────────────────────────────────────────────
	# ⚠ 櫓に**従属**させる。壁高 2.05m・3.0×2.6 —— 町家（軒高 3.6m 以上）
	#   より明らかに低く、屋根も片流れに近い緩勾配。夜に灯が点く唯一の窓。
	var hx := TX - 1.3
	var hz := TZ + 6.6
	var hy := height_at(hx, hz)
	var hut := lib.add(g, Node3D.new(), "番小屋") as Node3D
	hut.position = Vector3(hx, hy, hz)
	hut.rotation.y = 0.2
	lib.box(hut, "土台", Vector3(3.15, 0.18, 2.75), stone, Vector3(0, 0.09, 0))
	lib.box(hut, "壁", Vector3(3.0, 2.05, 2.6), _lmat("plaster", 1),
		Vector3(0, 1.20, 0))
	for sx in [-1.0, 1.0]:
		lib.box(hut, "隅柱_%d" % int(sx + 1.0), Vector3(0.14, 2.05, 0.14), dark,
			Vector3(sx * 1.43, 1.20, 1.23))
	lib.box(hut, "腰板", Vector3(3.06, 0.62, 2.66), dark, Vector3(0, 0.49, 0))
	# 番人が街を見る窓（本通側）。夜はここだけ灯る
	# ⚠ 「夜はここだけ灯る」と書いておきながら emissive を付けておらず、
	# 夕暮れの診断カットで真っ暗だった。番人が居ることの唯一の証拠なので、
	# 街燈と同じ既存パターンで自発光にする（光照ラウンドには入らない ——
	# 光源は足さず、材質の emission だけ）。
	lib.box(hut, "窓", Vector3(0.06, 0.72, 1.05),
		# ⚠ emission 0.85 は昼に**真っ白なパネル**として抜けた（t3）。
		# 目標は「昼は障子紙、夕方に灯る」なので、自発光は夕闇でだけ
		# 効く程度まで落とす。白い面積を作らない。
		lib.flat_mat("番小屋灯", Color(0.74, 0.67, 0.53), 0.55,
			Color(0.24, 0.17, 0.08)),
		Vector3(-1.52, 1.45, 0.1))
	lib.gable_roof(hut, 2.25, 3.5, 3.1, 0.30, 0.14, kawara, dark)
	_lm_collide(hut, Vector3(3.1, 2.3, 2.7))
	placed.append("番小屋")

	# ── 4. 高札場 ────────────────────────────────────────────
	# 辻の西側。火の用心の触れも、妖怪の警告も、ここに貼られる。
	var nx := -6.6
	var nz := -133.4
	var ny := height_at(nx, nz)
	var notice := lib.add(g, Node3D.new(), "高札場") as Node3D
	notice.position = Vector3(nx, ny, nz)
	notice.rotation.y = -PI * 0.5 + 0.18          # 板面が本通を向く
	for sd in [-1.0, 1.0]:
		lib.box(notice, "柱_%d" % int(sd + 1.0), Vector3(0.16, 2.5, 0.16), dark,
			Vector3(sd * 1.05, 1.25, 0))
	lib.box(notice, "板", Vector3(2.4, 1.35, 0.09),
		lib.pbr("高札板", "planks", 0.5, Color(0.70, 0.62, 0.50)),
		Vector3(0, 1.88, 0))
	lib.box(notice, "屋根", Vector3(2.8, 0.11, 0.55), kawara, Vector3(0, 2.68, 0))
	_lm_collide(notice, Vector3(2.5, 2.6, 0.55))
	placed.append("高札場")

	# ── 5. 地蔵 ──────────────────────────────────────────────
	# **門を向く**。村に入る者を迎え、出る者を送る。旅の無事の方の地蔵。
	var jx := -6.5
	var jz := -139.6
	var jy := height_at(jx, jz)
	var jz3 := lib.add(g, Node3D.new(), "辻地蔵") as Node3D
	jz3.position = Vector3(jx, jy, jz)
	jz3.rotation.y = PI                            # 北（門）を向く
	lib.box(jz3, "台座", Vector3(0.86, 0.30, 0.72), stone, Vector3(0, 0.15, 0))
	lib.cyl(jz3, "地蔵身", 0.19, 0.22, 0.62, stone, Vector3(0, 0.61, 0), 10)
	lib.cyl(jz3, "地蔵頭", 0.17, 0.17, 0.28, stone, Vector3(0, 1.06, 0), 10)
	lib.box(jz3, "前掛", Vector3(0.36, 0.34, 0.05),
		lib.flat_mat("辻前掛", Color(0.52, 0.13, 0.11), 0.85),
		Vector3(0, 0.70, -0.21))
	for sd2 in [-1.0, 1.0]:
		lib.box(jz3, "祠柱_%d" % int(sd2 + 1.0), Vector3(0.09, 1.42, 0.09), dark,
			Vector3(sd2 * 0.52, 0.71, 0.16))
	lib.box(jz3, "祠屋根", Vector3(1.32, 0.10, 0.92), kawara, Vector3(0, 1.50, 0.0))
	_lm_collide(jz3, Vector3(1.3, 1.6, 0.95))
	placed.append("辻地蔵")

	# ── 樹（任意項目）──
	# 機能要素を置いたあと、西側が空のままで櫓の質量と釣り合わなかった
	# （t2 で確認）。日陰と額縁のために**一本だけ**。並木にはしない。
	var tx2 := -8.8
	var tz2 := -136.4
	var tree := MeshInstance3D.new()
	tree.mesh = _village_tree_mesh("res://assets/models/tree_round_a.glb")
	tree.position = Vector3(tx2, height_at(tx2, tz2), tz2)
	tree.rotation.y = 0.6
	tree.scale = Vector3(1.15, 1.2, 1.15)
	lib.add(g, tree, "辻の樹")
	placed.append("樹")

	# 辻の足元の草を抜く（乱数不使用・buffer 直読み。共有 helper）
	var foot := [[Vector2(hx, hz), 2.1, 1.8], [Vector2(nx, nz), 1.5, 0.7],
			[Vector2(jx, jz), 1.0, 0.8], [Vector2(TX - 2.0, TZ + 2.4), 2.4, 2.6],
			[Vector2(tx2, tz2), 1.3, 1.3]]
	var cut := _cut_grass(foot)
	_audit.append("PHASE 3.1B 火の番の辻：%s（足元の草 %d 叢を除去）"
		% [", ".join(placed), cut])


# ══════════════════════════════════════════════════════════════════════
# PHASE 3.2A：本通の視線を割る 3 つの civic node（診断用の増分）
# ══════════════════════════════════════════════════════════════════════
#
# 測ったこと：本通 490m の**軸上（|x|<4）には一つも物が無い**。さらに
# ブロックの正面線を並べると z −83.9 〜 +90.1 の **174m** に本通の
# frontage が一切無い —— 村の中心で街に壁が無い。これが「空っぽの大通り」
# の正体で、遠景の話ではなかった。
#
# ⚠ これは 174m を飾る仕事ではない。**少数の意図的な node で律動が戻るか**
#   を試す診断。町家は足さない。道も地標も動かさない。
#
# ⚠ PLAZA(0,30) と MAIN_EW_Z(30.0) は同じ座標 —— 「広場の縁」と
#   「MAIN_EW の辻」は同じ場所なので、三つ目は z=+85 の横街に置いた。
#
# 三つは**機能・剪影・素材がすべて違う**（同じ語彙を三度繰り返さない）：
#   N1 地面の出来事（低く広い・木と布）… 視線を近景へ落とす
#   N2 水平の遮蔽（軒 2.7m の上屋）  … 消失点そのものを切る
#   N3 垂直の額縁（石灯籠の対）      … channel を絞る
#
# ⚠ RNG は一切使わない。草より後に建て、足元の草はフィルタで抜く
#   （3.1B と同じ手 —— _reserved に足すと草の抽選が村中でずれる）。
func _build_sight_nodes() -> void:
	var g := lib.add(_root, Node3D.new(), "本通の節") as Node3D
	var dark := _lmat("dark", 1)
	var kawara := _lmat("kawara", 1)
	# ⚠ uv1_scale は「大きいほど細かい」。0.5（＝2m タイル）だと 0.34m 角の
	#   灯籠の竿には目地が一本も乗らず、ただの黒い棒になる（初回の描画）。
	#   小物の石は 2.2（≒45cm タイル）で積みが読めるところまで細かくする。
	var stone := lib.pbr("節石", "stone_wall", 2.2, Color(0.74, 0.73, 0.70))
	var plank := lib.pbr("節板", "planks", 0.5, Color(0.62, 0.55, 0.44))
	var made: Array[String] = []
	var foot: Array = []

	# ⚠ 街燈は路縁 4.0＋1.3＝x±5.3 に立つ。節を x±6〜8 の同じ z に置くと、
	#   3.2m の鉄柱がちょうど節の正面に重なって節を縦に two つに割る
	#   （最初の描画で井戸も灯籠もそうなった）。街燈の実位置を読んで避ける。
	#   ※ 街燈側は乱数を使っていないので、ここで位置を読んでも抽選は動かない。
	var lamps: Array[Vector2] = []
	var lg := _root.get_node_or_null("街燈")
	if lg != null:
		for c in lg.get_children():
			if c is Node3D:
				lamps.append(Vector2((c as Node3D).position.x, (c as Node3D).position.z))
	var lamp_gap := func(p: Vector2) -> float:
		var best := 1e9
		for q in lamps:
			best = minf(best, p.distance_to(q))
		return best
	var dodge_lamp := func(p: Vector2, want: float) -> Vector2:
		for step in [0.0, 3.0, -3.0, 6.0, -6.0, 9.0, -9.0, 12.0, -12.0]:
			var c := Vector2(p.x, p.y + float(step))
			if lamp_gap.call(c) >= want:
				return c
		return p

	# ── N1：共同井戸（z=−52、寺子屋と鈴奈庵のあいだ）─────────────
	# 寺子屋の保留区は x −40.2..−11.8、鈴奈庵は x 5.2..18.0。
	# 西側の x=−6.8 がちょうど空いている（本通の路縁 −4.0 の外）。
	var w1: Vector2 = dodge_lamp.call(Vector2(-6.9, -52.0), 6.5)
	if not _pt_reserved(w1, 1.6):
		var y1 := height_at(w1.x, w1.y)
		var well := lib.add(g, Node3D.new(), "共同井戸") as Node3D
		well.position = Vector3(w1.x, y1, w1.y)
		well.rotation.y = 0.24
		for k in 8:                                    # 井筒（石を輪に）
			# ⚠ lib.box() は回転を取らない（引数は 5 つ）。返ってきた
			#   MeshInstance3D を自分で回す —— 石の薄い面（z=0.24）を半径方向へ。
			var a := TAU * float(k) / 8.0
			var st := lib.box(well, "井筒_%d" % k, Vector3(0.34, 0.52, 0.24), stone,
				Vector3(cos(a) * 0.72, 0.26, sin(a) * 0.72))
			st.rotation.y = PI * 0.5 - a
		lib.cyl(well, "井口", 0.62, 0.62, 0.06, dark, Vector3(0, 0.56, 0), 12)
		for sd in [-1.0, 1.0]:                          # 井桁
			lib.box(well, "井桁柱_%d" % int(sd + 1.0), Vector3(0.11, 1.9, 0.11),
				dark, Vector3(sd * 0.86, 0.95, 0))
		lib.box(well, "井桁梁", Vector3(1.94, 0.12, 0.12), dark, Vector3(0, 1.86, 0))
		lib.cyl(well, "滑車", 0.15, 0.15, 0.11, dark, Vector3(0, 1.72, 0), 8)
		lib.gable_roof(well, 1.98, 2.5, 2.2, 0.42, 0.13, kawara, dark)
		_lm_collide(well, Vector3(2.1, 1.9, 2.1))
		# 洗い場と縁台 —— 低く横に広がる「地面の出来事」
		lib.box(g, "洗い場", Vector3(2.1, 0.14, 1.5), stone,
			Vector3(w1.x - 1.9, height_at(w1.x - 1.9, w1.y + 1.7) + 0.07, w1.y + 1.7))
		var bx := w1.x - 0.4
		var bz := w1.y + 3.4
		lib.box(g, "縁台_座", Vector3(1.7, 0.09, 0.52), plank,
			Vector3(bx, height_at(bx, bz) + 0.42, bz))
		for sx in [-1.0, 1.0]:
			lib.box(g, "縁台_脚_%d" % int(sx + 1.0), Vector3(0.09, 0.40, 0.42),
				dark, Vector3(bx + sx * 0.72, height_at(bx, bz) + 0.20, bz))
		made.append("N1 共同井戸")
		foot.append([w1, 2.4, 3.0])

	# ── N2：荷継の上屋（z=+30、MAIN_EW の辻）─────────────────
	# 市場の保留区が西側 x −44.6..−7.4 / z 40..74 を占めるので東側へ。
	# ⚠ 初版は「左右対称・細い同断面の柱 6 本・薄い切妻・床なし」で、
	#   **現代のバス停の図**そのものだった（Art Review の指摘）。直しは
	#   対称を壊すことから：背面（東）を板壁で塞いで片流れ気味に葺き下ろし、
	#   柱は沓石に載せて貫と方杖を通し、軒下に垂木を見せ、土間を敷く。
	var w2: Vector2 = dodge_lamp.call(Vector2(8.4, 41.0), 5.5)
	if not _pt_reserved(w2, 2.4):
		var y2 := height_at(w2.x, w2.y)
		var uwa := lib.add(g, Node3D.new(), "上屋") as Node3D
		uwa.position = Vector3(w2.x, y2, w2.y)
		uwa.rotation.y = -0.12
		# 土間：踏み固めた土＋石の縁 —— 芝の上に浮いていた足元を地面に接ぐ
		lib.box(uwa, "土間", Vector3(6.4, 0.12, 4.6),
			lib.pbr("上屋土間", "terrain_path", 0.9, Color(0.72, 0.66, 0.56)),
			Vector3(0, 0.05, 0.2))
		for sz in [-2.05, 2.45]:
			lib.box(uwa, "土間縁", Vector3(6.4, 0.14, 0.22), stone, Vector3(0, 0.07, sz))
		# 柱：背面（東）3 本が高く、前（西・街側）3 本が低い ——
		# 背の壁に凭れる**下屋（лean-to）**。全て沓石（礎石）に載せる。
		# ⚠ 初版は前後差 0.6m を 4.7m の屋根に割った勾配 7° で、眼高から
		#   見ると屋根が**厚みのない一枚の線**に消えた（描画で確認）。
		#   勾配は前後の桁で作る：後桁 3.06 → 前桁 2.46。
		for i in 3:
			var px := -2.55 + float(i) * 2.55
			lib.box(uwa, "沓石_w%d" % i, Vector3(0.34, 0.26, 0.34), stone,
				Vector3(px, 0.16, -1.55))
			lib.box(uwa, "柱_w%d" % i, Vector3(0.16, 2.10, 0.16), dark,
				Vector3(px, 0.29 + 1.05, -1.55))
			lib.box(uwa, "沓石_e%d" % i, Vector3(0.34, 0.26, 0.34), stone,
				Vector3(px, 0.16, 1.75))
			lib.box(uwa, "柱_e%d" % i, Vector3(0.16, 2.70, 0.16), dark,
				Vector3(px, 0.29 + 1.35, 1.75))
		# 貫（腰の高さで三方を回す）と方杖（前桁を斜めに受ける）
		lib.box(uwa, "貫_前", Vector3(5.3, 0.10, 0.14), dark, Vector3(0, 0.98, -1.55))
		lib.box(uwa, "貫_後", Vector3(5.3, 0.10, 0.14), dark, Vector3(0, 0.98, 1.75))
		for sxk in [-1.0, 1.0]:
			lib.box(uwa, "貫_妻", Vector3(0.14, 0.10, 3.3), dark,
				Vector3(sxk * 2.55, 0.98, 0.1))
			var hj := lib.box(uwa, "方杖", Vector3(0.11, 0.90, 0.11), dark,
				Vector3(sxk * 2.35, 2.02, -1.42))
			hj.rotation.z = sxk * 0.6
		# 桁：後ろ（壁側）が高く、前（街側）が低い
		lib.box(uwa, "桁_前", Vector3(5.9, 0.17, 0.17), dark, Vector3(0, 2.46, -1.55))
		lib.box(uwa, "桁_後", Vector3(5.9, 0.17, 0.17), dark, Vector3(0, 3.06, 1.75))
		# 垂木：前後の桁に渡す（軒下に木の目が並ぶ —— バス停との決定的な差）
		for i in 8:
			var rx := -2.75 + float(i) * (5.5 / 7.0)
			var rf := lib.box(uwa, "垂木_%d" % i, Vector3(0.09, 0.09, 4.9), dark,
				Vector3(rx, 2.80, 0.10))
			rf.rotation.x = -0.181
		# 一枚屋根を**街へ葺き下ろす**（後高・前低の下屋）
		var slope := lib.box(uwa, "屋根面", Vector3(6.5, 0.15, 5.3), kawara,
			Vector3(0, 2.94, 0.10))
		slope.rotation.x = -0.181
		lib.box(uwa, "棟押え", Vector3(6.54, 0.14, 0.30), dark, Vector3(0, 3.42, 2.15))
		for sxk in [-1.0, 1.0]:                        # 破風板（妻の小口を隠す）
			var hf := lib.box(uwa, "破風_%d" % int(sxk + 1.0),
				Vector3(0.07, 0.17, 5.35), dark, Vector3(sxk * 3.26, 2.93, 0.10))
			hf.rotation.x = -0.181
		# 背面の板壁（腰から後桁まで。西＝街側だけが開く）
		lib.box(uwa, "背板壁", Vector3(5.2, 1.90, 0.07),
			lib.pbr("上屋板壁", "planks", 1.6, Color(0.62, 0.55, 0.45)),
			Vector3(0, 1.90, 1.72))
		_lm_collide(uwa, Vector3(5.6, 2.9, 3.6), Vector3(0, 0, 0.1))
		# 荷：土間の上に俵と木箱 —— 「継立の場」だと判る最小限
		var ni := MeshInstance3D.new()
		ni.mesh = lib.prop_mesh("res://assets/models/prop_tawara.glb")
		ni.position = Vector3(1.5, 0.12, 0.6)
		ni.rotation.y = 0.4
		lib.add(uwa, ni, "俵")
		var nc := MeshInstance3D.new()
		nc.mesh = lib.prop_mesh("res://assets/models/prop_crate.glb")
		nc.position = Vector3(-1.6, 0.12, 0.9)
		nc.rotation.y = -0.25
		lib.add(uwa, nc, "木箱")
		made.append("N2 上屋")
		foot.append([w2, 3.6, 2.8])

	# ── N3：常夜灯の対＋道標（z=+85 の横街）──────────────────
	# 石・細い垂直。channel を絞るだけで塞がない。
	# 対で門に見せたいので、z は左右**共通**の一つを選ぶ（片側だけずらすと
	#   遠近が食い違って対に見えない —— 一度そうなった）。
	var z3 := 78.0
	for step in [0.0, 3.0, -3.0, 6.0, -6.0, 9.0, -9.0, 12.0, -12.0]:
		var zc: float = 78.0 + float(step)
		if minf(lamp_gap.call(Vector2(-6.3, zc)), lamp_gap.call(Vector2(6.3, zc))) >= 7.0:
			z3 = zc
			break
	var placed3 := 0
	var west3 := Vector2(-6.3, z3)
	for sx2 in [-1.0, 1.0]:
		var w3 := Vector2(sx2 * 6.3, z3)
		if _pt_reserved(w3, 1.2) or lamp_gap.call(w3) < 7.0:
			continue
		var y3 := height_at(w3.x, w3.y)
		var lan := lib.add(g, Node3D.new(), "常夜灯_%d" % int(sx2 + 1.0)) as Node3D
		lan.position = Vector3(w3.x, y3, w3.y)
		lib.box(lan, "基壇", Vector3(1.05, 0.34, 1.05), stone, Vector3(0, 0.17, 0))
		lib.box(lan, "竿", Vector3(0.34, 1.85, 0.34), stone, Vector3(0, 1.26, 0))
		lib.box(lan, "中台", Vector3(0.66, 0.16, 0.66), stone, Vector3(0, 2.26, 0))
		lib.box(lan, "火袋", Vector3(0.58, 0.62, 0.58),
			lib.flat_mat("常夜灯火", Color(0.80, 0.73, 0.58), 0.55,
				Color(0.22, 0.16, 0.07)), Vector3(0, 2.65, 0))
		lib.box(lan, "笠", Vector3(0.94, 0.20, 0.94), stone, Vector3(0, 3.06, 0))
		lib.box(lan, "宝珠", Vector3(0.22, 0.26, 0.22), stone, Vector3(0, 3.29, 0))
		_lm_collide(lan, Vector3(1.0, 3.4, 1.0))
		foot.append([w3, 1.0, 1.0])
		if sx2 < 0.0:
			west3 = w3
		placed3 += 1
	if placed3 > 0:
		var dz2 := Vector2(west3.x, west3.y - 3.4)   # 道標は西の灯籠の手前に立てる
		if not _pt_reserved(dz2, 1.0):
			var y4 := height_at(dz2.x, dz2.y)
			lib.box(g, "道標", Vector3(0.30, 1.42, 0.26), stone,
				Vector3(dz2.x, y4 + 0.71, dz2.y))
			foot.append([dz2, 0.7, 0.7])
		made.append("N3 常夜灯 %d ＋道標" % placed3)

	# 足元の草を抜く（乱数不使用・buffer 直読み。共有 helper）
	var cut := _cut_grass(foot)
	_audit.append("PHASE 3.2A 本通の節：%s（足元の草 %d 叢を除去）"
		% [", ".join(made), cut])


# ══════════════════════════════════════════════════════════════════════
# PHASE 5A-V：市場區の機能的な設え
# ══════════════════════════════════════════════════════════════════════
#
# 「なぜこの物がここに在るのか」に答えられる物だけを置く。飾りは足さない。
#   荷揚げ台 … 蔵と広場の間で荷が動いている証拠
#   仕事庇   … 作業場の前で実際に作業する場所（生産が見える）
#   見世台   … 常設店が広場に向かって商う面
#   荷置き   … 屋台が仕舞われている間の在庫（西縁）
#   飛石     … 市木戸から南縁の店へ、雨の日の動線
#
# ⚠ RNG は一切使わない。草より後に建て、足元の草はフィルタで抜く
#   （3.1B/3.2A と同じ手 —— _reserved に足すと村中の草の抽選がずれる）。
func _build_market_quarter() -> void:
	var g := lib.add(_root, Node3D.new(), "市場區の設え") as Node3D
	var dark := _lmat("dark", 1)
	var wood := _lmat("wood", 0)
	var plank := lib.pbr("市場板", "planks", 0.55, Color(0.66, 0.58, 0.46))
	var stone := lib.pbr("市場踏石", "stone_wall", 2.0, Color(0.70, 0.69, 0.66))
	var made: Array[String] = []
	var foot: Array = []

	# ── 1. 荷揚げ台（蔵の広場側）────────────────────────────────
	# 蔵は横街に面して立つ。背面（z≈74.2）が広場に向くので、そこが荷捌き場。
	# 台は地面より 0.45m 高い —— 荷車の床と同じ高さ、というのが理由。
	var lx := -46.5
	var lz := 73.0
	var ly := height_at(lx, lz)
	var plat := lib.add(g, Node3D.new(), "荷揚げ台") as Node3D
	plat.position = Vector3(lx, ly, lz)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			lib.box(plat, "束石_%d%d" % [int(sx + 1.0), int(sz + 1.0)],
				Vector3(0.34, 0.30, 0.34), stone, Vector3(sx * 1.45, 0.15, sz * 0.78))
	lib.box(plat, "台板", Vector3(3.60, 0.16, 2.10), plank, Vector3(0, 0.45, 0))
	lib.box(plat, "縁桁", Vector3(3.72, 0.13, 0.13), dark, Vector3(0, 0.35, 1.06))
	lib.box(plat, "踏段", Vector3(1.30, 0.15, 0.42), plank, Vector3(-0.9, 0.22, 1.32))
	_lm_collide(plat, Vector3(3.7, 0.55, 2.2))
	for spec in [["prop_tawara", -47.6, 72.5, 0.30, 0.53],
			["prop_tawara", -47.6, 73.4, 0.34, 0.53],
			["prop_tawara", -47.5, 72.95, 0.10, 0.86],
			["prop_crate", -45.4, 73.2, -0.4, 0.53]]:
		var mi := MeshInstance3D.new()
		mi.mesh = lib.prop_mesh("res://assets/models/%s.glb" % String(spec[0]))
		mi.position = Vector3(float(spec[1]),
			height_at(lx, lz) + float(spec[4]), float(spec[2]))
		mi.rotation.y = float(spec[3])
		lib.add(g, mi, "蔵荷_%s_%d" % [String(spec[0]), int(float(spec[4]) * 100.0)])
	made.append("荷揚げ台と俵")
	foot.append([Vector2(lx, lz), 2.4, 1.8])

	# ── 2. 仕事庇（作業場の前）──────────────────────────────────
	# 作業場は市場に正面（z≈72.7）を向く。その前 2.5m に葭簀掛けの下屋を出す。
	# 軒 2.45m ＝ 町家の軒より低い。従属した仮設だと一目で判る高さにする。
	var wx := -34.0
	var wz := 70.0
	var wy := height_at(wx, wz)
	var can := lib.add(g, Node3D.new(), "仕事庇") as Node3D
	can.position = Vector3(wx, wy, wz)
	for sx2 in [-1.0, 1.0]:
		for sz2 in [-1.0, 1.0]:
			lib.strut(can, "庇柱_%d%d" % [int(sx2 + 1.0), int(sz2 + 1.0)],
				Vector3(sx2 * 2.55, 0.0, sz2 * 1.35),
				Vector3(sx2 * 2.55, 2.32 + sz2 * 0.13, sz2 * 1.35), 0.075, dark, 6)
	lib.box(can, "桁前", Vector3(5.30, 0.13, 0.12), dark, Vector3(0, 2.20, -1.35))
	lib.box(can, "桁後", Vector3(5.30, 0.13, 0.12), dark, Vector3(0, 2.46, 1.35))
	for i in 9:
		var rx := -2.35 + float(i) * 0.59
		var rf := lib.box(can, "垂木_%d" % i, Vector3(0.09, 0.06, 2.86), dark,
			Vector3(rx, 2.36, 0))
		rf.rotation.x = -0.09
	var yoshi := lib.box(can, "葭簀", Vector3(5.30, 0.05, 2.90),
		lib.pbr("葭簀", "planks", 1.6, Color(0.74, 0.66, 0.45)), Vector3(0, 2.42, 0))
	yoshi.rotation.x = -0.09
	# 作業台と材の staging —— 「ここで何かが作られている」の最小の証拠
	lib.box(can, "作業台", Vector3(2.10, 0.10, 0.86), plank, Vector3(-0.8, 0.78, 0.15))
	for sx3 in [-1.0, 1.0]:
		lib.box(can, "台脚_%d" % int(sx3 + 1.0), Vector3(0.11, 0.73, 0.78), wood,
			Vector3(-0.8 + sx3 * 0.92, 0.37, 0.15))
	for i2 in 5:
		lib.box(can, "材_%d" % i2, Vector3(2.60, 0.11, 0.13), wood,
			Vector3(1.55, 0.09 + float(i2 % 3) * 0.12, -0.65 + float(i2 / 3) * 0.30))
	_lm_collide(can, Vector3(5.4, 2.5, 2.9))
	for spec2 in [["prop_takigi", -36.9, 71.2, 0.25], ["prop_takigi", -36.9, 70.1, 0.25],
			["prop_taru", -31.3, 71.4, -0.5]]:
		var mi2 := MeshInstance3D.new()
		mi2.mesh = lib.prop_mesh("res://assets/models/%s.glb" % String(spec2[0]))
		mi2.position = Vector3(float(spec2[1]),
			height_at(float(spec2[1]), float(spec2[2])), float(spec2[2]))
		mi2.rotation.y = float(spec2[3])
		lib.add(g, mi2, "作業荷_%s_%d" % [String(spec2[0]), int(float(spec2[2]))])
	made.append("仕事庇と材")
	foot.append([Vector2(wx, wz), 3.4, 2.4])

	# ── 3. 見世台（南縁の常設店の店先）──────────────────────────
	# 常設店が広場に向かって商う面。屋台との違いは「毎日そこに在る」こと。
	for spec3 in [["prop_misedai", -22.6, 71.4, 0.0], ["prop_zaru", -20.2, 71.5, 0.4],
			["prop_kago", -19.4, 71.9, -0.2], ["prop_crate", -23.9, 71.9, 0.15],
			["prop_taru", -24.6, 72.2, 0.6]]:
		var mi3 := MeshInstance3D.new()
		mi3.mesh = lib.prop_mesh("res://assets/models/%s.glb" % String(spec3[0]))
		mi3.position = Vector3(float(spec3[1]),
			height_at(float(spec3[1]), float(spec3[2])), float(spec3[2]))
		mi3.rotation.y = float(spec3[3])
		lib.add(g, mi3, "店先_%s_%d" % [String(spec3[0]), int(-float(spec3[1]))])
	made.append("見世台と店先の荷")
	foot.append([Vector2(-22.0, 71.7), 3.6, 1.4])

	# ── 4. 西縁の荷置き ─────────────────────────────────────────
	# 市の通りの突き当たり。屋台が仕舞われている間の在庫が積んである。
	var sx4 := -42.2
	var sz4 := 66.6
	var sy4 := height_at(sx4, sz4)
	var rack := lib.add(g, Node3D.new(), "荷置き") as Node3D
	rack.position = Vector3(sx4, sy4, sz4)
	rack.rotation.y = -PI * 0.5
	lib.box(rack, "簀の子", Vector3(2.80, 0.10, 1.50), plank, Vector3(0, 0.10, 0))
	for sz5 in [-1.0, 1.0]:
		lib.box(rack, "枕木_%d" % int(sz5 + 1.0), Vector3(2.90, 0.12, 0.14), dark,
			Vector3(0, 0.06, sz5 * 0.62))
	_lm_collide(rack, Vector3(2.9, 0.3, 1.6))
	for spec4 in [["prop_tawara", -42.4, 65.9, 1.55, 0.16],
			["prop_tawara", -42.4, 66.8, 1.55, 0.16],
			["prop_tawara", -42.3, 66.35, 1.55, 0.49],
			["prop_crate", -41.6, 67.5, 0.2, 0.16],
			["prop_zaru", -43.0, 67.7, -0.3, 0.0]]:
		var mi4 := MeshInstance3D.new()
		mi4.mesh = lib.prop_mesh("res://assets/models/%s.glb" % String(spec4[0]))
		mi4.position = Vector3(float(spec4[1]),
			sy4 + float(spec4[4]), float(spec4[2]))
		mi4.rotation.y = float(spec4[3])
		lib.add(g, mi4, "西荷_%s_%d" % [String(spec4[0]), int(float(spec4[4]) * 100.0)])
	made.append("西縁の荷置き")
	foot.append([Vector2(sx4, sz4), 2.2, 2.2])

	# ── 5. 飛石（市木戸 → 南縁の店）────────────────────────────
	# 石畳は入口だけ。そこから先は土間なので、雨の日の動線を飛石で示す。
	for i3 in 7:
		var t := float(i3) / 6.0
		var px := lerpf(-14.2, -19.4, t)
		var pz := lerpf(66.4, 71.6, t)
		var st := lib.box(g, "飛石_%d" % i3, Vector3(0.62, 0.09, 0.52), stone,
			Vector3(px, height_at(px, pz) + 0.045, pz))
		st.rotation.y = 0.22 * float(i3 % 3 - 1)
	made.append("飛石 7")
	foot.append([Vector2(-16.8, 69.0), 3.6, 3.6])

	var cut := _cut_grass(foot)
	_audit.append("PHASE 5A-V 市場區の設え：%s（足元の草 %d 叢を除去）"
		% [", ".join(made), cut])


## 足元の草取り（共有 helper）。⚠ get_instance_transform は headless の
## dummy レンダラーでは**単位行列しか返さない**（check_map が同じ坑を
## 踏んで buffer 読みに直している）。ここも buffer を stride 12 で直接
## 読み書きする —— 3.1B/3.2A のフィルタは実は一度も発火していなかった
## （"0 叢を除去" は「無かった」ではなく「読めていなかった」）。
func _cut_grass(foot: Array) -> int:
	const GN := ["Shrubs", "Ferns", "GrassTall", "GrassFlower", "Reeds"]
	var cut := 0
	for ch in _root.get_children():
		if not (ch is MultiMeshInstance3D) or not (String(ch.name) in GN):
			continue
		var mm: MultiMesh = (ch as MultiMeshInstance3D).multimesh
		var buf: PackedFloat32Array = mm.buffer
		var stride := 12
		var keep := PackedFloat32Array()
		var kept := 0
		for i in mm.instance_count:
			var o := i * stride
			var q := Vector2(buf[o + 3], buf[o + 11])
			var hit := false
			for f in foot:
				var dd: Vector2 = q - (f[0] as Vector2)
				if absf(dd.x) < float(f[1]) and absf(dd.y) < float(f[2]):
					hit = true
					break
			if hit:
				cut += 1
			else:
				keep.append_array(buf.slice(o, o + stride))
				kept += 1
		if kept != mm.instance_count:
			var nm2 := MultiMesh.new()
			nm2.transform_format = MultiMesh.TRANSFORM_3D
			nm2.mesh = mm.mesh
			nm2.instance_count = kept
			nm2.buffer = keep
			(ch as MultiMeshInstance3D).multimesh = nm2
	return cut


# ══════════════ Main Street batch：本通の街並みの回復 ══════════════
#
# 達成条件：北から南へ歩いたとき、本通が「畑の中を通る道」ではなく
# 「人の住む町の通り」として連続して読めること。
#
# 手段は地標の**正面の延長**（塀・門・鳥居・幟・蔵・前庭）であって、
# 地標本体の移動ではない。路軸と路幅・地標の同一性・portal・動線・
# 承認済みの北門／火の番の構図は触らない。
#
# ⚠ 乱数は使わない（全て決め打ち）。lm_ghost の孤児碰撞検査があるので、
#   **碰撞体は地標保留区の外にだけ**置く。保留区の縁より内側の要素
#   （鳥居・玉垣）は見た目だけにして碰撞体を付けない。
func _build_mainstreet() -> void:
	var g := lib.add(_root, Node3D.new(), "本通の街並") as Node3D
	var dark := lib.pbr("塀柱", "dark_wood", 2.2, Color(0.34, 0.32, 0.29))
	# ⚠ shitami テクスチャはこの縮尺で扇形の柄に読める（描画で確認）。
	#   板塀は素直に planks。
	var itaita := lib.pbr("塀板", "planks", 3.4, Color(0.50, 0.44, 0.37))
	var stone := lib.pbr("街石", "stone_flag", 1.6, Color(0.55, 0.56, 0.54))
	var kawara := _lmat("kawara", 1)
	var made: Array[String] = []
	var foot: Array = []

	# ── 板塀 builder（柱＋下見板＋笠木。gap は門の開口）───────────
	var fence := func(fg: Node3D, fx: float, z0: float, z1: float, gaps: Array,
			h := 1.7, collide := true) -> void:
		var t := z0
		var pn := 0
		while t < z1 - 0.1:
			var seg_end := minf(t + 1.9, z1)
			var in_gap := false
			for gp in gaps:
				if t < float(gp[1]) and seg_end > float(gp[0]):
					in_gap = true
					break
			var y := height_at(fx, (t + seg_end) * 0.5)
			if not in_gap:
				lib.box(fg, "塀板_%d_%d" % [int(fx * 10.0), pn],
					Vector3(0.08, h - 0.26, seg_end - t - 0.13), itaita,
					Vector3(fx, y + 0.18 + (h - 0.26) * 0.5, (t + seg_end) * 0.5))
				lib.box(fg, "塀笠_%d_%d" % [int(fx * 10.0), pn],
					Vector3(0.16, 0.09, seg_end - t + 0.05), dark,
					Vector3(fx, y + h - 0.02, (t + seg_end) * 0.5))
			lib.box(fg, "塀柱_%d_%d" % [int(fx * 10.0), pn],
				Vector3(0.14, h + 0.08, 0.14), dark,
				Vector3(fx, height_at(fx, t) + (h + 0.08) * 0.5, t))
			t = seg_end
			pn += 1
		lib.box(fg, "塀柱_%d_end" % int(fx * 10.0), Vector3(0.14, h + 0.08, 0.14),
			dark, Vector3(fx, height_at(fx, z1) + (h + 0.08) * 0.5, z1))
		if collide:
			for gp2 in [[z0, gaps[0][0] if gaps.size() > 0 else z1],
					[gaps[0][1] if gaps.size() > 0 else z1, z1]]:
				var a2 := float(gp2[0])
				var b2 := float(gp2[1])
				if b2 - a2 < 0.5:
					continue
				var body := StaticBody3D.new()
				fg.add_child(body)
				body.owner = _root
				var cs := CollisionShape3D.new()
				var bx := BoxShape3D.new()
				bx.size = Vector3(0.25, h, b2 - a2)
				cs.shape = bx
				cs.position = Vector3(fx, height_at(fx, (a2 + b2) * 0.5) + h * 0.5,
					(a2 + b2) * 0.5)
				body.add_child(cs)
				cs.owner = _root

	# ── 棟門 builder（塀の開口に小さな切妻の屋根門）─────────────
	var mune := func(fg: Node3D, fx: float, fz: float, w: float) -> void:
		var y := height_at(fx, fz)
		var mn := lib.add(fg, Node3D.new(), "門_%d" % int(fz)) as Node3D
		mn.position = Vector3(fx, y, fz)
		for sd in [-1.0, 1.0]:
			lib.box(mn, "門柱_%d" % int(sd + 1.0), Vector3(0.19, 2.30, 0.19), dark,
				Vector3(0, 1.15, sd * w * 0.5))
		lib.box(mn, "冠木", Vector3(0.17, 0.20, w + 0.55), dark, Vector3(0, 2.22, 0))
		lib.gable_roof(mn, 2.42, 1.30, w + 0.95, 0.42, 0.11, kawara, dark)
		# 敷石（門から路肩へ）
		for i in 3:
			lib.box(fg, "門敷石_%d_%d" % [int(fz), i], Vector3(0.95, 0.07, 0.75), stone,
				Vector3(fx + (0.55 + float(i) * 0.85) * (1.0 if fx < 0.0 else -1.0) * -1.0,
					height_at(fx, fz) + 0.02, fz))

	# ── 1. 寺子屋の正面（西・z −62..−44）：板塀＋棟門 ─────────────
	# 保留区の東縁は x −11.8。塀は −8.2（保留区の外）。N1 共同井戸（−6.9,−52）
	# は塀の**前**に立つ ——「学び舎の塀の下の村の井戸」という読み。
	var g_tera := lib.add(g, Node3D.new(), "寺子屋塀") as Node3D
	fence.call(g_tera, -8.2, -62.0, -44.0, [[-55.3, -53.3]])
	mune.call(g_tera, -8.2, -54.3, 1.85)
	made.append("寺子屋の塀と門")
	foot.append([Vector2(-8.2, -53.0), 1.2, 9.6])

	# ── 2. 稲荷の小祠（西・z −30）：寺子屋と杜のあいだの空白を埋める ──
	var iy := height_at(-7.8, -30.0)
	var ina := lib.add(g, Node3D.new(), "稲荷小祠") as Node3D
	ina.position = Vector3(-7.8, iy, -30.0)
	ina.rotation.y = 0.5
	lib.box(ina, "基壇", Vector3(1.5, 0.28, 1.2), stone, Vector3(0, 0.14, 0))
	lib.box(ina, "祠身", Vector3(0.78, 0.72, 0.62),
		lib.pbr("祠木", "dark_wood", 2.6, Color(0.52, 0.46, 0.40)), Vector3(0, 0.64, 0))
	lib.gable_roof(ina, 1.02, 1.06, 0.92, 0.55, 0.09, kawara, dark)
	var verm := lib.flat_mat("鳥居朱", Color(0.435, 0.135, 0.10), 0.78)
	for k in 2:
		var tz := -1.05 - float(k) * 0.75
		for sd in [-1.0, 1.0]:
			lib.box(ina, "小鳥居柱_%d_%d" % [k, int(sd + 1.0)],
				Vector3(0.07, 0.95, 0.07), verm, Vector3(sd * 0.36, 0.475, tz))
		lib.box(ina, "小鳥居笠_%d" % k, Vector3(0.98, 0.08, 0.10), verm,
			Vector3(0, 0.95, tz))
	_lm_collide(ina, Vector3(1.6, 1.3, 1.3))
	made.append("稲荷小祠")
	foot.append([Vector2(-7.8, -30.0), 1.4, 1.8])

	# ── 3. 鎮守之杜の街縁（西・z −13..+17）：玉垣＋鳥居 ───────────
	# ⚠ 保留区の東縁は x −5.65 —— この帯の要素は保留区の**内側**に立つので
	#   碰撞体は付けない（lm_ghost の孤児碰撞に化ける）。低い玉垣なので
	#   跨げる見た目＝当たり無しでも嘘にならない。
	var tama := lib.pbr("玉垣", "planks", 1.9, Color(0.60, 0.55, 0.47))
	for rng2 in [[-13.0, -1.6], [5.6, 17.0]]:
		var t2 := float(rng2[0])
		while t2 < float(rng2[1]) - 0.1:
			var e2 := minf(t2 + 1.55, float(rng2[1]))
			var y3 := height_at(-6.5, (t2 + e2) * 0.5)
			lib.box(g, "玉垣板_%d" % int(t2 * 10.0), Vector3(0.07, 0.66, e2 - t2 - 0.10),
				tama, Vector3(-6.5, y3 + 0.52, (t2 + e2) * 0.5))
			lib.box(g, "玉垣柱_%d" % int(t2 * 10.0), Vector3(0.11, 0.94, 0.11),
				dark, Vector3(-6.5, height_at(-6.5, t2) + 0.47, t2))
			t2 = e2
	# 鳥居（社の街への顔。二本柱＋島木＋笠木＋貫 —— 反りは省く）
	var ty := height_at(-6.4, 2.0)
	var tor := lib.add(g, Node3D.new(), "鳥居") as Node3D
	tor.position = Vector3(-6.4, ty, 2.0)
	for sd in [-1.0, 1.0]:
		lib.box(tor, "柱_%d" % int(sd + 1.0), Vector3(0.24, 3.30, 0.24), verm,
			Vector3(0, 1.65, sd * 1.45))
		lib.box(tor, "亀腹_%d" % int(sd + 1.0), Vector3(0.38, 0.22, 0.38), stone,
			Vector3(0, 0.11, sd * 1.45))
	lib.box(tor, "貫", Vector3(0.16, 0.20, 3.85), verm, Vector3(0, 2.55, 0))
	lib.box(tor, "島木", Vector3(0.22, 0.20, 3.75), verm, Vector3(0, 3.32, 0))
	lib.box(tor, "笠木", Vector3(0.30, 0.17, 4.10), dark, Vector3(0, 3.50, 0))
	for i in 3:
		lib.box(g, "参道敷石_%d" % i, Vector3(0.95, 0.07, 0.80), stone,
			Vector3(-5.3 + 0.0, height_at(-5.3, 2.0) + 0.02, 2.0 - 0.85 + float(i) * 0.85))
	made.append("鎮守之杜の玉垣と鳥居")

	# ── 4. 蔵屋敷（東・z −38..−8）：市場の蔵の列 ─────────────────
	# 鈴奈庵（〜z −44）と MAIN_EW の家並み（z 0〜）のあいだ、東側 44m の
	# 空白。市の荷が入る蔵二棟を板塀で囲う —— 従属構造で正面を回復する。
	var g_kura := lib.add(g, Node3D.new(), "蔵屋敷塀") as Node3D
	fence.call(g_kura, 6.9, -38.0, -8.0, [[-23.4, -21.4]])
	mune.call(g_kura, 6.9, -22.4, 1.85)
	var kura_wall := lib.pbr("蔵漆喰", "plaster", 1.5, Color(1.04, 1.01, 0.95))
	var kura_koshi := lib.pbr("蔵海鼠", "namako", 2.1, Color(0.92, 0.92, 0.90))
	for kz in [-30.5, -14.5]:
		var kx := 11.6
		if _pt_reserved(Vector2(kx, kz), 2.0):
			continue
		var ky := height_at(kx, kz)
		var kura := lib.add(g, Node3D.new(), "蔵_%d" % int(kz)) as Node3D
		kura.position = Vector3(kx, ky, kz)
		kura.rotation.y = PI * 0.5           # 妻を街へ（蔵は妻入りが多い）
		lib.box(kura, "基壇", Vector3(5.0, 0.42, 6.4), stone, Vector3(0, 0.21, 0))
		lib.box(kura, "腰", Vector3(4.62, 0.95, 6.02), kura_koshi, Vector3(0, 0.90, 0))
		lib.box(kura, "壁", Vector3(4.58, 2.35, 5.98), kura_wall, Vector3(0, 2.53, 0))
		lib.box(kura, "扉", Vector3(1.15, 1.75, 0.14), dark, Vector3(0.6, 1.45, -3.02))
		lib.box(kura, "窓", Vector3(0.72, 0.55, 0.10), dark, Vector3(0, 3.05, -3.00))
		lib.gable_roof(kura, 3.72, 5.3, 7.0, 0.44, 0.15, kawara, dark)
		_lm_collide(kura, Vector3(5.0, 3.8, 6.4))
		foot.append([Vector2(kx, kz), 3.4, 3.0])
	made.append("蔵屋敷（塀＋蔵二棟）")
	foot.append([Vector2(6.9, -23.0), 1.0, 15.6])

	# ── 5. 市場の口（西・z 44..72）：幟の列＋木戸＋荷 ─────────────
	var nobori_c := [Color(0.16, 0.19, 0.31), Color(0.55, 0.30, 0.16),
		Color(0.80, 0.76, 0.66), Color(0.16, 0.19, 0.31), Color(0.30, 0.42, 0.28)]
	for i in 5:
		var nz := 46.0 + float(i) * 6.0
		var ny := height_at(-6.9, nz)
		var nb := lib.add(g, Node3D.new(), "幟_%d" % i) as Node3D
		nb.position = Vector3(-6.9, ny, nz)
		nb.rotation.y = 0.10 * float(i % 3 - 1)
		lib.cyl(nb, "竿", 0.045, 0.055, 4.3, dark, Vector3(0, 2.15, 0), 6)
		lib.box(nb, "横手", Vector3(0.05, 0.05, 0.62), dark, Vector3(0, 4.05, 0.26))
		lib.box(nb, "布", Vector3(0.035, 2.55, 0.55),
			lib.flat_mat("幟布_%d" % i, nobori_c[i], 0.85), Vector3(0, 2.72, 0.30))
	for sd in [-1.0, 1.0]:
		lib.box(g, "市木戸柱_%d" % int(sd + 1.0), Vector3(0.20, 2.45, 0.20), dark,
			Vector3(-6.9, height_at(-6.9, 57.0 + sd * 1.35) + 1.22, 57.0 + sd * 1.35))
	lib.box(g, "市木戸冠木", Vector3(0.17, 0.19, 3.35), dark,
		Vector3(-6.9, height_at(-6.9, 57.0) + 2.42, 57.0))
	# 荷のこぼれ：俵・木箱・笊 —— 市の口が「使われている」ことの最小の証拠
	var spill := [["prop_tawara", -6.3, 60.4, 0.7], ["prop_crate", -6.6, 61.4, -0.3],
		["prop_zaru", -6.1, 48.6, 0.2], ["prop_taru", -6.5, 47.6, 1.2]]
	for sp in spill:
		var mi := MeshInstance3D.new()
		mi.mesh = lib.prop_mesh("res://assets/models/%s.glb" % String(sp[0]))
		mi.position = Vector3(float(sp[1]),
			height_at(float(sp[1]), float(sp[2])), float(sp[2]))
		mi.rotation.y = float(sp[3])
		lib.add(g, mi, "市荷_%s_%d" % [String(sp[0]), int(float(sp[2]))])
	made.append("市場の幟と木戸")

	# ── 6. 湯屋（足洗邸）南の生垣（東・z 96..113）─────────────────
	for i in 4:
		var hz := 96.5 + float(i) * 4.4
		var hm := MeshInstance3D.new()
		hm.mesh = lib.prop_mesh("res://assets/models/hedge_a.glb", lib.vc_mat())
		hm.position = Vector3(6.6, height_at(6.6, hz), hz)
		hm.rotation.y = PI * 0.5
		lib.add(g, hm, "生垣_%d" % i)
	made.append("湯屋前の生垣")

	# ── 7. 街路樹（軒線より高い塊で長軸の抜けを上から刻む）─────────
	# 動線は塞がない：全て路肩の外。等間隔にはしない。
	var trees := [["tree_round_a", -6.3, -70.0, 1.30, 0.8],
		["tree_pine_a", 6.3, -43.0, 1.15, 2.1],
		["tree_sakura_a", -6.2, 26.0, 1.20, 4.0],
		["tree_round_c", 6.5, 61.0, 1.25, 5.3],
		["tree_sakura_b", -6.4, 120.0, 1.10, 0.4]]
	for tr in trees:
		var tx := float(tr[1])
		var tz := float(tr[2])
		if _pt_reserved(Vector2(tx, tz), 1.0):
			continue
		var tm := MeshInstance3D.new()
		tm.mesh = _village_tree_mesh("res://assets/models/%s.glb" % String(tr[0]))
		tm.position = Vector3(tx, height_at(tx, tz), tz)
		tm.rotation.y = float(tr[4])
		tm.scale = Vector3(float(tr[3]), float(tr[3]) * 1.05, float(tr[3]))
		lib.add(g, tm, "街路樹_%s" % String(tr[0]))
	made.append("街路樹 5 本")

	# ── 足元の草を抜く（乱数不使用・buffer 直読み）─────────────
	var cut := _cut_grass(foot)
	_audit.append("本通の街並：%s（足元の草 %d 叢を除去）" % [", ".join(made), cut])


func _build_gutters() -> void:
	var walls: Array[Transform3D] = []
	var floors: Array[Transform3D] = []
	var lids: Array[Transform3D] = []
	# [路索引, 沿 x?, 固定座標, 起, 迄, 路半寬]
	var runs := [
		{"ri": 0, "along_x": false, "fix": 0.0, "a": -170.0, "b": 220.0, "hw": 4.0},
		{"ri": 1, "along_x": true, "fix": MAIN_EW_Z, "a": -80.0, "b": 130.0,
			"hw": MAIN_EW_W * 0.5},
	]
	var n_seg := 0
	var n_cover := 0
	for run in runs:
		var along_x: bool = bool(run.along_x)
		var off: float = float(run.hw) + 0.6
		for side in [-1.0, 1.0]:
			var t: float = float(run.a)
			var seg_i := 0
			while t < float(run.b):
				var mid := t + GUTTER_SEG * 0.5
				var p := Vector2(mid, float(run.fix) + side * off) if along_x \
					else Vector2(float(run.fix) + side * off, mid)
				t += GUTTER_SEG
				seg_i += 1
				# PHASE 3.1A：回廊は commerce≈0.32 < 0.45 なので、石溝が
				# 一節も立っていなかった（＝路と建物のあいだに何もない）。
				if _commerce(p) < GUTTER_COMMERCE and not _in_pilot_xz(p.x, p.y):
					continue
				if _river_dist_xy(p.x, p.y) < RIVER_HALF + 2.0:
					continue
				# 橫街穿過來的地方不能是開口溝 —— 蓋起來讓人車過得去
				var covered := false
				for i in _roads.size():
					if i == int(run.ri):
						continue
					var r: Dictionary = _roads[i]
					if lib.poly_dist(r.pts, p.x, p.y) < float(r.w) * 0.5 + 1.2:
						covered = true
						break
				# 每一節錨在**自己中心**的地面（見 GUTTER_SEG 的註解）
				var y0: float = height_at(p.x, p.y)
				var b := Basis(Vector3.UP, PI * 0.5) if along_x else Basis()
				n_seg += 1
				if covered:
					# 整節鋪石蓋（用縮放拉長，不要排好幾塊 1.6m 的板 ——
					# 那樣重疊處會共面閃爍，這個檔案已經栽過六次）
					n_cover += 1
					lids.append(Transform3D(b.scaled(Vector3(1, 1, GUTTER_SEG / 1.6)),
						Vector3(p.x, y0 + 0.02, p.y)))
					continue
				for sd in [-1.0, 1.0]:
					var wo := Vector2(0.0, sd * 0.42) if along_x else Vector2(sd * 0.42, 0.0)
					walls.append(Transform3D(b, Vector3(p.x + wo.x, y0 - 0.24, p.y + wo.y)))
				floors.append(Transform3D(b, Vector3(p.x, y0 - 0.46, p.y)))
				if seg_i % 6 == 1:                 # 每六節架一塊石蓋（過路用；節變短了）
					lids.append(Transform3D(b, Vector3(p.x, y0 + 0.02, p.y)))
			pass
	if n_seg == 0:
		return
	# ⚠ 別用 MAT_TONES["stone"]：那組色調最暗的一支也有 0.82，乘上本來就
	# 亮的 stone_wall 貼圖，在直射陽光下是**純白的軌條**（俯視截圖看出來的，
	# 跟護岸「0.42 的灰讀成水泥防洪牆」是同一個病）。排水溝的石頭是濕的、暗的。
	var stone := lib.pbr("溝石", "stone_wall", 0.55, Color(0.60, 0.61, 0.59))
	# ⚠ 蓋の uv 0.30 は**タイル 3.33m** —— pbr() の uv は「大きいほど細かい」
	# ので、1.6〜3.0m の板に目地が一枚も乗らず「巨大なコンクリート板」に
	# 読めていた（Art Review の指摘）。1.9（≒53cm）で敷石の目が出る。
	# 色も路面より**暗い**濡れた石に落とし、板は薄く・地面に沈める
	# （+0.02 の浮きが縁に硬い影を落として「後から置いた板」に見えていた）。
	var slab := lib.pbr("溝蓋石", "stone_flag", 1.9, Color(0.42, 0.43, 0.42))
	var g := lib.add(_root, Node3D.new(), "石溝")
	var parts := [
		{"size": Vector3(0.22, 0.5, GUTTER_SEG), "list": walls, "mat": stone, "n": "溝壁"},
		{"size": Vector3(0.7, 0.12, GUTTER_SEG), "list": floors, "mat": stone, "n": "溝底"},
		{"size": Vector3(1.05, 0.10, 1.6), "list": lids, "mat": slab, "n": "溝蓋"},
	]
	for pt in parts:
		var bm := BoxMesh.new()
		bm.size = pt.size
		bm.material = pt.mat
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(bm, pt.list, [],
			OUT_DIR + "gen/gutter_%s.res" % String(pt.n))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lib.add(g, mmi, String(pt.n))
	_audit.append("石溝 %d 節（其中 %d 節是橫街的覆蓋段）→ 3 個 MultiMesh"
		% [n_seg, n_cover])


## 街燈：沿路網放，間距吃商業梯度（村心密、村緣疏）。
## ⚠ 舊版是手寫的 spots 陣列（吃 ST_X/ST_Z）；新圖的路是折線，所以改成
## **沿線行走取樣**。也因此不會再出現「燈站在田中央」那種舊格線殘留。
const LAMP_MAX := TownConfig.LAMP_MAX              # OmniLight3D 有成本，上限擺明寫死

## Main Street batch：街燈の語彙を全取り替え。
## 旧版は「機械的に丸い鉄柱＋乳白の発光箱＋商業勾配の等間隔・両側交互」——
## それは近代の街路照明の配置規則そのもので、村の灯りの規則ではない
## （Art Review の指摘）。村の規則は**人が集まる所だけ明るい**：
## 門・辻・社前・市の口・橋詰・湯屋の前。器具は木の**辻行灯**
## （台石＋角柱＋紙の火袋＋木の笠）。等間隔の巡回配置は廃止。
## ⚠ 乱数は使わない（決め打ちの錨点表）。N1/N2/N3 の錨点から 7m 以上
##   離す —— sight nodes 側の dodge_lamp が動いて節がずれるため。
const LAMP_ANCHORS := TownConfig.LAMP_ANCHORS

func _build_lamps() -> void:
	var g := lib.add(_root, Node3D.new(), "街燈")
	var wood := lib.pbr("行灯柱", "dark_wood", 2.4, Color(0.42, 0.40, 0.37))
	var stone := lib.pbr("行灯台石", "stone_flag", 1.8, Color(0.50, 0.51, 0.49))
	var paper := lib.flat_mat("行灯紙", Color(0.93, 0.87, 0.72), 0.6,
		Color(0.34, 0.245, 0.115))
	var n := 0
	for a in LAMP_ANCHORS:
		var p := Vector2(float(a[0]), float(a[1]))
		if _pt_reserved(p, 0.8):
			continue
		var lamp := Node3D.new()
		lamp.position = Vector3(p.x, height_at(p.x, p.y), p.y)
		lamp.rotation.y = 0.35 * float((n * 7) % 5 - 2) * 0.25   # わずかな振れ
		lib.add(g, lamp, "街燈_%d" % n)
		# 台石 → 角柱 → 紙の火袋（木の框）→ 木の笠。全て直方 —— 旋盤の丸柱は無い
		lib.box(lamp, "台石", Vector3(0.50, 0.22, 0.50), stone, Vector3(0, 0.11, 0))
		lib.box(lamp, "柱", Vector3(0.13, 1.85, 0.13), wood, Vector3(0, 0.22 + 0.925, 0))
		lib.box(lamp, "火袋", Vector3(0.36, 0.44, 0.36), paper, Vector3(0, 2.32, 0))
		# 火袋の框：四隅の細い柱だけ。⚠ 側板 2 枚で作った初版は紙の箱の
		#   前面が真っ黒な板になった（描画で確認）—— 紙は四面とも見せる。
		for ci in 4:
			lib.box(lamp, "框_%d" % ci, Vector3(0.05, 0.50, 0.05), wood,
				Vector3((-1.0 if ci % 2 == 0 else 1.0) * 0.165, 2.32,
					(-1.0 if ci < 2 else 1.0) * 0.165))
		lib.box(lamp, "笠", Vector3(0.56, 0.06, 0.56), wood, Vector3(0, 2.60, 0))
		lib.box(lamp, "笠上", Vector3(0.34, 0.05, 0.34), wood, Vector3(0, 2.65, 0))
		var li := OmniLight3D.new()
		li.position = Vector3(0, 2.32, 0)
		li.light_color = Color(1.0, 0.76, 0.46)
		li.light_energy = 1.1
		li.omni_range = 8.0
		li.shadow_enabled = false
		# ⚠ 燈本體 _perf_pass 會設距離淡出，但**燈光不是 MeshInstance3D**，
		# 不會被掃到 —— 自己設距離淡出。
		li.distance_fade_enabled = true
		li.distance_fade_begin = 55.0
		li.distance_fade_length = 15.0
		lib.add(lamp, li, "光")
		n += 1
	_audit.append("街燈 %d 盞（辻行灯：門・辻・社前・市の口・橋詰だけ。等間隔配置は廃止）" % n)



# ══════════════ 水邊 MIGRATE：動物／水生植物 ══════════════
#
# 舊 gen_village 的 `_build_fauna` / `_build_water_plants` 綁的是**水路**
# （CANAL，Stage 1 已移除）。新圖只有河，所以路徑、水面高度、生長帶全部改綁
# `_river()`。蘆葦已經在草層（`_reed_along_river`）裡了，這裡只補睡蓮與荷。
#
# 水面高度只有一個真相來源：`lib.river_water(..., RIVER_DEPTH * 0.20, bank_h)`
# → 水面 = bank_h − 0.5。舊碼寫的是 `sink * 0.35`（水路的係數），照抄會讓
# 全部的鴨與睡蓮浮高 0.375m。

const FAUNA_Z := TownConfig.FAUNA_Z     # 生物只放在**看得到**的村內段

## 河道在村內段的中心線 + 每個節點的水面高度（fauna.gd 的巡游路徑格式）
func _river_reach() -> Array:
	var pts: Array[Vector2] = []
	var ys: Array[float] = []
	for p in _river():
		if p.y < FAUNA_Z.x or p.y > FAUNA_Z.y:
			continue
		pts.append(p)
		ys.append(bank_h(p.x, p.y) - RIVER_DEPTH * 0.20)
	return [pts, ys]

func _build_fauna() -> void:
	var reach := _river_reach()
	var pts: Array = reach[0]
	var ys: Array = reach[1]
	if pts.size() < 2:
		return
	var g := lib.add(_root, Node3D.new(), "Fauna")
	g.set_script(load("res://scripts/fauna.gd"))
	g.set("paths", [{"pts": pts, "ys": ys}])
	var total_len := 0.0
	for k in range(pts.size() - 1):
		total_len += (pts[k] as Vector2).distance_to(pts[k + 1])

	var seg_n := pts.size() - 1
	var at_river := func(t: float, sink: float) -> Vector3:
		var ft: float = clampf(t, 0.0, 0.999) * float(seg_n)
		var i2 := int(ft)
		var f := ft - float(i2)
		var a: Vector2 = pts[i2]
		var b: Vector2 = pts[mini(i2 + 1, seg_n)]
		var q: Vector2 = a.lerp(b, f)
		# 橫向擺一點，但要留在水面內（水面半寬 = RIVER_HALF * 0.86 = 6.0）
		q += (b - a).normalized().orthogonal() * _street_rng.randf_range(-2.2, 2.2)
		var y0: float = lerpf(float(ys[i2]), float(ys[mini(i2 + 1, seg_n)]), f)
		return Vector3(q.x, y0 - sink, q.y)
	# ⚠ fauna.gd 的 speed 是**每秒走完全長的比例**，不是 m/s。舊值 0.006~0.016
	# 是配 390m 的水路寫的；直接搬到 619m 的河上，鴨子會用 3.7~9.9 m/s 巡游
	# （比人跑還快）。所以這裡從**真實速度**回推比例。
	var t_of := func(mps: float) -> float:
		return mps / maxf(total_len, 1.0)

	var duck_mesh := lib.prop_mesh("res://assets/models/duck.glb")
	var koi_mesh := lib.prop_mesh("res://assets/models/koi.glb")
	# ⚠ 位置一定要在**存檔時**就算好。只寫 meta、位置留給 fauna.gd 執行期算的話，
	# 編輯器不跑 _process，九隻鴨會全部疊在世界原點 —— 而原點是本通正中央。
	for i in 9:                                    # 鴨（水面）
		var d := MeshInstance3D.new()
		d.mesh = duck_mesh
		d.scale = Vector3.ONE * _street_rng.randf_range(0.85, 1.15)
		var dt := _street_rng.randf_range(0.06, 0.94)
		lib.add(g, d, "鴨_%d" % i)
		d.position = at_river.call(dt, -0.02)
		d.rotation.y = _street_rng.randf_range(0.0, TAU)
		d.set_meta("swim_kind", 0)
		d.set_meta("swim_t", dt)
		d.set_meta("swim_speed", t_of.call(_street_rng.randf_range(0.35, 0.9)))
	for i in 14:                                   # 鯉（水下）
		var k := MeshInstance3D.new()
		k.mesh = koi_mesh
		k.scale = Vector3.ONE * _street_rng.randf_range(0.8, 1.4)
		var kt := _street_rng.randf_range(0.06, 0.94)
		lib.add(g, k, "鯉_%d" % i)
		k.position = at_river.call(kt, 0.32)
		k.rotation.y = _street_rng.randf_range(0.0, TAU)
		k.set_meta("swim_kind", 1)
		k.set_meta("swim_t", kt)
		k.set_meta("swim_speed", t_of.call(_street_rng.randf_range(0.6, 1.6)))

	# 鷺鷥：站在**水際**不動（單腳立姿是牠的招牌）。
	# ⚠ 舊版是「沿水路法線外推固定距離」。那招在**梯形斷面的水路**上成立，
	# 在這條河上不成立 —— river_carve 的坡一路拖到 2.2×half=15.4m，
	# 「岸 + 1m」那個位置的地面其實還在水面以下 0.9m。第一版照抄，
	# 600 次嘗試 **一隻都站不住**（全被「沉在水裡」判掉）。
	# 正解是**往外走到地面剛好露出水面的那一格**——那才是水際線。
	var heron_mesh := lib.prop_mesh("res://assets/models/heron.glb")
	var placed := 0
	var tries := 0
	var shore_off: Array[float] = []
	while placed < 5 and tries < 600:
		tries += 1
		var k2 := _street_rng.randi() % maxi(seg_n, 1)
		var a: Vector2 = pts[k2]
		var b: Vector2 = pts[mini(k2 + 1, seg_n)]
		var t2 := _street_rng.randf()
		var c: Vector2 = a.lerp(b, t2)
		var nrm := (b - a).normalized().orthogonal()
		var sd := 1.0 if _street_rng.randf() < 0.5 else -1.0
		# 橋、鵜呑亭讓開；砌石護岸那一段也讓開（鷺鷥不會站在石垣腳下的水裡）
		var skip := false
		for br in BRIDGES:
			if c.distance_to(Vector2(float(br.x), float(br.z))) < 14.0:
				skip = true
		if skip or c.distance_to(_uno_pos) < 22.0:
			continue
		if Vector2(c.x, c.y - PLAZA.y).length() < 134.0:   # 護岸範圍（＋2m 餘裕）
			continue
		var wy: float = bank_h(c.x, c.y) - RIVER_DEPTH * 0.20
		# 從水線往外走，找地面第一次露出水面的位置
		var found := Vector2.ZERO
		var found_y := 0.0
		var found_d := 0.0
		var d := RIVER_HALF * 0.86
		while d < RIVER_HALF * 2.4:
			var p2: Vector2 = c + nrm * sd * d
			var gy2: float = height_at(p2.x, p2.y)
			if gy2 >= wy + 0.03:
				if gy2 <= wy + 0.5:                # 太高就是爬上岸頂了，不是水際
					found = p2
					found_y = gy2
					found_d = d
				break
			d += 0.2
		if found == Vector2.ZERO:
			continue
		var h := MeshInstance3D.new()
		h.mesh = heron_mesh
		h.position = Vector3(found.x, found_y, found.y)
		# 面向水（鷺鷥盯著水面等魚），不是隨機亂轉
		h.rotation.y = atan2(-nrm.x * sd, -nrm.y * sd) + _street_rng.randf_range(-0.5, 0.5)
		h.scale = Vector3.ONE * _street_rng.randf_range(0.9, 1.15)
		lib.add(g, h, "鷺鷥_%d" % placed)
		shore_off.append(found_d)
		placed += 1
	if placed > 0:
		var so := 0.0
		for v in shore_off:
			so += v
		_audit.append("　鷺鷥水際線實測：離河心平均 %.2fm（河半寬 %.1f、水面半寬 %.2f）"
			% [so / float(placed), RIVER_HALF, RIVER_HALF * 0.86])
	_audit.append("水邊生物：9 鴨 / 14 鯉 / %d 鷺鷥（巡游段 z %.0f~%.0f，全長 %.0fm）"
		% [placed, FAUNA_Z.x, FAUNA_Z.y, total_len])


## 水生植物：睡蓮與荷。
## ⚠ 舊版的生長帶是 0~0.72 半寬（= 撒到河心）。那是**靜水**水路的設定；
## 浮葉植物長在淺灘不長在流心，所以這裡收到 0.42~0.86，貼著岸長。
func _build_water_plants() -> void:
	var g := lib.add(_root, Node3D.new(), "WaterPlants")
	var pad := lib.tuft_mesh(6, 0.30, 0.34, Color(0.15, 0.29, 0.13), Color(0.27, 0.45, 0.19))
	var lotus := lib.tuft_mesh(5, 0.46, 0.14, Color(0.20, 0.34, 0.16), Color(0.92, 0.72, 0.80), true)
	var groups := [
		{"mesh": pad, "n": 220, "band": Vector2(0.42, 0.86), "sink": -0.03, "file": "睡蓮"},
		{"mesh": lotus, "n": 80, "band": Vector2(0.52, 0.84), "sink": -0.30, "file": "荷"},
	]
	var rv := _river()
	var total := 0
	var parts: Array[String] = []
	for grp in groups:
		var list: Array[Transform3D] = []
		var tries := 0
		var target: int = int(grp.n)
		while list.size() < target and tries < target * 60:
			tries += 1
			var k := int(_street_rng.randf() * float(rv.size() - 1))
			var a: Vector2 = rv[k]
			var b: Vector2 = rv[k + 1]
			var q: Vector2 = a.lerp(b, _street_rng.randf())
			var band: Vector2 = grp.band
			var off: float = RIVER_HALF * _street_rng.randf_range(band.x, band.y) \
				* (1.0 if _street_rng.randf() < 0.5 else -1.0)
			q += (b - a).normalized().orthogonal() * off
			if absf(q.x) > HALF - 8.0 or absf(q.y) > HALF - 8.0:
				continue
			# 橋下與鵜呑亭川床下不長（橋墩／柱會穿過去，而且是陰影）
			var skip := false
			for br in BRIDGES:
				if q.distance_to(Vector2(float(br.x), float(br.z))) < 12.0:
					skip = true
					break
			if skip or q.distance_to(_uno_pos) < 16.0:
				continue
			# ⚠ 一定要用 poly_dist 複驗：沿線取樣的 off 是照**該段法線**推的，
			# 河道轉彎處內側會被推到對岸去（實測會有株落在水面外）。
			var d: float = lib.poly_dist(rv, q.x, q.y)
			if d > RIVER_HALF * 0.86 - 0.3 or d < RIVER_HALF * 0.30:
				continue
			var wy: float = bank_h(q.x, q.y) - RIVER_DEPTH * 0.20 + float(grp.sink)
			var sc := _street_rng.randf_range(0.7, 1.5)
			list.append(Transform3D(
				Basis(Vector3.UP, _street_rng.randf() * TAU).scaled(Vector3(sc, sc, sc)),
				Vector3(q.x, wy, q.y)))
		total += list.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(grp.mesh, list, [],
			OUT_DIR + "gen/water_%s.res" % String(grp.file))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# ⚠ 不設 visibility_range —— MultiMeshInstance 是**整批**用 AABB 中心
		# 判距離的，跨半張圖的批次會被整批剔掉（草層踩過這個坑）。
		lib.add(g, mmi, String(grp.file))
		parts.append("%s %d" % [String(grp.file), list.size()])
	_audit.append("水生植物：%s（共 %d 株，貼岸帶 0.42~0.86 半寬）"
		% [", ".join(parts), total])


func _write_meta() -> void:
	## portals[0] 必須是北門：main.gd 的 _place_player 在 from_id=="" 時
	## 落在 portals[0]，所以 `--map=village` 會站在本通上而不是村角。
	## y 由 height_at 量出來，不手抄 —— 地形換了數值就會變。
	##
	## ⚠ Stage 2 的回程 portal：**不需要動 trail/kourindou**。
	## main.gd 的 _place_player 是「找目的地圖裡 target == from_id 的那個
	## portal」，也就是落點由**這張圖**的 portal 決定，不是由來源圖決定。
	## 而舊 village 的兩個 portal 座標 (0,−174)/(−132,100) 跟這裡產出的
	## **完全相同** —— 所以 trail→village、kourindou→village 的落點不變。
	## （查證過 data/village.meta.json 的舊值，不是憑印象。）
	var ports := [
		{"x": 0.0, "y": snappedf(height_at(0, -174), 0.01), "z": -174.0, "target": "trail"},
		{"x": -132.0, "y": snappedf(height_at(-132, 100), 0.01), "z": 100.0,
		 "target": "kourindou"},
		# 河畔道北端出圖 → 未來的霧之湖。target 留 null = 保留中的觸發區
		# （Area3D 照建、不畫光柱、不切場景），填上目的地就自動生效。
		_bank_portal(-286.0),
		# 稗田邸玄関前 → 室內一樓（傳送場景）。
		# ⚠ 位置隨「換成完整獨立版」一起挪。座標不是量出來的、是**推**出來的：
		# make_hieda.py 的 `Y_STEP = -11.43` 是唐破風石階最外緣，也是參道的
		# 起點（`build_avenue(bld, Y_STEP, Y_OUT)`）。Blender→Godot 是
		# z = −y，所以石階腳在 blockout 本地 z=+11.43；blockout 原點在世界
		# (−78.05, −178.0)（＝保留區中心 + HIEDA_OFF），石階腳就是 z=−166.6。
		# portal 再往參道外挪 2m，站在階前而不是站在階上。
		# ⚠ 這個 portal **刻意不進 connections**：connections 是世界圖層級
		# 的連通表（跟 mapRegistry.js 對齊），建築內部不是世界圖上的一格
		# —— 「不進 mapRegistry」的裁決串接後仍適用，樓層連結只活在
		# meta 的 portal 層。
		{"x": -78.05, "y": snappedf(height_at(-78.05, -164.6), 0.01), "z": -164.6,
		 "target": "hieda1f"},
	]
	# 跟 src/world/mapRegistry.js 的 village 條目對齊（myouren/lake 是
	# **規劃中**的連線，還沒有對應 portal；lake 已有保留觸發區）。
	TownOutput.write_meta(MAP_ID, ports)


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
	TownOutput.write_instance_dump(MAP_ID, _river(), _dump, _ddump)
