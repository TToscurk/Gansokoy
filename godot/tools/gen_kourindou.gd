# 香霖堂・場景產生器 —— 跑一次，輸出「真正的 .tscn」讓編輯器直接改。
#
#   godot --headless --path godot --script tools/gen_kourindou.gd
#
# 定位：這不是執行期生成。它把 web 版 maps/kourindou/kourindou.js 的佈局
# （店的位置尺寸、路網、雜物堆、林緣）翻成 Godot 節點樹存檔；跑完之後
# .tscn 就是普通場景 —— 每片屋頂、每根柱子都是獨立節點，在編輯器裡拖、
# 改、刪都行。重跑會整個覆蓋，所以**手動改過之後就別再重跑**（或先備份）。
#
# 座標與尺寸照抄 web 版（SHOP = (2,-7) 17×11×3.4、路網控制點、seed）——
# 這樣 meta.json 的碰撞箱與傳送點不用動就能對上。
extends SceneTree

const OUT_DIR := "res://maps/kourindou/"
const MAT_DIR := "res://assets/materials/"

# ── web 版佈局常數（kourindou.js） ──
const HALF := 70.0
const SHOP := { "x": 2.0, "z": -7.0, "w": 17.0, "d": 11.0, "h": 3.4 }
const YARD := { "x0": -12.0, "x1": 20.0, "z0": -32.0, "z1": -14.0 }
const PATH_SEGMENTS := [
	{ "width": 5.0, "pts": [[62.0, 10.0], [46.0, 11.0], [30.0, 10.0], [14.0, 8.0], [2.0, 7.0], [-16.0, 6.0], [-34.0, 4.0], [-50.0, 2.0], [-62.0, 0.0]] },
	{ "width": 3.0, "pts": [[2.0, 7.0], [2.0, 3.5], [2.0, 0.0]] },
	{ "width": 2.6, "pts": [[13.0, 8.0], [18.0, 2.0], [19.0, -10.0], [14.0, -21.0]] },
]

var _seed_state := 20260803
var _mats := {}
var _root: Node3D

func _rand() -> float:
	_seed_state = int((_seed_state * 1664525 + 1013904223) & 0xFFFFFFFF)
	return float(_seed_state) / 4294967296.0

func _rr(a: float, b: float) -> float:
	return a + _rand() * (b - a)

# ── 路徑距離（PathNet.edgeDist 的簡化版：折線最近距離） ──
func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

## 回傳 [離路緣距離, 路徑遮罩 0..1]
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
			mask = maxf(mask, 1.0 - smoothstep(w * 0.5 - 0.4, w * 0.5 + 1.2, d))
	return [edge, mask]

# ── 地形高度（heightAt 原樣移植） ──
func height_at(x: float, z: float) -> float:
	var roll := sin(x * 0.035) * 0.9 + sin(z * 0.041 + 1.1) * 0.75
	var ed: float = _path_info(x, z)[0]
	var h := roll * minf(1.0, (10.0 if ed == INF else ed) / 10.0)
	var inn := minf(minf(x - (YARD.x0 - 6.0), (YARD.x1 + 6.0) - x), minf(z - (YARD.z0 - 6.0), 10.0 - z))
	if inn > 0.0:
		h *= 1.0 - minf(1.0, inn / 6.0) * 0.85
	# （web 版在這裡把邊界抬成坡牆收玩家 —— Godot 版拿掉：斷邊改用
	#   遠景地形遮蔽 + 空氣牆，見 _build_vista / _build_boundary）
	return h + sin(x * 0.46 + z * 0.33) * 0.05

