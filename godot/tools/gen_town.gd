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

# ══════════ 整合 Stage 2：這支現在就是 village 的產生器（2026-08-06）══════════
# 使用者定案方案 (a)：sato 產生器**直接輸出到 maps/village/**，而不是把 sato 的
# 佈局搬進 gen_village.gd。理由：這支已經帶著完整的護欄（gbox OBB 自檢、
# _on_road、_in_reserved、村緣降級、單一收口點 _house），而 gen_village.gd 的
# 佈局程式碼在換圖之後幾乎全部作廢 —— 把新護欄搬進舊架構的風險高得多。
#
# ⚠ `gen_village.gd` 從此**不可再執行**（跑了會蓋掉這裡的產出）。它留著是
# 當 MIGRATE 清單的來源：地標內容、雜物、動物、草層都還在那支裡面。
const OUT_DIR := "res://maps/village/"
const MAP_ID := "village"
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
const LANDMARKS := [
	# 實建 25.8×14.5 —— 這座原本就夠（唯一一座）。
	# ⚠ 舊 builder 把內容擺在街區中心**往南 6m**（cz = bz − 6），所以實際
	# 量到的量體中心在 z=−58，會戳出保留區南緣 5.2m。搬入時把內容**對齊
	# 保留區中心**（拿掉那個 −6 偏移），保留區才是誠實的。
	# 保留區依**實測內容**放大：向拜與手水缽往南伸 2.8m、梵鐘往東 1.3m。
	# 原本的 26×16 只框得住主屋，框不住那些附屬件。
	{"n": "寺子屋", "x": -26.0, "z": -52.0, "w": 28.4, "d": 19.8, "h": 6.1,
		"build": "_lm_terakoya"},
	# ⚠ 實建 14.1×8.6 是**建物自己的局部尺寸**，而鈴奈庵整棟旋轉 −90°
	# （正面朝西對著本通）—— 世界座標下 W/D 是對調的。我第一次量的時候
	# 只累加平移、沒有處理旋轉，所以把保留區填成 14.6×9.5，**整個轉錯邊**。
	# 舊 tscn 的 basis 實測 x=(0,−1)、z=(1,0)，確認有轉。
	{"n": "鈴奈庵", "x": 11.6, "z": -52.0, "w": 12.8, "d": 15.0, "h": 5.4,
		"build": "_lm_suzunaan"},
	# ⚠ 稗田邸搬到村緣（使用者定案・方案 B）。舊位置 (-78, 2) 是沿用舊格線
	# 來的，離廣場只有 83m、離鎮守之杜 52m、離市場 76m —— 埋在商業核心裡，
	# 跟「私密、安靜、避世」的設定矛盾。新位置在北門西側：離北門（主入口、
	# portals[0]、玩家從 trail 進村的落點）79m，離最近商業設施 122m。
	# ⚠ 佔地從 27.7×18.7 改成 **40.7×43.7** —— 那是 village.tscn 裡**實際
	# 蓋出來**的院落（築地塀＋腰石垣＋主屋＋庭池）量出來的尺寸。舊值小了
	# 13×25m，等於保留區根本框不住真正的院落；現在沒撞到純粹是運氣好
	# （實測舊框內外都是 0 棟町家），不是護欄有效。
	# ✅ 已搬入真內容。保留區 42.4×45.6 → **45.2×48.2**（前庭替換那一輪）：
	# 格子塀的牆腳外多了一圈犬走り（石垣腳 0.79 + 碎石帶 1.34 = 牆心外 2.13），
	# 棟門的屋根也比舊藥醫門深（±1.65 vs ±1.0）。lm_ghost 實測新跨度
	# 44.3×47.3，這裡照慣例留 0.45m/邊。舊值 42.4×45.6 是照築地塀推的，
	# 沿用的話四邊各外溢 0.8~0.9m。
	{"n": "稗田邸", "x": -78.0, "z": -164.0, "w": 45.2, "d": 48.2, "h": 12.8,
		"build": "_lm_hieda"},
	# 實建 42.4×25.0（玉垣圍出來的境內比主殿大很多）
	{"n": "鎮守之杜", "x": -26.0, "z": 2.0, "w": 42.9, "d": 36.0, "h": 14.0,
		"build": "_lm_grove"},
	# 實建 34.3×25.8（八座屋台攤開的寬度）
	# 實測幾何跨度 36.0×26.8（屋台兩排 + 龍神像砂利圈 + 井屋根）
	{"n": "市場", "x": -26.0, "z": 57.0, "w": 37.2, "d": 34.0, "h": 4.6,
		"build": "_lm_market"},
	# ⚠ 實建 z 向是 **32.9m** 不是 24.5 —— 我第一次量的是「子節點原點的散佈」，
	# 沒算進側牆自己的長度（兩道側牆各長 16~18m）。保留區要框的是幾何，
	# 不是原點。第二次用 mesh AABB 世界包絡量才對。
	# ✅ 已搬入真內容（build）→ 不再產生佔位方塊與佔位碰撞箱
	{"n": "足洗邸", "x": 26.0, "z": 112.0, "w": 38.5, "d": 33.6, "h": 6.4,
		"build": "_lm_ashiarai"},
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
	lib.pond_water(OUT_DIR, HIEDA_POND.x, HIEDA_POND.y, HIEDA_POND_R, HIEDA_POND_SINK,
		_pond_bank_y, "庭池", 0.0, 4, 28, HIEDA_POND_DEPTH)
	_build_unomitei()          # 先算位置：護岸要在這一段讓開
	_build_revetment()
	_build_bridges()
	_street_rng.seed = STREET_SEED   # 街緣設施專用序列，不動地標／街區／草
	_build_gates()             # 要在鋪街區之前：門洞得先登記成保留區
	_build_landmark_stubs()
	_build_towers()
	_build_blocks()
	_assert_no_overlap()
	_emit_batches()
	_build_collision()
	_build_density()
	_build_gutters()           # 要在街區之後：溝要避開橫街，也吃商業梯度
	_build_lamps()             # 要在街區之後：燈要避開町家的 OBB
	_build_fauna()
	_build_water_plants()
	# 草層要在密度層之後：它要避開的保留區（地標／橋／鵜呑亭／門樓）到這裡才齊
	_build_grass()
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
	h = _flatten_yards(x, z, h)
	# 庭池要挖在**整平之後**的院子上 —— 順序反過來的話整平會把碗填平。
	h += lib.pond_carve(HIEDA_POND.x, HIEDA_POND.y, HIEDA_POND_R,
		HIEDA_POND_DEPTH, x, z, 0.16)
	return h


## 稗田邸的庭池（石組庭池・中島・石橋）。世界座標＝院落中心 + (+11, +8.5)。
##
## ⚠ 位置在「前庭替換」這一輪從 (−2, +8) 移到 (+11, +8.5)（使用者定案 C-1(a)）。
## 舊位置在**前庭正中央**：定案的參道是 6m 寬、筆直、從門一路連到玄関石階，
## 走 x = 軸線 ±3；舊池心離軸線只有 3m，池面連護岸實測橫跨 x −9.2~+5.2 ——
## 參道會從池子中間穿過去，狛犬（軸線 ±4.7）左邊那隻站在護岸上、右邊那隻
## 踩在州濱裡。獨立版（make_hieda.py）的池本來就在主屋北面的後院，前庭是
## 淨空的；村院沒有後院可用（主屋北牆到圍牆只剩 2.5m），所以往**東側**讓。
##
## 新位置的三個約束（都量過）：
##   ・參道東緣 x=−2，池的州濱外圈到 x=+16.7 —— 中間留 8.7m，構圖不打架
##   ・長廊南端 z=0（x 9.4~11.8），水線離它 3.4m
##   ・池心到東牆內面 8.5m，護岸還有 3.4m 的岸
## 東側原本就是空的（紅葉群聚在西南、離れ在東北），池填進去正好補上東半院
## 的空白，而且從緣側東端（x=+7, z=−1.9）看出去就是水面 —— 座視の庭。
const HIEDA_POND := Vector2(-67.0, -155.5)
const HIEDA_POND_R := 6.4
const HIEDA_POND_DEPTH := 1.7                  # 挖多深（碗底）
const HIEDA_POND_SINK := 0.55                  # 水面比岸低多少

## 池岸的基準高度。⚠ 不能直接用 bank_h —— 院子已經被 _flatten_yards 壓成
## 一個水平面，拿原始地形當岸高的話水面會斜 0.5m（一邊淹岸、一邊懸空）。
func _pond_bank_y(x: float, z: float) -> float:
	return _flatten_yards(x, z, bank_h(x, z))


## 院落整平：把指定地標的佔地壓成一個水平面，邊緣平滑收斂回原地形。
## ⚠ 稗田邸搬到 (−78,−164) 之後那塊地的高差是 **0.98m**（舊址只有 0.21m）——
## 40×44m 的築地塀圍牆＋庭池擺在 1m 的坡上會有一邊浮、一邊埋。
## 使用者定案方案 1：整平地形，不換位置、不加基壇。
## 手法沿用橋頭路廊那招（同一個檔案裡已驗收過的做法），只是改成矩形區域。
const YARD_FLATTEN := [
	{"x": -78.0, "z": -164.0, "w": 45.2, "d": 48.2, "fade": 9.0},   # 稗田邸（同保留區）
]

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

const GRASS_SEED := SEED + 913

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
			"mode": "wild", "need": 2.6, "vis": 150.0},
		{"mesh": fern, "n": 5000, "file": "ferns", "node": "Ferns",
			"mode": "wild", "need": 1.6, "vis": 120.0},
		{"mesh": tall, "n": 14000, "file": "grass_tall", "node": "GrassTall",
			"mode": "wild", "need": 1.6, "vis": 120.0},
		{"mesh": flower, "n": 1000, "file": "grass_flower", "node": "GrassFlower",
			"mode": "wild", "need": 1.6, "vis": 120.0},
		{"mesh": reed, "n": 1800, "file": "reeds", "node": "Reeds",
			"mode": "shore", "need": 0.0, "vis": 140.0},
	]
	var total := 0
	var parts: Array[String] = []
	for grp in groups:
		var list: Array[Transform3D] = []
		var target: int = int(grp.n)
		if String(grp.mode) == "shore":
			list = _reed_along_river(rng, target)
		else:
			var tries := 0
			while list.size() < target and tries < target * 10:
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
				var p := lerpf(0.08, 0.80, clampf(dr / 13.0, 0.0, 1.0))
				if Vector2(x, z - PLAZA.y).length() > CORE:
					p = maxf(p, 0.70)
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
const MAT_TONES := {
	# 真壁的填充要**亮**，木框才跳得出來 —— 參考圖的白灰接近純白。
	# 舊的 0.84/0.92 配上曬過的木框，整棟是一團褐色。
	"plaster": [Color(1.30, 1.28, 1.22), Color(1.16, 1.13, 1.06),
		Color(1.05, 1.04, 1.00), Color(1.22, 1.17, 1.09)],
	# 去髒（美術規格 §1.3）：貼圖裡的黃苔用「壓黃提藍」的色調蓋掉，
	# 瓦要乾淨的藍灰 —— 參考圖的屋頂近乎無髒污
	"kawara": [Color(0.86, 0.94, 1.10), Color(0.72, 0.80, 0.96),
		Color(0.80, 0.86, 1.00), Color(0.64, 0.72, 0.88)],
	"thatch": [Color(0.66, 0.54, 0.36), Color(0.58, 0.47, 0.31),
		Color(0.72, 0.60, 0.40), Color(0.50, 0.42, 0.30)],
	"mud": [Color(0.80, 0.72, 0.58), Color(0.70, 0.62, 0.48),
		Color(0.86, 0.78, 0.64), Color(0.64, 0.58, 0.46)],
	# ⚠ 別再讓木部的色調靠近 1.0 —— dark_wood 那張貼圖本身就很飽和，
	# 乘 1.0 出來是鮮豔的橘紅色，一整排通柱看起來像上了漆的塑膠。
	# 真實的木部是曬到發灰的褐色。
	# 色調是**相乘**的，只能壓不能加。dark_wood 那張紅得很兇，
	# 等比壓暗只會變成暗紅色 —— 要把紅色壓得比綠藍更多才會轉灰褐。
	"dark": [Color(0.44, 0.47, 0.45), Color(0.37, 0.40, 0.39),
		Color(0.52, 0.53, 0.50), Color(0.32, 0.35, 0.35)],
	"wood": [Color(0.72, 0.66, 0.58), Color(0.62, 0.56, 0.48),
		Color(0.80, 0.72, 0.62), Color(0.56, 0.51, 0.45)],
	"stone": [Color(1.00, 1.00, 1.00), Color(0.90, 0.90, 0.88),
		Color(0.82, 0.84, 0.82), Color(0.95, 0.93, 0.88)],
	"namako": [Color(1.00, 1.00, 1.00), Color(0.88, 0.90, 0.92),
		Color(0.94, 0.93, 0.90), Color(0.80, 0.83, 0.86)],
	"lattice": [Color(1.00, 0.98, 0.95), Color(0.88, 0.86, 0.84),
		Color(0.78, 0.76, 0.74), Color(0.94, 0.90, 0.86)],
	"gravel": [Color(1.00, 1.00, 1.00), Color(0.92, 0.94, 0.96),
		Color(0.88, 0.86, 0.82), Color(0.80, 0.83, 0.85)],
	# 河石是中灰的，不是白的。四個色調＝四種石色，一堆石頭才不是同一塊。
	"cobble": [Color(0.60, 0.61, 0.60), Color(0.50, 0.48, 0.45),
		Color(0.66, 0.63, 0.57), Color(0.42, 0.45, 0.48)],
	"foliage": [Color(1.00, 1.00, 1.00), Color(0.86, 0.94, 0.82),
		Color(0.74, 0.84, 0.70), Color(0.94, 0.90, 0.72)],
	"flag": [Color(1.00, 1.00, 1.00), Color(0.90, 0.90, 0.88),
		Color(0.82, 0.84, 0.86), Color(0.94, 0.91, 0.86)],
	"shoji": [Color(1.00, 1.00, 1.00), Color(0.96, 0.94, 0.90),
		Color(1.00, 0.98, 0.92), Color(0.92, 0.90, 0.86)],
	"tatami": [Color(1.00, 1.00, 1.00), Color(0.92, 0.94, 0.86),
		Color(0.86, 0.88, 0.80), Color(0.96, 0.92, 0.82)],
	"shitami": [Color(1.00, 0.98, 0.95), Color(0.86, 0.84, 0.80),
		Color(0.74, 0.72, 0.68), Color(0.92, 0.88, 0.82)],
	"yakisugi": [Color(1.00, 1.00, 1.00), Color(0.86, 0.86, 0.88),
		Color(1.12, 1.08, 1.04), Color(0.78, 0.79, 0.80)],
	"ishizumi": [Color(1.00, 1.00, 1.00), Color(0.90, 0.91, 0.90),
		Color(0.82, 0.84, 0.82), Color(0.95, 0.92, 0.86)],
}

