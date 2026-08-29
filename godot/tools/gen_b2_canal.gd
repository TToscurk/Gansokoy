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
## 磨坊灣：小屋站在水邊柱基上，岸線在此退開讓出 6m 深的凹槽
const PIT_Z0: float = 3.8
const PIT_Z1: float = 9.2
const PIT_DEPTH: float = 6.0
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
	_build_bay(root)
	_build_walkway(root)
	# v2：落差取消後它不再是攔河堰，回歸「小型分水閘門」本名——
	# 縮到高 1.0m 使冠頂齊水面 -1.80，靠東岸擺，是取水口不是水壩。
	_place(root, "res://assets/riverbank/堰／小型分水閘門.glb", "分水閘門",
		"y", 1.6, 0.0, Vector3(342.9, 0.0, WEIR_Z), UP_WATER_Y - 0.40)
	# r11：新資產組。實測小屋軸桿在高度 35.5%，規格高 4.5m → 軸心在基座上 1.598m。
	# 小屋不旋轉（rot 0），讓帶軸桿的 +X 面朝東對著渠道；基座 -2.30 使柱腳立在
	# 水邊（床 -2.80 之上 0.5m），軸心落在 -0.702，屋頂 +2.20 高過岸面。
	_place(root, "res://assets/riverbank/水車小屋.glb", "水車小屋",
		"y", 4.5, 0.0, Vector3(333.34, 0.0, WHEEL_Z), -2.30)
	# 水車 Ø3.0：輪心對齊小屋軸心 -0.702（底 -2.202，入水 0.40m）
	var wheel: Node3D = _place(root, "res://assets/riverbank/水車.glb", "水車輪",
		"x", 3.0, 90.0, Vector3(337.0, 0.0, WHEEL_Z), -2.202)
	# 木樋：自上游沿西岸送水到輪頂附近
	_place(root, "res://assets/riverbank/木樋（引水槽）支撐棚架.glb", "木樋",
		"x", 7.0, 90.0, Vector3(336.4, 0.0, 3.0), -2.60)
	if wheel != null:
		wheel.set_script(load("res://scripts/water_wheel_spin.gd"))
	_place(root, "res://assets/bridges/田-村橋(清河橋).glb", "清河橋",
		"z", 11.0, 90.0, Vector3(CX, 0.0, BRIDGE_Z), 0.0)
	_place(root, "res://assets/riverbank/親水階梯.glb", "親水階梯",
		"y", 1.8, -90.0, Vector3(343.2, 0.0, STAIR_Z), UP_WATER_Y)
	_place(root, "res://assets/riverbank/濱水平台.glb", "濱水平台",
		"y", 1.1, -90.0, Vector3(343.8, 0.0, PLATFORM_Z), -1.10)
	# 灌溉引水渠口：農田側（東岸），把水引出渠道進田
	_place(root, "res://assets/riverbank/田泵水口.glb", "灌溉引水渠口",
		"y", 1.6, -90.0, Vector3(343.4, 0.0, INTAKE_Z), -1.40)
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
			var bay_n: int = int(ceil(PIT_DEPTH / pitch_z))
			for pz in [PIT_Z0, PIT_Z1]:
				var pside: float = -1.0 if pz < WHEEL_Z else 1.0
				for course in range(COURSE):
					var by: float = _bed_y(pz) + pitch_y * float(course)
					if by + seg_h > 0.30:
						continue
					var prise: float = pitch_y * float(course)
					for j in range(bay_n):
						var rx: float = CX - WALL_FACE - PIT_DEPTH + pitch_z * (float(j) + 0.5)
						if rx > CX - WALL_FACE:
							continue
						rng.seed = WALL_SEED + 900000 + int(pz * 10.0) * 1000 + course * 10 + j
						_wall_block(walls, root, scn, bb, c, s, seg_d, rng,
							"bay_%02d_%d_%d" % [int(pz), course, j],
							0.0, pz + pside * WALL_BATTER * prise, pside,
							by, rx)
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
	## r13：單一水面。落差取消後還留著 UpperWater/LowerWater/WeirSpill 三塊
	## 同高度的面互相重疊，渲染出矩形接縫。改成一張網格，磨坊池一併涵蓋，
	## 用同一組格點避免 T 型接點裂縫。
	var mat: Material = load("res://assets/materials/b2_canal_water.tres")
	var hw: float = WALL_FACE - 0.15
	var bx: float = CX - WALL_FACE - PIT_DEPTH + 0.5   # 池西緣（略內縮於牆）
	var za: float = Z0 - 2.0
	var zb: float = Z1 + 2.0
	var cell: float = 1.8
	var nx: int = int(ceil((CX + hw - bx) / cell))
	var nz: int = int(ceil((zb - za) / cell))
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ix in range(nx):
		for iz in range(nz):
			var x0: float = bx + cell * float(ix)
			var x1: float = minf(x0 + cell, CX + hw)
			var z0: float = za + cell * float(iz)
			var z1: float = minf(z0 + cell, zb)
			var mx: float = (x0 + x1) * 0.5
			var mz: float = (z0 + z1) * 0.5
			var in_canal: bool = mx >= CX - hw
			var in_bay: bool = mz > PIT_Z0 and mz < PIT_Z1 and mx > bx
			if not (in_canal or in_bay):
				continue
			var q: Array = [Vector3(x0, UP_WATER_Y, z0), Vector3(x1, UP_WATER_Y, z0),
				Vector3(x1, UP_WATER_Y, z1), Vector3(x0, UP_WATER_Y, z1)]
			for v in [q[0], q[1], q[2], q[0], q[2], q[3]]:
				st.set_color(Color(0.0, 0.5, 0.5))   # bank=0：純深水，非岸邊泡沫
				st.set_uv(Vector2(v.x * 0.1, v.z * 0.1))
				st.add_vertex(v)
	st.generate_normals()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "CanalWater"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.set_meta("water_surface", true)
	root.add_child(mi)
	mi.owner = root


