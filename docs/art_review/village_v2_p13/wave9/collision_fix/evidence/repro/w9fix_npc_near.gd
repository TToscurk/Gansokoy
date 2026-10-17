extends SceneTree
## 一時：MXC_004 の戸口（局部 1.32, 5.46）から 12 m 以内の NPC（Population の体）・Area3D・互動ノード（唯讀）
const L := preload("res://tools/p13/w9/w9r2_lib.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v := (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await process_frame
	var b4 := v.get_node(NodePath(String(L.SPECS["B_P_MXC_004"]["path"]))) as Node3D
	var door := b4.global_transform * Vector3(1.32, 0, 5.46)
	var n_all := 0
	for n in v.find_children("*", "Node3D", true, false):
		var p := String(v.get_path_to(n))
		var is_pop := p.begins_with("Population") and (n is CharacterBody3D or n is AnimatableBody3D or n is RigidBody3D)
		var is_area := n is Area3D
		var has_int := n.has_method("interact") or n.has_method("_on_interact") or n.is_in_group("interactable") or n.is_in_group("npc")
		if not (is_pop or is_area or has_int):
			continue
		n_all += 1
		var d := (n as Node3D).global_position.distance_to(door)
		if d < 12.0:
			print("[W9NPC] %s（%s）距離 %.2f m%s" % [p, n.get_class(), d, "・互動" if has_int else ""])
	print("[W9NPC] 対象ノード総数 %d（Population の体・Area3D・互動）" % n_all)
	quit(0)
