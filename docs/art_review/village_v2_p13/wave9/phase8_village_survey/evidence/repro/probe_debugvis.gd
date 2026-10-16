extends SceneTree
## 唯讀：正式流程（非 ReviewStart）載入人間之里時，Debug／QuestAnchors／Portals 是否可見。
##   godot --headless --path godot --script probe_debugvis.gd -- --map=village_v2
func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var m: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	current_scene = m
	for i in 30:
		await process_frame
	var v: Node = null
	for n in root.find_children("*", "", true, false):
		if n.name == "VillageV2":
			v = n
			break
	if v == null:
		print("[DBG] VillageV2 not found")
		quit(1)
		return
	for nm in ["Debug", "QuestAnchors", "Portals", "Districts/LandmarkParcelLines", "Districts/AuxParcelLines"]:
		var n := v.get_node_or_null(nm)
		if n == null:
			print("[DBG] %-32s missing" % nm)
			continue
		var lab := 0
		var mi := 0
		for d in n.find_children("*", "", true, false):
			if d is Label3D and (d as Node3D).is_visible_in_tree():
				lab += 1
			elif d is MeshInstance3D and (d as Node3D).is_visible_in_tree():
				mi += 1
		print("[DBG] %-32s visible_in_tree=%s  visible Label3D=%d  visible MeshInstance3D=%d" % [nm, (n as Node3D).is_visible_in_tree(), lab, mi])
	var dn := v.get_node_or_null("Debug")
	if dn:
		for d in dn.find_children("*", "MeshInstance3D", true, false):
			print("[DBG]   mesh ", v.get_path_to(d), " ", (d as MeshInstance3D).mesh.get_class() if (d as MeshInstance3D).mesh else "null", " vis=", (d as Node3D).is_visible_in_tree())
		var k := 0
		for d in dn.find_children("*", "Label3D", true, false):
			if k < 8:
				print("[DBG]   label ", v.get_path_to(d), " text=", (d as Label3D).text.replace("\n", " "), " pos=", (d as Node3D).global_position.round())
			k += 1
	quit(0)
