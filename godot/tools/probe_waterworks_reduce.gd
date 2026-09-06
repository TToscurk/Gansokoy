extends SceneTree
## 開刀前的事實確認：
##   1. 牆_01 / 牆_05 的 mesh_node 與 mesh_node2 是不是逐頂點相同的重複網格？
##   2. 田泵水口_南 / 分水堰 玩家到底走不走得到？凸包取代會不會封住該通過的洞？
##
##   Godot --headless --path godot --script tools/probe_waterworks_reduce.gd

const SRC := "res://maps/slice/slice.tscn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load(SRC)
	var src := packed.instantiate()

	# ── 1. 重複網格 ──
	print("[RED] === 重複網格檢查 ===")
	for wall in ["牆_01", "牆_05", "牆_S1", "牆_N1"]:
		var g := src.get_node_or_null("MachiCanal/VillageStoneBank/%s" % wall)
		if g == null:
			continue
		var kids: Array = []
		for c in g.get_children():
			if c is MeshInstance3D:
				kids.append(c)
		var desc := PackedStringArray()
		for k in kids:
			var f := (k as MeshInstance3D).mesh.get_faces()
			var xf := (k as MeshInstance3D).transform
			var h := 0.0
			for v in f:
				h += v.x * 1.0 + v.y * 3.0 + v.z * 7.0
			desc.append("%s(面%d 雜湊%.3f 位移%s 資源%s)" % [
				k.name, f.size() / 3, h, xf.origin,
				(k as MeshInstance3D).mesh.resource_path.get_file()])
		print("[RED] %s -> %d 個網格：%s" % [wall, kids.size(), " | ".join(desc)])

	# ── 2. 凸包 vs 三角網：形狀差多少 ──
	print("[RED] === 凸包取代的形狀誤差 ===")
	for path in ["MachiCanal/Waterworks/田泵水口_南/output_unwrapped",
			"MachiCanal/Waterworks/分水堰/output_unwrapped",
			"MachiCanal/Waterworks/石造堰檻/mesh_node",
			"MachiCanal/Waterworks/水車/mesh_node"]:
		var mi := src.get_node_or_null(path) as MeshInstance3D
		if mi == null:
			print("[RED] 找不到 %s" % path)
			continue
		var m: Mesh = mi.mesh
		var faces := m.get_faces()
		var hull_pts := m.create_convex_shape(true, false).points
		# 體積比：凸包會填滿凹處，比值愈接近 1 代表原本就近似凸體，換掉最安全。
		var aabb := m.get_aabb()
		print("[RED] %-42s 三角面 %6d → 凸包 %3d 點；AABB %s" % [
			path.get_file() if path.get_file() != "mesh_node" else path,
			faces.size() / 3, hull_pts.size(), aabb.size])

	# ── 3. 玩家可達性：這兩個裝飾物頭頂與周邊的地面高度 ──
	print("[RED] === 玩家可達性（村道地面 y≈0.36，水路底 y≈-3.1）===")
	var main_packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	var main := main_packed.instantiate()
	root.add_child(main)
	await process_frame
	main.load_map("slice", "")
	for i in 6:
		await physics_frame
	var space: PhysicsDirectSpaceState3D = main.map_root.get_world_3d().direct_space_state
	var mask: int = main.player.collision_mask
	for probe in [
			{"n": "田泵水口_南 正上方", "xz": Vector2(291.5, -16.0)},
			{"n": "分水堰 正上方", "xz": Vector2(282.5, 34.0)},
			{"n": "石造堰檻 正上方", "xz": Vector2(288.0, 34.0)},
			{"n": "水車 正上方", "xz": Vector2(283.0, 30.0)},
			{"n": "親水階梯 中段", "xz": Vector2(281.0, -3.0)},
			{"n": "村道（對照）", "xz": Vector2(276.0, 30.0)}]:
		var xz: Vector2 = probe["xz"]
		var q := PhysicsRayQueryParameters3D.create(
			Vector3(xz.x, 60.0, xz.y), Vector3(xz.x, -60.0, xz.y), mask)
		var hit := space.intersect_ray(q)
		var who := "無"
		var y := NAN
		if not hit.is_empty():
			y = hit["position"].y
			var c: Node = hit["collider"]
			who = "%s/%s" % [c.get_parent().name if c.get_parent() else "", c.name]
		print("[RED] %-20s 落點 y=%7s  命中 %s" % [
			probe["n"], "無" if is_nan(y) else "%.2f" % y, who])

	src.free()
	print("[RED] done")
	quit(0)
