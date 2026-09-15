extends SceneTree
## 博麗神社南出口：在鳥居南側開一道往山下的缺口 —— 二之鳥居 → 石階（20 階，2 段）
## → 下方平台（傳送點）。石燈籠三對。
##
##   Godot --headless --path godot --script tools/gen_shrine_exit.gd [-- --lantern=models|pack]
##
## 產出（都是外部資源，不直接改 shrine.tscn；掛接由 MCP 做）：
##   maps/shrine/gen/terrain_exit.res   地形網格（走廊下切 + 石階斜面 + 下方平台）
##   maps/shrine/gen/vista_exit.res     遠景網格（缺口延伸到圖外）
##   maps/shrine/gen/ground_tex.res     地表遮罩（走廊 R 通道 = 路徑）—— 原檔先備份
##   maps/shrine/gen/shrine_exit.tscn   鳥居／石階／燈籠／碰撞／新邊界
##   stdout JSON：走廊內要挪開的樹（MOVE_TREES）
##
## 座標：南 = +z。主鳥居 z=44（高 7.17）。既有南邊界牆 z=62。

const OUT := "res://maps/shrine/gen/"
const TORII := "res://assets/shrine/博麗鳥居.glb"
const LANTERN_MODELS := "res://assets/models/stone_lantern.glb"
const LANTERN_PACK := "res://assets/shrine/props/StoneLantern.gltf"
const KIT := {
	"踏石": ["res://assets/_lod/踏石.glb", Vector3(1.60, 0.16, 0.38)],
	"平台石": ["res://assets/_lod/平台石.glb", Vector3(1.60, 0.16, 1.80)],
	"袖石垣": ["res://assets/_lod/袖石垣.glb", Vector3(0.45, 0.55, 0.38)],
	"收頭石": ["res://assets/_lod/收頭石.glb", Vector3(1.60, 0.20, 0.55)],
}

# ── 主軸剖面 ──
const Z_TOP_FLAT0 := 52.0      # 上平台起點（原地形 ≈ −1.23）
const Z_TORII2 := 57.0         # 二之鳥居
const Z_STAIR_TOP := 60.0      # 最上階北緣
const Y_TOP := -1.25
const STEP_RISE := 0.16
const STEP_TREAD := 0.38
const STEP_W := 3.2
const LANDING_D := 1.8
const N_STEPS := 20            # 2 段 × 10
const Z_PAD_END := 76.0        # 下平台南端（新邊界）
const CUT_HALF := 4.4          # 走廊全切半寬（石階 3.2 + 袖石垣 0.9 + 兩側路肩）
const CUT_FEATHER := 19.0      # 邊坡寬（外緣舊地形最高 +6.8，坡度 ≤ 30°）
const TORII2_SCALE := 7.4      # 高 5.53 m、淨開口 3.55 m（主鳥居 9.6 → 7.17 m，這座要小一號）
const LANTERN_H := 2.3

var _plan: Array = []          # [{z0,z1,y0,y1,landing}] 由北往南
var _y_bottom := 0.0
var _z_bottom := 0.0
var _lantern_path := LANTERN_MODELS   # pack 版是粉藍低模，實拍不像石頭


func _init() -> void:
	_run.call_deferred()


func _plan_stairs() -> void:
	var z := Z_STAIR_TOP
	var y := Y_TOP
	for s in 2:
		for i in N_STEPS / 2:
			_plan.append({"z0": z, "z1": z + STEP_TREAD, "y0": y, "y1": y - STEP_RISE, "landing": false})
			z += STEP_TREAD
			y -= STEP_RISE
		if s == 0:
			_plan.append({"z0": z, "z1": z + LANDING_D, "y0": y, "y1": y, "landing": true})
			z += LANDING_D
	_z_bottom = z
	_y_bottom = y
	print("STAIRS n=%d top_z=%.2f bottom_z=%.2f drop=%.2f y_bottom=%.2f" % [N_STEPS, Z_STAIR_TOP, _z_bottom, Y_TOP - _y_bottom, _y_bottom])


