extends SceneTree
## B2 小河（用水路）樣板段。
## r4：依《河岸建築部件》規格表重建。先前版本自行猜縮放，堰做成 3.7 倍、
## 護岸把 3m 模組拉成 8m，全部作廢。
##
## 規格表尺寸（公尺）：
##   水車輪 Ø4.0 × 1.2（僅輪子，不含支架／軸承座／小屋）
##   水車小屋 = 小屋＋軸承座＋支撐木架，側面留輪子的空位 → 輪子要嵌進去
##   堰／小型分水閘門 2.8 × 2.2 × 2.2
##   塊石牆一段 3.0 × 1.2 × 1.0（模組：平鋪＋堆疊，不可拉長）
##   親水階梯 2.5 × 2.0 × 1.5   濱水平台 3.0 × 0.6   灌溉引水渠口 1.8 × 1.2 × 1.0
##
## 縮放一律由「規格尺寸 ÷ 實測 bbox」求得，不手填倍率。

const CX: float = 340.0
const Z0: float = -25.0
const Z1: float = 25.0
const BED_UP: float = -2.45         # 堰上游床
const BED_DN: float = -5.45         # 堰下游床：上掛水車需要 ~4m 水頭
const WALL_FACE: float = 2.7        # 護岸面到渠道中線
const COURSE: int = 7               # 上限；實測模組高 0.88m，超出地面自動停
const WEIR_Z: float = 3.0
const UP_WATER_Y: float = -0.95
const DN_WATER_Y: float = -4.95     # 落差 4.00m＝輪徑，上掛水車成立
const WHEEL_Z: float = 6.5        # 堰下游，承接跌水
const STAIR_Z: float = -7.0         # 親水節點移到上游靜水段（下游是水車跌水區）
const INTAKE_Z: float = -14.0
const PLATFORM_Z: float = -2.0
const BRIDGE_Z: float = -21.0

func _init() -> void:
	var root: Node3D = Node3D.new()
	root.name = "B2_Canal"
	_build_walls(root)
	_build_water(root)
	# 堰：以高度 2.2m 定縮放，寬度隨之約 6.1m，正好跨過 5.4m 水面
	_place(root, "res://assets/riverbank/堰／小型分水閘門.glb", "堰",
		"y", 2.2, 0.0, Vector3(CX, 0.0, WEIR_Z), BED_UP)
	# 水車小屋：岸上，側面空位朝渠道
	_place(root, "res://assets/riverbank/水車小屋.glb", "水車小屋",
		"z", 8.0, 90.0, Vector3(332.4, 0.0, WHEEL_Z), -0.85)
	# 水車：Ø4.0m，嵌進小屋側面空位，輪底觸下游水面
	var wheel: Node3D = _place(root, "res://assets/riverbank/水車.glb", "水車輪",
		"x", 4.0, 90.0, Vector3(338.5, 0.0, WHEEL_Z), DN_WATER_Y - 0.20)
	if wheel != null:
		wheel.set_script(load("res://scripts/water_wheel_spin.gd"))
	_place(root, "res://assets/bridges/田-村橋(清河橋).glb", "清河橋",
		"z", 10.0, 90.0, Vector3(CX, 0.0, BRIDGE_Z), -0.25)
	_place(root, "res://assets/riverbank/親水階梯一組.glb", "親水階梯",
		"y", 1.5, -90.0, Vector3(343.3, 0.0, STAIR_Z), UP_WATER_Y - 0.05)
	_place(root, "res://assets/riverbank/濱水平台一塊.glb", "濱水平台",
		"x", 3.0, -90.0, Vector3(343.6, 0.0, PLATFORM_Z), -0.15)
	# 灌溉引水渠口：農田側（東岸），把水引出渠道進田
	_place(root, "res://assets/riverbank/田泵水口.glb", "灌溉引水渠口",
		"y", 1.2, -90.0, Vector3(343.0, 0.0, INTAKE_Z), -0.9)
	var ps: PackedScene = PackedScene.new()
	var err: int = ps.pack(root)
	if err != OK:
		push_error("pack failed: %d" % err)
	else:
		err = ResourceSaver.save(ps, "res://maps/slice/gen/b2_canal.tscn")
		print("SAVE_RESULT %d" % err)
	quit()


func _local_bbox(root_node: Node3D) -> AABB:
	var acc: AABB = AABB()
	var has: bool = false
	var stack: Array = []
	for c in root_node.get_children():
		stack.push_back([c, Transform3D.IDENTITY])
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var nd: Node = pair[0]
		var xf: Transform3D = pair[1]
		if nd is Node3D:
			xf = xf * (nd as Node3D).transform
		if nd is MeshInstance3D:
			var mi: MeshInstance3D = nd
			if mi.mesh != null:
				var a: AABB = xf * mi.mesh.get_aabb()
				if has:
					acc = acc.merge(a)
				else:
					acc = a
					has = true
		for c2 in nd.get_children():
			stack.push_back([c2, xf])
	return acc