const MAT_SET := {
	"kawara": ["roof_kawara", 0.22],
	# ⚠ 茅葺以前借的是 terrain_grass（空拍草地）—— 難怪茅頂看起來像鋪了草皮。
	# roof_thatch 現在是 tools/gen_textures.gd 烤的真茅稈。
	"thatch": ["roof_thatch", 0.55],
	# ⚠ v16 之前 "plaster" 與 "mud" 指向**同一組貼圖**，只是色調不同 ——
	# 全村 653 面牆等於一張圖染成 8 色。使用者：「其實我也覺得挺單調的」。
	"plaster": ["plaster", 0.4], "mud": ["arakabe", 0.42],
	"dark": ["dark_wood", 0.45], "wood": ["planks", 0.5], "stone": ["stone_wall", 0.30],
	# 海鼠壁以前是拿瓦的貼圖硬壓成炭黑冒充，現在有真的菱格 + 凸目地了
	"namako": ["namako", 0.30],
	# 以下都是 v15 新烤的：格子窗、玉石、葉團、板石、障子、疊蓆
	"lattice": ["wood_lattice", 0.28],
	# pebble 有兩個用法，比例差十倍，不能共用一個材質：
	#   "gravel" = 一片小石子地（州濱、洗石子），一張貼圖裡看到很多顆
	#   "cobble" = **一顆**玉石，整顆石頭只吃到貼圖裡的一格
	# v15 初版兩邊都用 0.5，結果每一顆護岸石表面都長出五顆小石頭。
	"gravel": ["pebble", 0.5],
	# 單顆玉石不要用 pebble 貼圖 —— 縮到「一顆填滿整張」之後圖案沒了，
	# 只剩一片近乎純色的高光，看起來像塑膠豆。改用 stone_wall 的石粒
	# （比例調到一顆石頭上看得到顆粒，但看不到石塊接縫）。
	"cobble": ["stone_wall", 0.85],
	"foliage": ["foliage", 0.42], "flag": ["stone_flag", 0.30],
	"shoji": ["shoji", 0.30], "tatami": ["tatami", 0.42],
	# v17 的牆面：下見板張り（腰壁）／焼杉（關西町並的黑板壁）／
	# 荒壁（摻稻稈的土壁）／野面積み（亂石腰壁）
	"shitami": ["shitami", 0.34], "yakisugi": ["yakisugi", 0.36],
	"ishizumi": ["ishizumi", 0.30],
}


var _lm_rng := RandomNumberGenerator.new()

## 材質：同一種建材四個色調。舊 `_mat()` 的搬遷版。
func _lmat(key: String, v := -1) -> StandardMaterial3D:
	if not MAT_SET.has(key):
		key = "plaster"
	var tones: Array = MAT_TONES[key]
	if v < 0:
		v = int(_lm_rng.randf() * float(tones.size()))
	v = v % tones.size()
	var spec: Array = MAT_SET[key]
	return lib.pbr("%s_%d" % [key, v], String(spec[0]), float(spec[1]), tones[v])

## 水面以下不算地面 —— 拿 height_at 的話院內有池就整棟沉下去。
func _lm_ground_sample(x: float, z: float) -> float:
	var y := height_at(x, z)
	if lib.poly_dist(_river(), x, z) < RIVER_HALF:
		y = maxf(y, bank_h(x, z) - RIVER_DEPTH * 0.20)
	# 稗田邸院內有庭池：不擋的話 _ground_under 會取到碗底，整座宅子沉 1.7m。
	# ⚠ 擋的範圍要**整個碗**（pond_carve 的影響半徑 = R×1.35），不是只有水面
	# 那一圈：水線半徑只有 5.10m，碗緣還有 3.5m 是斜的，取樣點落在那一圈一樣
	# 會把院落的基準高度往下拉（實測新池心那組取樣，最近的一點離水線只差
	# 0.005m —— 那是「這次剛好過、下次挪一米就不過」的那種通過）。
	# ⚠ 而且要取**岸高**不是水面高。舊版取 bank − sink，於是整座宅子（主屋
	# 基壇、緣側、長廊、離れ）連同前庭整組沉在院子地面下 0.55m：基壇只露
	# 5cm、緣側離地只剩 0.35m —— 唐破風玄関的五段石階（總升 0.90）根本擺不
	# 進去。院落的基準面是**院子地面**，不是池水面。
	if Vector2(x - HIEDA_POND.x, z - HIEDA_POND.y).length() < HIEDA_POND_R * 1.35:
		y = maxf(y, _pond_bank_y(x, z))
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
	big.mesh = lib.tree_mesh("res://assets/models/tree_round_a.glb")
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
		sub.mesh = lib.tree_mesh(TREES[_lm_rng.randi() % TREES.size()])
		sub.position = lp.call(wx, wz, 0.0)
		sub.scale = Vector3.ONE * _lm_rng.randf_range(1.05, 1.5)
		sub.rotation.y = _lm_rng.randf_range(0.0, TAU)
		lib.add(g, sub, "杜木_%d" % i)


## ── 市場（開放廣場：龍神像＋屋台十二座＋水井＋高札場）──
## ⚠ 跟鎮守之杜一樣，舊 builder 全用世界座標寫，搬過來要換算成區域座標。
const SHRINE_R := 7.2

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
	for i in 12:
		var row := i % 2
		var k0: int = i / 2
		var ox := -13.0 + float(k0) * 5.4 + _lm_rng.randf_range(-0.9, 0.9)
		var oz := AISLE_Z + (AISLE_HALF if row == 1 else -AISLE_HALF) \
			+ _lm_rng.randf_range(-0.4, 0.4)
		var gu := _ground_under(wc.x + ox, wc.y + oz, 3.6, 3.0)
		var st := Node3D.new()
		st.position = Vector3(ox, float(gu[0]) - y0, oz)
		st.rotation.y = (PI if row == 1 else 0.0) + _lm_rng.randf_range(-0.10, 0.10)
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


# ══════════════ 稗田邸前庭（定案構圖・2026-08-07 替換）══════════════
#
# ⚠ Stage 0 的「稗田邸 MIGRATE」搬錯版本 —— 搬的是舊 gen_village 的
# **築地塀＋藥醫門**。使用者真正逐輪迭代驗收過的前庭在
# `assets/blender/make_hieda.py`（獨立版 hieda_blockout.glb）：
# 格子塀、棟門、成對狛犬、石燈籠、飛石參道。這一輪照定案規格重建。
#
# 座標換算（獨立版 Blender Z-up → 村院 Godot Y-up）：
#     村本地 x = blender x + HIEDA_AXIS
#     村本地 z = −blender y − 12.5      （定錨：門線 y=−34 → 南牆 z=+21.5）
#     村本地 y = blender z + 院子地面高
#
# 中軸為什麼是 −5 不是 0：獨立版的門與主屋同在 x=0；村版主屋中心偏西 5m
# （HX=−5，那是為了讓出東側的長廊與離れ）。門留在 x=0 的話參道得斜著接
# 玄関，違反定案第 3 條「從外參道一路連到石階腳下不斷開」。40m 長的連續牆
# 上門偏 5m 沒人看得出來；主屋正立面配對稱入母屋屋頂，玄関偏心 5m 一眼就歪
# —— 所以是**門讓主屋**。
const HIEDA_AXIS := -5.0
const MON_HW := 3.6              # 門洞半寬（6m 參道穿得過）
const MON_POST_HW := 0.35        # 門柱半寬
const WALL_HT := 0.525           # 石垣頂半寬（勾配上緣）
const WALL_HB := 0.79            # 石垣腳半寬（勾配下緣）
const INU_W := 1.34               # 犬走り總寬（內 0.34 是接觸陰影帶）
const KARA_HW := 2.9             # 唐破風玄関開口半寬

## 面朝外的四邊形。a→b→c→d 共面即可，朝向由「離開 ctr 的方向」判，繞序自己
## 翻正 —— 手推六個面的繞序純粹是在給自己找錯（獨立版 `_auto_quad` 的教訓）。
## ⚠ Godot 的正面是**順時針**：一樓地板探針驗過的那組 a,b,c/a,c,d 算出來的
## CCW 法線是 −Y，而那面是從 +Y 看得到、射線打得中的。法線明寫不靠
## generate_normals —— 繞序若判錯，錯的會是「面被剔掉」（截圖一眼看得出來），
## 不是「法線朝內」（只表現成一片詭異的暗，很難查）。
func _face_out(st: SurfaceTool, ctr: Vector3, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if n.dot((a + b + c + d) * 0.25 - ctr) > 0.0:
		st.set_normal(n)
		st.add_vertex(a); st.add_vertex(d); st.add_vertex(c)
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
	else:
		st.set_normal(-n)
		st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)


## 石垣腳：上窄下寬的梯形柱（真石垣的「勾配」）。長度沿本地 x，寬度沿本地 z。
## 等寬 box 跟地面交出一條完全垂直的硬邊，讀起來就是「一塊牆放在一塊地上」
## 的兩個物件；往外攤開的斜面讓光沿著它連續變化，牆才像從地裡長出來的
## （使用者驗收意見・前庭修訂輪 2 第 3 點）。
func _batter(g: Node3D, name: String, ln: float, ht: float, hb: float,
		y_lo: float, y_hi: float, mat: Material, pos: Vector3, yaw := 0.0) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ctr := Vector3(0, (y_lo + y_hi) * 0.5, 0)
	var h := ln * 0.5
	for sd in [1.0, -1.0]:
		_face_out(st, ctr, Vector3(-h, y_hi, sd * ht), Vector3(h, y_hi, sd * ht),
			Vector3(h, y_lo, sd * hb), Vector3(-h, y_lo, sd * hb))
	for t in [-h, h]:
		_face_out(st, ctr, Vector3(t, y_hi, -ht), Vector3(t, y_hi, ht),
			Vector3(t, y_lo, hb), Vector3(t, y_lo, -hb))
	_face_out(st, ctr, Vector3(-h, y_hi, -ht), Vector3(h, y_hi, -ht),
		Vector3(h, y_hi, ht), Vector3(-h, y_hi, ht))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = yaw
	lib.add(g, mi, name)
	return mi