# ── 材質 ──
func _noise_tex(freq: float, octaves: int, s: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	n.seed = s
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 256
	t.height = 256
	t.seamless = true
	# 亮度壓在 0.78–1.0：albedo_texture 是「乘」上去的，全域噪聲會把
	# 材質整個弄黑（第一版就是這樣變剪影的）—— 只要微妙的明暗變化
	var g := Gradient.new()
	g.set_color(0, Color(0.78, 0.78, 0.78))
	g.set_color(1, Color(1.02, 1.02, 1.02))
	t.color_ramp = g
	return t

# Poly Haven PBR 材質（assets/textures/<set>_diff/nor_gl/rough.jpg）。
# triplanar：BoxMesh 每面都是 0..1 的 UV，世界座標投影才有均勻的紋理密度。
func _pbr(name: String, set_name: String, uv := 0.35, tint := Color(1, 1, 1), tri := true) -> StandardMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = load("res://assets/textures/%s_diff.jpg" % set_name)
	var nor := "res://assets/textures/%s_nor_gl.jpg" % set_name
	if ResourceLoader.exists(nor):
		m.normal_enabled = true
		m.normal_texture = load(nor)
	var rgh := "res://assets/textures/%s_rough.jpg" % set_name
	if ResourceLoader.exists(rgh):
		m.roughness_texture = load(rgh)
	m.uv1_triplanar = tri
	m.uv1_scale = Vector3(uv, uv, uv)
	var path := MAT_DIR + name + ".tres"
	ResourceSaver.save(m, path)
	m.take_over_path(path)
	_mats[name] = m
	return m

func _mat(name: String, color: Color, rough := 0.9, noisy := 0.0, emission := Color(0, 0, 0)) -> StandardMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if noisy > 0.0:
		m.albedo_texture = _noise_tex(0.05, 4, name.hash() % 1000)
		# noise 是灰階，靠 albedo_color 上色；noisy 控制對比（貼圖夠用就好）
	if emission.get_luminance() > 0.01:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 1.6
	var path := MAT_DIR + name + ".tres"
	ResourceSaver.save(m, path)
	m.take_over_path(path)
	_mats[name] = m
	return m

# ── 節點小工具 ──
func _add(parent: Node, node: Node, name: String) -> Node:
	node.name = name
	parent.add_child(node)
	node.owner = _root
	return node

func _box(parent: Node, name: String, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	mi.mesh = m
	mi.position = pos
	_add(parent, mi, name)
	return mi

func _cyl(parent: Node, name: String, r_top: float, r_bot: float, h: float, mat: Material, pos: Vector3, seg := 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = seg
	m.material = mat
	mi.mesh = m
	mi.position = pos
	_add(parent, mi, name)
	return mi

# ═══════════════════════════════════════════════════════════════
func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR + "gen"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MAT_DIR))
	_root = Node3D.new()
	_root.name = "Kourindou"

	_build_terrain()
	_build_boundary()
	_build_shop()
	_build_lamps()
	_build_junk()
	_build_forest()
	_build_vista()   # 要用 _build_forest 建好的樹材質，順序在後
	_build_env()

	var packed := PackedScene.new()
	packed.pack(_root)
	var err := ResourceSaver.save(packed, OUT_DIR + "kourindou.tscn")
	print("saved kourindou.tscn err=", err)
	quit()

# ── 地形 ──
# 顏色直接寫進頂點色（1 公尺一格 → 柔軟的低頻色塊，正是 web 版地面
# 那種斑駁感）。比自訂 shader 穩：不吃貼圖生成時序、相容模式一定過。

func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n1 := FastNoiseLite.new()
	n1.frequency = 0.055
	n1.fractal_octaves = 3
	n1.seed = 7
	var n2 := FastNoiseLite.new()
	n2.frequency = 0.021
	n2.seed = 31
	var res := 141          # 1 公尺一格
	var step := 2.0 * HALF / float(res - 1)
	for j in res:
		for i in res:
			var x := -HALF + i * step
			var z := -HALF + j * step
			st.set_uv(Vector2(float(i) / float(res - 1), float(j) / float(res - 1)))
			st.add_vertex(Vector3(x, height_at(x, z), z))
	# 注意繞向：Godot 的正面是**順時針**（跟 three.js 相反）——
	# 反了整片地就只有從地底往上看得到
	for j in res - 1:
		for i in res - 1:
			var a := j * res + i
			st.add_index(a); st.add_index(a + 1); st.add_index(a + res)
			st.add_index(a + 1); st.add_index(a + res + 1); st.add_index(a + res)
	st.generate_normals()
	var mesh := st.commit()

	# 混合遮罩烤成貼圖：R=石徑、G=林床（往西愈濃）、B=大尺度明暗。
	# 細節紋理（Poly Haven PBR）在 shader 裡用世界座標平舖，遮罩負責「在哪」。
	var tex_res := 512
	var img := Image.create(tex_res, tex_res, false, Image.FORMAT_RGB8)
	for j in tex_res:
		for i in tex_res:
			var x := -HALF + (float(i) + 0.5) / float(tex_res) * 2.0 * HALF
			var z := -HALF + (float(j) + 0.5) / float(tex_res) * 2.0 * HALF
			var g2 := clampf(n2.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
			var west := clampf(1.0 - (x + HALF) / (2.0 * HALF) * 1.6, 0.0, 1.0)
			var forest_w := clampf(west * 0.7 + g2 * west * 0.3, 0.0, 1.0)
			var macro := clampf(n1.get_noise_2d(x * 0.4, z * 0.4) * 0.5 + 0.5, 0.0, 1.0)
			img.set_pixel(i, j, Color(_path_info(x, z)[1], forest_w, macro))
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + "gen/ground_mask.png"))

	# 遮罩存成獨立資源（PortableCompressedTexture2D 要先開 keep_compressed_buffer，
	# 否則存出去是空殼），材質走 ext_resource 鏈掛 material_override
	var tex := PortableCompressedTexture2D.new()
	tex.keep_compressed_buffer = true
	tex.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
	ResourceSaver.save(tex, OUT_DIR + "gen/ground_tex.res")
	tex.take_over_path(OUT_DIR + "gen/ground_tex.res")
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/terrain_pbr.gdshader")
	mat.set_shader_parameter("grass_diff", load("res://assets/textures/terrain_grass_diff.jpg"))
	mat.set_shader_parameter("grass_nor", load("res://assets/textures/terrain_grass_nor_gl.jpg"))
	mat.set_shader_parameter("forest_diff", load("res://assets/textures/terrain_forest_diff.jpg"))
	mat.set_shader_parameter("forest_nor", load("res://assets/textures/terrain_forest_nor_gl.jpg"))
	mat.set_shader_parameter("path_diff", load("res://assets/textures/terrain_path_diff.jpg"))
	mat.set_shader_parameter("path_nor", load("res://assets/textures/terrain_path_nor_gl.jpg"))
	mat.set_shader_parameter("mask_tex", tex)
	ResourceSaver.save(mat, MAT_DIR + "terrain_kourindou.tres")
	mat.take_over_path(MAT_DIR + "terrain_kourindou.tres")

	# mesh 不另存 .res：讓 pack() 內嵌進 .tscn（外部 ArrayMesh .res 在
	# headless 產生器下有資料遺失的坑，內嵌最穩）
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	_add(_root, mi, "Terrain")

