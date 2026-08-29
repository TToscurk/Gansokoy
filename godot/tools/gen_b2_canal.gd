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
const BED_UP: float = -2.80         # 堰上游床（水深 1.0m）
const BED_DN: float = -2.80         # v2 雛型：單一水位，不再分上下游
const WALL_FACE: float = 4.0        # 護岸面到渠道中線 → 水面寬 7.7m
const COURSE: int = 7               # 上限；實測模組高 0.88m，超出地面自動停
const WEIR_Z: float = 3.0
const UP_WATER_Y: float = -1.80     # 上游水面：牆露 1.8m
const DN_WATER_Y: float = -1.80     # 與上游同高：整條渠道讀成同一種建築
const WHEEL_Z: float = 6.5        # 堰下游，承接跌水
const STAIR_Z: float = -7.0         # 親水節點在上游靜水段
const INTAKE_Z: float = -14.0
const PLATFORM_Z: float = -2.0
const BRIDGE_Z: float = -21.0
## 水車坑：r8。舊版只是把三段牆 `continue` 掉，留下一片裸土（使用者 2026-08-29
## 指出的「缺口」）。改成砌成有底有側的壁龕：主牆在此退到坑底，兩端加回歸牆。
const PIT_Z0: float = 4.4
const PIT_Z1: float = 8.6
const PIT_DEPTH: float = 0.6
## 護岸砌法：錯縫 + 每塊微擾。固定種子，重跑結果一致。
const WALL_SEED: int = 20260829
const BOND_OVERLAP_Y: float = 0.06  # 層間壓疊量，>最大縮放抖動，杜絕透光橫縫
const BOND_OVERLAP_Z: float = 0.05  # 同層相鄰壓疊量
## r9 砌法：勾配與坐落。使用者 2026-08-29 指出「太直、沒貼平在河岸上」。
## 量測佐證：147 塊局部 Y 軸偏離垂直全為 0.00 度，牆面只落在 8 個 X 平面。
## 病灶是 (1) face 每層共用同一 WALL_FACE，零勾配；(2) 只給 yaw，X/Z 旋轉寫死 0。
const WALL_BATTER: float = 0.15     # 勾配 1:0.15——每上升 1m，牆面往岸內退 0.15m
const BLOCK_TILT: float = 1.4       # 每塊坐落微傾上限（度），疊在勾配之上

func _init() -> void:
	var root: Node3D = Node3D.new()
	root.name = "B2_Canal"
	_build_walls(root)
	_build_bed(root)
	_build_water(root)
	# v2：落差取消後它不再是攔河堰，回歸「小型分水閘門」本名——
	# 縮到高 1.0m 使冠頂齊水面 -1.80，靠東岸擺，是取水口不是水壩。
	_place(root, "res://assets/riverbank/堰／小型分水閘門.glb", "分水閘門",
		"y", 1.0, 0.0, Vector3(342.2, 0.0, WEIR_Z), BED_UP)
	# v2 雛型：放棄 4m 深坑上掛，改成齊岸胸射輪。渲染證實深坑讓上下游護岸
	# 讀成兩種建築，且小屋永遠碰不到輪軸。現在輪軸在 -1.10（岸下 1.1m），
	# 由砌石墩承住，小屋樓板落在岸面 0.0——與參考圖同一種關係。
	# 輪 Ø3.0，底 -2.60 正好觸下游水面，頂 +0.40 微高於岸。
	var wheel: Node3D = _place(root, "res://assets/riverbank/水車.glb", "水車輪",
		"x", 3.0, 90.0, Vector3(336.8, 0.0, WHEEL_Z), -2.40)
	# 小屋樓板齊岸，東緣 336.3 接上輪西緣
	_place(root, "res://assets/riverbank/水車小屋.glb", "水車小屋",
		"z", 10.0, 90.0, Vector3(331.3, 0.0, WHEEL_Z), 0.0)
	# 木樋：自上游引水到輪腰（胸射），不再吊到 4m 高
	_place(root, "res://assets/riverbank/木樋（引水槽）支撐棚架.glb", "木樋",
		"x", 7.0, 90.0, Vector3(336.8, 0.0, 3.4), -1.30)
	if wheel != null:
		wheel.set_script(load("res://scripts/water_wheel_spin.gd"))
	_place(root, "res://assets/bridges/田-村橋(清河橋).glb", "清河橋",
		"z", 11.0, 90.0, Vector3(CX, 0.0, BRIDGE_Z), 0.0)
	_place(root, "res://assets/riverbank/親水階梯一組.glb", "親水階梯",
		"y", 1.8, -90.0, Vector3(343.6, 0.0, STAIR_Z), UP_WATER_Y)
	_place(root, "res://assets/riverbank/濱水平台一塊.glb", "濱水平台",
		"x", 3.0, -90.0, Vector3(344.4, 0.0, PLATFORM_Z), 0.0)
	# 灌溉引水渠口：農田側（東岸），把水引出渠道進田
	_place(root, "res://assets/riverbank/田泵水口.glb", "灌溉引水渠口",
		"y", 1.2, -90.0, Vector3(344.0, 0.0, INTAKE_Z), -1.30)
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


