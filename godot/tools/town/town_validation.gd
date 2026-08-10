extends RefCounted

const TownGeometry := preload("res://tools/town/town_geometry.gd")


static func assert_no_overlap(dump: Array, modules: Dictionary, audit: Array[String]) -> void:
	## Pairwise OBB/SAT validation for houses, bridges and the riverside restaurant.
	var rects: Array = []
	for entry in dump:
		rects.append(TownGeometry.obb_of(entry, modules))
	var cell := 26.0
	var grid := {}
	for i in rects.size():
		var center: Vector2 = rects[i][0]
		var radius: float = maxf(rects[i][3], rects[i][4])
		var span := int(ceil(radius / cell))
		var grid_x := int(floor(center.x / cell))
		var grid_z := int(floor(center.y / cell))
		for dx in range(-span - 1, span + 2):
			for dz in range(-span - 1, span + 2):
				var key := "%d,%d" % [grid_x + dx, grid_z + dz]
				if not grid.has(key):
					grid[key] = []
				grid[key].append(i)
	var bad := 0
	var seen := {}
	for key in grid:
		var ids: Array = grid[key]
		for ii in ids.size():
			for jj in range(ii + 1, ids.size()):
				var i: int = ids[ii]
				var j: int = ids[jj]
				var pair_key := "%d_%d" % [min(i, j), max(i, j)]
				if seen.has(pair_key):
					continue
				seen[pair_key] = true
				var depth := TownGeometry.penetration(rects[i], rects[j])
				if depth > 0.05:
					bad += 1
					if bad <= 8:
						push_error("重疊：%s#%d × %s#%d 穿插 %.2fm"
							% [rects[i][5], i, rects[j][5], j, depth])
	if bad == 0:
		audit.append("重疊檢查：%d 件（町家＋橋＋鯢吞亭，含出簷 OBB）—— 0 穿插 ✓"
			% rects.size())
	else:
		audit.append("⚠ 重疊檢查：%d 對穿插 —— 佈局有 bug" % bad)
