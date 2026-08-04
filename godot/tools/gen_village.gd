# 人間之里・場景產生器 v2（設計書：docs/village-design.md）
#
#   godot --headless --path godot --script tools/gen_village.gd
#
# 骨架依據：thwiki「幻想鄉柱狀地圖」的人里俯瞰圖（使用者提供）——
# 里不是「街道兩側排房子」，而是**一格一格的圍牆街區**：
# 土塀圍出街區，長條建築沿街區周邊排（屋頂連成一片），中間是內庭與樹，
# 街區之間是寬闊的砂土大街。1.2 條主街 = 本通（南北貫穿）+ 橫町（東西中段）。
#
# 官方設施（THBWiki）：寺子屋、稗田邸（房舍＋長廊＋庭院水池楓樹）、
# 鈴奈庵（貸本屋）、鵜吞亭、足洗邸、龍神像。
# 傳送點沿用 meta.json：北門 (0,-174) → 獸道、西南門 (-132,100) → 香霖堂。
extends SceneTree

const Lib := preload("res://tools/gen_lib.gd")

const OUT_DIR := "res://maps/village/"
const HALF := 300.0
const PLAZA := Vector2(0.0, 30.0)
const CORE := 196.0

# ── 街道格：南北 x = -104/-52/0/52/104、東西 z = -135/-80/-25/30/85/140 ──
const ST_X := [-156.0, -104.0, -52.0, 0.0, 52.0, 104.0, 156.0]
const ST_Z := [-190.0, -135.0, -80.0, -25.0, 30.0, 85.0, 140.0, 195.0]
const BLOCK_X := [-130.0, -78.0, -26.0, 26.0, 78.0, 130.0]   # 街區中心
const BLOCK_Z := [-162.0, -107.0, -52.0, 2.0, 57.0, 112.0, 167.0]
const BLOCK_W := 42.0
const BLOCK_D := 45.0

# 街寬（使用者定案：主街 8m、巷道 3~4m；牆到牆剩下的空地用「街緣」填滿＝方案 B）。
# ⚠ 這裡的 width 不是看得到的鋪面寬 —— 遮罩還會往外淡出 PATH_FADE，
# 實際鋪面 ≈ width + 2*PATH_FADE。v13 的淡出是 2.0，所以 11m 的本通
# 看起來有 15m 寬，整條街像機場跑道。
const PATH_FADE := 0.9
const PATH_SEGMENTS := [
	# 本通（主街・南北貫穿，最寬）
	{ "width": 8.0, "pts": [[0.0, -240.0], [0.0, -120.0], [0.0, 30.0], [0.0, 160.0], [0.0, 250.0]] },
	# 橫町（0.2 條・東西中段，東端過橋）
	{ "width": 7.0, "pts": [[-190.0, 30.0], [-104.0, 30.0], [0.0, 30.0], [104.0, 30.0], [190.0, 30.0], [232.0, 30.0]] },
	# 其餘南北街（ST_X 除了本通）
	{ "width": 4.5, "pts": [[-156.0, -190.0], [-156.0, 0.0], [-156.0, 195.0]] },
	{ "width": 4.5, "pts": [[-104.0, -190.0], [-104.0, 0.0], [-104.0, 195.0]] },
	{ "width": 4.5, "pts": [[-52.0, -190.0], [-52.0, 0.0], [-52.0, 195.0]] },
	{ "width": 4.5, "pts": [[52.0, -190.0], [52.0, 0.0], [52.0, 195.0]] },
	{ "width": 4.5, "pts": [[104.0, -190.0], [104.0, 0.0], [104.0, 195.0]] },
	{ "width": 4.5, "pts": [[156.0, -190.0], [156.0, 0.0], [156.0, 195.0]] },
	# 其餘東西街
	{ "width": 4.5, "pts": [[-182.0, -190.0], [0.0, -190.0], [182.0, -190.0]] },
	{ "width": 4.5, "pts": [[-182.0, -135.0], [0.0, -135.0], [182.0, -135.0]] },
	{ "width": 4.5, "pts": [[-182.0, -80.0], [0.0, -80.0], [182.0, -80.0]] },
	{ "width": 4.5, "pts": [[-182.0, -25.0], [0.0, -25.0], [182.0, -25.0]] },
	{ "width": 5.0, "pts": [[-182.0, 85.0], [0.0, 85.0], [182.0, 85.0]] },
	{ "width": 4.5, "pts": [[-182.0, 140.0], [0.0, 140.0], [182.0, 140.0]] },
	{ "width": 4.5, "pts": [[-182.0, 195.0], [0.0, 195.0], [182.0, 195.0]] },
	# 西南門引道（香霖堂）
	{ "width": 4.0, "pts": [[-132.0, 100.0], [-145.0, 98.0], [-156.0, 94.0]] },
]
# ── 河（東側，橫町東端石橋跨過；北端往圖外＝河畔道接口） ──
const RIVER := [[268.0, -300.0], [250.0, -190.0], [232.0, -80.0], [222.0, -10.0],
	[220.0, 30.0], [226.0, 100.0], [240.0, 200.0], [256.0, 300.0]]
# ── 水路（貫穿村里的水渠，多座小橋橫過 —— 柱狀地圖裡那些白色帶狀物） ──
## 水路是**一條直線**（使用者：「水道直直的就好不要轉彎」）。
## v10 為了接河把東端拐了個彎，那個折角在編輯器裡很明顯。
## 改成固定 z=85 一路往東拉到 x=236 —— 大河在 z=85 附近的中心線約在
## x=225，所以直直拉過去自然就接上了，不用轉彎。
# ⚠ 東端**不能**畫到 236 —— 河在 z=85 這一段的中心在 x≈224、半寬 8，
# 也就是佔到 x=232。水路畫到 236 等於把水路的水面直接疊在河的水面上，
# 兩張半透明面互穿，遠看是一條詭異的斜向色帶（使用者：「水道請改善」）。
# 收在 206，剩下那段用水門（落水口）洩到河裡。
const CANAL := [[-300.0, 85.0], [-150.0, 85.0], [0.0, 85.0], [150.0, 85.0], [206.0, 85.0]]
const CANAL_OUTLET := Vector2(206.0, 85.0)
const CANAL_HALF := 4.6      # 參考圖的水路很寬，不是小水溝
const CANAL_DEPTH := 2.0
const CANAL_BRIDGES := [-156.0, -104.0, -52.0, 0.0, 52.0, 104.0, 156.0]
const RIVER_HALF := 8.0
const RIVER_DEPTH := 2.8
const BRIDGE := Vector2(221.0, 30.0)
# ── 池塘（兩種：稗田邸的石組庭池 + 村西的自然池） ──
const GARDEN_POND := Vector2(-80.0, 10.0)      # 稗田邸內庭（block -78,2 的南側）
const GARDEN_POND_R := 6.4
const GARDEN_POND_DEPTH := 1.7                 # 挖多深（碗底）
const GARDEN_POND_SINK := 0.55                 # 水面比岸低多少
## ⚠ 池心離最近街緣必須 > R*1.35 + 餘裕，否則開挖會吃到路面。
## v9 放在 (-140,150)：離街緣只有 6.5m，而開挖半徑是 20m —— 池塘直接壓在路上。
const NATURE_POND := Vector2(-202.0, 168.0)    # 村西北外緣的自然池
const NATURE_POND_R := 15.0
const NATURE_POND_DEPTH := 2.4
const NATURE_POND_SINK := 0.75

## 街區用途（依 THBWiki 設施清單配置）
const BLOCK_KIND := {
	"-26,-52": "terakoya", "26,-52": "suzunaan",
	"-78,2": "hieda", "26,2": "unomitei",
	"-26,57": "market", "26,57": "tower",
	"-26,2": "grove",                      # 鎮守之杜：整個街區留空給神木
	"26,112": "ashiarai",
}

var lib: Lib
var _nh: FastNoiseLite
var _n2: FastNoiseLite
var _rects: Array = []
## 門面清單（Frontage）：每筆 { pos: Vector2 世界座標, dir: Vector2 朝外方向,
## shop: bool, width: float, ground: float }。地板裝飾靠這份清單對齊門口。
var _frontages: Array = []

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _path_info(x: float, z: float) -> Array:
	var p := Vector2(x, z)
	var edge := INF
	var mask := 0.0
	for seg in PATH_SEGMENTS:
		var pts: Array = seg.pts
		var w: float = seg.width
		for k in pts.size() - 1:
			var d := _seg_dist(p, Vector2(pts[k][0], pts[k][1]), Vector2(pts[k + 1][0], pts[k + 1][1]))
			edge = minf(edge, maxf(0.0, d - w * 0.5))
			mask = maxf(mask, 1.0 - smoothstep(w * 0.5 - 0.5, w * 0.5 + PATH_FADE, d))
	return [edge, mask]

func _field_w(x: float, z: float) -> float:
	var r := Vector2(x, z - PLAZA.y).length()
	if r < CORE + 10.0 or r > CORE + 62.0:
		return 0.0
	if lib.poly_dist(RIVER, x, z) < RIVER_HALF * 2.4:
		return 0.0
	if _path_info(x, z)[0] < 3.0:
		return 0.0
	var row := fmod(absf(z * 0.7 + x * 0.3), 8.0)
	return 0.9 if row > 1.6 else 0.1

## 岸邊地面高度（不含任何下切）—— 水面高度一定要用這個算。
## v3 的 bug：拿含下切的 height_at 去減 sink，水面沉到河床底下，
## 河跟水路的水整個埋進地裡（所以「看不到橋」其實是看不到水）。
func bank_h(x: float, z: float) -> float:
	var roll := _nh.get_noise_2d(x, z) * 2.4
	var town := smoothstep(CORE - 20.0, CORE + 70.0, Vector2(x, z - PLAZA.y).length())
	return roll * (0.06 + 0.94 * town) + sin(x * 0.46 + z * 0.33) * 0.04

## 地勢：里在整過地的台地上；河、水路、兩個池塘都往下挖
func height_at(x: float, z: float) -> float:
	var h := bank_h(x, z)
	h += lib.river_carve(RIVER, RIVER_HALF, RIVER_DEPTH, x, z)
	h += lib.river_carve(CANAL, CANAL_HALF, CANAL_DEPTH, x, z)
	h += lib.pond_carve(GARDEN_POND.x, GARDEN_POND.y, GARDEN_POND_R, GARDEN_POND_DEPTH, x, z)
	return h + lib.pond_carve(NATURE_POND.x, NATURE_POND.y, NATURE_POND_R, NATURE_POND_DEPTH, x, z, 0.22)

func mask_at(x: float, z: float) -> Color:
	var info := _path_info(x, z)
	var g2 := clampf(_n2.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var rd := lib.poly_dist(RIVER, x, z)
	var shore := 1.0 - smoothstep(RIVER_HALF * 0.7, RIVER_HALF * 1.9, rd)
	var cd := lib.poly_dist(CANAL, x, z)
	shore = maxf(shore, 1.0 - smoothstep(CANAL_HALF * 0.8, CANAL_HALF * 2.6, cd))
	# 地面定調（使用者選《求聞編年史》）：街道鋪石板、街廓之間是綠草地。
	# 不再把整個里塗成砂土色。
	var path_w: float = maxf(info[1], shore)
	# 在（村緣）的路不鋪石板 —— 石板一路鋪到田邊很出戲。
	# 把石板的權重收掉、同樣的量補到土的通道上，路還在、材質換掉。
	# 參考圖（幻走スカイドリフト＋官方美術）四張的地面**全部是夯土**，
	# 不是石板。石板只留給村心廣場周邊（參道與店前的鋪面另外做）。
	var zr := Vector2(x, z - PLAZA.y).length()
	var stone_k := 1.0 - smoothstep(10.0, 38.0, zr)
	var lane_dirt: float = path_w * (1.0 - stone_k)
	path_w *= stone_k
	var soil := maxf(_field_w(x, z), g2 * 0.12)
	var macro := clampf(_nh.get_noise_2d(x * 0.4, z * 0.4) * 0.5 + 0.5, 0.0, 1.0)
	return Color(path_w, soil, macro, maxf(_court_w(x, z), lane_dirt))

## 街廓內側（土塀圍起來的院子）＝踏み固めた土。
## 天天有人走的地方不長草 —— 之前整個里的院子都是翠綠草皮，
## 從空中看像高爾夫球場，不像聚落。牆腳留一圈草（雜草本來就從那裡長）。
const COURT_EARTH_IN := 0.66      # 內側到這個比例都是全土
const COURT_EARTH_OUT := 0.99     # 到塀邊淡出成草
## 這幾種街區不鋪土：神木林（苔と下草）、稗田邸（庭園）
const COURT_GREEN := ["grove", "hieda"]
func _court_w(x: float, z: float) -> float:
	var best := 0.0
	for bx in BLOCK_X:
		for bz in BLOCK_Z:
			var kind: String = BLOCK_KIND.get("%d,%d" % [int(bx), int(bz)], "compound")
			if kind in COURT_GREEN:
				continue
			var dx: float = absf(x - bx) / (BLOCK_W * 0.5)
			var dz: float = absf(z - bz) / (BLOCK_D * 0.5)
			var d: float = maxf(dx, dz)
			best = maxf(best, 1.0 - smoothstep(COURT_EARTH_IN, COURT_EARTH_OUT, d))
	return best

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + "gen"))
	_nh = FastNoiseLite.new()
	_nh.frequency = 0.011
	_nh.seed = 500
	_n2 = FastNoiseLite.new()
	_n2.frequency = 0.03
	_n2.seed = 77

	var root := Node3D.new()
	root.name = "Village"
	root.set_meta("own_colliders", true)
	lib = Lib.new()
	lib.setup(root, 20260810)

	# 街道鋪石板；草地壓黃補綠（使用者回報「村內草地偏黃」）
	lib.terrain(OUT_DIR, HALF, 221, height_at, mask_at, "cobble", Color(0.60, 0.94, 0.55),
		"terrain_path", Color(0.80, 0.75, 0.66))
	lib.boundary(HALF - 2.0)
	# 水面要比開挖**窄**：開挖是有坡度的，水面照全寬鋪會爬到岸上去
	lib.river_water(OUT_DIR, RIVER, RIVER_HALF * 0.86, RIVER_DEPTH * 0.35, bank_h)
	# 水色照參考圖：飽和的藍綠，不是淡青
	var canal_w := lib.river_water(OUT_DIR, CANAL, CANAL_HALF * 0.84, CANAL_DEPTH * 0.35, bank_h, "Canal")
	var cm: ShaderMaterial = canal_w.material_override
	cm.set_shader_parameter("deep_color", Color(0.06, 0.24, 0.32))
	cm.set_shader_parameter("shallow_color", Color(0.16, 0.44, 0.50))
	cm.set_shader_parameter("bank_scale", 0.55)
	lib.pond_water(OUT_DIR, GARDEN_POND.x, GARDEN_POND.y, GARDEN_POND_R, GARDEN_POND_SINK, bank_h,
		"庭池", 0.0, 4, 28, GARDEN_POND_DEPTH)
	lib.pond_water(OUT_DIR, NATURE_POND.x, NATURE_POND.y, NATURE_POND_R, NATURE_POND_SINK, bank_h,
		"自然池", 0.22, 4, 28, NATURE_POND_DEPTH)
	_assert_water_clear_of_streets()
	_build_blocks()
	_build_bridge()
	_build_canal_bridges()
	_build_canal_banks()
	_build_nature_pond()
	_build_fauna()
	_build_floor_decor()
	_build_props()
	_build_water_plants()
	_build_clutter()
	_build_gates()
	_build_lamps()
	_build_trees()
	_build_grass()
	lib.vista(OUT_DIR, HALF, 900.0, height_at, [
		{ "x": -520.0, "z": -560.0, "h": 140.0, "r": 240.0 },
		{ "x": 480.0, "z": -420.0, "h": 55.0, "r": 180.0 },
	], "res://assets/models/tree_round_b.glb", 420)
	_build_env()

	# ⚠ _merge_decor() 目前**沒有啟用**。
	# 它要解的問題是真的：全村 15,625 個 MeshInstance3D = 15,625 次 draw call
	# （使用者：「我電腦變卡了」）。但這一版跑不完 —— 在 GDScript 裡逐頂點
	# 重建上萬個 mesh 太慢，加了尺寸護欄與 null 防護之後仍然會撞到超時。
	# 下一輪要改的方向：
	#   ・不要用 SurfaceTool（每個頂點一次函式呼叫），改直接組 PackedArray
	#   ・或者根本不要在產生器裡合併，改成獨立的一支後處理工具
	# 這一版先靠「砍掉重複幾何」把 15,625 降到 11,825，其餘留給下一輪。
	# var mg := _merge_decor(root)

	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, OUT_DIR + "village.tscn")
	print("saved village.tscn err=", err)
	quit()

# ═══════════════════════════════════ 工具 ═══════════════════════════════
# 佔位索引用空間網格：建築變多之後，每次都掃全表是 O(n²)，
# 樹木散佈那圈迴圈會讓產生器跑到超時。
const CELL := 16.0
var _grid := {}

func _cells(cx: float, cz: float, hw: float, hd: float) -> Array:
	var out: Array[Vector2i] = []
	var i0 := int(floor((cx - hw) / CELL))
	var i1 := int(floor((cx + hw) / CELL))
	var j0 := int(floor((cz - hd) / CELL))
	var j1 := int(floor((cz + hd) / CELL))
	for i in range(i0, i1 + 1):
		for j in range(j0, j1 + 1):
			out.append(Vector2i(i, j))
	return out

## 回傳這塊地在 _rects 裡的索引 —— 店前鋪面要能「忽略自己那棟房子」
## tag 只給診斷用（門面被誰擋住、哪一種地權互卡）——沒有它就只知道「被擋了」，
## 得再寫一次臨時腳本去撈，這種事發生過太多次了。
func _claim(cx: float, cz: float, w: float, d: float, tag := "") -> int:
	var idx := _rects.size()
	_rects.append([cx, cz, w, d, tag])
	for c in _cells(cx, cz, w * 0.5, d * 0.5):
		if not _grid.has(c):
			_grid[c] = []
		_grid[c].append(idx)
	return idx

## 店前鋪面專用的空地判定：
## 不能用 _free —— 它會擋掉「離街 0.6m 內」與「壓到自家地權」，
## 而鋪面本來就該貼著街緣、就該疊在自家門口那塊地上。
func _free_for_apron(cx: float, cz: float, w: float, d: float, own: int) -> bool:
	return _blocker_at(cx, cz, w, d, own) == ""

## 回傳擋路的那塊地權的 tag（沒被擋就回空字串）
func _blocker_at(cx: float, cz: float, w: float, d: float, own: int) -> String:
	var hw := w * 0.5
	var hd := d * 0.5
	for c in _cells(cx, cz, hw, hd):
		if not _grid.has(c):
			continue
		for idx in _grid[c]:
			if idx == own:
				continue
			var r: Array = _rects[idx]
			if absf(cx - r[0]) < (hw + r[2] * 0.5) and absf(cz - r[1]) < (hd + r[3] * 0.5):
				return "%s@(%.0f,%.0f)" % [("?" if r.size() < 5 else r[4]), r[0], r[1]]
	return ""

func _free(cx: float, cz: float, w: float, d: float, margin := 0.6) -> bool:
	var hw := w * 0.5 + margin
	var hd := d * 0.5 + margin
	# 邊中點也要取樣 —— 只測四角的話，長屋的側邊會壓在街上（v2 的 bug）
	for c in [[cx - hw, cz - hd], [cx + hw, cz - hd], [cx - hw, cz + hd], [cx + hw, cz + hd],
			[cx, cz], [cx - hw, cz], [cx + hw, cz], [cx, cz - hd], [cx, cz + hd]]:
		if _path_info(c[0], c[1])[0] < 0.6:
			return false
	if lib.poly_dist(RIVER, cx, cz) < RIVER_HALF * 1.9:
		return false
	if lib.poly_dist(CANAL, cx, cz) < CANAL_HALF * 2.4 + maxf(hw, hd) * 0.5:
		return false
	# 池塘：v7 的 _free 只認得河與水路，於是自然池邊蓋了一棟陷進碗裡 2.8m 的長屋。
	# 池的開挖半徑是 R*1.35，再留一點岸。
	if Vector2(cx - GARDEN_POND.x, cz - GARDEN_POND.y).length() < GARDEN_POND_R * 1.45 + maxf(hw, hd):
		return false
	if Vector2(cx - NATURE_POND.x, cz - NATURE_POND.y).length() < NATURE_POND_R * 1.45 + maxf(hw, hd):
		return false
	var seen := {}
	for c in _cells(cx, cz, hw, hd):
		if not _grid.has(c):
			continue
		var bucket: Array = _grid[c]
		for idx in bucket:
			if seen.has(idx):
				continue
			seen[idx] = true
			var r: Array = _rects[idx]
			if absf(cx - r[0]) < (hw + r[2] * 0.5) and absf(cz - r[1]) < (hd + r[3] * 0.5):
				return false
	return true

