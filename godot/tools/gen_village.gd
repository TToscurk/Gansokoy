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

const PATH_SEGMENTS := [
	# 本通（主街・南北貫穿，最寬）
	{ "width": 11.0, "pts": [[0.0, -240.0], [0.0, -120.0], [0.0, 30.0], [0.0, 160.0], [0.0, 250.0]] },
	# 橫町（0.2 條・東西中段，東端過橋）
	{ "width": 9.0, "pts": [[-190.0, 30.0], [-104.0, 30.0], [0.0, 30.0], [104.0, 30.0], [190.0, 30.0], [232.0, 30.0]] },
	# 其餘南北街（ST_X 除了本通）
	{ "width": 7.0, "pts": [[-156.0, -190.0], [-156.0, 0.0], [-156.0, 195.0]] },
	{ "width": 7.0, "pts": [[-104.0, -190.0], [-104.0, 0.0], [-104.0, 195.0]] },
	{ "width": 7.0, "pts": [[-52.0, -190.0], [-52.0, 0.0], [-52.0, 195.0]] },
	{ "width": 7.0, "pts": [[52.0, -190.0], [52.0, 0.0], [52.0, 195.0]] },
	{ "width": 7.0, "pts": [[104.0, -190.0], [104.0, 0.0], [104.0, 195.0]] },
	{ "width": 7.0, "pts": [[156.0, -190.0], [156.0, 0.0], [156.0, 195.0]] },
	# 其餘東西街
	{ "width": 7.0, "pts": [[-182.0, -190.0], [0.0, -190.0], [182.0, -190.0]] },
	{ "width": 7.0, "pts": [[-182.0, -135.0], [0.0, -135.0], [182.0, -135.0]] },
	{ "width": 7.0, "pts": [[-182.0, -80.0], [0.0, -80.0], [182.0, -80.0]] },
	{ "width": 7.0, "pts": [[-182.0, -25.0], [0.0, -25.0], [182.0, -25.0]] },
	{ "width": 7.5, "pts": [[-182.0, 85.0], [0.0, 85.0], [182.0, 85.0]] },
	{ "width": 7.0, "pts": [[-182.0, 140.0], [0.0, 140.0], [182.0, 140.0]] },
	{ "width": 7.0, "pts": [[-182.0, 195.0], [0.0, 195.0], [182.0, 195.0]] },
	# 西南門引道（香霖堂）
	{ "width": 5.2, "pts": [[-132.0, 100.0], [-145.0, 98.0], [-156.0, 94.0]] },
]
# ── 河（東側，橫町東端石橋跨過；北端往圖外＝河畔道接口） ──
const RIVER := [[268.0, -300.0], [250.0, -190.0], [232.0, -80.0], [222.0, -10.0],
	[220.0, 30.0], [226.0, 100.0], [240.0, 200.0], [256.0, 300.0]]
# ── 水路（貫穿村里的水渠，多座小橋橫過 —— 柱狀地圖裡那些白色帶狀物） ──
## 東端要**接進大河**（使用者：「水道河流沒銜接到外部大河流」）。
## v9 的東端停在 x=200，離河最近點還有 30m —— 水路憑空斷在草地上。
## 西端也拉到圖外，讓它看起來是從山那邊引過來的。
const CANAL := [[-260.0, 84.0], [-190.0, 85.0], [-100.0, 86.5], [-20.0, 84.5],
	[60.0, 86.0], [140.0, 84.5], [196.0, 86.0], [216.0, 90.0], [226.0, 96.0]]
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
			mask = maxf(mask, 1.0 - smoothstep(w * 0.5 - 0.5, w * 0.5 + 2.0, d))
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
	var soil := maxf(_field_w(x, z), g2 * 0.12)
	var macro := clampf(_nh.get_noise_2d(x * 0.4, z * 0.4) * 0.5 + 0.5, 0.0, 1.0)
	return Color(path_w, soil, macro)

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
	lib.terrain(OUT_DIR, HALF, 221, height_at, mask_at, "cobble", Color(0.60, 0.94, 0.55))
	lib.boundary(HALF - 2.0)
	lib.river_water(OUT_DIR, RIVER, RIVER_HALF, RIVER_DEPTH * 0.35, bank_h)
	# 水色照參考圖：飽和的藍綠，不是淡青
	var canal_w := lib.river_water(OUT_DIR, CANAL, CANAL_HALF, CANAL_DEPTH * 0.35, bank_h, "Canal")
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
func _claim(cx: float, cz: float, w: float, d: float) -> int:
	var idx := _rects.size()
	_rects.append([cx, cz, w, d])
	for c in _cells(cx, cz, w * 0.5, d * 0.5):
		if not _grid.has(c):
			_grid[c] = []
		_grid[c].append(idx)
	return idx

