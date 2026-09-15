extends SceneTree
## 神社境內樹木落地：量整棵樹（全部 mesh 合併）世界 AABB 底邊，
## 對地形做重心內插取樣，調整節點 y 使樹底埋入地面 SINK 公尺，回寫 shrine.tscn。
##   Godot --headless --path godot --script tools/fix_shrine_tree_ground.gd -- [--dry]

const SCENE := "res://maps/shrine/shrine.tscn"
const TREES := ["大衫", "2大衫", "普通樹", "針葉樹1", "針葉樹2glb", "針葉林樹3", "針葉林樹4"]
const SINK := 0.15  ## 樹底埋入地面的深度（m），避免縫隙露出


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var dry := "--dry" in OS.get_cmdline_user_args()
	var ps := load(SCENE) as PackedScene
	var rootn := ps.instantiate() as Node3D
	root.add_child(rootn)
	await process_frame

	var terr: MeshInstance3D = _find_terrain(rootn)
	if terr == null:
		print("找不到地形")
		quit(1)
		return
	var grid := _build_grid(terr)
	print("地形 %s 三角 %d  格 %dx%d  cell %.3f m"
		% [terr.get_path(), grid["tri"].size() / 3, grid["nx"], grid["nz"], grid["cell"]])
	# 地形只有 150x150 m，外圍森林站在遠景地形 Vista 上，需要第二層取樣。
	var vista_node := rootn.get_node_or_null("Vista") as MeshInstance3D
	var vgrid: Dictionary = {}
	if vista_node != null:
		vgrid = _build_grid(vista_node)
		print("遠景 Vista 三角 %d  AABB %s size %s"
			% [vgrid["tri"].size() / 3, vgrid["aabb"].position, vgrid["aabb"].size])

	var moved := 0
	var total := 0
	var worst := 0.0
	var sum_abs := 0.0
	var outside_n := 0
	var stats: Dictionary = {}
	for n in _walk(rootn):
		var species := _species(String(n.name))
		if species == "":
			continue
		var node3 := n as Node3D
		if node3 == null:
			continue
		var box := _merged_aabb(node3)
		if box.size == Vector3.ZERO:
			continue
		var cx: float = box.position.x + box.size.x * 0.5
		var cz: float = box.position.z + box.size.z * 0.5
		var ab: AABB = grid["aabb"]
		var inside: bool = (cx > ab.position.x and cx < ab.position.x + ab.size.x
			and cz > ab.position.z and cz < ab.position.z + ab.size.z)
		var gy := NAN
		if inside:
			gy = _sample(grid, cx, cz)
		elif not vgrid.is_empty():
			outside_n += 1
			gy = _sample(vgrid, cx, cz)
		if is_nan(gy):
			continue
		total += 1
		var drift: float = box.position.y - (gy - SINK)
		sum_abs += absf(drift)
		if absf(drift) > absf(worst):
			worst = drift
		if not stats.has(species):
			stats[species] = [0, 0.0]
		stats[species][0] += 1
		stats[species][1] = maxf(stats[species][1], absf(drift))
		if absf(drift) > 0.02:
			moved += 1
			if not dry:
				node3.global_position -= Vector3(0.0, drift, 0.0)

	for k in stats:
		var s: Array = stats[k]
		print("%-10s %4d 棵  修正前最大偏移 %.3f m" % [k, s[0], s[1]])
	print("TREES total=%d need_fix=%d outside_terrain=%d worst=%+.3f m mean_abs=%.3f m"
		% [total, moved, outside_n, worst, sum_abs / maxf(1.0, float(total))])

	if dry:
		print("DRY RUN — 未寫檔")
		quit()
		return

	var out := PackedScene.new()
	_reown(rootn, rootn)
	var err := out.pack(rootn)
	if err != OK:
		print("pack 失敗 %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(out, SCENE)
	print("SAVE %s err=%d" % [SCENE, err])
	quit(0 if err == OK else 1)


func _species(nm: String) -> String:
	# 先比長名（2大衫 / 針葉樹2glb），避免前綴誤判。
	var best := ""
	for t in TREES:
		if nm.begins_with(t) and t.length() > best.length():
			best = t
	if best == "":
		return ""
	# 分類容器（名稱恰為樹種名，如 植被/外圍森林/大衫）不是樹，跳過，
	# 否則會把整群一起位移。
	var rest: String = nm.substr(best.length())
	if not rest.begins_with("_"):
		return ""
	return best


func _merged_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in _walk(n):
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


## 地形是規則 XZ 網格 → 建 bucket 加速，並在三角內做重心內插。
func _build_grid(terr: MeshInstance3D) -> Dictionary:
	var tri: PackedVector3Array = terr.mesh.get_faces()
	var xf: Transform3D = terr.global_transform
	for i in tri.size():
		tri[i] = xf * tri[i]
	var b: AABB = terr.global_transform * terr.mesh.get_aabb()
	var n := int(round(sqrt(float(tri.size() / 3) / 2.0)))
	n = maxi(n, 1)
	var cell: float = b.size.x / float(n)
	var buckets: Dictionary = {}
	var i := 0
	while i < tri.size():
		var cxmin := 1e9
		var cxmax := -1e9
		var czmin := 1e9
		var czmax := -1e9
		for k in 3:
			var p: Vector3 = tri[i + k]
			cxmin = minf(cxmin, p.x)
			cxmax = maxf(cxmax, p.x)
			czmin = minf(czmin, p.z)
			czmax = maxf(czmax, p.z)
		var gx0 := int(floor((cxmin - b.position.x) / cell))
		var gx1 := int(floor((cxmax - b.position.x) / cell))
		var gz0 := int(floor((czmin - b.position.z) / cell))
		var gz1 := int(floor((czmax - b.position.z) / cell))
		for gx in range(gx0, gx1 + 1):
			for gz in range(gz0, gz1 + 1):
				var key := Vector2i(gx, gz)
				if not buckets.has(key):
					buckets[key] = PackedInt32Array()
				buckets[key].append(i)
		i += 3
	return {"tri": tri, "buckets": buckets, "aabb": b, "cell": cell, "nx": n, "nz": n}


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
				var a: Vector3 = tri[idx]
				var bb: Vector3 = tri[idx + 1]
				var c: Vector3 = tri[idx + 2]
				var y := _bary_y(a, bb, c, x, z)
				if not is_nan(y):
					return y
				# 落在三角外 → 記錄最近頂點當退路
				for p in [a, bb, c]:
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


func _find_terrain(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (String(n.name).findn("terrain") >= 0 or String(n.name).find("地形") >= 0):
		return n
	for c in n.get_children():
		var r := _find_terrain(c)
		if r != null:
			return r
	return null


func _reown(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		if c.owner != null:
			c.owner = owner_node
		if c.get_child_count() > 0 and c.scene_file_path == "":
			_reown(c, owner_node)


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
