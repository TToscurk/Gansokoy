extends SceneTree
## 一時：overlay .scn を読み、ノード（パス・型・transform・meta・碰撞形状）を 1 行ずつ出す（BEFORE／AFTER の diff 用）。
func _init() -> void:
	var path := OS.get_cmdline_user_args()[0]
	var ps := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var r := ps.instantiate()
	_dump(r, "")
	r.free()
	quit(0)


func _dump(n: Node, pre: String) -> void:
	var p := pre + "/" + String(n.name)
	var s := "%s %s" % [p, n.get_class()]
	if n is Node3D:
		s += " xf=%s vis=%s" % [str((n as Node3D).transform), (n as Node3D).visible]
	for m in n.get_meta_list():
		s += " %s=%s" % [m, str(n.get_meta(m))]
	if n is MeshInstance3D:
		s += " mesh=%s" % (n as MeshInstance3D).mesh.resource_path
	if n is CollisionObject3D:
		s += " layer=%d mask=%d" % [(n as CollisionObject3D).collision_layer, (n as CollisionObject3D).collision_mask]
	if n is CollisionShape3D:
		s += " dis=%s shape=%s" % [(n as CollisionShape3D).disabled, str(((n as CollisionShape3D).shape as BoxShape3D).size) if (n as CollisionShape3D).shape is BoxShape3D else "?"]
	print(s)
	for c in n.get_children():
		_dump(c, p)