## 走廊中心線目標高（含平台）；不在走廊 z 範圍回 NAN
func _axis_y(z: float) -> float:
	if z < Z_TOP_FLAT0:
		return NAN
	if z <= Z_STAIR_TOP:
		return Y_TOP
	for e in _plan:
		if z >= e.z0 and z <= e.z1:
			if e.landing:
				return e.y0
			var t: float = (z - e.z0) / (e.z1 - e.z0)
			return lerpf(e.y0, e.y1, t)
	return _y_bottom


func _corridor_w(x: float, z: float) -> float:
	var w := 1.0 - smoothstep(CUT_HALF, CUT_HALF + CUT_FEATHER, absf(x))
	# 北端淡入（原地形本來就 ≈ Y_TOP，只是保險）
	w *= smoothstep(Z_TOP_FLAT0 - 4.0, Z_TOP_FLAT0, z)
	return w


func _new_h(x: float, z: float, old: float) -> float:
	var ay := _axis_y(z)
	if is_nan(ay):
		return old
	var w := _corridor_w(x, z)
	if w <= 0.0:
		return old
	# 走廊內：只往下切，不抬（南端原地形 −1.2，下平台 −4.45）
	var target := minf(ay - 0.05, old) if absf(x) < CUT_HALF else ay - 0.05
	return lerpf(old, target, w)


func _run() -> void:
	_plan_stairs()
	var scn: Node3D = load("res://maps/shrine/shrine.tscn").instantiate()
	root.add_child(scn)
	await process_frame
	if "--lantern=pack" in OS.get_cmdline_user_args():
		_lantern_path = LANTERN_PACK

	# ── 1. 地形 ──
	var terrain: MeshInstance3D = scn.get_node("Terrain")
	var tm := _rebuild(terrain, terrain.global_transform, 0.0)
	var err := ResourceSaver.save(tm, OUT + "terrain_exit.res")
	print("TERRAIN saved err=%d" % err)
	# ── 2. 遠景：缺口延伸出圖外，往南繼續下降 ──
	var vista: MeshInstance3D = scn.get_node("Vista")
	var vm := _rebuild(vista, vista.global_transform, 1.0)
	err = ResourceSaver.save(vm, OUT + "vista_exit.res")
	print("VISTA saved err=%d" % err)
	# ── 3. 遮罩：走廊塗成路徑 ──
	_paint_mask()
	# ── 4. 出口套件 ──
	var kit := Node3D.new()
	kit.name = "南出口"
	_build_torii(kit)
	_build_stairs(kit)
	_build_lanterns(kit)
	_build_boundary(kit)
	var ps := PackedScene.new()
	ps.pack(kit)
	err = ResourceSaver.save(ps, OUT + "shrine_exit.tscn")
	print("KIT saved err=%d nodes=%d" % [err, _count(kit)])
	# ── 5. 走廊裡的樹 → 列出要挪的 ──
	_list_trees(scn, tm)
	print("PORTAL z=%.2f y=%.2f" % [_z_bottom + 3.0, _y_bottom])
	quit(0)


func _rebuild(mi: MeshInstance3D, xf: Transform3D, vista_mode: float) -> ArrayMesh:
	var a: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var changed := 0
	var inv := xf.affine_inverse()
	for i in verts.size():
		var w: Vector3 = xf * verts[i]
		var nh: float
		if vista_mode > 0.0:
			if w.z < 48.0 or absf(w.x) > 40.0:
				continue
			# 遠景網格 18 m 一格，圖內原本貼舊地形 → 走廊段會冒出來蓋住新石階；
			# 圖內壓到走廊剖面之下 0.3 m，圖外從下平台高度沿 z 緩降（每 12.5 m 降 1 m）
			var ay: float
			if w.z <= Z_PAD_END:
				var az := _axis_y(w.z)
				ay = (az if not is_nan(az) else Y_TOP) - 0.3
			else:
				ay = _y_bottom - 0.3 - (w.z - Z_PAD_END) * 0.08
			var ww := 1.0 - smoothstep(CUT_HALF + 1.0, CUT_HALF + CUT_FEATHER + 6.0, absf(w.x))
			ww *= 1.0 - smoothstep(140.0, 220.0, w.z)
			nh = lerpf(w.y, minf(ay, w.y), ww)
		else:
			nh = _new_h(w.x, w.z, w.y)
		if absf(nh - w.y) > 0.001:
			verts[i] = inv * Vector3(w.x, nh, w.z)
			changed += 1
	a[Mesh.ARRAY_VERTEX] = verts
	# 重算法線
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var cols: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	for i in verts.size():
		if uvs.size() > i:
			st.set_uv(uvs[i])
		if cols.size() > i:
			st.set_color(cols[i])
		st.add_vertex(verts[i])
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	for k in idx:
		st.add_index(k)
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, mi.mesh.surface_get_material(0))
	print("REBUILD %s verts=%d changed=%d" % [mi.name, verts.size(), changed])
	return m


