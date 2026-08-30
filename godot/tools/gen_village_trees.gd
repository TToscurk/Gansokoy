extends SceneTree
## 村緣樹群（B3 r5）。使用者提供的 Meshy 景觀資產，全部 OPAQUE 實體葉團，
## 沒有薄 alpha 卡——gl_compatibility 下不會碎成白點。
## 產出 res://maps/slice/gen/village_trees.tscn，於 slice.tscn 以單一節點實例。
##
## 規則：
##  - 每種樹烘成單一 ArrayMesh（底面 y=0、xz 置中）存成 gen/tree_*.res，
##    再以 MultiMesh 佈點；不逐棵 instance PackedScene（250 棵會是 2.8M 面）。
##  - 每個樹種一條獨立 RNG（per-layer RNG isolation），改動一種不會位移其他種。
##  - 禁區：街廓本體、地標淨空、河道走廊，以及**鳥居往南的借景走廊**——
##    主街南望遠峰是已成立的構圖，種樹擋掉就毀了。

const OUT_SCENE := "res://maps/slice/gen/village_trees.tscn"
const SRC := "res://assets/landscape/"

# 樹種：檔名、目標實高(m)、目標株數、最小間距(m)、隨機縮放範圍。
# 順序即優先權——共用間距集合會被先跑的樹種佔位，所以櫻花與雜木排最前面
# （概念圖裡櫻花就在村緣，排最後只搶得到 3 個位置）。
const SPECIES: Array = [
	{"file": "櫻花樹.glb",      "h": 8.0,  "n": 18, "gap": 12.0, "sv": 0.18, "seed": 4109},
	{"file": "普通樹.glb",      "h": 9.5,  "n": 38, "gap": 10.0, "sv": 0.22, "seed": 4108},
	{"file": "大衫.glb",        "h": 17.0, "n": 34, "gap": 15.0, "sv": 0.16, "seed": 4101},
	{"file": "2大衫.glb",       "h": 19.5, "n": 22, "gap": 18.0, "sv": 0.14, "seed": 4102},
	{"file": "針葉樹1.glb",     "h": 12.5, "n": 30, "gap": 12.0, "sv": 0.18, "seed": 4103},
	{"file": "針葉樹2glb.glb",  "h": 13.5, "n": 28, "gap": 12.0, "sv": 0.18, "seed": 4104},
	{"file": "針葉林樹3.glb",   "h": 14.5, "n": 26, "gap": 13.0, "sv": 0.16, "seed": 4105},
	{"file": "針葉林樹4.glb",   "h": 15.5, "n": 24, "gap": 13.0, "sv": 0.16, "seed": 4106},
	{"file": "松樹.glb",        "h": 10.5, "n": 26, "gap": 11.0, "sv": 0.20, "seed": 4107},
]
# 盆樹走另一條規則：只沿裏路地外緣點綴
const BONSAI := {"file": "盆樹.glb", "h": 2.6, "n": 22, "sv": 0.22, "seed": 4110}

# 佈點範圍
const X_MIN := 118.0
const X_MAX := 306.0
const Z_MIN := -226.0
const Z_MAX := 236.0

# 禁區
const BLOCK := Rect2(200.0, -72.0, 70.0, 184.0)        # 街廓本體（x,z,w,h）
const SIGHT := Rect2(213.0, 94.0, 44.0, 172.0)         # 鳥居往南的借景走廊
const LANDMARKS: Array = [
	Vector3(233.2, -138.6, 52.0),   # 稗田邸
	Vector3(314.8, 34.6, 34.0),     # 寺子屋
	Vector3(225.2, -65.5, 30.0),    # 鈴奈庵
]

var _placed: Array = []   # 已放置點，跨樹種共用以維持間距


func _init() -> void:
	var root: Node3D = Node3D.new()
	root.name = "VillageTrees"
	for sp in SPECIES:
		_build_species(root, sp)
	_build_bonsai(root)
	var ps: PackedScene = PackedScene.new()
	var err: int = ps.pack(root)
	if err != OK:
		push_error("pack failed: %d" % err)
	else:
		err = ResourceSaver.save(ps, OUT_SCENE)
		print("SAVE_RESULT %d" % err)
	quit()