## 依規格尺寸擺放。spec_axis 指定用哪一軸對規格（"x"/"y"/"z"），
## 求得等比縮放後，水平置中於 center_xz、底面對齊 bottom_y。
func _place(root: Node3D, path: String, node_name: String,
		spec_axis: String, spec_size: float, rot_y_deg: float,
		center_xz: Vector3, bottom_y: float) -> Node3D:
	var scn: PackedScene = load(path)
	if scn == null:
		push_error("load failed: " + path)
		return null
	var inst: Node3D = scn.instantiate() as Node3D
	inst.name = node_name
	var bb: AABB = _local_bbox(inst)
	var src: float = bb.size.x
	if spec_axis == "y":
		src = bb.size.y
	elif spec_axis == "z":
		src = bb.size.z
	var s: float = spec_size / maxf(src, 0.0001)
	var c: Vector3 = bb.position + bb.size * 0.5
	var rot: Basis = Basis(Vector3.UP, deg_to_rad(rot_y_deg))
	var off: Vector3 = rot * (c * s)
	inst.rotation_degrees = Vector3(0.0, rot_y_deg, 0.0)
	inst.scale = Vector3(s, s, s)
	inst.position = Vector3(
		center_xz.x - off.x,
		bottom_y - (c.y - bb.size.y * 0.5) * s,
		center_xz.z - off.z)
	root.add_child(inst)
	inst.owner = root
	print("PLACED %s scale=%.3f final=%.2fx%.2fx%.2f" %
		[node_name, s, bb.size.x * s, bb.size.y * s, bb.size.z * s])
	return inst


## 渠床高程：堰上游平緩，下游跌落成水車坑（水頭＝輪徑 4.0m）。
func _bed_y(z: float) -> float:
	return lerpf(BED_UP, BED_DN, smoothstep(WEIR_Z - 1.0, WEIR_Z + 5.0, z))


func _build_walls(root: Node3D) -> void:
	## 塊石牆模組：規格 3.0m 長。平鋪沿岸、堆疊 COURSE 層築成護岸。
	## 不拉長單一模組——那會把石紋撐爛（r3 的錯）。
	var walls: Node3D = Node3D.new()
	walls.name = "石砌護岸"
	root.add_child(walls)
	walls.owner = root
	var scn: PackedScene = load("res://assets/riverbank/塊石疊砌牆一段.glb")
	if scn == null:
		push_error("wall load failed")
		return
	var probe: Node3D = scn.instantiate() as Node3D
	var bb: AABB = _local_bbox(probe)
	probe.free()
	var s: float = 3.0 / maxf(bb.size.x, 0.0001)     # 規格長 3.0m
	var seg_len: float = bb.size.x * s
	var seg_h: float = bb.size.y * s
	var seg_d: float = bb.size.z * s
	var c: Vector3 = bb.position + bb.size * 0.5
	var n_seg: int = int(floor((Z1 - Z0) / seg_len))
	var count: int = 0
	for side in [-1.0, 1.0]:
		var ry: float = 90.0 if side < 0.0 else -90.0
		var rot: Basis = Basis(Vector3.UP, deg_to_rad(ry))
		var off: Vector3 = rot * (c * s)
		for k in range(n_seg):
			var wz: float = Z0 + seg_len * (float(k) + 0.5)
			# 西岸水車輪坑
			if side < 0.0 and absf(wz - WHEEL_Z) < 3.2:
				continue
			# 東岸親水階梯與引水渠口
			if side > 0.0 and (absf(wz - STAIR_Z) < 2.4 or absf(wz - INTAKE_Z) < 2.0):
				continue
			for course in range(COURSE):
				var base_y: float = _bed_y(wz) + seg_h * float(course)
				if base_y > -0.05:
					break
				var inst: Node3D = scn.instantiate() as Node3D
				inst.name = "wall_%02d_%d" % [k, course]
				inst.rotation_degrees = Vector3(0.0, ry, 0.0)
				inst.scale = Vector3(s, s, s)
				var face_x: float = CX + side * WALL_FACE
				var cx_w: float = face_x + side * seg_d * 0.5
				inst.position = Vector3(cx_w - off.x,
					base_y - (c.y - bb.size.y * 0.5) * s, wz - off.z)
				walls.add_child(inst)
				inst.owner = root
				count += 1
	print("WALLS %d (seg %.2fm x %.2fm, %d courses)" % [count, seg_len, seg_h, COURSE])


func _build_water(root: Node3D) -> void:
	var mat: Material = load("res://assets/materials/east_river_water.tres")
	_water_plane(root, mat, "UpperWater", UP_WATER_Y, Z0 - 2.0, WEIR_Z - 0.3)
	_water_plane(root, mat, "LowerWater", DN_WATER_Y, WEIR_Z + 0.5, Z1 + 2.0)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw: float = WALL_FACE - 0.15
	var a: Vector3 = Vector3(CX - hw, UP_WATER_Y - 0.02, WEIR_Z - 0.3)
	var b: Vector3 = Vector3(CX + hw, UP_WATER_Y - 0.02, WEIR_Z - 0.3)
	var c2: Vector3 = Vector3(CX + hw, DN_WATER_Y - 0.02, WEIR_Z + 0.6)
	var d: Vector3 = Vector3(CX - hw, DN_WATER_Y - 0.02, WEIR_Z + 0.6)
	for v in [a, b, c2, a, c2, d]:
		st.set_uv(Vector2(v.x * 0.1, v.z * 0.1))
		st.add_vertex(v)
	st.generate_normals()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "WeirSpill"
	mi.mesh = st.commit()
	mi.material_override = mat
	root.add_child(mi)
	mi.owner = root


func _water_plane(root: Node3D, mat: Material, node_name: String,
		wy: float, za: float, zb: float) -> void:
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = Vector2((WALL_FACE - 0.15) * 2.0, zb - za)
	mesh.subdivide_width = 4
	mesh.subdivide_depth = 20
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = Vector3(CX, wy, (za + zb) * 0.5)
	mi.material_override = mat
	mi.set_meta("water_surface", true)
	root.add_child(mi)
	mi.owner = root