## r15 濱水步道：地形收坡移到牆外後，牆背會露出一段下凹。這條步道把它蓋住，
## 同時補上概念圖裡一直缺的「濱水步道」——親水節點本來就該由步道串起來。
func _build_walkway(root: Node3D) -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	# terrain_path 是強烈的橘土，在渠邊會比砌石還搶眼。改用石板，
	# 讓步道與護岸講同一種材料語言。
	mat.albedo_texture = load("res://assets/textures/cobble_diff.jpg")
	mat.normal_enabled = true
	mat.normal_texture = load("res://assets/textures/cobble_nor_gl.jpg")
	mat.roughness_texture = load("res://assets/textures/cobble_rough.jpg")
	# uv=世界座標，scale 1.0 = 每公尺一格。0.35 時每格約 3m，碎石大得像鵝卵石。
	mat.uv1_scale = Vector3(1.0, 1.0, 1.0)
	# terrain_path 本身偏暖橘，在正午陽光下會刺眼——壓暗並去飽和，
	# 讓步道退到護岸與水面之後，不要變成畫面最亮的東西。
	mat.albedo_color = Color(0.72, 0.72, 0.70)
	mat.roughness = 1.0
	# 岸面實測約 0.2~0.3（壓頂石頂 0.30）。0.05 會讓整條步道埋在土裡。
	# 與壓頂齊平才是碼頭該有的關係。
	var y: float = -0.50
	var outer: float = 9.0   # 必須蓋過地形收坡（TOP_HALF 6.5）外緣的裸土帶
	for side in [-1.0, 1.0]:
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		## ⚠ 繞線：兩側的 xa/xb 大小關係相反，若直接照 side 分支寫，
		## 其中一側法線會朝下被剔除（東岸步道 r15 就這樣整條消失）。
		## 一律排成升冪 x，用同一組三角形順序，法線保證 +Y。
		var xa: float = minf(CX + side * WALL_FACE, CX + side * outer)
		var xb: float = maxf(CX + side * WALL_FACE, CX + side * outer)
		var z: float = Z0 - 2.0
		var step: float = 2.0
		while z < Z1 + 2.0:
			var z1: float = minf(z + step, Z1 + 2.0)
			# 西岸在磨坊池範圍讓開（那裡是水，不是岸）
			var skip: bool = side < 0.0 and (z + z1) * 0.5 > PIT_Z0 - 0.5 				and (z + z1) * 0.5 < PIT_Z1 + 0.5
			if not skip:
				var q: Array = [Vector3(xa, y, z), Vector3(xb, y, z),
					Vector3(xb, y, z1), Vector3(xa, y, z1)]
				## 繞線對齊 _build_bed（渠床，已知從上方可見）的 [a,b,c,a,c,d]。
				## r15c 我把它反轉，兩側步道同時從畫面消失——正是規則裡
				## 「背面剔除」那條，而且我自己踩了一次。
				var tri: Array = [q[0], q[1], q[2], q[0], q[2], q[3]]
				for v in tri:
					st.set_uv(Vector2(v.x, v.z))
					st.add_vertex(v)
			z = z1
		st.generate_normals()
		st.generate_tangents()
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "濱水步道_W" if side < 0.0 else "濱水步道_E"
		mi.mesh = st.commit()
		mi.material_override = mat
		root.add_child(mi)
		mi.owner = root


## 磨坊池床：小屋立在池中柱基上，池床與主渠床同高（水面已由 _build_water 統一）。
func _build_bay(root: Node3D) -> void:
	var x0: float = CX - WALL_FACE - PIT_DEPTH
	var x1: float = CX - WALL_FACE
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y: float = BED_UP
	var q: Array = [Vector3(x0, y, PIT_Z0), Vector3(x1, y, PIT_Z0),
		Vector3(x1, y, PIT_Z1), Vector3(x0, y, PIT_Z1)]
	for v in [q[0], q[1], q[2], q[0], q[2], q[3]]:
		st.set_uv(Vector2(v.x * 0.5, v.z * 0.5))
		st.add_vertex(v)
	st.generate_normals()
	st.generate_tangents()
	var bmat: StandardMaterial3D = StandardMaterial3D.new()
	bmat.albedo_texture = load("res://assets/textures/cobble_diff.jpg")
	bmat.albedo_color = Color(0.42, 0.44, 0.44)
	bmat.roughness = 1.0
	var bed: MeshInstance3D = MeshInstance3D.new()
	bed.name = "BayBed"
	bed.mesh = st.commit()
	bed.material_override = bmat
	root.add_child(bed)
	bed.owner = root


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
