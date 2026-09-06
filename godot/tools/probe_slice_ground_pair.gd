extends SceneTree
## check_map 把 slice 的 11 個水面全報成「100% 埋在地下」，但實拍看得到水。
## 這支比對兩個地面網格在水路一帶的高度，確認誤報來源。
##
##   Godot --headless --path godot --script tools/probe_slice_ground_pair.gd
##
## slice 有兩個地面 MeshInstance3D：
##   Terrain        — 舊地形（水路重做前，河床還沒挖）
##   UnifiedGround  — 統一地面（gen_terrain_river.gd 產出，含河床）
## check_map 的 _build_height_field() 只 find_child("Terrain")，
## 所以拿舊地形當基準，水面當然全部「低於地面」。

func _init() -> void:
	var ps := load("res://maps/slice/slice.tscn") as PackedScene
	var root := ps.instantiate() as Node3D
	var pairs := {}
	for name in ["Terrain", "UnifiedGround"]:
		var mi := root.find_child(name, true, false) as MeshInstance3D
		if mi == null or mi.mesh == null:
			print("[PAIR] %s：找不到或沒有 mesh" % name)
			continue
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var xf := mi.global_transform if mi.is_inside_tree() else mi.transform
		var grid := {}
		for v in vs:
			var w: Vector3 = xf * v
			var c := Vector2i(int(floor(w.x / 4.0)), int(floor(w.z / 4.0)))
			if not grid.has(c) or grid[c] > w.y:
				grid[c] = w.y
		pairs[name] = grid
		print("[PAIR] %-14s 頂點 %6d  格數 %5d" % [name, vs.size(), grid.size()])

	# check_map 報的最深點，逐一比對兩份地面
	var spots := [
		[281, 50, "UpstreamWater"], [293, -28, "DownstreamWater"],
		[293, 33, "WeirDrop"], [282, 34, "WheelRaceWater"],
		[281, -51, "Reach_Lower"], [281, 61, "Reach_Upper"],
		[301, 22, "FeederWater"],
	]
	print("[PAIR] %-18s %10s %14s %10s" % ["位置", "Terrain", "UnifiedGround", "差"])
	for s in spots:
		var c := Vector2i(int(floor(float(s[0]) / 4.0)), int(floor(float(s[1]) / 4.0)))
		var a: Variant = pairs.get("Terrain", {}).get(c)
		var b: Variant = pairs.get("UnifiedGround", {}).get(c)
		var sa := "%.2f" % a if a != null else "(無)"
		var sb := "%.2f" % b if b != null else "(無)"
		var sd := "%+.2f" % (float(b) - float(a)) if (a != null and b != null) else "-"
		print("[PAIR] %-18s %10s %14s %10s" % ["%s (%d,%d)" % [s[2], s[0], s[1]], sa, sb, sd])
	root.free()
	quit(0)
