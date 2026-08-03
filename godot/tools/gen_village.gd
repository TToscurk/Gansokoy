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
const HALF := 230.0
const PLAZA := Vector2(0.0, 30.0)
const CORE := 140.0

# ── 街道格：南北 x = -104/-52/0/52/104、東西 z = -135/-80/-25/30/85/140 ──
const ST_X := [-104.0, -52.0, 0.0, 52.0, 104.0]
const ST_Z := [-135.0, -80.0, -25.0, 30.0, 85.0, 140.0]
const BLOCK_X := [-78.0, -26.0, 26.0, 78.0]      # 街區中心
const BLOCK_Z := [-107.0, -52.0, 2.0, 57.0, 112.0]
const BLOCK_W := 42.0
const BLOCK_D := 45.0

const PATH_SEGMENTS := [
	# 本通（主街・南北貫穿，最寬）
	{ "width": 10.0, "pts": [[0.0, -174.0], [0.0, -80.0], [0.0, 30.0], [0.0, 140.0], [0.0, 190.0]] },
	# 橫町（0.2 條・東西中段，東端過橋）
	{ "width": 8.4, "pts": [[-130.0, 30.0], [-52.0, 30.0], [0.0, 30.0], [52.0, 30.0], [104.0, 30.0], [146.0, 30.0]] },
	# 其餘南北街
	{ "width": 7.0, "pts": [[-104.0, -135.0], [-104.0, 0.0], [-104.0, 140.0]] },
	{ "width": 7.0, "pts": [[-52.0, -135.0], [-52.0, 0.0], [-52.0, 140.0]] },
	{ "width": 7.0, "pts": [[52.0, -135.0], [52.0, 0.0], [52.0, 140.0]] },
	{ "width": 7.0, "pts": [[104.0, -135.0], [104.0, 0.0], [104.0, 140.0]] },
	# 其餘東西街
	{ "width": 7.0, "pts": [[-126.0, -135.0], [0.0, -135.0], [126.0, -135.0]] },
	{ "width": 7.0, "pts": [[-126.0, -80.0], [0.0, -80.0], [126.0, -80.0]] },
	{ "width": 7.0, "pts": [[-126.0, -25.0], [0.0, -25.0], [126.0, -25.0]] },
	{ "width": 7.0, "pts": [[-126.0, 85.0], [0.0, 85.0], [126.0, 85.0]] },
	{ "width": 7.0, "pts": [[-126.0, 140.0], [0.0, 140.0], [126.0, 140.0]] },
	# 西南門引道（香霖堂）
	{ "width": 5.2, "pts": [[-132.0, 100.0], [-118.0, 96.0], [-104.0, 90.0]] },
]
# ── 河（東側，橫町東端石橋跨過；北端往圖外＝河畔道接口） ──
const RIVER := [[196.0, -230.0], [178.0, -150.0], [162.0, -70.0], [152.0, -10.0],
	[150.0, 30.0], [156.0, 90.0], [170.0, 160.0], [186.0, 230.0]]
const RIVER_HALF := 8.0
const RIVER_DEPTH := 2.8
const BRIDGE := Vector2(151.0, 30.0)

## 街區用途（依 THBWiki 設施清單配置）
const BLOCK_KIND := {
	"-78,-107": "compound", "-26,-107": "compound", "26,-107": "compound", "78,-107": "compound",
	"-78,-52": "compound", "-26,-52": "terakoya", "26,-52": "suzunaan", "78,-52": "compound",
	"-78,2": "hieda", "-26,2": "compound", "26,2": "unomitei", "78,2": "compound",
	"-78,57": "compound", "-26,57": "market", "26,57": "tower", "78,57": "compound",
	"-78,112": "compound", "-26,112": "compound", "26,112": "ashiarai", "78,112": "compound",
}

var lib: Lib
var _nh: FastNoiseLite
var _n2: FastNoiseLite
var _rects: Array = []

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
	if r < CORE + 8.0 or r > 205.0:
		return 0.0
	if lib.poly_dist(RIVER, x, z) < RIVER_HALF * 2.4:
		return 0.0
	if _path_info(x, z)[0] < 3.0:
		return 0.0
	var row := fmod(absf(z * 0.7 + x * 0.3), 8.0)
	return 0.9 if row > 1.6 else 0.1

