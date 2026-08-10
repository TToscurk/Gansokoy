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
#   ・鯢吞亭**不搬遷**，改成臨河食堂（使用者本輪定案）。
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
const TownLandmarks := preload("res://tools/town/town_landmarks.gd")
const TownMarket := preload("res://tools/town/town_market.gd")
const TownStreetFixtures := preload("res://tools/town/town_street_fixtures.gd")
const TownEcology := preload("res://tools/town/town_ecology.gd")
const TownPilotNode := preload("res://tools/town/town_pilot_node.gd")
const TownSightNodes := preload("res://tools/town/town_sight_nodes.gd")
const TownMarketQuarter := preload("res://tools/town/town_market_quarter.gd")
const TownMainStreet := preload("res://tools/town/town_mainstreet.gd")
const TownPhase5APilot := preload("res://tools/town/town_phase5a_pilot.gd")
const TownPilotEdge := preload("res://tools/town/town_pilot_edge.gd")
const TownLandmarkRegistry := preload("res://tools/town/town_landmark_registry.gd")
const TownRiversideDiner := preload("res://tools/town/town_riverside_diner.gd")
const TownRoadNetwork := preload("res://tools/town/town_road_network.gd")
const TownWaterfront := preload("res://tools/town/town_waterfront.gd")
const TownHiedaGrove := preload("res://tools/town/town_hieda_grove.gd")
const TownBuildingOutput := preload("res://tools/town/town_building_output.gd")
const TownGrass := preload("res://tools/town/town_grass.gd")
const TownBlocks := preload("res://tools/town/town_blocks.gd")

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

# 鯢吞亭（臨河食堂）：正面朝河，離主橋西橋頭約 13m。
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
var _uno_pos := Vector2(1e9, 1e9)   # 鯢吞亭位置（護岸在這段要讓開）
var _reserved := []                 # 不准蓋町家的 OBB（地標／鯢吞亭／橋）

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
	# 草層要在密度層之後：它要避開的保留區（地標／橋／鯢吞亭／門樓）到這裡才齊
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
	TownRoadNetwork.build(
		_roads, _river(), MAIN_EW_W, BANK_PATH, _nearest_river_pt)


# ── 護岸（MultiMesh）──
# 全長 619m、154 段 × 2 岸 = 308 個候選；扣掉橋位、鯢吞亭與村外之後
# 實際約 119 個實例。一段一個 MeshInstance3D 的話就是 119 個節點。

func _build_revetment() -> void:
	TownWaterfront.build_revetment(
		lib, _root, OUT_DIR, _river(), RIVER_HALF, BRIDGES,
		_uno_pos, PLAZA, bank_h, _audit)


func _plug_river_mouths() -> void:
	TownWaterfront.plug_river_mouths(_root, _river(), RIVER_HALF, HALF)


# ── 橋 ──

func _build_bridges() -> void:
	TownWaterfront.build_bridges(
		lib, _root, BRIDGES, _mods, bank_h, _obb_of,
		_dump, _reserved, _audit)


# ── 地標佔位 + 鯢吞亭 ──

func _build_landmark_stubs() -> void:
	TownLandmarkRegistry.build(
		lib, _root, LANDMARKS, SEED, _lm_rng, _reserved,
		_ground_under, bank_h, self, _audit)


func _build_unomitei() -> void:
	_uno_pos = TownRiversideDiner.build(
		lib, _root, UNOMITEI_ANCHOR, RIVER_HALF, _mods,
		_nearest_river_pt, river_tangent, bank_h, _obb_of,
		_dump, _reserved, _audit)


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

const CONSOLIDATE := TownConfig.CONSOLIDATE
const CONSOLIDATE_ALL := TownConfig.CONSOLIDATE_ALL
const KIT_FRONT := TownConfig.KIT_FRONT

var _block_rng := RandomNumberGenerator.new()


func _in_pilot_xz(x: float, z: float) -> bool:
	return absf(x) < 14.0 and z >= -168.0 and z <= -80.0


func _is_pilot(e: Array) -> bool:
	return _is_house_kind(String(e[0])) \
		and absf(float(e[1])) < 40.0 \
		and float(e[3]) >= -165.0 and float(e[3]) <= -80.0


func _kitify(cfg: Dictionary) -> Dictionary:
	return TownBlocks.kitify(cfg)


