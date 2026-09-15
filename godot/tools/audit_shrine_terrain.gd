extends SceneTree
## 博麗神社 收邊／地形體檢（唯讀，不改任何檔）。
##
##   Godot --headless --path godot --script tools/audit_shrine_terrain.gd
##
## 量四件事，全部以**磁碟上的 shrine.tscn 實際網格**為準，不用產生器公式：
##   1. 地形網格坡度：>35° 的格數與位置（梯田／斷崖）
##   2. 地形 ↔ 遠景（Vista）接縫：地圖四邊每 2 m 取樣兩張網格的高差
##   3. 邊界牆：牆底是否高過地形（可鑽）、牆頂是否低於地形（可翻）
##   4. 物件落地：每個 MeshInstance3D 的世界 AABB 底 vs 該點地形高
##      （浮空 > 0.25 m、陷入 > 0.6 m 各列出）
## stdout 以 [AUD] 開頭，最後印 JSON 摘要。

const SCENE := "res://maps/shrine/shrine.tscn"
const HALF := 75.0
const SLOPE_LIMIT := 35.0
const FLOAT_LIM := 0.25
const SINK_LIM := 0.60
const SKIP_TOP := ["Vista", "遠景地標", "天象系統", "神社環境", "標記", "神社互動點"]

var _grid: PackedVector3Array
var _res := 0
var _step := 0.0
var _vista_mesh: ArrayMesh
var _vista_xf: Transform3D


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var scn: Node3D = load(SCENE).instantiate()
	root.add_child(scn)
	await process_frame
	var terrain: MeshInstance3D = scn.get_node("Terrain")
	_load_grid(terrain)
	var vista: MeshInstance3D = scn.get_node("Vista")
	_vista_mesh = vista.mesh
	_vista_xf = vista.global_transform
	var summary := {}
	summary["slope"] = _audit_slope()
	summary["seam"] = _audit_seam()
	summary["boundary"] = _audit_boundary(scn)
	summary["ground"] = _audit_grounding(scn)
	# 中軸剖面：石階腳（z −1 ~ +6）地形 vs 最低階頂面 0.0
	var prof := ""
	var zz := -2.0
	while zz <= 6.0:
		prof += "%+.1f:%.2f " % [zz, h_at(0.0, zz)]
		zz += 0.5
	print("[AUD] 中軸 x=0 地形剖面（石階最低階頂面 y=0.00、南收頭石頂 0.02 @ z=0.2）: " + prof)
	print("[AUD] SUMMARY " + JSON.stringify(summary))
	quit(0)


func _load_grid(mi: MeshInstance3D) -> void:
	var a: Array = mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	_res = int(round(sqrt(float(v.size()))))
	assert(_res * _res == v.size(), "terrain not a square grid")
	_step = 2.0 * HALF / float(_res - 1)
	var xf := mi.global_transform
	# ⚠ SurfaceTool.generate_normals() 會 deindex→index，頂點順序變成三角形
	#   串流首次出現順序，不再是 row-major。一律依座標重排。
	_grid.resize(v.size())
	for i in v.size():
		var p := xf * v[i]
		var gi := int(round((p.x + HALF) / _step))
		var gj := int(round((p.z + HALF) / _step))
		_grid[gj * _res + gi] = p
	print("[AUD] terrain grid %d×%d step %.3f m  mesh=%s" % [_res, _res, _step, mi.mesh.resource_path])


func h_at(x: float, z: float) -> float:
	var fx := (x + HALF) / _step
	var fz := (z + HALF) / _step
	var i := clampi(int(floor(fx)), 0, _res - 2)
	var j := clampi(int(floor(fz)), 0, _res - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - j, 0.0, 1.0)
	var a := _grid[j * _res + i].y
	var b := _grid[j * _res + i + 1].y
	var c := _grid[(j + 1) * _res + i].y
	var d := _grid[(j + 1) * _res + i + 1].y
	# 與 gen_lib.terrain 的三角剖分一致：(a, b, c) / (b, d, c)
	if tx + tz <= 1.0:
		return a + (b - a) * tx + (c - a) * tz
	return d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)