## 把 GLB 全部表面烘成一個 ArrayMesh：縮到目標高度、底面落 y=0、xz 置中。
func _bake(file: String, target_h: float) -> ArrayMesh:
	var scn: PackedScene = load(SRC + file)
	if scn == null:
		push_error("load failed: " + file)
		return null
	var inst: Node3D = scn.instantiate() as Node3D
	# 先量原始 AABB
	var bb: AABB = AABB()
	var has: bool = false
	var stack: Array = []
	for c in inst.get_children():
		stack.push_back([c, Transform3D.IDENTITY])
	var parts: Array = []
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var nd: Node = pair[0]
		var xf: Transform3D = pair[1]
		if nd is Node3D:
			xf = xf * (nd as Node3D).transform
		if nd is MeshInstance3D and (nd as MeshInstance3D).mesh != null:
			var mi: MeshInstance3D = nd
			parts.append([mi, xf])
			var a: AABB = xf * mi.mesh.get_aabb()
			if has:
				bb = bb.merge(a)
			else:
				bb = a
				has = true
		for c2 in nd.get_children():
			stack.push_back([c2, xf])
	if not has:
		push_error("no mesh in " + file)
		inst.free()
		return null

	var s: float = target_h / maxf(bb.size.y, 0.0001)
	var centre: Vector3 = bb.position + bb.size * 0.5
	var offset := Vector3(-centre.x * s, -bb.position.y * s, -centre.z * s)
	var to_world := Transform3D(Basis.IDENTITY, offset) \
		* Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)), Vector3.ZERO)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat: Material = null
	for p in parts:
		var mi2: MeshInstance3D = p[0]
		var xf2: Transform3D = to_world * (p[1] as Transform3D)
		for si in range(mi2.mesh.get_surface_count()):
			st.append_from(mi2.mesh, si, xf2)
			if mat == null:
				mat = mi2.mesh.surface_get_material(si)
				if mat == null:
					mat = mi2.get_active_material(si)
	var baked: ArrayMesh = st.commit()
	if mat != null:
		baked.surface_set_material(0, mat)
	var out_path: String = "res://maps/slice/gen/tree_%s.res" % file.get_basename()
	ResourceSaver.save(baked, out_path, ResourceSaver.FLAG_COMPRESS)
	inst.free()
	# 存完再 load 回來：這樣資源帶著 resource_path，打包時是 ExtResource 參照，
	# 網格不會被塞進 .tscn 文字（原本讓場景檔膨脹到 7.2 MB）。
	baked = load(out_path)
	print("BAKE %-12s h=%.1f tris=%d surfaces=%d" % [
		file, target_h, baked.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3,
		baked.get_surface_count()])
	return baked


## 佈點密度：離街廓愈遠愈稀，西／北側較密（概念圖的林緣在那一側）。
func _density(x: float, z: float) -> float:
	var dx: float = maxf(absf(x - 235.0) - 36.0, 0.0)
	var dz: float = maxf(absf(z - 20.0) - 92.0, 0.0)
	var d: float = sqrt(dx * dx + dz * dz)
	var near: float = 1.0 - smoothstep(6.0, 165.0, d)     # 靠街廓最密
	var west: float = 1.0 - smoothstep(150.0, 236.0, x)   # 西側林緣
	return clampf(maxf(near * 0.85, west * 0.55), 0.0, 1.0)


func _blocked(x: float, z: float) -> bool:
	if BLOCK.has_point(Vector2(x, z)):
		return true
	if SIGHT.has_point(Vector2(x, z)):
		return true
	for lm in LANDMARKS:
		if Vector2(x - lm.x, z - lm.y).length() < lm.z:
			return true
	return false


func _too_close(x: float, z: float, gap: float) -> bool:
	for p in _placed:
		var pv: Vector2 = p[0]
		var need: float = maxf(gap, p[1])
		if Vector2(x - pv.x, z - pv.y).length() < need:
			return true
	return false


