extends SceneTree
## B1/B3 市集街廓：主街密排町家 ＋ 裏路地背排 ＋ 中央広場（等 ART_REVIEW，未批准不進 village）
## 產出 res://maps/slice/gen/b1_street.tscn，於 slice.tscn 以單一節點實例。
## r4（2026-08-29）：
##  - 擺位改為「量實際 AABB 反推」，不再信任參數表。倉庫.glb 的 glTF 節點帶
##    translation[0,0.882,0]，大鳥居用 MATRIX——只量 mesh 座標會浮空。
##  - 街面改中央石板帶＋兩側夯土，邊緣以頂點 alpha 柔化並加不規則擾動。
## r5（2026-08-30，B3 街廓化）：概念圖的市集是「街廓」不是「一條街」。
##  - 前排改成可跳段（skip band），中段讓出中央広場。
##  - 新增東西兩條裏路地與背排（長屋／倉庫／市集商家），街廓有了進深。
##  - 中央広場：西側以背排商家圍合。r3 拔掉廣場與路地的石板鋪面——
##    概念圖的広場與裏路地是夯土，鋪面層讓它們變成亮黃色球場；
##    這兩處的地面交給 gen_terrain_river.gd 的裸土分區。
##    攤台一度用 assets/models/prop_*（店台／樽／笊／俵），但那批 GLB
##    materials=0、images=0，在引擎裡是純白塑膠塊——已移除。廣場的屋台
##    需要使用者的 Meshy 屋台組才能上。
##  - 前排南段補到接近鳥居，補掉 B1 z=66→92 的空洞。

const STREET_X: float = 235.0      # 街道中線 x
const Z0: float = -60.0            # 北端（-z 為北）
const Z1: float = 92.0             # 南端
const STREET_W: float = 8.0        # 路寬
const GAP: float = 1.5             # 基本棟距（使用者已認可）
const ROJI: float = 3.2            # 路地
const ROJI_EVERY: int = 3
const SINK: float = 0.15           # 沉降：主牆基入土
# 霧雨店地標槽位（使用者擺位：中心 z=-33.9）
const KIRISAME_Z0: float = -41.0
const KIRISAME_Z1: float = -26.3

# 前排實測最大進深 12.37（町家）→ 背牆線 x=231-12.37=218.63 / 239+12.37=251.37。
# 裏路地夾在背牆線與背排正面之間，寬約 4.1 m。
const WEST_FRONT_X: float = 231.0   # 西前排正面（朝 +x）
const EAST_FRONT_X: float = 239.0   # 東前排正面（朝 -x）
const WEST_BACK_X: float = 214.5    # 西背排正面（朝 +x，同時是廣場西緣）
const EAST_BACK_X: float = 255.5    # 東背排正面（朝 -x）
const WEST_ALLEY_X0: float = 214.5  # 西裏路地
const WEST_ALLEY_X1: float = 218.7
const EAST_ALLEY_X0: float = 251.3  # 東裏路地
const EAST_ALLEY_X1: float = 255.5

# 中央広場：開在主街西側，北南由前排收頭、西緣由背排商家圍合、東緣即主街。
const PLAZA_Z0: float = 6.0
const PLAZA_Z1: float = 44.0
const PLAZA_X0: float = 214.5
const PLAZA_X1: float = 231.0

# 只保留路徑與目標簷高比例；尺寸一律實測。
const TYPES: Dictionary = {
	"machiya":  {"path": "res://assets/machiya/町家.glb",   "scale": 6.5},
	"komachiya":{"path": "res://assets/machiya/小町家1.glb", "scale": 4.8},
	"oomachiya":{"path": "res://assets/machiya/大町家.glb",  "scale": 6.4},
	"shouka":   {"path": "res://assets/machiya/市集商家.glb", "scale": 5.2},
	"nagaya":   {"path": "res://assets/machiya/長屋.glb",   "scale": 6.3},
	"kura":     {"path": "res://assets/machiya/倉庫.glb",   "scale": 3.3},
}

