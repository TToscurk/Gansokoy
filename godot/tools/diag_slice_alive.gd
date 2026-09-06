extends SceneTree
## 場景回來了嗎？數給你看：載入 slice，統計樹/草/橋/運河實體數。

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.load_map("slice", "")
	for i in 40:
		await physics_frame
		await process_frame
	var mr: Node3D = main.map_root

	var counts := {}
	var trees := 0
	var grass := 0
	var meshes := 0
	var multimesh_total := 0
	for n in mr.find_children("*", "Node3D", true, false):
		var nm := String(n.name)
		if "VillageTrees" in nm and n.visible:
			trees += 1
		if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
			grass += 1
			multimesh_total += (n as MultiMeshInstance3D).multimesh.instance_count
		if n is MeshInstance3D:
			meshes += 1
	var canal := mr.get_node_or_null("B2_Canal") != null
	var street := mr.get_node_or_null("B1_Street") != null
	var lamps := mr.find_children("*LAMP*", "Node3D", true, false).size() \
		+ mr.find_children("*路燈*", "Node3D", true, false).size()
	print("[ALIVE] 根節點子數=%d  MeshInstance=%d  VillageTrees=%d  MultiMesh=%d(實例 %s)  燈=%d  B2_Canal=%s  B1_Street=%s"
		% [mr.get_child_count(), meshes, trees, grass, JSON.stringify(multimesh_total), lamps,
			str(canal), str(street)])
	var ok := trees >= 5 and grass >= 4 and canal and street and meshes > 3000
	print("[ALIVE] %s" % ("場景完整回來了" if ok else "還是少了東西"))
	quit(0 if ok else 1)