## 犬走り：牆腳外一圈兩階碎石帶（暗→淡），把牆腳接進地面。
## ⚠ 內側那條 0.34 寬的是**接觸陰影**，albedo 必須壓到 0.15 —— 量過渲染值：
## 草地 albedo 0.22 出來是 130，第一版暗帶給 0.285 出來 144、比草還亮，整條
## 讀成一道混凝土路緣，等於又多加一條硬邊，跟要解的問題正好相反。
func _apron(g: Node3D, tag: String, p: float, q: float, fix: float, ax: bool,
		yard: float, dk: Material, gv: Material) -> void:
	if q - p < 0.05:
		return
	for sd in [1.0, -1.0]:
		for band in 2:
			var o0: float = WALL_HB + (0.0 if band == 0 else 0.34)
			var o1: float = WALL_HB + (0.34 if band == 0 else INU_W)
			var c: float = fix + sd * (o0 + o1) * 0.5
			var pos := Vector3((p + q) * 0.5, yard + 0.02, c) if ax \
				else Vector3(c, yard + 0.02, (p + q) * 0.5)
			var size := Vector3(q - p, 0.04, o1 - o0) if ax \
				else Vector3(o1 - o0, 0.04, q - p)
			lib.box(g, "犬走り_%s_%d%d" % [tag, int(sd + 1.0), band], size,
				dk if band == 0 else gv, pos)


## 一段格子塀：石垣勾配 → 犬走り → 白漆喰 → 深色木格子帶 → 冠木 → 兩坡瓦頂
## → 棟瓦。`ax` = true 沿 x 走（fix 是 z），false 沿 z 走（fix 是 x）。
##
## 兩軸共用同一支函式而不是各寫一份：六層的尺寸各寫一份等於抄兩遍，改一邊
## 忘另一邊是遲早的事（獨立版第一版的側面回折就是手抄的，格柵間距跟正面
## 對不上）。ap_p/ap_q 是犬走り兩端各自要延伸／內縮到哪 —— 轉角處兩道牆的
## 犬走り**共面重疊**的話，兩張同法線的面互相擋掉環境光，地上會出現全黑補丁
## （唐破風階梯側面的同一個病，獨立版踩過第三次）。所以是接齊、不是疊。
##
## 格柵不各給一個節點：全院 300+ 支，一支一個 MeshInstance3D 會把場景撐爛。
## 收進 slats 由呼叫端一起做成 MultiMesh。
func _hieda_wall_run(g: Node3D, tag: String, p: float, q: float, fix: float, ax: bool,
		yard: float, y_bot: float, slats: Array[Transform3D],
		ap_p: float, ap_q: float) -> void:
	if q - p < 0.05:
		return
	var y_stone := yard + 0.72
	var y_wall := yard + 2.30
	var y_lat := yard + 3.10
	var y_top := yard + 3.50
	var cc := (p + q) * 0.5
	var ln := q - p
	var yaw: float = 0.0 if ax else PI * 0.5
	var at := func(c: float, off: float, y: float) -> Vector3:
		return Vector3(c, y, fix + off) if ax else Vector3(fix + off, y, c)
	var slab := func(nm: String, thick: float, cy: float, h: float, mat: Material,
			ext := 0.0) -> void:
		lib.box(g, nm, Vector3(ln + ext, h, thick) if ax else Vector3(thick, h, ln + ext),
			mat, at.call(cc, 0.0, cy))
	# 腰石垣（勾配梯形）+ 犬走り
	_batter(g, "石垣_%s" % tag, ln, WALL_HT, WALL_HB, y_bot, y_stone,
		_lmat("stone", 1), at.call(cc, 0.0, 0.0), yaw)
	_apron(g, tag, ap_p, ap_q, fix, ax, yard,
		lib.flat_mat("hieda_contact", Color(0.150, 0.150, 0.135), 0.96),
		_lmat("gravel", 2))
	# 白漆喰腰壁
	slab.call("漆喰壁_%s" % tag, 0.86, (y_stone + y_wall) * 0.5, y_wall - y_stone,
		_lmat("plaster", 0))
	# 格子帶：深色底板 + 直立木格柵（格柵厚過底板，才有立體的格子影）。
	# 一面 3.5m 高、40m 長的純白牆在遠景就是一條白帶子，沒有任何尺度感；
	# 橫向的格子把它切成有節奏的段落，遠看深淺相間、近看才是木格柵。
	slab.call("格子底_%s" % tag, 0.80, (y_wall + y_lat) * 0.5, y_lat - y_wall,
		_lmat("dark", 3))
	var n_sl: int = maxi(2, int(ln / 0.42))
	for i in n_sl:
		var pc: float = p + (float(i) + 0.5) * (ln / float(n_sl))
		slats.append(Transform3D(Basis(Vector3.UP, yaw),
			at.call(pc, 0.0, (y_wall + y_lat) * 0.5)))
	slab.call("冠木_%s" % tag, 1.00, y_lat + 0.07, 0.14, _lmat("dark", 1))
	# 兩坡瓦頂（出簷 0.74）+ 棟瓦
	for sd in [-1.0, 1.0]:
		var sl := lib.box(g, "塀屋根_%s_%d" % [tag, int(sd + 1.0)],
			Vector3(ln, 0.10, 0.73) if ax else Vector3(0.73, 0.10, ln), _lmat("kawara", 1),
			at.call(cc, sd * 0.40, y_top - 0.13))
		if ax:
			sl.rotation.x = sd * -0.365
		else:
			sl.rotation.z = sd * 0.365
	slab.call("棟瓦_%s" % tag, 0.28, y_top + 0.15, 0.18, _lmat("kawara", 3))
	_lm_collide(g, Vector3(ln, 3.5, 0.95) if ax else Vector3(0.95, 3.5, ln),
		at.call(cc, 0.0, yard))


## 表門（棟門）：兩根粗門柱 + 冠木 + 貫 + 瓦屋根。參道從中間穿過。
##
## 柱高 3.30（不是 3.60）：狛犬放大 18% 之後，門柱／簷口與狛犬要在同一個
## 視覺量級上 —— 門太高會把石獅子吃掉（使用者：狛犬「被門吃掉」）。兩邊各
## 讓一步比只動一邊自然，狛犬 3.25m 對門柱 3.30m，幾乎同高。
## 門柱比牆身厚（1.10 vs 0.86）才露得出來：獨立版上一版柱寬 0.62 完全埋在
## 牆裡，整座門只剩一片浮在開口上的屋頂，柱子一根都看不到。
func _hieda_gate(g: Node3D, ctr: float, fix: float, yard: float, y_bot: float) -> void:
	var dark := _lmat("dark", 1)
	var stone := _lmat("stone", 1)
	var z_post := yard + 3.30
	var z_beam := yard + 3.32
	for sx in [-1.0, 1.0]:
		var px: float = ctr + sx * (MON_HW + MON_POST_HW)
		# 礎石也走勾配，跟牆腳同一套語言，柱子才不是「插在地上」。半寬與
		# 犬走り的偏移都跟牆腳取同一組（0.525/0.79），兩邊的碎石帶才會接齊
		# 而不是疊在一起。
		_batter(g, "門礎石_%d" % int(sx + 1.0), 2.0 * MON_POST_HW, WALL_HT, WALL_HB,
			y_bot, yard + 0.52, stone, Vector3(px, 0.0, fix))
		_apron(g, "門柱%d" % int(sx + 1.0), px - MON_POST_HW, px + MON_POST_HW, fix, true,
			yard, lib.flat_mat("hieda_contact", Color(0.150, 0.150, 0.135), 0.96),
			_lmat("gravel", 2))
		lib.box(g, "門柱_%d" % int(sx + 1.0), Vector3(2.0 * MON_POST_HW, z_post - yard - 0.48, 1.10),
			dark, Vector3(px, (yard + 0.48 + z_post) * 0.5, fix))
		_lm_collide(g, Vector3(0.9, 3.3, 1.2), Vector3(px, yard, fix))
	var span := 2.0 * (MON_HW + 2.0 * MON_POST_HW)
	lib.box(g, "冠木", Vector3(span, 0.48, 0.52), dark, Vector3(ctr, z_beam + 0.24, fix))
	lib.box(g, "貫", Vector3(span * 0.86, 0.34, 0.34), dark, Vector3(ctr, z_beam - 0.40, fix))
	# 屋根：兩坡，出簷比牆頂大一截 —— 門要比牆搶眼
	var zr := z_beam + 0.48
	for sy in [-1.0, 1.0]:
		var sl := lib.box(g, "門屋根_%d" % int(sy + 1.0), Vector3(span + 1.2, 0.16, 1.70),
			_lmat("kawara", 1), Vector3(ctr, zr + 0.42, fix + sy * 0.815))
		sl.rotation.x = sy * -0.520
	lib.box(g, "門大棟", Vector3(span + 1.2, 0.26, 0.42), _lmat("kawara", 3),
		Vector3(ctr, zr + 0.92, fix))
	for sx2 in [-1.0, 1.0]:                                   # 鬼瓦
		lib.box(g, "鬼瓦_%d" % int(sx2 + 1.0), Vector3(0.34, 0.46, 0.52), _lmat("kawara", 3),
			Vector3(ctr + sx2 * (span * 0.5 + 0.58), zr + 1.02, fix))


## 參道：一條乾淨連續的切石鋪面，中央微拱。z1（門外）→ z0（石階腳下）。
##
## ⚠ 原始規格是「邊緣與草地不規則交錯侵蝕」。使用者看過參考圖（求聞編年史
## 的稗田邸參道）後改規格 —— 那是**整齊的切石鋪面**，不是荒廢的碎石徑。
## 侵蝕感讓整條路看起來像沒人維護的野徑，跟「貴族宅邸的正式參道」是反的。
## 石板尺寸仍有 ±3% 色差（真石材本來就不同色），但**幾何**完全對齊。
func _hieda_sando(g: Node3D, ctr: float, z0: float, z1: float, wc: Vector2, y0: float) -> void:
	const WIDTH := 6.0
	var hw := WIDTH * 0.5
	# ⚠ 橫向**五**塊不是獨立版的四塊：偶數塊會在正中央留下一條從門一路通到石階、
	# 完全不斷開的縱向目地。橫向目地在視線裡是被壓扁的短線，那條縱向的卻是
	# 沿著視線鋪過去的整條 —— 遠看就是一道排水溝，把整條參道從中間切成兩半
	# （引擎內截圖抓到；四道靜態閘看不見這種東西）。奇數塊讓中央那塊跨在中軸上，
	# 目地就變成兩條對稱的、離軸線 0.6m 的線，這也是真的切石敷き的排法。
	var cols := 5
	var rows: int = maxi(1, int(absf(z1 - z0) / 1.55))
	var joint := 0.055
	var crown := func(x: float) -> float:              # 中央微拱：拋物線
		var u: float = x / hw
		return 0.16 * maxf(0.0, 1.0 - u * u)
	# 底層鋪面（目地的陰影色）—— 石板浮在它上面，縫看起來就是暗的。
	# ⚠ 不能鋪一片**平的**底板：中央微拱把內側兩排的板抬高 0.15m，平底板與板面
	# 之間就開出一道 0.19m 深的槽，正中央那條縫遠看是一條黑溝（引擎內截圖抓到
	# 的；lm_ghost／check_map／walk_test／portal_test 四道閘全部看不見這種東西）。
	# 底板改成跟著每一排一起傾斜、只低 0.045m，縫才是「縫」不是「溝」。
	var base_y: float = height_at(wc.x + ctr, wc.y + (z0 + z1) * 0.5) - y0
	var jmat := lib.flat_mat("hieda_sando_joint", Color(0.150, 0.152, 0.145), 0.94)
	for c0 in cols:
		var bxa: float = -hw + WIDTH * float(c0) / float(cols)
		var bxb: float = -hw + WIDTH * float(c0 + 1) / float(cols)
		var bha: float = crown.call(bxa)
		var bhb: float = crown.call(bxb)
		var bs := lib.box(g, "參道底_%d" % c0,
			Vector3(bxb - bxa + joint * 2.0, 0.08, absf(z1 - z0) + joint * 2.0), jmat,
			Vector3(ctr + (bxa + bxb) * 0.5, base_y + 0.030 + (bha + bhb) * 0.5,
				(z0 + z1) * 0.5))
		bs.rotation.z = -atan2(bhb - bha, bxb - bxa)
	for r in rows:
		var za: float = z0 + (z1 - z0) * float(r) / float(rows) + joint
		var zb: float = z0 + (z1 - z0) * float(r + 1) / float(rows) - joint
		var ry: float = height_at(wc.x + ctr, wc.y + (za + zb) * 0.5) - y0
		for c in cols:
			var xa: float = -hw + WIDTH * float(c) / float(cols) + joint
			var xb: float = -hw + WIDTH * float(c + 1) / float(cols) - joint
			var ha: float = crown.call(xa)
			var hb: float = crown.call(xb)
			var sl := lib.box(g, "參道石_%d_%d" % [r, c],
				Vector3(xb - xa, 0.10, absf(zb - za)), _lmat("stone", (r + c) % 4),
				Vector3(ctr + (xa + xb) * 0.5, ry + 0.075 + (ha + hb) * 0.5,
					(za + zb) * 0.5))
			# 拱是靠**每塊板自己傾斜**接出來的，不是四排各給一個高度：
			# 四排各平放的話排與排之間會出現 8cm 的階，遠看是四條並排的路。
			sl.rotation.z = -atan2(hb - ha, xb - xa)