# 前排（B1 已認可的組成，南段各補兩棟填掉鳥居前的空洞）
const ROW_WEST: Array = ["machiya", "komachiya", "machiya", "shouka", "machiya", "nagaya", "komachiya", "machiya", "oomachiya", "machiya", "komachiya", "kura"]
const ROW_EAST: Array = ["komachiya", "machiya", "shouka", "machiya", "nagaya", "machiya", "komachiya", "oomachiya", "machiya", "kura", "komachiya", "machiya"]
# 背排：街廓深處是倉庫與長屋；廣場西緣安排市集商家當店面。
const ROW_WEST_BACK: Array = ["kura", "nagaya", "komachiya", "kura", "nagaya", "shouka", "shouka", "komachiya", "kura", "nagaya", "komachiya"]
const ROW_EAST_BACK: Array = ["kura", "nagaya", "kura", "komachiya", "nagaya", "kura", "nagaya", "komachiya", "kura", "nagaya"]

# 橫向通路（讓廣場／主街能走進裏路地）
const CROSS_W: Array = [[3.0, 9.0], [44.0, 50.0]]
const CROSS_E: Array = [[-6.0, 0.0], [46.0, 52.0]]


func _init() -> void:
	var root: Node3D = Node3D.new()
	root.name = "B1_Street"
	# 前排：西排讓出中央広場，東排連續（當廣場對街的街牆）
	_build_row(root, ROW_WEST, true, WEST_FRONT_X, "西", Z0, Z1, [[PLAZA_Z0, PLAZA_Z1]])
	_build_row(root, ROW_EAST, false, EAST_FRONT_X, "東", Z0, Z1, [[KIRISAME_Z0, KIRISAME_Z1]])
	# 背排
	_build_row(root, ROW_WEST_BACK, true, WEST_BACK_X, "西裏", -50.0, 84.0, CROSS_W)
	_build_row(root, ROW_EAST_BACK, false, EAST_BACK_X, "東裏", -40.0, 74.0, CROSS_E)
	_build_torii(root)
	_build_paving(root)
	var ps: PackedScene = PackedScene.new()
	var err: int = ps.pack(root)
	if err != OK:
		push_error("pack failed: %d" % err)
	else:
		err = ResourceSaver.save(ps, "res://maps/slice/gen/b1_street.tscn")
		print("SAVE_RESULT %d" % err)
	quit()


## 回傳 inst 局部空間的實際 AABB（含所有子節點變換）。
func _local_bbox(root_node: Node3D) -> AABB:
	var acc: AABB = AABB()
	var has: bool = false
	var stack: Array = []
	for c in root_node.get_children():
		stack.push_back([c, Transform3D.IDENTITY])
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


## faces_east=true：正面朝 +x（街西側各排）。skips 為 [[z0,z1], ...] 的讓位帶。
func _build_row(root: Node3D, row: Array, faces_east: bool, front_x: float,
		side: String, z_start: float, z_end: float, skips: Array) -> void:
	# 模型正面 +z。朝東 rot_y=+90（局部 +z → 世界 +x）；朝西 rot_y=-90。
	var rot_y: float = 90.0 if faces_east else -90.0
	var cursor: float = z_start
	var i: int = 0
	for key in row:
		var t: Dictionary = TYPES[key]
		var s: float = t["scale"]
		var scn: PackedScene = load(t["path"])
		if scn == null:
			push_error("load failed: " + str(t["path"]))
			continue
		var inst: Node3D = scn.instantiate() as Node3D
		var bb: AABB = _local_bbox(inst)
		var c: Vector3 = bb.position + bb.size * 0.5   # 局部中心
		var fw: float = bb.size.x * s                  # 沿街寬（局部 x）
		# 跨過所有讓位帶（廣場／地標槽位／橫向通路）
		for band in skips:
			if cursor < band[1] and cursor + fw > band[0]:
				cursor = band[1] + GAP
		if cursor + fw > z_end:
			inst.free()
			break
		inst.name = "%s_%s_%02d" % [key, side, i]
		inst.rotation_degrees = Vector3(0.0, rot_y, 0.0)
		inst.scale = Vector3(s, s, s)
		# 正面（局部 +z 最大面）對齊 front_x
		var front_local: float = (c.z + bb.size.z * 0.5) * s
		var px: float = front_x - front_local if faces_east else front_x + front_local
		# 沿街跨距落在 [cursor, cursor+fw]
		var pz: float = cursor + fw * 0.5 + (c.x * s if faces_east else -c.x * s)
		# 底面落在 -SINK
		var py: float = -SINK - (c.y - bb.size.y * 0.5) * s
		inst.position = Vector3(px, py, pz)
		root.add_child(inst)
		inst.owner = root
		i += 1
		cursor += fw + GAP
		if i % ROJI_EVERY == 0:
			cursor += ROJI


