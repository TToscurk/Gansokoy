extends SceneTree
## W9 R2 唯讀 probe：選定建築的 Kit 節點結構（LOD0 子節點名、AABB）、Frontage 子節點、body 同層節點。
##   godot --headless --path godot --script res://tools/p13/w9/w9r2_probe_kit.gd -- B_P_MKT_012 B_P_RSW_047
func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var ids: Array = OS.get_cmdline_user_args()
	var vil := (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(vil)
	await process_frame
	for id in ids:
		var body := vil.find_child(String(id), true, false) as Node3D
		if body == null:
			print("[R2P] %s: 找不到" % id)
			continue
		print("[R2P] === %s  path=%s  xf.origin=%s yaw=%.1f" % [id, vil.get_path_to(body), body.global_transform.origin, rad_to_deg(body.global_transform.basis.get_euler().y)])
		for c in body.get_children():
			print("[R2P]   child %s (%s) vis=%s" % [c.name, c.get_class(), (c as Node3D).visible if c is Node3D else "-"])
		var kit := body.get_node_or_null("Kit")
		if kit != null:
			for lod in ["LOD0", "LOD1", "LOD2"]:
				var g := kit.get_node(lod)
				var names := {}
				for mi in g.get_children():
					var nm := String(mi.name)
					var key := nm.rstrip("0123456789@")
					names[key] = int(names.get(key, 0)) + 1
				var ks := names.keys()
				ks.sort()
				var line := ""
				for k in ks:
					line += "%s×%d " % [k, names[k]]
				print("[R2P]   Kit/%s %d 子：%s" % [lod, g.get_child_count(), line.substr(0, 1400)])
			for m in kit.get_meta_list():
				var v = kit.get_meta(m)
				print("[R2P]   Kit.meta %s = %s" % [m, str(v).substr(0, 200)])
		var fr := body.get_node_or_null("Frontage")
		if fr != null:
			var fl := ""
			for c in fr.get_children():
				fl += "%s " % c.name
			print("[R2P]   Frontage %d 子：%s" % [fr.get_child_count(), fl.substr(0, 400)])
		for c in body.get_children():
			if c is CollisionShape3D:
				var sh := (c as CollisionShape3D).shape
				print("[R2P]   Collision %s %s pos=%s" % [c.name, (sh as BoxShape3D).size if sh is BoxShape3D else sh, (c as Node3D).position])
	quit()
