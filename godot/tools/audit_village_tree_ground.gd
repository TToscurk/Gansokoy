extends SceneTree
## 診斷村緣樹群：每棵樹對地面射線取樣，量浮空／埋沒／落在水面上的數量。
## 不猜——直接讀 slice.tscn 的實際碰撞與水面高度。

const NAMES := ["普通樹", "大衫", "2大衫", "針葉樹1",
	"針葉林樹3", "針葉林樹4", "盆樹"]

func _init() -> void:
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("slice", "trail")
	await _wait(90)

	var space: PhysicsDirectSpaceState3D = main.get_viewport().world_3d.direct_space_state

	# 找水面節點，量它們的 y 與 xz 範圍
	print("=== 水面 / 河道節點 ===")
	var waters: Array = []
	var stack: Array = [main]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		var nm := String(nd.name)
		if nd is MeshInstance3D and (nm.contains("水") or nm.to_lower().contains("water")
				or nm.to_lower().contains("river") or nm.to_lower().contains("creek")
				or nm.to_lower().contains("canal")):
			var mi: MeshInstance3D = nd
			var ab: AABB = mi.get_aabb()
			var g: AABB = mi.global_transform * ab
			waters.append(g)
			print("  %-28s y頂=%.2f  x[%.1f..%.1f] z[%.1f..%.1f]"
				% [nm, g.position.y + g.size.y, g.position.x, g.position.x + g.size.x,
					g.position.z, g.position.z + g.size.z])
		for c in nd.get_children():
			stack.push_back(c)

	print("\n=== 每棵樹的地面落差 ===")
	var float_n := 0
	var sink_n := 0
	var water_n := 0
	var miss_n := 0
	var total := 0
	var worst: Array = []
	for n in NAMES:
		var mm := ResourceLoader.load("res://maps/slice/gen/treemm_%s.res" % n,
			"", ResourceLoader.CACHE_MODE_IGNORE) as MultiMesh
		if mm == null:
			continue
		for i in mm.instance_count:
			total += 1
			var t: Transform3D = mm.get_instance_transform(i)
			var p: Vector3 = t.origin
			# 只打地面層（bit32）；不設 mask 會撞到 y=55 的邊界牆與長屋屋頂，
			# 把牆頂當成「地面」，正常的樹會被誤報成埋沒 -54 m。
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(p.x, p.y + 200.0, p.z), Vector3(p.x, p.y - 200.0, p.z),
				1 << 31)
			var hit: Dictionary = space.intersect_ray(q)
			if hit.is_empty():
				miss_n += 1
				worst.append([999.0, n, i, p, "無地面"])
				continue
			var gy: float = hit.position.y
			var d: float = p.y - gy          # 正=浮空，負=埋沒
			if d > 0.35:
				float_n += 1
				worst.append([d, n, i, p, "浮空"])
			elif d < -0.6:
				sink_n += 1
				worst.append([d, n, i, p, "埋沒"])
			# 是否落在水面 xz 範圍內
			for g in waters:
				var wtop: float = g.position.y + g.size.y
				if p.x >= g.position.x and p.x <= g.position.x + g.size.x \
						and p.z >= g.position.z and p.z <= g.position.z + g.size.z \
						and gy <= wtop + 0.5:
					water_n += 1
					worst.append([abs(d) + 100.0, n, i, p, "在水域範圍"])
					break

	print("  總樹數 %d：浮空(>0.35m) %d，埋沒(<-0.6m) %d，射線打不到地面 %d，落在水域 %d"
		% [total, float_n, sink_n, miss_n, water_n])

	worst.sort_custom(func(a, b): return abs(a[0]) > abs(b[0]))
	print("\n=== 最嚴重的 25 棵 ===")
	for i in mini(25, worst.size()):
		var w: Array = worst[i]
		print("  %-10s #%-3d %-6s 落差%7.2f m  @ (%.1f, %.2f, %.1f)"
			% [w[1], w[2], w[4], w[0] if w[0] < 100.0 else 0.0,
				(w[3] as Vector3).x, (w[3] as Vector3).y, (w[3] as Vector3).z])
	quit(0)
