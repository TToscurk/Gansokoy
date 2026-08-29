extends SceneTree
## B2 小河（用水路）樣板段：水車＋堰＋木拱橋＋親水階梯＋石砌護岸。
## 產出 res://maps/slice/gen/b2_canal.tscn，於 slice.tscn 以單一節點實例。
## 依據：新版水護岸概念圖（分層護岸、親水節點）＋村落農村概念俯視（水車在堰的落差上）。
## 渠道地形由 gen_terrain_river.gd 的 CANAL_* 常數開挖，本檔數值與其對齊。
## 擺位一律量實際 AABB（教訓：glTF 節點可帶 translation/MATRIX，參數表會浮空）。

const CX: float = 340.0            # 渠道中線（= 地形 CANAL_X）
const Z0: float = -46.0
const Z1: float = 46.0
const WEIR_Z: float = 2.0          # 堰位置：上游高水、下游低水
const UP_WATER_Y: float = -0.55    # 上游水面
const DN_WATER_Y: float = -1.35    # 下游水面（落差 0.8m 驅動水車）
const BED_Y: float = -2.05
const WALL_FACE: float = 5.2       # 護岸面到中線距離
const WALL_STEP: float = 8.05

func _init() -> void:
	var root: Node3D = Node3D.new()
	root.name = "B2_Canal"
	_build_walls(root)
	_build_water(root)
	_spawn(root, "res://assets/riverbank/堰／小型分水閘門.glb", "堰",
		Vector3(5.4, 5.4, 5.4), 0.0, Vector3(CX, 0.0, WEIR_Z), -2.05, false)
	var wheel: Node3D = _spawn(root, "res://assets/riverbank/水車.glb", "水車",
		Vector3(4.2, 4.2, 4.2), 90.0, Vector3(337.9, 0.0, 5.4), 0.0, true)
	if wheel != null:
		wheel.position.y = 0.25   # 軸心高：輪底 -1.85，浸入下游水面 0.5m
		wheel.set_script(load("res://scripts/water_wheel_spin.gd"))
	_spawn(root, "res://assets/riverbank/水車小屋.glb", "水車小屋",
		Vector3(3.2, 3.2, 3.2), 90.0, Vector3(330.2, 0.0, 5.4), -0.15, false)
	_spawn(root, "res://assets/bridges/田-村橋(清河橋).glb", "清河橋",
		Vector3(13.0, 13.0, 13.0), 90.0, Vector3(CX, 0.0, -28.0), -0.35, false)
	_spawn(root, "res://assets/riverbank/親水階梯一組.glb", "親水階梯",
		Vector3(4.0, 4.0, 4.0), -90.0, Vector3(343.2, 0.0, -14.0), -1.75, false)
	_spawn(root, "res://assets/riverbank/濱水平台一塊.glb", "濱水平台",
		Vector3(2.2, 2.2, 2.2), -90.0, Vector3(343.6, 0.0, -20.5), -1.5, false)
	_spawn(root, "res://assets/riverbank/田泵水口.glb", "田泵水口",
		Vector3(2.6, 2.6, 2.6), -90.0, Vector3(344.6, 0.0, 28.0), -0.7, false)
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


## 量 AABB 後擺放：水平置中於 center_xz，底面對齊 bottom_y。
## center_y_mode=true 時忽略 bottom_y，由呼叫端自行設 y（水車軸心用）。
func _spawn(root: Node3D, path: String, node_name: String, s: Vector3,
		rot_y_deg: float, center_xz: Vector3, bottom_y: float,
		center_y_mode: bool) -> Node3D:
	var scn: PackedScene = load(path)
	if scn == null:
		push_error("load failed: " + path)
		return null
	var inst: Node3D = scn.instantiate() as Node3D
	inst.name = node_name
	var bb: AABB = _local_bbox(inst)
	var c: Vector3 = bb.position + bb.size * 0.5
	var rot: Basis = Basis(Vector3.UP, deg_to_rad(rot_y_deg))
	var off: Vector3 = rot * Vector3(c.x * s.x, c.y * s.y, c.z * s.z)
	inst.rotation_degrees = Vector3(0.0, rot_y_deg, 0.0)
	inst.scale = s
	var py: float = 0.0
	if not center_y_mode:
		py = bottom_y - (c.y - bb.size.y * 0.5) * s.y
	inst.position = Vector3(center_xz.x - off.x, py, center_xz.z - off.z)
	root.add_child(inst)
	inst.owner = root
	print("PLACED %s bb=%s" % [node_name, str(bb.size)])
	return inst