# ── 1. 坡度 ──
func _audit_slope() -> Dictionary:
	var bad := 0
	var n := 0
	var worst := 0.0
	var worst_p := Vector2.ZERO
	var buckets := {}
	for j in _res - 1:
		for i in _res - 1:
			var a := _grid[j * _res + i]
			var b := _grid[j * _res + i + 1]
			var c := _grid[(j + 1) * _res + i]
			var nrm := (b - a).cross(c - a).normalized()
			var deg := rad_to_deg(acos(clampf(absf(nrm.y), 0.0, 1.0)))
			n += 1
			if deg > worst:
				worst = deg
				worst_p = Vector2(a.x, a.z)
			if deg > SLOPE_LIMIT:
				bad += 1
				var key := "%d,%d" % [int(floor(a.x / 15.0)) * 15, int(floor(a.z / 15.0)) * 15]
				buckets[key] = buckets.get(key, 0) + 1
	print("[AUD] 坡度 >%.0f°：%d/%d 格（%.1f%%），最陡 %.1f° @ (%.1f, %.1f)"
		% [SLOPE_LIMIT, bad, n, 100.0 * bad / n, worst, worst_p.x, worst_p.y])
	var keys := buckets.keys()
	keys.sort_custom(func(p, q): return buckets[p] > buckets[q])
	for k in keys.slice(0, 8):
		print("[AUD]   15 m 格 (%s) 陡格 %d" % [k, buckets[k]])
	return {"bad": bad, "total": n, "worst_deg": snappedf(worst, 0.1), "worst_at": [worst_p.x, worst_p.y]}


# ── 2. 地形 ↔ Vista 接縫 ──
## 用**實際三角形**取樣（bucket 18 m），不假設頂點在規則格上——r2 把 72 圈頂點
## 搬到 ±75，格子內插會算錯。
var _vtris: PackedVector3Array
var _vbuckets := {}

func _vista_prep() -> void:
	if _vtris.size() > 0:
		return
	_vtris = _vista_mesh.get_faces()
	for i in _vtris.size():
		_vtris[i] = _vista_xf * _vtris[i]
	var k := 0
	while k < _vtris.size():
		var x0 := INF; var x1 := -INF; var z0 := INF; var z1 := -INF
		for q in 3:
			var p := _vtris[k + q]
			x0 = minf(x0, p.x); x1 = maxf(x1, p.x); z0 = minf(z0, p.z); z1 = maxf(z1, p.z)
		for gx in range(int(floor(x0 / 18.0)), int(floor(x1 / 18.0)) + 1):
			for gz in range(int(floor(z0 / 18.0)), int(floor(z1 / 18.0)) + 1):
				var key := Vector2i(gx, gz)
				if not _vbuckets.has(key):
					_vbuckets[key] = PackedInt32Array()
				_vbuckets[key].append(k)
		k += 3


func _vista_h(x: float, z: float) -> float:
	_vista_prep()
	var key := Vector2i(int(floor(x / 18.0)), int(floor(z / 18.0)))
	if not _vbuckets.has(key):
		return NAN
	for k in _vbuckets[key]:
		var a := _vtris[k]; var b := _vtris[k + 1]; var c := _vtris[k + 2]
		var d := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(d) < 1e-9:
			continue
		var w0 := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / d
		var w1 := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / d
		var w2 := 1.0 - w0 - w1
		if w0 < -1e-4 or w1 < -1e-4 or w2 < -1e-4:
			continue
		return a.y * w0 + b.y * w1 + c.y * w2
	return NAN


func _vista_has_tri(x: float, z: float) -> bool:
	return not is_nan(_vista_h(x, z))


