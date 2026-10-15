extends "res://tools/p13/w6/w6_base.gd"
## 診断（唯読）：指定地点に玩家を置き、実際の SpringArm3D の長さと『腕が当たっているもの』を出す。
##   godot --path . --script res://tools/p13/w9/diag_arm.gd -- <x> <z> <fx> <fz> [--disable=EnrichW9P3,ArchW9R2P13]
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var p := Vector2(float(args[0]), float(args[1]))
	var f := Vector2(float(args[2]), float(args[3]))
	var disables: Array = []
	for a: String in args:
		if a.begins_with("--disable="):
			disables.append_array(a.trim_prefix("--disable=").split(",", false))
	out = ""
	await _boot()
	for dn: String in disables:
		var dnode := vil.get_node_or_null(NodePath(dn))
		if dnode != null:
			if "enabled" in dnode:
				dnode.set("enabled", false)
			else:
				vil.remove_child(dnode)
				dnode.queue_free()
	await _frames(8)
	await _tpw(p, f.normalized())
	await _frames(20)
	var arm := player.get_node("Pivot/SpringArm3D") as SpringArm3D
	var o := arm.global_position
	var dir := arm.global_transform.basis.z.normalized()
	print("[ARM] disabled=%s player=(%.2f, %.2f, %.2f) arm_origin=(%.2f, %.2f, %.2f) dir=(%.3f, %.3f, %.3f) spring_length=%.2f hit_length=%.3f margin=%.2f mask=%d" % [str(disables), player.global_position.x, player.global_position.y, player.global_position.z, o.x, o.y, o.z, dir.x, dir.y, dir.z, arm.spring_length, arm.get_hit_length(), arm.margin, arm.collision_mask])
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(o, o + dir * arm.spring_length, arm.collision_mask, [player.get_rid()])
	var r := space.intersect_ray(q)
	if r.is_empty():
		print("[ARM] ray: 何にも当たらない")
	else:
		var col := r["collider"] as Node
		var cs := col.get_path() if col != null else NodePath("")
		var pos: Vector3 = r["position"]
		print("[ARM] ray hit %.3f m  collider=%s  pos=(%.2f, %.2f, %.2f)" % [o.distance_to(pos), str(cs), pos.x, pos.y, pos.z])
		var par := col.get_parent() if col != null else null
		while par != null and par != vil.get_parent():
			print("[ARM]    ↑ %s (%s)" % [par.name, par.get_class()])
			par = par.get_parent()
			if par == vil:
				break
	quit(0)
