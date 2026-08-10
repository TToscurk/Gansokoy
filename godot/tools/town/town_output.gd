extends RefCounted

## Deterministic serialization for Human Village validation artifacts.


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