func _build_walls(root: Node3D) -> void:
	## 塊石疊砌牆：兩岸各 11 段。非等比縮放 (8, 8, 1.4)——模型深度軸過厚，
	## 直接等比會插進渠道；石紋在窄面上的拉伸可接受（見報告）。
	var walls: Node3D = Node3D.new()
	walls.name = "護岸"
	root.add_child(walls)
	walls.owner = root
	var scn: PackedScene = load("res://assets/riverbank/塊石疊砌牆一段.glb")
	if scn == null:
		push_error("wall load failed")
		return
	var i: int = 0
	for side in [-1.0, 1.0]:
		var face_x: float = CX + side * WALL_FACE
		# 面向渠道：西岸(-1)朝 +x → rot_y +90；東岸朝 -x → rot_y -90
		var ry: float = 90.0 if side < 0.0 else -90.0
		for k in range(11):
			var wz: float = -40.0 + WALL_STEP * float(k)
			# 東岸親水階梯槽位
			if side > 0.0 and absf(wz - (-16.0)) < 4.5:
				continue
			var inst: Node3D = scn.instantiate() as Node3D
			inst.name = "wall_%02d" % i
			var bb: AABB = _local_bbox(inst)
			var c: Vector3 = bb.position + bb.size * 0.5
			var s: Vector3 = Vector3(8.0, 8.0, 1.4)
			var rot: Basis = Basis(Vector3.UP, deg_to_rad(ry))
			var off: Vector3 = rot * Vector3(c.x * s.x, c.y * s.y, c.z * s.z)
			inst.rotation_degrees = Vector3(0.0, ry, 0.0)
			inst.scale = s
			var py: float = -2.2 - (c.y - bb.size.y * 0.5) * s.y
			# 面貼齊 face_x：牆深(局部 z)旋轉後沿世界 x，向岸側退半深
			var depth_w: float = bb.size.z * s.z
			var cx_w: float = face_x + side * depth_w * 0.5
			inst.position = Vector3(cx_w - off.x, py, wz - off.z)
			walls.add_child(inst)
			inst.owner = root
			i += 1
	print("WALLS %d" % i)


func _build_water(root: Node3D) -> void:
	var mat: Material = load("res://assets/materials/east_river_water.tres")
	# 上游池
	_water_plane(root, mat, "UpperWater", UP_WATER_Y, Z0 - 2.0, WEIR_Z - 0.4)
	# 下游池
	_water_plane(root, mat, "LowerWater", DN_WATER_Y, WEIR_Z + 0.6, Z1 + 2.0)
	# 堰落水斜面
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw: float = WALL_FACE - 0.1
	var a: Vector3 = Vector3(CX - hw, UP_WATER_Y - 0.02, WEIR_Z - 0.4)
	var b: Vector3 = Vector3(CX + hw, UP_WATER_Y - 0.02, WEIR_Z - 0.4)
	var c2: Vector3 = Vector3(CX + hw, DN_WATER_Y - 0.02, WEIR_Z + 0.7)
	var d: Vector3 = Vector3(CX - hw, DN_WATER_Y - 0.02, WEIR_Z + 0.7)
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
	mesh.size = Vector2((WALL_FACE - 0.1) * 2.0, zb - za)
	mesh.subdivide_width = 4
	mesh.subdivide_depth = 24
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = Vector3(CX, wy, (za + zb) * 0.5)
	mi.material_override = mat
	mi.set_meta("water_surface", true)
	root.add_child(mi)
	mi.owner = root