## 唐破風的斷面曲線。t ∈ [−1,1]（0=棟、±1=簷角），回傳絕對高度。
## 末端那一勾用 s⁶：六次方在 s<0.75 幾乎是 0，只有最外側十幾 % 抬得動 ——
## 剛好是簷角的位置，不會把中段的凸壓平。
func _kara_y(t: float, peak: float, drop := 1.25, flare := 0.55) -> float:
	var s: float = minf(1.0, absf(t))
	return peak - drop * pow(sin(s * PI * 0.5), 2.0) + flare * pow(s, 6.0)


## 向唐破風玄関（村版・程序化）：屋面 + 破風板 + 妻壁 + 兎毛通 + 向拝柱 + 虹樑
## + 五段石階。使用者定案 C-2：不整棟換 hieda_main.glb，只在村版主屋南面補
## 這座前廊 —— 定案構圖第 2 條說「三對添景把視線收束到唐破風玄関」，村版主屋
## 原本是一片平立面，參道走到底會停在空牆前，整條軸線沒有終點。
##
## 屋面**不是**把斷面沿深度平移拉出去（那是圓筒，看起來像水管）：從牆面掃到
## 簷口的過程中半寬 3.35→3.85 外張、棟高 4.45→3.75 下傾，每一圈都是一條不同
## 的 S 曲線，圈與圈之間鋪 quad。高度是被上下夾死的 —— 上有裳階簷口（底 4.5）、
## 下有腰壁（頂 1.76），動 peak 之前先重算這兩個夾擠點。
func _hieda_karahafu(g: Node3D, ctr: float, z_face: float, deck_y: float, yard: float) -> void:
	const ZB := -0.13                     # 屋面內端（埋進牆 0.13）
	const ZT := 3.35                      # 簷口離牆面
	const HWB := 3.35
	const HWT := 3.85
	const SOF := 0.22                     # 軒裏（下皮）厚
	const BD_H := 0.46                    # 破風板垂高
	const BD_T := 0.20                    # 破風板厚
	var pk_b := yard + 4.45
	var pk_t := yard + 3.75
	var nd := 2
	var nt := 18
	var hw_at := func(u: float) -> float: return HWB + (HWT - HWB) * u
	var pk_at := func(u: float) -> float: return pk_b + (pk_t - pk_b) * u
	var pt := func(i: int, j: int) -> Vector3:
		var u: float = float(i) / float(nd)
		var v: float = float(j) / float(nt) * 2.0 - 1.0
		return Vector3(ctr + v * float(hw_at.call(u)),
			_kara_y(v, float(pk_at.call(u))), z_face + ZB + (ZT - ZB) * u)
	var ctr3 := Vector3(ctr, pk_b - 2.0, z_face + (ZB + ZT) * 0.5)
	# 屋面（上皮）+ 兩側簷口的厚度側面
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in nd:
		for j in nt:
			_face_out(st, ctr3, pt.call(i, j), pt.call(i, j + 1),
				pt.call(i + 1, j + 1), pt.call(i + 1, j))
	for i in nd:
		for j in [0, nt]:
			var a: Vector3 = pt.call(i, j)
			var b: Vector3 = pt.call(i + 1, j)
			_face_out(st, ctr3, a, b, b - Vector3(0, SOF, 0), a - Vector3(0, SOF, 0))
	var roof := MeshInstance3D.new()
	roof.mesh = st.commit()
	roof.material_override = _lmat("kawara", 1)
	lib.add(g, roof, "玄関屋面")
	# 棟：收在破風板後面 0.60m。頂到簷口的話正面看就是破風尖上頂著一顆方盒子
	# （棟的端面），唐破風最好看的那個頂點會被自己的棟砸爛。
	var u_rg: float = (ZT - 0.60 - ZB) / (ZT - ZB)
	var rg_a := Vector3(ctr, pk_b + 0.06, z_face + ZB)
	var rg_b := Vector3(ctr, float(pk_at.call(u_rg)) + 0.06, z_face + ZT - 0.60)
	lib.strut(g, "玄関棟", rg_a, rg_b, 0.13, _lmat("kawara", 3), 4)
	# 軒裏（下皮）：玩家站在階梯上抬頭第一眼就是這一面，零厚度的單面屋頂
	# 會被背面剔除直接看穿到天空去。
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dn := Vector3(0, SOF, 0)
	for i in nd:
		for j in nt:
			_face_out(st2, ctr3 + Vector3(0, 40.0, 0),
				pt.call(i, j) - dn, pt.call(i, j + 1) - dn,
				pt.call(i + 1, j + 1) - dn, pt.call(i + 1, j) - dn)
	var sof := MeshInstance3D.new()
	sof.mesh = st2.commit()
	sof.material_override = _lmat("wood", 2)
	lib.add(g, sof, "玄関軒裏")
	# 破風板：沿簷口那條 S 曲線垂下的厚板 —— 唐破風的招牌
	var st3 := SurfaceTool.new()
	st3.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zt: float = z_face + ZT
	for j in nt:
		var v0: float = float(j) / float(nt) * 2.0 - 1.0
		var v1: float = float(j + 1) / float(nt) * 2.0 - 1.0
		var x0: float = ctr + v0 * HWT
		var x1: float = ctr + v1 * HWT
		var y0t := _kara_y(v0, pk_t)
		var y1t := _kara_y(v1, pk_t)
		var f0 := Vector3(x0, y0t, zt)
		var f1 := Vector3(x1, y1t, zt)
		_face_out(st3, ctr3, f0, f1, Vector3(x1, y1t - BD_H, zt),
			Vector3(x0, y0t - BD_H, zt))
		_face_out(st3, ctr3, Vector3(x0, y0t - BD_H, zt), Vector3(x1, y1t - BD_H, zt),
			Vector3(x1, y1t - BD_H, zt - BD_T), Vector3(x0, y0t - BD_H, zt - BD_T))
	var bd := MeshInstance3D.new()
	bd.mesh = st3.commit()
	bd.material_override = _lmat("dark", 1)
	lib.add(g, bd, "玄関破風板")
	# 妻壁：破風板背後那片漆喰，被 S 曲線切成一彎月牙
	var y_lint := _kara_y(2.78 / HWT, pk_t) - 0.35
	var st4 := SurfaceTool.new()
	st4.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in nt:
		var v0: float = float(j) / float(nt) * 2.0 - 1.0
		var v1: float = float(j + 1) / float(nt) * 2.0 - 1.0
		var y0t := _kara_y(v0, pk_t) - BD_H
		var y1t := _kara_y(v1, pk_t) - BD_H
		if y0t <= y_lint and y1t <= y_lint:
			continue                       # 曲線已經掉到樑下，月牙到此為止
		_face_out(st4, ctr3, Vector3(ctr + v0 * HWT, maxf(y0t, y_lint), zt - BD_T),
			Vector3(ctr + v1 * HWT, maxf(y1t, y_lint), zt - BD_T),
			Vector3(ctr + v1 * HWT, y_lint, zt - BD_T),
			Vector3(ctr + v0 * HWT, y_lint, zt - BD_T))
	var gw := MeshInstance3D.new()
	gw.mesh = st4.commit()
	gw.material_override = _lmat("plaster", 0)
	lib.add(g, gw, "玄関妻壁")
	# 兎毛通（破風正中央垂下的懸魚）：兩段收窄，不然就是掛在破風上的一顆箱子
	var yc := _kara_y(0.0, pk_t) - BD_H
	lib.box(g, "兎毛通_上", Vector3(0.52, 0.30, 0.14), _lmat("dark", 1),
		Vector3(ctr, yc - 0.14, zt - BD_T - 0.06))
	lib.box(g, "兎毛通_下", Vector3(0.30, 0.26, 0.14), _lmat("dark", 1),
		Vector3(ctr, yc - 0.38, zt - BD_T - 0.06))
	# 向拝柱 ×2 + 礎石 + 虹樑。柱頂用 _kara_y 現算屋面高度，不寫死數字：
	# 改上面任何一個參數，柱子會自己長到屋面底下，不會又戳出去或懸空。
	var z_post: float = z_face + 2.90
	var u_post: float = (2.90 - ZB) / (ZT - ZB)
	var pk_p: float = float(pk_at.call(u_post))
	var hw_p: float = float(hw_at.call(u_post))
	var y_col := _kara_y(2.55 / hw_p, pk_p) - SOF - 0.06
	for sx in [-1.0, 1.0]:
		lib.box(g, "礎石_%d" % int(sx + 1.0), Vector3(0.72, 0.26, 0.72), _lmat("stone", 1),
			Vector3(ctr + sx * 2.55, yard + 0.13, z_post))
		lib.box(g, "向拝柱_%d" % int(sx + 1.0), Vector3(0.40, y_col - yard - 0.26, 0.40),
			_lmat("dark", 1), Vector3(ctr + sx * 2.55, (yard + 0.26 + y_col) * 0.5, z_post))
	lib.box(g, "虹樑", Vector3(5.9, 0.42, 0.34), _lmat("dark", 1),
		Vector3(ctr, y_lint - 0.21, z_post))
	# 玄関口：格子戸（主屋那面平牆上要看得出這裡是入口）
	lib.box(g, "玄関格子戸", Vector3(2.0 * KARA_HW - 0.4, 2.30, 0.10), _lmat("lattice", 1),
		Vector3(ctr, deck_y + 1.15, z_face + 0.06))
	lib.box(g, "玄関框", Vector3(2.0 * KARA_HW, 0.26, 0.16), _lmat("dark", 1),
		Vector3(ctr, deck_y + 2.42, z_face + 0.06))
	# ── 五段石階 ──
	# ⚠ 不能用五個從地面長上來的**巢狀** box：側面全部落在同一個平面上互相
	# 重疊，共面的兩張面會互相擋掉環境光，整片階梯側面算成純黑（獨立版查了
	# 比唐破風本身還久的那個病）。這裡每一階各佔各的 z 區間、不重疊。
	# ⚠ 階梯寬度收到 4.30（不是開口寬 5.70）：向拝柱的礎石在 x=±2.55、寬 0.72
	# （→ 2.19~2.91），照獨立版的 hw_st=2.85 鋪下去，兩根柱子會**穿過階梯側面**
	# 站在踏面中間。收到 2.15 之後是柱子夾著階梯，那才是向拝柱該站的位置。
	var n_st := 5
	var tread := 0.42
	var hw_st := 2.15
	var z_bot: float = z_face + 2.20 + tread * float(n_st)
	for i in n_st:
		var h: float = (deck_y - yard) * float(i + 1) / float(n_st)
		var zc: float = z_bot - tread * (float(i) + 0.5)
		lib.box(g, "玄関階_%d" % i, Vector3(2.0 * hw_st, h, tread), _lmat("stone", 2),
			Vector3(ctr, yard + h * 0.5, zc))
		var sb := StaticBody3D.new()
		sb.position = Vector3(ctr, yard + h * 0.5, zc)
		var sh := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(2.0 * hw_st, h, tread)
		sh.shape = bx
		sb.add_child(sh)
		lib.add(g, sb, "玄関階碰撞_%d" % i)
		sh.owner = _root