## 地勢：里在整過地的台地上（幾乎全平），外圍起伏；河道下切
func height_at(x: float, z: float) -> float:
	var roll := _nh.get_noise_2d(x, z) * 2.4
	var town := smoothstep(CORE - 20.0, CORE + 70.0, Vector2(x, z - PLAZA.y).length())
	var h := roll * (0.06 + 0.94 * town) + sin(x * 0.46 + z * 0.33) * 0.04
	return h + lib.river_carve(RIVER, RIVER_HALF, RIVER_DEPTH, x, z)

func mask_at(x: float, z: float) -> Color:
	var info := _path_info(x, z)
	var g2 := clampf(_n2.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var rd := lib.poly_dist(RIVER, x, z)
	var shore := 1.0 - smoothstep(RIVER_HALF * 0.7, RIVER_HALF * 1.9, rd)
	# 里內的地面本來就是踏實的砂土（參考圖：整片砂色），街區內庭才有綠
	var in_town := 1.0 - smoothstep(CORE - 30.0, CORE + 10.0, Vector2(x, z - PLAZA.y).length())
	var packed_earth := in_town * 0.55
	var path_w: float = maxf(maxf(info[1], shore), packed_earth)
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

	lib.terrain(OUT_DIR, HALF, 181, height_at, mask_at)
	lib.boundary(HALF - 2.0)
	lib.river_water(OUT_DIR, RIVER, RIVER_HALF, RIVER_DEPTH * 0.6, height_at)
	_build_blocks()
	_build_bridge()
	_build_props()
	_build_gates()
	_build_lamps()
	_build_trees()
	_build_grass()
	lib.vista(OUT_DIR, HALF, 820.0, height_at, [
		{ "x": -520.0, "z": -560.0, "h": 140.0, "r": 240.0 },
		{ "x": 480.0, "z": -420.0, "h": 55.0, "r": 180.0 },
	], "res://assets/models/tree_round_b.glb", 320)
	_build_env()

	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, OUT_DIR + "village.tscn")
	print("saved village.tscn err=", err)
	quit()

# ═══════════════════════════════════ 工具 ═══════════════════════════════
func _claim(cx: float, cz: float, w: float, d: float) -> void:
	_rects.append([cx, cz, w, d])

func _free(cx: float, cz: float, w: float, d: float, margin := 0.6) -> bool:
	var hw := w * 0.5 + margin
	var hd := d * 0.5 + margin
	for c in [[cx - hw, cz - hd], [cx + hw, cz - hd], [cx - hw, cz + hd], [cx + hw, cz + hd], [cx, cz]]:
		if _path_info(c[0], c[1])[0] < 0.6:
			return false
	if lib.poly_dist(RIVER, cx, cz) < RIVER_HALF * 1.9:
		return false
	for r in _rects:
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

func _mat(key: String) -> StandardMaterial3D:
	match key:
		"kawara": return lib.pbr("kawara", "roof_kawara", 0.22, Color(0.8, 0.84, 0.92))
		"thatch": return lib.pbr("thatch", "roof_thatch", 0.3, Color(0.95, 0.9, 0.78))
		"plaster": return lib.pbr("plaster", "plaster", 0.4)
		"mud": return lib.pbr("mud_wall", "plaster", 0.5, Color(0.80, 0.72, 0.58))
		"dark": return lib.pbr("dark_wood", "dark_wood", 0.45)
		"wood": return lib.pbr("wood", "planks", 0.5, Color(0.9, 0.82, 0.72))
		"stone": return lib.pbr("stone", "stone_wall", 0.30)
	return lib.pbr("plaster", "plaster", 0.4)

