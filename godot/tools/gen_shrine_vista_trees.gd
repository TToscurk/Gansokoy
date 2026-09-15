extends SceneTree
## 神社遠景樹重建：把 700 個舊式三角葉 `tree_round_far.glb`（104 面、無貼圖）換成
## 本圖同款樹種的極簡版（vista_lod/*_far.glb，193–670 面、帶貼圖），並重新貼上
## **現在的** Vista 網格 —— 南出口走廊挖低後，舊的 700 個實例有 47 個浮空到 12.5 m。
##
##   Godot --headless --path godot --script tools/gen_shrine_vista_trees.gd [-- --dry]
##
## 產出：maps/shrine/gen/vista_trees_r2/<樹種>.res（每樹種一個 MultiMesh）
##       stdout: MCP 要建的節點清單
##
## ⚠ 舊檔 vista_trees.res 是「一個 MultiMesh 配一顆 mesh」，要換樹種就得拆成
##   多個 MultiMeshInstance3D（MultiMesh 只能有一顆 mesh）。
## ⚠ 舊檔的實例是用 `buffer` 灌的 —— get_instance_transform() 會回 identity，
##   必須直接讀 mm.buffer（每實例 12 float，列主序 3×4）才量得到位置。

const OUT_DIR := "res://maps/shrine/gen/vista_trees_r2/"
## 舊的 700 棵三角葉樹（構圖來源；節點已從 shrine.tscn 刪掉，檔案留著當基準）
const OLD_MM := "res://maps/shrine/gen/vista_trees.res"
## 現在的遠景地形（含南出口走廊下切）
const VISTA_MESH := "res://maps/shrine/gen/vista_exit.res"
## 首跑後把「最終水平分布」存這裡，之後換 LOD 資產重跑構圖不會漂
const POINTS := "res://maps/shrine/gen/vista_trees_r2/_points.json"
const SPECIES := [
	["針葉樹1", "res://assets/vista_lod/針葉樹1_far.glb"],
	["針葉林樹3", "res://assets/vista_lod/針葉林樹3_far.glb"],
	["針葉林樹4", "res://assets/vista_lod/針葉林樹4_far.glb"],
	["普通樹", "res://assets/vista_lod/普通樹_far.glb"],
]
## 境內半徑 75 m：這圈之內由實體樹負責，遠景樹不進來（會穿幫）。
const KEEP_OUT := 82.0
## 南出口走廊：缺口要看得見天光與下山的路，遠景樹不能塞住。
const GAP_HALF := 13.0
const GAP_Z0 := 55.0
const TALL := [5.5, 9.5]     # 遠景樹高 m


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var dry := "--dry" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	# ── 舊實例的水平分布照抄（那是調過的構圖），只重算高度與樹種 ──
	# ⚠ 直接讀磁碟上的資源，不載入 shrine.tscn：整張場景有 3 萬節點、
	#   headless 載入要好幾分鐘，而這支只需要兩個 .res。
	# ⚠ 舊檔的實例是用 `buffer` 灌的 → get_instance_transform() 回 identity，
	#   必須讀 mm.buffer（每實例 12 float，列主序 3×4，origin = [3],[7],[11]）。
	var pts: Array = []
	var pj := FileAccess.open(POINTS, FileAccess.READ)
	if pj != null:
		for e in (JSON.parse_string(pj.get_as_text()) as Array):
			pts.append(Vector3(e[0], e[1], e[2]))
		print("OLD source=%s count=%d" % [POINTS, pts.size()])
	else:
		var old: MultiMesh = load(OLD_MM)
		var buf: PackedFloat32Array = old.buffer
		for j in old.instance_count:
			var o := j * 12
			pts.append(Vector3(buf[o + 3], buf[o + 7], buf[o + 11]))
		print("OLD source=%s count=%d" % [OLD_MM, pts.size()])
	if pts.is_empty():
		push_error("找不到遠景樹來源")
		quit(1)
		return

	# ── 現在的 Vista 網格（含走廊下切）──
	var vmesh: ArrayMesh = load(VISTA_MESH)
	var vmi := MeshInstance3D.new()
	vmi.mesh = vmesh
	root.add_child(vmi)
	await process_frame
	var grid := _build_grid(vmi)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260915
	var per: Dictionary = {}
	for s in SPECIES:
		per[s[0]] = []
	var dropped_near := 0
	var dropped_gap := 0
	for p in pts:
		var d := Vector2(p.x, p.z).length()
		if d < KEEP_OUT:
			dropped_near += 1
			continue
		# 出口走廊軸線讓路
		if p.z > GAP_Z0 and absf(p.x) < GAP_HALF:
			dropped_gap += 1
			continue
		var gy := _sample(grid, p.x, p.z)
		if is_nan(gy):
			continue
		var sp: String = SPECIES[rng.randi_range(0, SPECIES.size() - 1)][0]
		per[sp].append([p.x, gy, p.z, rng.randf_range(TALL[0], TALL[1]), rng.randf() * TAU])
	# 走廊兩側補一排，讓缺口有「往下望進森林」的層次。
	# ⚠ 只在首跑（讀舊 700 棵）補；重跑讀 _points.json 時那批已在裡面，再補會翻倍。
	for i in (0 if pj != null else 34):
		var t := float(i) / 33.0
		var z: float = lerpf(95.0, 260.0, t)
		for side in [-1.0, 1.0]:
			var x: float = side * (GAP_HALF + 4.0 + rng.randf() * 22.0 + t * 34.0)
			var gy := _sample(grid, x, z)
			if is_nan(gy):
				continue
			var sp: String = SPECIES[rng.randi_range(0, SPECIES.size() - 1)][0]
			per[sp].append([x, gy, z, rng.randf_range(TALL[0], TALL[1]), rng.randf() * TAU])

	var total := 0
	var lines: Array = []
	for s in SPECIES:
		var nm: String = s[0]
		var rows: Array = per[nm]
		total += rows.size()
		if rows.is_empty():
			continue
		var ps: PackedScene = load(s[1])
		var src := _first_mesh(ps.instantiate())
		var box: AABB = src[1]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = src[0]
		mm.instance_count = rows.size()
		for i in rows.size():
			var r: Array = rows[i]
			var sc: float = float(r[3]) / maxf(box.size.y, 0.01)
			var b := Basis(Vector3.UP, float(r[4])).scaled(Vector3.ONE * sc)
			# 埋 0.2 m：遠景看不到根，寧可埋也不要浮
			mm.set_instance_transform(i, Transform3D(b,
				Vector3(float(r[0]), float(r[1]) - box.position.y * sc - 0.2, float(r[2]))))
		var path: String = OUT_DIR + nm + ".res"
		if not dry:
			var err := ResourceSaver.save(mm, path)
			print("SAVE %-10s %4d 棵 err=%d  %s" % [nm, rows.size(), err, path])
		lines.append({"name": "遠景樹_" + nm, "res": path, "count": rows.size()})
	print("NEW total=%d（原 %d；境內 %d m 內剔除 %d、出口走廊剔除 %d）"
		% [total, pts.size(), KEEP_OUT, dropped_near, dropped_gap])
	# 把最終水平分布存下來，下次換 LOD 資產重跑構圖不會漂
	if not dry:
		var keep: Array = []
		for s in SPECIES:
			for r in per[s[0]]:
				keep.append([r[0], r[1], r[2]])
		var f := FileAccess.open(POINTS, FileAccess.WRITE)
		f.store_string(JSON.stringify(keep))
		f.close()
		print("POINTS saved %d" % keep.size())
	print("MCP_NODES " + JSON.stringify(lines))
	quit(0)