## 店前鋪面專用的空地判定：
## 不能用 _free —— 它會擋掉「離街 0.6m 內」與「壓到自家地權」，
## 而鋪面本來就該貼著街緣、就該疊在自家門口那塊地上。
func _free_for_apron(cx: float, cz: float, w: float, d: float, own: int) -> bool:
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
				return false
	return true

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
	"plaster": [Color(1.00, 0.98, 0.94), Color(0.92, 0.88, 0.80),
		Color(0.84, 0.82, 0.78), Color(0.96, 0.91, 0.84)],
	"kawara": [Color(0.80, 0.84, 0.92), Color(0.66, 0.70, 0.78),
		Color(0.74, 0.76, 0.80), Color(0.58, 0.62, 0.70)],
	"thatch": [Color(0.66, 0.54, 0.36), Color(0.58, 0.47, 0.31),
		Color(0.72, 0.60, 0.40), Color(0.50, 0.42, 0.30)],
	"mud": [Color(0.80, 0.72, 0.58), Color(0.70, 0.62, 0.48),
		Color(0.86, 0.78, 0.64), Color(0.64, 0.58, 0.46)],
	"dark": [Color(1.00, 1.00, 1.00), Color(0.82, 0.78, 0.74),
		Color(0.70, 0.64, 0.60), Color(0.92, 0.86, 0.80)],
	"wood": [Color(0.90, 0.82, 0.72), Color(0.78, 0.68, 0.56),
		Color(0.96, 0.88, 0.74), Color(0.70, 0.62, 0.52)],
	"stone": [Color(1.00, 1.00, 1.00), Color(0.90, 0.90, 0.88),
		Color(0.82, 0.84, 0.82), Color(0.95, 0.93, 0.88)],
}
const MAT_SET := {
	"kawara": ["roof_kawara", 0.22], "thatch": ["terrain_grass", 1.1],
	"plaster": ["plaster", 0.4], "mud": ["plaster", 0.5],
	"dark": ["dark_wood", 0.45], "wood": ["planks", 0.5], "stone": ["stone_wall", 0.30],
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
		ridge_along_x: bool, storey := 1, roof := "kawara", flip := false) -> void:
	var wall := _mat("plaster") if lib.rand() < 0.6 else _mat("mud")
	var dark := _mat("dark")
	var stone := _mat("stone")
	var roof_m := _mat(roof)
	# 高度不要只有兩檔 —— v8 所有平房一律 3.0m，整排剪影一模一樣
	var h := lib.rr(2.7, 3.4) if storey == 1 else lib.rr(4.6, 5.6)
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
	# ── 立面：逐間（bay）決定是玄關／窗／板壁 ──
	# v3 的問題是「只有一片格子戶貼在牆上」，走近看是紙板。
	# 這裡每一間都做立體：凹陷的玄關、有框有格的窗、腰板、庇。
	var fz2 := depth * 0.5
	var bays := maxi(int(length / 3.4), 1)
	var bw := length / float(bays)
	var door_bay := int(lib.rand() * float(bays))
	var is_shop := lib.rand() < 0.55
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
				cloth.albedo_color = [Color(0.26, 0.22, 0.32), Color(0.52, 0.24, 0.20),
					Color(0.20, 0.30, 0.40), Color(0.34, 0.30, 0.18)][int(lib.rand() * 4.0)]
				cloth.roughness = 1.0
				for k in [-1, 0, 1]:
					lib.box(g, "暖簾_%d_%d" % [i, k + 1], Vector3(minf(bw * 0.2, 0.75), 0.72, 0.04), cloth,
						Vector3(dx + float(k) * minf(bw * 0.22, 0.82), 2.02, fz2 + 0.02))
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
			for k in 3:
				lib.box(g, "縦格子_%d_%d" % [i, k], Vector3(0.07, 1.35, 0.12), dark,
					Vector3(dx - ww * 0.3 + float(k) * ww * 0.3, 1.85, fz2 + 0.05))
			lib.box(g, "横桟_%d" % i, Vector3(ww, 0.07, 0.12), dark, Vector3(dx, 1.85, fz2 + 0.05))
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
		var gs := lib.rr(0.35, 0.5)
		var gd := lib.rr(1.4, 2.2)
		var gz := (depth * 0.5 + gd * 0.5) * (1.0 if lib.rand() < 0.5 else -1.0)
		lib.box(g, "下屋壁", Vector3(length * lib.rr(0.5, 0.85), 2.0, gd), wall,
			Vector3(lib.rr(-0.15, 0.15) * length, 1.32, gz))
		var geya := lib.box(g, "下屋根", Vector3(length * lib.rr(0.55, 0.9), 0.16, gd + 0.8), roof_m,
			Vector3(lib.rr(-0.15, 0.15) * length, 2.42, gz + (0.2 if gz > 0.0 else -0.2)))
		geya.rotation.x = (-gs if gz > 0.0 else gs)
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
	var own := _claim(cx, cz, length + 1.0, depth + 1.6) if ridge_along_x \
		else _claim(cx, cz, depth + 1.6, length + 1.0)
	_frontages.append({
		"pos": door_w, "dir": out_dir, "shop": is_shop,
		"width": minf(bw, 3.2), "ground": float(gu[0]), "own": own,
	})