func _block(seed_i: int, cfg: Dictionary) -> void:
	_block_rng.seed = seed_i
	TownBlocks.build_block(seed_i, cfg, _block_rng, {
		"lib": lib,
		"mods": _mods,
		"roads": _roads,
		"reserved": _reserved,
		"plaza": PLAZA,
		"consolidate": CONSOLIDATE,
		"consolidate_all": CONSOLIDATE_ALL,
		"ghosting": _ghosting,
		"ghost": _ghost,
		"batches": _batch,
		"dump": _dump,
		"bank_h": bank_h,
		"obb_of": _obb_of,
		"obb_pen": _obb_pen,
		"nearest_river_point": _nearest_river_pt,
		"river_tangent": river_tangent,
		"river_half": RIVER_HALF,
		"commerce": _commerce,
	})





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
		# river_end 拿掉：這段西岸已經給鯢吞亭了（兩者都被推到同一條河法線上，
		# 彼此完全不知道對方存在 → 實測互穿 6.8m）。臨河的門面由鯢吞亭擔。
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
	TownPhase5APilot.apply(
		_mods, _dump, _batch, PHASE5A_FAMILIES,
		bank_h, _market_quarter_lots, _audit)


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
	## 橋的原點在中心、鯢吞亭的川床往後伸 16m 而 fd 當時還寫成 10.9，
	## 於是自檢對它們**結構性全盲**：印著「0 穿插 ✓」，實際有 3 對互穿
	## （鯢吞亭 × 河畔町家 6.8m、鯢吞亭 × 主橋 2.3m）。gbox 一律照實量。
	return TownGeometry.obb_of(e, _mods)


func _assert_no_overlap() -> void:
	## 逐對 OBB（SAT）—— **不再只檢查町家**：橋與鯢吞亭一起進來。
	TownValidation.assert_no_overlap(_dump, _mods, _audit)


func _obb_pen(ra: Array, rb: Array) -> float:
	return TownGeometry.penetration(ra, rb)


func _emit_batches() -> void:
	TownBuildingOutput.emit_batches(
		lib, _root, OUT_DIR, _mods, _batch, _audit)


func _build_collision() -> void:
	TownBuildingOutput.build_collision(
		_root, _mods, _dump, _is_house_kind, _audit)


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
	# 「梯度」讀不出來。走廊項加寬加重、補鯢吞亭川床一帶，底率壓低
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
var _grass_rng := RandomNumberGenerator.new()
var _grass_patch_noise := FastNoiseLite.new()

## 離最近路緣多遠（0 = 站在路面上）。草的密度吃這個值。
func _road_dist(x: float, z: float) -> float:
	var best := 1e9
	for r in _roads:
		best = minf(best, lib.poly_dist(r.pts, x, z) - r.w * 0.5)
	return maxf(best, 0.0)


func _river_dist_xy(x: float, z: float) -> float:
	return lib.poly_dist(_river(), x, z)


func _build_grass() -> void:
	_grass_rng.seed = GRASS_SEED
	_grass_patch_noise.seed = GRASS_SEED + 41
	_grass_patch_noise.frequency = 0.018
	_grass_patch_noise.fractal_octaves = 3
	TownGrass.build(
		lib, _root, OUT_DIR, HALF, _river(), RIVER_HALF,
		BRIDGES, _uno_pos, _dump, _reserved,
		_grass_rng, _grass_patch_noise,
		mask_at, _obb_of, _road_dist, _commerce, height_at, _audit)




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
	return TownLandmarks.ground_sample(lib, _river(), RIVER_HALF, RIVER_DEPTH,
		height_at, bank_h, x, z)

## 一塊 footprint 的 [最低地面, 起伏量]。取樣約每 4m 一點 ——
## 3×3 對 40m 長的土塀太稀，中段有坑就整段浮空（舊圖體檢抓過）。
func _ground_under(cx: float, cz: float, w: float, d: float) -> Array:
	return TownLandmarks.ground_under(_lm_ground_sample, cx, cz, w, d)

## 建物碰撞箱。⚠ owner 一定要是 _root，否則不會存進 .tscn（ADR-017）。
func _lm_collide(g: Node3D, size: Vector3, off := Vector3.ZERO) -> void:
	TownLandmarks.add_collision(_root, g, size, off)


## 石垣基壇（寺子屋等地標坐在其上，正面切石階）。搬自 gen_village。
func _dais_in(g: Node3D, w: float, d: float, h: float, face: Vector2, spread: float) -> void:
	TownLandmarks.build_dais(
		lib, g, w, d, h, face, spread, _lmat, _lm_collide)

## 生垣（樹籬）＋竹垣：村緣的「圍牆」。
##
## 在（農家那一環）用土塀是錯的 —— 土塀是町方的東西，要人力與瓦。
## 村緣圍的是樹籬與竹垣，而且矮，看得到裡面的曬場。
## 這也是「密度不一樣的街區不要混在一起」的一部分：材質本身就要換。


## ── 足洗邸（第一座搬入）──
## 荒廢的宅邸：崩れ塀三段 + 母屋（茅葺）。牆腳要埋進坡裡，不然整段浮著。
func _lm_ashiarai(g: Node3D, spread: float) -> void:
	TownLandmarks.build_ashiarai(
		lib, g, spread, _lm_rng, _lmat, _lm_collide)