# ── 遠景地形：把「地圖斷邊」藏進綿延的丘陵 ──
# 玩法範圍還是 ±70，但視野裡的世界一路鋪到 ±430：外圈起伏隨距離放大、
# 最外緣抬成遠山稜線，配合霧把邊界完全收掉。純視覺，沒有碰撞。
func _build_vista() -> void:
	var nv := FastNoiseLite.new()
	nv.frequency = 0.008
	nv.fractal_octaves = 3
	nv.seed = 99
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ext := 430.0
	var res := 101
	var step := 2.0 * ext / float(res - 1)
	var idx := {}
	var verts: Array[Vector3] = []
	for j in res:
		for i in res:
			var x := -ext + i * step
			var z := -ext + j * step
			var d := maxf(absf(x), absf(z)) - HALF
			var t := clampf(d / 320.0, 0.0, 1.0)
			var y: float
			if d <= 0.0:
				y = height_at(x, z) - 0.15          # 內圈墊在正圖下面一點，蓋接縫
			else:
				var hills := nv.get_noise_2d(x, z) * lerpf(3.0, 34.0, t)
				y = height_at(clampf(x, -HALF, HALF), clampf(z, -HALF, HALF)) \
					+ hills * (0.25 + 0.75 * t) + t * t * 46.0
			idx[Vector2i(i, j)] = verts.size()
			verts.append(Vector3(x, y, z))
			st.set_uv(Vector2(x, z))
			st.add_vertex(verts[verts.size() - 1])
	var inner_lo := int((-HALF + ext) / step) + 1
	var inner_hi := int((HALF + ext) / step) - 1
	for j in res - 1:
		for i in res - 1:
			# 完全落在玩法範圍內的格子跳過（正圖地形在那裡）
			if i >= inner_lo and i + 1 <= inner_hi and j >= inner_lo and j + 1 <= inner_hi:
				continue
			var a := j * res + i
			st.add_index(a); st.add_index(a + 1); st.add_index(a + res)
			st.add_index(a + 1); st.add_index(a + res + 1); st.add_index(a + res)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/terrain_grass_diff.jpg")
	mat.albedo_color = Color(0.66, 0.78, 0.58)   # 遠景壓綠壓暗，跟正圖草地銜接
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.1, 0.1, 0.1)
	mat.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	_add(_root, mi, "Vista")

	# 遠方林帶：玩法圈外撒大棵的樹，剪影 + 霧 = 「森林一直延伸出去」
	var far_trees: Array[Transform3D] = []
	var tries := 0
	while far_trees.size() < 300 and tries < 9000:
		tries += 1
		var x := _rr(-260.0, 260.0)
		var z := _rr(-260.0, 260.0)
		var d := maxf(absf(x), absf(z)) - HALF
		if d < 4.0 or d > 190.0:
			continue
		if _rand() > clampf(1.0 - d / 220.0, 0.25, 0.95):
			continue
		var nvh := nv.get_noise_2d(x, z) * lerpf(3.0, 34.0, clampf(d / 320.0, 0.0, 1.0))
		var y := height_at(clampf(x, -HALF, HALF), clampf(z, -HALF, HALF)) \
			+ nvh * (0.25 + 0.75 * clampf(d / 320.0, 0.0, 1.0)) \
			+ clampf(d / 320.0, 0.0, 1.0) * clampf(d / 320.0, 0.0, 1.0) * 46.0
		var s := _rr(1.4, 2.4)
		var basis := Basis(Vector3.UP, _rand() * TAU).scaled(Vector3(s, s * _rr(0.9, 1.15), s))
		far_trees.append(Transform3D(basis, Vector3(x, y - 0.4, z)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _make_multimesh(_tree_mesh("res://assets/models/tree_round_b.glb"),
		far_trees, [], OUT_DIR + "gen/vista_trees.res")
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(_root, mmi, "VistaTrees")
	print("vista trees: ", far_trees.size())

# ── 空氣牆：四面透明的碰撞牆，把玩家留在 ±68 ──
func _build_boundary() -> void:
	var body := StaticBody3D.new()
	body.name = "Boundary"
	_add(_root, body, "Boundary")
	var walls := [
		[Vector3(0, 15, -68.5), Vector3(140, 30, 1)],
		[Vector3(0, 15, 68.5), Vector3(140, 30, 1)],
		[Vector3(-68.5, 15, 0), Vector3(1, 30, 140)],
		[Vector3(68.5, 15, 0), Vector3(1, 30, 140)],
	]
	for w in walls:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = w[1]
		shape.shape = box
		shape.position = w[0]
		body.add_child(shape)
		shape.owner = _root

# ── 店（和洋混合，佈局照抄 web 版） ──
func _build_shop() -> void:
	# 寫實定調（風格筆記：寫實環境 × 卡通角色）—— 建物全上照片級 PBR
	var wood := _pbr("wood", "planks", 0.5, Color(0.9, 0.82, 0.72))
	var dark := _pbr("dark_wood", "dark_wood", 0.45)
	var plank := _pbr("plank", "planks", 0.28)
	var stone := _pbr("stone", "stone_wall", 0.30)
	var slate := _pbr("slate", "roof_kawara", 0.22, Color(0.85, 0.88, 0.95))
	var brick := _pbr("brick", "brick_red", 0.35)
	var glass := _mat("glass", Color(0.75, 0.82, 0.78), 0.2, 0.0, Color(0.35, 0.3, 0.18))
	var cloth := _mat("cloth", Color(0.32, 0.34, 0.45), 0.95)

	var shop := Node3D.new()
	shop.position = Vector3(SHOP.x, height_at(SHOP.x, SHOP.z), SHOP.z)
	_add(_root, shop, "Shop")

	var w: float = SHOP.w
	var d: float = SHOP.d
	var h: float = SHOP.h
	var hw := w / 2.0
	var hd := d / 2.0
	var fz := hd + 0.02

	_box(shop, "石基", Vector3(w + 1.4, 0.5, d + 1.4), stone, Vector3(0, 0.25, 0))
	_box(shop, "屋身", Vector3(w, h, d), plank, Vector3(0, 0.5 + h / 2.0, 0))

	# 正面格子窗 ×2
	for s in [-1, 1]:
		var wx := float(s) * 5.2
		var win := Node3D.new()
		_add(shop, win, "格子窗_東" if s > 0 else "格子窗_西")
		win.position = Vector3(wx, 0, fz)
		_box(win, "玻璃", Vector3(3.6, 1.9, 0.12), glass, Vector3(0, 2.35, 0))
		_box(win, "上框", Vector3(3.9, 0.16, 0.2), dark, Vector3(0, 3.36, 0))
		_box(win, "下框", Vector3(3.9, 0.16, 0.2), dark, Vector3(0, 1.34, 0))
		for k in [-1, 0, 1]:
			_box(win, "格_%d" % (k + 1), Vector3(0.13, 1.9, 0.2), dark, Vector3(k * 1.15, 2.35, 0))

	_box(shop, "引戶", Vector3(2.6, 2.4, 0.16), dark, Vector3(0, 1.7, fz))
	_box(shop, "戶合わせ目", Vector3(0.16, 2.4, 0.22), wood, Vector3(0, 1.7, fz + 0.04))

	# 暖簾三片 + 竿
	var noren := Node3D.new()
	_add(shop, noren, "暖簾")
	for k in [-1, 0, 1]:
		_box(noren, "布_%d" % (k + 1), Vector3(0.84, 1.0, 0.05), cloth, Vector3(k * 0.9, 3.35, fz + 0.16))
	_box(noren, "竿", Vector3(3.0, 0.14, 0.24), dark, Vector3(0, 3.9, fz + 0.16))

	# 看板
	var sign := _box(shop, "看板", Vector3(3.4, 0.9, 0.14), wood, Vector3(5.4, 4.3, fz + 0.1))
	sign.rotation.z = -0.03
	_box(shop, "看板上緣", Vector3(3.6, 0.12, 0.2), dark, Vector3(5.4, 4.82, fz + 0.1))

	# 陡切妻屋頂：兩片斜坡 + 屋脊 + 山牆
	var rw := w + 2.2
	var rd := d + 2.6
	for s in [-1, 1]:
		var slope := _box(shop, "屋頂南坡" if s > 0 else "屋頂北坡",
			Vector3(rw, 0.3, rd * 0.66), slate, Vector3(0, 0.5 + h + 1.9, s * rd * 0.22))
		slope.rotation.x = s * 0.84
	_box(shop, "屋脊", Vector3(rw + 0.5, 0.34, 0.9), slate, Vector3(0, 0.5 + h + 3.35, 0))
	for s in [-1, 1]:
		var gable := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(rd * 0.86, 2.9, 0.32)
		pm.material = plank
		gable.mesh = pm
		gable.position = Vector3(s * (rw / 2.0 - 0.16), 0.5 + h + 1.42, 0)
		gable.rotation.y = PI / 2.0
		_add(shop, gable, "破風_東" if s > 0 else "破風_西")

	# 磚煙囪
	_box(shop, "煙囪", Vector3(1.1, 4.2, 1.1), brick, Vector3(-6.0, 0.5 + h + 2.4, -1.6))
	_box(shop, "煙囪冠", Vector3(1.5, 0.28, 1.5), stone, Vector3(-6.0, 0.5 + h + 4.6, -1.6))

	# 屋根窗（dormer）
	var dormer := Node3D.new()
	_add(shop, dormer, "屋根窗")
	dormer.position = Vector3(3.4, 0.5 + h + 2.0, 2.4)
	_box(dormer, "窗體", Vector3(2.2, 1.5, 1.6), plank, Vector3.ZERO)
	_box(dormer, "玻璃", Vector3(1.5, 0.95, 0.1), glass, Vector3(0, 0.1, 0.82))
	var dr := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.0
	dm.bottom_radius = 1.9
	dm.height = 1.1
	dm.radial_segments = 4
	dm.material = slate
	dr.mesh = dm
	dr.position = Vector3(0, 1.2, 0)
	dr.rotation.y = PI / 4.0
	_add(dormer, dr, "小屋頂")

	# 正面下屋（庇）與細柱、踏石
	_box(shop, "庇", Vector3(w + 1.2, 0.16, 2.4), wood, Vector3(0, 3.05, fz + 1.1))
	for s in [-1, 1]:
		_cyl(shop, "庇柱_東" if s > 0 else "庇柱_西", 0.09, 0.1, 3.0, dark,
			Vector3(s * (hw - 0.5), 1.5, fz + 2.1), 6)
	_box(shop, "踏石", Vector3(2.8, 0.26, 1.1), stone, Vector3(0, 0.13, fz + 2.9))

# ── 街燈（主徑旁，暖光） ──
func _build_lamps() -> void:
	var iron := _mat("iron", Color(0.16, 0.16, 0.18), 0.6)
	var lamp_glow := _mat("lamp_glow", Color(1.0, 0.85, 0.55), 0.3, 0.0, Color(1.0, 0.75, 0.4))
	var lamps := Node3D.new()
	_add(_root, lamps, "Lamps")
	var spots := [[40.0, 14.5], [18.0, 4.5], [-8.0, 9.5], [-38.0, 7.0], [8.5, -2.5]]
	var idx := 0
	for s in spots:
		idx += 1
		var y := height_at(s[0], s[1])
		var lamp := Node3D.new()
		lamp.position = Vector3(s[0], y, s[1])
		_add(lamps, lamp, "街燈_%d" % idx)
		_cyl(lamp, "柱", 0.055, 0.075, 3.4, iron, Vector3(0, 1.7, 0), 8)
		_box(lamp, "燈頭", Vector3(0.42, 0.5, 0.42), lamp_glow, Vector3(0, 3.55, 0))
		_box(lamp, "燈帽", Vector3(0.56, 0.1, 0.56), iron, Vector3(0, 3.85, 0))
		var li := OmniLight3D.new()
		li.position = Vector3(0, 3.5, 0)
		li.light_color = Color(1.0, 0.78, 0.5)
		li.light_energy = 1.4
		li.omni_range = 9.0
		li.shadow_enabled = false
		_add(lamp, li, "光")

# ── 雜物堆（junkPile 移植，同一顆 seed） ──
func _build_junk() -> void:
	var wood: StandardMaterial3D = _mats["wood"]
	var dark: StandardMaterial3D = _mats["dark_wood"]
	var iron: StandardMaterial3D = _mats["iron"]
	var cloth: StandardMaterial3D = _mats["cloth"]
	var rust := _mat("rust", Color(0.45, 0.28, 0.18), 0.85, 1.0)
	var moss := _mat("moss_stone", Color(0.4, 0.45, 0.36), 0.95, 1.0)
	var junk_root := Node3D.new()
	_add(_root, junk_root, "Junk")
	var piles := [[-8.6, 1.2, 6], [12.0, 0.4, 5], [-11.5, -6.0, 5], [14.5, -4.5, 5], [-12.5, 3.6, 4]]
	var pi := 0
	for pile in piles:
		pi += 1
		var pg := Node3D.new()
		_add(junk_root, pg, "雜物堆_%d" % pi)
		for i in int(pile[2]):
			var x: float = pile[0] + _rr(-1.6, 1.6)
			var z: float = pile[1] + _rr(-1.6, 1.6)
			var kind := int(_rand() * 5.0)
			var yy := height_at(x, z)
			var nm := "%d_%d" % [pi, i]
			if kind == 0:
				var s := _rr(0.5, 0.95)
				var b := _box(pg, "木箱_" + nm, Vector3(s, s * 0.8, s), wood, Vector3(x, yy + s * 0.4, z))
				b.rotation.y = _rand() * 3.14
			elif kind == 1:
				var hh := _rr(0.7, 1.05)
				_cyl(pg, "鐵桶_" + nm, 0.32, 0.32, hh, rust, Vector3(x, yy + hh / 2.0, z))
			elif kind == 2:
				var r := _rr(0.34, 0.52)
				var t := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = r - 0.055
				tm.outer_radius = r + 0.055
				tm.material = iron
				t.mesh = tm
				t.position = Vector3(x, yy + r, z)
				t.rotation = Vector3(PI / 2.0 + _rr(-0.3, 0.3), _rand() * 3.14, 0)
				_add(pg, t, "車輪_" + nm)
			elif kind == 3:
				var c := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.0
				cm.bottom_radius = _rr(0.42, 0.6)
				cm.height = 0.42
				cm.radial_segments = 8
				cm.material = cloth
				c.mesh = cm
				c.position = Vector3(x, yy + 0.42, z)
				c.rotation = Vector3(_rr(0.4, 1.1), _rand() * 3.14, 0)
				_add(pg, c, "洋傘_" + nm)
				_cyl(pg, "傘柄_" + nm, 0.03, 0.03, 0.9, dark, Vector3(x, yy + 0.3, z), 5)
			else:
				var r2 := _rr(0.26, 0.4)
				var p := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = r2
				sm.height = r2 * 2.5
				sm.material = moss
				p.mesh = sm
				p.position = Vector3(x, yy + r2, z)
				_add(pg, p, "甕_" + nm)

# ── 林緣（Blender 產的多層次樹，見 assets/blender/make_trees.py） ──
## 樹的兩個 surface：0=樹幹（bark 材質槽）、1=樹冠（foliage 材質槽）。
## 樹幹上真樹皮 PBR；樹冠 = 頂點色層次 × 葉紋理（triplanar），
## 讓平面色塊多一層有機的細節 —— 「寫實環境」定調下的樹。
func _canopy_mat() -> StandardMaterial3D:
	if _mats.has("canopy"):
		return _mats["canopy"]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.7, 1.6, 1.45)   # 葉紋理偏暗，把亮度乘回來
	m.albedo_texture = load("res://assets/textures/terrain_forest_diff.jpg")
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.8, 0.8, 0.8)
	m.roughness = 1.0
	ResourceSaver.save(m, MAT_DIR + "canopy.tres")
	m.take_over_path(MAT_DIR + "canopy.tres")
	_mats["canopy"] = m
	return m