## 土塀：街區外圍的圍牆（帶瓦冠）
func _wall_run(parent: Node, name: String, cx: float, cz: float, length: float, along_x: bool) -> void:
	if length < 1.0:
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
	_claim(cx, cz, length + 0.6 if along_x else 1.2, 1.2 if along_x else length + 0.6)

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
	print("blocks built, longhouses: ", n_house)

## 一般街區：四邊長屋 + 土塀補缺 + 內庭（蔵、井、樹位）
func _blk_compound(parent: Node, bx: float, bz: float) -> int:
	var hw := BLOCK_W * 0.5
	var hd := BLOCK_D * 0.5
	var n := 0
	# 街區大門開在哪一邊（朝最近的主街）
	var gate_side := 0 if absf(bx) > absf(bz - PLAZA.y) else 2      # 0=W/E 1..
	for side in 4:
		# side: 0=北(-z) 1=南(+z) 2=西(-x) 3=東(+x)
		var along_x := side < 2
		var span := BLOCK_W if along_x else BLOCK_D
		var sgn := -1.0 if side % 2 == 0 else 1.0
		var has_house := lib.rand() < 0.86
		if has_house:
			var length := span * lib.rr(0.48, 0.68)   # 轉角要留空，太長四邊會互相排擠
			var depth := lib.rr(6.4, 8.2)
			# 內縮量由進深決定：屋簷外緣要留在土塀內側（v2 的「建築卡圍牆」）
			var inset := ((hd if along_x else hw) - 1.6) - depth * 0.5 - 0.75
			var off := lib.rr(-0.45, 0.45) * (span - length)
			var cx := bx + (off if along_x else sgn * inset)
			var cz := bz + (sgn * inset if along_x else off)
			if _free(cx, cz, length if along_x else depth, depth if along_x else length, 0.2):
				var storey := 2 if lib.rand() < 0.3 else 1
				var roof := "kawara" if lib.rand() < 0.72 else "thatch"
				# 立面朝街：北側／西側要轉 180 度，否則玄關開向中庭
				_longhouse(parent, "長屋_%d" % side, cx, cz, length, depth, along_x, storey, roof, sgn < 0.0)
				n += 1
				# 兩端補土塀
				for e in [-1.0, 1.0]:
					var b_edge: float = off + float(e) * length * 0.5      # 屋身端點
					var blk_edge: float = float(e) * span * 0.5            # 街區端點
					var wlen: float = absf(blk_edge - b_edge) - 0.5
					if wlen < 1.0:
						continue
					var wc: float = (b_edge + blk_edge) * 0.5
					var wcx: float = bx + (wc if along_x else sgn * (hw - 0.4))
					var wcz: float = bz + (sgn * (hd - 0.4) if along_x else wc)
					_wall_run(parent, "塀_%d_%d" % [side, int(e)], wcx, wcz, wlen, along_x)
				continue
		# 沒有房子的邊：整段土塀（大門那邊留缺口）
		var wl := span - (7.0 if side == gate_side else 0.0)
		_wall_run(parent, "塀全_%d" % side, bx + (0.0 if along_x else sgn * (hw - 0.4)),
			bz + (sgn * (hd - 0.4) if along_x else 0.0), wl, along_x)
	# 內庭：離れ（後棟小屋）—— 街區內部也要有東西
	for k in 2:
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
		if lib.rand() < 0.55 and _free(ix, iz, tw, td, 0.5):
			_longhouse(parent, "離れ_%d" % k, ix, iz, ln, dp,
				along, 1, "kawara" if lib.rand() < 0.5 else "thatch", lib.rand() < 0.5)
			n += 1
	# 內庭：土藏（白牆倉庫）
	if lib.rand() < 0.6:
		var sx := bx + lib.rr(-6.0, 6.0)
		var sz := bz + lib.rr(-6.0, 6.0)
		if _free(sx, sz, 6.0, 5.0, 0.5):
			var s := Node3D.new()
			s.position = Vector3(sx, height_at(sx, sz), sz)
			s.rotation.y = lib.rr(0.0, TAU)
			lib.add(parent, s, "土藏")
			lib.box(s, "基石", Vector3(5.6, 0.35, 4.6), _mat("stone"), Vector3(0, 0.18, 0))
			lib.box(s, "藏身", Vector3(5.0, 4.2, 4.0), _mat("plaster"), Vector3(0, 2.45, 0))
			lib.box(s, "腰", Vector3(5.1, 0.9, 4.1), _mat("dark"), Vector3(0, 0.85, 0))
			lib.box(s, "扉", Vector3(1.3, 2.0, 0.14), _mat("dark"), Vector3(0, 1.55, 2.05))
			lib.gable_roof(s, 4.55, 6.2, 5.2, 0.5, 0.22, _mat("kawara"), _mat("plaster"))
			_collide(s, Vector3(5.2, 5.0, 4.2))
			_claim(sx, sz, 6.4, 5.4)
	return n

