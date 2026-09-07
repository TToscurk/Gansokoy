extends SceneTree
## 人間之里可走範圍量測：格點取樣地面，找出真正的遊玩區邊界。
## 邊界牆要立在「有地面」與「沒地面」的交界，不能憑地圖檔尺寸猜。
##   Godot --headless --path godot --script tools/audit_slice_extent.gd
var main: Node
var space: PhysicsDirectSpaceState3D


func _init() -> void:
	_run.call_deferred()


func _settle(n: int = 4) -> void:
	for i in n:
		await physics_frame
		await process_frame


## 該 xz 是否有可站立地面（排除 40 m 高的隱形邊界牆）
func _ground(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 300.0, z), Vector3(x, -80.0, z))
	q.exclude = [main.player.get_rid()] as Array[RID]
	var hit := space.intersect_ray(q)
	return hit.position.y if hit.has("position") else -INF


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(20)
	main.load_map("slice", "")
	await _settle(50)
	space = main.get_viewport().get_world_3d().direct_space_state

	# 1) 地面 mesh 的視覺範圍
	var mr: Node = main.map_root
	for nm in ["UnifiedGround", "Terrain", "BasinHills", "GroundUnderlay"]:
		var n: Node = mr.get_node_or_null(nm)
		if n == null or not (n is MeshInstance3D):
			continue
		var b: AABB = (n as Node3D).global_transform * (n as MeshInstance3D).get_aabb()
		print("[EXT] mesh %-16s x[%.0f, %.0f] z[%.0f, %.0f] 可見=%s"
			% [nm, b.position.x, b.end.x, b.position.z, b.end.z,
			(n as Node3D).is_visible_in_tree()])

	# 2) 實際碰撞地面的格點掃描
	var STEP := 8.0
	var minx := INF
	var maxx := -INF
	var minz := INF
	var maxz := -INF
	var n_ok := 0
	var x := -80.0
	while x <= 560.0:
		var z := -260.0
		while z <= 560.0:
			var gy := _ground(x, z)
			if gy != -INF and gy > -20.0 and gy < 60.0:
				n_ok += 1
				minx = minf(minx, x); maxx = maxf(maxx, x)
				minz = minf(minz, z); maxz = maxf(maxz, z)
			z += STEP
		x += STEP
	print("[EXT] 有地面的格點 %d 個（%.0f m 間距）" % [n_ok, STEP])
	print("[EXT] 地面範圍 x[%.0f, %.0f] z[%.0f, %.0f]（%.0f × %.0f m）"
		% [minx, maxx, minz, maxz, maxx - minx, maxz - minz])

	# 3) 邊緣掃描：每條邊上，地面實際在哪裡結束
	print("[EXT] ── 四邊的地面終點（每 40 m 抽一條線）──")
	var zc := (minz + maxz) * 0.5
	for zi in range(int(minz), int(maxz) + 1, 40):
		var west := INF
		var east := -INF
		var xx := minx - 40.0
		while xx <= maxx + 40.0:
			if _ground(xx, float(zi)) != -INF:
				west = minf(west, xx)
				east = maxf(east, xx)
			xx += 4.0
		if west != INF:
			print("[EXT] z=%-6d 地面 x 從 %.0f 到 %.0f" % [zi, west, east])

	# 4) 傳送點必須在牆內
	print("[EXT] ── 傳送點 ──")
	for p in main.current_portals():
		print("[EXT] portal → %-10s (%.0f, %.0f)"
			% [String(p.get("target", "保留")), float(p.x), float(p.z)])
	# 5) 玩家出生點
	print("[EXT] 玩家出生 (%.1f, %.1f)" % [main.player.global_position.x, main.player.global_position.z])
	quit(0)
