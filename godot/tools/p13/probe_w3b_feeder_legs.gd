extends SceneTree
## P13 W3B：竜骨車の送り樋の脚・落とし桝が T0 の木槽の頭（s＝0）から何 m の所にあるかを測る（唯讀、headless 可）
const SCENE := "res://maps/village_v2/gen/farmland_p8.scn"
const FLib := preload("res://tools/village_v2_farmland_lib.gd")
const ZLib := preload("res://tools/village_v2_farmland_zone.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var P: Dictionary = FLib.plan()
	var line := PackedVector2Array()
	for br: Dictionary in P["zone"]["branches"]:
		if br["id"] == "T0":
			line = br["runs"][0]["line"]
	print("T0 run0 の頭 ", line[0], " 方向 ", FLib.at_s(line, 0.0)[1])
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	await process_frame
	for path in ["FieldDetails/WaterSupply/Ryukotsu/Post_FeedLeg_0_0", "FieldDetails/WaterSupply/Ryukotsu/Post_FeedLeg_0_1", "FieldDetails/WaterSupply/Ryukotsu/Post_FeedLeg_1_0",
			"FieldDetails/WaterSupply/Ryukotsu/Post_FeedLeg_1_1", "FieldDetails/WaterSupply/Ryukotsu/Feed/Body", "FieldDetails/WaterSupply/DropBox"]:
		var n := v.get_node_or_null(path) as Node3D
		if n == null:
			print(path, " なし")
			continue
		var ab := AABB()
		var first := true
		for mi in ([n] if n is MeshInstance3D else n.find_children("*", "MeshInstance3D", true, false)):
			var a: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			ab = a if first else ab.merge(a)
			first = false
		var c := Vector2(ab.get_center().x, ab.get_center().z)
		var s := FLib.project_s(line, c)
		var cl: Vector2 = FLib.at_s(line, s)[0]
		print("%-60s AABB x %.2f–%.2f z %.2f–%.2f y %.2f–%.2f  中心の T0 s=%.2f 横ずれ %.2f" % [path.get_file(), ab.position.x, ab.end.x, ab.position.z, ab.end.z, ab.position.y, ab.end.y, s, c.distance_to(cl)])
	quit(0)
