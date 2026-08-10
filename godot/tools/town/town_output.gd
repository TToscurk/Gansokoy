extends RefCounted

## Deterministic serialization for Human Village validation artifacts.


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