## 與 _local_bbox 同一套走訪，但把 nd 自身的 transform 也算進去，
## 用來在擺放之後量「實際落在哪」。
func _subtree_bbox(nd: Node3D) -> AABB:
	var acc: AABB = AABB()
	var has: bool = false
	var stack: Array = [[nd, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var n: Node = pair[0]
		var xf: Transform3D = pair[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n
			if mi.mesh != null:
				var a: AABB = xf * mi.mesh.get_aabb()
				if has:
					acc = acc.merge(a)
				else:
					acc = a
					has = true
		for c2 in n.get_children():
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
	## r9 兩段式定位：擺完實測一次，把殘差補回去。解析預測對水車小屋失準
	## （要求中心 x=334.0，實得 328.27，與水車拉開 5.5m），實測校正讓宣告值必成立。
	var got: AABB = _subtree_bbox(inst)
	if got.size.length() > 0.0001:
		var gc: Vector3 = got.position + got.size * 0.5
		inst.position += Vector3(
			center_xz.x - gc.x,
			bottom_y - got.position.y,
			center_xz.z - gc.z)
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
	## r8 砌法修正。舊版三個病灶：
	##  (1) 每層起點相同 → 垂直通縫每 3m 一道，從渠底通到牆頂；
	##  (2) 層距正好等於模組高 → 塊與塊之間留髮絲縫透光，就是渲染圖裡
	##      橫貫整個畫面那條亮線；
	##  (3) 118 塊同一顆石頭、同一角度、同一尺寸 → 讀成貼圖不是砌石。
	## 對策：奇數層平移半格（錯縫）、層距與格距各壓疊一點、每塊依固定種子
	## 微擾角度與尺寸。不做 180 度翻面——模組背面未必可見，翻了會破面。
	var pitch_z: float = seg_len - BOND_OVERLAP_Z
	var pitch_y: float = seg_h - BOND_OVERLAP_Y
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var count: int = 0
	for side in [-1.0, 1.0]:
		var ry: float = 90.0 if side < 0.0 else -90.0
		for course in range(COURSE):
			var shift: float = pitch_z * 0.5 if course % 2 == 1 else 0.0
			var n_seg: int = int(ceil((Z1 - Z0) / pitch_z)) + 1
			for k in range(n_seg):
				var wz: float = Z0 + shift + pitch_z * (float(k) + 0.5)
				if wz > Z1 + pitch_z * 0.5:
					continue
				# 東岸親水階梯與引水渠口留空
				if side > 0.0 and (absf(wz - STAIR_Z) < 2.4 or absf(wz - INTAKE_Z) < 2.0):
					continue
				# 西岸水車坑：主牆退到坑底，坑仍然是砌石不是裸土
				var rise: float = pitch_y * float(course)
				var face_x: float = CX + side * (WALL_FACE + WALL_BATTER * rise)
				if side < 0.0 and wz > PIT_Z0 and wz < PIT_Z1:
					face_x += side * PIT_DEPTH
				# 截止條件看石塊「頂面」不是底面。r8 第一版沿用舊的底面判斷，
				# 但層距壓成 0.82 後同一條件多容一層，壓頂石整排凸出草地。
				# 0.30 是留給壓頂的唇高，與大河護岸 0.22 同一類做法。
				var base_y: float = _bed_y(wz) + pitch_y * float(course)
				if base_y + seg_h > 0.30:
					continue
				rng.seed = WALL_SEED + int(side + 2.0) * 100000 + k * 100 + course
				_wall_block(walls, root, scn, bb, c, s, seg_d, rng,
					"wall_%s%02d_%d" % ["w" if side < 0.0 else "e", k, course],
					ry, face_x, side, base_y, wz)
				count += 1
		# 水車坑的兩道回歸牆（坑的上下游側壁），沿 x 佈置把裸土封起來
		if side < 0.0:
			for pz in [PIT_Z0, PIT_Z1]:
				for course in range(COURSE):
					var by: float = _bed_y(pz) + pitch_y * float(course)
					if by + seg_h > 0.30:
						continue
					rng.seed = WALL_SEED + 900000 + int(pz * 10.0) * 100 + course
					var pside: float = -1.0 if pz < WHEEL_Z else 1.0
					var prise: float = pitch_y * float(course)
					_wall_block(walls, root, scn, bb, c, s, seg_d, rng,
						"pit_%02d_%d" % [int(pz), course],
						0.0, pz + pside * WALL_BATTER * prise, pside,
						by, CX - WALL_FACE - PIT_DEPTH * 0.5)
					count += 1
	print("WALLS %d (seg %.2fm x %.2fm, pitch %.2f/%.2f, %d courses)"
		% [count, seg_len, seg_h, pitch_z, pitch_y, COURSE])


## 擺一塊護岸石。face_axis 是牆面所在座標，run_axis 是沿牆方向的座標；
## 兩者的意義隨 ry 旋轉互換，由呼叫端負責傳對。
func _wall_block(walls: Node3D, root: Node3D, scn: PackedScene, bb: AABB,
		c: Vector3, s0: float, seg_d: float, rng: RandomNumberGenerator,
		node_name: String, ry: float, face_v: float, side: float,
		base_y: float, run_v: float) -> void:
	var s: float = s0 * rng.randf_range(0.97, 1.03)
	var yaw: float = ry + rng.randf_range(-2.5, 2.5)
	## 勾配：石塊頂端往岸內傾，與每層退縮量同一角度，牆面才是一個斜面而非階梯。
	## 再疊上每塊的坐落微傾，砌石才不會讀成一片機器切出來的平面。
	var lean: float = rad_to_deg(atan(WALL_BATTER)) + rng.randf_range(-BLOCK_TILT, BLOCK_TILT)
	var roll: float = rng.randf_range(-BLOCK_TILT, BLOCK_TILT)
	var b: Basis = Basis(Vector3.UP, deg_to_rad(yaw))
	if absf(ry) > 45.0:
		# 牆沿 Z 走、深度在 X：繞世界 Z 傾倒
		b = Basis(Vector3.BACK, deg_to_rad(-side * lean)) * b
		b = Basis(Vector3.RIGHT, deg_to_rad(roll)) * b
	else:
		# 牆沿 X 走、深度在 Z：繞世界 X 傾倒
		b = Basis(Vector3.RIGHT, deg_to_rad(side * lean)) * b
		b = Basis(Vector3.BACK, deg_to_rad(roll)) * b
	var off: Vector3 = b * (c * s)
	var inst: Node3D = scn.instantiate() as Node3D
	inst.name = node_name
	inst.transform.basis = b.scaled(Vector3(s, s, s))
	var depth_v: float = face_v + side * (seg_d * 0.5 + rng.randf_range(-0.05, 0.05))
	var y: float = base_y - (c.y - bb.size.y * 0.5) * s + rng.randf_range(-0.03, 0.03)
	var run: float = run_v + rng.randf_range(-0.04, 0.04)
	if absf(ry) > 45.0:
		inst.position = Vector3(depth_v - off.x, y, run - off.z)
	else:
		inst.position = Vector3(run - off.x, y, depth_v - off.z)
	walls.add_child(inst)
	inst.owner = root


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


func _build_bed(root: Node3D) -> void:
	## 砌石渠床。地形格點 6m 畫不出 5.4m 寬的垂直渠道（會內插成 V 形谷，
	## 水面只剩中央一條縫——2026-08-29 的 AFTER 圖就是這個症狀）。
	## 解法：地形挖得比這裡更深，渠床由本函式鋪成實體，水永遠有底。
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw: float = WALL_FACE
	var za: float = Z0 - 3.0
	var zb: float = Z1 + 3.0
	var segs: int = 90
	for k in range(segs):
		var z0: float = za + (zb - za) * float(k) / float(segs)
		var z1: float = za + (zb - za) * float(k + 1) / float(segs)
		var y0: float = _bed_y(z0)
		var y1: float = _bed_y(z1)
		var a: Vector3 = Vector3(CX - hw, y0, z0)
		var b: Vector3 = Vector3(CX + hw, y0, z0)
		var c: Vector3 = Vector3(CX + hw, y1, z1)
		var d: Vector3 = Vector3(CX - hw, y1, z1)
		for v in [a, b, c, a, c, d]:
			st.set_uv(Vector2(v.x * 0.25, v.z * 0.25))
			st.add_vertex(v)
	st.generate_normals()
	st.generate_tangents()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "CanalBed"
	mi.mesh = st.commit()
	mi.material_override = load("res://assets/materials/canal_bed.tres")
	root.add_child(mi)
	mi.owner = root
	print("BED %.1fm long, %.2f..%.2f" % [zb - za, _bed_y(za), _bed_y(zb)])