## 長屋：街區周邊的長條建築。ridge_along_x = 屋脊沿 x 軸（南北向的牆用）
func _longhouse(parent: Node, name: String, cx: float, cz: float, length: float, depth: float,
		ridge_along_x: bool, storey := 1, roof := "kawara") -> void:
	var wall := _mat("plaster") if lib.rand() < 0.6 else _mat("mud")
	var dark := _mat("dark")
	var stone := _mat("stone")
	var roof_m := _mat(roof)
	var h := 3.0 if storey == 1 else 5.0
	var g := Node3D.new()
	g.position = Vector3(cx, height_at(cx, cz), cz)
	if not ridge_along_x:
		g.rotation.y = PI / 2.0
	lib.add(parent, g, name)
	# 本體（本地座標一律「長邊沿 x」，靠 rotation 轉向）
	lib.box(g, "基石", Vector3(length + 0.4, 0.32, depth + 0.4), stone, Vector3(0, 0.16, 0))
	lib.box(g, "屋身", Vector3(length, h, depth), wall, Vector3(0, 0.32 + h * 0.5, 0))
	# 立面分割：柱與腰板（長屋的節奏感）
	var bays := int(length / 3.4)
	for i in bays + 1:
		var px := -length * 0.5 + float(i) * (length / float(maxi(bays, 1)))
		lib.box(g, "柱_%d" % i, Vector3(0.2, h, 0.22), dark, Vector3(px, 0.32 + h * 0.5, depth * 0.5 + 0.02))
	lib.box(g, "腰板", Vector3(length + 0.05, 0.9, 0.08), dark, Vector3(0, 0.78, depth * 0.5 + 0.05))
	for i in maxi(bays, 1):
		var dx := -length * 0.5 + (float(i) + 0.5) * (length / float(maxi(bays, 1)))
		if lib.rand() < 0.5:
			lib.box(g, "格子戶_%d" % i, Vector3(2.0, 1.9, 0.1), dark, Vector3(dx, 1.55, depth * 0.5 + 0.06))
		else:
			lib.box(g, "板壁_%d" % i, Vector3(2.2, 1.9, 0.08), _mat("wood"), Vector3(dx, 1.55, depth * 0.5 + 0.05))
	if storey == 2:
		lib.box(g, "二階窗", Vector3(length * 0.75, 1.1, 0.08), dark, Vector3(0, 4.0, depth * 0.5 + 0.05))
		lib.box(g, "庇", Vector3(length + 0.8, 0.14, 1.1), roof_m, Vector3(0, 3.1, depth * 0.5 + 0.42))
	# 切妻屋頂
	var rl := length + 0.9
	var rd := depth + 1.5
	var thick := 0.22 if roof == "kawara" else 0.5
	var lift := 0.85 if roof == "kawara" else 1.15
	var pitch := 0.58 if roof == "kawara" else 0.72
	for s in [-1, 1]:
		var slope := lib.box(g, "屋頂_%d" % (s + 1), Vector3(rl, thick, rd * 0.64), roof_m,
			Vector3(0, 0.32 + h + lift, float(s) * rd * 0.21))
		slope.rotation.x = float(s) * pitch
	lib.box(g, "棟", Vector3(rl + 0.25, thick * 1.2, 0.8), roof_m, Vector3(0, 0.32 + h + lift + 0.85, 0))
	_collide(g, Vector3(length + 0.4, h + 2.0, depth + 0.4))
	if ridge_along_x:
		_claim(cx, cz, length + 1.0, depth + 1.6)
	else:
		_claim(cx, cz, depth + 1.6, length + 1.0)

## 土塀：街區外圍的圍牆（帶瓦冠）
func _wall_run(parent: Node, name: String, cx: float, cz: float, length: float, along_x: bool) -> void:
	if length < 1.0:
		return
	var g := Node3D.new()
	g.position = Vector3(cx, height_at(cx, cz), cz)
	if not along_x:
		g.rotation.y = PI / 2.0
	lib.add(parent, g, name)
	lib.box(g, "塀", Vector3(length, 1.9, 0.34), _mat("mud"), Vector3(0, 0.95, 0))
	lib.box(g, "塀瓦", Vector3(length + 0.2, 0.14, 0.62), _mat("kawara"), Vector3(0, 1.97, 0))
	_collide(g, Vector3(length, 2.1, 0.5))