## 面街的商家街區（鈴奈庵、鵜吞亭）：主建築貼本通那一側，其餘同一般街區
func _blk_shopfront(parent: Node, bx: float, bz: float, title: String, face_dir: int) -> int:
	var hw := BLOCK_W * 0.5
	var cx := bx + float(face_dir) * (hw - 5.0)
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
	_claim(cx, cz, d + 2.0, w + 2.0)
	return 1 + _blk_compound(parent, bx, bz)

## 寺子屋：大屋頂主屋 + 外廊 + 前庭（慧音的私塾）
func _blk_terakoya(parent: Node, bx: float, bz: float) -> void:
	var cx := bx
	var cz := bz - 6.0
	var g := Node3D.new()
	g.position = Vector3(cx, height_at(cx, cz), cz)
	lib.add(parent, g, "寺子屋")
	lib.box(g, "基壇", Vector3(24.0, 0.6, 14.0), _mat("stone"), Vector3(0, 0.3, 0))
	lib.box(g, "屋身", Vector3(22.0, 3.8, 12.0), _mat("plaster"), Vector3(0, 2.5, 0))
	lib.box(g, "外廊", Vector3(23.4, 0.28, 2.2), _mat("wood"), Vector3(0, 0.74, 7.0))
	for i in 8:
		lib.cyl(g, "廊柱_%d" % i, 0.15, 0.15, 2.8, _mat("dark"), Vector3(-10.0 + float(i) * 2.85, 2.2, 7.8), 6)
	for i in 5:
		lib.box(g, "障子_%d" % i, Vector3(3.4, 2.3, 0.08), _mat("wood"), Vector3(-8.6 + float(i) * 4.3, 1.85, 6.05))
	lib.gable_roof(g, 4.4, 25.0, 15.0, 0.5, 0.34, _mat("kawara"), _mat("plaster"))
	_collide(g, Vector3(22.4, 6.2, 12.4))
	_claim(cx, cz, 25.0, 15.0)
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
		var wfoot := spread + 0.3
		lib.box(g, "土塀_%d_%d" % [int(w[0]), int(w[1])],
			Vector3(w[2] if w[3] else 0.36, 2.2 + wfoot, 0.36 if w[3] else w[2]), _mat("mud"),
			Vector3(w[0], 1.1 - wfoot * 0.5, w[1]))
		lib.box(g, "塀瓦_%d_%d" % [int(w[0]), int(w[1])],
			Vector3((w[2] + 0.2) if w[3] else 0.62, 0.15, 0.62 if w[3] else (w[2] + 0.2)), _mat("kawara"),
			Vector3(w[0], 2.28, w[1]))
		_collide(g, Vector3(w[2] if w[3] else 0.5, 2.4, 0.5 if w[3] else w[2]), Vector3(w[0], 0, w[1]))
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
	var moss_m := lib.rock_mat()
	# 兩種石色：靠水的長苔偏綠、離水的偏乾灰。只有一種色的話整圈石頭是同一塊。
	var dry_m := lib.rock_mat_dry()
	# 石頭要坐在**自己腳下**的地面上。這棟宅子的原點是整塊地的基準高度，
	# 池邊的地已經往下挖了 —— 照原點擺，石頭會浮在水面上像紙片。
	var rock_y := func(wx: float, wz: float, sink: float) -> float:
		return height_at(wx, wz) - g.position.y - sink
	# 掃滿一整圈：起點隨機、但走的總角度是 TAU（v8 初版寫成 while ang < TAU，
	# 起點若落在 5.5 rad 就只鋪了一小段，池邊等於光禿禿的）
	var ang := lib.rr(0.0, TAU)
	var swept := 0.0
	var rk_i := 0
	while swept < TAU:
		var group := 2 + int(lib.rand() * 3.0)      # 一組 2~4 顆
		var ga := ang
		for k in group:
			var a := ga + float(k) * lib.rr(0.10, 0.20)
			var sc: float = lib.rr(0.5, 1.25) * (1.25 if k == 0 else 0.8)   # 主石 + 添石
			var rr3: float = shore * lib.rr(0.99, 1.14)
			var rk := MeshInstance3D.new()
			rk.mesh = lib.prop_mesh(Lib.ROCK_GLBS[int(lib.rand() * 4.0)], moss_m if lib.rand() < 0.55 else dry_m)
			var wx: float = bx + pl.x + cos(a) * rr3
			var wz: float = bz + pl.z + sin(a) * rr3
			rk.position = Vector3(pl.x + cos(a) * rr3,
				rock_y.call(wx, wz, sc * lib.rr(0.25, 0.55)), pl.z + sin(a) * rr3)
			rk.scale = Vector3(sc * lib.rr(0.85, 1.35), sc * lib.rr(0.68, 1.0), sc * lib.rr(0.85, 1.35))
			rk.rotation = Vector3(lib.rr(-0.35, 0.35), lib.rr(0.0, TAU), lib.rr(-0.35, 0.35))
			lib.add(g, rk, "護岸石_%d" % rk_i)
			rk_i += 1
			swept += a - ang
			ang = a
		# 留白：這段岸沒有大石，改鋪一排半埋的小卵石（州濱）
		var gap: float = lib.rr(0.35, 0.95)
		var pebbles := int(gap * 9.0)
		for k2 in pebbles:
			var a3 := ang + gap * (float(k2) + 0.5) / float(maxi(pebbles, 1)) + lib.rr(-0.05, 0.05)
			var sc2 := lib.rr(0.14, 0.30)
			var pb := MeshInstance3D.new()
			pb.mesh = lib.prop_mesh(Lib.ROCK_GLBS[int(lib.rand() * 4.0)], moss_m)
			var pr: float = shore * lib.rr(1.0, 1.10)
			pb.position = Vector3(pl.x + cos(a3) * pr,
				rock_y.call(bx + pl.x + cos(a3) * pr, bz + pl.z + sin(a3) * pr, sc2 * 0.5),
				pl.z + sin(a3) * pr)
			pb.scale = Vector3(sc2 * 1.3, sc2 * 0.55, sc2 * 1.3)
			pb.rotation.y = lib.rr(0.0, TAU)
			lib.add(g, pb, "州濱_%d" % rk_i)
			rk_i += 1
		ang += gap
		swept += gap
	# 池面：睡蓮與菖蒲。空的水面就只是一塊色板 —— 要有東西打斷它。
	var pad := lib.tuft_mesh(6, 0.26, 0.30, Color(0.16, 0.30, 0.14), Color(0.28, 0.46, 0.20))
	for i in 14:
		var pa := lib.rr(0.0, TAU)
		var pd: float = shore * lib.rr(0.15, 0.86)
		var lp := MeshInstance3D.new()
		lp.mesh = pad
		lp.position = Vector3(pl.x + cos(pa) * pd,
			rock_y.call(bx + pl.x + cos(pa) * pd, bz + pl.z + sin(pa) * pd, GARDEN_POND_SINK - 0.04),
			pl.z + sin(pa) * pd)
		lp.scale = Vector3.ONE * lib.rr(0.7, 1.3)
		lp.rotation.y = lib.rr(0.0, TAU)
		lib.add(g, lp, "睡蓮_%d" % i)
	# 岸邊的菖蒲叢（水際的垂直元素，讓水岸不是一條硬邊）
	var iris := lib.tuft_mesh(7, 0.70, 0.10, Color(0.12, 0.26, 0.10), Color(0.34, 0.54, 0.20))
	for i in 22:
		var ia := lib.rr(0.0, TAU)
		var ir: float = shore * lib.rr(0.94, 1.06)
		var ib := MeshInstance3D.new()
		ib.mesh = iris
		ib.position = Vector3(pl.x + cos(ia) * ir,
			rock_y.call(bx + pl.x + cos(ia) * ir, bz + pl.z + sin(ia) * ir, 0.05),
			pl.z + sin(ia) * ir)
		ib.scale = Vector3.ONE * lib.rr(0.7, 1.25)
		ib.rotation.y = lib.rr(0.0, TAU)
		lib.add(g, ib, "菖蒲_%d" % i)
	print("garden pond rocks: ", rk_i)
	for i in 3:                                    # 池中的三尊石組
		var a2 := float(i) / 3.0 * TAU + 0.7
		var d2: float = shore * lib.rr(0.25, 0.5)
		var sc3 := lib.rr(0.6, 1.1)
		var rk3 := MeshInstance3D.new()
		rk3.mesh = lib.prop_mesh(Lib.ROCK_GLBS[int(lib.rand() * 4.0)], moss_m)
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
	_claim(bx, bz, BLOCK_W + 2.0, BLOCK_D + 2.0)

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
	_claim(bx, bz, BLOCK_W, BLOCK_D)