## ── 稗田邸（第六座・最後一座）：格子塀＋棟門＋二層入母屋主屋＋石組庭池 ──
##
## 舊 builder 的本地座標整組**原封不動**沿用：舊址中心 (−78, 2)、新址中心
## (−78, −164)，兩邊都是「以院落中心為原點」，所以只有需要拿世界座標去問
## 地形的地方要換算（wc + local）。庭池的相對位置 (−2, +8) 也一樣，於是
## HIEDA_POND 就直接定成 (−80, −156)。
##
## ⚠ 這座宅子跟前五座不同：它**會改地形**（庭池在 height_at 裡挖碗）。
## 所以三件事要同時成立，缺一就會出現「水面斜掛」或「主屋沉 1.7m」：
##   1. height_at 的順序是「先整平院子、再挖池」
##   2. _pond_bank_y（＝整平後的岸高）同時餵給 pond_water 與 _lm_ground_sample
##   3. _lm_ground_sample 要把池心那圈當成「地面 = 水面」，_ground_under
##      才不會把整棟宅子的基準高度拉到碗底
func _lm_hieda(g: Node3D, spread: float) -> void:
	var wc := Vector2(g.position.x, g.position.z)
	var y0: float = g.position.y
	# 院落地面。_lm_ground_sample 修好之後群組原點就是院子地面，yard≈0；
	# 仍然照算不寫死 0 —— 哪天整平規則再改，前庭會自己跟著走。
	var yard: float = _pond_bank_y(wc.x, wc.y) - y0
	var y_bot: float = yard - (spread + 0.35)
	var hw := 20.0
	var hd := 21.5
	# ── 格子塀：四面（南面讓出門洞）──
	# 使用者定案 C-4：五段全部換成格子塀規格，把定案語言補完整圈。只換門面
	# 那道的話，轉角處會是「格子塀硬接築地塀」，兩種語言對撞比不換還糟。
	var slats: Array[Transform3D] = []
	var gate_hw := MON_HW + 2.0 * MON_POST_HW
	# 犬走り在轉角**接齊不重疊**：南北兩道各往外多鋪一個犬走り的寬度，
	# 東西兩道就往內縮同一個量。重疊的話兩張同法線的面互相擋掉環境光，
	# 轉角地上會出現全黑補丁。
	var ex := WALL_HB + INU_W
	_hieda_wall_run(g, "北", -hw, hw, -hd, true, yard, y_bot, slats, -hw - ex, hw + ex)
	for sx in [-1.0, 1.0]:
		_hieda_wall_run(g, "東" if sx > 0.0 else "西", -hd, hd, sx * hw, false,
			yard, y_bot, slats, -hd + ex, hd - ex)
	_hieda_wall_run(g, "南西", -hw, HIEDA_AXIS - gate_hw, hd, true, yard, y_bot, slats,
		-hw - ex, HIEDA_AXIS - gate_hw)
	_hieda_wall_run(g, "南東", HIEDA_AXIS + gate_hw, hw, hd, true, yard, y_bot, slats,
		HIEDA_AXIS + gate_hw, hw + ex)
	var slat_mesh := BoxMesh.new()
	slat_mesh.size = Vector3(0.14, 0.68, 0.94)
	slat_mesh.material = _lmat("dark", 0)
	var lmm := MultiMeshInstance3D.new()
	lmm.multimesh = lib.make_multimesh(slat_mesh, slats, [], OUT_DIR + "gen/mm_hieda_koushi.res")
	lib.add(g, lmm, "MM_格子")
	# ── 表門（棟門）+ 參道 ──
	_hieda_gate(g, HIEDA_AXIS, hd, yard, y_bot)
	_hieda_sando(g, HIEDA_AXIS, 0.35, hd + 0.9, wc, y0)
	# ── 對稱添景：狛犬 / 石燈籠 / 松，三對沿參道由內而外、由窄而寬排成八字 ──
	# 前庭深 22.6m（門 z=+21.5 → 石階 z=−1.1）。狛犬擺在「從門往內約 1/3」處
	# = 21.5 − 22.6/3 ≈ +14.0。燈籠與松依序往外側讓開，站在門口往內看，
	# 三對物件把視線收束到唐破風玄関上。
	# 資產一律 `prop_mesh` 載定案的 .glb —— 抄一份幾何過來就等於開第二個真相
	# 來源，下次改狛犬一定有一隻沒跟到。
	var prop_stone := lib.rock_mat_dry()
	var komainu := lib.prop_mesh("res://assets/models/komainu_a.glb", prop_stone)
	var lantern := lib.prop_mesh("res://assets/models/stone_lantern.glb", prop_stone)
	var pine_m := lib.prop_mesh("res://assets/models/hieda_pine_a.glb")
	# 狛犬**維持嚴格左右對稱**：牠是儀式性的門衛，一對石獅子擺歪只是沒對齊。
	# 放大到 1.18（2.75 → 3.25m）、門柱同時降到 3.30，兩邊各讓一步之後狛犬跟
	# 門柱幾乎同高，在門前的構圖裡是同一個量級，不再是門洞旁的小擺設。
	for sx2 in [-1.0, 1.0]:
		var km := MeshInstance3D.new()
		km.mesh = komainu
		km.position = Vector3(HIEDA_AXIS + sx2 * 4.7,
			height_at(wc.x + HIEDA_AXIS + sx2 * 4.7, wc.y + 14.0) - y0, 14.0)
		km.scale = Vector3.ONE * 1.18
		# 原型面朝 +z；繞 y 轉 ∓1.0 讓兩隻都斜對參道中線、同時偏向來人
		km.rotation.y = -sx2 * 1.0
		lib.add(g, km, "狛犬_%d" % int(sx2 + 1.0))
		_lm_collide(g, Vector3(1.3, 3.3, 1.9),
			Vector3(km.position.x, yard, km.position.z))
	# ── 松與燈籠：刻意**不對稱** ──
	# 上一版兩側完全鏡射、而且間距均等，讀起來像貼上去的裝飾而不是長出來的
	# 庭園。四個物件的座標／旋轉／縮放全部拆成明表寫死、放棄 for 迴圈鏡射 ——
	# 迴圈天生只生對稱，要不對稱就得先放棄迴圈。
	#   右側：燈籠緊挨狛犬（1.9m）、松再拉遠（4.8m）—— 疏密對比大
	#   左側：燈籠退遠（3.6m）、松貼著燈籠（2.9m）—— 節奏跟右側相反
	for L in [[6.50, 14.70, 0.26, 1.06], [-7.40, 16.40, -0.62, 0.98]]:
		var lx: float = HIEDA_AXIS + float(L[0])
		var lz: float = float(L[1])
		var ln2 := MeshInstance3D.new()
		ln2.mesh = lantern
		ln2.position = Vector3(lx, height_at(wc.x + lx, wc.y + lz) - y0, lz)
		ln2.scale = Vector3.ONE * float(L[3])
		ln2.rotation.y = float(L[2])
		lib.add(g, ln2, "門前燈籠_%d" % int(signf(float(L[0])) + 1.0))
		_lm_collide(g, Vector3(1.0, 2.6, 1.0), Vector3(lx, yard, lz))
	# 門前的松：用稗田邸自己那棵遞迴樹（tree_pine_a 是「圓錐插在棍子上」）。
	# 高度靠縮放給定 —— hieda_pine_a 的原型高 8.0m（make_props 量過）。
	for P in [[9.90, 18.10, 0.9, 7.6], [-9.50, 18.40, 2.4, 8.8]]:
		var px2: float = HIEDA_AXIS + float(P[0])
		var pz2: float = float(P[1])
		var pn := MeshInstance3D.new()
		pn.mesh = pine_m
		pn.material_override = lib.foliage_vc_mat()
		pn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		pn.position = Vector3(px2, height_at(wc.x + px2, wc.y + pz2) - y0, pz2)
		pn.scale = Vector3.ONE * (float(P[3]) / 8.0)
		pn.rotation.y = float(P[2])
		lib.add(g, pn, "門前松_%d" % int(signf(float(P[0])) + 1.0))
	# ⚠ 六座地標共用一條 `_lm_rng`（照 LANDMARKS 順序抽）。前庭改寫之後抽樣
	# 次數變了，後面的鎮守之杜／市場／足洗邸會整組位移 —— 那是這一輪範圍外的
	# 三座，不能動。舊前庭（築地塀 5 段 ×7 次色調 + 藥醫門 4 次）一共抽 39 次，
	# 新前庭全部明指色調（0 次），所以這裡把序列補回原位。
	# 附帶好處：庭池的石組排列跟搬遷前**逐項一致**，只有池心位置變了 ——
	# 「這一輪只動了該動的東西」因此驗得出來，不必用眼睛比。
	for _i in 39:
		_lm_rng.randf()
	# ── 主屋：二層入母屋 ──
	# 25×15、一層 3.6 + 二層 2.9、入母屋屋頂。位置往北挪（中心 z −11.5），
	# 南面讓出庭池的曲岸。
	var hfoot := spread + 0.4
	var HX := -5.0
	var HZ := -11.5
	lib.box(g, "主屋基壇", Vector3(26.5, 0.6 + hfoot, 16.5), _lmat("stone"),
		Vector3(HX, 0.3 - hfoot * 0.5, HZ))
	lib.box(g, "主屋", Vector3(25.0, 3.6, 15.0), _lmat("plaster", 0), Vector3(HX, 0.6 + 1.8, HZ))
	lib.box(g, "主屋腰壁", Vector3(25.1, 1.15, 15.1), _lmat("shitami", 0),
		Vector3(HX, 0.6 + 0.58, HZ))
	# 一層立面的通柱（南面）
	for i in 9:
		var cx2: float = HX - 12.0 + float(i) * 3.0
		# 玄関開口讓路：唐破風底下那一根會正對門洞、站在土間口正中央
		if absf(cx2 - HIEDA_AXIS) < KARA_HW:
			continue
		lib.box(g, "主屋柱_%d" % i, Vector3(0.17, 3.6, 0.12), _lmat("dark", 0),
			Vector3(cx2, 0.6 + 1.8, HZ + 7.56))
	# 裳階（一二層之間的環繞屋簷）—— 這一圈才是「二層豪邸」的剪影。
	# ⚠ 裳階的內緣要**塞進二階牆裡**（二階半深 6.0／半寬 10.5），
	# 不然從上往下看是一圈懸空的簷。
	for sd2 in [-1.0, 1.0]:
		var mk := lib.box(g, "裳階_z%d" % int(sd2 + 1), Vector3(27.0, 0.18, 3.1), _lmat("kawara"),
			Vector3(HX, 4.62, HZ + sd2 * 7.15))
		mk.rotation.x = sd2 * -0.42
		var mk2 := lib.box(g, "裳階_x%d" % int(sd2 + 1), Vector3(3.4, 0.18, 17.2), _lmat("kawara"),
			Vector3(HX + sd2 * 11.8, 4.62, HZ))
		mk2.rotation.z = sd2 * 0.42
	# 二層（內縮，才有塔狀的收分）
	lib.box(g, "主屋二階", Vector3(21.0, 2.9, 12.0), _lmat("plaster", 0),
		Vector3(HX, 4.5 + 1.45, HZ))
	lib.box(g, "二階窗帯", Vector3(18.0, 1.15, 0.1), _lmat("lattice", 0),
		Vector3(HX, 6.2, HZ + 6.06))
	# 入母屋 = 切妻（上）+ 四注的裾（下）。gable_roof 給切妻與妻壁，
	# 兩端再各蓋一片斜的隅屋根蓋住妻壁下半 —— 剪影就是入母屋。
	lib.gable_roof(g, 7.4, 23.0, 14.0, 0.52, 0.34, _lmat("kawara"), _lmat("plaster", 0),
		Vector3(HX, 0, HZ))
	for e in [-1.0, 1.0]:
		var hip := lib.box(g, "隅屋根_%d" % int(e + 1), Vector3(5.4, 0.3, 10.5), _lmat("kawara"),
			Vector3(HX + e * 9.4, 9.35, HZ))
		hip.rotation.z = e * 0.72
	lib.box(g, "緣側", Vector3(24.0, 0.3, 2.2), _lmat("wood"), Vector3(HX, 0.75, HZ + 8.6))
	# ⚠ 高欄在玄関這一段要**開口**。獨立版的教訓：階梯做好了，前面卻橫著一整排
	# 不斷開的高欄，等於做了一座走不上去的階梯。束柱同理，落在開口裡的跳過。
	for i in 12:
		var rx: float = HX - 11.5 + float(i) * 2.1
		if absf(rx - HIEDA_AXIS) < KARA_HW:
			continue
		lib.box(g, "高欄束_%d" % i, Vector3(0.1, 0.6, 0.1), _lmat("dark", 0),
			Vector3(rx, 1.35, HZ + 9.6))
	for k4 in 2:
		var a2: float = (HX - 12.0) if k4 == 0 else (HIEDA_AXIS + KARA_HW)
		var b2: float = (HIEDA_AXIS - KARA_HW) if k4 == 0 else (HX + 12.0)
		lib.box(g, "高欄_%d" % k4, Vector3(b2 - a2, 0.12, 0.12), _lmat("dark", 0),
			Vector3((a2 + b2) * 0.5, 1.68, HZ + 9.6))
	_lm_collide(g, Vector3(25.4, 10.0, 15.4), Vector3(HX, 0, HZ))
	# ── 唐破風玄関前廊（使用者定案 C-2）──
	_hieda_karahafu(g, HIEDA_AXIS, HZ + 7.5, 0.90, yard)
	# 長廊（連到東側的離れ）
	lib.box(g, "長廊", Vector3(2.4, 0.24, 12.0), _lmat("wood"), Vector3(10.6, 0.7, -6.0))
	for i in 5:
		lib.cyl(g, "廊柱_%d" % i, 0.12, 0.12, 2.4, _lmat("dark"),
			Vector3(11.5, 1.9, -11.0 + float(i) * 2.6), 6)
	for sd2 in [-1, 1]:
		var sl2 := lib.box(g, "廊屋根_%d" % (sd2 + 1), Vector3(1.9, 0.16, 12.4), _lmat("kawara"),
			Vector3(10.6 + float(sd2) * 0.85, 3.15, -6.0))
		sl2.rotation.z = float(sd2) * -0.5
	lib.box(g, "離れ", Vector3(6.5, 3.2, 6.5), _lmat("plaster"), Vector3(13.5, 1.9, -14.5))
	lib.box(g, "離れ屋根", Vector3(7.9, 0.26, 7.9), _lmat("kawara"), Vector3(13.5, 3.7, -14.5))
	_lm_collide(g, Vector3(6.7, 3.6, 6.7), Vector3(13.5, 0, -14.5))
	# ── 庭園：石組庭池（水面由 lib.pond_water 產，這裡只做護岸與添景）──
	var pl := Vector3(HIEDA_POND.x - wc.x, 0.0, HIEDA_POND.y - wc.y)
	var shore := lib.pond_shore_r(HIEDA_POND_R, HIEDA_POND_SINK, HIEDA_POND_DEPTH)
	# 石頭要坐在**自己腳下**的地面上。這棟宅子的原點是院落的基準高度，
	# 池邊的地已經往下挖了 —— 照原點擺，石頭會浮在水面上像紙片。
	var rock_y := func(wx: float, wz: float, sink: float) -> float:
		return height_at(wx, wz) - y0 - sink
	# ── 石組：日本庭園的石不是均勻繞一圈，是「三尊石」的組法 ──
	#   ・**主石立起來**（縦石），高過水面，一組只有一顆
	#   ・旁邊配 1~2 顆矮的臥石（横石）
	#   ・組與組之間**大片留白**，留白處鋪州濱（細卵石灘）
	#   ・數量取奇數（三・五・七）
	var rk_i := 0
	var groups := 5                                   # 奇數
	var g_ang: Array[float] = []
	var a0 := _lm_rng.randf_range(0.0, TAU)
	for gi in groups:
		# 不等角：黃金角的擾動，避免五顆平均分佈（那又變成項鍊）
		g_ang.append(a0 + float(gi) * TAU / float(groups) + _lm_rng.randf_range(-0.34, 0.34))
	for gi in groups:
		var ga: float = g_ang[gi]
		var upright: bool = gi % 2 == 0               # 隔一組立一顆
		var members := 2 + (gi % 2)
		for k in members:
			var a := ga + float(k) * _lm_rng.randf_range(0.055, 0.10) * (1.0 if k % 2 == 0 else -1.0)
			var rr3: float = shore * _lm_rng.randf_range(0.97, 1.09)
			var wx: float = wc.x + pl.x + cos(a) * rr3
			var wz: float = wc.y + pl.z + sin(a) * rr3
			var rk := MeshInstance3D.new()
			var main := k == 0
			# 主石：立起來（y 拉長、xz 收窄）。配石：臥著。
			var sc: float = _lm_rng.randf_range(0.75, 1.15) if main else _lm_rng.randf_range(0.42, 0.72)
			rk.mesh = lib.blob_mesh(rk_i * 7 + 3,
				_lm_rng.randf_range(1.15, 1.55) if (main and upright) else _lm_rng.randf_range(0.42, 0.62),
				_lm_rng.randf_range(0.20, 0.34))
			rk.material_override = _lmat("cobble", -1)
			rk.position = Vector3(pl.x + cos(a) * rr3,
				rock_y.call(wx, wz, sc * (0.18 if (main and upright) else 0.34)),
				pl.z + sin(a) * rr3)
			rk.scale = Vector3(sc * _lm_rng.randf_range(0.72, 0.95), sc * _lm_rng.randf_range(0.9, 1.35),
				sc * _lm_rng.randf_range(0.72, 0.95)) if (main and upright) \
				else Vector3(sc * _lm_rng.randf_range(1.0, 1.4), sc * _lm_rng.randf_range(0.55, 0.8),
					sc * _lm_rng.randf_range(1.0, 1.4))
			rk.rotation = Vector3(_lm_rng.randf_range(-0.18, 0.18), _lm_rng.randf_range(0.0, TAU),
				_lm_rng.randf_range(-0.18, 0.18))
			lib.add(g, rk, "石組%d_%s%d" % [gi, "主石" if main else "添石", k])
			rk_i += 1
	# ── 州濱（すはま）：兩組石之間的留白鋪細卵石，一路鋪進淺水 ──
	for gi in groups:
		var a_lo: float = g_ang[gi] + 0.28
		var a_hi: float = g_ang[(gi + 1) % groups] + (TAU if gi == groups - 1 else 0.0) - 0.28
		if a_hi - a_lo < 0.25:
			continue
		var np := int((a_hi - a_lo) * 9.0)
		for k2 in np:
			var a3: float = a_lo + (a_hi - a_lo) * (float(k2) + 0.5) / float(np)
			for band in 3:                            # 三圈：岸上、水際、淺水
				var pr: float = shore * (1.12 - float(band) * 0.11) * _lm_rng.randf_range(0.98, 1.02)
				var sc2 := _lm_rng.randf_range(0.10, 0.24) * (1.0 - float(band) * 0.15)
				var pb := MeshInstance3D.new()
				pb.mesh = lib.blob_mesh(rk_i * 13 + k2 * 5 + band * 3 + 11,
					_lm_rng.randf_range(0.30, 0.46), 0.14)
				pb.material_override = _lmat("cobble", -1)
				var pwx: float = wc.x + pl.x + cos(a3) * pr
				var pwz: float = wc.y + pl.z + sin(a3) * pr
				pb.position = Vector3(pl.x + cos(a3) * pr,
					rock_y.call(pwx, pwz, sc2 * 0.62), pl.z + sin(a3) * pr)
				pb.scale = Vector3(sc2 * _lm_rng.randf_range(1.1, 1.5), sc2 * _lm_rng.randf_range(0.5, 0.75),
					sc2 * _lm_rng.randf_range(1.1, 1.5))
				pb.rotation.y = _lm_rng.randf_range(0.0, TAU)
				lib.add(g, pb, "州濱_%d" % rk_i)
				rk_i += 1
	# ── 睡蓮：只鋪在一側，不要撒滿（滿池浮葉是水草不是庭園）──
	var lily_a := g_ang[1] + _lm_rng.randf_range(-0.3, 0.3)
	var pad := lib.tuft_mesh(6, 0.26, 0.30, Color(0.16, 0.30, 0.14), Color(0.28, 0.46, 0.20))
	for i in 11:
		var pa := lily_a + _lm_rng.randf_range(-0.85, 0.85)
		var pd: float = shore * _lm_rng.randf_range(0.30, 0.78)
		var lp := MeshInstance3D.new()
		lp.mesh = pad
		lp.position = Vector3(pl.x + cos(pa) * pd,
			rock_y.call(wc.x + pl.x + cos(pa) * pd, wc.y + pl.z + sin(pa) * pd,
				HIEDA_POND_SINK - 0.04),
			pl.z + sin(pa) * pd)
		lp.scale = Vector3.ONE * _lm_rng.randf_range(0.7, 1.3)
		lp.rotation.y = _lm_rng.randf_range(0.0, TAU)
		lib.add(g, lp, "睡蓮_%d" % i)
	# ── 菖蒲：只長在州濱那幾段的水際，不繞整圈 ──
	var iris := lib.tuft_mesh(7, 0.70, 0.10, Color(0.12, 0.26, 0.10), Color(0.34, 0.54, 0.20))
	for i in 16:
		var ia := g_ang[int(_lm_rng.randf() * float(groups))] + _lm_rng.randf_range(0.35, 1.1)
		var ir: float = shore * _lm_rng.randf_range(0.96, 1.06)
		var ib := MeshInstance3D.new()
		ib.mesh = iris
		ib.position = Vector3(pl.x + cos(ia) * ir,
			rock_y.call(wc.x + pl.x + cos(ia) * ir, wc.y + pl.z + sin(ia) * ir, 0.05),
			pl.z + sin(ia) * ir)
		ib.scale = Vector3.ONE * _lm_rng.randf_range(0.7, 1.25)
		ib.rotation.y = _lm_rng.randf_range(0.0, TAU)
		lib.add(g, ib, "菖蒲_%d" % i)
	# ── 中島 + 石橋：池泉庭園的核心（曲岸／中島／石橋）──
	# 中島不是浮的 —— 它從碗底疊上來，頂面略低於岸、高於水面。
	var isl := Vector2(pl.x + 2.3, pl.z + 1.4)                 # 本地座標的島心
	var bank_ref: float = height_at(wc.x + pl.x + 12.0, wc.y + pl.z) - y0
	var floor_y: float = height_at(wc.x + isl.x, wc.y + isl.y) - y0
	var top_y: float = bank_ref - 0.18
	var base := MeshInstance3D.new()
	base.mesh = lib.blob_mesh(311, 0.55, 0.22)
	base.material_override = _lmat("cobble", 1)
	base.position = Vector3(isl.x, (floor_y + top_y) * 0.5, isl.y)
	base.scale = Vector3(2.5, (top_y - floor_y) * 0.5 + 0.55, 2.5)
	lib.add(g, base, "中島岩")  # ⚠ 不能叫「基石」：那是體檢的貼地關鍵字，會被判成建物跨水
	var cap := MeshInstance3D.new()
	cap.mesh = lib.blob_mesh(317, 0.35, 0.18)
	cap.material_override = lib.flat_mat("island_moss", Color(0.21, 0.30, 0.16), 0.95)
	cap.position = Vector3(isl.x, top_y + 0.05, isl.y)
	cap.scale = Vector3(1.8, 0.3, 1.8)
	lib.add(g, cap, "中島苔面")
	# 島上一棵小松 + 石灯籠（庭園的「景」）
	var pine := MeshInstance3D.new()
	pine.mesh = lib.tree_mesh("res://assets/models/tree_pine_a.glb")
	pine.position = Vector3(isl.x - 0.4, top_y + 0.1, isl.y - 0.3)
	pine.scale = Vector3(0.72, 0.66, 0.72)
	pine.rotation.y = _lm_rng.randf_range(0.0, TAU)
	lib.add(g, pine, "中島松")
	var stone_i := _lmat("stone")
	lib.cyl(g, "島灯籠竿", 0.10, 0.12, 0.8, stone_i, Vector3(isl.x + 0.9, top_y + 0.5, isl.y + 0.6), 8)
	lib.box(g, "島灯籠火袋", Vector3(0.34, 0.3, 0.34), stone_i, Vector3(isl.x + 0.9, top_y + 1.05, isl.y + 0.6))
	lib.box(g, "島灯籠笠", Vector3(0.52, 0.12, 0.52), stone_i, Vector3(isl.x + 0.9, top_y + 1.28, isl.y + 0.6))
	# 石橋：兩片微拱的石板，從西北岸跨到島 —— 玩家可以走上島
	var shore_pt := Vector2(pl.x - 4.2, pl.z + 3.4)
	var bdir := (isl - shore_pt).normalized()
	var blen := shore_pt.distance_to(isl) - 1.2
	for k3 in 2:
		var t0: float = 0.28 + 0.46 * float(k3)
		var bc := shore_pt + bdir * blen * t0
		var slab := lib.box(g, "石橋_%d" % k3, Vector3(1.35, 0.22, 2.3), _lmat("stone"),
			Vector3(bc.x, bank_ref - 0.10 + float(k3) * 0.05, bc.y))
		slab.rotation.y = atan2(bdir.x, bdir.y)
		slab.rotation.x = (0.06 if k3 == 0 else -0.06)
		var sb := StaticBody3D.new()
		slab.add_child(sb)
		sb.owner = _root
		var sh := CollisionShape3D.new()
		var bx2 := BoxShape3D.new()
		bx2.size = Vector3(1.35, 0.25, 2.3)
		sh.shape = bx2
		sb.add_child(sh)
		sh.owner = _root
	# 中島也要能站 —— 玩家走石橋上島
	var isb := StaticBody3D.new()
	isb.position = Vector3(isl.x, top_y - 0.1, isl.y)
	var ish := CollisionShape3D.new()
	var icy := CylinderShape3D.new()
	icy.radius = 1.9
	icy.height = 0.6
	ish.shape = icy
	isb.add_child(ish)
	lib.add(g, isb, "中島碰撞")
	ish.owner = _root
	# 沢飛石（橫過池面的踏石）拿掉了：這個池只有 9m，踏石橫過去佔滿水面 ——
	# 反效果。庭池要留**空的水面**。
	for i in 3:                                    # 池中的三尊石組
		var a2 := float(i) / 3.0 * TAU + 0.7
		var d2: float = shore * _lm_rng.randf_range(0.25, 0.5)
		var sc3 := _lm_rng.randf_range(0.6, 1.1)
		var rk3 := MeshInstance3D.new()
		rk3.mesh = lib.blob_mesh(i * 29 + 5, _lm_rng.randf_range(0.6, 0.9), _lm_rng.randf_range(0.20, 0.34))
		rk3.material_override = _lmat("cobble", -1)
		# 池中立石：從池底長上來，露出水面一截
		rk3.position = Vector3(pl.x + cos(a2) * d2,
			rock_y.call(wc.x + pl.x + cos(a2) * d2, wc.y + pl.z + sin(a2) * d2, -sc3 * 0.55),
			pl.z + sin(a2) * d2)
		# 不要拉高 1.7 倍 —— 那會把圓潤的岩石抽成尖刺。日式庭園的立石是
		# 「厚實、微微前傾」，不是尖塔。
		rk3.scale = Vector3(sc3 * 0.95, sc3 * 1.05, sc3 * 0.85)
		rk3.rotation.x = _lm_rng.randf_range(-0.18, 0.18)
		rk3.rotation.z = _lm_rng.randf_range(-0.18, 0.18)
		rk3.rotation.y = _lm_rng.randf_range(0.0, TAU)
		lib.add(g, rk3, "立石_%d" % i)
	# 沢渡り（踏石）
	for i in 4:
		lib.box(g, "踏石_%d" % i, Vector3(0.9, 0.35, 0.8), _lmat("stone"),
			pl + Vector3(-HIEDA_POND_R * 0.7 + float(i) * HIEDA_POND_R * 0.45, -0.35,
				HIEDA_POND_R * 0.35)).rotation.y = _lm_rng.randf_range(0.0, TAU)
	# 春日燈籠（池畔）：基礎→竿→中台→火袋（開窗）→笠→寶珠，
	# 一根連續的柱子撐上去，剪影一眼就認得（雪見型做出來像四腳桌）。
	# ⚠ 舊位置是池心 +(R+1.9, −2.2)＝池的東南岸。池搬到東側之後那個位置正好
	# 落在東牆的犬走り上（本地 x=19.3，牆內面才 17.9）。改到**西南岸、石橋橋頭
	# 旁**：從緣側往東看是「燈籠 → 水面 → 中島」的層次，而且燈籠替橋頭定位。
	var lz := pl + Vector3(-6.2, 0, 4.4)
	lz.y = height_at(wc.x + lz.x, wc.y + lz.z) - y0
	var stone_l := _lmat("stone", 1)
	lib.cyl(g, "燈籠基礎", 0.52, 0.62, 0.26, stone_l, lz + Vector3(0, 0.13, 0), 8)
	lib.cyl(g, "燈籠竿", 0.17, 0.20, 1.05, stone_l, lz + Vector3(0, 0.78, 0), 8)
	for r_i in 2:                                   # 竿上的節（春日燈籠的特徵）
		lib.cyl(g, "竿節_%d" % r_i, 0.23, 0.23, 0.07, stone_l,
			lz + Vector3(0, 0.52 + float(r_i) * 0.52, 0), 8)
	lib.cyl(g, "中台", 0.40, 0.30, 0.20, stone_l, lz + Vector3(0, 1.40, 0), 8)
	lib.cyl(g, "火袋底", 0.36, 0.36, 0.07, stone_l, lz + Vector3(0, 1.54, 0), 6)
	for c_i in 4:
		var ca := float(c_i) / 4.0 * TAU + 0.4
		lib.box(g, "火袋柱_%d" % c_i, Vector3(0.09, 0.46, 0.09), stone_l,
			lz + Vector3(cos(ca) * 0.29, 1.80, sin(ca) * 0.29))
	lib.cyl(g, "火袋頂", 0.38, 0.36, 0.07, stone_l, lz + Vector3(0, 2.06, 0), 6)
	var kasa := MeshInstance3D.new()
	var km := CylinderMesh.new()
	km.top_radius = 0.10
	km.bottom_radius = 0.72
	km.height = 0.34
	km.radial_segments = 6
	km.material = stone_l
	kasa.mesh = km
	kasa.position = lz + Vector3(0, 2.27, 0)
	lib.add(g, kasa, "燈籠笠")
	lib.cyl(g, "寶珠", 0.0, 0.13, 0.22, stone_l, lz + Vector3(0, 2.55, 0), 8)
	_lm_collide(g, Vector3(1.1, 2.7, 1.1), lz)
	_audit.append("稗田邸：庭池石組 %d 顆（護岸＋州濱＋立石）" % rk_i)
	_lm_hieda_planting(g, wc, y0)