# ═══════════════════════════════ 街區 ═══════════════════════════════════
func _build_blocks() -> void:
	var root := lib.add(lib.root, Node3D.new(), "Blocks")
	var n_house := 0
	for bx in BLOCK_X:
		for bz in BLOCK_Z:
			var kind: String = BLOCK_KIND.get("%d,%d" % [int(bx), int(bz)], "compound")
			var g := lib.add(root, Node3D.new(), "街區_%d_%d_%s" % [int(bx), int(bz), kind])
			match kind:
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
		var inset := (hd - 4.2) if along_x else (hw - 4.2)
		var sgn := -1.0 if side % 2 == 0 else 1.0
		var has_house := lib.rand() < 0.86
		if has_house:
			var length := span * lib.rr(0.48, 0.68)   # 轉角要留空，太長四邊會互相排擠
			var depth := lib.rr(6.4, 8.2)
			var off := lib.rr(-0.45, 0.45) * (span - length)
			var cx := bx + (off if along_x else sgn * inset)
			var cz := bz + (sgn * inset if along_x else off)
			if _free(cx, cz, length if along_x else depth, depth if along_x else length, 0.2):
				var storey := 2 if lib.rand() < 0.3 else 1
				var roof := "kawara" if lib.rand() < 0.72 else "thatch"
				_longhouse(parent, "長屋_%d" % side, cx, cz, length, depth, along_x, storey, roof)
				n += 1
				# 兩端補土塀
				var rem := (span - length) * 0.5
				for e in [-1.0, 1.0]:
					var eo: float = off + float(e) * (length + rem) * 0.5
					var wcx: float = bx + (eo if along_x else sgn * (hw - 0.4))
					var wcz: float = bz + (sgn * (hd - 0.4) if along_x else eo)
					_wall_run(parent, "塀_%d_%d" % [side, int(e)], wcx, wcz, maxf(rem - 0.6, 0.0), along_x)
				continue
		# 沒有房子的邊：整段土塀（大門那邊留缺口）
		var wl := span - (7.0 if side == gate_side else 0.0)
		_wall_run(parent, "塀全_%d" % side, bx + (0.0 if along_x else sgn * (hw - 0.4)),
			bz + (sgn * (hd - 0.4) if along_x else 0.0), wl, along_x)
	# 內庭：離れ（後棟小屋）—— 街區內部也要有東西
	for k in 2:
		var ix := bx + lib.rr(-11.0, 11.0)
		var iz := bz + lib.rr(-11.0, 11.0)
		if lib.rand() < 0.55 and _free(ix, iz, 11.0, 7.0, 0.5):
			_longhouse(parent, "離れ_%d" % k, ix, iz, lib.rr(8.0, 11.0), lib.rr(5.5, 6.8),
				lib.rand() < 0.5, 1, "kawara" if lib.rand() < 0.5 else "thatch")
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
			for sd in [-1, 1]:
				var sl := lib.box(s, "屋頂_%d" % (sd + 1), Vector3(6.2, 0.22, 3.2), _mat("kawara"),
					Vector3(0, 5.1, float(sd) * 1.1))
				sl.rotation.x = float(sd) * 0.6
			lib.box(s, "棟", Vector3(6.4, 0.26, 0.7), _mat("kawara"), Vector3(0, 5.75, 0))
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
	for sd in [-1, 1]:
		var sl := lib.box(g, "屋頂_%d" % (sd + 1), Vector3(w + 1.4, 0.24, (d + 1.6) * 0.64), _mat("kawara"),
			Vector3(0, 6.45, float(sd) * (d + 1.6) * 0.21))
		sl.rotation.x = float(sd) * 0.58
	lib.box(g, "棟", Vector3(w + 1.7, 0.28, 0.85), _mat("kawara"), Vector3(0, 7.35, 0))
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
	for sd in [-1, 1]:
		var sl := lib.box(g, "大屋根_%d" % (sd + 1), Vector3(25.0, 0.34, 10.0), _mat("kawara"),
			Vector3(0, 5.9, float(sd) * 3.4))
		sl.rotation.x = float(sd) * 0.55
	lib.box(g, "大棟", Vector3(25.4, 0.4, 1.2), _mat("kawara"), Vector3(0, 7.15, 0))
	_collide(g, Vector3(22.4, 6.2, 12.4))
	_claim(cx, cz, 25.0, 15.0)
	# 前庭：手水缽與立札
	lib.box(g, "立札", Vector3(1.6, 1.1, 0.1), _mat("wood"), Vector3(-8.0, 1.3, 10.5))
	lib.cyl(g, "手水缽", 0.7, 0.75, 0.7, _mat("stone"), Vector3(9.0, 0.35, 10.0), 10)
	_blk_compound(parent, bx, bz)

