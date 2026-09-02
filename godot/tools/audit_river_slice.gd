extends SceneTree
## One-shot audit of slice.tscn river geometry.
## Prints per-mesh stats and, for a set of probe XZ points (in the pale
## "white field" zones), which meshes cover that column and at what Y.
## Run: godot --headless --path godot --script tools/audit_river_slice.gd

const PROBES: Array = [
	Vector2(-150, 500),   # SW outside the channel (pale field, south bridge cam left)
	Vector2(-60, 430),    # inside village side near south bridge
	Vector2(120, 530),    # SE outside channel
	Vector2(-300, 260),   # west outside
	Vector2(60, 300),     # village platform interior
	Vector2(0, 476),      # mid-channel (should be water/bed)
	Vector2(220, -260),   # northeast detail-camera target
	Vector2(260, -300),
	Vector2(300, -340),
	Vector2(340, -380),
	Vector2(380, -420),
	Vector2(420, -460),
	Vector2(170, -310),   # unified northeast dry-land closure
	Vector2(290, -206),
	Vector2(573, -381),
	Vector2(303, -615),
	Vector2(80, -350),
	Vector2(330, -150),
]

const CANAL_TRENCH_PROBES: Array[Vector2] = [
	Vector2(287.0, -40.0),
	Vector2(287.0, 16.0),
	Vector2(287.0, 72.0),
]
const CANAL_TERRAIN_MAX_Y := -3.0