# ══════════════ 稗田邸院內植栽（使用者定案：村院另做小型植栽）══════════════
#
# ⚠ 這**不是**把 `maps/hieda/gen/*.res` 搬過來 —— 那批做不到，實測：
#     hieda_garden.instances.json 的擺位跨度  95.4 × 107.0 m（136 實例）
#     hieda_blockout.glb 本體                75.6 × 110.5 m
#     村圖稗田邸保留區                        42.4 ×  45.6 m
#   線性差 ~2.3×；而且扣掉主屋／緣側／長廊／離れ／庭池之後，塀內 38×41m
#   真正能種東西的只剩 **593 ㎡（38%）**，面積差 ~17×。整套塞進來只會是一叢
#   互相穿模的樹牆。那批資產是照**獨立地圖**的尺度做的（markers 裡還有一個
#   target 待填的木戶 portal），留給它自己那張圖。
#
# 這裡的做法是**重用同樣那 10 種模組**，照村院的實際空地重排：
#   ・生垣沿築地塀內側（門洞、主屋、離れ 讓開）
#   ・紅葉在西南象限群聚 + 一株探出池面（庭池的借景）
#   ・松兩株框住庭池的視線，避開從表門到主屋的通道
#   ・灌木填在生垣與紅葉之間
#
# ⚠ 亂數用自己的 `_gard_rng`：稗田邸是 LANDMARKS 的第 3 座，動 `_lm_rng`
#   會把後面的鎮守之杜／市場／足洗邸整組位移。
const GARD_SEED := SEED + 6011