## ── 鈴奈庵（貸本屋）──
## ⚠ 整棟旋轉 −90°：正面（局部 +z）要朝西對著本通。舊 builder 的
## `bx + face_dir*(hw−6.6)` 與 `lib.rr(-4,4)` 抖動都已經烘進 LANDMARKS 的
## 座標了，搬過來之後直接以保留區中心為原點，不再重算偏移（也不再抖動 ——
## 抖動會讓保留區跟實際位置每次產生都對不上）。
func _lm_suzunaan(g: Node3D, _spread: float) -> void:
	TownLandmarks.build_suzunaan(lib, g, _lmat, _lm_collide)


## ── 寺子屋（慧音的私塾）──
## 大屋頂主屋 + 外廊 + 向拜 + 梵鐘。坐在 1.5m 石垣基壇上。
## ⚠ 內容對齊保留區中心（舊版是街區中心往南 6m，會戳出保留區）。
func _lm_terakoya(g: Node3D, spread: float) -> void:
	TownLandmarks.build_terakoya(lib, g, spread, _dais_in, _lmat, _lm_collide)


## ── 鎮守之杜（村社的神木與境內）──
## 神木（放大的闊葉樹）＋土壇＋注連縄＋紙垂＋玉垣一圈＋石燈籠一對＋杜木。
## ⚠ 舊 builder 全程用**世界座標**寫（因為它的 g 掛在原點）。搬過來之後 g
## 已經被擺到地標位置了，所以每一件都要換算成群組**區域座標**：
## 區域 = 世界 − 群組原點；y 則是 height_at(世界) − 群組原點 y。
## 直接照抄世界座標的話整組會位移一個地標座標的量。
func _lm_grove(g: Node3D, _spread: float) -> void:
	TownLandmarks.build_grove(
		lib, g, _root, _lm_rng, height_at, _road_dist,
		_village_tree_mesh, _lmat)


## ── 市場（開放廣場：龍神像＋屋台十二座＋水井＋高札場）──
## ⚠ 跟鎮守之杜一樣，舊 builder 全用世界座標寫，搬過來要換算成區域座標。
const SHRINE_R := TownConfig.SHRINE_R

func _lm_dragon(g: Node3D, ox: float, oz: float) -> void:
	TownLandmarks.build_dragon(
		lib, g, ox, oz, SHRINE_R, _lmat, _lm_collide)


func _lm_market(g: Node3D, _spread: float) -> void:
	TownMarket.build_market(
		lib, g, _lm_rng, _ground_under, height_at,
		_lmat, _lm_collide, _lm_dragon)


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
	TownHiedaGrove.build(
		lib, _root, OUT_DIR, LANDMARKS, HIEDA_OFF, GROVE_SEED,
		_road_info, height_at, _village_tree_mesh, _audit)


func _lm_hieda(g: Node3D, _spread: float) -> void:
	TownLandmarks.build_hieda(lib, g, HIEDA_OFF, _flatten_yards, bank_h, _audit)


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
	TownStreetFixtures.build_gates(
		lib, _root, GATES, _lmat, _ground_under,
		_lm_collide, _reserved, _audit)


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
	TownPilotEdge.build(
		lib, _root, OUT_DIR, SEED, _mods, _dump,
		_is_pilot, _pt_on_road_core, height_at, _audit)


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
	TownPilotNode.build(
		lib, _root, OUT_DIR, MAT_SET.has("wood"),
		_lmat, height_at, _lm_collide,
		_village_tree_mesh, _cut_grass, _audit)


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
	TownSightNodes.build(
		lib, _root, _lmat, _pt_reserved, height_at,
		_lm_collide, _cut_grass, _audit)


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
	TownMarketQuarter.build(
		lib, _root, _lmat, height_at,
		_lm_collide, _cut_grass, _audit)


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
	TownMainStreet.build(
		lib, _root, _lmat, height_at, _pt_reserved,
		_lm_collide, _village_tree_mesh, _cut_grass, _audit)


func _build_gutters() -> void:
	TownStreetFixtures.build_gutters(
		lib, _root, OUT_DIR, MAIN_EW_Z, MAIN_EW_W,
		GUTTER_SEG, GUTTER_COMMERCE, RIVER_HALF, _roads,
		_commerce, _in_pilot_xz, _river_dist_xy, height_at, _audit)


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
	TownStreetFixtures.build_lamps(
		lib, _root, LAMP_ANCHORS, _pt_reserved, height_at, _audit)



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

func _build_fauna() -> void:
	TownEcology.build_fauna(
		lib, _root, _river(), FAUNA_Z, RIVER_HALF, RIVER_DEPTH,
		BRIDGES, _uno_pos, PLAZA, _street_rng,
		bank_h, height_at, _audit)


## 水生植物：睡蓮與荷。
## ⚠ 舊版的生長帶是 0~0.72 半寬（= 撒到河心）。那是**靜水**水路的設定；
## 浮葉植物長在淺灘不長在流心，所以這裡收到 0.42~0.86，貼著岸長。
func _build_water_plants() -> void:
	TownEcology.build_water_plants(
		lib, _root, _river(), OUT_DIR, HALF, RIVER_HALF, RIVER_DEPTH,
		BRIDGES, _uno_pos, _street_rng, bank_h, _audit)


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
