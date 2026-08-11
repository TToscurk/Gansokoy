extends RefCounted

## Deterministic serialization for Human Village validation artifacts.


static func save_scene(root: Node3D, out_dir: String, map_id: String) -> void:
	var packed := PackedScene.new()
	packed.pack(root)
	var error := ResourceSaver.save(packed, out_dir + "%s.tscn" % map_id)
	print("saved %s.tscn err=%d  節點 %d" % [
		map_id, error, _count_nodes(root)])


static func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count


static func build_portals(height_at: Callable, nearest_river_point: Callable,
		river: PackedVector2Array, bank_path: float) -> Array:
	## portals[0] 必須是北門：main.gd 的 _place_player 在 from_id=="" 時
	## 落在 portals[0]，所以 `--map=village` 會站在本通上而不是村角。
	## y 由 height_at 量出來，不手抄 —— 地形換了數值就會變。
	##
	## Stage 2 回程落點由目的地圖中 target == from_id 的 portal 決定；
	## 舊 village 的兩個座標與這裡相同，所以既有回程落點不變。
	return [
		{"x": 0.0, "y": snappedf(height_at.call(0, -174), 0.01),
			"z": -174.0, "target": "trail"},
		{"x": -132.0, "y": snappedf(height_at.call(-132, 100), 0.01),
			"z": 100.0, "target": "kourindou"},
		# 河畔道北端出圖 → 未來的霧之湖。target 留 null = 保留中的觸發區。
		_bank_portal(-286.0, height_at, nearest_river_point, river, bank_path),
		# 稗田邸玄関前 → 室內一樓。石階腳在世界 z=-166.6，portal 再往
		# 參道外挪 2m，站在階前而不是階上。建築內部不進世界圖 connections。
		{"x": -78.05,
			"y": snappedf(height_at.call(-78.05, -164.6), 0.01),
			"z": -164.6, "target": "hieda1f"},
	]


static func _bank_portal(z: float, height_at: Callable,
		nearest_river_point: Callable, river: PackedVector2Array,
		bank_path: float) -> Dictionary:
	## x 要用該 z 的河道最近點算，不能拿任意樣條索引。
	var nearest: Vector2 = nearest_river_point.call(Vector2(0, z))
	var best := nearest
	var best_distance := 1e18
	for point in river:
		var distance: float = absf(point.y - z)
		if distance < best_distance:
			best_distance = distance
			best = point
	var x: float = best.x - bank_path
	return {"x": snappedf(x, 0.1),
		"y": snappedf(height_at.call(x, z), 0.01),
		"z": z, "target": null}


static func write_meta(map_id: String, portals: Array) -> void:
	var meta := {
		"id": map_id,
		"note": "人間之里（街區重設計版，gen_town.gd 產出）。整合 Stage 2 起"
			+ "這支取代了 gen_village.gd 的佈局；地標內容／草層／動物等"
			+ "MIGRATE 項目逐步搬入中。gen_village.gd 不可再執行。",
		"playSize": [460, 460],
		"safe": true,
		"connections": ["trail", "kourindou", "myouren", "lake"],
		"portals": portals,
		"colliders": [],
	}
	var file := FileAccess.open("res://data/%s.meta.json" % map_id, FileAccess.WRITE)
	file.store_string(JSON.stringify(meta, " "))
	file.close()
	print("wrote data/%s.meta.json" % map_id)


static func write_instance_dump(map_id: String, river: PackedVector2Array,
		instances: Array, density: Array) -> void:
	var output := {
		"note": "人間之里擺位表（gen_town.gd 產出，驗證腳本用）",
		"river": [],
		"instances": instances,
		"density": density,
	}
	for point in river:
		output["river"].append([snappedf(point.x, 0.01), snappedf(point.y, 0.01)])
	var file := FileAccess.open("res://data/%s.instances.json" % map_id, FileAccess.WRITE)
	file.store_string(JSON.stringify(output, " "))
	file.close()
	print("wrote data/%s.instances.json（%d 實例）" % [map_id, instances.size()])