## 院內的障礙（本地座標，[cx, cz, w, d]）—— 跟 builder 的幾何對齊
const GARD_BLOCK := [
	[-5.0, -11.5, 26.5, 16.5],     # 主屋基壇
	[-5.0, -2.9, 24.0, 2.2],       # 緣側
	[-5.0, -0.7, 5.6, 3.6],        # 唐破風玄関前廊（五段石階＋向拝柱）
	[10.6, -6.0, 2.4, 12.0],       # 長廊
	[13.5, -14.5, 7.9, 7.9],       # 離れ屋根
	# 定案構圖的中軸與八字添景：參道是**筆直不斷開**的，兩側的添景也各有
	# 明表座標，灌木不能長進來擋住視線收束。
	[-5.0, 11.0, 8.0, 23.0],       # 參道（6m 鋪面 + 兩側各 1m）
	[-0.3, 14.0, 3.2, 3.2],        # 狛犬（右）
	[-9.7, 14.0, 3.2, 3.2],        # 狛犬（左）
	[1.5, 14.7, 2.6, 2.6],         # 門前燈籠（右）
	[-12.4, 16.4, 2.6, 2.6],       # 門前燈籠（左）
	[4.9, 18.1, 5.2, 5.2],         # 門前松（右）
	[-14.5, 18.4, 5.8, 5.8],       # 門前松（左）
	[4.8, 12.9, 2.4, 2.4],         # 池畔春日燈籠
]

func _lm_hieda_planting(g: Node3D, wc: Vector2, y0: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GARD_SEED
	var pond := Vector2(HIEDA_POND.x - wc.x, HIEDA_POND.y - wc.y)
	# 本地 (x,z) → 本地 Vector3（貼地形；院子被整平過但庭池挖了碗，
	# 而 g 的原點取的是**含碗底**的最低點，直接用 y=0 會整批埋進土裡 0.55m）
	var lp := func(lx: float, lz: float) -> Vector3:
		return Vector3(lx, height_at(wc.x + lx, wc.y + lz) - y0, lz)
	var free := func(lx: float, lz: float, need: float) -> bool:
		# 界限是**犬走り的內緣**（牆心 20/21.5 − 石垣腳 0.79 − 碎石帶 1.34），
		# 不是牆的內面 —— 種在碎石帶上的灌木讀起來像從水泥地裡長出來的。
		if absf(lx) > 17.87 - need or absf(lz) > 19.37 - need:
			return false
		for b in GARD_BLOCK:
			if absf(lx - float(b[0])) < float(b[2]) * 0.5 + need \
					and absf(lz - float(b[1])) < float(b[3]) * 0.5 + need:
				return false
		# 庭池（水面半徑 + 護岸石組那一圈）
		if Vector2(lx - pond.x, lz - pond.y).length() < HIEDA_POND_R * 1.05 + need:
			return false
		return true

	var batch := {}
	var put := func(mod: String, t: Transform3D) -> void:
		if not batch.has(mod):
			batch[mod] = [] as Array[Transform3D]
		batch[mod].append(t)

	# ── 生垣：沿格子塀內側（模組實測 2.63 長 × 1.19 高 × 1.24 深）──
	# 間距 2.5 < 模組長 2.63，接得起來才是「一道」生垣。
	# ⚠ 舊值 ±18.8 / 20.3 是貼著築地塀內面排的。換成格子塀之後牆腳外多了一圈
	# 1.68m 的犬走り，舊位置整排會種在碎石帶上 —— 全部往內退到犬走り內緣。
	# 南緣兩段還要讓開新的門洞與參道（中軸挪到 x=−5）。
	var HED := ["hieda_hedge_a", "hieda_hedge_b", "hieda_hedge_c"]
	var runs := [
		{"x": -17.1, "a": -1.0, "b": 16.5, "ax": false},    # 西牆（主屋基壇以南）
		{"x": 17.1, "a": -8.0, "b": 14.5, "ax": false},     # 東牆（離れ以南、庭池以東）
		{"z": 18.6, "a": -18.0, "b": -8.8, "ax": true},     # 南牆・門西
		{"z": 18.6, "a": 0.2, "b": 16.0, "ax": true},       # 南牆・門東
	]
	var n_hedge := 0
	for r in runs:
		var ax: bool = bool(r.ax)
		var t := float(r.a)
		while t <= float(r.b):
			var lx: float = t if ax else float(r.x)
			var lz: float = float(r.z) if ax else t
			t += 2.5
			var yaw: float = (0.0 if ax else PI * 0.5) + rng.randf_range(-0.04, 0.04)
			var s := rng.randf_range(0.94, 1.06)
			var b := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(s, rng.randf_range(0.9, 1.1), s))
			put.call(HED[n_hedge % 3], Transform3D(b, lp.call(lx, lz)))
			n_hedge += 1

	# ── 紅葉：兩株框住參道 + 西側群聚 + 一株探出池面 ──
	var MAP3 := ["hieda_maple_a", "hieda_maple_b", "hieda_maple_c"]
	# ⚠ 樹冠是隨機縮放又隨機轉向的，旋轉後的 AABB 半徑實測到 5.05m ——
	# 貼著保留區邊界會變成「這次剛好過、下次剛好不過」。收到 |x| ≤ 15.5、z ≤ 14.5。
	# ⚠ 舊的西南象限群聚（−13.5 / −9.5 / −5.5，z≈15）整組壓在新的前庭構圖上：
	# −5.5 那株直接站在參道正中（中軸挪到 x=−5），−9.5 與 −13.5 壓住左側的
	# 門前燈籠與松。前兩株改擺到獨立版**巨樹框景**的位置（軸線 ±4.9、z 7.9/9.0）
	# —— 那本來就是定案構圖裡收束視線的一對，村院沒有巨樹資產，用紅葉擔這角色。
	var maples := [Vector2(-0.1, 7.9), Vector2(-9.9, 9.0), Vector2(-15.5, 12.0),
		Vector2(-15.0, 6.0), Vector2(14.0, 14.2)]
	for i in maples.size():
		var p: Vector2 = maples[i]
		var s := rng.randf_range(0.76, 0.94)
		var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) \
			* Basis.from_scale(Vector3(s, s * rng.randf_range(0.94, 1.08), s))
		put.call(MAP3[i % 3], Transform3D(b, lp.call(p.x, p.y)))
		# 7m 高的樹要有幹的碰撞（跟鎮守之杜的神木同一條規矩）
		var body := StaticBody3D.new()
		body.position = lp.call(p.x, p.y)
		var sh := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 0.42
		cy.height = 5.0
		sh.shape = cy
		sh.position = Vector3(0, 2.5, 0)
		body.add_child(sh)
		lib.add(g, body, "紅葉幹_%d" % i)
		sh.owner = _root

	# ── 松：框住庭池的視線，讓開表門→主屋的通道 ──
	for p2 in [Vector2(4.0, 2.0), Vector2(-13.0, 1.5)]:
		var s2 := rng.randf_range(0.82, 0.96)
		put.call("hieda_pine_a", Transform3D(
			Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis.from_scale(Vector3(s2, s2, s2)),
			lp.call(p2.x, p2.y)))

	# ── 灌木：填在生垣與紅葉之間（模組本身 3~3.6m 寬、根部埋在原點以下）──
	# ⚠ 株數不寫死 12，改成「補到全院 51 株」（使用者定案：村院植栽總數不變）。
	# 生垣因為犬走り退縮、南緣讓開新門洞而少了幾株，缺口在這裡補回來 ——
	# 補的是**數量**，位置仍然照 free() 的規則挑。
	var BSH := ["hieda_bush_a", "hieda_bush_b", "hieda_bush_c"]
	var n_bush := 0
	var tries := 0
	var n_want: int = 51 - n_hedge - maples.size() - 2
	while n_bush < n_want and tries < 900:
		tries += 1
		var lx := rng.randf_range(-17.0, 17.0)
		var lz := rng.randf_range(-1.0, 18.0)
		if not free.call(lx, lz, 2.4):
			continue
		var near := false
		for p3 in maples:
			if Vector2(lx, lz).distance_to(p3) < 4.6:
				near = true
				break
		if near:
			continue
		var s3 := rng.randf_range(0.48, 0.68)
		put.call(BSH[n_bush % 3], Transform3D(
			Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis.from_scale(Vector3(s3, s3, s3)),
			lp.call(lx, lz)))
		n_bush += 1

	var total := 0
	var mods: Array = batch.keys()
	mods.sort()
	for m in mods:
		var list: Array[Transform3D] = batch[m]
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(
			lib.prop_mesh("res://assets/models/%s.glb" % m), list, [],
			OUT_DIR + "gen/mm_%s.res" % m)
		mmi.material_override = lib.foliage_vc_mat()
		# 葉子是薄片，投影要 double-sided 才不會半邊沒影子
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		lib.add(g, mmi, "MM_%s" % m)
		total += list.size()
	_audit.append("稗田邸院內植栽：生垣 %d、紅葉 %d、松 2、灌木 %d —— 共 %d 株 / %d draw call"
		% [n_hedge, maples.size(), n_bush, total, mods.size()])


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
const STREET_SEED := SEED + 5231