func _audit_seam() -> Dictionary:
	var worst := 0.0
	var worst_p := Vector2.ZERO
	var over := 0
	var n := 0
	var sum := 0.0
	var per_side := {"N": 0.0, "S": 0.0, "W": 0.0, "E": 0.0}   # 有號：Vista − 地形
	var t := -HALF
	while t <= HALF:
		for side in [["N", t, -HALF, 0.0, -0.05], ["S", t, HALF, 0.0, 0.05], ["W", -HALF, t, -0.05, 0.0], ["E", HALF, t, 0.05, 0.0]]:
			var x: float = side[1]
			var z: float = side[2]
			# Vista 取樣往外 5 cm（邊線本身在地形三角形上，Vista 從邊線外開始）
			var vh := _vista_h(x + side[3], z + side[4])
			if is_nan(vh):
				continue
			var d: float = vh - h_at(x, z)
			n += 1
			sum += absf(d)
			if absf(d) > absf(per_side[side[0]]):
				per_side[side[0]] = snappedf(d, 0.01)
			if absf(d) > worst:
				worst = absf(d)
				worst_p = Vector2(x, z)
			if absf(d) > 0.5:
				over += 1
		t += 2.0
	print("[AUD] 地形↔Vista 接縫：%d 取樣，平均 |Δ| %.2f m，>0.5 m 有 %d 處，最大 %.2f m @ (%.0f, %.0f)"
		% [n, sum / n, over, worst, worst_p.x, worst_p.y])
	print("[AUD]   各邊最大（Vista−地形，有號）：N %+.2f  S %+.2f  W %+.2f  E %+.2f" % [per_side.N, per_side.S, per_side.W, per_side.E])
	# 邊界外 15 m（Vista 第一圈頂點 |x|=90）的落差：這才是玩家隔著牆看到的「崖」
	var ring := {"N": 0.0, "S": 0.0, "W": 0.0, "E": 0.0}
	t = -HALF
	while t <= HALF:
		for side in [["N", t, -90.0, t, -HALF], ["S", t, 90.0, t, HALF], ["W", -90.0, t, -HALF, t], ["E", 90.0, t, HALF, t]]:
			var vh2 := _vista_h(side[1], side[2])
			if is_nan(vh2):
				continue
			var d: float = vh2 - h_at(side[3], side[4])
			if absf(d) > absf(ring[side[0]]):
				ring[side[0]] = snappedf(d, 0.01)
		t += 2.0
	print("[AUD]   邊界外 15 m Vista 相對地形邊緣：N %+.2f  S %+.2f  W %+.2f  E %+.2f" % [ring.N, ring.S, ring.W, ring.E])
	# Vista 內圈實際範圍（gen_lib.vista 的 inner_lo/inner_hi 用 int() 截斷，不對稱）
	var poke := 0
	var poke_n := 0
	var poke_worst := 0.0
	var poke_at := Vector2.ZERO
	var x := -HALF
	while x <= HALF:
		var z := -HALF
		while z <= HALF:
			if _vista_has_tri(x, z):
				poke_n += 1
				var d := _vista_h(x, z) - h_at(x, z)
				if d > -0.05:
					poke += 1
					if d > poke_worst:
						poke_worst = d
						poke_at = Vector2(x, z)
			z += 1.0
		x += 1.0
	print("[AUD]   Vista 與地形重疊帶：%d 取樣，Vista 高於地形−5cm（會穿出）%d 處，最高 %+.2f m @ (%.0f, %.0f)"
		% [poke_n, poke, poke_worst, poke_at.x, poke_at.y])
	return {"samples": n, "over_0p5": over, "worst": snappedf(worst, 0.01), "worst_at": [worst_p.x, worst_p.y],
		"per_side": per_side, "ring15": ring, "overlap_samples": poke_n, "overlap_poke": poke, "poke_worst": snappedf(poke_worst, 0.01)}


# ── 3. 邊界牆 ──
func _audit_boundary(scn: Node3D) -> Array:
	var out := []
	var bodies := []
	for path in ["Boundary", "ShrineExit/出口邊界"]:
		if scn.has_node(path):
			bodies.append(scn.get_node(path))
	for body in bodies:
		for sh in body.get_children():
			if not (sh is CollisionShape3D) or not (sh.shape is BoxShape3D):
				continue
			var cs := sh as CollisionShape3D
			var xf := cs.global_transform
			var sz: Vector3 = (cs.shape as BoxShape3D).size
			var bottom := xf.origin.y - sz.y * 0.5
			var top := xf.origin.y + sz.y * 0.5
			# 沿牆長取樣地形
			var along := Vector3(1, 0, 0) if sz.x > sz.z else Vector3(0, 0, 1)
			var length := maxf(sz.x, sz.z)
			var gmin := INF
			var gmax := -INF
			var k := -length * 0.5
			while k <= length * 0.5:
				var p := xf.origin + along * k
				if absf(p.x) <= HALF and absf(p.z) <= HALF:
					var g := h_at(p.x, p.z)
					gmin = minf(gmin, g)
					gmax = maxf(gmax, g)
				k += 2.0
			var gap_under := bottom - gmin          # >0 = 牆底高過最低地形 → 可鑽
			var head := top - gmax                  # <3 = 牆太矮
			var flag := ""
			if cs.disabled:
				flag = "(disabled)"
			elif gmin == INF:
				flag = "（在地形外，坐在 Vista 上）"
			elif gap_under > 0.0:
				flag = "✗ 牆底懸空 %.2f m" % gap_under
			elif head < 3.0:
				flag = "✗ 牆頂只高出地形 %.2f m" % head
			else:
				flag = "✓"
			print("[AUD] 牆 %s/%s @ (%.1f, %.1f, %.1f) 尺寸 %s  地形 %.2f~%.2f  %s"
				% [body.name, cs.name, xf.origin.x, xf.origin.y, xf.origin.z, sz, gmin, gmax, flag])
			out.append({"body": String(body.name), "shape": String(cs.name), "pos": [xf.origin.x, xf.origin.y, xf.origin.z],
				"size": [sz.x, sz.y, sz.z], "ground_min": snappedf(gmin, 0.01), "ground_max": snappedf(gmax, 0.01),
				"disabled": cs.disabled, "flag": flag})
	return out