func _tree_mesh(glb_path: String) -> Mesh:
	var packed: PackedScene = load(glb_path)
	var node := packed.instantiate()
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
	var bark := _pbr("bark", "bark_cedar", 0.7)
	var canopy := _canopy_mat()
	if mesh.get_surface_count() >= 2:
		mesh.surface_set_material(0, bark)
		for s in range(1, mesh.get_surface_count()):
			mesh.surface_set_material(s, canopy)
	else:
		mesh.surface_set_material(0, canopy)
	return mesh

func _build_forest() -> void:
	var variants := [
		{ "mesh": _tree_mesh("res://assets/models/tree_round_a.glb"), "list": [], "file": "trees_round_a" },
		{ "mesh": _tree_mesh("res://assets/models/tree_round_b.glb"), "list": [], "file": "trees_round_b" },
		{ "mesh": _tree_mesh("res://assets/models/tree_round_c.glb"), "list": [], "file": "trees_round_c" },
		{ "mesh": _tree_mesh("res://assets/models/tree_pine_a.glb"), "list": [], "file": "trees_pine_a" },
		{ "mesh": _tree_mesh("res://assets/models/tree_pine_b.glb"), "list": [], "file": "trees_pine_b" },
	]

	var count := 0
	var tries := 0
	while count < 560 and tries < 16000:
		tries += 1
		var x := _rr(-HALF + 2.0, HALF - 2.0)
		var z := _rr(-HALF + 2.0, HALF - 2.0)
		# 密度：西半邊（魔法之森）密，東邊只有零星；路面/店庭/後院不長
		var density := clampf(0.9 - (x + HALF) / (2.0 * HALF) * 1.1, 0.06, 0.9)
		var border := maxf(absf(x), absf(z)) / HALF          # 邊界一圈一定有樹牆
		density = maxf(density, smoothstep(0.72, 0.95, border) * 0.95)
		if _rand() > density:
			continue
		if _path_info(x, z)[0] < 3.0:
			continue
		if x > YARD.x0 - 3.0 and x < YARD.x1 + 3.0 and z > YARD.z0 - 3.0 and z < 10.0:
			continue
		var y := height_at(x, z)
		var s := _rr(0.7, 1.3)
		var basis := Basis(Vector3.UP, _rand() * TAU).scaled(Vector3(s, s * _rr(0.9, 1.2), s))
		# 杉樹愈往西（魔法之森深處）愈多，東邊幾乎全是闊葉；
		# 每型內再抽變體（a/b/c、pine a/b），打破複製感
		var pine_p := clampf(0.55 - (x + HALF) / (2.0 * HALF) * 0.9, 0.04, 0.55)
		var vi: int
		if _rand() < pine_p:
			vi = 3 if _rand() < 0.65 else 4
		else:
			var r := _rand()
			vi = 0 if r < 0.45 else (1 if r < 0.8 else 2)
		variants[vi].list.append(Transform3D(basis, Vector3(x, y, z)))
		count += 1

	var forest := Node3D.new()
	_add(_root, forest, "Forest")
	for v in variants:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = _make_multimesh(v.mesh, v.list, [], OUT_DIR + "gen/" + String(v.file) + ".res")
		_add(forest, mmi, String(v.file).capitalize().replace(" ", ""))
	print("forest: ", count, " trees")
	_build_grass()