## 市集街區：不設圍牆的開放廣場（攤位、龍神像）
func _blk_market(parent: Node, bx: float, bz: float) -> void:
	var wood := _mat("wood")
	var stone := _mat("stone")
	# 龍神像（THBWiki 設施清單）—— Blender 雕的完整龍（曲面龍身、五爪、
	# 鬃鰭、角鬚、龍珠、石柱與基壇），不再是方塊堆。
	var dstat := MeshInstance3D.new()
	dstat.mesh = lib.prop_mesh("res://assets/models/dragon_statue.glb", _mat("stone"))
	dstat.position = Vector3(bx - 12.0, height_at(bx - 12.0, bz - 10.0), bz - 10.0)
	dstat.rotation.y = 0.6
	lib.add(parent, dstat, "龍神像")
	var dbody := StaticBody3D.new()
	dstat.add_child(dbody)
	dbody.owner = lib.root
	var dsh := CollisionShape3D.new()
	var dbx := BoxShape3D.new()
	dbx.size = Vector3(3.0, 7.6, 3.0)
	dsh.shape = dbx
	dsh.position = Vector3(0, 3.8, 0)
	dbody.add_child(dsh)
	dsh.owner = lib.root
	_claim(bx - 12.0, bz - 10.0, 4.0, 4.0)
	# 攤位群
	var cloths := [Color(0.62, 0.3, 0.26), Color(0.28, 0.36, 0.52), Color(0.72, 0.6, 0.3), Color(0.34, 0.46, 0.32)]
	var placed := 0
	for i in 12:
		var px := bx - 14.0 + float(i % 4) * 9.0 + lib.rr(-0.8, 0.8)
		var pz := bz - 2.0 + float(i / 4) * 8.5 + lib.rr(-0.8, 0.8)
		if not _free(px, pz, 3.4, 2.6, 0.4):
			continue
		placed += 1
		var st := Node3D.new()
		st.position = Vector3(px, height_at(px, pz), pz)
		st.rotation.y = lib.rr(-0.25, 0.25)
		lib.add(parent, st, "攤_%d" % i)
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				lib.cyl(st, "腳_%d%d" % [sx + 1, sz + 1], 0.05, 0.05, 2.2, wood,
					Vector3(float(sx) * 1.3, 1.1, float(sz) * 0.9), 6)
		lib.box(st, "檯面", Vector3(2.8, 0.12, 1.9), wood, Vector3(0, 0.95, 0))
		var cm := StandardMaterial3D.new()
		cm.albedo_color = cloths[i % cloths.size()]
		cm.roughness = 1.0
		var top := lib.box(st, "棚布", Vector3(3.2, 0.08, 2.4), cm, Vector3(0, 2.35, -0.2))
		top.rotation.x = 0.16
		lib.box(st, "貨箱", Vector3(0.8, 0.5, 0.6), wood, Vector3(lib.rr(-1, 1), 0.25, 1.4))
		_collide(st, Vector3(3.0, 1.1, 2.2))
		_claim(px, pz, 3.6, 2.8)
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
	_claim(wp.x, wp.y, 5.2, 5.0)
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
	_claim(np.x, np.y, 3.2, 1.4)
	print("market stalls: ", placed)