## 稗田邸：土塀圍院 + 表門 + 主屋 + 長廊 + 庭園水池與楓樹（THBWiki 考據）
func _blk_hieda(parent: Node, bx: float, bz: float) -> void:
	var g := Node3D.new()
	g.position = Vector3(bx, height_at(bx, bz), bz)
	lib.add(parent, g, "稗田邸")
	var hw := BLOCK_W * 0.5 - 1.0
	var hd := BLOCK_D * 0.5 - 1.0
	# 圍牆（南面留門）
	for w in [[0.0, -hd, hw * 2.0, true], [-hw, 0.0, hd * 2.0, false], [hw, 0.0, hd * 2.0, false],
			[-hw * 0.62, hd, hw * 0.76, true], [hw * 0.62, hd, hw * 0.76, true]]:
		lib.box(g, "土塀_%d_%d" % [int(w[0]), int(w[1])],
			Vector3(w[2] if w[3] else 0.36, 2.2, 0.36 if w[3] else w[2]), _mat("mud"),
			Vector3(w[0], 1.1, w[1]))
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
	lib.box(g, "主屋基壇", Vector3(19.0, 0.55, 13.0), _mat("stone"), Vector3(-3.0, 0.28, -7.0))
	lib.box(g, "主屋", Vector3(17.5, 4.0, 11.5), _mat("plaster"), Vector3(-3.0, 2.55, -7.0))
	lib.box(g, "緣側", Vector3(18.4, 0.26, 2.0), _mat("wood"), Vector3(-3.0, 0.68, -0.8))
	for sd in [-1, 1]:
		var sl := lib.box(g, "主屋根_%d" % (sd + 1), Vector3(20.0, 0.32, 9.4), _mat("kawara"),
			Vector3(-3.0, 5.8, -7.0 + float(sd) * 3.3))
		sl.rotation.x = float(sd) * 0.56
	lib.box(g, "主屋棟", Vector3(20.4, 0.36, 1.1), _mat("kawara"), Vector3(-3.0, 7.0, -7.0))
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
	# 庭園：水池（池邊楓樹的位置留給樹散佈）
	var pond := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 5.2
	pm.bottom_radius = 4.6
	pm.height = 0.3
	pm.radial_segments = 18
	var water := ShaderMaterial.new()
	water.shader = load("res://assets/shaders/water.gdshader")
	water.set_shader_parameter("wave_nor", load("res://assets/textures/terrain_grass_nor_gl.jpg"))
	pm.material = water
	pond.mesh = pm
	pond.position = Vector3(-2.0, 0.12, 8.0)
	pond.scale = Vector3(1.4, 1.0, 1.0)
	lib.add(g, pond, "庭池")
	for i in 10:                                   # 池畔的石組
		var a := float(i) / 10.0 * TAU
		lib.box(g, "護岸石_%d" % i, Vector3(lib.rr(0.6, 1.1), 0.5, lib.rr(0.6, 1.0)), _mat("stone"),
			Vector3(-2.0 + cos(a) * 7.4, 0.2, 8.0 + sin(a) * 5.4))
	lib.box(g, "石燈籠基", Vector3(0.7, 0.24, 0.7), _mat("stone"), Vector3(5.5, 0.12, 12.0))
	lib.cyl(g, "石燈籠竿", 0.14, 0.16, 1.2, _mat("stone"), Vector3(5.5, 0.85, 12.0), 8)
	lib.box(g, "石燈籠火袋", Vector3(0.55, 0.5, 0.55), _mat("stone"), Vector3(5.5, 1.7, 12.0))
	lib.box(g, "石燈籠笠", Vector3(0.85, 0.18, 0.85), _mat("stone"), Vector3(5.5, 2.02, 12.0))
	_claim(bx, bz, BLOCK_W + 2.0, BLOCK_D + 2.0)

