extends SceneTree
## P13 W7 診断（唯読・headless）：名前に pat を含む節点の可視・位置・子の MeshInstance 数。
##   godot --headless --path . --script res://tools/p13/w7/w7_probe_nodes.gd -- <pattern> [<pattern2> ...]
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var pats := OS.get_cmdline_user_args()
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 8:
		await process_frame
	for pat in pats:
		var hits := v.find_children("*" + pat + "*", "Node3D", true, false)
		print("[W7N] pattern ", pat, " → ", hits.size())
		for h in hits.slice(0, 14):
			var n3 := h as Node3D
			var meshes := n3.find_children("*", "MeshInstance3D", true, false).size()
			print("[W7N]   ", v.get_path_to(n3), "  visible_in_tree=", n3.is_visible_in_tree(), "  pos=", n3.global_position.snapped(Vector3(0.1, 0.1, 0.1)), "  meshes=", meshes)
	quit(0)