func _build_torii(root: Node3D) -> void:
	var scn: PackedScene = load("res://assets/landmark/大鳥居.glb")
	if scn == null:
		push_error("torii load failed")
		return
	var t: Node3D = scn.instantiate() as Node3D
	t.name = "大鳥居"
	var bb: AABB = _local_bbox(t)
	var c: Vector3 = bb.position + bb.size * 0.5
	var s: float = 12.0 / maxf(bb.size.x, 0.001)   # 目標寬 12m
	t.scale = Vector3(s, s, s)
	t.position = Vector3(
		STREET_X - c.x * s,
		-0.1 - (c.y - bb.size.y * 0.5) * s,
		Z1 + 9.0 - c.z * s)
	root.add_child(t)
	t.owner = root


## 確定性偽雜訊（無 RNG，多頻正弦疊加），值域約 [-1, 1]
func _n2(x: float, z: float) -> float:
	return (sin(x * 0.37 + z * 0.21) * 0.5
		+ sin(x * 0.91 - z * 0.63 + 2.1) * 0.3
		+ sin(x * 2.30 + z * 1.70 - 1.3) * 0.2)


func _build_paving(root: Node3D) -> void:
	## 中央石板帶 → 兩側夯土。r5：縮窄石板、加磨損斑駁與黃土色調變化。
	##  - alpha 由「距街心的漸退」與「斑駁雜訊」相乘，石板會有露土的破口
	##  - 頂點色在冷灰石與暖黃土之間變化，避免整片死板同色
	const HALF_FULL: float = 1.8      # 全實心石板半寬（使用者反映石板偏多）
	const HALF_EDGE: float = 5.2      # 完全消失處半寬
	const SEGS_Z: int = 300
	const SEGS_X: int = 34
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z_len: float = (Z1 - Z0) + 26.0
	var z_start: float = Z0 - 13.0
	for iz in range(SEGS_Z):
		var z0: float = z_start + z_len * float(iz) / float(SEGS_Z)
		var z1: float = z_start + z_len * float(iz + 1) / float(SEGS_Z)
		for ix in range(SEGS_X):
			var u0: float = float(ix) / float(SEGS_X) * 2.0 - 1.0
			var u1: float = float(ix + 1) / float(SEGS_X) * 2.0 - 1.0
			var quad: Array = [[u0, z0], [u1, z0], [u1, z1], [u0, z1]]
			for k in [0, 1, 2, 0, 2, 3]:
				var uv: Array = quad[k]
				var x: float = uv[0] * HALF_EDGE
				var z: float = uv[1]
				# 邊界蜿蜒
				var wob: float = sin(z * 0.13) * 0.5 + sin(z * 0.041 + 1.7) * 0.8
				var d: float = absf(x)
				var band: float = 1.0 - smoothstep(HALF_FULL + wob, HALF_EDGE + wob * 0.6, d)
				# 磨損斑駁：低頻大破口 + 高頻細碎
				var wear: float = _n2(x * 0.9, z * 0.9)
				var patch: float = smoothstep(-0.55, 0.15, wear)
				var a: float = clampf(band * (0.35 + 0.65 * patch), 0.0, 1.0)
				# 色調：冷灰石 ↔ 暖黃土，隨雜訊變化
				var warm: float = clampf(0.5 + 0.5 * _n2(x * 0.45 + 40.0, z * 0.45), 0.0, 1.0)
				var col: Color = Color(0.55, 0.53, 0.50).lerp(Color(0.78, 0.66, 0.42), warm)
				st.set_color(Color(col.r, col.g, col.b, a))
				st.set_uv(Vector2(x * 0.14, z * 0.14))
				st.add_vertex(Vector3(STREET_X + x, 0.02, z))
	st.generate_normals()
	st.generate_tangents()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "StreetPaving"
	mi.mesh = st.commit()
	mi.material_override = load("res://assets/materials/street_paving.tres")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.0
	root.add_child(mi)
	mi.owner = root