func _build_species(root: Node3D, sp: Dictionary) -> void:
	var mesh: ArrayMesh = _bake(sp["file"], sp["h"])
	if mesh == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = sp["seed"]
	var xforms: Array = []
	var tries: int = 0
	while xforms.size() < int(sp["n"]) and tries < 20000:
		tries += 1
		var x: float = rng.randf_range(X_MIN, X_MAX)
		var z: float = rng.randf_range(Z_MIN, Z_MAX)
		if _blocked(x, z):
			continue
		if rng.randf() > _density(x, z):
			continue
		if _too_close(x, z, sp["gap"]):
			continue
		_placed.append([Vector2(x, z), float(sp["gap"])])
		var sc: float = 1.0 + rng.randf_range(-float(sp["sv"]), float(sp["sv"]))
		var b := Basis.IDENTITY.rotated(Vector3.UP, rng.randf_range(0.0, TAU))
		b = b.scaled(Vector3(sc, sc, sc))
		xforms.append(Transform3D(b, Vector3(x, -0.08, z)))
	_emit(root, sp["file"].get_basename(), mesh, xforms)
	print("PLACE %-12s %d/%d (tries=%d)" % [sp["file"], xforms.size(), sp["n"], tries])


## 盆樹：只點綴在裏路地外緣，不進佈點主流程。
func _build_bonsai(root: Node3D) -> void:
	var mesh: ArrayMesh = _bake(BONSAI["file"], BONSAI["h"])
	if mesh == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = BONSAI["seed"]
	var xforms: Array = []
	var lanes: Array = [213.4, 256.6]   # 兩條裏路地的外緣
	for i in range(int(BONSAI["n"])):
		var lane: float = lanes[i % lanes.size()]
		var z: float = -46.0 + float(i) * 11.4 + rng.randf_range(-2.0, 2.0)
		if z > 78.0:
			continue
		var x: float = lane + rng.randf_range(-0.7, 0.7)
		var sc: float = 1.0 + rng.randf_range(-float(BONSAI["sv"]), float(BONSAI["sv"]))
		var b := Basis.IDENTITY.rotated(Vector3.UP, rng.randf_range(0.0, TAU))
		b = b.scaled(Vector3(sc, sc, sc))
		xforms.append(Transform3D(b, Vector3(x, -0.05, z)))
	_emit(root, "盆樹", mesh, xforms)
	print("PLACE 盆樹         %d" % xforms.size())


func _emit(root: Node3D, name_: String, mesh: ArrayMesh, xforms: Array) -> void:
	if xforms.is_empty():
		return
	# headless 跑的是 dummy renderer，set_instance_transform() 寫不進去
	# （回讀全是原點，242 棵樹整疊在 0,0,0）。直接組 buffer——
	# clear_street_vegetation.gd 早就是這樣讀寫的，stride 12 = 3x4 矩陣列優先。
	var buf := PackedFloat32Array()
	buf.resize(xforms.size() * 12)
	for i in range(xforms.size()):
		var t: Transform3D = xforms[i]
		var o: int = i * 12
		buf[o + 0] = t.basis.x.x; buf[o + 1] = t.basis.y.x
		buf[o + 2] = t.basis.z.x; buf[o + 3] = t.origin.x
		buf[o + 4] = t.basis.x.y; buf[o + 5] = t.basis.y.y
		buf[o + 6] = t.basis.z.y; buf[o + 7] = t.origin.y
		buf[o + 8] = t.basis.x.z; buf[o + 9] = t.basis.y.z
		buf[o + 10] = t.basis.z.z; buf[o + 11] = t.origin.z
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	mm.buffer = buf
	# MultiMesh 的 buffer 不會序列化進 .tscn 文字（本專案已知，veg_mm_*.res
	# 外置就是同一個原因）——第一版把 mm 直接掛上去，存出來只有
	# transform_format/instance_count/mesh，231 棵樹全部塌在原點。
	# 必須存成 .res 再 load 回來，讓它以外部資源被參照。
	var mm_path: String = "res://maps/slice/gen/treemm_%s.res" % name_
	ResourceSaver.save(mm, mm_path, ResourceSaver.FLAG_COMPRESS)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Trees_%s" % name_
	mmi.multimesh = load(mm_path)
	root.add_child(mmi)
	mmi.owner = root