func _paint_mask() -> void:
	var src := "res://maps/shrine/gen/ground_tex.res"
	var tex: Texture2D = load(src)
	var img: Image = tex.get_image()
	img.decompress()
	var half := 75.0
	var res := img.get_width()
	var painted := 0
	for j in res:
		var z := -half + (float(j) + 0.5) / float(res) * 2.0 * half
		if z < Z_TOP_FLAT0 - 6.0:
			continue
		for i in res:
			var x := -half + (float(i) + 0.5) / float(res) * 2.0 * half
			var axis := 1.0 - smoothstep(1.5, 2.6, absf(x))
			if axis <= 0.0:
				continue
			var c := img.get_pixel(i, j)
			c.r = maxf(c.r, axis)
			c.g = c.g * (1.0 - axis)
			# 石階段鋪石權重高一點
			if z > Z_STAIR_TOP - 1.0 and z < _z_bottom + 1.0:
				c.a = maxf(c.a, axis * 0.7)
			img.set_pixel(i, j, c)
			painted += 1
	var out := PortableCompressedTexture2D.new()
	out.keep_compressed_buffer = true
	out.create_from_image(img, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
	var err := ResourceSaver.save(out, src)
	print("MASK painted=%d err=%d" % [painted, err])


func _build_torii(kit: Node3D) -> void:
	var ps: PackedScene = load(TORII)
	var box := _aabb_of(ps)
	var inst: Node3D = ps.instantiate()
	inst.scale = Vector3.ONE * TORII2_SCALE
	inst.position = Vector3(0.0, Y_TOP - box.position.y * TORII2_SCALE, Z_TORII2)
	_add(kit, inst, "二之鳥居")
	var clear_w := 0.481 * box.size.x * TORII2_SCALE
	print("TORII2 h=%.2f clear=%.2f" % [box.size.y * TORII2_SCALE, clear_w])
	var body := StaticBody3D.new()
	_add(kit, body, "二之鳥居碰撞")
	for side in [-1.0, 1.0]:
		var sh := CollisionShape3D.new()
		var c := CylinderShape3D.new()
		c.radius = 0.26
		c.height = box.size.y * TORII2_SCALE
		sh.shape = c
		sh.position = Vector3(side * (clear_w * 0.5 + 0.26), Y_TOP + c.height * 0.5, Z_TORII2)
		body.add_child(sh)
		sh.owner = kit


func _build_stairs(kit: Node3D) -> void:
	var g := Node3D.new()
	_add(kit, g, "出口石階")
	var body := StaticBody3D.new()
	_add(g, body, "石階碰撞")
	var tread := Node3D.new(); _add(g, tread, "踏石")
	var sode := Node3D.new(); _add(g, sode, "袖石垣")
	var n := 0
	for e in _plan:
		var depth: float = e.z1 - e.z0
		var top: float = e.y0          # 往下走：每階頂面 = 北緣高度
		var cz: float = (e.z0 + e.z1) * 0.5
		var kitname: String = "平台石" if e.landing else "踏石"
		var seam := 0.06 if n % 2 == 0 else -0.06
		for side in [-1.0, 1.0]:
			var half_w := STEP_W * 0.5
			_step_stone(kit, tread, KIT[kitname][0], Vector3(side * half_w * 0.5 + seam, top, cz),
				Vector3(half_w, KIT[kitname][1].y, depth), "%s_%02d_%s" % [kitname, n, "L" if side < 0 else "R"])
		for side in [-1.0, 1.0]:
			var kw: float = KIT["袖石垣"][1].x
			var kh: float = KIT["袖石垣"][1].y
			_step_stone(kit, sode, KIT["袖石垣"][0],
				Vector3(side * (STEP_W * 0.5 + kw * 0.5), top + kh * 0.45, cz),
				Vector3(kw, kh, depth), "袖石_%02d_%s" % [n, "L" if side < 0 else "R"])
		var blk_h: float = 0.8
		var sh := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(STEP_W + 0.9, blk_h, depth)
		sh.shape = bs
		sh.position = Vector3(0.0, top - blk_h * 0.5, cz)
		body.add_child(sh)
		sh.owner = kit
		n += 1
	var cap := Node3D.new(); _add(g, cap, "收頭石")
	for spec in [[Z_STAIR_TOP - 0.30, Y_TOP, "北"], [_z_bottom + 0.30, _y_bottom, "南"]]:
		for side in [-1.0, 1.0]:
			_step_stone(kit, cap, KIT["收頭石"][0],
				Vector3(side * STEP_W * 0.25, spec[1] + 0.02, spec[0]),
				Vector3(STEP_W * 0.5, KIT["收頭石"][1].y, KIT["收頭石"][1].z),
				"收頭_%s_%s" % [spec[2], "L" if side < 0 else "R"])
	print("STAIR_PIECES steps=%d" % n)


func _build_lanterns(kit: Node3D) -> void:
	var g := Node3D.new()
	_add(kit, g, "石燈籠")
	var ps: PackedScene = load(_lantern_path)
	if ps == null:
		push_error("lantern load failed " + _lantern_path)
		return
	var box := _aabb_of(ps)
	var s := LANTERN_H / box.size.y
	# [z, x偏移, 地面 y]
	var spots := [
		[Z_TORII2 - 2.2, 2.7, Y_TOP],
		[Z_STAIR_TOP - 0.9, 2.45, Y_TOP],
		[_z_bottom + 1.1, 2.45, _y_bottom],
	]
	var i := 0
	# stone_lantern.glb 自帶材質是無貼圖純色（實拍粉藍發白）；套地藏同款石材
	var stone_mat: Material = load("res://assets/materials/jizo_stone.tres")
	for sp in spots:
		for side in [-1.0, 1.0]:
			# ⚠ 實例化 GLB 再改子節點 material_override 不會進 .tscn（記錄在案）；
			#   改成自建 MeshInstance3D 直接持有 mesh + override。
			var src: Node3D = ps.instantiate()
			var mns := _mesh_nodes(src)
			var inst := MeshInstance3D.new()
			inst.mesh = (mns[0] as MeshInstance3D).mesh
			inst.material_override = stone_mat
			src.free()
			inst.scale = Vector3.ONE * s
			var cx: float = side * sp[1]
			# 落地：CENTRE/BASE 原點通吃
			inst.position = Vector3(cx - (box.position.x + box.size.x * 0.5) * s, sp[2] - box.position.y * s,
				sp[0] - (box.position.z + box.size.z * 0.5) * s)
			inst.rotation.y = deg_to_rad(90.0 if side < 0 else -90.0)
			_add(g, inst, "燈籠_%d_%s" % [i, "L" if side < 0 else "R"])
			var body := StaticBody3D.new()
			_add(g, body, "燈籠碰撞_%d_%s" % [i, "L" if side < 0 else "R"])
			var sh := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(0.7, LANTERN_H, 0.7)
			sh.shape = bs
			sh.position = Vector3(cx, sp[2] + LANTERN_H * 0.5, sp[0])
			body.add_child(sh)
			sh.owner = kit
		i += 1
	print("LANTERNS %d pairs asset=%s h=%.2f" % [i, _lantern_path, LANTERN_H])


## 新邊界：原南牆 z=62 要停用（MCP），這裡補：南牆兩翼 z=62、走廊側牆、走廊南端牆 z=Z_PAD_END
func _build_boundary(kit: Node3D) -> void:
	var body := StaticBody3D.new()
	_add(kit, body, "出口邊界")
	var half := 53.0
	var gap := 4.6
	var walls := [
		[Vector3(-(half + gap) * 0.5, 14.0, 62.0), Vector3(half - gap, 52.0, 1.0)],
		[Vector3((half + gap) * 0.5, 14.0, 62.0), Vector3(half - gap, 52.0, 1.0)],
		[Vector3(-gap - 0.5, 14.0, (62.0 + Z_PAD_END) * 0.5), Vector3(1.0, 52.0, Z_PAD_END - 62.0 + 1.0)],
		[Vector3(gap + 0.5, 14.0, (62.0 + Z_PAD_END) * 0.5), Vector3(1.0, 52.0, Z_PAD_END - 62.0 + 1.0)],
		[Vector3(0.0, 14.0, Z_PAD_END + 0.5), Vector3(gap * 2.0 + 2.0, 52.0, 1.0)],
	]
	for w in walls:
		var sh := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = w[1]
		sh.shape = b
		sh.position = w[0]
		body.add_child(sh)
		sh.owner = kit


func _list_trees(scn: Node3D, tm: ArrayMesh) -> void:
	var moves: Array = []
	var veg: Node = scn.get_node("植被")
	var stack: Array = veg.get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if not (n is Node3D):
			continue
		var nm := String(n.name)
		var parts := nm.rsplit("_", true, 1)
		var is_tree := parts.size() == 2 and parts[1].is_valid_int() and n.get_child_count() > 0 \
			and not (n is MeshInstance3D)
		if not is_tree:
			stack.append_array(n.get_children())
			continue
		var p: Vector3 = (n as Node3D).global_position
		if p.z > Z_TOP_FLAT0 - 2.0 and p.z < Z_PAD_END + 12.0 and absf(p.x) < 9.5:
			var nx: float = signf(p.x if p.x != 0.0 else 1.0) * (10.5 + fmod(absf(p.z) * 0.37, 3.0))
			moves.append({"path": String(scn.get_path_to(n)), "from": [p.x, p.y, p.z], "to_x": nx, "z": p.z})
	print("MOVE_TREES " + JSON.stringify(moves))


func _step_stone(owner: Node, parent: Node3D, path: String, pos: Vector3, size: Vector3, nm: String) -> void:
	var ps: PackedScene = load(path)
	var box := _aabb_of(ps)
	var s := Vector3(size.x / maxf(box.size.x, 0.01), size.y / maxf(box.size.y, 0.01), size.z / maxf(box.size.z, 0.01))
	var inst: Node3D = ps.instantiate()
	inst.scale = s
	inst.position = Vector3(pos.x, pos.y - size.y - box.position.y * s.y, pos.z)
	inst.rotation.y = fmod(float(nm.hash()) * 0.0001, 0.04) - 0.02
	parent.add_child(inst)
	inst.owner = owner


func _add(parent: Node, n: Node, nm: String) -> void:
	n.name = nm
	parent.add_child(n)
	var o: Node = parent
	while o.get_parent() != null and o.get_parent() != root:
		o = o.get_parent()
	n.owner = o


func _aabb_of(ps: PackedScene) -> AABB:
	var inst: Node3D = ps.instantiate()
	var acc := AABB(); var has := false
	var st: Array = [[inst, Transform3D.IDENTITY]]
	while not st.is_empty():
		var pr: Array = st.pop_back()
		var nn: Node = pr[0]; var xf: Transform3D = pr[1]
		if nn != inst and nn is Node3D:
			xf = xf * (nn as Node3D).transform
		if nn is MeshInstance3D and nn.mesh != null:
			var b: AABB = xf * nn.mesh.get_aabb()
			acc = acc.merge(b) if has else b; has = true
		for c in nn.get_children():
			st.push_back([c, xf])
	inst.free()
	return acc


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


func _mesh_nodes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		o.append(n)
	for c in n.get_children():
		o.append_array(_mesh_nodes(c))
	return o
