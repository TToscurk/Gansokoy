extends SceneTree
## 獸道戰鬥點選址：量測候選座標的地面高度與可站立性。
##   Godot --headless --path godot --script tools/probe_trail_spots.gd
var main: Node
var space: PhysicsDirectSpaceState3D


func _init() -> void:
	_run.call_deferred()


func _settle(n: int = 4) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _ground(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -100.0, z))
	q.exclude = [main.player.get_rid()] as Array[RID]
	var ex: Array[RID] = [main.player.get_rid()]
	for k in 8:
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if not hit.has("position"):
			return -INF
		var col: Object = hit.get("collider")
		var nm := String(col.name) if col else ""
		if not (nm.contains("Boundary") or nm.contains("邊界") or nm.contains("boundary")):
			return hit.position.y
		ex.append(hit.rid)
	return -INF


## 這個點周圍 r 公尺內有多少可站立空間（避免把狼生在樹幹裡）
func _clearance(x: float, z: float, r: float) -> float:
	var ok := 0
	var total := 0
	for i in 12:
		var a := TAU * float(i) / 12.0
		var px := x + cos(a) * r
		var pz := z + sin(a) * r
		total += 1
		var gy := _ground(px, pz)
		if gy != -INF:
			# 上方 2 m 有沒有東西擋著（樹幹／岩石）
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(px, gy + 0.4, pz), Vector3(px, gy + 2.2, pz))
			if not space.intersect_ray(q).has("position"):
				ok += 1
	return 100.0 * float(ok) / float(total)


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(20)
	main.load_map("trail", "")
	await _settle(40)
	space = main.get_viewport().get_world_3d().direct_space_state
	# MQ01 在 trail_presence (7, -70) 完成；神社口在 (3, -107.8)。
	# 戰鬥點要在這兩者之間，且離兩端都有距離。
	print("[SPOT] 候選點（獸道 z=-72 ~ -100 段）")
	var best := []
	var z := -74.0
	while z >= -102.0:
		# 沿 path 內插 x：(7.3,-59.4) → (3,-107.8)
		var t: float = (absf(z) - 59.4) / (107.8 - 59.4)
		var x: float = 7.3 + (3.0 - 7.3) * clampf(t, 0.0, 1.0)
		var gy := _ground(x, z)
		var cl := _clearance(x, z, 3.0)
		var cl6 := _clearance(x, z, 6.0)
		print("[SPOT] (%.1f, %.1f) 地面=%.2f 淨空3m=%.0f%% 淨空6m=%.0f%%" % [x, z, gy, cl, cl6])
		if gy != -INF and cl >= 90.0:
			best.append([z, x, gy, cl6])
		z -= 4.0
	print("[SPOT] ── 淨空 3 m 達 90% 的點，依 6 m 淨空排序 ──")
	best.sort_custom(func(a, b): return float(a[3]) > float(b[3]))
	for b in best.slice(0, 6):
		print("[SPOT] z=%.1f x=%.1f 地面=%.2f 淨空6m=%.0f%%" % [b[0], b[1], b[2], b[3]])
	quit(0)