func _init() -> void:
	var ps: PackedScene = load("res://maps/slice/slice.tscn")
	var root: Node = ps.instantiate()
	if not _audit_canal_trench(root):
		root.free()
		ps = null
		quit(1)
		return
	if not _audit_feeder_outfall(root):
		root.free()
		ps = null
		quit(1)
		return
	if not _audit_river_links(root):
		root.free()
		ps = null
		quit(1)
		return
	if not _audit_paddy_support(root):
		root.free()
		ps = null
		quit(1)
		return
	if OS.get_cmdline_user_args().has("--canal-only"):
		root.free()
		ps = null
		quit()
		return
	var targets: Array = []
	_collect(root, targets)

	for mi_any in targets:
		var mi: MeshInstance3D = mi_any
		var mesh: ArrayMesh = mi.mesh as ArrayMesh
		if mesh == null:
			print("%s: (no ArrayMesh: %s)" % [mi.name, str(mi.mesh)])
			continue
		var aabb: AABB = mesh.get_aabb()
		var total_v: int = 0
		var total_f: int = 0
		var all_y := PackedFloat32Array()
		for s in range(mesh.get_surface_count()):
			var arr: Array = mesh.surface_get_arrays(s)
			var surface_vertices: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			total_v += surface_vertices.size()
			for vertex in surface_vertices:
				all_y.append(vertex.y)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			total_f += (idx.size() / 3) if idx.size() > 0 else ((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3)
		print("%s: surfaces=%d verts=%d faces=%d aabb_pos=%s aabb_size=%s xform_origin=%s" % [
			mi.name, mesh.get_surface_count(), total_v, total_f,
			str(aabb.position), str(aabb.size), str(mi.transform.origin)])
		all_y.sort()
		if not all_y.is_empty():
			print("  y percentiles: min=%.2f p50=%.2f p90=%.2f p95=%.2f p99=%.2f max=%.2f >20m=%d" % [
				all_y[0], _percentile(all_y, 0.50), _percentile(all_y, 0.90),
				_percentile(all_y, 0.95), _percentile(all_y, 0.99), all_y[-1],
				_count_above(all_y, 20.0)])

		# probe coverage (skip absurdly big meshes per-face; note it)
		if total_f > 400000:
			print("  (skipped probe test: too many faces)")
			continue
		for p_i in range(PROBES.size()):
			var p: Vector2 = PROBES[p_i]
			var lp: Vector3 = Vector3(p.x, 0.0, p.y) - mi.transform.origin
			if not _aabb_covers_xz(aabb, lp):
				continue
			var hit_y: float = -1e9
			var hit: bool = false
			for s in range(mesh.get_surface_count()):
				var arr: Array = mesh.surface_get_arrays(s)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				var n: int = idx.size() if idx.size() > 0 else vs.size()
				for f in range(0, n, 3):
					var a: Vector3
					var b: Vector3
					var c3: Vector3
					if idx.size() > 0:
						a = vs[idx[f]]; b = vs[idx[f + 1]]; c3 = vs[idx[f + 2]]
					else:
						a = vs[f]; b = vs[f + 1]; c3 = vs[f + 2]
					var y: float = _tri_y_at(a, b, c3, Vector2(lp.x, lp.z))
					if y > -1e8:
						hit = true
						hit_y = max(hit_y, y)
			if hit:
				print("  probe %d %s -> covered, top_y=%.2f" % [p_i, str(p), hit_y + mi.transform.origin.y])
	targets.clear()
	root.free()
	ps = null
	quit()


func _audit_canal_trench(root: Node) -> bool:
	var ground: MeshInstance3D = root.get_node_or_null("UnifiedGround") as MeshInstance3D
	if ground == null:
		push_error("CANAL_TRENCH: UnifiedGround missing")
		return false
	var ok := true
	for probe in CANAL_TRENCH_PROBES:
		var top_y: float = _mesh_top_y_at(ground, probe)
		print("CANAL_TRENCH probe=%s terrain_top=%.3f max=%.3f" % [
			str(probe), top_y, CANAL_TERRAIN_MAX_Y])
		if top_y > CANAL_TERRAIN_MAX_Y:
			push_error("CANAL_TRENCH blocked at %s: terrain %.3f is above %.3f" % [
				str(probe), top_y, CANAL_TERRAIN_MAX_Y])
			ok = false
	return ok


## 田區排水鏈必須在三維上連續：水平排水渠要碰到幹渠東緣，且自身最低點
## 必須落到該處下游水面；只在 XZ 重疊但懸在水面上方仍視為失敗。
## ❗ 接水面必須取「實際看得見」的那一層。舊版寫死 DownstreamWater，
## 而它在正式場景是 visible=false 的廢棄 box；它的 y 恰巧與新水面
## 相同，於是 vertical_gap=0.000 假通過，而實機畫面裡跌水根本沒接到水。
func _visible_receiver(root: Node) -> MeshInstance3D:
	var candidates: Array[String] = [
		"MachiCanal/ChannelGeometry/CanalWater/Reach_Lower",
		"MachiCanal/ChannelGeometry/DownstreamWater",
	]
	for p in candidates:
		var node: MeshInstance3D = root.get_node_or_null(p) as MeshInstance3D
		if node == null:
			continue
		var shown: bool = node.visible
		var walker: Node = node.get_parent()
		while shown and walker != null and walker != root:
			var as_v3d: Node3D = walker as Node3D
			if as_v3d != null and not as_v3d.visible:
				shown = false
			walker = walker.get_parent()
		if shown:
			print("FEEDER_OUTFALL receiver=%s" % p)
			return node
		print("FEEDER_OUTFALL skip hidden receiver=%s" % p)
	return null


func _audit_feeder_outfall(root: Node) -> bool:
	var feeder: MeshInstance3D = root.get_node_or_null("EastBankDressing/FeederWater") as MeshInstance3D
	var receiver: MeshInstance3D = _visible_receiver(root)
	if feeder == null or receiver == null:
		push_error("FEEDER_OUTFALL: FeederWater or a VISIBLE canal water surface missing")
		return false
	var feeder_ab: AABB = _world_xform(feeder) * feeder.get_aabb()
	var receiver_ab: AABB = _world_xform(receiver) * receiver.get_aabb()
	var receiver_east: float = receiver_ab.position.x + receiver_ab.size.x
	var receiver_top: float = receiver_ab.position.y + receiver_ab.size.y
	# 排水鏈是三段：水平渠 → 水舌 → 幹渠水面。水舌已拆成獨立節點，所以
	# 不能再拿 FeederWater 直接比幹渠水面（那樣它必然懸空 2.5m）。
	# 逐段檢查銜接：水平渠底 ↔ 水舌頂、水舌底 ↔ 幹渠水面。
	var nappe: MeshInstance3D = root.get_node_or_null("EastBankDressing/FeederNappe") as MeshInstance3D
	if nappe == null:
		push_error("FEEDER_OUTFALL: FeederNappe (the drop) missing — feeder would hang over the canal")
		return false
	var nab: AABB = _world_xform(nappe) * nappe.get_aabb()
	var nappe_top: float = nab.position.y + nab.size.y
	var nappe_bot: float = nab.position.y
	# 銜接 1：水舌頂端必須接到水平渠的水面高度。
	var link_up: float = absf(nappe_top - feeder_ab.position.y)
	# 銜接 2：水舌底端必須落到幹渠水面（不得懸空）。
	var vertical_gap: float = nappe_bot - receiver_top
	# 銜接 3：水舌必須向西越過幹渠東緣。
	var x_gap: float = nab.position.x - receiver_east
	var old_trough: Node = root.get_node_or_null("MachiCanal/PaddyFields/Irrigation/木樋_北")
	var old_pump: Node = root.get_node_or_null("MachiCanal/Waterworks/田泵水口_北")
	print("FEEDER_OUTFALL link_up=%.3f x_gap=%.3f vertical_gap=%.3f nappe_y=%.3f..%.3f feeder_y=%.3f receiver_top=%.3f old_trough=%s old_pump=%s" % [
		link_up, x_gap, vertical_gap, nappe_bot, nappe_top,
		feeder_ab.position.y, receiver_top, str(old_trough != null), str(old_pump != null)])
	if link_up > 0.05:
		push_error("FEEDER_OUTFALL drop detached from the horizontal drain by %.3f m" % link_up)
		return false
	if x_gap > 0.01:
		push_error("FEEDER_OUTFALL dry XZ break %.3f m" % x_gap)
		return false
	if vertical_gap > 0.05:
		push_error("FEEDER_OUTFALL hangs %.3f m above canal water" % vertical_gap)
		return false
	if old_trough != null:
		push_error("FEEDER_OUTFALL obsolete 木樋_北 still present")
		return false
	if old_pump != null:
		push_error("FEEDER_OUTFALL obsolete 田泵水口_北 blocks the drop mouth")
		return false
	# 落點必須有泡沫舌，且鋪在下游（西）側。
	# 泡沫扇形必須鋪在落點的下游（西）側。cos 符號寫錯會讓它整片往東
	# 鋪回上游的田裡，而長度、面積、材質全部照樣通過——只有方向能抓到。
	# 註：舊的 FEEDER_APRON west_reach 檢查已移除——泡沫舌已拆成獨立的
	# FeederSplash 節點，不再是 FeederWater mesh 的一部分，那條會恆為 0。
	var splash: MeshInstance3D = root.get_node_or_null("EastBankDressing/FeederSplash") as MeshInstance3D
	if splash == null:
		push_error("FEEDER_SPLASH node missing")
		return false
	var sab: AABB = _world_xform(splash) * splash.get_aabb()
	var splash_w: float = sab.position.x
	var splash_e: float = sab.position.x + sab.size.x
	print("FEEDER_SPLASH x=%.2f..%.2f (mouth=292.40)" % [splash_w, splash_e])
	if splash_w > 292.0:
		push_error("FEEDER_SPLASH points upstream: west edge %.2f never reaches the canal" % splash_w)
		return false
	if splash_e > 292.9:
		push_error("FEEDER_SPLASH spills %.2f m east onto the paddy side" % (splash_e - 292.4))
		return false
	# 水舌與泡沫都必須用有 shred 的專屬材質。若被合回 canal_water_upper
	# （shore_alpha=0.62、shred=0），輪廓就淡不掉，重新變回硬邊平板——
	# 位置、尺寸、連續性全部照樣通過，只有材質參數能抓到這個退化。
	for spec in [["EastBankDressing/FeederNappe", "nappe"], ["EastBankDressing/FeederSplash", "splash"]]:
		var mi: MeshInstance3D = root.get_node_or_null(spec[0]) as MeshInstance3D
		if mi == null:
			push_error("FEEDER_SHRED %s node missing" % spec[1])
			return false
		var mat: ShaderMaterial = mi.material_override as ShaderMaterial
		if mat == null:
			push_error("FEEDER_SHRED %s has no ShaderMaterial override" % spec[1])
			return false
		var sh: float = float(mat.get_shader_parameter("shred"))
		var sa2: float = float(mat.get_shader_parameter("shore_alpha"))
		print("FEEDER_SHRED %s shred=%.2f shore_alpha=%.2f" % [spec[1], sh, sa2])
		if sh < 0.3:
			push_error("FEEDER_SHRED %s shred=%.2f — edges will read as a hard plate" % [spec[1], sh])
			return false
		if sa2 > 0.05:
			push_error("FEEDER_SHRED %s shore_alpha=%.2f floors ALPHA; edge cannot fade" % [spec[1], sa2])
			return false
	return true


## 幹渠接大河的兩口都必須真的通到河裡。⚠ 上一版只比對 Y（跌水底 =
## -5.15 = 河面）就放行，但沒檢查 XZ 是否落在水面範圍內 —— 結果南口
## 跌水離水面西緣還差 1.0m，整段打在乾坡上，稽核全綠。
## 根因是我用 _river_x() 解析式估水面位置，那條式子忽略 noise 項，
## z=-118 算出 413.9 而實測 411.5。這裡改成從 EastRiverWater 的實際
## mesh 取該 z 切片的水面 x 範圍，再確認泡沫確實落在裡面。
func _river_water_span(root: Node, z: float) -> Vector2:
	var rw: MeshInstance3D = root.get_node_or_null("EastRiverWater") as MeshInstance3D
	if rw == null or rw.mesh == null:
		return Vector2(INF, -INF)
	var vs: PackedVector3Array = rw.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var xf: Transform3D = _world_xform(rw)
	var lo: float = INF
	var hi: float = -INF
	for v in vs:
		var w: Vector3 = xf * v
		if absf(w.z - z) < 4.0:
			lo = minf(lo, w.x)
			hi = maxf(hi, w.x)
	return Vector2(lo, hi)


func _audit_river_links(root: Node) -> bool:
	var ok: bool = true
	var mouths: Array = [
		["outfall", "RiverLinks/OutfallWater", "RiverLinks/OutfallNappe", "RiverLinks/OutfallSplash", -118.0],
		["intake", "RiverLinks/IntakeWater", "RiverLinks/IntakeNappe", "RiverLinks/IntakeSplash", 150.0]]
	var water_y: float = -5.15
	for m in mouths:
		var tag: String = String(m[0])
		var cw: MeshInstance3D = root.get_node_or_null(String(m[1])) as MeshInstance3D
		var np: MeshInstance3D = root.get_node_or_null(String(m[2])) as MeshInstance3D
		var sp: MeshInstance3D = root.get_node_or_null(String(m[3])) as MeshInstance3D
		if cw == null or np == null or sp == null:
			push_error("RIVER_LINK %s missing water/nappe/splash node" % tag)
			return false
		var cab: AABB = _node_world_aabb(cw)
		var nab: AABB = _node_world_aabb(np)
		var sab: AABB = _node_world_aabb(sp)
		# 1) 渠道最低點必須接上跌水頂
		var join: float = absf(cab.position.y - (nab.position.y + nab.size.y))
		# 2) 跌水底必須落到河面
		var land: float = absf(nab.position.y - water_y)
		# 3) ⚠ 泡沫必須真的落在河水的 XZ 範圍內，不是只有高度對
		var span: Vector2 = _river_water_span(root, float(m[4]))
		var splash_e: float = sab.position.x + sab.size.x
		var reach: float = splash_e - span.x
		print("RIVER_LINK %s: canal_low=%.3f nappe %.3f..%.3f splash_x=%.1f..%.1f river_x=%.1f..%.1f | join=%.3f land=%.3f reach=%+.2fm" % [
			tag, cab.position.y, nab.position.y, nab.position.y + nab.size.y,
			sab.position.x, splash_e, span.x, span.y, join, land, reach])
		if join > 0.05:
			push_error("RIVER_LINK %s drop detached from canal by %.3f m" % [tag, join]); ok = false
		if land > 0.05:
			push_error("RIVER_LINK %s drop does not reach river level (%.3f m off)" % [tag, land]); ok = false
		if reach < 0.5:
			push_error("RIVER_LINK %s splash lands %.2f m SHORT of the river water — it is hitting dry bank" % [tag, -reach]); ok = false
	# 兩座水門必須跨在渠上，不得埋進渠底
	for g in [["RiverLinks/北口水門", "RiverLinks/IntakeWater"], ["RiverLinks/分水口水門", "RiverLinks/OutfallWater"]]:
		var gn: Node3D = root.get_node_or_null(String(g[0])) as Node3D
		var cn: MeshInstance3D = root.get_node_or_null(String(g[1])) as MeshInstance3D
		if gn == null or cn == null:
			push_error("RIVER_LINK gate %s missing" % String(g[0])); ok = false
			continue
		var gab: AABB = _node_world_aabb(gn)
		var rab: AABB = _node_world_aabb(cn)
		var sink: float = (rab.position.y - 0.32) - gab.position.y
		print("RIVER_LINK %s bottom=%.3f sink=%.3f" % [String(g[0]).get_slice("/", 1), gab.position.y, sink])
		if sink > 0.6:
			push_error("RIVER_LINK %s buried %.3f m below the channel bed" % [String(g[0]).get_slice("/", 1), sink]); ok = false
	# 水車方案已被使用者否決，這些節點不得復活
	for dead in ["RiverLinks/揚水水車", "RiverLinks/揚水水車小屋", "RiverLinks/IntakeFlume", "RiverLinks/IntakeFlumeWater"]:
		if root.get_node_or_null(dead) != null:
			push_error("RIVER_LINK rejected waterwheel node still present: %s" % dead); ok = false
	return ok


## 取節點（含其所有 MeshInstance3D 子節點）的世界 AABB。
func _node_world_aabb(n: Node3D) -> AABB:
	var mi: MeshInstance3D = n as MeshInstance3D
	if mi != null and mi.mesh != null:
		return _world_xform(mi) * mi.get_aabb()
	var agg: AABB = AABB()
	var first: bool = true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var cm: MeshInstance3D = c as MeshInstance3D
		if cm.mesh == null:
			continue
		var cab: AABB = _world_xform(cm) * cm.get_aabb()
		if first:
			agg = cab
			first = false
		else:
			agg = agg.merge(cab)
	return agg


## 水田支撐面審計：每格水田中心下方，UnifiedGround 的地形頂必須低於
## 該格泥面底，否則地形會把田面埋掉。
## 注意：實例化但未加入 SceneTree 時，global_transform 是 IDENTITY——
## 必須手動累加 transform 鏈（本檔 _mesh_top_y_at 曾犯過同一個錯）。
func _audit_paddy_support(root: Node) -> bool:
	var ground: MeshInstance3D = root.get_node_or_null("UnifiedGround") as MeshInstance3D
	var paddy: Node = root.get_node_or_null("MachiCanal/PaddyFields/PaddyWater")
	if ground == null or paddy == null:
		push_error("PADDY_SUPPORT: UnifiedGround or PaddyWater missing")
		return false
	var ok := true
	var mesh_arrays: Array = ground.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = mesh_arrays[Mesh.ARRAY_VERTEX]
	for child in paddy.get_children():
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var ab: AABB = _world_xform(mi) * mi.get_aabb()
		var probe: Vector2 = Vector2(ab.position.x + ab.size.x * 0.5, ab.position.z + ab.size.z * 0.5)
		var paddy_bottom: float = ab.position.y
		var terrain_top: float = -INF
		for v in verts:
			var d: float = Vector2(v.x - probe.x, v.z - probe.y).length_squared()
			if d < 9.0 and v.y > terrain_top:  # 3m 半徑內取最高點
				terrain_top = v.y
		if terrain_top == -INF:
			push_warning("PADDY_SUPPORT %s: no terrain sample near %s" % [child.name, str(probe)])
			continue
		var clearance: float = paddy_bottom - terrain_top
		if clearance < 0.0:
			push_error("PADDY_SUPPORT buried %s probe=(%.1f,%.1f): terrain %.3f above paddy bottom %.3f (%.3f m)" % [
				child.name, probe.x, probe.y, terrain_top, paddy_bottom, -clearance])
			ok = false
		else:
			print("PADDY_SUPPORT %s probe=(%.1f,%.1f) terrain=%.3f paddy_bottom=%.3f clearance=%.3f" % [
				child.name, probe.x, probe.y, terrain_top, paddy_bottom, clearance])
	return ok


func _world_xform(n: Node3D) -> Transform3D:
	var t: Transform3D = n.transform
	var cur: Node = n.get_parent()
	while cur != null:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _mesh_top_y_at(mi: MeshInstance3D, world_xz: Vector2) -> float:
	var mesh: ArrayMesh = mi.mesh as ArrayMesh
	if mesh == null:
		return INF
	# The audit instantiates the scene without adding it to SceneTree, so use
	# the node's local transform. UnifiedGround is a direct child of slice.
	var local_probe: Vector3 = mi.transform.affine_inverse() * Vector3(world_xz.x, 0.0, world_xz.y)
	var top_y := -INF
	for surface in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var raw_indices = arrays[Mesh.ARRAY_INDEX]
		var indices: PackedInt32Array = raw_indices if raw_indices != null else PackedInt32Array()
		var count: int = indices.size() if not indices.is_empty() else vertices.size()
		for face in range(0, count, 3):
			var a: Vector3 = vertices[indices[face]] if not indices.is_empty() else vertices[face]
			var b: Vector3 = vertices[indices[face + 1]] if not indices.is_empty() else vertices[face + 1]
			var c: Vector3 = vertices[indices[face + 2]] if not indices.is_empty() else vertices[face + 2]
			var local_y: float = _tri_y_at(a, b, c, Vector2(local_probe.x, local_probe.z))
			if local_y > -1e8:
				var world_y: float = (mi.transform * Vector3(local_probe.x, local_y, local_probe.z)).y
				top_y = maxf(top_y, world_y)
	return top_y


func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		var m: Mesh = mi.mesh
		if m != null:
			var ab: AABB = m.get_aabb()
			# only meshes big enough to be a "field" (>80m on a ground axis)
			if ab.size.x > 80.0 or ab.size.z > 80.0:
				out.append(mi)
	for c in n.get_children():
		_collect(c, out)


func _aabb_covers_xz(aabb: AABB, lp: Vector3) -> bool:
	return lp.x >= aabb.position.x and lp.x <= aabb.position.x + aabb.size.x \
		and lp.z >= aabb.position.z and lp.z <= aabb.position.z + aabb.size.z


func _tri_y_at(a: Vector3, b: Vector3, c: Vector3, p: Vector2) -> float:
	var p0 := Vector2(a.x, a.z)
	var p1 := Vector2(b.x, b.z)
	var p2 := Vector2(c.x, c.z)
	var d: float = (p1.y - p2.y) * (p0.x - p2.x) + (p2.x - p1.x) * (p0.y - p2.y)
	if abs(d) < 0.000001:
		return -1e9
	var w0: float = ((p1.y - p2.y) * (p.x - p2.x) + (p2.x - p1.x) * (p.y - p2.y)) / d
	var w1: float = ((p2.y - p0.y) * (p.x - p2.x) + (p0.x - p2.x) * (p.y - p2.y)) / d
	var w2: float = 1.0 - w0 - w1
	if w0 < -0.001 or w1 < -0.001 or w2 < -0.001:
		return -1e9
	return a.y * w0 + b.y * w1 + c.y * w2


func _percentile(values: PackedFloat32Array, ratio: float) -> float:
	var index: int = clampi(roundi(float(values.size() - 1) * ratio), 0, values.size() - 1)
	return values[index]


func _count_above(values: PackedFloat32Array, threshold: float) -> int:
	var count: int = 0
	for value in values:
		if value > threshold:
			count += 1
	return count