func _collide(g: Node3D, size: Vector3, off := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	g.add_child(body)
	body.owner = lib.root
	var shape := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	shape.shape = bx
	shape.position = off + Vector3(0, size.y * 0.5, 0)
	body.add_child(shape)
	shape.owner = lib.root

## 每種建材的**色調變體**。使用者回報「不要只有一種材質的顏色模組」——
## 以前 _mat() 每個 key 只回傳一個共用材質實例，全村的灰泥牆是同一個顏色，
## 遠看就是一片同色的積木。真實聚落每戶的灰泥、瓦、木頭都風化得不一樣。
const MAT_TONES := {
	# 真壁的填充要**亮**，木框才跳得出來 —— 參考圖的白灰接近純白。
	# 舊的 0.84/0.92 配上曬過的木框，整棟是一團褐色。
	"plaster": [Color(1.30, 1.28, 1.22), Color(1.16, 1.13, 1.06),
		Color(1.05, 1.04, 1.00), Color(1.22, 1.17, 1.09)],
	"kawara": [Color(0.80, 0.84, 0.92), Color(0.66, 0.70, 0.78),
		Color(0.74, 0.76, 0.80), Color(0.58, 0.62, 0.70)],
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

## v = 色調變體編號。省略就隨機挑一個 —— 一棟房子要自己記住 v，
## 不然同一棟的牆跟腰板會是不同色。
func _mat(key: String, v := -1) -> StandardMaterial3D:
	if not MAT_SET.has(key):
		key = "plaster"
	var tones: Array = MAT_TONES[key]
	if v < 0:
		v = int(lib.rand() * float(tones.size()))
	v = v % tones.size()
	var spec: Array = MAT_SET[key]
	return lib.pbr("%s_%d" % [key, v], String(spec[0]), float(spec[1]), tones[v])

## 擺建物時該看到的地面高度：實際地面，但水面以下不算數。
## 兩個坑各踩過一次：
##   拿 height_at → 稗田邸的院子裡有庭池，最低點是池底，整棟宅子沉 1.7m；
##   拿 bank_h（完全不開挖）→ 水路旁的土塀量到未開挖的岸高，整段浮 0.9m。
## 正解是「河床不算、但岸坡算」——水裡的取樣點一律當成水面高度。
func _ground_sample(x: float, z: float) -> float:
	var y := height_at(x, z)
	var surf := -INF
	var rd := lib.poly_dist(RIVER, x, z)
	if rd < RIVER_HALF:
		surf = maxf(surf, bank_h(x, z) - RIVER_DEPTH * 0.35)
	var cd := lib.poly_dist(CANAL, x, z)
	if cd < CANAL_HALF:
		surf = maxf(surf, bank_h(x, z) - CANAL_DEPTH * 0.35)
	if Vector2(x - GARDEN_POND.x, z - GARDEN_POND.y).length() < GARDEN_POND_R:
		surf = maxf(surf, bank_h(x, z) - GARDEN_POND_SINK)
	if Vector2(x - NATURE_POND.x, z - NATURE_POND.y).length() < NATURE_POND_R:
		surf = maxf(surf, bank_h(x, z) - NATURE_POND_SINK)
	return maxf(y, surf)

## 這個座標在不在水裡（池／河／水路）。
## 使用者拍到「池塘水裡有灰色方塊」—— 是店前的飛石。飛石是照玄關朝向
## 往外排的，稗田邸的玄關正對著庭池，於是三塊石頭排進水裡浮在水面上。
func _in_water(x: float, z: float, pad := 0.0) -> bool:
	# ⚠ 要用**開挖半徑**（R * 1.35）不是 R —— 池子挖出來的碗比 R 大一圈，
	# 拿 R 判定的話碗緣那一圈仍然會被當成陸地，石板照樣鋪進水裡。
	if Vector2(x - GARDEN_POND.x, z - GARDEN_POND.y).length() < GARDEN_POND_R * 1.45 + pad:
		return true
	if Vector2(x - NATURE_POND.x, z - NATURE_POND.y).length() < NATURE_POND_R * 1.45 + pad:
		return true
	if lib.poly_dist(RIVER, x, z) < RIVER_HALF + pad:
		return true
	return lib.poly_dist(CANAL, x, z) < CANAL_HALF + pad

## 建物腳下的地面高度：取涵蓋範圍內最低點（只取中心的話，一端會浮空）
## 回傳 [最低高度, 高差] —— 高差交給基石往下埋掉。
func _ground_under(cx: float, cz: float, w: float, d: float) -> Array:
	var lo := INF
	var hi := -INF
	# 取樣密度跟尺寸走：約每 4m 一點。3×3 對 40m 長的土塀來說太稀，
	# 中段有個坑就整段浮空（體檢抓到的 塀全_2 就是這樣來的）。
	var nx := clampi(int(ceil(w / 4.0)) + 1, 3, 9)
	var nz := clampi(int(ceil(d / 4.0)) + 1, 3, 9)
	for i in nx:
		for j in nz:
			var ox := float(i) / float(nx - 1) - 0.5
			var oz := float(j) / float(nz - 1) - 0.5
			var y := _ground_sample(cx + ox * w, cz + oz * d)
			lo = minf(lo, y)
			hi = maxf(hi, y)
	return [lo, hi - lo]

## 長屋：街區周邊的長條建築。ridge_along_x = 屋脊沿 x 軸（南北向的牆用）
## flip = 立面轉 180 度。v7 的立面永遠朝本地 +z，於是街區北側與西側的長屋
## 「玄關開向自家中庭」—— 這也是店前鋪面永遠對不齊門口的根本原因。
func _longhouse(parent: Node, name: String, cx: float, cz: float, length: float, depth: float,
		ridge_along_x: bool, storey := 1, roof := "kawara", flip := false,
		shop_p := 0.55) -> void:
	# ── 牆的做法（かべ）：一棟一種，按分區抽 ──
	# v16 之前只有 plaster/mud 兩個 key，而且它們**指向同一張貼圖** ——
	# 全村的牆是一張圖染成 8 色。使用者：「其實我也覺得挺單調的」。
	# 現在町方偏漆喰與焼杉（都市感、講究），在偏荒壁（土壁裸露，農家的做法）。
	var wall_kinds: Array = ["plaster", "plaster", "yakisugi", "shitami"] if _zone_of(cx, cz) == ZONE_MACHI \
		else (["plaster", "mud", "shitami", "yakisugi"] if _zone_of(cx, cz) == ZONE_HANNO \
		else ["mud", "mud", "mud", "shitami"])
	var wall_kind: String = wall_kinds[int(lib.rand() * float(wall_kinds.size()))]
	var tone_v := int(lib.rand() * 4.0)     # 整棟共用一個色調變體
	var wall := _mat(wall_kind, tone_v)
	# 腰壁（こしかべ）：牆腳那一段換材質。町並最好認的分層 ——
	# 上半白漆喰、下半下見板張り或亂石，一整排立面立刻有節奏。
	var skirt_kind := ""
	if wall_kind in ["plaster", "mud"]:
		skirt_kind = "shitami" if lib.rand() < 0.7 else "ishizumi"
	var dark := _mat("dark")
	var stone := _mat("stone")
	var roof_m := _mat(roof)
	# 高度不要只有兩檔 —— v8 所有平房一律 3.0m，整排剪影一模一樣
	var h := lib.rr(2.9, 3.5) if storey == 1 else lib.rr(5.4, 6.6)
	var gu := _ground_under(cx, cz, length if ridge_along_x else depth, depth if ridge_along_x else length)
	var g := Node3D.new()
	g.position = Vector3(cx, gu[0], cz)          # 站在最低點，不會有一端浮空
	var yaw := 0.0 if ridge_along_x else PI / 2.0
	if flip:
		yaw += PI
	g.rotation.y = yaw
	lib.add(parent, g, name)
	# 本體（本地座標一律「長邊沿 x」，靠 rotation 轉向）
	# 基石往下加深「高差 + 0.4」，把坡度吃掉（v6 的建築離地就是缺這段）
	var foot: float = float(gu[1]) + 0.45
	lib.box(g, "基石", Vector3(length + 0.4, 0.32 + foot, depth + 0.4), stone, Vector3(0, 0.16 - foot * 0.5, 0))
	lib.box(g, "屋身", Vector3(length, h, depth), wall, Vector3(0, 0.32 + h * 0.5, 0))
	if skirt_kind != "":
		# 只做四周薄薄一圈，不是整棟換材質（整棟換的話上半的白牆就沒了）
		var sk_h := lib.rr(0.85, 1.25)
		lib.box(g, "腰壁", Vector3(length + 0.09, sk_h, depth + 0.09), _mat(skirt_kind),
			Vector3(0, 0.32 + sk_h * 0.5, 0))
	# ── 真壁造（しんかべ）：柱樑露在牆外的格子 ──
	# 使用者拿《幻走スカイドリフト》與官方美術當參考，四張圖的共同特徵就是這個：
	# 牆不是一片平的，是**白灰嵌在木框裡**。這才是「材質模組更多樣」的答案 ——
	# 光換貼圖沒有用，缺的是**結構線**。焼杉那種板壁本來就沒有真壁，跳過。
	if wall_kind in ["plaster", "mud"]:
		var fr := _mat("dark", tone_v)
		var ez: float = depth * 0.5 + 0.045
		var ex: float = length * 0.5 + 0.045
		var y0: float = 0.32
		var posts := maxi(int(length / 3.2), 2)
		for face in [1.0, -1.0]:                       # 前後兩面
			for i in posts + 1:
				var px: float = -length * 0.5 + length * float(i) / float(posts)
				lib.box(g, "柱_%d_%d" % [int(face), i], Vector3(0.15, h, 0.10), fr,
					Vector3(px, y0 + h * 0.5, face * ez))
			# 土台・胴貫・桁：三道橫材，二層的話中間再加一道
			var rails: Array = [0.02, 0.99] if storey == 1 else [0.02, 0.50, 0.99]
			for ri in rails.size():
				lib.box(g, "貫_%d_%d" % [int(face), ri], Vector3(length + 0.1, 0.17, 0.10), fr,
					Vector3(0, y0 + h * float(rails[ri]), face * ez))
		for face2 in [1.0, -1.0]:                      # 兩側妻面
			for i in 2:
				var pz: float = -depth * 0.5 + depth * float(i)
				lib.box(g, "妻柱_%d_%d" % [int(face2), i], Vector3(0.10, h, 0.15), fr,
					Vector3(face2 * ex, y0 + h * 0.5, pz))
			lib.box(g, "妻貫_%d" % int(face2), Vector3(0.10, 0.17, depth + 0.1), fr,
				Vector3(face2 * ex, y0 + h * 0.99, 0.0))

	# ── 立面：逐間（bay）決定是玄關／窗／板壁 ──
	# v3 的問題是「只有一片格子戶貼在牆上」，走近看是紙板。
	# 這裡每一間都做立體：凹陷的玄關、有框有格的窗、腰板、庇。
	var fz2 := depth * 0.5
	var bays := maxi(int(length / 3.4), 1)
	var bw := length / float(bays)
	var door_bay := int(lib.rand() * float(bays))
	var is_shop := lib.rand() < shop_p
	# ── 門面（Frontage）：把玄關的世界座標與朝向登記出去 ──
	# 有了這個，店前鋪面／飛石／樽桶才能真的擺在門口，而不是沿街亂撒。
	var door_lx := -length * 0.5 + (float(door_bay) + 0.5) * bw
	var cy := cos(yaw)
	var sy := sin(yaw)
	var out_dir := Vector2(sy, cy)                                   # 本地 +z 的世界方向
	var door_w := Vector2(cx + door_lx * cy + fz2 * sy, cz - door_lx * sy + fz2 * cy)
	for i in bays + 1:
		var px: float = -length * 0.5 + float(i) * bw
		lib.box(g, "通柱_%d" % i, Vector3(0.22, h, 0.24), dark, Vector3(px, 0.32 + h * 0.5, fz2 + 0.03))
	lib.box(g, "腰板", Vector3(length + 0.05, 0.85, 0.1), dark, Vector3(0, 0.75, fz2 + 0.06))
	lib.box(g, "軒桁", Vector3(length + 0.3, 0.2, 0.26), dark, Vector3(0, 0.32 + h - 0.12, fz2 + 0.06))
	for i in bays:
		var dx := -length * 0.5 + (float(i) + 0.5) * bw
		if i == door_bay:
			# 玄關：牆面凹進去 0.55m（黑洞洞的門口，參考圖的關鍵特徵）
			lib.box(g, "玄關凹", Vector3(minf(bw * 0.72, 2.6), 2.3, 1.1),
				lib.flat_mat("interior_dark", Color(0.06, 0.055, 0.05), 1.0),
				Vector3(dx, 1.32, fz2 - 0.5))
			for sd in [-1, 1]:                       # 門框
				lib.box(g, "門框_%d_%d" % [i, sd + 1], Vector3(0.16, 2.5, 0.6), dark,
					Vector3(dx + float(sd) * minf(bw * 0.36, 1.3), 1.4, fz2 - 0.18))
			lib.box(g, "鴨居_%d" % i, Vector3(minf(bw * 0.8, 2.9), 0.22, 0.6), dark, Vector3(dx, 2.62, fz2 - 0.18))
			lib.box(g, "沓脫石_%d" % i, Vector3(1.5, 0.22, 0.9), _mat("stone"), Vector3(dx, 0.11, fz2 + 0.55))
			lib.box(g, "玄關庇_%d" % i, Vector3(minf(bw * 1.05, 3.5), 0.14, 1.3), roof_m,
				Vector3(dx, 0.32 + h * 0.78, fz2 + 0.55))
			for sd2 in [-1, 1]:
				lib.cyl(g, "庇柱_%d_%d" % [i, sd2 + 1], 0.08, 0.09, 0.32 + h * 0.78, dark,
					Vector3(dx + float(sd2) * minf(bw * 0.45, 1.6), (0.32 + h * 0.78) * 0.5, fz2 + 1.1), 6)
			if is_shop:                              # 商家：暖簾 + 吊招牌（象徵性裝飾）
				var cloth := StandardMaterial3D.new()
				# ⚠ 舊的四個色全是灰掉的濁色（0.26,0.22,0.32 之類），
				# 掛上去等於沒掛。參考圖裡的暖簾是**整條街唯一的顏色來源** ——
				# 飽和的紫、綠、藍、紅，而且面積很大。
				cloth.albedo_color = [Color(0.34, 0.16, 0.46), Color(0.12, 0.42, 0.24),
					Color(0.10, 0.24, 0.56), Color(0.62, 0.16, 0.14),
					Color(0.86, 0.72, 0.22), Color(0.08, 0.30, 0.42)][int(lib.rand() * 6.0)]
				cloth.roughness = 1.0
				for k in [-1, 0, 1]:
					lib.box(g, "暖簾_%d_%d" % [i, k + 1], Vector3(minf(bw * 0.26, 0.95), 1.05, 0.04), cloth,
						Vector3(dx + float(k) * minf(bw * 0.27, 1.0), 1.92, fz2 + 0.02))
				lib.box(g, "暖簾竿_%d" % i, Vector3(minf(bw * 0.72, 2.6), 0.08, 0.1), dark,
					Vector3(dx, 2.4, fz2 + 0.02))
				var sign := lib.box(g, "吊招牌_%d" % i, Vector3(0.5, 1.5, 0.1), _mat("wood"),
					Vector3(dx + minf(bw * 0.5, 1.8), 1.9, fz2 + 0.85))
				sign.rotation.y = lib.rr(-0.05, 0.05)
		elif lib.rand() < 0.62:
			# 窗：外框 + 內縮的暗面 + 立體格子
			var ww := minf(bw * 0.66, 2.3)
			lib.box(g, "窗暗面_%d" % i, Vector3(ww, 1.35, 0.1),
				lib.flat_mat("interior_dark", Color(0.06, 0.055, 0.05), 1.0),
				Vector3(dx, 1.85, fz2 - 0.06))
			var frames: Array = [[ww + 0.24, 0.14, 0.0, 0.72], [ww + 0.24, 0.14, 0.0, -0.72],
					[0.14, 1.5, (ww + 0.1) * 0.5, 0.0], [0.14, 1.5, -(ww + 0.1) * 0.5, 0.0]]
			for e in frames:
				lib.box(g, "窗框_%d_%d" % [i, int(e[2] * 10 + e[3] * 10)],
					Vector3(e[0], e[1], 0.16), dark, Vector3(dx + e[2], 1.85 + e[3], fz2 + 0.06))
			# ⚠ 格子以前是 3 根直木 + 1 根橫桟的實體（每扇窗 4 個 mesh，全村 1160 個）。
			# v15 烤了 wood_lattice 貼圖，改成一片板 —— 遠看一樣，近看差在深度，
			# 但 1160 次 draw call 換一點深度不值得。
			lib.box(g, "格子_%d" % i, Vector3(ww, 1.35, 0.06), _mat("lattice", tone_v),
				Vector3(dx, 1.85, fz2 + 0.05))
			if lib.rand() < 0.4:                     # 雨戶箱（收雨窗的箱子）
				lib.box(g, "雨戶箱_%d" % i, Vector3(0.45, 1.5, 0.3), _mat("wood"),
					Vector3(dx + ww * 0.5 + 0.3, 1.85, fz2 + 0.12))
		else:
			lib.box(g, "板壁_%d" % i, Vector3(bw * 0.92, 1.9, 0.09), _mat("wood"),
				Vector3(dx, 1.6, fz2 + 0.05))
			if lib.rand() < 0.25:                    # 牆邊的晾衣竿（生活感）
				for sd3 in [-1, 1]:
					lib.cyl(g, "竿柱_%d_%d" % [i, sd3 + 1], 0.05, 0.06, 1.8, dark,
						Vector3(dx + float(sd3) * bw * 0.3, 0.9, fz2 + 1.2), 5)
				lib.box(g, "物干竿_%d" % i, Vector3(bw * 0.66, 0.06, 0.06), dark,
					Vector3(dx, 1.75, fz2 + 1.2))
	# 緣側（外廊）：部分建築有
	if lib.rand() < 0.35:
		lib.box(g, "緣側", Vector3(length * 0.8, 0.16, 1.5), _mat("wood"), Vector3(0, 0.42, fz2 + 0.8))
		for k2 in 4:
			lib.cyl(g, "緣束_%d" % k2, 0.07, 0.07, 0.42, dark,
				Vector3(-length * 0.32 + float(k2) * length * 0.21, 0.21, fz2 + 1.4), 5)
	if storey == 2:
		lib.box(g, "二階窗", Vector3(length * 0.75, 1.1, 0.08), dark, Vector3(0, 4.0, depth * 0.5 + 0.05))
		lib.box(g, "庇", Vector3(length + 0.8, 0.14, 1.1), roof_m, Vector3(0, 3.1, depth * 0.5 + 0.42))
	# ── 下屋（げや）：側面加一段低矮的披屋，剪影就不再是一個純方塊 ──
	if lib.rand() < 0.42:
		var gd := lib.rr(1.5, 2.3)                 # 披屋的進深
		# ⚠ 只能往**背面**長（-z）。本地 +z 是立面 —— 格子窗、玄關、庇都在那邊。
		# v13 這裡是 `1.0 if rand()<0.5 else -1.0`，於是一半的長屋
		# 在自己的窗前 1.5~2.3m 立了一道下屋壁 ——
		# 使用者兩次回報「有牆擋到窗戶」，就是這個。
		# 門面淨空檢查抓不到它：它是**同一棟建物自己的**構件，不是別人的地權。
		var sgn_g := -1.0
		var gw := length * lib.rr(0.5, 0.8)
		var gxo := lib.rr(-0.12, 0.12) * length
		var z_in: float = depth * 0.5              # 貼著主屋牆的那一邊
		var z_out: float = z_in + gd               # 外側簷口
		var y_in := 0.32 + h * 0.62                # 上緣接在主牆上
		var y_out := y_in - gd * 0.42              # 下緣（坡度約 23°）
		lib.box(g, "下屋壁", Vector3(gw, y_out - 0.1, gd * 0.92), wall,
			Vector3(gxo, (y_out - 0.1) * 0.5, sgn_g * (z_in + gd * 0.5)))
		# 屋面：長度用斜邊算（gd/cos θ），角度用兩緣高差算 —— 這樣上緣一定
		# 貼在主牆上、下緣一定落在簷口，不會一邊翹進牆裡一邊懸空
		var ang := atan2(y_in - y_out, gd)
		var slab_len := gd / cos(ang)
		var geya := lib.box(g, "下屋根", Vector3(gw + 0.5, 0.15, slab_len + 0.45), roof_m,
			Vector3(gxo, (y_in + y_out) * 0.5, sgn_g * (z_in + gd * 0.5)))
		geya.rotation.x = ang * sgn_g
	# ── 卯建（うだつ）：相鄰兩戶之間突出屋頂的防火壁，町並的招牌特徵 ──
	if storey == 2 and lib.rand() < 0.55:
		for sd_u in [-1.0, 1.0]:
			lib.box(g, "卯建_%d" % int(sd_u + 1), Vector3(0.28, 1.5, depth * 0.72), wall,
				Vector3(sd_u * length * 0.5, 0.32 + h + 0.55, 0))
			lib.box(g, "卯建瓦_%d" % int(sd_u + 1), Vector3(0.5, 0.14, depth * 0.78), roof_m,
				Vector3(sd_u * length * 0.5, 0.32 + h + 1.36, 0))
	# 切妻屋頂：坡度也隨機一點，整排才不會像同一個模具壓出來
	var thick := 0.22 if roof == "kawara" else 0.5
	var pitch := lib.rr(0.42, 0.58) if roof == "kawara" else lib.rr(0.60, 0.76)
	lib.gable_roof(g, 0.32 + h, length + 0.9, depth + 1.5, pitch, thick, roof_m, wall)
	_collide(g, Vector3(length + 0.4, h + 2.0, depth + 0.4))
	var own := _claim(cx, cz, length + 1.0, depth + 1.6, "longhouse") if ridge_along_x \
		else _claim(cx, cz, depth + 1.6, length + 1.0, "longhouse")
	_frontages.append({
		"pos": door_w, "dir": out_dir, "shop": is_shop, "src": name,
		"width": minf(bw, 3.2), "ground": float(gu[0]), "own": own,
	})

## 這個座標落在哪一種街區（給圍牆判斷用）
func _kind_at(cx: float, cz: float) -> String:
	var best := ""
	var bd := INF
	for bx in BLOCK_X:
		for bz in BLOCK_Z:
			var d := maxf(absf(cx - bx) / (BLOCK_W * 0.5), absf(cz - bz) / (BLOCK_D * 0.5))
			if d < bd:
				bd = d
				best = BLOCK_KIND.get("%d,%d" % [int(bx), int(bz)], "compound")
	return best if bd <= 1.15 else "compound"

const LANDMARK_KINDS := ["hieda", "terakoya", "suzunaan", "unomitei", "ashiarai"]

## 築地塀（ついじべい）：地標宅邸的圍牆。
##
## 使用者看《求聞編年史》的參考圖之後說：「有地標的建築圍牆跟建築比例
## 都要放很大才有氣勢感」。關鍵不在把房子放大 —— 參考圖裡氣勢是靠
## **高石垣 + 帶瓦屋頂的高牆 + 石階**堆出來的。
## 一般民家用 1.9m 的土塀；地標用 2.9m 的築地塀，還有真的兩坡瓦頂與控柱。
const TSUIJI_H := 2.9
## Blender 生垣模組的長度（make_hedge.py 的 MODULE_LEN）
const HEDGE_MODULE := 2.4
const HEDGE_MODS := ["hedge_a", "hedge_b", "hedge_c"]
var _hedge_batch := {"hedge_a": [], "hedge_b": [], "hedge_c": []}
func _tsuiji_run(parent: Node, name: String, cx: float, cz: float, length: float, along_x: bool) -> void:
	var gw := _ground_under(cx, cz, length if along_x else 1.4, 1.4 if along_x else length)
	var g := Node3D.new()
	g.position = Vector3(cx, gw[0], cz)
	if not along_x:
		g.rotation.y = PI / 2.0
	lib.add(parent, g, name)
	var foot: float = float(gw[1]) + 0.4
	var stone := _mat("stone")
	var kawara := _mat("kawara")
	# 腰石垣：牆腳先墊一段亂石，高牆才站得住（也是參考圖裡最顯眼的一層）
	lib.box(g, "腰石垣", Vector3(length, 0.85 + foot, 0.86), stone,
		Vector3(0, 0.42 - foot * 0.5, 0))
	lib.box(g, "塀身", Vector3(length, TSUIJI_H - 0.85, 0.62), _mat("plaster", 0),
		Vector3(0, 0.85 + (TSUIJI_H - 0.85) * 0.5, 0))
	# 白牆上的橫線（定規筋）—— 格式高的築地塀才有，一眼看出「這裡不一樣」
	for i in 3:
		lib.box(g, "定規筋_%d" % i, Vector3(length, 0.07, 0.70), stone,
			Vector3(0, TSUIJI_H - 0.42 - float(i) * 0.22, 0))
	# 兩坡瓦屋頂（不是一塊瓦冠板）
	for sd in [-1.0, 1.0]:
		var slope := lib.box(g, "塀屋根_%d" % int(float(sd) + 1),
			Vector3(length + 0.3, 0.14, 0.78), kawara,
			Vector3(0, TSUIJI_H + 0.16, float(sd) * 0.32))
		slope.rotation.x = float(sd) * -0.42
	lib.box(g, "棟瓦", Vector3(length + 0.3, 0.2, 0.26), kawara, Vector3(0, TSUIJI_H + 0.3, 0))
	# 控柱（撐住高牆的斜柱）—— 沒有它高牆看起來像立起來的紙板
	var props := maxi(int(length / 5.5), 1)
	for i in props:
		var px: float = -length * 0.5 + (float(i) + 0.5) / float(props) * length
		lib.strut(g, "控柱_%d" % i, Vector3(px, 0.0, 0.75), Vector3(px, TSUIJI_H - 0.6, 0.34),
			0.09, _mat("dark"), 5)
	_collide(g, Vector3(length, TSUIJI_H + 0.5, 0.9))
	_claim(cx, cz, length + 0.6 if along_x else 1.6, 1.6 if along_x else length + 0.6, "tsuiji_run")

## 石垣基壇 + 石階：把地標墊高。參考圖裡的稗田邸就是坐在一道高石垣上，
## 正面切出一段石階 —— 這是「氣勢」的來源，不是把屋身放大。
## 回傳基壇頂面的相對高度。
## ⚠ 基壇要掛在**建物自己的群組**底下，不能當兄弟節點 ——
## 體檢是「一個群組 = 一棟建物」在量離地的，基壇分開放的話
## 主屋會被判成離地 1.5m（而它其實是站在基壇上）。
## 傳進來的 g 的原點 = 基壇**頂面**，所以基壇往下長。
func _dais_in(g: Node3D, w: float, d: float, h: float, face: Vector2, spread: float) -> void:
	var stone := _mat("stone")
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
	_collide(g, Vector3(w, h, d), Vector3(0, -h, 0))

## 生垣（樹籬）＋竹垣：村緣的「圍牆」。
##
## 在（農家那一環）用土塀是錯的 —— 土塀是町方的東西，要人力與瓦。
## 村緣圍的是樹籬與竹垣，而且矮，看得到裡面的曬場。
## 這也是「密度不一樣的街區不要混在一起」的一部分：材質本身就要換。
func _hedge_run(parent: Node, name: String, cx: float, cz: float, length: float, along_x: bool) -> void:
	var gw := _ground_under(cx, cz, length if along_x else 0.8, 0.8 if along_x else length)
	var g := Node3D.new()
	g.position = Vector3(cx, gw[0], cz)
	if not along_x:
		g.rotation.y = PI / 2.0
	lib.add(parent, g, name)
	# ⚠ 這裡改過兩次，兩次都被抓包：
	#   v14 用 lib.box 疊葉叢 →「這個方塊的草到底是什麼」
	#   v15 改成 blob_mesh 橢圓球 + cellular 葉貼圖 →「很像西瓜黏上去」
	# 兩次的病根是同一個：**光滑的封閉曲面**。真正的樹籬輪廓是碎的，
	# 幾百根小枝葉戳出來；光滑曲面不管貼什麼圖都是水果。
	# v16 改成用 Blender 雕好的模組（assets/blender/make_hedge.py）：
	# 粗胚塊體擋視線 + 表面 200 叢枝葉打碎輪廓 + 底下露枝幹。
	# 模組不各自建 MeshInstance3D —— 一個模組 1.2 萬個三角形、全村 350 段，
	# 那是 400 萬個三角形與 350 次 draw call。收集 transform，最後一次
	# 用 MultiMesh 發出去（每種變體一次 draw call）。
	var count := maxi(int(length / HEDGE_MODULE), 1)
	var step := length / float(count)
	for i in count:
		var px2: float = -length * 0.5 + (float(i) + 0.5) * step
		var mwx: float = cx + (px2 if along_x else 0.0)
		var mwz: float = cz + (0.0 if along_x else px2)
		var jitter: float = lib.rr(-0.10, 0.10)
		var t := Transform3D()
		# 模組要重疊一點（step > MODULE 時會露縫），高矮也各自變化
		t.basis = t.basis.scaled(Vector3(step / HEDGE_MODULE * lib.rr(1.06, 1.16),
			lib.rr(0.88, 1.16), lib.rr(0.92, 1.12)))
		t.basis = t.basis.rotated(Vector3.UP, (PI if lib.rand() < 0.5 else 0.0)
			+ (0.0 if along_x else PI * 0.5))
		t.origin = Vector3(mwx + (0.0 if along_x else jitter),
			_ground_sample(mwx, mwz) - 0.06,
			mwz + (jitter if along_x else 0.0))
		_hedge_batch[HEDGE_MODS[int(lib.rand() * 3.0)]].append(t)
	_collide(g, Vector3(length, 1.4, 0.9))
	_claim(cx, cz, length + 0.6 if along_x else 1.2, 1.2 if along_x else length + 0.6, "hedge_run")

## 土塀：街區外圍的圍牆（帶瓦冠）
func _wall_run(parent: Node, name: String, cx: float, cz: float, length: float, along_x: bool) -> void:
	if length < 1.0:
		return
	# 地標宅邸用築地塀（高、帶瓦屋頂）—— 氣勢是圍牆給的
	if _kind_at(cx, cz) in LANDMARK_KINDS:
		_tsuiji_run(parent, name.replace("塀", "築地塀"), cx, cz, length, along_x)
		return
	# 在（村緣）改用生垣：材質換掉，區與區才不會混在一起
	if _zone_of(cx, cz) == ZONE_ZAI:
		_hedge_run(parent, name.replace("塀", "生垣"), cx, cz, length, along_x)
		return
	# 土塀是「街區缺口一律補上」的，不像建物會先問 _free ——
	# 於是村西南那個街區的圍牆直接橫過自然池（岸石就長在牆裡了）。
	if Vector2(cx - NATURE_POND.x, cz - NATURE_POND.y).length() < NATURE_POND_R * 1.25:
		return
	if Vector2(cx - GARDEN_POND.x, cz - GARDEN_POND.y).length() < GARDEN_POND_R * 1.25:
		return
	if lib.poly_dist(CANAL, cx, cz) < CANAL_HALF * 1.6:
		return
	var gw := _ground_under(cx, cz, length if along_x else 0.6, 0.6 if along_x else length)
	var g := Node3D.new()
	g.position = Vector3(cx, gw[0], cz)
	if not along_x:
		g.rotation.y = PI / 2.0
	lib.add(parent, g, name)
	var wfoot: float = float(gw[1]) + 0.35
	lib.box(g, "塀", Vector3(length, 1.9 + wfoot, 0.34), _mat("mud"), Vector3(0, 0.95 - wfoot * 0.5, 0))
	lib.box(g, "塀瓦", Vector3(length + 0.2, 0.14, 0.62), _mat("kawara"), Vector3(0, 1.97, 0))
	_collide(g, Vector3(length, 2.1, 0.5))
	# 土塀也要佔地權 —— 沒有的話岸石／樹會直接長在牆上
	_claim(cx, cz, length + 0.6 if along_x else 1.2, 1.2 if along_x else length + 0.6, "wall_run")

# ═══════════════════════════════ 街區 ═══════════════════════════════════
## 產生器自己驗：水體的開挖範圍不能碰到街。
## 使用者回報「池塘在路上」——池心離街緣 6.5m，而開挖半徑是 20m。
## 這種事應該在產生的當下就吵，而不是等截圖才發現。
func _assert_water_clear_of_streets() -> void:
	var bad := 0
	for w in [[NATURE_POND, NATURE_POND_R], [GARDEN_POND, GARDEN_POND_R]]:
		var c: Vector2 = w[0]
		var r: float = float(w[1]) * 1.35
		var worst := 1e9
		for i in 48:
			var a := float(i) / 48.0 * TAU
			var p := c + Vector2(cos(a), sin(a)) * r
			worst = minf(worst, _path_info(p.x, p.y)[0])
		if worst < 1.0:
			bad += 1
			push_warning("水體壓到街：池心 (%.0f, %.0f) 開挖到街緣內 %.1fm" % [c.x, c.y, 1.0 - worst])
			print("  ⚠ 水體壓到街：池心 (%.0f, %.0f)，開挖圈離街緣 %.1fm" % [c.x, c.y, worst])
	if bad == 0:
		print("water/street clearance: ok")

func _build_blocks() -> void:
	var root := lib.add(lib.root, Node3D.new(), "Blocks")
	var n_house := 0
	for bx in BLOCK_X:
		for bz in BLOCK_Z:
			var kind: String = BLOCK_KIND.get("%d,%d" % [int(bx), int(bz)], "compound")
			var g := lib.add(root, Node3D.new(), "街區_%d_%d_%s" % [int(bx), int(bz), kind])
			var before := n_house
			match kind:
				"grove": _blk_grove(g, bx, bz)
				"market": _blk_market(g, bx, bz)
				"tower": _blk_tower(g, bx, bz)
				"hieda": _blk_hieda(g, bx, bz)
				"terakoya": _blk_terakoya(g, bx, bz)
				"suzunaan": n_house += _blk_shopfront(g, bx, bz, "鈴奈庵", -1)
				"unomitei": n_house += _blk_shopfront(g, bx, bz, "鵜吞亭", -1)
				"ashiarai": _blk_ashiarai(g, bx, bz)
				_: n_house += _blk_compound(g, bx, bz)
	# 分區報表：改了 ZONE_SPEC 要能一眼看出「密度真的不一樣」。
	# 空拍看不出 5% 的差別，這行看得出來。
	var zparts: Array[String] = []
	for i in 3:
		var blocks: int = _zone_stat[i][0]
		var area: float = _zone_stat[i][2]
		var cover: float = area / maxf(float(blocks) * BLOCK_W * BLOCK_D, 1.0) * 100.0
		zparts.append("%s %d院落/%d棟/建蔽 %.0f%%" % [ZONE_NAME[i], blocks, _zone_stat[i][1], cover])
	print("blocks built, longhouses: %d ── %s" % [n_house, "  ".join(zparts)])
	_emit_hedges()
	_assert_frontage_clear()

## ── 合併裝飾構件（降 draw call）──
##
## 使用者：「我電腦變卡了」。量出來是 **15,625 個 MeshInstance3D**，
## 也就是 15,625 次 draw call（正常該在 2000 以內）。原因是產生器的每一根
## 柱、每一片窗框、每一塊海鼠瓦都是獨立的 lib.box()。
##
## 解法是把**同一棟建物、同一個材質**的裝飾構件烤成一個 ArrayMesh。
##
## ⚠ 只合併裝飾件。`check_map.gd` 是靠子節點的名字（基石／屋身／塀／
## 基壇／土台／石垣）逐片量離地與互卡的 —— 那些**不能**合併，
## 合併了體檢就瞎了。這也是為什麼不做「整棟合成一個 mesh」。
var _merged_removed := 0
const NO_MERGE := ["基石", "屋身", "塀", "基壇", "土台", "石垣", "腰壁", "屋根", "瓦"]

func _mergeable(nm: String) -> bool:
	for k in NO_MERGE:
		if nm.contains(k):
			return false
	return true

func _merge_decor(root: Node) -> Array:
	var before := 0
	var after := 0
	var stack: Array[Node] = [root]
	const SKIP := ["Terrain", "Vista", "遠景", "River", "Canal", "Water"]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		for c in node.get_children():
			var skip := false
			for k in SKIP:
				if String(c.name).contains(k):
					skip = true
					break
			if skip:
				continue
			if c.get_child_count() > 0 or (c is Node3D and not (c is MeshInstance3D)):
				stack.push_back(c)
		# 這一層的可合併子節點，依材質分組
		var buckets := {}
		for c in node.get_children():
			if not (c is MeshInstance3D):
				continue
			var mi := c as MeshInstance3D
			before += 1
			if mi.get_child_count() > 0:          # 掛著碰撞體的不動
				continue
			if not _mergeable(String(mi.name)):
				continue
			var mat: Material = mi.material_override
			if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
				mat = mi.mesh.surface_get_material(0)
			if mat == null or mi.mesh == null:
				continue
			# ⚠ 只吃小零件。第一版沒設上限，合併器跑去啃遠景地形與 vista
			# （幾十萬頂點），在 GDScript 裡逐頂點重建 → 直接掛住十分鐘。
			# 箱子 24 個頂點、圓柱 ~70 個，180 綽綽有餘。
			var vcount := 0
			for si0 in mi.mesh.get_surface_count():
				vcount += (mi.mesh.surface_get_arrays(si0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			if vcount > 180:
				continue
			var key: String = mat.resource_path if mat.resource_path != "" else str(mat.get_instance_id())
			if not buckets.has(key):
				buckets[key] = [mat, []]
			buckets[key][1].append(mi)
		for key in buckets:
			var mat: Material = buckets[key][0]
			var list: Array = buckets[key][1]
			if list.size() < 3:                   # 合併不划算
				continue
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for mi2 in list:
				var mesh: Mesh = (mi2 as MeshInstance3D).mesh
				var xf: Transform3D = (mi2 as MeshInstance3D).transform
				for si in mesh.get_surface_count():
					var arr: Array = mesh.surface_get_arrays(si)
					# ⚠ 這幾格可能是 **null**（沒有 UV 或沒有索引的 mesh）。
					# 直接指定給 PackedVector2Array 會拋型別錯誤，整個合併器死掉，
					# 而且死在存檔前面 —— 場景根本不會被重寫。
					var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					var nv = arr[Mesh.ARRAY_NORMAL]
					var uv = arr[Mesh.ARRAY_TEX_UV]
					var ix = arr[Mesh.ARRAY_INDEX]
					var norms: PackedVector3Array = nv if nv != null else PackedVector3Array()
					var uvs: PackedVector2Array = uv if uv != null else PackedVector2Array()
					var idx := PackedInt32Array()
					if ix != null:
						idx = ix
					else:
						for vi in verts.size():
							idx.append(vi)
					for ii in idx:
						if norms.size() > ii:
							st.set_normal((xf.basis * norms[ii]).normalized())
						if uvs.size() > ii:
							st.set_uv(uvs[ii])
						st.add_vertex(xf * verts[ii])
			st.index()
			var merged := MeshInstance3D.new()
			merged.mesh = st.commit()
			merged.material_override = mat
			# 名字保留一個代表，方便之後除錯知道合併了什麼
			var tag := String((list[0] as MeshInstance3D).name).split("_")[0]
			node.add_child(merged)
			merged.owner = lib.root
			merged.name = "合併_%s_x%d" % [tag, list.size()]
			after += 1
			_merged_removed += list.size()
			for mi3 in list:
				node.remove_child(mi3)
				mi3.queue_free()
	return [before, after]

## 生垣：把收集到的模組 transform 一次發成 MultiMesh
func _emit_hedges() -> void:
	var total := 0
	var g := lib.add(lib.root, Node3D.new(), "生垣")
	for m in HEDGE_MODS:
		var list: Array = _hedge_batch[m]
		if list.is_empty():
			continue
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(
			lib.prop_mesh("res://assets/models/%s.glb" % m), list, [],
			"%s/mm_%s.tres" % [OUT_DIR, m])
		mmi.material_override = lib.foliage_vc_mat()
		lib.add(g, mmi, "生垣_%s" % m)
		total += list.size()
	print("hedges: %d 模組 / %d 種" % [total, HEDGE_MODS.size()])

## 驗每個門面前方有沒有淨空 —— 使用者回報「有窗戶的面被牆壁擋住」。
## 立面（玄關與窗戶那一面）前方 CLEAR_D 公尺內不能有別的地權。
## 這種事程式算得出來，不該等截圖才發現。
const FRONT_CLEAR := 2.6
func _assert_frontage_clear() -> void:
	var blocked := 0
	var why: Array[String] = []
	for f in _frontages:
		var p: Vector2 = f.pos
		var d: Vector2 = f.dir
		var by := ""
		for step in [1.0, 1.8, 2.6]:
			var q: Vector2 = p + d * step
			# 忽略自己那塊地
			by = _blocker_at(q.x, q.y, 0.6, 0.6, int(f.own))
			if by != "":
				break
		if by != "":
			blocked += 1
			if why.size() < 4:
				why.append("%s(%.0f,%.0f)←%s" % [f.get("src", "?"), p.x, p.y, by])
	if blocked > 0:
		print("  ⚠ 門面被擋：%d / %d：%s" % [blocked, _frontages.size(), ", ".join(why)])
	else:
		print("frontage clearance: ok (%d 個門面)" % _frontages.size())

# ═════════════════════════════ 街區分區 ═══════════════════════════════
# 使用者：「村子在做密度不一樣的街區 不要混在一起」。
#
# v13 的 34 個院落全部走同一組參數：同樣的 0.86 有房機率、同樣的 0.48~0.68
# 長度比、同樣的 0.3 兩層機率。建蔽率其實有 30%，不算低 —— 但每一格長得
# 一模一樣，從空中看是同一個模具蓋 34 次，所以「看起來很空」。
# 問題是**均質**，不是稀疏。
#
# 分法是**連續的環**（距廣場中心 r），不是隨機撒點 —— 這就是「不要混在一起」。
# 詳細設計與各區參數見 docs/village-zoning-design.md。
const ZONE_MACHI := 0      # 町方（商家町）    r < 95    12 區
const ZONE_HANNO := 1      # 半農町（職人）    95~155    16 區
const ZONE_ZAI := 2        # 在（農家）        r >= 155  14 區
const ZONE_R := [95.0, 155.0]
const ZONE_NAME := ["町方", "半農町", "在"]

## 各區的性格。全部集中在這裡，不要散在程式各處（ADR-015）。
const ZONE_SPEC := [
	{   # 町方：屋頂要連成一片，轉角只留 1~2m
		"has_house": 1.00, "len_lo": 0.84, "len_hi": 0.96,
		"depth_lo": 7.6, "depth_hi": 9.0,
		# 使用者：「場景和建築都很高很有幻想鄉的獨特味道」。參考圖的町並
		# 幾乎全是二層，而且街道相對窄 —— 高度感是「窄街 + 二層」給的。
		"storey2": 0.88, "kawara": 0.94, "shop": 0.85,
		"hanare": 0, "kura": 0.75,
		# 町方的「圍牆」就是房子本身 —— 參考圖裡的商家町是連續立面直接臨街，
		# 沒有土塀。端牆只在真的需要收邊時才補。
		"wall_end": 0.20, "wall_full": 0.45,
	},
	{   # 半農町：維持現況的密度，但屋根與店舖比例往下調
		"has_house": 0.82, "len_lo": 0.55, "len_hi": 0.74,
		"depth_lo": 6.6, "depth_hi": 8.2,
		"storey2": 0.42, "kawara": 0.50, "shop": 0.30,
		"hanare": 1, "kura": 0.55,
		"wall_end": 0.55, "wall_full": 0.75,
	},
	{   # 在：這一環之後會換成 _blk_farm()，這組參數是還沒換完時的退路
		"has_house": 0.55, "len_lo": 0.40, "len_hi": 0.58,
		"depth_lo": 6.2, "depth_hi": 7.4,
		"storey2": 0.00, "kawara": 0.15, "shop": 0.05,
		"hanare": 1, "kura": 0.30,
		"wall_end": 0.40, "wall_full": 0.55,
	},
]

## 分區統計：{zone: [院落區數, 棟數, 建物佔地 m2]}
## 用**建蔽率**而不是「每區棟數」—— 町方有 7 個街區是地標，
## 棟數平均會被稀釋成 0.9，看起來像「町方最疏」，剛好講反。
var _zone_stat := [[0, 0, 0.0], [0, 0, 0.0], [0, 0, 0.0]]

func _zone_of(bx: float, bz: float) -> int:
	var r := Vector2(bx, bz - PLAZA.y).length()
	if r < ZONE_R[0]:
		return ZONE_MACHI
	return ZONE_HANNO if r < ZONE_R[1] else ZONE_ZAI

## 一般街區：四邊長屋 + 土塀補缺 + 內庭（蔵、井、樹位）
func _blk_compound(parent: Node, bx: float, bz: float) -> int:
	var zi := _zone_of(bx, bz)
	var zs: Dictionary = ZONE_SPEC[zi]
	_zone_stat[zi][0] += 1
	var hw := BLOCK_W * 0.5
	var hd := BLOCK_D * 0.5
	var n := 0
	# 街區大門開在哪一邊（朝最近的主街）
	var gate_side := 0 if absf(bx) > absf(bz - PLAZA.y) else 2      # 0=W/E 1..

	# ⚠ 四邊必須**先一起決定**，不能一邊一邊蓋。
	# 町方的長度比是 0.84~0.96，四個邊各自吃到轉角，南北向那兩棟一定會跟
	# 東西向那兩棟撞在轉角上 —— 而 `_free()` 只會默默把後兩棟拒掉，
	# 結果「加密」反而只剩兩棟。真實的町並是：沿長邊那兩棟通到底，
	# 短邊那兩棟**只排在它們之間**（轉角讓給長邊）。
	# side: 0=北(-z) 1=南(+z) 2=西(-x) 3=東(+x)
	var has := []
	var depth := []
	for side in 4:
		has.append(lib.rand() < float(zs.has_house))
		depth.append(lib.rr(float(zs.depth_lo), float(zs.depth_hi)))
	# 東西向（沿 z）那兩棟的可用長度：扣掉南北兩棟實際佔到哪裡。
	# ⚠ 不是「hd - 進深」—— 長屋還往內縮了 1.6（塀）+ 0.75（簷）＝ 2.35，
	# 而且地權比屋身再大一圈。少扣這 2.35 的話兩邊會差 0.4m 卡住，
	# `_free()` 只會默默拒掉，町方的建蔽率就卡在 19% 上不去。
	const SIDE_PAD := 2.35 + 1.4          # 內縮量 + 地權外擴
	var z_lo: float = -hd + (SIDE_PAD + float(depth[0]) if has[0] else 0.0)
	var z_hi: float = hd - (SIDE_PAD + float(depth[1]) if has[1] else 0.0)

	for side in 4:
		var along_x := side < 2
		var sgn := -1.0 if side % 2 == 0 else 1.0
		# 這一邊可以用的區間（本地座標，沿著這一邊的方向）
		# 沿 x 那兩棟也要縮 —— 不縮的話端點會頂進東西兩側的圍牆線
		# （地標街區換成 0.92m 厚的築地塀之後就撞出來了）。
		const WALL_PAD := 1.2
		var lo: float = (-hw + WALL_PAD) if along_x else z_lo
		var hi: float = (hw - WALL_PAD) if along_x else z_hi
		var span: float = hi - lo
		var mid: float = (lo + hi) * 0.5
		if has[side] and span > 8.0:
			var dp: float = float(depth[side])
			var length: float = span * lib.rr(float(zs.len_lo), float(zs.len_hi))
			# 內縮量由進深決定：屋簷外緣要留在土塀內側（v2 的「建築卡圍牆」）
			var inset := ((hd if along_x else hw) - 1.6) - dp * 0.5 - 0.75
			var off := mid + lib.rr(-0.45, 0.45) * (span - length)
			var cx := bx + (off if along_x else sgn * inset)
			var cz := bz + (sgn * inset if along_x else off)
			if _free(cx, cz, length if along_x else dp, dp if along_x else length, 0.2):
				var storey: int = 2 if lib.rand() < float(zs.storey2) else 1
				var roof: String = "kawara" if lib.rand() < float(zs.kawara) else "thatch"
				# 立面朝街：北側／西側要轉 180 度，否則玄關開向中庭
				_longhouse(parent, "長屋_%d" % side, cx, cz, length, dp, along_x, storey, roof,
					sgn < 0.0, float(zs.shop))
				n += 1
				_zone_stat[zi][1] += 1
				_zone_stat[zi][2] += length * dp
				# 兩端補土塀（補到街區邊，不是補到可用區間邊 —— 圍牆要圍滿）
				for e in [-1.0, 1.0]:
					if lib.rand() >= float(zs.wall_end):
						continue
					var b_edge: float = off + float(e) * length * 0.5            # 屋身端點
					var blk_edge: float = float(e) * (hw if along_x else hd)     # 街區端點
					var wlen: float = absf(blk_edge - b_edge) - 0.5
					if wlen < 1.0:
						continue
					var wc: float = (b_edge + blk_edge) * 0.5
					var wcx: float = bx + (wc if along_x else sgn * (hw - 0.4))
					var wcz: float = bz + (sgn * (hd - 0.4) if along_x else wc)
					_wall_run(parent, "塀_%d_%d" % [side, int(e)], wcx, wcz, wlen, along_x)
				continue
		# 沒有房子的邊：整段土塀（大門那邊留缺口）。
		# ⚠ 不是每一邊都要牆 —— 使用者：「不用每個住家都用圍牆」。
		# 地標街區例外，那裡的牆是氣勢的來源。
		if not (_kind_at(bx, bz) in LANDMARK_KINDS) and lib.rand() >= float(zs.wall_full):
			continue
		var wl := (BLOCK_W if along_x else BLOCK_D) - (7.0 if side == gate_side else 0.0)
		_wall_run(parent, "塀全_%d" % side, bx + (0.0 if along_x else sgn * (hw - 0.4)),
			bz + (sgn * (hd - 0.4) if along_x else 0.0), wl, along_x)
	# ── 四個角落的隅柱：把圍牆封起來 ──
	# 各邊的塀是各自算長度的，交會處必然留縫（使用者：「院子圍牆很多都沒封起來」）。
	# 補一根方柱把角接起來，順便當成角落的裝飾。
	for cxs in [-1.0, 1.0]:
		for czs in [-1.0, 1.0]:
			var kx: float = bx + float(cxs) * (hw - 0.4)
			var kz: float = bz + float(czs) * (hd - 0.4)
			if lib.poly_dist(CANAL, kx, kz) < CANAL_HALF * 1.6:
				continue
			var kgu := _ground_under(kx, kz, 1.0, 1.0)
			var kfoot: float = float(kgu[1]) + 0.35
			var kn := Node3D.new()
			kn.position = Vector3(kx, kgu[0], kz)
			lib.add(parent, kn, "隅柱_%d_%d" % [int(cxs), int(czs)])
			lib.box(kn, "塀", Vector3(0.62, 2.05 + kfoot, 0.62), _mat("mud"),
				Vector3(0, 1.02 - kfoot * 0.5, 0))
			lib.box(kn, "隅瓦", Vector3(0.88, 0.16, 0.88), _mat("kawara"), Vector3(0, 2.14, 0))
			_collide(kn, Vector3(0.7, 2.2, 0.7))
			_claim(kx, kz, 1.0, 1.0, "blk_compound")

	# ⚠ 蔵要先蓋。它是中庭裡最大的量體，離れ的立面又一律朝中庭 ——
	# 後蓋的話蔵就會正好堵在離れ門口（門面體檢抓到的就是這一條）。
	# 先佔位，離れ才有辦法閃開它。
	_kura_in_court(parent, bx, bz, float(zs.kura))

	# 內庭：離れ（後棟小屋）—— 街區內部也要有東西
	for k in int(zs.hanare) * 2:
		var ix := bx + lib.rr(-11.0, 11.0)
		var iz := bz + lib.rr(-11.0, 11.0)
		# ⚠ 先決定朝向再測空地。v8 是拿固定的 11×7 去測，之後才隨機轉 90° ——
		# 轉了之後實際佔地變成 7×11，測到的跟蓋出來的不是同一塊，
		# 結果離れ卡進長屋裡（體檢的「建物互相卡住」就是抓到這個）。
		var along := lib.rand() < 0.5
		var ln := lib.rr(8.0, 11.0)
		var dp := lib.rr(5.5, 6.8)
		var tw: float = (ln if along else dp) + 1.4
		var td: float = (dp if along else ln) + 1.4
		if lib.rand() >= 0.55 or not _free(ix, iz, tw, td, 0.5):
			continue
		# 立面要朝中庭（也就是朝街區中心），不能隨機翻 ——
		# 隨機的話有一半的離れ是「有窗戶的那一面貼著自家圍牆」
		# （使用者：「有窗戶的面被牆壁擋住或蓋到」）。
		# 本地 +z 是立面；along_x 時 +z 指向世界 +z，否則指向世界 +x。
		var toward: float = (bz - iz) if along else (bx - ix)
		var face := Vector2(0, signf(toward)) if along else Vector2(signf(toward), 0)
		# 朝中庭也可能剛好對著蔵。先算過再蓋（ADR：能算的不要等截圖）。
		var door := Vector2(ix, iz) + face * (dp * 0.5)
		if not _clear_ahead(door, face, -1, ln * 0.5 - 0.6):
			continue
		if _blocks_any_frontage(ix, iz, tw, td):
			continue
		_longhouse(parent, "離れ_%d" % k, ix, iz, ln, dp,
			along, 1, "kawara" if lib.rand() < 0.5 else "thatch", toward < 0.0)
		n += 1
		_zone_stat[zi][1] += 1
		_zone_stat[zi][2] += ln * dp
	return n

## 反過來問：這塊要蓋的地，會不會擋到**已經蓋好**的某個門面？
## 只驗「我自己的門口有沒有被擋」是不夠的 —— 先蓋的蔵門口是空的，
## 後蓋的離れ剛好停在它前面，蔵就被封死了（體檢抓到的 (87,-52)）。
func _blocks_any_frontage(cx: float, cz: float, w: float, d: float) -> bool:
	var hw := w * 0.5 + 0.3
	var hd := d * 0.5 + 0.3
	for f in _frontages:
		var p: Vector2 = f.pos
		var dir: Vector2 = f.dir
		var tan := dir.orthogonal()
		var half: float = maxf(float(f.get("width", 2.0)) * 0.5, 1.2)
		for o in [-half, 0.0, half]:
			for step in [1.0, 1.8, FRONT_CLEAR]:
				var q: Vector2 = p + tan * float(o) + dir * step
				if absf(q.x - cx) < hw and absf(q.y - cz) < hd:
					return true
	return false

## 門面前方 FRONT_CLEAR 內有沒有別人的地權（自己那塊還沒登記，所以 own 傳 -1）。
## half_w：玄關開在立面的哪一間是 _longhouse 自己隨機決定的，蓋之前不知道，
## 所以整片立面都要淨空 —— 只驗中心點的話，門開在端點那間就會漏掉
## （體檢抓到的 (87,-52) 就是這樣：立面中心是空的，端點那頭卡到隔壁長屋）。
func _clear_ahead(p: Vector2, dir: Vector2, own := -1, half_w := 0.0) -> bool:
	var tan := dir.orthogonal()
	var offs: Array = [0.0] if half_w < 0.5 else [-half_w, 0.0, half_w]
	for o in offs:
		var base: Vector2 = p + tan * float(o)
		for step in [1.0, 1.8, FRONT_CLEAR]:
			var q: Vector2 = base + dir * step
			if _blocker_at(q.x, q.y, 0.6, 0.6, own) != "":
				return false
	return true

## 土藏（白牆倉庫）——中庭裡的防火倉庫，町並最好認的量體之一。
##
## 舊版的問題：隨機轉 TAU（於是屋脊跟街區歪掉、扉朝著自家圍牆），
## 但地權只登記軸對齊的 6.4×5.4，轉過之後量到的跟蓋出來的不是同一塊。
## 這一版只轉 90° 的倍數，且扉一律朝街區中心（中庭）——那是進得去的一側。
func _kura_in_court(parent: Node, bx: float, bz: float, p := 0.6) -> void:
	if lib.rand() >= p:
		return
	var w := 5.0          # 開間（沿屋脊）
	var d := 4.2          # 進深
	# 貼中庭的一角，扉朝中心。along = 屋脊沿 x
	var along := lib.rand() < 0.5
	var sgn := -1.0 if lib.rand() < 0.5 else 1.0
	var off := lib.rr(-5.0, 5.0)
	var back := lib.rr(9.0, 12.5)                      # 離街區中心多遠
	var sx: float = bx + (off if along else sgn * back)
	var sz: float = bz + (sgn * back if along else off)
	var fw: float = (w if along else d) + 1.4
	var fd: float = (d if along else w) + 1.4
	if not _free(sx, sz, fw, fd, 0.5):
		return
	# 扉朝中心 = 朝 -sgn
	var face := Vector2(0, -sgn) if along else Vector2(-sgn, 0)
	var door := Vector2(sx, sz) + face * (d * 0.5)
	if not _clear_ahead(door, face, -1, w * 0.5 - 0.6):
		return
	if _blocks_any_frontage(sx, sz, fw, fd):
		return

	var gu := _ground_under(sx, sz, fw, fd)
	var foot: float = float(gu[1]) + 0.3
	var s := Node3D.new()
	s.position = Vector3(sx, gu[0], sz)
	# 本地 +z 是扉那一面
	s.rotation.y = atan2(face.x, face.y)
	lib.add(parent, s, "土藏")

	var stone := _mat("stone")
	var dark := _mat("dark")
	# 蔵就是要白 —— 隨機挑到偏灰的那一檔，整棟看起來只是塊水泥
	var plaster := _mat("plaster", 0)
	var kawara := _mat("kawara")
	var namako := _mat("namako")

	# 亂石基壇（高差往下埋）
	lib.box(s, "基壇", Vector3(w + 0.8, 0.4 + foot, d + 0.8), stone,
		Vector3(0, 0.2 - foot * 0.5, 0))
	# 藏身：白漆喰
	lib.box(s, "藏身", Vector3(w, 4.3, d), plaster, Vector3(0, 2.55, 0))
	# 海鼠壁（なまこ壁）：下半段黑瓦 + 白灰縫的菱格。蔵最好認的紋樣，
	# 也是「材質不要只有一塊純色」的解 —— 貼一整片深色會變成一坨。
	var band_h := 1.5
	# ⚠ 海鼠壁以前是**一顆一顆菱形方塊**排出來的 —— 全村 576 個獨立 mesh，
	# 576 次 draw call，只為了做一個花紋。v15 已經烤了 namako 貼圖
	# （菱格 + 凸白目地都在裡面），改成一面一塊板。
	for side_i in 4:
		var sx_face := side_i < 2                          # true = 正／背面（沿 x 展開）
		var sn := -1.0 if side_i % 2 == 0 else 1.0
		var span: float = w if sx_face else d
		lib.box(s, "海鼠壁_%d" % side_i,
			Vector3(span, band_h, 0.09) if sx_face else Vector3(0.09, band_h, span),
			namako,
			Vector3(0, 0.45 + band_h * 0.5, sn * (d * 0.5 + 0.05)) if sx_face
			else Vector3(sn * (w * 0.5 + 0.05), 0.45 + band_h * 0.5, 0))
	# 海鼠壁上緣的水切瓦
	for side_j in 4:
		var sx_face2 := side_j < 2
		var sn2 := -1.0 if side_j % 2 == 0 else 1.0
		lib.box(s, "水切_%d" % side_j,
			Vector3(w + 0.3, 0.12, 0.3) if sx_face2 else Vector3(0.3, 0.12, d + 0.3),
			kawara,
			Vector3(0, 0.45 + band_h + 0.08, sn2 * (d * 0.5 + 0.1)) if sx_face2
			else Vector3(sn2 * (w * 0.5 + 0.1), 0.45 + band_h + 0.08, 0))
	# 扉：厚重的觀音開き + 框
	lib.box(s, "扉框", Vector3(2.1, 2.6, 0.18), dark, Vector3(0, 1.65, d * 0.5 + 0.06))
	for dv in [-1.0, 1.0]:
		lib.box(s, "扉_%d" % int(dv + 1), Vector3(0.88, 2.2, 0.16), _mat("wood"),
			Vector3(dv * 0.48, 1.55, d * 0.5 + 0.16))
	lib.box(s, "扉閂", Vector3(1.9, 0.14, 0.1), dark, Vector3(0, 1.5, d * 0.5 + 0.26))
	# 高處的小窗（蔵只開一個，而且有格子）—— 開在側面，不會被扉那面的東西擋到
	lib.box(s, "窗框", Vector3(0.14, 0.9, 1.1), dark, Vector3(w * 0.5 + 0.06, 3.3, 0))
	for gi in 3:
		lib.box(s, "窗格_%d" % gi, Vector3(0.1, 0.72, 0.07), dark,
			Vector3(w * 0.5 + 0.12, 3.3, -0.34 + float(gi) * 0.34))
	# 置屋根：蔵的屋頂是「另外蓋在土牆上」的，出簷特別深
	lib.gable_roof(s, 4.68, w + 1.8, d + 1.7, 0.52, 0.24, kawara, plaster)
	# 鏝絵（こてえ）：妻壁上的白灰浮雕，一個小圓章就夠看
	lib.cyl(s, "鏝絵", 0.42, 0.42, 0.09, plaster, Vector3(0, 5.1, d * 0.5 - 0.1), 12)

	_collide(s, Vector3(w + 0.4, 5.2, d + 0.4))
	var own := _claim(sx, sz, fw, fd, "土藏")
	_frontages.append({
		"pos": door, "dir": face, "shop": false,
		"width": 2.1, "ground": float(gu[0]), "own": own,
	})

## 面街的商家街區（鈴奈庵、鵜吞亭）：主建築貼本通那一側，其餘同一般街區
func _blk_shopfront(parent: Node, bx: float, bz: float, title: String, face_dir: int) -> int:
	var hw := BLOCK_W * 0.5
	# ⚠ 6.6 不是 5.0 —— 地標街區的圍牆換成築地塀之後厚了一倍（0.36 → 0.92），
	# 5.0 會讓鈴奈庵／鵜吞亭的側牆卡進圍牆裡（體檢：建物互相卡住 8.4㎡）。
	var cx := bx + float(face_dir) * (hw - 6.6)
	var cz := bz + lib.rr(-4.0, 4.0)
	var g := Node3D.new()
	g.position = Vector3(cx, height_at(cx, cz), cz)
	g.rotation.y = -PI / 2.0 if face_dir < 0 else PI / 2.0
	lib.add(parent, g, title)
	var w := 13.0
	var d := 9.5
	lib.box(g, "基石", Vector3(w + 0.5, 0.35, d + 0.5), _mat("stone"), Vector3(0, 0.18, 0))
	lib.box(g, "屋身", Vector3(w, 5.4, d), _mat("plaster"), Vector3(0, 3.05, 0))
	lib.box(g, "腰板", Vector3(w + 0.05, 1.0, 0.08), _mat("dark"), Vector3(0, 0.85, d * 0.5 + 0.05))
	lib.box(g, "格子戶", Vector3(w * 0.62, 2.1, 0.1), _mat("dark"), Vector3(0, 1.75, d * 0.5 + 0.06))
	lib.box(g, "二階窗", Vector3(w * 0.72, 1.3, 0.08), _mat("dark"), Vector3(0, 4.3, d * 0.5 + 0.06))
	lib.box(g, "庇", Vector3(w + 1.0, 0.16, 1.4), _mat("kawara"), Vector3(0, 3.35, d * 0.5 + 0.6))
	# 暖簾與看板
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.28, 0.24, 0.34) if title == "鈴奈庵" else Color(0.55, 0.26, 0.22)
	cloth.roughness = 1.0
	for k in [-1, 0, 1]:
		lib.box(g, "暖簾_%d" % (k + 1), Vector3(2.0, 0.9, 0.05), cloth,
			Vector3(float(k) * 2.2, 2.55, d * 0.5 + 0.66))
	lib.box(g, "看板", Vector3(0.6, 2.4, 0.14), _mat("wood"), Vector3(w * 0.44, 3.0, d * 0.5 + 0.5))
	if title == "鈴奈庵":
		lib.box(g, "書架", Vector3(4.2, 1.3, 0.9), _mat("wood"), Vector3(-2.6, 1.0, d * 0.5 + 1.1))
	else:
		for i in 3:                                    # 鵜吞亭：店頭長凳
			lib.box(g, "長凳_%d" % i, Vector3(1.8, 0.45, 0.6), _mat("wood"),
				Vector3(-3.5 + float(i) * 3.5, 0.4, d * 0.5 + 1.5))
	lib.gable_roof(g, 5.75, w + 1.4, d + 1.6, 0.5, 0.24, _mat("kawara"), _mat("plaster"))
	_collide(g, Vector3(w + 0.5, 7.0, d + 0.5))
	_claim(cx, cz, d + 2.0, w + 2.0, "blk_shopfront")
	return 1 + _blk_compound(parent, bx, bz)

## 寺子屋：大屋頂主屋 + 外廊 + 前庭（慧音的私塾）
func _blk_terakoya(parent: Node, bx: float, bz: float) -> void:
	var cx := bx
	var cz := bz - 6.0
	var g := Node3D.new()
	g.position = Vector3(cx, height_at(cx, cz), cz)
	lib.add(parent, g, "寺子屋")
	# 石垣基壇（參考《求聞編年史》：地標坐在一道高石垣上，正面切石階）
	var dgu := _ground_under(cx, cz, 26.0, 16.0)
	const DAIS_H := 1.5
	g.position = Vector3(cx, dgu[0] + DAIS_H, cz)
	_dais_in(g, 26.0, 16.0, DAIS_H, Vector2(0, 1), float(dgu[1]))
	lib.box(g, "土台", Vector3(24.0, 0.5, 14.0), _mat("stone"), Vector3(0, 0.25, 0))
	lib.box(g, "屋身", Vector3(22.0, 4.6, 12.0), _mat("plaster", 0), Vector3(0, 2.9, 0))
	# 縁側（寬廊）與高欄 —— 參考圖的正面就是一整道木廊
	lib.box(g, "外廊", Vector3(23.4, 0.34, 3.0), _mat("wood"), Vector3(0, 0.85, 7.2))
	lib.box(g, "高欄", Vector3(23.4, 0.14, 0.14), _mat("dark"), Vector3(0, 1.62, 8.6))
	for i in 14:
		lib.box(g, "高欄束_%d" % i, Vector3(0.1, 0.62, 0.1), _mat("dark"),
			Vector3(-11.2 + float(i) * 1.72, 1.32, 8.6))
	for i in 8:
		lib.cyl(g, "廊柱_%d" % i, 0.19, 0.19, 3.6, _mat("dark"), Vector3(-10.0 + float(i) * 2.85, 2.8, 8.4), 6)
	for i in 5:
		lib.box(g, "障子_%d" % i, Vector3(3.4, 2.8, 0.08),
			lib.flat_mat("shoji", Color(0.94, 0.93, 0.88), 0.9),
			Vector3(-8.6 + float(i) * 4.3, 2.25, 6.05))
		lib.box(g, "障子框_%d" % i, Vector3(3.6, 0.14, 0.12), _mat("dark"),
			Vector3(-8.6 + float(i) * 4.3, 3.72, 6.05))
	lib.gable_roof(g, 5.2, 26.0, 16.0, 0.52, 0.4, _mat("kawara"), _mat("plaster", 0))
	# 向拜（正面突出的唐破風式門廊）—— 參考圖最有辨識度的一件
	lib.box(g, "向拜屋根", Vector3(7.4, 0.3, 3.4), _mat("kawara"), Vector3(0, 4.6, 8.0))
	for sd in [-1.0, 1.0]:
		lib.cyl(g, "向拜柱_%d" % int(sd + 1), 0.22, 0.24, 4.4, _mat("dark"),
			Vector3(sd * 3.2, 2.2, 9.2), 8)
	lib.box(g, "梵鐘架", Vector3(2.6, 0.3, 2.6), _mat("dark"), Vector3(13.0, 3.4, 6.0))
	lib.cyl(g, "梵鐘", 0.62, 0.78, 1.5, lib.pbr("bonsho", "stone_wall", 0.6, Color(0.52, 0.58, 0.52)),
		Vector3(13.0, 2.4, 6.0), 12)
	_collide(g, Vector3(22.4, 7.0, 12.4))
	_claim(cx, cz, 25.0, 15.0, "blk_terakoya")
	# 前庭：手水缽與立札
	lib.box(g, "立札", Vector3(1.6, 1.1, 0.1), _mat("wood"), Vector3(-8.0, 1.3, 10.5))
	lib.cyl(g, "手水缽", 0.7, 0.75, 0.7, _mat("stone"), Vector3(9.0, 0.35, 10.0), 10)
	_blk_compound(parent, bx, bz)

## 稗田邸：土塀圍院 + 表門 + 主屋 + 長廊 + 庭園水池與楓樹（THBWiki 考據）
func _blk_hieda(parent: Node, bx: float, bz: float) -> void:
	# 站在整塊地的最低點：v7 用中心點高度，體檢量出主屋離地 1.68m
	var gu := _ground_under(bx, bz, BLOCK_W, BLOCK_D)
	var spread: float = float(gu[1])
	var g := Node3D.new()
	g.position = Vector3(bx, gu[0], bz)
	lib.add(parent, g, "稗田邸")
	var hw := BLOCK_W * 0.5 - 1.0
	var hd := BLOCK_D * 0.5 - 1.0
	# 圍牆（南面留門）
	for w in [[0.0, -hd, hw * 2.0, true], [-hw, 0.0, hd * 2.0, false], [hw, 0.0, hd * 2.0, false],
			[-hw * 0.62, hd, hw * 0.76, true], [hw * 0.62, hd, hw * 0.76, true]]:
		# 牆身往下加深「高差 + 0.3」，坡地上才不會有一段懸空
		# 稗田邸的圍牆是**築地塀**規格：腰石垣 + 白牆 + 定規筋 + 兩坡瓦頂。
		# 使用者看參考圖後說地標的圍牆比例要放大才有氣勢 —— 從 2.2m 拉到 3.1m。
		var wfoot := spread + 0.3
		var wl: float = float(w[2])
		var alx: bool = bool(w[3])
		lib.box(g, "腰石垣_%d_%d" % [int(w[0]), int(w[1])],
			Vector3(wl if alx else 0.92, 0.95 + wfoot, 0.92 if alx else wl), _mat("stone"),
			Vector3(w[0], 0.47 - wfoot * 0.5, w[1]))
		lib.box(g, "築地塀_%d_%d" % [int(w[0]), int(w[1])],
			Vector3(wl if alx else 0.62, 2.15, 0.62 if alx else wl), _mat("plaster", 0),
			Vector3(w[0], 2.02, w[1]))
		for k in 3:
			lib.box(g, "定規筋_%d_%d_%d" % [int(w[0]), int(w[1]), k],
				Vector3(wl if alx else 0.70, 0.07, 0.70 if alx else wl), _mat("stone"),
				Vector3(w[0], 2.68 - float(k) * 0.22, w[1]))
		for sd in [-1.0, 1.0]:
			var sl := lib.box(g, "塀屋根_%d_%d_%d" % [int(w[0]), int(w[1]), int(sd + 1)],
				Vector3((wl + 0.3) if alx else 0.82, 0.14, 0.82 if alx else (wl + 0.3)),
				_mat("kawara"),
				Vector3(w[0] + (0.0 if alx else sd * 0.34), 3.26, w[1] + (sd * 0.34 if alx else 0.0)))
			if alx:
				sl.rotation.x = sd * -0.42
			else:
				sl.rotation.z = sd * 0.42
		lib.box(g, "棟瓦_%d_%d" % [int(w[0]), int(w[1])],
			Vector3((wl + 0.3) if alx else 0.28, 0.2, 0.28 if alx else (wl + 0.3)), _mat("kawara"),
			Vector3(w[0], 3.4, w[1]))
		_collide(g, Vector3(wl if alx else 0.95, 3.5, 0.95 if alx else wl), Vector3(w[0], 0, w[1]))
	# 表門（藥醫門）
	for sx in [-1, 1]:
		lib.box(g, "門柱_%d" % (sx + 1), Vector3(0.55, 3.2, 0.55), _mat("dark"), Vector3(float(sx) * 2.6, 1.6, hd))
	lib.box(g, "門樑", Vector3(6.0, 0.45, 0.7), _mat("dark"), Vector3(0, 3.3, hd))
	lib.box(g, "門屋根", Vector3(7.2, 0.24, 2.0), _mat("kawara"), Vector3(0, 3.7, hd))
	# 主屋
	var hfoot := spread + 0.4
	lib.box(g, "主屋基壇", Vector3(19.0, 0.55 + hfoot, 13.0), _mat("stone"), Vector3(-3.0, 0.28 - hfoot * 0.5, -7.0))
	lib.box(g, "主屋", Vector3(17.5, 4.0, 11.5), _mat("plaster"), Vector3(-3.0, 2.55, -7.0))
	lib.box(g, "緣側", Vector3(18.4, 0.26, 2.0), _mat("wood"), Vector3(-3.0, 0.68, -0.8))
	lib.gable_roof(g, 4.55, 20.0, 14.0, 0.5, 0.32, _mat("kawara"), _mat("plaster"), Vector3(-3.0, 0, -7.0))
	_collide(g, Vector3(17.9, 6.2, 11.9), Vector3(-3.0, 0, -7.0))
	# 長廊（連到東側的離れ）
	lib.box(g, "長廊", Vector3(2.4, 0.24, 14.0), _mat("wood"), Vector3(8.0, 0.7, -2.0))
	for i in 6:
		lib.cyl(g, "廊柱_%d" % i, 0.12, 0.12, 2.4, _mat("dark"), Vector3(8.9, 1.9, -8.0 + float(i) * 2.6), 6)
	for sd2 in [-1, 1]:
		var sl2 := lib.box(g, "廊屋根_%d" % (sd2 + 1), Vector3(1.9, 0.16, 14.4), _mat("kawara"),
			Vector3(8.0 + float(sd2) * 0.85, 3.15, -2.0))
		sl2.rotation.z = float(sd2) * -0.5
	lib.box(g, "離れ", Vector3(7.0, 3.2, 7.0), _mat("plaster"), Vector3(9.0, 1.9, -11.0))
	lib.box(g, "離れ屋根", Vector3(8.4, 0.26, 8.4), _mat("kawara"), Vector3(9.0, 3.7, -11.0))
	_collide(g, Vector3(7.2, 3.6, 7.2), Vector3(9.0, 0, -11.0))
	# 庭園：石組庭池（水面在 lib.pond_water，這裡只做石砌護岸與添景）
	# 池心在 GARDEN_POND（世界座標），換算成這個節點的本地座標
	var pl := Vector3(GARDEN_POND.x - bx, 0.0, GARDEN_POND.y - bz)
	# 護岸石組：v7 是 20 顆等角度繞一圈，遠看就是一條石頭項鍊。
	# 日式庭園的石組是「數顆一群、群與群之間留白」，留白處鋪州濱（小卵石）。
	var shore := lib.pond_shore_r(GARDEN_POND_R, GARDEN_POND_SINK, GARDEN_POND_DEPTH)
	# 玉石的色差交給 _mat("cobble", -1) 的四個色調變體（隨機挑），
	# 不再用 rock_mat / rock_mat_dry —— 那兩個是配稜角岩塊的。
	# 石頭要坐在**自己腳下**的地面上。這棟宅子的原點是整塊地的基準高度，
	# 池邊的地已經往下挖了 —— 照原點擺，石頭會浮在水面上像紙片。
	var rock_y := func(wx: float, wz: float, sink: float) -> float:
		return height_at(wx, wz) - g.position.y - sink
	# ── 石組：日本庭園的石不是均勻繞一圈，是「三尊石」的組法 ──
	# 使用者：「這個池塘的石頭很醜」→「設計個有藝術性的池塘出來」。
	# v15 是等角度撒滿一圈的扁石頭，看起來像一圈灰色麵包。真正的石組是：
	#   ・**主石立起來**（縦石），高過水面，一組只有一顆
	#   ・旁邊配 1~2 顆矮的臥石（横石）
	#   ・組與組之間**大片留白**，留白處鋪州濱（細卵石灘）
	#   ・數量取奇數（三・五・七）
	var rk_i := 0
	var groups := 5                                   # 奇數
	var g_ang: Array[float] = []
	var a0 := lib.rr(0.0, TAU)
	for gi in groups:
		# 不等角：黃金角的擾動，避免五顆平均分佈（那又變成項鍊）
		g_ang.append(a0 + float(gi) * TAU / float(groups) + lib.rr(-0.34, 0.34))
	for gi in groups:
		var ga: float = g_ang[gi]
		var upright: bool = gi % 2 == 0               # 隔一組立一顆
		var members := 2 + (gi % 2)
		for k in members:
			var a := ga + float(k) * lib.rr(0.055, 0.10) * (1.0 if k % 2 == 0 else -1.0)
			var rr3: float = shore * lib.rr(0.97, 1.09)
			var wx: float = bx + pl.x + cos(a) * rr3
			var wz: float = bz + pl.z + sin(a) * rr3
			var rk := MeshInstance3D.new()
			var main := k == 0
			# 主石：立起來（y 拉長、xz 收窄）。配石：臥著。
			var sc: float = lib.rr(0.75, 1.15) if main else lib.rr(0.42, 0.72)
			rk.mesh = lib.blob_mesh(rk_i * 7 + 3,
				lib.rr(1.15, 1.55) if (main and upright) else lib.rr(0.42, 0.62),
				lib.rr(0.20, 0.34))
			rk.material_override = _mat("cobble", -1)
			rk.position = Vector3(pl.x + cos(a) * rr3,
				rock_y.call(wx, wz, sc * (0.18 if (main and upright) else 0.34)),
				pl.z + sin(a) * rr3)
			rk.scale = Vector3(sc * lib.rr(0.72, 0.95), sc * lib.rr(0.9, 1.35),
				sc * lib.rr(0.72, 0.95)) if (main and upright) \
				else Vector3(sc * lib.rr(1.0, 1.4), sc * lib.rr(0.55, 0.8), sc * lib.rr(1.0, 1.4))
			rk.rotation = Vector3(lib.rr(-0.18, 0.18), lib.rr(0.0, TAU), lib.rr(-0.18, 0.18))
			lib.add(g, rk, "石組%d_%s%d" % [gi, "主石" if main else "添石", k])
			rk_i += 1
	# ── 州濱（すはま）：兩組石之間的留白鋪細卵石，一路鋪進淺水 ──
	# 這是庭池最「有藝術性」的一段 —— 硬邊變成漸層的灘。
	for gi in groups:
		var a_lo: float = g_ang[gi] + 0.28
		var a_hi: float = g_ang[(gi + 1) % groups] + (TAU if gi == groups - 1 else 0.0) - 0.28
		if a_hi - a_lo < 0.25:
			continue
		var np := int((a_hi - a_lo) * 9.0)
		for k2 in np:
			var a3: float = a_lo + (a_hi - a_lo) * (float(k2) + 0.5) / float(np)
			for band in 3:                            # 三圈：岸上、水際、淺水
				var pr: float = shore * (1.12 - float(band) * 0.11) * lib.rr(0.98, 1.02)
				var sc2 := lib.rr(0.10, 0.24) * (1.0 - float(band) * 0.15)
				var pb := MeshInstance3D.new()
				pb.mesh = lib.blob_mesh(rk_i * 13 + k2 * 5 + band * 3 + 11, lib.rr(0.30, 0.46), 0.14)
				pb.material_override = _mat("cobble", -1)
				var pwx: float = bx + pl.x + cos(a3) * pr
				var pwz: float = bz + pl.z + sin(a3) * pr
				pb.position = Vector3(pl.x + cos(a3) * pr,
					rock_y.call(pwx, pwz, sc2 * 0.62), pl.z + sin(a3) * pr)
				pb.scale = Vector3(sc2 * lib.rr(1.1, 1.5), sc2 * lib.rr(0.5, 0.75),
					sc2 * lib.rr(1.1, 1.5))
				pb.rotation.y = lib.rr(0.0, TAU)
				lib.add(g, pb, "州濱_%d" % rk_i)
				rk_i += 1
	# ── 睡蓮：只鋪在一側，不要撒滿（滿池浮葉是水草不是庭園）──
	var lily_a := g_ang[1] + lib.rr(-0.3, 0.3)
	var pad := lib.tuft_mesh(6, 0.26, 0.30, Color(0.16, 0.30, 0.14), Color(0.28, 0.46, 0.20))
	for i in 11:
		var pa := lily_a + lib.rr(-0.85, 0.85)
		var pd: float = shore * lib.rr(0.30, 0.78)
		var lp := MeshInstance3D.new()
		lp.mesh = pad
		lp.position = Vector3(pl.x + cos(pa) * pd,
			rock_y.call(bx + pl.x + cos(pa) * pd, bz + pl.z + sin(pa) * pd,
				GARDEN_POND_SINK - 0.04),
			pl.z + sin(pa) * pd)
		lp.scale = Vector3.ONE * lib.rr(0.7, 1.3)
		lp.rotation.y = lib.rr(0.0, TAU)
		lib.add(g, lp, "睡蓮_%d" % i)
	# ── 菖蒲：只長在州濱那幾段的水際，不繞整圈 ──
	var iris := lib.tuft_mesh(7, 0.70, 0.10, Color(0.12, 0.26, 0.10), Color(0.34, 0.54, 0.20))
	for i in 16:
		var ia := g_ang[int(lib.rand() * float(groups))] + lib.rr(0.35, 1.1)
		var ir: float = shore * lib.rr(0.96, 1.06)
		var ib := MeshInstance3D.new()
		ib.mesh = iris
		ib.position = Vector3(pl.x + cos(ia) * ir,
			rock_y.call(bx + pl.x + cos(ia) * ir, bz + pl.z + sin(ia) * ir, 0.05),
			pl.z + sin(ia) * ir)
		ib.scale = Vector3.ONE * lib.rr(0.7, 1.25)
		ib.rotation.y = lib.rr(0.0, TAU)
		lib.add(g, ib, "菖蒲_%d" % i)
	# 沢飛石（橫過池面的踏石）拿掉了：這個池只有 9m，踏石橫過去佔滿水面，
	# 而且從岸上看就是幾塊石頭浮在水上 —— 反效果。庭池要留**空的水面**。
	print("garden pond rocks: ", rk_i)
	for i in 3:                                    # 池中的三尊石組
		var a2 := float(i) / 3.0 * TAU + 0.7
		var d2: float = shore * lib.rr(0.25, 0.5)
		var sc3 := lib.rr(0.6, 1.1)
		var rk3 := MeshInstance3D.new()
		rk3.mesh = lib.blob_mesh(i * 29 + 5, lib.rr(0.6, 0.9), lib.rr(0.20, 0.34))
		rk3.material_override = _mat("cobble", -1)
		# 池中立石：從池底長上來，露出水面一截
		rk3.position = Vector3(pl.x + cos(a2) * d2,
			rock_y.call(bx + pl.x + cos(a2) * d2, bz + pl.z + sin(a2) * d2, -sc3 * 0.55),
			pl.z + sin(a2) * d2)
		# 不要拉高 1.7 倍 —— 那會把圓潤的岩石抽成尖刺，遠看像碎玻璃。
		# 日式庭園的立石是「厚實、微微前傾」，不是尖塔。
		rk3.scale = Vector3(sc3 * 0.95, sc3 * 1.05, sc3 * 0.85)
		rk3.rotation.x = lib.rr(-0.18, 0.18)
		rk3.rotation.z = lib.rr(-0.18, 0.18)
		rk3.rotation.y = lib.rr(0.0, TAU)
		lib.add(g, rk3, "立石_%d" % i)
	# 沢渡り（踏石）與石橋板
	for i in 4:
		lib.box(g, "踏石_%d" % i, Vector3(0.9, 0.35, 0.8), _mat("stone"),
			pl + Vector3(-GARDEN_POND_R * 0.7 + float(i) * GARDEN_POND_R * 0.45, -0.35, GARDEN_POND_R * 0.35)).rotation.y = lib.rr(0.0, TAU)
	# 春日燈籠（池畔）—— v8 那座「雪見型」做出來像一張四腳桌：
	# 笠是一片扁圓錐、腳細又外張、火袋懸在中間，看不出是燈籠。
	# 改成有竿（柱身）的春日型：基礎→竿→中台→火袋（開窗）→笠→寶珠，
	# 一根連續的柱子撐上去，剪影一眼就認得。
	var lz := pl + Vector3(GARDEN_POND_R + 1.9, 0, -2.2)
	var stone_l := _mat("stone", 1)
	lib.cyl(g, "燈籠基礎", 0.52, 0.62, 0.26, stone_l, lz + Vector3(0, 0.13, 0), 8)
	lib.cyl(g, "燈籠竿", 0.17, 0.20, 1.05, stone_l, lz + Vector3(0, 0.78, 0), 8)
	for r_i in 2:                                   # 竿上的節（春日燈籠的特徵）
		lib.cyl(g, "竿節_%d" % r_i, 0.23, 0.23, 0.07, stone_l,
			lz + Vector3(0, 0.52 + float(r_i) * 0.52, 0), 8)
	lib.cyl(g, "中台", 0.40, 0.30, 0.20, stone_l, lz + Vector3(0, 1.40, 0), 8)
	# 火袋：六角柱 + 四根角柱撐出「窗」的感覺（實心一塊會像石墩）
	lib.cyl(g, "火袋底", 0.36, 0.36, 0.07, stone_l, lz + Vector3(0, 1.54, 0), 6)
	for c_i in 4:
		var ca := float(c_i) / 4.0 * TAU + 0.4
		lib.box(g, "火袋柱_%d" % c_i, Vector3(0.09, 0.46, 0.09), stone_l,
			lz + Vector3(cos(ca) * 0.29, 1.80, sin(ca) * 0.29))
	lib.cyl(g, "火袋頂", 0.38, 0.36, 0.07, stone_l, lz + Vector3(0, 2.06, 0), 6)
	var kasa := MeshInstance3D.new()
	var km := CylinderMesh.new()
	km.top_radius = 0.10
	km.bottom_radius = 0.72          # v8 是 1.35 —— 比火袋寬一倍，像雨傘
	km.height = 0.34
	km.radial_segments = 6
	km.material = stone_l
	kasa.mesh = km
	kasa.position = lz + Vector3(0, 2.27, 0)
	lib.add(g, kasa, "燈籠笠")
	lib.cyl(g, "寶珠", 0.0, 0.13, 0.22, stone_l, lz + Vector3(0, 2.55, 0), 8)
	_collide(g, Vector3(1.1, 2.7, 1.1), lz)
	_claim(bx, bz, BLOCK_W + 2.0, BLOCK_D + 2.0, "blk_hieda")

## 足洗邸：荒廢的宅子（傳說中的妖怪宅）—— 土塀有缺口、屋頂塌一角
func _blk_ashiarai(parent: Node, bx: float, bz: float) -> void:
	var gu := _ground_under(bx, bz, BLOCK_W, BLOCK_D)   # 崩れ塀鋪到街區邊，footprint 要一起算
	var spread: float = float(gu[1])
	var g := Node3D.new()
	g.position = Vector3(bx, gu[0], bz)
	lib.add(parent, g, "足洗邸")
	var hw := BLOCK_W * 0.5 - 2.0
	var hd := BLOCK_D * 0.5 - 2.0
	for w in [[0.0, -hd, hw * 1.4, true], [-hw, -6.0, hd * 0.9, false], [hw, 4.0, hd * 0.8, false]]:
		var kh := lib.rr(1.2, 1.9)
		var kfoot := spread + 0.4                  # 牆腳埋進坡裡，否則整段浮著
		lib.box(g, "崩れ塀_%d" % int(w[0]),
			Vector3(w[2] if w[3] else 0.36, kh + kfoot, 0.36 if w[3] else w[2]),
			_mat("mud"), Vector3(w[0], kh * 0.5 - kfoot * 0.5, w[1]))
	var afoot := spread + 0.4
	lib.box(g, "母屋基壇", Vector3(16.0, 0.5 + afoot, 12.0), _mat("stone"), Vector3(0, 0.25 - afoot * 0.5, -2.0))
	lib.box(g, "母屋", Vector3(14.5, 3.6, 10.5), _mat("dark"), Vector3(0, 2.3, -2.0))
	lib.gable_roof(g, 4.1, 17.0, 13.0, 0.62, 0.5, _mat("thatch"), _mat("dark"), Vector3(0, 0, -2.0))
	_collide(g, Vector3(14.9, 5.4, 10.9), Vector3(0, 0, -2.0))
	# 崩れ塀 鋪到街區邊，地權要跟著放大 —— 只 claim 18×14 的話樹會長在牆裡
	_claim(bx, bz, BLOCK_W, BLOCK_D, "blk_ashiarai")

## 龍神像與基壇 —— 廣場的地標。
##
## v12 只有一尊 6.4m 的石像直接插在草地上，遠看是一根灰柱子，
## 完全沒有「這是村子的信仰中心」的份量（使用者點名要重做「龍神像與基壇」）。
## 地標要靠**基座與周邊**撐起來：三段石壇、玉垣、注連縄、常夜燈、供物台，
## 外圈再鋪一圈砂利。像本身不變大，靠層次拉出輕重。
const SHRINE_R := 7.2          # 玉垣外徑：這個值同時決定地權與淨空
func _dragon_shrine(parent: Node, cx: float, cz: float) -> void:
	var stone := _mat("stone")
	var dark := _mat("dark")
	var gu := _ground_under(cx, cz, SHRINE_R * 2.0, SHRINE_R * 2.0)
	var g := Node3D.new()
	g.position = Vector3(cx, gu[0], cz)
	lib.add(parent, g, "龍神像")

	# 砂利敷（外圈的白砂）—— 一片薄圓盤，把地標從草地上「切」出來
	lib.cyl(g, "砂利敷", SHRINE_R, SHRINE_R, 0.12,
		lib.pbr("shrine_gravel", "cobble", 0.9, Color(0.88, 0.86, 0.80)),
		Vector3(0, 0.06, 0), 24)
	# 三段石壇（下寬上窄，每段都有壓簷）
	var tiers := [[6.0, 0.42], [4.9, 0.40], [4.0, 0.38]]
	var y := 0.1
	for i in tiers.size():
		var tw: float = tiers[i][0]
		var th: float = tiers[i][1]
		lib.box(g, "石壇_%d" % i, Vector3(tw, th, tw), stone, Vector3(0, y + th * 0.5, 0))
		lib.box(g, "壇緣_%d" % i, Vector3(tw + 0.22, 0.1, tw + 0.22), stone,
			Vector3(0, y + th - 0.02, 0))
		y += th
	# 龍神像本體（glb 自帶柱與小基壇，站在最上段）
	var dstat := MeshInstance3D.new()
	dstat.mesh = lib.prop_mesh("res://assets/models/dragon_statue.glb", stone)
	dstat.position = Vector3(0, y, 0)
	dstat.rotation.y = 0.6
	lib.add(g, dstat, "像")
	# 玉垣（環繞的石柱 + 貫）
	var posts := 16
	for i in posts:
		var a := float(i) / float(posts) * TAU
		var px := cos(a) * SHRINE_R * 0.86
		var pz := sin(a) * SHRINE_R * 0.86
		var pl := lib.box(g, "玉垣柱_%d" % i, Vector3(0.24, 1.25, 0.24), stone,
			Vector3(px, 0.72, pz))
		pl.rotation.y = -a
		lib.box(g, "玉垣笠_%d" % i, Vector3(0.34, 0.1, 0.34), stone, Vector3(px, 1.39, pz))
		# 貫：接到下一根柱子（用端點畫，不手算角度 ADR-014）
		var a2 := float(i + 1) / float(posts) * TAU
		lib.strut(g, "玉垣貫_%d" % i,
			Vector3(px, 1.02, pz),
			Vector3(cos(a2) * SHRINE_R * 0.86, 1.02, sin(a2) * SHRINE_R * 0.86),
			0.055, stone, 4)
	# 正面（朝 -z，也就是朝廣場中心）留缺口當入口：把那兩根柱換成門柱
	for sd in [-1.0, 1.0]:
		lib.box(g, "門柱_%d" % int(float(sd) + 1), Vector3(0.34, 2.4, 0.34), stone,
			Vector3(float(sd) * 1.5, 1.2, -SHRINE_R * 0.86))
		lib.cyl(g, "門柱頭_%d" % int(float(sd) + 1), 0.0, 0.26, 0.3, stone,
			Vector3(float(sd) * 1.5, 2.5, -SHRINE_R * 0.86), 8)
	# 注連縄：兩根門柱之間垂下來的稻繩 + 紙垂
	var rope := lib.pbr("shimenawa", "terrain_grass", 1.6, Color(0.86, 0.80, 0.60))
	var segs := 8
	for i in segs:
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var sag := 0.42
		lib.strut(g, "注連縄_%d" % i,
			Vector3(lerpf(-1.5, 1.5, t0), 2.2 - sin(t0 * PI) * sag, -SHRINE_R * 0.86),
			Vector3(lerpf(-1.5, 1.5, t1), 2.2 - sin(t1 * PI) * sag, -SHRINE_R * 0.86),
			0.13 - absf(t0 - 0.5) * 0.08, rope, 6)
	for i in 3:
		var sx2 := -0.9 + float(i) * 0.9
		lib.box(g, "紙垂_%d" % i, Vector3(0.16, 0.42, 0.02),
			lib.flat_mat("shide", Color(0.97, 0.97, 0.95), 0.9),
			Vector3(sx2, 1.62, -SHRINE_R * 0.86 - 0.06))
	# 常夜燈（兩座石燈籠，站在砂利圈上）
	for sd2 in [-1.0, 1.0]:
		var lx: float = sd2 * 4.6
		var lz := -SHRINE_R * 0.55
		lib.box(g, "燈籠基_%d" % int(float(sd2) + 1), Vector3(0.9, 0.24, 0.9), stone, Vector3(lx, 0.24, lz))
		lib.cyl(g, "燈籠竿_%d" % int(float(sd2) + 1), 0.16, 0.19, 1.25, stone, Vector3(lx, 0.98, lz), 8)
		lib.box(g, "燈籠中台_%d" % int(float(sd2) + 1), Vector3(0.62, 0.16, 0.62), stone, Vector3(lx, 1.68, lz))
		lib.box(g, "火袋_%d" % int(float(sd2) + 1), Vector3(0.52, 0.6, 0.52),
			lib.flat_mat("toro_light", Color(0.98, 0.88, 0.62), 0.8, Color(0.9, 0.66, 0.34)),
			Vector3(lx, 2.06, lz))
		for ci in 4:                                   # 火袋的四根角柱
			var ca := float(ci) / 4.0 * TAU + PI * 0.25
			lib.box(g, "火袋柱_%d_%d" % [int(float(sd2) + 1), ci], Vector3(0.1, 0.62, 0.1), dark,
				Vector3(lx + cos(ca) * 0.26, 2.06, lz + sin(ca) * 0.26))
		lib.cyl(g, "燈籠笠_%d" % int(float(sd2) + 1), 0.12, 0.62, 0.34, stone, Vector3(lx, 2.53, lz), 6)
		lib.cyl(g, "寶珠_%d" % int(float(sd2) + 1), 0.0, 0.14, 0.24, stone, Vector3(lx, 2.8, lz), 8)
	# 供物台（門前的石桌，擺著酒瓶）
	lib.box(g, "供物台", Vector3(1.5, 0.16, 0.7), stone, Vector3(0, 0.72, -SHRINE_R * 0.86 - 0.9))
	for sd3 in [-1.0, 1.0]:
		lib.box(g, "供物台脚_%d" % int(float(sd3) + 1), Vector3(0.22, 0.64, 0.5), stone,
			Vector3(float(sd3) * 0.55, 0.34, -SHRINE_R * 0.86 - 0.9))
	for i in 2:
		lib.cyl(g, "御神酒_%d" % i, 0.06, 0.11, 0.34,
			lib.flat_mat("sake_bottle", Color(0.90, 0.90, 0.86), 0.35),
			Vector3(-0.3 + float(i) * 0.6, 0.97, -SHRINE_R * 0.86 - 0.9), 8)

	# 碰撞：像的柱子 + 石壇（玉垣讓人走得過去，不然廣場會被切成兩半）
	_collide(g, Vector3(4.2, 8.4, 4.2))
	_claim(cx, cz, SHRINE_R * 2.0, SHRINE_R * 2.0, "龍神像")

## 市集街區：不設圍牆的開放廣場（攤位、龍神像）
func _blk_market(parent: Node, bx: float, bz: float) -> void:
	var wood := _mat("wood")
	var stone := _mat("stone")
	# 龍神像（THBWiki 設施清單）—— Blender 雕的完整龍（曲面龍身、五爪、
	# 鬃鰭、角鬚、龍珠、石柱與基壇），不再是方塊堆。
	_dragon_shrine(parent, bx - 12.0, bz - 10.0)
	# ── 屋台（攤位）──
	# v9 是「四支腳撐一塊純色板」，遠看像塑膠野餐桌。真正的屋台有：
	# 斜的布篷（會下垂）、撐篷的斜柱、檯面上的貨、垂下來的暖簾、
	# 腳邊的木箱與草蓆。而且要立在**掃出來的土間**上，不是直接插在草地。
	# 布篷的顏色要壓下來 —— 純色高飽和的一大片，從上面看就只是色塊。
	# 而且要有織紋（借 plaster 那張當布紋），不然是塑膠板。
	var cloths := [Color(0.52, 0.30, 0.27), Color(0.30, 0.35, 0.45),
		Color(0.58, 0.50, 0.32), Color(0.34, 0.42, 0.33), Color(0.46, 0.40, 0.50)]
	var goods := [Color(0.78, 0.62, 0.34), Color(0.52, 0.30, 0.24), Color(0.40, 0.52, 0.30),
		Color(0.86, 0.80, 0.62), Color(0.30, 0.34, 0.40)]
	var earth := lib.pbr("市場土間", "terrain_path", 0.30, Color(0.92, 0.88, 0.80))
	var placed := 0
	# ⚠ 攤位不能撒成 4×3 的方陣 —— v12 就是這樣，從空中看是停車場。
	# 市集是「兩排面對面夾一條走道」，客人走中間、攤販站兩側。
	# 走道沿 x，攤位的正面（+z 那一面，有暖簾與篷垂）一律朝走道。
	const AISLE_Z := 2.0          # 走道在街區座標的 z
	const AISLE_HALF := 4.6       # 走道半寬：兩排攤位之間留 9.2m
	for i in 12:
		var row := i % 2                                  # 0 = 南排（朝 +z）1 = 北排（朝 -z）
		var k0 := i / 2
		var px := bx - 13.0 + float(k0) * 5.4 + lib.rr(-0.9, 0.9)
		var pz := bz + AISLE_Z + (AISLE_HALF if row == 1 else -AISLE_HALF) + lib.rr(-0.4, 0.4)
		if not _free(px, pz, 4.2, 3.4, 0.4):
			continue
		placed += 1
		var gu := _ground_under(px, pz, 3.6, 3.0)
		var st := Node3D.new()
		st.position = Vector3(px, gu[0], pz)
		st.rotation.y = (PI if row == 1 else 0.0) + lib.rr(-0.10, 0.10)
		lib.add(parent, st, "屋台_%d" % i)
		# 掃過的土間（攤位腳下的地是踩實的，不是草）
		lib.box(st, "土間", Vector3(4.4, 0.10, 3.6), earth, Vector3(0, 0.03, 0.2))
		# 四支腳 + 檯面 + 檯面下的橫撐
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				lib.strut(st, "腳_%d%d" % [int(sx + 1), int(sz + 1)],
					Vector3(sx * 1.3, 0.06, sz * 0.85), Vector3(sx * 1.3, 0.95, sz * 0.85),
					0.055, wood, 5)
			lib.strut(st, "貫_%d" % int(sx + 1),
				Vector3(sx * 1.3, 0.34, -0.85), Vector3(sx * 1.3, 0.34, 0.85), 0.04, wood, 4)
		lib.box(st, "檯面", Vector3(2.9, 0.10, 1.9), _mat("wood", i % 4), Vector3(0, 1.0, 0))
		# 支篷的斜柱（後高前低，布才會斜）
		var back_h := 2.45
		var front_h := 2.05
		for sx2 in [-1.0, 1.0]:
			lib.strut(st, "篷柱後_%d" % int(sx2 + 1),
				Vector3(sx2 * 1.35, 0.95, -0.95), Vector3(sx2 * 1.4, back_h, -1.05), 0.05, wood, 5)
			lib.strut(st, "篷柱前_%d" % int(sx2 + 1),
				Vector3(sx2 * 1.35, 0.95, 0.95), Vector3(sx2 * 1.4, front_h, 1.15), 0.05, wood, 5)
		var base_c: Color = cloths[i % cloths.size()]
		var cm := lib.pbr("屋台布_%d" % (i % 5), "plaster", 1.8, base_c)
		# 條紋：屋台的布篷幾乎都是縞（直條紋），單色一片太假
		var cm2 := lib.pbr("屋台布縞_%d" % (i % 5), "plaster", 1.8,
			Color(base_c.r * 0.62 + 0.30, base_c.g * 0.62 + 0.30, base_c.b * 0.62 + 0.30))
		# 布篷做成兩片，中間下垂一點（一整片平板一看就是塑膠）
		# 篷布切成 6 條直條紋、前後兩段（中間微微下垂）
		var strips := 6
		for k in 2:
			var t := float(k)
			var sag := -0.10 if k == 0 else 0.0
			for sI in strips:
				var sw := 3.3 / float(strips)
				var cloth := lib.box(st, "篷_%d_%d" % [k, sI], Vector3(sw * 0.99, 0.05, 1.25),
					cm if sI % 2 == 0 else cm2,
					Vector3(-1.65 + (float(sI) + 0.5) * sw,
						lerpf(back_h, front_h, 0.25 + t * 0.5) + sag, -0.55 + t * 1.1))
				cloth.rotation.x = 0.20 + t * 0.06
		# 前緣垂下來的布邊
		var skirt := lib.box(st, "篷垂", Vector3(3.3, 0.34, 0.04), cm2, Vector3(0, front_h - 0.12, 1.18))
		skirt.rotation.x = 0.1
		# 檯面上的貨（三堆不同顏色，才看得出在賣東西）
		for k2 in 3:
			var gmat := lib.flat_mat("貨_%d" % ((i + k2) % 5), goods[(i + k2) % goods.size()], 0.9)
			var gx2 := -0.95 + float(k2) * 0.95
			if lib.rand() < 0.5:
				for k3 in 3:                       # 疊起來的圓形（果物・團子）
					lib.cyl(st, "貨_%d_%d" % [k2, k3], 0.16, 0.18, 0.12, gmat,
						Vector3(gx2 + lib.rr(-0.05, 0.05), 1.11 + float(k3) * 0.12, lib.rr(-0.3, 0.3)), 8)
			else:
				lib.box(st, "貨箱_%d" % k2, Vector3(0.6, 0.26, 0.5), gmat,
					Vector3(gx2, 1.18, lib.rr(-0.25, 0.25)))
		# 暖簾（垂在攤位側邊）
		if lib.rand() < 0.6:
			var nx := 1.42 * (1.0 if lib.rand() < 0.5 else -1.0)
			for k4 in 3:
				lib.box(st, "暖簾_%d" % k4, Vector3(0.04, 0.6, 0.42),
					cm if k4 % 2 == 0 else cm2, Vector3(nx, 1.72, -0.5 + float(k4) * 0.5))
		# 腳邊的木箱與草蓆
		lib.box(st, "木箱", Vector3(0.75, 0.48, 0.58), _mat("wood", (i + 1) % 4),
			Vector3(lib.rr(-1.1, 1.1), 0.29, 1.45))
		if lib.rand() < 0.5:
			lib.box(st, "莚", Vector3(1.5, 0.05, 1.0),
				lib.pbr("莚", "terrain_grass", 1.5, Color(0.80, 0.70, 0.46)),
				Vector3(lib.rr(-0.6, 0.6), 0.09, 1.7))
		_collide(st, Vector3(3.0, 1.1, 2.2))
		_claim(px, pz, 4.6, 3.8, "blk_market")
	# 水井與高札場
	var wp := Vector2(bx + 13.0, bz + 8.0)
	var well := Node3D.new()
	well.position = Vector3(wp.x, height_at(wp.x, wp.y), wp.y)
	lib.add(parent, well, "水井")
	lib.cyl(well, "井筒", 1.15, 1.25, 1.0, stone, Vector3(0, 0.5, 0), 12)
	lib.cyl(well, "井口", 0.95, 0.95, 0.05, lib.flat_mat("water_dark", Color(0.07, 0.12, 0.15), 0.1),
		Vector3(0, 1.0, 0), 12)
	for sd in [-1, 1]:
		lib.cyl(well, "支柱_%d" % (sd + 1), 0.09, 0.09, 2.6, _mat("dark"), Vector3(float(sd) * 1.0, 1.3, 0), 6)
	lib.box(well, "橫木", Vector3(2.4, 0.14, 0.14), _mat("dark"), Vector3(0, 2.55, 0))
	lib.box(well, "桶", Vector3(0.4, 0.4, 0.4), wood, Vector3(0, 1.9, 0))
	# 井屋根（參考圖那個有屋頂的井）
	lib.gable_roof(well, 2.62, 3.0, 2.6, 0.5, 0.16, _mat("kawara"), wood)
	lib.cyl(well, "滑車", 0.16, 0.16, 0.12, _mat("dark"), Vector3(0, 2.42, 0), 8)
	_collide(well, Vector3(2.5, 1.2, 2.5))
	# 井有屋頂（3.0×2.6）與吊桶架，地權要涵蓋整組 —— v9 只 claim 3×3，
	# 生活雜物就擺進井屋裡了
	_claim(wp.x, wp.y, 5.2, 5.0, "blk_market")
	var np := Vector2(bx + 14.0, bz - 12.0)
	var notice := Node3D.new()
	notice.position = Vector3(np.x, height_at(np.x, np.y), np.y)
	notice.rotation.y = -0.5
	lib.add(parent, notice, "高札場")
	for sd2 in [-1, 1]:
		lib.box(notice, "柱_%d" % (sd2 + 1), Vector3(0.18, 2.6, 0.18), _mat("dark"), Vector3(float(sd2) * 1.2, 1.3, 0))
	lib.box(notice, "板", Vector3(2.7, 1.5, 0.1), wood, Vector3(0, 2.0, 0))
	lib.box(notice, "屋根", Vector3(3.1, 0.12, 0.6), _mat("kawara"), Vector3(0, 2.85, 0))
	_collide(notice, Vector3(2.8, 2.8, 0.6))
	_claim(np.x, np.y, 3.2, 1.4, "blk_market")
	print("market stalls: ", placed)

## 火見櫓街區：木塔 + 番屋（消防小屋）
## 火見櫓（望火樓）。
##
## v9 的做法是「每層各自放四根傾斜的圓柱」—— 每層的傾角是各自算的，
## 層與層之間對不起來，遠看整座塔像散掉的鷹架（使用者：「設計不良」）。
## 正解是把柱子當成**一根從地面直通塔頂的連續構件**，用 lib.strut 給端點，
## 讓程式去算位置與旋轉；橫材與斜撐也一樣用端點定義，接點自然吻合。
func _blk_tower(parent: Node, bx: float, bz: float) -> void:
	var dark := _mat("dark", 2)
	var wood := _mat("wood", 1)
	var tgu := _ground_under(bx, bz, 8.0, 8.0)
	var f := Node3D.new()
	f.position = Vector3(bx, tgu[0], bz)
	lib.add(parent, f, "火見櫓")

	var H := 13.2                                  # 塔身高（不含屋頂）
	var R0 := 2.9                                  # 地面的半跨（外八字）
	var R1 := 1.15                                 # 塔頂的半跨
	var LEV := [0.0, 3.5, 6.9, 10.1, H]            # 五個節點高度
	var corner := func(lvl: float, i: int) -> Vector3:
		var t := lvl / H
		var r: float = lerpf(R0, R1, t)
		var a := float(i) * PI * 0.5 + PI * 0.25
		return Vector3(cos(a) * r, lvl, sin(a) * r)

	# ── 四根主柱：一根到頂，不分段 ──
	for i in 4:
		lib.strut(f, "主柱_%d" % i, corner.call(0.0, i), corner.call(H, i),
			0.17, dark, 6, 0.11)
	# ── 各層的水平橫材（貫）──
	for li in range(1, LEV.size()):
		var y: float = LEV[li]
		for i in 4:
			lib.strut(f, "貫_%d_%d" % [li, i], corner.call(y, i), corner.call(y, (i + 1) % 4),
				0.075, dark, 5)
	# ── 斜撐（筋交い）：每一面每一層打一根對角，這才是塔不會晃的原因 ──
	for li in range(LEV.size() - 1):
		var y0: float = LEV[li]
		var y1: float = LEV[li + 1]
		for i in 4:
			var j := (i + 1) % 4
			# 交錯方向，看起來才像真的桁架
			if (li + i) % 2 == 0:
				lib.strut(f, "筋交_%d_%d" % [li, i], corner.call(y0, i), corner.call(y1, j), 0.055, dark, 5)
			else:
				lib.strut(f, "筋交_%d_%d" % [li, i], corner.call(y0, j), corner.call(y1, i), 0.055, dark, 5)

	# ── 望樓（頂上的平台）──
	var pf := 1.72
	lib.box(f, "樓板", Vector3(pf * 2.0, 0.18, pf * 2.0), wood, Vector3(0, H + 0.09, 0))
	for i in 4:                                    # 平台的托木（挑出去撐住樓板）
		var a2 := float(i) * PI * 0.5 + PI * 0.25
		lib.strut(f, "腕木_%d" % i,
			Vector3(cos(a2) * R1 * 0.4, H - 1.1, sin(a2) * R1 * 0.4),
			Vector3(cos(a2) * pf * 1.02, H, sin(a2) * pf * 1.02), 0.07, dark, 5)
	# 欄杆：四根角柱 + 上下兩道橫木（v9 是四片薄板，近看是紙片）
	for i in 4:
		var p0 := Vector3(cos(float(i) * PI * 0.5 + PI * 0.25) * pf * 0.98, H + 0.18,
			sin(float(i) * PI * 0.5 + PI * 0.25) * pf * 0.98)
		lib.strut(f, "欄杆柱_%d" % i, p0, p0 + Vector3(0, 0.92, 0), 0.055, wood, 5)
	for hgt in [0.5, 0.9]:
		for i in 4:
			var a3 := float(i) * PI * 0.5 + PI * 0.25
			var a4 := float((i + 1) % 4) * PI * 0.5 + PI * 0.25
			lib.strut(f, "欄杆貫_%d_%d" % [int(hgt * 10), i],
				Vector3(cos(a3) * pf * 0.98, H + 0.18 + hgt, sin(a3) * pf * 0.98),
				Vector3(cos(a4) * pf * 0.98, H + 0.18 + hgt, sin(a4) * pf * 0.98), 0.045, wood, 5)
	# 屋根：四根柱撐起的小方形屋頂
	for i in 4:
		var a5 := float(i) * PI * 0.5 + PI * 0.25
		lib.strut(f, "屋根柱_%d" % i,
			Vector3(cos(a5) * pf * 0.78, H + 0.27, sin(a5) * pf * 0.78),
			Vector3(cos(a5) * pf * 0.62, H + 2.15, sin(a5) * pf * 0.62), 0.07, dark, 5)
	var roof := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.06
	rm.bottom_radius = pf * 1.42
	rm.height = 0.95
	rm.radial_segments = 4
	rm.material = _mat("kawara", 1)
	roof.mesh = rm
	roof.position = Vector3(0, H + 2.55, 0)
	roof.rotation.y = PI / 4.0
	lib.add(f, roof, "望樓屋根")
	lib.cyl(f, "露盤", 0.16, 0.22, 0.28, dark, Vector3(0, H + 3.14, 0), 6)
	# 半鐘：吊在屋簷下，加一根吊木才不會浮在空中
	lib.strut(f, "鐘吊木", Vector3(0, H + 2.05, 0.0), Vector3(0.95, H + 2.05, 0.0), 0.05, dark, 5)
	lib.strut(f, "鐘繩", Vector3(0.95, H + 2.05, 0.0), Vector3(0.95, H + 1.62, 0.0), 0.02, dark, 4)
	lib.cyl(f, "半鐘", 0.24, 0.33, 0.52,
		lib.flat_mat("bell", Color(0.40, 0.34, 0.20), 0.35), Vector3(0.95, H + 1.35, 0.0), 10)

	# ── 梯子：從地面爬到望樓（沒有梯子的話這座塔沒人上得去）──
	var lx := R0 * 0.72
	for sd in [-1.0, 1.0]:
		lib.strut(f, "梯柱_%d" % int(sd + 1),
			Vector3(lx, 0.0, sd * 0.34), Vector3(R1 * 0.7, H, sd * 0.34), 0.055, wood, 5)
	var rungs := int(H / 0.42)
	for i in rungs:
		var t2 := (float(i) + 0.5) / float(rungs)
		var rx: float = lerpf(lx, R1 * 0.7, t2)
		lib.strut(f, "踏桟_%d" % i, Vector3(rx, t2 * H, -0.34), Vector3(rx, t2 * H, 0.34), 0.035, wood, 4)

	_collide(f, Vector3(R0 * 2.0, 3.2, R0 * 2.0))
	_claim(bx, bz, 9.0, 9.0, "blk_tower")
	# 番屋
	var qx := bx + 12.0
	var qz := bz + 10.0
	if _free(qx, qz, 10.0, 7.0, 0.6):
		_longhouse(parent, "番屋", qx, qz, 9.0, 6.5, true, 1, "kawara")
	_blk_compound(parent, bx, bz)

# ── 石橋 ──
func _build_bridge() -> void:
	var stone := _mat("stone")
	var g := Node3D.new()
	var by := height_at(BRIDGE.x, BRIDGE.y) + RIVER_DEPTH + 0.5
	g.position = Vector3(BRIDGE.x, by, BRIDGE.y)
	lib.add(lib.root, g, "石橋")
	var span := RIVER_HALF * 2.0 + 10.0
	lib.box(g, "橋面", Vector3(span, 0.5, 5.6), stone, Vector3(0, 0, 0))
	for sd in [-1, 1]:
		lib.box(g, "欄干_%d" % (sd + 1), Vector3(span, 0.75, 0.4), stone, Vector3(0, 0.6, float(sd) * 2.6))
		for i in 5:
			lib.box(g, "擬寶珠_%d_%d" % [sd + 1, i], Vector3(0.45, 1.0, 0.45), stone,
				Vector3(-span * 0.5 + float(i) * span * 0.25, 0.75, float(sd) * 2.6))
	for sd2 in [-1, 1]:
		lib.box(g, "橋台_%d" % (sd2 + 1), Vector3(3.2, RIVER_DEPTH + 1.4, 5.6), stone,
			Vector3(float(sd2) * (span * 0.5 - 1.3), -(RIVER_DEPTH + 1.4) * 0.5, 0))
	var body := StaticBody3D.new()
	g.add_child(body)
	body.owner = lib.root
	for c in [[Vector3(span, 0.5, 5.6), Vector3(0, 0, 0)],
			[Vector3(span, 0.8, 0.4), Vector3(0, 0.65, 2.6)],
			[Vector3(span, 0.8, 0.4), Vector3(0, 0.65, -2.6)]]:
		var shape := CollisionShape3D.new()
		var bx2 := BoxShape3D.new()
		bx2.size = c[0]
		shape.shape = bx2
		shape.position = c[1]
		body.add_child(shape)
		shape.owner = lib.root

# ── 石垣護岸 + 睡蓮 + 岸邊松（參考圖：《求聞編年史》的水路） ──
func _build_canal_banks() -> void:
	var g := lib.add(lib.root, Node3D.new(), "水路護岸")
	var stone := _mat("stone")
	# 石垣：沿水路兩側砌牆，從河床砌到岸面
	var n := 0
	for k in CANAL.size() - 1:
		var a := Vector2(CANAL[k][0], CANAL[k][1])
		var b := Vector2(CANAL[k + 1][0], CANAL[k + 1][1])
		var len_ab := a.distance_to(b)
		var dir := (b - a).normalized()
		var nrm := dir.orthogonal()
		var steps := int(len_ab / 6.0)
		for i in steps:
			var t := (float(i) + 0.5) / float(steps)
			var c := a.lerp(b, t)
			# 水路是**流進**大河的，護岸要在河岸邊收掉。
			# v11 一路砌到 x=236，兩道石垣直接橫過河面 ——
			# 使用者看到的「水道被牆壁擋住了」就是這個。
			if lib.poly_dist(RIVER, c.x, c.y) < RIVER_HALF + 3.0:
				continue
			for sd in [-1, 1]:
				var p := c + nrm * (CANAL_HALF + 0.35) * float(sd)
				var by := bank_h(p.x, p.y)
				var wall := lib.box(g, "石垣_%d" % n, Vector3(6.2, CANAL_DEPTH + 0.6, 0.7), stone,
					Vector3(p.x, by - (CANAL_DEPTH + 0.6) * 0.5 + 0.3, p.y))
				wall.rotation.y = -atan2(dir.y, dir.x)
				# 護岸要擋人 —— 水路的兩岸只能靠橋連通。
				# 以前是靠 main.gd 給每片 mesh 生 trimesh 才擋得住，
				# 那層拿掉之後就得自己放碰撞箱（可走性測試立刻抓到穿牆過河）。
				var wc := StaticBody3D.new()
				wall.add_child(wc)
				wc.owner = lib.root
				var wsh := CollisionShape3D.new()
				var wbx := BoxShape3D.new()
				wbx.size = Vector3(6.2, CANAL_DEPTH + 1.4, 0.7)
				wsh.shape = wbx
				wc.add_child(wsh)
				wsh.owner = lib.root
				# 岸緣的收邊石（參考圖那圈白色石帶）
				lib.box(g, "緣石_%d" % n, Vector3(6.2, 0.28, 1.1),
					lib.pbr("edge_stone", "stone_wall", 0.5, Color(1.25, 1.25, 1.2)),
					Vector3(p.x, by + 0.1, p.y)).rotation.y = -atan2(dir.y, dir.x)
				n += 1
	# ── 洗い場（かわど）：從岸面下到水邊的石階，村人在這裡洗菜洗衣 ──
	# 水路現在是一條沒有出入口的溝，兩岸只有石垣 —— 看起來像排水渠不像生活用水。
	# 每隔一段開一個缺口，這是水路最有生活感的一件事。
	var wash := 0
	for wx in [-170.0, -122.0, -70.0, -18.0, 34.0, 86.0, 138.0]:
		var side := 1.0 if fposmod(wx, 104.0) < 52.0 else -1.0
		var by := bank_h(wx, 85.0)
		var wg := Node3D.new()
		wg.position = Vector3(wx, by, 85.0 + side * (CANAL_HALF + 0.35))
		lib.add(g, wg, "洗い場_%d" % wash)
		# 石階往水裡下 4 階
		for st in 4:
			var t := float(st) + 0.5
			lib.box(wg, "洗石_%d" % st, Vector3(2.6, 0.3, 0.75), stone,
				Vector3(0, -t * 0.42, -side * (t * 0.42)))
		# 兩側的立石（擋住上下的人不會滑進水裡）
		for sd2 in [-1.0, 1.0]:
			lib.box(wg, "立石_%d" % int(sd2 + 1), Vector3(0.32, 1.0, 0.9), stone,
				Vector3(sd2 * 1.55, 0.2, -side * 0.4))
		# 洗い場前擺個桶
		lib.cyl(wg, "桶", 0.28, 0.26, 0.34, _mat("wood"), Vector3(1.0, 0.28, side * 0.9), 10)
		wash += 1

	# ── 水門（落水口）：水路在河岸前收住，靠這座石造水門洩進大河 ──
	# 沒有它的話水路就是「走到一半消失」。
	var og := Node3D.new()
	var oy := bank_h(CANAL_OUTLET.x, CANAL_OUTLET.y)
	og.position = Vector3(CANAL_OUTLET.x, oy, CANAL_OUTLET.y)
	lib.add(g, og, "水門")
	# 兩側的翼牆（八字張開，把水收進閘口）
	for sd3 in [-1.0, 1.0]:
		var wing := lib.box(og, "翼壁_%d" % int(sd3 + 1),
			Vector3(7.0, CANAL_DEPTH + 1.2, 0.8), stone,
			Vector3(2.8, -(CANAL_DEPTH + 1.2) * 0.5 + 0.5, sd3 * (CANAL_HALF + 1.4)))
		wing.rotation.y = sd3 * 0.28
	# 閘口的門框與木閘板
	for sd4 in [-1.0, 1.0]:
		lib.box(og, "門柱_%d" % int(sd4 + 1), Vector3(0.7, CANAL_DEPTH + 2.0, 0.7), stone,
			Vector3(0, -(CANAL_DEPTH + 2.0) * 0.5 + 1.2, sd4 * (CANAL_HALF - 0.6)))
	lib.box(og, "門楣", Vector3(0.8, 0.6, CANAL_HALF * 2.0), stone, Vector3(0, 2.0, 0))
	lib.box(og, "閘板", Vector3(0.24, 1.5, CANAL_HALF * 1.7), _mat("dark"), Vector3(0, 0.5, 0))
	for hw2 in 3:                                     # 閘板的橫貫
		lib.box(og, "閘貫_%d" % hw2, Vector3(0.34, 0.16, CANAL_HALF * 1.8), _mat("dark"),
			Vector3(0, 0.05 + float(hw2) * 0.55, 0))
	# 落差工：閘口外的石疊，水從這裡跌進河
	for st2 in 4:
		lib.box(og, "落差石_%d" % st2, Vector3(1.6, 0.36, CANAL_HALF * 1.9 - float(st2) * 0.5), stone,
			Vector3(1.4 + float(st2) * 1.5, -0.5 - float(st2) * 0.5, 0))
	_collide(og, Vector3(1.0, CANAL_DEPTH + 2.0, CANAL_HALF * 2.0))
	print("canal bank stones: %d、洗い場 %d、水門 1" % [n, wash])

	# 睡蓮與荷花（水面上的浮葉）
	var pad_mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 9:                                     # 圓葉（缺一角，睡蓮的特徵）
		var a0 := float(i) / 9.0 * TAU * 0.92 + 0.3
		var a1 := float(i + 1) / 9.0 * TAU * 0.92 + 0.3
		st.set_color(Color(0.24, 0.42, 0.20))
		st.add_vertex(Vector3.ZERO)
		st.set_color(Color(0.32, 0.52, 0.24))
		st.add_vertex(Vector3(cos(a0) * 0.45, 0, sin(a0) * 0.45))
		st.set_color(Color(0.32, 0.52, 0.24))
		st.add_vertex(Vector3(cos(a1) * 0.45, 0, sin(a1) * 0.45))
	for p in 5:                                     # 花瓣
		var pa := float(p) / 5.0 * TAU
		st.set_color(Color(0.98, 0.94, 0.96))
		st.add_vertex(Vector3(0.18, 0.03, 0))
		st.set_color(Color(0.96, 0.82, 0.88))
		st.add_vertex(Vector3(0.18 + cos(pa) * 0.14, 0.16, sin(pa) * 0.14))
		st.set_color(Color(0.96, 0.82, 0.88))
		st.add_vertex(Vector3(0.18 + cos(pa + 1.2) * 0.14, 0.16, sin(pa + 1.2) * 0.14))
	st.generate_normals()
	pad_mesh = st.commit()
	var pad_mat := StandardMaterial3D.new()
	pad_mat.vertex_color_use_as_albedo = true
	pad_mat.roughness = 0.85
	pad_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pad_mesh.surface_set_material(0, pad_mat)
	var pads: Array[Transform3D] = []
	var tries := 0
	while pads.size() < 190 and tries < 9000:
		tries += 1
		var x := lib.rr(-190.0, 200.0)
		var z := lib.rr(78.0, 94.0)
		var cd := lib.poly_dist(CANAL, x, z)
		if cd > CANAL_HALF * 0.8:
			continue
		if lib.rand() < 0.55:                        # 成叢生長，不要均勻散佈
			continue
		var sc := lib.rr(0.7, 1.5)
		pads.append(Transform3D(Basis(Vector3.UP, lib.rand() * TAU).scaled(Vector3(sc, sc, sc)),
			Vector3(x, minf(bank_h(x, z) - CANAL_DEPTH * 0.32,
				height_at(x, z) + CANAL_DEPTH * 0.55), z)))   # 保險：不會浮到岸上
	var pmm := MultiMeshInstance3D.new()
	pmm.multimesh = lib.make_multimesh(pad_mesh, pads, [], OUT_DIR + "gen/lilypads.res")
	pmm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lib.add(g, pmm, "睡蓮")

	# 岸邊松（參考圖：水路兩側成排的松）
	var pines: Array[Transform3D] = []
	var t2 := 0
	while pines.size() < 26 and t2 < 3000:
		t2 += 1
		var px := lib.rr(-180.0, 190.0)
		var side := 1.0 if lib.rand() < 0.5 else -1.0
		var pz := 85.0 + side * lib.rr(CANAL_HALF + 2.2, CANAL_HALF + 4.0)
		# 這裡不能用 _free —— 它會把「靠近水路」整個排除，而岸邊松
		# 本來就要種在水路旁。只檢查街道與既有佔位。
		if _path_info(px, pz)[0] < 1.2:
			continue
		var blocked := false
		for c in _cells(px, pz, 2.5, 2.5):
			if not _grid.has(c):
				continue
			var bucket: Array = _grid[c]
			for idx in bucket:
				var r: Array = _rects[idx]
				if absf(px - r[0]) < (2.5 + r[2] * 0.5) and absf(pz - r[1]) < (2.5 + r[3] * 0.5):
					blocked = true
					break
			if blocked:
				break
		if blocked:
			continue
		_claim(px, pz, 5.0, 5.0, "build_canal_banks")
		var sc2 := lib.rr(0.8, 1.3)
		pines.append(Transform3D(Basis(Vector3.UP, lib.rand() * TAU).scaled(Vector3(sc2, sc2 * lib.rr(0.8, 1.0), sc2)),
			Vector3(px, height_at(px, pz), pz)))
	var pinemm := MultiMeshInstance3D.new()
	pinemm.multimesh = lib.make_multimesh(lib.tree_mesh("res://assets/models/tree_pine_a.glb"),
		pines, [], OUT_DIR + "gen/canal_pines.res")
	lib.add(g, pinemm, "岸邊松")
	print("canal pines: ", pines.size())

# ── 自然池：不規則水岸、大小不一半埋的苔石（使用者要的「挖坑填水」）──
func _build_nature_pond() -> void:
	var g := lib.add(lib.root, Node3D.new(), "自然池畔")
	var moss := lib.rock_mat()
	var stone := _mat("stone")
	# 岩石換成 Blender 產的不規則造型（v5 之前是方板，使用者直接點出來）
	var rock_lists := [[], [], [], []]
	# 岩石帶要落在真正的水線上（水面半徑 ≈ 0.84R，拿 R 排會全部離水一大圈）
	var nshore := lib.pond_shore_r(NATURE_POND_R, NATURE_POND_SINK, NATURE_POND_DEPTH)
	for i in 46:
		var a := lib.rr(0.0, TAU)
		# 岸線本身是不規則的（跟 pond_carve 的 wobble 同一條公式）
		var rr4 := nshore * (1.0 + 0.22 * (sin(a * 3.0) * 0.6 + sin(a * 5.0 + 1.3) * 0.4))
		var d := rr4 * lib.rr(0.92, 1.22)
		var px := NATURE_POND.x + cos(a) * d
		var pz := NATURE_POND.y + sin(a) * d
		# 池畔跟村界會重疊 —— 沒檢查的話岸石會長在土塀裡
		if not _free(px, pz, 2.4, 2.4, 0.2):
			continue
		var sc := lib.rr(0.5, 1.5)
		var basis := Basis(Vector3.UP, lib.rand() * TAU).scaled(
			Vector3(sc * lib.rr(0.8, 1.3), sc * lib.rr(0.6, 1.0), sc * lib.rr(0.8, 1.3)))
		basis = basis.rotated(Vector3.RIGHT, lib.rr(-0.3, 0.3))
		rock_lists[int(lib.rand() * 4.0)].append(
			Transform3D(basis, Vector3(px, height_at(px, pz) - sc * lib.rr(0.15, 0.4), pz)))
	for i in 7:                                    # 水中的露頭石
		var a2 := lib.rr(0.0, TAU)
		var d2: float = nshore * lib.rr(0.2, 0.6)
		var px2 := NATURE_POND.x + cos(a2) * d2
		var pz2 := NATURE_POND.y + sin(a2) * d2
		var sc2 := lib.rr(0.6, 1.4)
		var b2 := Basis(Vector3.UP, lib.rand() * TAU).scaled(Vector3(sc2, sc2 * 1.2, sc2))
		rock_lists[int(lib.rand() * 4.0)].append(
			Transform3D(b2, Vector3(px2, height_at(px2, pz2) + sc2 * 0.25, pz2)))
	for ri in 4:
		if rock_lists[ri].is_empty():
			continue
		var rmm := MultiMeshInstance3D.new()
		rmm.multimesh = lib.make_multimesh(lib.prop_mesh(Lib.ROCK_GLBS[ri], moss), rock_lists[ri], [],
			OUT_DIR + "gen/pond_rocks_%d.res" % ri)
		lib.add(g, rmm, "岸石_%d" % ri)
	_claim(NATURE_POND.x, NATURE_POND.y, NATURE_POND_R * 2.8, NATURE_POND_R * 2.8, "build_nature_pond")
	print("nature pond rocks: 39")

# ── 水路上的小木橋（柱狀地圖：多座橋橫貫村里） ──
func _build_canal_bridges() -> void:
	var g := lib.add(lib.root, Node3D.new(), "CanalBridges")
	var wood := _mat("wood")
	var dark := _mat("dark")
	var stone := _mat("stone")
	for i in CANAL_BRIDGES.size():
		var bx: float = CANAL_BRIDGES[i]
		# 水路在這個 x 的實際 z（折線內插）
		var bz := 85.0
		for k in CANAL.size() - 1:
			var a: Array = CANAL[k]
			var b: Array = CANAL[k + 1]
			if bx >= a[0] and bx <= b[0]:
				bz = a[1] + (b[1] - a[1]) * ((bx - a[0]) / maxf(b[0] - a[0], 0.001))
				break
		var p := Node3D.new()
		p.position = Vector3(bx, height_at(bx, bz) + CANAL_DEPTH + 0.35, bz)
		lib.add(g, p, "水路橋_%d" % i)
		var span := CANAL_HALF * 2.0 + 5.0
		# ── 橋桁（縱樑）：橋面下面要有東西撐，不然只是一片飄著的木板 ──
		var beam_y := -0.30
		for sd0 in [-1.0, 1.0]:
			lib.strut(p, "橋桁_%d" % int(sd0 + 1),
				Vector3(sd0 * 1.55, beam_y, -span * 0.5), Vector3(sd0 * 1.55, beam_y, span * 0.5),
				0.16, dark, 4)
		# 橋脚：水中兩排短柱（水路窄，兩排就夠）
		for sd1 in [-1.0, 1.0]:
			for sd2 in [-1.0, 1.0]:
				lib.strut(p, "橋脚_%d_%d" % [int(sd1 + 1), int(sd2 + 1)],
					Vector3(sd2 * 1.55, beam_y - 0.1, sd1 * CANAL_HALF * 0.62),
					Vector3(sd2 * 1.55, -CANAL_DEPTH - 0.5, sd1 * CANAL_HALF * 0.62),
					0.13, dark, 5)
			lib.strut(p, "橋脚貫_%d" % int(sd1 + 1),
				Vector3(-1.55, -CANAL_DEPTH * 0.55, sd1 * CANAL_HALF * 0.62),
				Vector3(1.55, -CANAL_DEPTH * 0.55, sd1 * CANAL_HALF * 0.62), 0.09, dark, 4)
		# ── 橋面：一片片木板（v9 是一整塊，看不出是木橋）──
		var nb := int(span / 0.42)
		for k3 in nb:
			var bzp: float = -span * 0.5 + (float(k3) + 0.5) * (span / float(nb))
			lib.box(p, "橋板_%d" % k3, Vector3(4.1, 0.13, span / float(nb) * 0.86),
				_mat("wood", k3 % 4), Vector3(0, 0, bzp))
		for sd in [-1, 1]:
			lib.box(p, "橋台_%d" % (sd + 1), Vector3(4.4, CANAL_DEPTH + 0.9, 1.6), stone,
				Vector3(0, -(CANAL_DEPTH + 0.9) * 0.5, float(sd) * (span * 0.5 - 0.7)))
			# ── 高欄：**兩側都要**（v9 只做了一邊，走上去一邊是懸空的）──
			# 親柱（端柱）粗、中間的架柱細，上面架一道手摺
			for k2 in 5:
				var t2 := float(k2) / 4.0
				var zz: float = -span * 0.42 + t2 * span * 0.84
				var is_end := (k2 == 0 or k2 == 4)
				lib.strut(p, "欄柱_%d_%d" % [sd + 1, k2],
					Vector3(float(sd) * 1.95, 0.0, zz),
					Vector3(float(sd) * 1.95, 0.95 if is_end else 0.82, zz),
					0.085 if is_end else 0.055, dark, 5)
				if is_end:      # 親柱頂上的擬寶珠
					lib.cyl(p, "擬寶珠_%d_%d" % [sd + 1, k2], 0.0, 0.10, 0.18, dark,
						Vector3(float(sd) * 1.95, 1.03, zz), 6)
			lib.strut(p, "手摺_%d" % (sd + 1),
				Vector3(float(sd) * 1.95, 0.86, -span * 0.42),
				Vector3(float(sd) * 1.95, 0.86, span * 0.42), 0.055, dark, 5)
			lib.strut(p, "中貫_%d" % (sd + 1),
				Vector3(float(sd) * 1.95, 0.46, -span * 0.42),
				Vector3(float(sd) * 1.95, 0.46, span * 0.42), 0.04, dark, 4)
		var body := StaticBody3D.new()
		p.add_child(body)
		body.owner = lib.root
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(4.2, 0.3, span)
		shape.shape = bs
		body.add_child(shape)
		shape.owner = lib.root
		_claim(bx, bz, 4.5, span + 1.0, "build_canal_bridges")
	print("canal bridges: ", CANAL_BRIDGES.size())

# ── 水邊生態：游動的鴨、水下的鯉、岸邊的鷺鷥 ──
func _build_fauna() -> void:
	var g := lib.add(lib.root, Node3D.new(), "Fauna")
	g.set_script(load("res://scripts/fauna.gd"))
	# 水路中心線交給 fauna.gd 當巡游路徑（水面高度 = 岸高 - sink）
	# 逐節點取水面高度（整條共用一個 y 的話，地面起伏會讓鴨子浮到路上）
	var pts: Array[Vector2] = []
	var ys: Array[float] = []
	for p in CANAL:
		pts.append(Vector2(p[0], p[1]))
		ys.append(bank_h(float(p[0]), float(p[1])) - CANAL_DEPTH * 0.35)
	g.set("paths", [{ "pts": pts, "ys": ys }])

	var duck_mesh := lib.prop_mesh("res://assets/models/duck.glb")
	var koi_mesh := lib.prop_mesh("res://assets/models/koi.glb")
	# ⚠ 一定要在**存檔時**就把生物擺到水路上。
	# v8 只寫了 meta，位置留給 fauna.gd 在執行期算 —— 但編輯器不跑 _process，
	# 所以在編輯器裡九隻鴨子全部疊在世界原點 (0,0,0)，
	# 而原點剛好是本通正中央（使用者：「鴨子在路上」）。
	var seg_n := pts.size() - 1
	var at_canal := func(t: float, sink: float) -> Vector3:
		var ft: float = clampf(t, 0.0, 0.999) * float(seg_n)
		var i2 := int(ft)
		var f := ft - float(i2)
		var a: Vector2 = pts[i2]
		var b: Vector2 = pts[mini(i2 + 1, seg_n)]
		var q: Vector2 = a.lerp(b, f)
		# 橫向擺一點，但要留在水面內（水路半寬 CANAL_HALF，石垣在更外側）
		q += (b - a).normalized().orthogonal() * lib.rr(-1.6, 1.6)
		return Vector3(q.x, bank_h(q.x, q.y) - CANAL_DEPTH * 0.35 - sink, q.y)

	for i in 9:                                    # 鴨（水面）
		var d := MeshInstance3D.new()
		d.mesh = duck_mesh
		d.scale = Vector3.ONE * lib.rr(0.85, 1.15)
		var dt := lib.rr(0.06, 0.94)
		lib.add(g, d, "鴨_%d" % i)
		d.position = at_canal.call(dt, -0.02)
		d.rotation.y = lib.rr(0.0, TAU)
		d.set_meta("swim_kind", 0)
		d.set_meta("swim_t", dt)
		d.set_meta("swim_speed", lib.rr(0.006, 0.016))
	for i in 14:                                   # 鯉（水下）
		var k := MeshInstance3D.new()
		k.mesh = koi_mesh
		k.scale = Vector3.ONE * lib.rr(0.8, 1.4)
		var kt := lib.rr(0.06, 0.94)
		lib.add(g, k, "鯉_%d" % i)
		k.position = at_canal.call(kt, 0.32)
		k.rotation.y = lib.rr(0.0, TAU)
		k.set_meta("swim_kind", 1)
		k.set_meta("swim_t", kt)
		k.set_meta("swim_speed", lib.rr(0.010, 0.026))

	# 鷺鷥：站在岸邊不動（單腳立姿是牠的招牌）
	var heron_mesh := lib.prop_mesh("res://assets/models/heron.glb")
	var placed := 0
	var tries := 0
	while placed < 5 and tries < 400:
		tries += 1
		var hx := lib.rr(-170.0, 180.0)
		var side := 1.0 if lib.rand() < 0.5 else -1.0
		var hz := 85.0 + side * (CANAL_HALF + lib.rr(0.6, 1.4))
		if _path_info(hx, hz)[0] < 0.8:
			continue
		var h := MeshInstance3D.new()
		h.mesh = heron_mesh
		h.position = Vector3(hx, bank_h(hx, hz), hz)
		h.rotation.y = lib.rr(0.0, TAU)
		h.scale = Vector3.ONE * lib.rr(0.9, 1.15)
		lib.add(g, h, "鷺鷥_%d" % placed)
		placed += 1
	print("fauna: 9 鴨 / 14 鯉 / ", placed, " 鷺鷥")

# ── 地板裝飾：店門石板鋪面、飛石步道、石溝與溝蓋、地面招牌與樽桶 ──
func _build_floor_decor() -> void:
	var g := lib.add(lib.root, Node3D.new(), "FloorDecor")
	var stone := _mat("stone")
	var slab := lib.pbr("slab", "stone_path", 0.35) if ResourceLoader.exists("res://assets/textures/stone_path_diff.jpg") else _mat("stone")
	var wood := _mat("wood")
	var dark := _mat("dark")
	var n_apron := 0
	var n_step := 0
	var n_gutter := 0
	# 店門口的石板鋪面 + 飛石：擺在**真正的玄關**前面。
	# v7 是沿著主街每隔 9~17m 隨機撒一組，於是鋪面跟門口對不上 ——
	# 那是因為當時建築不對外公布自己的門開在哪（缺 Frontage 這個概念）。
	# 現在 _longhouse 會把每個玄關的世界座標與朝向登記進 _frontages。
	for f in _frontages:
		if not f.shop:
			continue
		var fp: Vector2 = f.pos
		var fd: Vector2 = f.dir
		# 只裝飾「開向街道」的店面：門口往外 6m 內要碰得到路
		var reach: float = _path_info(fp.x + fd.x * 6.0, fp.y + fd.y * 6.0)[0]
		if reach > 4.5:
			continue
		var cxy: Vector2 = fp + fd * 1.75            # 鋪面中心：門前一步半
		if not _free_for_apron(cxy.x, cxy.y, 3.6, 3.0, int(f.own)):
			continue
		# 門口正對水面的話整組不做 —— 飛石會排進池裡
		if _in_water(cxy.x, cxy.y, 2.0) or _in_water(fp.x + fd.x * 6.0, fp.y + fd.y * 6.0, 1.0):
			continue
		var ap := Node3D.new()
		ap.position = Vector3(cxy.x, height_at(cxy.x, cxy.y), cxy.y)
		ap.rotation.y = atan2(fd.x, fd.y)            # 本地 +z 對齊「朝街道」
		lib.add(g, ap, "店前鋪面_%d" % n_apron)
		# 鋪面：3×2 塊石板，微微高於街面
		for ix in 3:
			for iz in 2:
				# 逐塊檢查：鋪面中心過關不代表六塊石板都在陸地上
				var lox: float = (float(ix) - 1.0) * 1.42
				var loz: float = (float(iz) - 0.5) * 1.42
				var wsx: float = cxy.x + fd.y * lox + fd.x * loz
				var wsz: float = cxy.y - fd.x * lox + fd.y * loz
				if _in_water(wsx, wsz, 0.6):
					continue
				var sl := lib.box(ap, "石板_%d%d" % [ix, iz], Vector3(1.38, 0.20, 1.38), slab,
					Vector3((float(ix) - 1.0) * 1.42, -0.06, (float(iz) - 0.5) * 1.42))
				sl.rotation.y = lib.rr(-0.02, 0.02)
		# 飛石：從鋪面繼續往街心走
		for k in 3:
			var swx: float = cxy.x + fd.x * (2.6 + float(k) * 1.25)
			var swz: float = cxy.y + fd.y * (2.6 + float(k) * 1.25)
			if _in_water(swx, swz, 0.8):
				break
			# 飛石要**埋進地面**，只露 4cm。v8 是 14cm 厚整塊擺在地表上，
			# 側面全看得到，遠看像疊在石板路上的紙板。
			lib.box(ap, "飛石_%d" % k, Vector3(lib.rr(0.78, 1.05), 0.22, lib.rr(0.66, 0.92)), stone,
				Vector3(lib.rr(-0.5, 0.5), -0.07, 2.6 + float(k) * 1.25)).rotation.y = lib.rr(-0.3, 0.3)
			n_step += 1
		# 立看板、樽桶、米俵擺在門的兩側，不擋動線
		if lib.rand() < 0.6:
			var brd := lib.box(ap, "立看板", Vector3(0.9, 1.3, 0.1), wood, Vector3(-2.1, 0.75, 0.1))
			brd.rotation.y = lib.rr(-0.25, 0.25)
			lib.box(ap, "看板腳", Vector3(1.0, 0.1, 0.5), dark, Vector3(-2.1, 0.12, 0.1))
		if lib.rand() < 0.55:
			for b in 2:
				var bar := lib.cyl(ap, "樽_%d" % b, 0.34, 0.30, 0.72, wood,
					Vector3(2.0 + float(b) * 0.78, 0.36, lib.rr(-0.5, 0.1)), 10)
				lib.box(ap, "樽箍_%d" % b, Vector3(0.72, 0.07, 0.72), dark,
					Vector3(bar.position.x, 0.52, bar.position.z))
		if lib.rand() < 0.4:
			lib.box(ap, "米俵", Vector3(1.1, 0.42, 0.5),
				lib.pbr("tawara", "terrain_grass", 1.4, Color(0.82, 0.70, 0.46)),
				Vector3(2.4, 0.22, 0.9)).rotation.y = lib.rr(0.0, TAU)
		_claim(cxy.x, cxy.y, 4.2, 3.4, "build_floor_decor")
		n_apron += 1
	# 石溝與溝蓋：沿本通兩側的排水溝
	for side2 in [-1.0, 1.0]:
		var gx: float = float(side2) * 6.2
		var z2 := -220.0
		while z2 < 230.0:
			var seg_len := 6.0
			# 溝不能架在水上：本通兩側的溝會橫穿水路，那一段要跳掉
			if lib.poly_dist(CANAL, gx, z2 + seg_len * 0.5) < CANAL_HALF * 1.9 \
					or lib.poly_dist(RIVER, gx, z2 + seg_len * 0.5) < RIVER_HALF * 1.6:
				z2 += seg_len
				n_gutter += 1
				continue
			# 用 footprint 最低點：6m 長的一節溝拿中心高度擺，斜坡上會翹起來
			var ggu := _ground_under(gx, z2 + seg_len * 0.5, 1.2, seg_len)
			var gt := Node3D.new()
			gt.position = Vector3(gx, ggu[0], z2 + seg_len * 0.5)
			lib.add(g, gt, "石溝_%d" % n_gutter)
			for sd in [-1, 1]:                    # 溝壁
				lib.box(gt, "溝壁_%d" % (sd + 1), Vector3(0.22, 0.5, seg_len), stone,
					Vector3(float(sd) * 0.42, -0.22, 0))
			lib.box(gt, "溝底", Vector3(0.7, 0.12, seg_len), stone, Vector3(0, -0.44, 0))
			if n_gutter % 3 == 1:                  # 每三節架一塊石蓋
				lib.box(gt, "溝蓋", Vector3(1.15, 0.14, 1.6), slab, Vector3(0, 0.04, 0))
			z2 += seg_len
			n_gutter += 1
	print("floor decor: ", n_apron, "/", _frontages.size(), " 店前鋪面 / ", n_step, " 飛石 / ", n_gutter, " 石溝節")

# ── 村民：沿街走動的路人 NPC ──
## 這是「先做 Q 版中階給我看」那一輪的產物。角色資產在
## assets/blender/make_chars.py，走路動畫在 scripts/npc.gd。
## 這裡只負責：挑幾條街當路線、取地面高度、灑人。
func _build_villagers() -> void:
	var g := lib.add(lib.root, Node3D.new(), "Villagers")
	g.set_script(load("res://scripts/npc.gd"))

	# 路線 = 街道折線，逐節點取地面高度（整條共用一個 y 會讓人陷進坡裡）
	var routes: Array = []
	for si in PATH_SEGMENTS.size():
		var seg: Dictionary = PATH_SEGMENTS[si]
		if float(seg.width) < 7.0:
			continue
		var pts: Array[Vector2] = []
		var ys: Array[float] = []
		# 折線節點之間再細分，坡地上人才會貼著地走
		var raw: Array = seg.pts
		for k in raw.size() - 1:
			var a := Vector2(raw[k][0], raw[k][1])
			var b := Vector2(raw[k + 1][0], raw[k + 1][1])
			var steps := maxi(int(a.distance_to(b) / 8.0), 1)
			for i in steps:
				var q := a.lerp(b, float(i) / float(steps))
				# 只留在村範圍內的段（村外的街沒有人走）
				if absf(q.x) > CORE + 20.0 or absf(q.y - PLAZA.y) > CORE + 40.0:
					continue
				pts.append(q)
				ys.append(height_at(q.x, q.y))
		if pts.size() >= 2:
			routes.append({ "pts": pts, "ys": ys })
	g.set("routes", routes)

	var kinds := ["villager_a", "villager_b", "villager_c"]
	var n := 0
	for i in 90:
		var kind: String = kinds[0] if lib.rand() < 0.42 else (kinds[1] if lib.rand() < 0.75 else kinds[2])
		var ri := int(lib.rand() * float(routes.size()))
		var t := lib.rr(0.02, 0.96)
		var v := lib.char_scene("res://assets/models/%s.glb" % kind)
		lib.add(g, v, "村民_%d" % i)
		lib.own_all(v)
		# 存檔時就把人擺在路線上：npc.gd 沒跑（或壞掉）時場景依然是對的，
		# 而且省掉「第一幀所有人疊在原點」的那一瞬間。
		var rt: Dictionary = routes[ri]
		var pts: Array = rt.pts
		var ys: Array = rt.ys
		var k := clampi(int(t * float(pts.size() - 1)), 0, pts.size() - 2)
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[k + 1]
		var dir := (b - a).normalized()
		var side: Vector2 = dir.orthogonal() * lib.rr(-2.4, 2.4)
		var q: Vector2 = a.lerp(b, lib.rr(0.0, 1.0)) + side
		v.position = Vector3(q.x, float(ys[k]), q.y)
		v.rotation.y = atan2(-dir.y, dir.x)
		v.set_meta("walk_route", ri)
		v.set_meta("walk_t", t)
		v.set_meta("walk_speed", lib.rr(0.0035, 0.0085) * (1.0 if lib.rand() < 0.5 else -1.0))
		v.set_meta("walk_phase", lib.rr(0.0, TAU))
		n += 1
	print("villagers: ", n, " on ", routes.size(), " routes")

# ── 水生植物：睡蓮／荷／菖蒲／水草，鋪滿水路與河的岸邊 ──
## 使用者：「河道也可以加很多植物蓮花之類的」。
## 只鋪在**真的是水**的地方 —— 距離中心線 < 半寬，而且不能壓到橋。
func _build_water_plants() -> void:
	var g := lib.add(lib.root, Node3D.new(), "WaterPlants")
	var pad := lib.tuft_mesh(6, 0.30, 0.34, Color(0.15, 0.29, 0.13), Color(0.27, 0.45, 0.19))
	var lotus := lib.tuft_mesh(5, 0.46, 0.14, Color(0.20, 0.34, 0.16), Color(0.92, 0.72, 0.80), true)
	var reed := lib.tuft_mesh(8, 0.95, 0.10, Color(0.14, 0.26, 0.11), Color(0.42, 0.56, 0.24))
	reed.surface_set_material(0, lib.grass_wind_mat(0.11))
	var groups := [
		{ "mesh": pad, "n": 260, "band": Vector2(0.0, 0.72), "sink": -0.03, "file": "睡蓮" },
		{ "mesh": lotus, "n": 90, "band": Vector2(0.15, 0.66), "sink": -0.30, "file": "荷" },
		{ "mesh": reed, "n": 420, "band": Vector2(0.82, 1.22), "sink": 0.10, "file": "蘆葦" },
	]
	var total := 0
	for grp in groups:
		var list: Array[Transform3D] = []
		var tries := 0
		var target: int = grp.n
		while list.size() < target and tries < target * 60:
			tries += 1
			# 一半沿水路、一半沿河
			var on_canal := lib.rand() < 0.62
			var poly: Array = CANAL if on_canal else RIVER
			var half: float = CANAL_HALF if on_canal else RIVER_HALF
			var sink: float = CANAL_DEPTH if on_canal else RIVER_DEPTH
			var k := int(lib.rand() * float(poly.size() - 1))
			var a := Vector2(poly[k][0], poly[k][1])
			var b := Vector2(poly[k + 1][0], poly[k + 1][1])
			var q: Vector2 = a.lerp(b, lib.rr(0.0, 1.0))
			var band: Vector2 = grp.band
			var off: float = half * lib.rr(band.x, band.y) * (1.0 if lib.rand() < 0.5 else -1.0)
			q += (b - a).normalized().orthogonal() * off
			if absf(q.x) > HALF - 8.0 or absf(q.y) > HALF - 8.0:
				continue
			# 橋下不長（橋墩與橋面會穿過去）
			var near_bridge := false
			for bxp in _canal_bridge_xs():
				if on_canal and absf(q.x - bxp) < 4.5:
					near_bridge = true
					break
			if near_bridge:
				continue
			var wy: float = bank_h(q.x, q.y) - sink * 0.35 + float(grp.sink)
			var sc := lib.rr(0.7, 1.5)
			list.append(Transform3D(Basis(Vector3.UP, lib.rand() * TAU).scaled(Vector3(sc, sc, sc)),
				Vector3(q.x, wy, q.y)))
		total += list.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(grp.mesh, list, [],
			OUT_DIR + "gen/water_%s.res" % String(grp.file))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lib.add(g, mmi, String(grp.file))
	print("water plants: ", total)

func _canal_bridge_xs() -> Array:
	return CANAL_BRIDGES

# ── 村的中心：神木與鎮守之杜（地標的輕重層次）──
## 使用者回報俯瞰時「眼睛沒有地方停」。原因是每塊街區的份量都一樣 ——
## 同樣大小的圍院、同樣高的房子。真實聚落一定有一個「這裡是中心」的東西。
## 這裡放一棵遠高於周圍的神木，四周清空、用玉垣圍起來。
## 鎮守之杜：**佔滿一整個街區**。
## v9 把神木硬塞在 PLAZA 旁邊我手挑的座標，結果卡在建築的內角落 ——
## 要「空曠」就不能跟建物搶地，得整塊街區都不蓋房子。
func _blk_grove(parent: Node, bx: float, bz: float) -> void:
	var g := lib.add(parent, Node3D.new(), "鎮守之杜")
	var c := Vector2(bx, bz)
	var gy := height_at(c.x, c.y)
	# ⚠ 這裡**先不 claim 整個街區**。v9 先圈地再種杜木，結果小樹全被自己
	# 剛圈下的地權擋掉，一棵都沒長出來。整塊地權留到最後再圈。

	# 神木：比一般樹高兩倍以上，剪影才會從屋頂上冒出來
	var trunk_mound := lib.cyl(g, "土壇", 5.6, 6.4, 0.7, _mat("stone", 2),
		Vector3(c.x, gy + 0.25, c.y), 16)
	trunk_mound.name = "土壇"
	var big := MeshInstance3D.new()
	big.mesh = lib.tree_mesh("res://assets/models/tree_round_b.glb")
	big.position = Vector3(c.x, gy + 0.6, c.y)
	big.scale = Vector3(3.4, 4.2, 3.4)
	lib.add(g, big, "神木")
	var tb := StaticBody3D.new()
	big.add_child(tb)
	tb.owner = lib.root
	var tsh := CollisionShape3D.new()
	var tcy := CylinderShape3D.new()
	tcy.radius = 1.6
	tcy.height = 8.0
	tsh.shape = tcy
	tsh.position = Vector3(0, 1.2, 0)
	tb.add_child(tsh)
	tsh.owner = lib.root

	# 注連縄（繞樹一圈的粗繩 + 垂紙）—— 一眼看出這是神木不是路樹
	var rope_m := lib.pbr("shimenawa", "roof_thatch" if false else "terrain_grass", 1.6,
		Color(0.88, 0.84, 0.66))
	var seg := 20
	for i in seg:
		var a := float(i) / float(seg) * TAU
		var a2 := float(i + 1) / float(seg) * TAU
		var r_in := 1.75
		var mid := (a + a2) * 0.5
		var link := lib.cyl(g, "注連縄_%d" % i, 0.17, 0.17,
			r_in * TAU / float(seg) * 1.12, rope_m,
			Vector3(c.x + cos(mid) * r_in, gy + 3.1, c.y + sin(mid) * r_in), 6)
		link.rotation.y = -mid
		link.rotation.z = PI * 0.5
	for i in 6:                                     # 紙垂（白色垂紙）
		var a3 := float(i) / 6.0 * TAU + 0.25
		lib.box(g, "紙垂_%d" % i, Vector3(0.16, 0.5, 0.03),
			lib.flat_mat("shide", Color(0.96, 0.96, 0.94), 0.9),
			Vector3(c.x + cos(a3) * 1.78, gy + 2.72, c.y + sin(a3) * 1.78))

	# 玉垣（圍住神木的矮石欄）—— 給中心一個明確的邊界
	var post_m := _mat("stone", 1)
	for i in 16:
		var a4 := float(i) / 16.0 * TAU
		var px := c.x + cos(a4) * 5.4
		var pz := c.y + sin(a4) * 5.4
		lib.box(g, "玉垣柱_%d" % i, Vector3(0.22, 1.05, 0.22), post_m,
			Vector3(px, height_at(px, pz) + 0.5, pz))
		var a5 := (float(i) + 0.5) / 16.0 * TAU
		var bxp := c.x + cos(a5) * 5.4
		var bzp := c.y + sin(a5) * 5.4
		var rail := lib.box(g, "玉垣貫_%d" % i, Vector3(2.15, 0.13, 0.10), post_m,
			Vector3(bxp, height_at(bxp, bzp) + 0.78, bzp))
		rail.rotation.y = -a5

	# 石燈籠一對、賽錢箱一個（有人來拜的痕跡）
	for sd in [-1.0, 1.0]:
		var lx: float = c.x + 6.6
		var lz2: float = c.y + sd * 2.6
		var ly := height_at(lx, lz2)
		lib.cyl(g, "獻燈基_%d" % int(sd + 1), 0.34, 0.40, 0.22, post_m, Vector3(lx, ly + 0.11, lz2), 8)
		lib.cyl(g, "獻燈竿_%d" % int(sd + 1), 0.13, 0.15, 1.15, post_m, Vector3(lx, ly + 0.8, lz2), 8)
		lib.cyl(g, "獻燈袋_%d" % int(sd + 1), 0.30, 0.28, 0.42, post_m, Vector3(lx, ly + 1.58, lz2), 6)
		lib.cyl(g, "獻燈笠_%d" % int(sd + 1), 0.08, 0.56, 0.26, post_m, Vector3(lx, ly + 1.92, lz2), 6)
	# 杜：神木周圍再種一圈較小的樹（「杜」是樹叢不是一棵樹）
	for i in 14:
		var wa := lib.rr(0.0, TAU)
		var wr := lib.rr(8.5, 18.0)
		var wx := c.x + cos(wa) * wr
		var wz := c.y + sin(wa) * wr
		# 只避開街與彼此，不用避開自己這塊街區
		if _path_info(wx, wz)[0] < 1.6:
			continue
		if not _free(wx, wz, 5.0, 5.0, 0.5):
			continue
		var sub := MeshInstance3D.new()
		sub.mesh = lib.tree_mesh(Lib.TREE_GLBS[int(lib.rand() * 5.0)])
		sub.position = Vector3(wx, height_at(wx, wz), wz)
		sub.scale = Vector3.ONE * lib.rr(1.1, 1.7)
		sub.rotation.y = lib.rr(0.0, TAU)
		lib.add(g, sub, "杜木_%d" % i)
		_claim(wx, wz, 4.6, 4.6, "blk_grove")
	# 最後才把整個街區圈起來，別的東西就不會蓋進來
	_claim(c.x, c.y, BLOCK_W + 2.0, BLOCK_D + 2.0, "blk_grove")
	print("grove: 神木 + 玉垣 @ (", int(c.x), ",", int(c.y), ")")

# ── 生活感雜物：曬衣、柴堆、水桶、農具、俵 ──
## 每一件都要先問 _free 再 _claim（使用者：「放之前先算會不會擋住」）。
func _build_clutter() -> void:
	var g := lib.add(lib.root, Node3D.new(), "Clutter")
	var wood := _mat("wood")
	var dark := _mat("dark")
	var n := 0
	var tries := 0
	while n < 150 and tries < 26000:
		tries += 1
		var x := lib.rr(-CORE, CORE)
		var z := PLAZA.y + lib.rr(-CORE, CORE)
		# v9 全塞在離街 1.5~9m 的院子裡 —— 那些院子被土塀圍著，從街上根本看不到
		# （使用者：「我沒看到多的生活雜物」）。改成大部分貼著街緣擺。
		var ed: float = _path_info(x, z)[0]
		if ed < 0.9 or ed > 11.0:
			continue
		if ed > 5.0 and lib.rand() < 0.55:
			continue
		if _field_w(x, z) > 0.2:
			continue
		if not _free(x, z, 3.6, 3.6, 0.4):
			continue
		# 貼地要用 footprint 最低點：拿中心點的高度，斜坡上 3m 寬的曬衣竿
		# 會有一端翹在半空（使用者：「雜物在空中」）
		var gu := _ground_under(x, z, 3.2, 3.2)
		# ⚠ 一定要先接上樹再做零件。掛在還沒進樹的節點上的子節點 owner 設不上去，
		# 而**沒有 owner 的節點不會被存進 .tscn**。v9~v12 的雜物在編輯器裡
		# 全部是 320 個空節點 —— 使用者說「我沒看到多的生活雜物」是真的看不到，
		# 不是擺得不夠顯眼。
		var p := lib.add(g, Node3D.new(), "雜物_%d" % n) as Node3D
		p.position = Vector3(x, gu[0], z)
		p.rotation.y = lib.rr(0.0, TAU)
		var kind := int(lib.rand() * 5.0)
		match kind:
			0:      # 物干し（曬衣竿 + 掛著的布）
				for sd in [-1.0, 1.0]:
					lib.cyl(p, "竿柱_%d" % int(sd + 1), 0.06, 0.07, 1.9, dark,
						Vector3(sd * 1.3, 0.95, 0), 5)
				lib.box(p, "竿", Vector3(2.9, 0.06, 0.06), dark, Vector3(0, 1.82, 0))
				var cloth := lib.flat_mat("laundry_%d" % (n % 4),
					[Color(0.72, 0.74, 0.78), Color(0.42, 0.46, 0.56),
					Color(0.78, 0.70, 0.58), Color(0.56, 0.60, 0.52)][n % 4], 1.0)
				for k in 3:
					# 0.02 太薄，側看就是三根黑棍子 —— 使用者拍到的「看不懂的雜物」就是它
					lib.box(p, "布_%d" % k, Vector3(0.62, lib.rr(0.7, 1.05), 0.09), cloth,
						Vector3(-0.9 + float(k) * 0.9, 1.82 - lib.rr(0.36, 0.53), 0))
			1:      # 薪積み（柴堆）
				var rows := 2 + int(lib.rand() * 2.0)
				for r in rows:
					for k2 in 3:
						var lg := lib.cyl(p, "薪_%d_%d" % [r, k2], 0.075, 0.08, lib.rr(0.6, 0.8), wood,
							Vector3(-0.5 + float(k2) * 0.25, 0.09 + float(r) * 0.17, lib.rr(-0.06, 0.06)), 5)
						lg.rotation.z = PI * 0.5
						lg.rotation.y = lib.rr(-0.06, 0.06)
			2:      # 水桶と桶台
				lib.box(p, "桶台", Vector3(1.1, 0.14, 0.8), wood, Vector3(0, 0.07, 0))
				for k3 in 2:
					var bk := lib.cyl(p, "桶_%d" % k3, 0.26, 0.23, 0.46, wood,
						Vector3(-0.28 + float(k3) * 0.56, 0.37, lib.rr(-0.1, 0.1)), 10)
					lib.box(p, "桶箍_%d" % k3, Vector3(0.55, 0.05, 0.55), dark,
						Vector3(bk.position.x, 0.52, bk.position.z))
			3:      # 農具（鍬・鋤靠牆）
				lib.box(p, "農具棚", Vector3(1.6, 0.1, 0.35), wood, Vector3(0, 0.05, 0))
				for k4 in 3:
					var hd := lib.cyl(p, "柄_%d" % k4, 0.035, 0.04, 1.5, wood,
						Vector3(-0.5 + float(k4) * 0.5, 0.78, 0.1), 5)
					hd.rotation.x = lib.rr(0.16, 0.26)
					lib.box(p, "刃_%d" % k4, Vector3(0.2, 0.24, 0.04), dark,
						Vector3(hd.position.x, 0.1, 0.32))
			_:      # 俵積み（米袋）
				var tawara := lib.pbr("tawara", "terrain_grass", 1.4, Color(0.82, 0.70, 0.46))
				for r2 in 2:
					for k5 in (3 - r2):
						var tw := lib.cyl(p, "俵_%d_%d" % [r2, k5], 0.22, 0.22, 0.72, tawara,
							Vector3(-0.35 + float(k5) * 0.35 + float(r2) * 0.18,
								0.22 + float(r2) * 0.42, 0), 8)
						tw.rotation.z = PI * 0.5
		_claim(x, z, 4.0, 4.0, "build_clutter")
		n += 1
	print("clutter: ", n)

# ── 生活痕跡（街邊） ──
func _build_props() -> void:
	var g := lib.add(lib.root, Node3D.new(), "Props")
	var wood := _mat("wood")
	var dark := _mat("dark")
	var stone := _mat("stone")
	var n := 0
	var tries := 0
	while n < 60 and tries < 4000:
		tries += 1
		var x := lib.rr(-CORE, CORE)
		var z := PLAZA.y + lib.rr(-CORE, CORE)
		var ed: float = _path_info(x, z)[0]
		if ed < 0.8 or ed > 5.0:
			continue
		if not _free(x, z, 2.6, 2.6, 0.4):
			continue
		var y := height_at(x, z)
		var kind := int(lib.rand() * 4.0)
		var p := Node3D.new()
		p.position = Vector3(x, y, z)
		p.rotation.y = lib.rr(0.0, TAU)
		lib.add(g, p, "小物_%02d" % n)
		if kind == 0:
			for i in 4:
				var lg := lib.cyl(p, "柴_%d" % i, 0.09, 0.11, lib.rr(1.1, 1.6), dark,
					Vector3(lib.rr(-0.5, 0.5), 0.12 + float(i) * 0.17, lib.rr(-0.3, 0.3)), 5)
				lg.rotation.z = PI / 2.0
				lg.rotation.y = lib.rr(-0.25, 0.25)
			_collide(p, Vector3(1.6, 1.3, 1.2))
		elif kind == 1:
			lib.cyl(p, "水缸", 0.55, 0.48, 1.0, stone, Vector3(0, 0.5, 0), 12)
			lib.cyl(p, "水面", 0.5, 0.5, 0.05, lib.flat_mat("water_dark", Color(0.07, 0.12, 0.15), 0.1),
				Vector3(0, 0.98, 0), 12)
			lib.box(p, "手桶", Vector3(0.35, 0.35, 0.35), wood, Vector3(0.85, 0.18, 0.3))
			_collide(p, Vector3(1.2, 1.1, 1.2))
		elif kind == 2:
			for sd in [-1, 1]:
				lib.cyl(p, "架柱_%d" % (sd + 1), 0.07, 0.09, 2.2, dark, Vector3(float(sd) * 1.6, 1.1, 0), 5)
			for lv in 2:
				lib.box(p, "橫竿_%d" % lv, Vector3(3.6, 0.08, 0.08), dark, Vector3(0, 1.3 + float(lv) * 0.5, 0))
			for i2 in 9:
				lib.box(p, "稻束_%d" % i2, Vector3(0.28, 0.75, 0.22), _mat("thatch"),
					Vector3(-1.45 + float(i2) * 0.36, 1.42, 0))
			_collide(p, Vector3(3.4, 2.0, 0.6))
		else:
			lib.box(p, "基", Vector3(0.6, 0.24, 0.6), stone, Vector3(0, 0.12, 0))
			lib.cyl(p, "竿", 0.13, 0.15, 1.1, stone, Vector3(0, 0.78, 0), 8)
			lib.box(p, "火袋", Vector3(0.5, 0.45, 0.5), stone, Vector3(0, 1.55, 0))
			lib.box(p, "笠", Vector3(0.78, 0.16, 0.78), stone, Vector3(0, 1.85, 0))
			_collide(p, Vector3(0.7, 2.0, 0.7))
		_claim(x, z, 2.8, 2.8, "build_props")
		n += 1
	print("props: ", n)

func _build_gates() -> void:
	var dark := _mat("dark")
	var kawara := _mat("kawara")
	var defs := [
		{ "name": "北門", "x": 0.0, "z": -215.0, "yaw": 0.0 },
		{ "name": "西南門", "x": -172.0, "z": 92.0, "yaw": 0.42 },
	]
	for d in defs:
		var g := Node3D.new()
		g.position = Vector3(d.x, height_at(d.x, d.z), d.z)
		g.rotation.y = d.yaw
		lib.add(lib.root, g, d.name)
		for s in [-1, 1]:
			lib.box(g, "柱_%d" % (s + 1), Vector3(0.7, 5.0, 0.7), dark, Vector3(float(s) * 5.2, 2.5, 0))
			_collide(g, Vector3(0.9, 5.2, 0.9), Vector3(float(s) * 5.2, 0, 0))
		lib.box(g, "樑", Vector3(12.0, 0.55, 0.9), dark, Vector3(0, 5.0, 0))
		lib.box(g, "簷", Vector3(13.2, 0.24, 1.8), kawara, Vector3(0, 5.5, 0))
		_claim(d.x, d.z, 13.0, 2.5, "build_gates")

func _build_lamps() -> void:
	var iron := lib.flat_mat("iron", Color(0.16, 0.16, 0.18), 0.6)
	var glow := lib.flat_mat("lamp_glow", Color(1.0, 0.85, 0.55), 0.3, Color(1.0, 0.75, 0.4))
	var lamps := lib.add(lib.root, Node3D.new(), "Lamps")
	var spots := []
	for z in ST_Z:
		spots.append(Vector2(6.2, z + 6.0))
		spots.append(Vector2(-6.2, z - 6.0))
	for x in ST_X:
		if absf(x) > 0.1:
			spots.append(Vector2(x + 5.2, 35.0))
	for z2 in [-110.0, -55.0, 60.0, 115.0]:
		spots.append(Vector2(5.8, z2))
	var idx := 0
	for s in spots:
		idx += 1
		var lamp := Node3D.new()
		lamp.position = Vector3(s.x, height_at(s.x, s.y), s.y)
		lib.add(lamps, lamp, "街燈_%d" % idx)
		lib.cyl(lamp, "柱", 0.055, 0.075, 3.2, iron, Vector3(0, 1.6, 0), 8)
		lib.box(lamp, "燈頭", Vector3(0.38, 0.46, 0.38), glow, Vector3(0, 3.35, 0))
		lib.box(lamp, "燈帽", Vector3(0.52, 0.1, 0.52), iron, Vector3(0, 3.63, 0))
		var li := OmniLight3D.new()
		li.position = Vector3(0, 3.3, 0)
		li.light_color = Color(1.0, 0.78, 0.5)
		li.light_energy = 1.2
		li.omni_range = 9.0
		li.shadow_enabled = false
		lib.add(lamp, li, "光")

func _build_trees() -> void:
	var variants := []
	for glb in Lib.TREE_GLBS:
		variants.append({ "mesh": lib.tree_mesh(glb), "list": [], "cols": [] })
	var count := 0
	var tries := 0
	while count < 2600 and tries < 130000:
		tries += 1
		var x := lib.rr(-HALF + 3.0, HALF - 3.0)
		var z := lib.rr(-HALF + 3.0, HALF - 3.0)
		if _path_info(x, z)[0] < 3.5:
			continue
		if _field_w(x, z) > 0.2:
			continue
		if lib.poly_dist(RIVER, x, z) < RIVER_HALF * 1.4:
			continue
		if lib.poly_dist(CANAL, x, z) < CANAL_HALF * 2.2:
			continue
		# 佔位檢查**一律**要做，不能只在 r0 < CORE 時做 ——
		# CORE 是圓的、村是長方形的，南北兩排街區落在圓外，
		# 於是那幾排的院子長出穿進建築的樹（修好體檢之後才抓到）。
		if not _free(x, z, 5.5, 5.5, 0.5):
			continue
		var r0 := Vector2(x, z - PLAZA.y).length()
		if r0 < CORE:
			# 里內：只長在街區內庭的空隙（參考圖：每個院子都有一兩棵樹）
			if lib.rand() > 0.35:
				continue
			_claim(x, z, 5.0, 5.0, "build_trees")
		elif lib.rand() > 0.7:      # 田環帶外側一路長到圖邊，遠景才不會空一塊
			continue
		var y := height_at(x, z)
		var s := lib.rr(0.9, 1.7)
		var basis := Basis(Vector3.UP, lib.rand() * TAU).scaled(Vector3(s, s * lib.rr(0.9, 1.2), s))
		var r := lib.rand()
		var vi := 0 if r < 0.4 else (1 if r < 0.7 else (2 if r < 0.85 else (3 if r < 0.95 else 4)))
		variants[vi].list.append(Transform3D(basis, Vector3(x, y, z)))
		# 逐棵色差：五種樹模乘上隨機色調，一整片林子才不會像同一個貼紙複製
		variants[vi].cols.append(Color(lib.rr(0.84, 1.10), lib.rr(0.88, 1.08), lib.rr(0.80, 1.02)))
		count += 1
	var forest := lib.add(lib.root, Node3D.new(), "Trees")
	for i in variants.size():
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(variants[i].mesh, variants[i].list, variants[i].cols,
			OUT_DIR + "gen/trees_%d.res" % i)
		lib.add(forest, mmi, "Trees%d" % i)
	print("trees: ", count)

func _build_grass() -> void:
	# 草色：v7 的葉尖 (0.38,0.50,0.20) 是橄欖色，配上偏乾的地形貼圖整片發黃
	var tall := lib.tuft_mesh(7, 0.40, 0.20, Color(0.11, 0.21, 0.08), Color(0.29, 0.48, 0.18))
	tall.surface_set_material(0, lib.grass_wind_mat(0.10))
	var flower := lib.tuft_mesh(5, 0.34, 0.16, Color(0.12, 0.22, 0.09), Color(0.28, 0.46, 0.18), true)
	flower.surface_set_material(0, lib.grass_wind_mat(0.08))
	var rice := lib.tuft_mesh(5, 0.32, 0.10, Color(0.20, 0.34, 0.12), Color(0.45, 0.62, 0.22))
	rice.surface_set_material(0, lib.grass_wind_mat(0.07))
	var reed := lib.tuft_mesh(6, 0.62, 0.14, Color(0.18, 0.28, 0.12), Color(0.52, 0.56, 0.28))
	reed.surface_set_material(0, lib.grass_wind_mat(0.13))
	# 灌木層：介於草與樹之間的中層。只有「草 + 樹」兩層時，
	# 地面到樹冠之間是空的，遠看就是一片綠地上插著棒棒糖。
	var shrub := lib.tuft_mesh(9, 1.05, 0.55, Color(0.10, 0.20, 0.08), Color(0.26, 0.42, 0.16))
	shrub.surface_set_material(0, lib.grass_wind_mat(0.05))
	var fern := lib.tuft_mesh(7, 0.55, 0.40, Color(0.13, 0.24, 0.10), Color(0.32, 0.50, 0.20))
	fern.surface_set_material(0, lib.grass_wind_mat(0.06))
	var groups := [
		{ "mesh": shrub, "n": 900, "file": "shrubs", "mode": "wild" },
		{ "mesh": fern, "n": 1200, "file": "ferns", "mode": "wild" },
		{ "mesh": tall, "n": 2600, "file": "grass_tall", "mode": "wild" },
		{ "mesh": flower, "n": 240, "file": "grass_flower", "mode": "wild" },
		{ "mesh": rice, "n": 3600, "file": "rice_rows", "mode": "field" },
		{ "mesh": reed, "n": 800, "file": "reeds", "mode": "shore" },
	]
	var total := 0
	for grp in groups:
		var list: Array[Transform3D] = []
		var tries := 0
		var target: int = grp.n
		while list.size() < target and tries < target * 40:
			tries += 1
			var x := lib.rr(-HALF + 4.0, HALF - 4.0)
			var z := lib.rr(-HALF + 4.0, HALF - 4.0)
			var mode := String(grp.mode)
			if mode == "field":
				if _field_w(x, z) < 0.5:
					continue
				x = snappedf(x, 1.4) + lib.rr(-0.12, 0.12)
				z = snappedf(z, 1.4) + lib.rr(-0.12, 0.12)
			elif mode == "shore":
				var rd := lib.poly_dist(RIVER, x, z)
				var cd := lib.poly_dist(CANAL, x, z)
				var on_river := rd >= RIVER_HALF * 0.85 and rd <= RIVER_HALF * 2.0
				var on_canal := cd >= CANAL_HALF * 1.1 and cd <= CANAL_HALF * 2.3
				if not (on_river or on_canal):
					continue
			else:
				if _path_info(x, z)[0] < 1.0 or _field_w(x, z) > 0.2:
					continue
				# 草也要避開建物 —— 從屋內長出來的草跟樹一樣詭異
				# （使用者：「不要有東西擋住或是放在同一層」）
				var need: float = 2.6 if String(grp.file) == "shrubs" else 1.6
				if not _free(x, z, need, need, 0.1):
					continue
				if lib.poly_dist(RIVER, x, z) < RIVER_HALF * 1.2:
					continue
				if lib.poly_dist(CANAL, x, z) < CANAL_HALF * 1.8:
					continue
				var r0 := Vector2(x, z - PLAZA.y).length()
				if lib.rand() > (0.1 if r0 < CORE else 0.6):
					continue
			var s := lib.rr(0.7, 1.4)
			var basis := Basis(Vector3.UP, lib.rand() * TAU).scaled(Vector3(s, s, s))
			list.append(Transform3D(basis, Vector3(x, height_at(x, z), z)))
		total += list.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(grp.mesh, list, [], OUT_DIR + "gen/" + String(grp.file) + ".res")
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lib.add(lib.root, mmi, String(grp.file).capitalize().replace(" ", ""))
	print("grass/rice/reeds: ", total)

func _build_env() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.54, 0.82)
	sky_mat.sky_horizon_color = Color(0.76, 0.82, 0.82)
	sky_mat.ground_horizon_color = Color(0.62, 0.66, 0.60)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	# 亮度校正（使用者回報畫面過白）：天空環境光原本 1.05 直接灌滿畫面、
	# glow 門檻又是預設值 → 亮部整片溢出。壓曝光 + 抬 glow 門檻 + 補對比。
	env.glow_intensity = 0.45
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.25
	env.tonemap_exposure = 0.82
	env.tonemap_white = 4.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.78, 0.78)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.2
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	# SDFGI 關閉：室外大場景會把畫面整個洗白（使用者回報），改靠天空環境光
	env.sdfgi_enabled = false
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.78, 0.83, 0.83)
	var we := WorldEnvironment.new()
	we.environment = env
	lib.add(lib.root, we, "WorldEnvironment")
