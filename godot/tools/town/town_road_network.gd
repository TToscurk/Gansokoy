extends RefCounted


static func build(
		roads: Array,
		river: PackedVector2Array,
		main_ew_width: float,
		bank_path: float,
		nearest_river_point: Callable) -> void:
	roads.append({"pts": [Vector2(0, -240), Vector2(0, 250)], "w": 8.0})
	roads.append({
		"pts": [Vector2(-190, 30), Vector2(200, 30)],
		"w": main_ew_width,
	})
	for spec in [[-135.0, false], [-80.0, true], [85.0, false], [140.0, true]]:
		var z: float = spec[0]
		var bridged: bool = spec[1]
		var nearest: Vector2 = nearest_river_point.call(Vector2(0, z))
		var river_x := nearest.x
		for point in river:
			if absf(point.y - z) < 2.5:
				river_x = point.x
				break
		if bridged:
			roads.append({
				"pts": [Vector2(-150, z), Vector2(150, z)], "w": 5.0})
		else:
			roads.append({
				"pts": [Vector2(-150, z), Vector2(river_x - bank_path, z)],
				"w": 5.0,
			})
			roads.append({
				"pts": [Vector2(river_x + bank_path, z), Vector2(150, z)],
				"w": 5.0,
			})
	for x in [-156.0, 104.0]:
		roads.append({
			"pts": [Vector2(x, -190), Vector2(x, 195)], "w": 4.5})
	for x in [-104.0, -52.0]:
		roads.append({
			"pts": [Vector2(x, -130), Vector2(x, 195)], "w": 4.5})
	roads.append({"pts": [Vector2(52, -190), Vector2(52, 118)], "w": 4.5})
	roads.append({"pts": [Vector2(-104, 92), Vector2(-172, 92)], "w": 4.0})
	roads.append({"pts": [Vector2(0, -240), Vector2(0, -215)], "w": 6.0})