# ── 4. 物件落地 ──
func _audit_grounding(scn: Node3D) -> Dictionary:
	var per := {}
	var floats := []
	var sinks := []
	for top in scn.get_children():
		if String(top.name) in SKIP_TOP or top is MultiMeshInstance3D:
			continue
		if top.name == "Terrain":
			continue
		# 物件 = GLB 實例根（scene_file_path 非空）或自建 MeshInstance3D；
		# 拜殿 121 個 tripo_part 要合併成一件量，否則屋頂零件全報浮空。
		var objs := {}
		for mi in _mesh_nodes(top):
			var o: Node = mi
			var cur: Node = mi
			while cur != null and cur != top:
				if cur.scene_file_path != "":
					o = cur
					break
				cur = cur.get_parent()
			if not objs.has(o):
				objs[o] = []
			objs[o].append(mi)
		for o in objs.keys():
			var m := o as Node3D
			var box: AABB
			var first := true
			for mi in objs[o]:
				var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
				box = b if first else box.merge(b)
				first = false
			var ox := m.global_position.x
			var oz := m.global_position.z
			if absf(ox) > HALF or absf(oz) > HALF:
				continue
			# 地形取樣在**節點原點**（樹幹／建築基準點），不是 AABB 中心：
			# 斜坡上樹冠不對稱，AABB 中心可能離樹幹好幾公尺。
			var g := h_at(ox, oz)
			var d := box.position.y - g          # >0 浮、<0 陷
			var grp := _group_of(m, scn)
			if not per.has(grp):
				per[grp] = {"n": 0, "float": 0, "sink": 0, "worst_float": 0.0, "worst_sink": 0.0}
			var e: Dictionary = per[grp]
			e.n += 1
			if d > FLOAT_LIM:
				e.float += 1
				e.worst_float = maxf(e.worst_float, d)
				floats.append([d, String(scn.get_path_to(m)), ox, oz])
			elif d < -SINK_LIM:
				e.sink += 1
				e.worst_sink = minf(e.worst_sink, d)
				sinks.append([d, String(scn.get_path_to(m)), ox, oz])
	var keys := per.keys()
	keys.sort()
	for k in keys:
		var e: Dictionary = per[k]
		print("[AUD] 落地 %-28s n=%5d 浮空 %4d（最大 %+.2f） 陷入 %4d（最深 %+.2f）"
			% [k, e.n, e.float, e.worst_float, e.sink, e.worst_sink])
	floats.sort_custom(func(a, b): return a[0] > b[0])
	sinks.sort_custom(func(a, b): return a[0] < b[0])
	print("[AUD] 浮空最嚴重 15：")
	for f in floats.slice(0, 15):
		print("[AUD]   %+.2f  %s @ (%.1f, %.1f)" % [f[0], f[1], f[2], f[3]])
	print("[AUD] 陷入最嚴重 15：")
	for s in sinks.slice(0, 15):
		print("[AUD]   %+.2f  %s @ (%.1f, %.1f)" % [s[0], s[1], s[2], s[3]])
	return {"groups": per, "float_total": floats.size(), "sink_total": sinks.size()}


func _group_of(n: Node, scn: Node) -> String:
	# 「頂層/次層」兩段當分組名
	var chain := []
	var cur: Node = n
	while cur != null and cur != scn:
		chain.push_front(String(cur.name))
		cur = cur.get_parent()
	if chain.size() >= 2:
		return chain[0] + "/" + chain[1]
	return chain[0] if chain.size() > 0 else "?"


func _mesh_nodes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		o.append(n)
	for c in n.get_children():
		o.append_array(_mesh_nodes(c))
	return o