var _street_rng := RandomNumberGenerator.new()

## 門樓：擺在 portal 上，玩家一落地就是**穿門進村**。
## 舊值 (0,-215)/(-172,92) 是舊圖的村界，新圖的 portal 在 (0,-174)/(-132,100)。
const GATES := [
	# 北門：trail 落點 (0,-174) 往村內 6m。本通在這裡寬 8m，門洞 9.5m。
	{"n": "北門", "x": 0.0, "z": -168.0, "yaw": 0.0},
	# 西南門：kourindou 落點 (-132,100) 的**西側**（= 玩家背後就是林道）。
	# 壓在西南門引道（z=92，沿 x 走）上 —— 所以要轉 90°，不然門是順著路
	# 站的，跨不住路。舊圖那條引道是斜的（yaw 0.42），新圖是正的。
	{"n": "西南門", "x": -150.0, "z": 92.0, "yaw": PI * 0.5},
]

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
const GUTTER_SEG := 3.0
const GUTTER_COMMERCE := 0.45     # 石溝是町方的東西，村緣的排水是土溝

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
				if _commerce(p) < GUTTER_COMMERCE:
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
	var slab := lib.pbr("溝蓋石", "stone_flag", 0.30, Color(0.56, 0.57, 0.55))
	var g := lib.add(_root, Node3D.new(), "石溝")
	var parts := [
		{"size": Vector3(0.22, 0.5, GUTTER_SEG), "list": walls, "mat": stone, "n": "溝壁"},
		{"size": Vector3(0.7, 0.12, GUTTER_SEG), "list": floors, "mat": stone, "n": "溝底"},
		{"size": Vector3(1.15, 0.14, 1.6), "list": lids, "mat": slab, "n": "溝蓋"},
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
const LAMP_MAX := 44              # OmniLight3D 有成本，上限擺明寫死

func _build_lamps() -> void:
	var iron := lib.flat_mat("iron", Color(0.16, 0.16, 0.18), 0.6)
	var glow := lib.flat_mat("lamp_glow", Color(1.0, 0.85, 0.55), 0.3, Color(1.0, 0.75, 0.4))
	var g := lib.add(_root, Node3D.new(), "街燈")
	# 町家 OBB 的空間索引（照 _build_grass 的做法）
	var hgrid := {}
	for e in _dump:
		var r := _obb_of(e)
		var c: Vector2 = r[0]
		var rad: float = maxf(r[3], r[4]) + 3.0
		for i in range(int(floor((c.x - rad) / 24.0)), int(floor((c.x + rad) / 24.0)) + 1):
			for j in range(int(floor((c.y - rad) / 24.0)), int(floor((c.y + rad) / 24.0)) + 1):
				var k := Vector2i(i, j)
				if not hgrid.has(k):
					hgrid[k] = []
				hgrid[k].append(r)
	var in_house := func(p: Vector2, pad: float) -> bool:
		var key := Vector2i(int(floor(p.x / 24.0)), int(floor(p.y / 24.0)))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var k := Vector2i(key.x + dx, key.y + dz)
				if not hgrid.has(k):
					continue
				for r in hgrid[k]:
					var d: Vector2 = p - r[0]
					if absf(d.dot(r[1])) < r[3] + pad and absf(d.dot(r[2])) < r[4] + pad:
						return true
		return false

	var placed: Array[Vector2] = []
	var side_flip := false
	for r in _roads:
		var pts: Array = r.pts
		var half: float = float(r.w) * 0.5
		for k in range(pts.size() - 1):
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			var seg := b - a
			var ln := seg.length()
			if ln < 1.0:
				continue
			var dir := seg / ln
			var nrm := dir.orthogonal()
			var s := 0.0
			while s < ln:
				var base: Vector2 = a + dir * s
				# 間距吃商業梯度：村心 17m、村緣 48m
				var cm := _commerce(base)
				var step: float = lerpf(48.0, 17.0, clampf(cm / 0.75, 0.0, 1.0))
				s += step
				if cm < 0.20:
					continue
				side_flip = not side_flip
				var p: Vector2 = base + nrm * (1.0 if side_flip else -1.0) * (half + 1.3)
				if _pt_reserved(p, 1.0) or in_house.call(p, 0.8):
					continue
				if _river_dist_xy(p.x, p.y) < RIVER_HALF + 1.5:
					continue
				var too_near := false
				for q in placed:
					if q.distance_to(p) < 12.0:
						too_near = true
						break
				if too_near:
					continue
				placed.append(p)
	# 太多的話按商業權重砍尾巴（村心的先留）
	if placed.size() > LAMP_MAX:
		placed.sort_custom(func(u, v): return _commerce(u) > _commerce(v))
		placed.resize(LAMP_MAX)
	for i in placed.size():
		var p: Vector2 = placed[i]
		var lamp := Node3D.new()
		lamp.position = Vector3(p.x, height_at(p.x, p.y), p.y)
		lib.add(g, lamp, "街燈_%d" % i)
		lib.cyl(lamp, "柱", 0.055, 0.075, 3.2, iron, Vector3(0, 1.6, 0), 8)
		lib.box(lamp, "燈頭", Vector3(0.38, 0.46, 0.38), glow, Vector3(0, 3.35, 0))
		lib.box(lamp, "燈帽", Vector3(0.52, 0.1, 0.52), iron, Vector3(0, 3.63, 0))
		var li := OmniLight3D.new()
		li.position = Vector3(0, 3.3, 0)
		li.light_color = Color(1.0, 0.78, 0.5)
		li.light_energy = 1.2
		li.omni_range = 9.0
		li.shadow_enabled = false
		# ⚠ 燈本體 _perf_pass 會設距離淡出，但**燈光不是 MeshInstance3D**，
		# 不會被掃到。44 盞全程開著的話遠景白付一筆 —— 自己設距離淡出。
		li.distance_fade_enabled = true
		li.distance_fade_begin = 55.0
		li.distance_fade_length = 15.0
		lib.add(lamp, li, "光")
	_audit.append("街燈 %d 盞（間距吃商業梯度：村心 17m、村緣 48m）" % placed.size())


# ══════════════ 水邊 MIGRATE：動物／水生植物 ══════════════
#
# 舊 gen_village 的 `_build_fauna` / `_build_water_plants` 綁的是**水路**
# （CANAL，Stage 1 已移除）。新圖只有河，所以路徑、水面高度、生長帶全部改綁
# `_river()`。蘆葦已經在草層（`_reed_along_river`）裡了，這裡只補睡蓮與荷。
#
# 水面高度只有一個真相來源：`lib.river_water(..., RIVER_DEPTH * 0.20, bank_h)`
# → 水面 = bank_h − 0.5。舊碼寫的是 `sink * 0.35`（水路的係數），照抄會讓
# 全部的鴨與睡蓮浮高 0.375m。

const FAUNA_Z := Vector2(-120.0, 160.0)     # 生物只放在**看得到**的村內段

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
		# ⚠ 位置隨前庭替換一起挪：舊點 (−84, −167) 在主屋正面外 0.8m，那裡
		# 現在是唐破風玄関的五段石階**底下**（緣側往外 2.2m 才是階梯口）。
		# 新點放在**石階腳下**、參道的終點上 —— 定案構圖第 3 條的「參道一路連到
		# 唐破風石階腳下」，走到底就是入口，動線與構圖同一條線。
		# 世界座標 = 院落中心 (−78, −164) + 本地 (HIEDA_AXIS, +0.6)。
		# ⚠ 這個 portal **刻意不進 connections**：connections 是世界圖層級
		# 的連通表（跟 mapRegistry.js 對齊），建築內部不是世界圖上的一格
		# —— 「不進 mapRegistry」的裁決串接後仍適用，樓層連結只活在
		# meta 的 portal 層。
		{"x": -83.0, "y": snappedf(height_at(-83, -163.4), 0.01), "z": -163.4,
		 "target": "hieda1f"},
	]
	var meta := {
		"id": MAP_ID,
		"note": "人間之里（街區重設計版，gen_town.gd 產出）。整合 Stage 2 起"
			+ "這支取代了 gen_village.gd 的佈局；地標內容／草層／動物等"
			+ "MIGRATE 項目逐步搬入中。gen_village.gd 不可再執行。",
		"playSize": [460, 460],
		"safe": true,
		# 跟 src/world/mapRegistry.js 的 village 條目對齊（myouren/lake 是
		# **規劃中**的連線，還沒有對應 portal；lake 已有保留觸發區）。
		# 兩份登記表要說同一件事，不然整合完還是有兩個真相來源。
		"connections": ["trail", "kourindou", "myouren", "lake"],
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
	var out := {"note": "人間之里擺位表（gen_town.gd 產出，驗證腳本用）",
		"river": [], "instances": _dump, "density": _ddump}
	for p in _river():
		out["river"].append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
	var f := FileAccess.open("res://data/%s.instances.json" % MAP_ID, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	print("wrote data/%s.instances.json（%d 實例）" % [MAP_ID, _dump.size()])