## 火見櫓街區：木塔 + 番屋（消防小屋）
func _blk_tower(parent: Node, bx: float, bz: float) -> void:
	var dark := _mat("dark")
	var wood := _mat("wood")
	var tgu := _ground_under(bx, bz, 7.0, 7.0)
	var f := Node3D.new()
	f.position = Vector3(bx, tgu[0], bz)
	lib.add(parent, f, "火見櫓")
	for i in 4:
		var sx := 1.0 if i % 2 == 0 else -1.0
		var sz := 1.0 if i < 2 else -1.0
		for lvl in 3:
			var y0 := float(lvl) * 3.6
			var sp0 := 2.6 - float(lvl) * 0.6
			var sp1 := 2.6 - float(lvl + 1) * 0.6
			var col := lib.cyl(f, "柱_%d_%d" % [i, lvl], 0.13, 0.15, 3.7, dark,
				Vector3(sx * (sp0 + sp1) * 0.5, y0 + 1.85, sz * (sp0 + sp1) * 0.5), 6)
			col.rotation.z = -sx * 0.08
			col.rotation.x = sz * 0.08
	for lvl in 3:
		var y1 := float(lvl) * 3.6 + 3.6
		var sp2 := 2.6 - float(lvl + 1) * 0.6
		for sd in [-1, 1]:
			lib.box(f, "橫材_%d_%d" % [lvl, sd + 1], Vector3(sp2 * 2.2, 0.12, 0.12), dark,
				Vector3(0, y1, float(sd) * sp2))
			lib.box(f, "橫材b_%d_%d" % [lvl, sd + 1], Vector3(0.12, 0.12, sp2 * 2.2), dark,
				Vector3(float(sd) * sp2, y1, 0))
	lib.box(f, "樓板", Vector3(4.0, 0.2, 4.0), wood, Vector3(0, 10.9, 0))
	for sd3 in [-1, 1]:
		lib.box(f, "欄杆_%d" % (sd3 + 1), Vector3(4.0, 0.55, 0.09), wood, Vector3(0, 11.4, float(sd3) * 1.95))
		lib.box(f, "欄杆b_%d" % (sd3 + 1), Vector3(0.09, 0.55, 4.0), wood, Vector3(float(sd3) * 1.95, 11.4, 0))
		lib.cyl(f, "屋根柱_%d" % (sd3 + 1), 0.09, 0.09, 1.9, dark, Vector3(float(sd3) * 1.6, 12.05, 0), 6)
	var roof := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.0
	rm.bottom_radius = 3.4
	rm.height = 1.5
	rm.radial_segments = 4
	rm.material = _mat("kawara")
	roof.mesh = rm
	roof.position = Vector3(0, 13.6, 0)
	roof.rotation.y = PI / 4.0
	lib.add(f, roof, "望樓屋根")
	lib.cyl(f, "半鐘", 0.3, 0.36, 0.55, lib.flat_mat("bell", Color(0.42, 0.36, 0.22), 0.4),
		Vector3(1.2, 11.7, 0), 10)
	_collide(f, Vector3(5.2, 3.2, 5.2))
	_claim(bx, bz, 7.0, 7.0)
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
	print("canal bank stones: ", n)

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
		_claim(px, pz, 5.0, 5.0)
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
	_claim(NATURE_POND.x, NATURE_POND.y, NATURE_POND_R * 2.8, NATURE_POND_R * 2.8)
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
		lib.box(p, "橋板", Vector3(4.2, 0.28, span), wood, Vector3.ZERO)
		for sd in [-1, 1]:
			lib.box(p, "橋台_%d" % (sd + 1), Vector3(4.4, CANAL_DEPTH + 0.9, 1.6), stone,
				Vector3(0, -(CANAL_DEPTH + 0.9) * 0.5, float(sd) * (span * 0.5 - 0.7)))
			# 欄杆
			lib.box(p, "欄_%d" % (sd + 1), Vector3(0.12, 0.1, span), dark, Vector3(float(sd) * 2.0, 0.75, 0))
			for k2 in 3:
				lib.cyl(p, "欄柱_%d_%d" % [sd + 1, k2], 0.07, 0.07, 0.85, dark,
					Vector3(float(sd) * 2.0, 0.42, -span * 0.35 + float(k2) * span * 0.35), 5)
		var body := StaticBody3D.new()
		p.add_child(body)
		body.owner = lib.root
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(4.2, 0.3, span)
		shape.shape = bs
		body.add_child(shape)
		shape.owner = lib.root
		_claim(bx, bz, 4.5, span + 1.0)
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
		var ap := Node3D.new()
		ap.position = Vector3(cxy.x, height_at(cxy.x, cxy.y), cxy.y)
		ap.rotation.y = atan2(fd.x, fd.y)            # 本地 +z 對齊「朝街道」
		lib.add(g, ap, "店前鋪面_%d" % n_apron)
		# 鋪面：3×2 塊石板，微微高於街面
		for ix in 3:
			for iz in 2:
				var sl := lib.box(ap, "石板_%d%d" % [ix, iz], Vector3(1.38, 0.20, 1.38), slab,
					Vector3((float(ix) - 1.0) * 1.42, -0.06, (float(iz) - 0.5) * 1.42))
				sl.rotation.y = lib.rr(-0.02, 0.02)
		# 飛石：從鋪面繼續往街心走
		for k in 3:
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
		_claim(cxy.x, cxy.y, 4.2, 3.4)
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
		_claim(wx, wz, 4.6, 4.6)
	# 最後才把整個街區圈起來，別的東西就不會蓋進來
	_claim(c.x, c.y, BLOCK_W + 2.0, BLOCK_D + 2.0)
	print("grove: 神木 + 玉垣 @ (", int(c.x), ",", int(c.y), ")")

# ── 生活感雜物：曬衣、柴堆、水桶、農具、俵 ──
## 每一件都要先問 _free 再 _claim（使用者：「放之前先算會不會擋住」）。
func _build_clutter() -> void:
	var g := lib.add(lib.root, Node3D.new(), "Clutter")
	var wood := _mat("wood")
	var dark := _mat("dark")
	var n := 0
	var tries := 0
	while n < 320 and tries < 26000:
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
		var p := Node3D.new()
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
					lib.box(p, "布_%d" % k, Vector3(0.5, lib.rr(0.7, 1.05), 0.02), cloth,
						Vector3(-0.9 + float(k) * 0.9, 1.82 - lib.rr(0.36, 0.53), 0))
			1:      # 薪積み（柴堆）
				var rows := 3 + int(lib.rand() * 2.0)
				for r in rows:
					for k2 in 5:
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
		lib.add(g, p, "雜物_%d" % n)
		_claim(x, z, 4.0, 4.0)
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
			for i in 7:
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
		_claim(x, z, 2.8, 2.8)
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
		_claim(d.x, d.z, 13.0, 2.5)

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
			_claim(x, z, 5.0, 5.0)
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