## MultiMesh 存檔的坑：set_instance_transform 寫進去的資料，ResourceSaver
## 存完再載回來會全變 identity（buffer 沒跟著序列化）。直接組 buffer
## （每 instance：3×4 的 transform 列 + 可選 RGBA）就一定會存到。
func _make_multimesh(mesh: Mesh, list: Array, cols: Array, path: String) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = cols.size() > 0
	mm.mesh = mesh
	mm.instance_count = list.size()
	var stride := 16 if cols.size() > 0 else 12
	var buf := PackedFloat32Array()
	buf.resize(list.size() * stride)
	for i in list.size():
		var t: Transform3D = list[i]
		var o := i * stride
		buf[o + 0] = t.basis.x.x; buf[o + 1] = t.basis.y.x; buf[o + 2] = t.basis.z.x; buf[o + 3] = t.origin.x
		buf[o + 4] = t.basis.x.y; buf[o + 5] = t.basis.y.y; buf[o + 6] = t.basis.z.y; buf[o + 7] = t.origin.y
		buf[o + 8] = t.basis.x.z; buf[o + 9] = t.basis.y.z; buf[o + 10] = t.basis.z.z; buf[o + 11] = t.origin.z
		if cols.size() > 0:
			var c: Color = cols[i]
			buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = c.a
	mm.buffer = buf
	ResourceSaver.save(mm, path)
	mm.take_over_path(path)
	return mm