func _first_mesh(inst: Node) -> Array:
	var st: Array = [inst]
	while not st.is_empty():
		var n: Node = st.pop_back()
		st.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			return [mi.mesh, mi.mesh.get_aabb()]
	return [null, AABB()]


func _build_grid(mi: MeshInstance3D) -> Dictionary:
	var tri: PackedVector3Array = mi.mesh.get_faces()
	var xf: Transform3D = mi.global_transform
	for i in tri.size():
		tri[i] = xf * tri[i]
	var b: AABB = xf * mi.mesh.get_aabb()
	var cell := 24.0
	var buckets: Dictionary = {}
	var i := 0
	while i < tri.size():
		var xmin := 1e9
		var xmax := -1e9
		var zmin := 1e9
		var zmax := -1e9
		for k in 3:
			var p: Vector3 = tri[i + k]
			xmin = minf(xmin, p.x); xmax = maxf(xmax, p.x)
			zmin = minf(zmin, p.z); zmax = maxf(zmax, p.z)
		for gx in range(int(floor((xmin - b.position.x) / cell)), int(floor((xmax - b.position.x) / cell)) + 1):
			for gz in range(int(floor((zmin - b.position.z) / cell)), int(floor((zmax - b.position.z) / cell)) + 1):
				var key := Vector2i(gx, gz)
				if not buckets.has(key):
					buckets[key] = PackedInt32Array()
				buckets[key].append(i)
		i += 3
	return {"tri": tri, "buckets": buckets, "aabb": b, "cell": cell}


func _sample(grid: Dictionary, x: float, z: float) -> float:
	var b: AABB = grid["aabb"]
	var cell: float = grid["cell"]
	var tri: PackedVector3Array = grid["tri"]
	var buckets: Dictionary = grid["buckets"]
	var gx := int(floor((x - b.position.x) / cell))
	var gz := int(floor((z - b.position.z) / cell))
	var best := NAN
	var bestd := 1e9
	for dx in [0, -1, 1]:
		for dz in [0, -1, 1]:
			var key := Vector2i(gx + dx, gz + dz)
			if not buckets.has(key):
				continue
			for idx in buckets[key]:
				var y := _bary_y(tri[idx], tri[idx + 1], tri[idx + 2], x, z)
				if not is_nan(y):
					return y
				for p in [tri[idx], tri[idx + 1], tri[idx + 2]]:
					var d: float = (p.x - x) * (p.x - x) + (p.z - z) * (p.z - z)
					if d < bestd:
						bestd = d
						best = p.y
	return best


func _bary_y(a: Vector3, b: Vector3, c: Vector3, x: float, z: float) -> float:
	var d := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
	if absf(d) < 1e-9:
		return NAN
	var w0: float = ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / d
	var w1: float = ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / d
	var w2: float = 1.0 - w0 - w1
	if w0 < -1e-4 or w1 < -1e-4 or w2 < -1e-4:
		return NAN
	return a.y * w0 + b.y * w1 + c.y * w2
