extends SceneTree
## 圍牆選址勘查：候選線上的地面高度、既有結構、以及玩家動線。
##
##   Godot --headless --path godot --script tools/probe_wall_site.gd
##
## 為什麼要先量：圍牆是長條結構，只要地面沿線起伏超過牆體能吸收的量，
## 就會出現「一端埋進土裡、另一端浮空」。這支沿候選線每 2 m 取一次地面高度，
## 把起伏量、以及該線會不會撞到既有建物，一次講清楚。

const SAMPLE_STEP := 2.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	main.load_map("slice", "")
	for i in 8:
		await physics_frame
	var space: PhysicsDirectSpaceState3D = main.map_root.get_world_3d().direct_space_state
	var mask: int = main.player.collision_mask

	# 先問一個基本問題：村子的實際邊界在哪？沿幾條線掃地面，找出
	# 「村內平地」與「外圍」的分界。
	print("[SITE] === 北端東西向掃描（z 固定，x 變動）===")
	for z in [80.0, 90.0, 93.8, 100.0, 110.0]:
		_scan_line(space, mask, Vector3(180.0, 0, z), Vector3(340.0, 0, z),
			"z=%.0f" % z)

	print("[SITE] === 南端東西向掃描 ===")
	for z in [-150.0, -160.0, -170.0]:
		_scan_line(space, mask, Vector3(180.0, 0, z), Vector3(340.0, 0, z),
			"z=%.0f" % z)

	print("[SITE] === 西側南北向掃描（x 固定）===")
	for x in [190.0, 200.0, 210.0]:
		_scan_line(space, mask, Vector3(x, 0, -160.0), Vector3(x, 0, 100.0),
			"x=%.0f" % x)

	print("[SITE] === 東側南北向掃描 ===")
	for x in [330.0, 350.0, 370.0]:
		_scan_line(space, mask, Vector3(x, 0, -160.0), Vector3(x, 0, 100.0),
			"x=%.0f" % x)

	print("[SITE] done")
	quit(0)


func _scan_line(space: PhysicsDirectSpaceState3D, mask: int,
		a: Vector3, b: Vector3, label: String) -> void:
	var n := int(a.distance_to(b) / SAMPLE_STEP)
	var ys := PackedFloat64Array()
	var holes := 0
	var hits := {}
	for i in range(n + 1):
		var p := a.lerp(b, float(i) / float(n))
		var q := PhysicsRayQueryParameters3D.create(
			Vector3(p.x, 60.0, p.z), Vector3(p.x, -40.0, p.z), mask)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			holes += 1
			continue
		ys.append(hit["position"].y)
		var c: Node = hit["collider"]
		var nm := String(c.name)
		hits[nm] = hits.get(nm, 0) + 1
	if ys.is_empty():
		print("[SITE] %-8s 全線無地面" % label)
		return
	var lo := ys[0]
	var hi := ys[0]
	var sum := 0.0
	for y in ys:
		lo = minf(lo, y)
		hi = maxf(hi, y)
		sum += y
	# 命中最多的三個表面，看這條線壓在什麼東西上
	var names: Array = hits.keys()
	names.sort_custom(func(p, q): return hits[p] > hits[q])
	var top := PackedStringArray()
	for i in mini(3, names.size()):
		top.append("%s×%d" % [names[i], hits[names[i]]])
	print("[SITE] %-8s 地面 %.2f~%.2f（起伏 %.2f m，均 %.2f）洞 %d  %s" % [
		label, lo, hi, hi - lo, sum / ys.size(), holes, ", ".join(top)])
