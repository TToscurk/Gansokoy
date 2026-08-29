extends SceneTree
## B1 密度原型：主街密排町家（等 ART_REVIEW，未批准不進 village）
## 產出 res://maps/slice/gen/b1_street.tscn，於 slice.tscn 以單一節點實例。
## r4（2026-08-29）：
##  - 擺位改為「量實際 AABB 反推」，不再信任參數表。倉庫.glb 的 glTF 節點帶
##    translation[0,0.882,0]，大鳥居用 MATRIX——只量 mesh 座標會浮空。
##  - 街面改中央石板帶＋兩側夯土，邊緣以頂點 alpha 柔化並加不規則擾動。

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

# 只保留路徑與目標簷高比例；尺寸一律實測。
const TYPES: Dictionary = {
	"machiya":  {"path": "res://assets/machiya/町家.glb",   "scale": 6.5},
	"komachiya":{"path": "res://assets/machiya/小町家1.glb", "scale": 4.8},
	"oomachiya":{"path": "res://assets/machiya/大町家.glb",  "scale": 6.4},
	"shouka":   {"path": "res://assets/machiya/市集商家.glb", "scale": 5.2},
	"nagaya":   {"path": "res://assets/machiya/長屋.glb",   "scale": 6.3},
	"kura":     {"path": "res://assets/machiya/倉庫.glb",   "scale": 3.3},
}

const ROW_WEST: Array = ["machiya", "komachiya", "machiya", "shouka", "machiya", "nagaya", "komachiya", "machiya", "oomachiya", "machiya", "komachiya", "kura"]
const ROW_EAST: Array = ["komachiya", "machiya", "shouka", "machiya", "nagaya", "machiya", "komachiya", "oomachiya", "machiya", "kura"]

func _init() -> void:
	var root: Node3D = Node3D.new()
	root.name = "B1_Street"
	_build_row(root, ROW_WEST, true)
	_build_row(root, ROW_EAST, false)
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


func _build_row(root: Node3D, row: Array, is_west: bool) -> void:
	var side: String = "西" if is_west else "東"
	var front_x: float = STREET_X - STREET_W * 0.5 if is_west else STREET_X + STREET_W * 0.5
	# 模型正面 +z。西排 rot_y=+90（局部 +z → 世界 +x）；東排 rot_y=-90（局部 +z → 世界 -x）。
	var rot_y: float = 90.0 if is_west else -90.0
	var cursor: float = Z0
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
		var fd: float = bb.size.z * s                  # 進深（局部 z）
		# 東排避開霧雨店槽位
		if not is_west and cursor < KIRISAME_Z1 and cursor + fw > KIRISAME_Z0:
			cursor = KIRISAME_Z1 + GAP
		if cursor + fw > Z1:
			inst.free()
			break
		inst.name = "%s_%s_%02d" % [key, side, i]
		inst.rotation_degrees = Vector3(0.0, rot_y, 0.0)
		inst.scale = Vector3(s, s, s)
		# 正面（局部 +z 最大面）對齊 front_x
		var front_local: float = (c.z + bb.size.z * 0.5) * s
		var px: float = front_x - front_local if is_west else front_x + front_local
		# 沿街跨距落在 [cursor, cursor+fw]
		var pz: float = cursor + fw * 0.5 + (c.x * s if is_west else -c.x * s)
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
	root.add_child(mi)
	mi.owner = root