## 足洗邸：荒廢的宅子（傳說中的妖怪宅）—— 土塀有缺口、屋頂塌一角
func _blk_ashiarai(parent: Node, bx: float, bz: float) -> void:
	var g := Node3D.new()
	g.position = Vector3(bx, height_at(bx, bz), bz)
	lib.add(parent, g, "足洗邸")
	var hw := BLOCK_W * 0.5 - 2.0
	var hd := BLOCK_D * 0.5 - 2.0
	for w in [[0.0, -hd, hw * 1.4, true], [-hw, -6.0, hd * 0.9, false], [hw, 4.0, hd * 0.8, false]]:
		lib.box(g, "崩れ塀_%d" % int(w[0]), Vector3(w[2] if w[3] else 0.36, lib.rr(1.2, 1.9), 0.36 if w[3] else w[2]),
			_mat("mud"), Vector3(w[0], 0.8, w[1]))
	lib.box(g, "母屋基壇", Vector3(16.0, 0.5, 12.0), _mat("stone"), Vector3(0, 0.25, -2.0))
	lib.box(g, "母屋", Vector3(14.5, 3.6, 10.5), _mat("dark"), Vector3(0, 2.3, -2.0))
	for sd in [-1, 1]:
		var sl := lib.box(g, "屋根_%d" % (sd + 1), Vector3(17.0, 0.5, 8.0), _mat("thatch"),
			Vector3(0, 5.0, -2.0 + float(sd) * 2.8))
		sl.rotation.x = float(sd) * 0.66
		if sd > 0:
			sl.rotation.z = 0.12          # 塌陷的一角
	lib.box(g, "棟", Vector3(17.2, 0.45, 0.9), _mat("thatch"), Vector3(0, 6.1, -2.0))
	_collide(g, Vector3(14.9, 5.4, 10.9), Vector3(0, 0, -2.0))
	_claim(bx, bz, 18.0, 14.0)

