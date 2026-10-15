extends SceneTree
## W9 R3 唯読 probe：対象建築の前（壁から 3 m・左右 ±0.5 m・高さ 0–3 m）にある『他 overlay の実体』を局部座標で列挙する。
##   godot --headless --path godot --script res://tools/p13/w9/w9r3_probe_occ.gd -- B_P_MKT_025 ...
## MultiMesh は headless では読めない（instance transform が 0）ので、MultiMeshInstance3D は名前だけ出す。
func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var ids: Array = OS.get_cmdline_user_args()
	var vil := (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(vil)
	for i in 3:
		await process_frame
	for id in ids:
		var body := vil.find_child(String(id), true, false) as Node3D
		if body == null:
			print("[OCC] %s 無し" % id)
			continue
		var shp := body.get_node("Shape") as CollisionShape3D
		var w := (shp.shape as BoxShape3D).size.x
		var d := (shp.shape as BoxShape3D).size.z
		var zf := d / 2.0
		var inv := body.global_transform.affine_inverse()
		print("[OCC] === %s  w=%.2f d=%.2f zf=%.2f" % [id, w, d, zf])
		var zone := AABB(Vector3(-w / 2.0 - 0.5, 0.0, zf - 0.2), Vector3(w + 1.0, 3.0, 3.2))
		var mm_names := {}
		var found := 0
		for n in vil.find_children("*", "VisualInstance3D", true, false):
			var top := String(vil.get_path_to(n)).get_slice("/", 0)
			if top == "Terrain" or top == "Districts" and String(vil.get_path_to(n)).contains(String(id)):
				continue
			if n is MultiMeshInstance3D:
				var p2 := String(vil.get_path_to(n)).get_slice("/", 0)
				mm_names[p2] = true
				continue
			if not (n is MeshInstance3D):
				continue
			if not (n as Node3D).is_visible_in_tree():
				continue
			var g := (n as MeshInstance3D).get_aabb()
			if g.size == Vector3.ZERO:
				continue
			var lb := inv * ((n as Node3D).global_transform * g)
			if lb.size.length() > 12.0:
				continue
			if zone.intersects(lb):
				found += 1
				if found <= 40:
					var pth := String(vil.get_path_to(n))
					print("[OCC]   %s  local x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f" % [pth.substr(0, 90), lb.position.x, lb.end.x, lb.position.y, lb.end.y, lb.position.z, lb.end.z])
		print("[OCC]   （MultiMesh を持つ overlay：%s）" % ", ".join(PackedStringArray(mm_names.keys())))
	quit(0)
