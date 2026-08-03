# 產生器共用程式庫 —— 各地圖的 gen_<map>.gd 用 preload 載入。
# 抽自香霖堂產生器（gen_kourindou.gd 尚未回頭改用，之後清理）。
#
# 踩過的坑都封在這裡：Godot 順時針繞向、MultiMesh 要手組 buffer、
# PortableCompressedTexture2D 要 keep_compressed_buffer、
# 貼圖／材質走 ext_resource 鏈。
extends RefCounted

const MAT_DIR := "res://assets/materials/"

var root: Node3D
var mats := {}
var _seed_state := 1

func setup(p_root: Node3D, p_seed: int) -> void:
	root = p_root
	_seed_state = p_seed

# ── 決定性亂數 ──
func rand() -> float:
	_seed_state = int((_seed_state * 1664525 + 1013904223) & 0xFFFFFFFF)
	return float(_seed_state) / 4294967296.0

func rr(a: float, b: float) -> float:
	return a + rand() * (b - a)

# ── 節點 ──
func add(parent: Node, node: Node, name: String) -> Node:
	node.name = name
	parent.add_child(node)
	node.owner = root
	return node

func box(parent: Node, name: String, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	mi.mesh = m
	mi.position = pos
	add(parent, mi, name)
	return mi

func cyl(parent: Node, name: String, r_top: float, r_bot: float, h: float, mat: Material, pos: Vector3, seg := 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = seg
	m.material = mat
	mi.mesh = m
	mi.position = pos
	add(parent, mi, name)
	return mi

# ── 材質 ──
func pbr(name: String, set_name: String, uv := 0.35, tint := Color(1, 1, 1), tri := true) -> StandardMaterial3D:
	if mats.has(name):
		return mats[name]
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
	_save_mat(m, name)
	return m

func flat_mat(name: String, color: Color, rough := 0.9, emission := Color(0, 0, 0)) -> StandardMaterial3D:
	if mats.has(name):
		return mats[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if emission.get_luminance() > 0.01:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = 1.6
	_save_mat(m, name)
	return m

func _save_mat(m: Material, name: String) -> void:
	var path := MAT_DIR + name + ".tres"
	ResourceSaver.save(m, path)
	m.take_over_path(path)
	mats[name] = m

# ── MultiMesh（buffer 手組，否則存檔資料會掉） ──
func make_multimesh(mesh: Mesh, list: Array, cols: Array, path: String) -> MultiMesh:
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

# ── 樹（Blender glb：surface 0=樹幹 bark、1+=樹冠 foliage） ──
func canopy_mat() -> StandardMaterial3D:
	if mats.has("canopy"):
		return mats["canopy"]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.7, 1.6, 1.45)
	m.albedo_texture = load("res://assets/textures/terrain_forest_diff.jpg")
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.8, 0.8, 0.8)
	m.roughness = 1.0
	_save_mat(m, "canopy")
	return m

func tree_mesh(glb_path: String) -> Mesh:
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
	var bark_m := pbr("bark", "bark_cedar", 0.7)
	var canopy_m := canopy_mat()
	if mesh.get_surface_count() >= 2:
		mesh.surface_set_material(0, bark_m)
		for s in range(1, mesh.get_surface_count()):
			mesh.surface_set_material(s, canopy_m)
	else:
		mesh.surface_set_material(0, canopy_m)
	return mesh

const TREE_GLBS := [
	"res://assets/models/tree_round_a.glb",
	"res://assets/models/tree_round_b.glb",
	"res://assets/models/tree_round_c.glb",
	"res://assets/models/tree_pine_a.glb",
	"res://assets/models/tree_pine_b.glb",
]

# ── 草（風吹 shader + 三種簇型） ──
func grass_wind_mat(strength: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/grass_wind.gdshader")
	m.set_shader_parameter("sway_strength", strength)
	return m

func tuft_mesh(blades: int, base_h: float, spread: float, root_c: Color, tip_c: Color, flower := false) -> ArrayMesh:
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

# ── 地形網格（順時針繞向）＋遮罩貼圖材質 ──
## height_fn(x,z)->float；mask_fn(x,z)->Color(R=路徑,G=林床,B=macro)
func terrain(out_dir: String, half: float, res: int, height_fn: Callable, mask_fn: Callable) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 2.0 * half / float(res - 1)
	for j in res:
		for i in res:
			var x := -half + i * step
			var z := -half + j * step
			st.set_uv(Vector2(float(i) / float(res - 1), float(j) / float(res - 1)))
			st.add_vertex(Vector3(x, height_fn.call(x, z), z))
	for j in res - 1:
		for i in res - 1:
			var a := j * res + i
			st.add_index(a); st.add_index(a + 1); st.add_index(a + res)
			st.add_index(a + 1); st.add_index(a + res + 1); st.add_index(a + res)
	st.generate_normals()
	var mesh := st.commit()

	var tex_res := 512
	var img := Image.create(tex_res, tex_res, false, Image.FORMAT_RGB8)
	for j in tex_res:
		for i in tex_res:
			var x := -half + (float(i) + 0.5) / float(tex_res) * 2.0 * half
			var z := -half + (float(j) + 0.5) / float(tex_res) * 2.0 * half
			img.set_pixel(i, j, mask_fn.call(x, z))
	var tex := PortableCompressedTexture2D.new()
	tex.keep_compressed_buffer = true
	tex.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
	ResourceSaver.save(tex, out_dir + "gen/ground_tex.res")
	tex.take_over_path(out_dir + "gen/ground_tex.res")

	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/terrain_pbr.gdshader")
	mat.set_shader_parameter("grass_diff", load("res://assets/textures/terrain_grass_diff.jpg"))
	mat.set_shader_parameter("grass_nor", load("res://assets/textures/terrain_grass_nor_gl.jpg"))
	mat.set_shader_parameter("forest_diff", load("res://assets/textures/terrain_forest_diff.jpg"))
	mat.set_shader_parameter("forest_nor", load("res://assets/textures/terrain_forest_nor_gl.jpg"))
	mat.set_shader_parameter("path_diff", load("res://assets/textures/terrain_path_diff.jpg"))
	mat.set_shader_parameter("path_nor", load("res://assets/textures/terrain_path_nor_gl.jpg"))
	mat.set_shader_parameter("mask_tex", tex)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add(root, mi, "Terrain")
	return mi

# ── 遠景：丘陵 + 地標山 + 遠方林帶（斷邊藏進風景） ──
## landmarks: [{ "x":…, "z":…, "h":…, "r":… }] 在遠景高度上疊高斯山包
func vista(out_dir: String, half: float, ext: float, height_fn: Callable,
		landmarks: Array = [], tree_glb := "res://assets/models/tree_round_b.glb",
		far_tree_count := 300) -> void:
	var nv := FastNoiseLite.new()
	nv.frequency = 0.008
	nv.fractal_octaves = 3
	nv.seed = 99
	var vh := func(x: float, z: float) -> float:
		var d := maxf(absf(x), absf(z)) - half
		if d <= 0.0:
			return float(height_fn.call(x, z)) - 0.15
		var t := clampf(d / (ext - half - 20.0), 0.0, 1.0)
		var y := float(height_fn.call(clampf(x, -half, half), clampf(z, -half, half))) \
			+ nv.get_noise_2d(x, z) * lerpf(3.0, 34.0, t) * (0.25 + 0.75 * t) + t * t * 46.0
		for lm in landmarks:
			var dx := x - float(lm.x)
			var dz := z - float(lm.z)
			y += float(lm.h) * exp(-(dx * dx + dz * dz) / (float(lm.r) * float(lm.r)))
		return y

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var res := 101
	var step := 2.0 * ext / float(res - 1)
	for j in res:
		for i in res:
			var x := -ext + i * step
			var z := -ext + j * step
			st.set_uv(Vector2(x, z))
			st.add_vertex(Vector3(x, vh.call(x, z), z))
	var inner_lo := int((-half + ext) / step) + 1
	var inner_hi := int((half + ext) / step) - 1
	for j in res - 1:
		for i in res - 1:
			if i >= inner_lo and i + 1 <= inner_hi and j >= inner_lo and j + 1 <= inner_hi:
				continue
			var a := j * res + i
			st.add_index(a); st.add_index(a + 1); st.add_index(a + res)
			st.add_index(a + 1); st.add_index(a + res + 1); st.add_index(a + res)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/terrain_grass_diff.jpg")
	mat.albedo_color = Color(0.66, 0.78, 0.58)
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.1, 0.1, 0.1)
	mat.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add(root, mi, "Vista")

	var far_trees: Array[Transform3D] = []
	var tries := 0
	while far_trees.size() < far_tree_count and tries < far_tree_count * 30:
		tries += 1
		var x := rr(-(half + 200.0), half + 200.0)
		var z := rr(-(half + 200.0), half + 200.0)
		var d := maxf(absf(x), absf(z)) - half
		if d < 4.0 or d > 190.0:
			continue
		if rand() > clampf(1.0 - d / 220.0, 0.25, 0.95):
			continue
		var s := rr(1.4, 2.4)
		var basis := Basis(Vector3.UP, rand() * TAU).scaled(Vector3(s, s * rr(0.9, 1.15), s))
		far_trees.append(Transform3D(basis, Vector3(x, vh.call(x, z) - 0.4, z)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = make_multimesh(tree_mesh(tree_glb), far_trees, [], out_dir + "gen/vista_trees.res")
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add(root, mmi, "VistaTrees")

# ── 切妻屋頂（正確的幾何：脊高 = 半深 × tanθ） ──
## 之前寫死抬升量 0.85，導致兩片斜面互相穿插、屋脊蓋在斜面下、
## 山牆三角形開口 —— 牆會從屋簷「插出來」就是這個。
## base_y = 牆頂高度（本地座標）；w/d = 屋頂平面尺寸（含出簷）
func gable_roof(parent: Node, base_y: float, w: float, d: float, pitch: float,
		thick: float, mat: Material, gable_mat: Material = null, off := Vector3.ZERO) -> void:
	var hd := d * 0.5
	var rise := hd * tan(pitch)
	var slab := hd / cos(pitch)
	for sd in [-1, 1]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, thick, slab)
		bm.material = mat
		mi.mesh = bm
		mi.position = off + Vector3(0, base_y + rise * 0.5, float(sd) * hd * 0.5)
		mi.rotation.x = float(sd) * pitch
		add(parent, mi, "屋根坡_%d" % (sd + 1))
	var cap := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(w + thick * 1.2, thick * 1.3, thick * 3.2)
	cm.material = mat
	cap.mesh = cm
	cap.position = off + Vector3(0, base_y + rise, 0)
	add(parent, cap, "棟")
	# 山牆（妻壁）：把兩端的三角形封起來，否則從側面看得到屋頂內部
	var gm: Material = gable_mat if gable_mat else mat
	for sd2 in [-1, 1]:
		var tri := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(d, rise, thick * 1.1)
		pm.material = gm
		tri.mesh = pm
		tri.position = off + Vector3(float(sd2) * (w * 0.5 - thick * 0.6), base_y + rise * 0.5, 0)
		tri.rotation.y = PI * 0.5
		add(parent, tri, "妻壁_%d" % (sd2 + 1))

# ── 河川（全世界共用：村、湖、澤都吃這組） ──
## 折線最近距離（河道中心線）
func poly_dist(pts: Array, x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := INF
	for k in pts.size() - 1:
		best = minf(best, _seg_dist(p, Vector2(pts[k][0], pts[k][1]), Vector2(pts[k + 1][0], pts[k + 1][1])))
	return best

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

## 地形下切量（負值）：河床是 U 形斷面，岸邊平滑收斂 —— 加進 height_at
func river_carve(pts: Array, half_w: float, depth: float, x: float, z: float) -> float:
	var d := poly_dist(pts, x, z)
	if d > half_w * 2.2:
		return 0.0
	# 中央最深，往外 cos 收斂到 0（外緣 2.2 倍寬處完全沒影響）
	var t := clampf(d / (half_w * 2.2), 0.0, 1.0)
	return -depth * (0.5 + 0.5 * cos(t * PI))

## 水面：沿河道折線鋪一條帶狀 mesh（頂點色 R = 靠岸程度，shader 用來做泡沫）
## bank_y_fn(x,z) 給岸邊地面高度；水面 = 岸高 - sink
func river_water(out_dir: String, pts: Array, half_w: float, sink: float, bank_y_fn: Callable, name := "River") -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := []
	var steps := 8       # 每段細分
	for k in pts.size() - 1:
		var a := Vector2(pts[k][0], pts[k][1])
		var b := Vector2(pts[k + 1][0], pts[k + 1][1])
		var n := (b - a).normalized().orthogonal()
		var last := k == pts.size() - 2
		for s in range(steps + (1 if last else 0)):
			var t := float(s) / float(steps)
			var c := a.lerp(b, t)
			var y: float = float(bank_y_fn.call(c.x, c.y)) - sink
			rows.append([c - n * half_w, c, c + n * half_w, y])
	for r in rows.size() - 1:
		var r0 = rows[r]
		var r1 = rows[r + 1]
		# 左半 + 右半（中央一排頂點讓 bank 漸層有中間值）
		for half in 2:
			var i0: int = half
			var i1: int = half + 1
			var c0 := 1.0 if half == 0 else 0.0
			var c1 := 0.0 if half == 0 else 1.0
			st.set_color(Color(c0, 0, 0)); st.add_vertex(Vector3(r0[i0].x, r0[3], r0[i0].y))
			st.set_color(Color(c1, 0, 0)); st.add_vertex(Vector3(r0[i1].x, r0[3], r0[i1].y))
			st.set_color(Color(c0, 0, 0)); st.add_vertex(Vector3(r1[i0].x, r1[3], r1[i0].y))
			st.set_color(Color(c1, 0, 0)); st.add_vertex(Vector3(r0[i1].x, r0[3], r0[i1].y))
			st.set_color(Color(c1, 0, 0)); st.add_vertex(Vector3(r1[i1].x, r1[3], r1[i1].y))
			st.set_color(Color(c0, 0, 0)); st.add_vertex(Vector3(r1[i0].x, r1[3], r1[i0].y))
	st.generate_normals()
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/water.gdshader")
	mat.set_shader_parameter("wave_nor", load("res://assets/textures/terrain_sand_nor_gl.jpg")
		if ResourceLoader.exists("res://assets/textures/terrain_sand_nor_gl.jpg")
		else load("res://assets/textures/terrain_grass_nor_gl.jpg"))
	mat.render_priority = 1
	ResourceSaver.save(mat, MAT_DIR + "water.tres")
	mat.take_over_path(MAT_DIR + "water.tres")
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add(root, mi, name)

# ── 空氣牆 ──
func boundary(half: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Boundary"
	add(root, body, "Boundary")
	var walls := [
		[Vector3(0, 20, -half - 0.5), Vector3(half * 2.0, 40, 1)],
		[Vector3(0, 20, half + 0.5), Vector3(half * 2.0, 40, 1)],
		[Vector3(-half - 0.5, 20, 0), Vector3(1, 40, half * 2.0)],
		[Vector3(half + 0.5, 20, 0), Vector3(1, 40, half * 2.0)],
	]
	for w in walls:
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = w[1]
		shape.shape = b
		shape.position = w[0]
		body.add_child(shape)
		shape.owner = root