# ── 草叢：三種草 + 風吹 shader（grass_wind.gdshader） ──
# 高叢（路緣與空地）、矮叢（大面積打底）、野花（零星點綴）。
# 顏色烤頂點色（根暗尖亮），搖擺在 shader 做：相位吃世界座標 + 低頻陣風。
func _grass_wind_mat(strength: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/grass_wind.gdshader")
	m.set_shader_parameter("sway_strength", strength)
	return m

## blades 片葉組成一簇；flower=true 時葉尖加一小簇花瓣色
func _tuft_mesh(blades: int, base_h: float, spread: float, root_c: Color, tip_c: Color, flower := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in blades:
		var ang := float(b) / float(blades) * TAU + 0.4
		var off := Vector2(cos(ang), sin(ang)) * spread * 0.5
		var lean := Vector2(cos(ang), sin(ang)) * spread
		var hh := base_h + base_h * 0.45 * sin(float(b) * 2.1)
		var tip := tip_c.lerp(root_c, 0.15 * absf(sin(float(b) * 3.7)))
		st.set_color(root_c)
		st.add_vertex(Vector3(off.x - 0.045, 0, off.y))
		st.set_color(root_c)
		st.add_vertex(Vector3(off.x + 0.045, 0, off.y))
		st.set_color(tip)
		st.add_vertex(Vector3(off.x + lean.x, hh, off.y + lean.y))
	if flower:
		for f in 3:
			var ang2 := float(f) / 3.0 * TAU + 1.1
			var fx := cos(ang2) * 0.05
			var fz := sin(ang2) * 0.05
			var fy := base_h * 1.15
			st.set_color(Color(0.95, 0.9, 0.75))
			st.add_vertex(Vector3(fx - 0.05, fy, fz))
			st.set_color(Color(0.98, 0.95, 0.85))
			st.add_vertex(Vector3(fx + 0.05, fy, fz))
			st.set_color(Color(0.9, 0.78, 0.4))
			st.add_vertex(Vector3(fx, fy + 0.09, fz))
	st.generate_normals()
	return st.commit()

func _scatter_grass(target: int, min_edge: float, max_p: float, far_p: float) -> Array[Transform3D]:
	var list: Array[Transform3D] = []
	var tries := 0
	while list.size() < target and tries < target * 30:
		tries += 1
		var x := _rr(-HALF + 4.0, HALF - 4.0)
		var z := _rr(-HALF + 4.0, HALF - 4.0)
		if x < -34.0:                       # 深林裡不長草，長也看不到
			continue
		var ed: float = _path_info(x, z)[0]
		if ed < min_edge:
			continue
		if _rand() > (max_p if ed < 4.0 else far_p):
			continue
		var s := _rr(0.7, 1.6)
		var basis := Basis(Vector3.UP, _rand() * TAU).scaled(Vector3(s, s, s))
		list.append(Transform3D(basis, Vector3(x, height_at(x, z), z)))
	return list

func _build_grass() -> void:
	var tall := _tuft_mesh(7, 0.40, 0.20, Color(0.13, 0.22, 0.08), Color(0.38, 0.50, 0.20))
	tall.surface_set_material(0, _grass_wind_mat(0.10))
	var short := _tuft_mesh(5, 0.22, 0.28, Color(0.15, 0.24, 0.10), Color(0.33, 0.44, 0.18))
	short.surface_set_material(0, _grass_wind_mat(0.06))
	var flower := _tuft_mesh(5, 0.34, 0.16, Color(0.14, 0.23, 0.09), Color(0.36, 0.48, 0.20), true)
	flower.surface_set_material(0, _grass_wind_mat(0.08))

	var groups := [
		{ "mesh": tall, "n": 1500, "min_edge": 0.5, "near": 0.85, "far": 0.25, "file": "grass_tall" },
		{ "mesh": short, "n": 1400, "min_edge": 0.35, "near": 0.6, "far": 0.45, "file": "grass_short" },
		{ "mesh": flower, "n": 240, "min_edge": 1.0, "near": 0.25, "far": 0.1, "file": "grass_flower" },
	]
	var total := 0
	for g in groups:
		var list := _scatter_grass(g.n, g.min_edge, g.near, g.far)
		total += list.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = _make_multimesh(g.mesh, list, [], OUT_DIR + "gen/" + String(g.file) + ".res")
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add(_root, mmi, String(g.file).capitalize().replace(" ", ""))
	print("grass: ", total)

# ── 氛圍（這張圖自己的 WorldEnvironment，蓋掉 main 的預設） ──
func _build_env() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.34, 0.52, 0.8)
	sky_mat.sky_horizon_color = Color(0.82, 0.8, 0.72)
	sky_mat.ground_horizon_color = Color(0.72, 0.7, 0.62)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	# 效能放開（使用者指示不受本機規格侷限）：Forward+ 下生效，
	# 相容模式自動忽略 —— SDFGI 全域光照 + SSAO 接觸陰影 + 體積霧
	env.sdfgi_enabled = true
	env.ssao_enabled = true
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.015
	env.volumetric_fog_albedo = Color(0.82, 0.84, 0.8)
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.78, 0.7)
	env.fog_density = 0.0016       # 林緣的薄霧：有縱深但不洗掉中景的顏色
	env.fog_sky_affect = 0.25
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	_add(_root, we, "WorldEnvironment")