## 市集街區：不設圍牆的開放廣場（攤位、龍神像）
func _blk_market(parent: Node, bx: float, bz: float) -> void:
	var wood := _mat("wood")
	var stone := _mat("stone")
	# 龍神像（里的守護神）
	var d := Node3D.new()
	d.position = Vector3(bx - 12.0, height_at(bx - 12.0, bz - 10.0), bz - 10.0)
	lib.add(parent, d, "龍神像")
	lib.box(d, "台座", Vector3(3.2, 1.2, 3.2), stone, Vector3(0, 0.6, 0))
	lib.box(d, "台座上", Vector3(2.6, 0.3, 2.6), stone, Vector3(0, 1.35, 0))
	var body := lib.cyl(d, "龍身", 0.34, 0.55, 4.2, stone, Vector3(0, 3.6, 0), 8)
	body.rotation.z = 0.12
	lib.box(d, "龍首", Vector3(1.5, 0.9, 1.1), stone, Vector3(0.55, 5.9, 0))
	lib.box(d, "角", Vector3(0.2, 0.9, 0.2), stone, Vector3(0.2, 6.5, 0.3))
	lib.box(d, "角b", Vector3(0.2, 0.9, 0.2), stone, Vector3(0.2, 6.5, -0.3))
	_collide(d, Vector3(3.4, 6.5, 3.4))
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
	_collide(well, Vector3(2.5, 1.2, 2.5))
	_claim(wp.x, wp.y, 3.0, 3.0)
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
	var f := Node3D.new()
	f.position = Vector3(bx, height_at(bx, bz), bz)
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
		{ "name": "北門", "x": 0.0, "z": -152.0, "yaw": 0.0 },
		{ "name": "西南門", "x": -120.0, "z": 96.0, "yaw": 0.42 },
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
		variants.append({ "mesh": lib.tree_mesh(glb), "list": [] })
	var count := 0
	var tries := 0
	while count < 1200 and tries < 60000:
		tries += 1
		var x := lib.rr(-HALF + 3.0, HALF - 3.0)
		var z := lib.rr(-HALF + 3.0, HALF - 3.0)
		if _path_info(x, z)[0] < 3.5:
			continue
		if _field_w(x, z) > 0.2:
			continue
		if lib.poly_dist(RIVER, x, z) < RIVER_HALF * 1.4:
			continue
		var r0 := Vector2(x, z - PLAZA.y).length()
		if r0 < CORE:
			# 里內：只長在街區內庭的空隙（參考圖：每個院子都有一兩棵樹）
			if not _free(x, z, 5.5, 5.5, 0.5):
				continue
			if lib.rand() > 0.35:
				continue
			_claim(x, z, 5.0, 5.0)
		elif lib.rand() > (0.45 if r0 < 195.0 else 0.85):
			continue
		var y := height_at(x, z)
		var s := lib.rr(0.9, 1.7)
		var basis := Basis(Vector3.UP, lib.rand() * TAU).scaled(Vector3(s, s * lib.rr(0.9, 1.2), s))
		var r := lib.rand()
		var vi := 0 if r < 0.4 else (1 if r < 0.7 else (2 if r < 0.85 else (3 if r < 0.95 else 4)))
		variants[vi].list.append(Transform3D(basis, Vector3(x, y, z)))
		count += 1
	var forest := lib.add(lib.root, Node3D.new(), "Trees")
	for i in variants.size():
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = lib.make_multimesh(variants[i].mesh, variants[i].list, [],
			OUT_DIR + "gen/trees_%d.res" % i)
		lib.add(forest, mmi, "Trees%d" % i)
	print("trees: ", count)

func _build_grass() -> void:
	var tall := lib.tuft_mesh(7, 0.40, 0.20, Color(0.13, 0.22, 0.08), Color(0.38, 0.50, 0.20))
	tall.surface_set_material(0, lib.grass_wind_mat(0.10))
	var flower := lib.tuft_mesh(5, 0.34, 0.16, Color(0.14, 0.23, 0.09), Color(0.36, 0.48, 0.20), true)
	flower.surface_set_material(0, lib.grass_wind_mat(0.08))
	var rice := lib.tuft_mesh(5, 0.32, 0.10, Color(0.20, 0.34, 0.12), Color(0.45, 0.62, 0.22))
	rice.surface_set_material(0, lib.grass_wind_mat(0.07))
	var reed := lib.tuft_mesh(6, 0.62, 0.14, Color(0.18, 0.28, 0.12), Color(0.52, 0.56, 0.28))
	reed.surface_set_material(0, lib.grass_wind_mat(0.13))
	var groups := [
		{ "mesh": tall, "n": 1500, "file": "grass_tall", "mode": "wild" },
		{ "mesh": flower, "n": 240, "file": "grass_flower", "mode": "wild" },
		{ "mesh": rice, "n": 3200, "file": "rice_rows", "mode": "field" },
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
				if rd < RIVER_HALF * 0.85 or rd > RIVER_HALF * 2.0:
					continue
			else:
				if _path_info(x, z)[0] < 1.0 or _field_w(x, z) > 0.2:
					continue
				if lib.poly_dist(RIVER, x, z) < RIVER_HALF * 1.2:
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
	sky_mat.sky_horizon_color = Color(0.84, 0.83, 0.74)
	sky_mat.ground_horizon_color = Color(0.72, 0.7, 0.62)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.78, 0.7)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.2
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.05
	# SDFGI 關閉：室外大場景會把畫面整個洗白（使用者回報），改靠天空環境光
	env.sdfgi_enabled = false
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.84, 0.85, 0.78)
	var we := WorldEnvironment.new()
	we.environment = env
	lib.add(lib.root, we, "WorldEnvironment")
