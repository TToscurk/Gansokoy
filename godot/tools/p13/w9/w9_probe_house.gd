extends SceneTree
## P13 W9 診断（唯読・headless）：町家 Kit の局部座標（正面壁・庇・軒・棟）と bay の並びを実測する。
##   godot --headless --path . --script res://tools/p13/w9/w9_probe_house.gd -- B_P_RSW_047 B_P_MKT_017 …
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await process_frame
	for nm: String in OS.get_cmdline_user_args():
		var b := v.get_node("Districts").find_child(nm, true, false) as Node3D
		if b == null:
			print("[PH] 無し ", nm)
			continue
		var kit := b.get_node("Kit")
		print("[PH] === %s pos=%s yaw=%.1f° meta: %s" % [nm, str(b.global_position), rad_to_deg(b.global_rotation.y), str(b.get_meta_list().map(func(k: String) -> String: return "%s=%s" % [k, str(b.get_meta(k))]))])
		print("[PH]   kit metas: ", str(kit.get_meta_list().map(func(k: String) -> String: return "%s=%s" % [k, str(kit.get_meta(k))])).substr(0, 600))
		var lod0 := kit.get_node("LOD0")
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		var groups := {}
		for mi in lod0.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			var a := g.transform * g.get_aabb()   # Kit 局部（LOD0 直下の子は identity 親と仮定）
			lo = lo.min(a.position)
			hi = hi.max(a.end)
			var pre := ""
			for ch in String(g.name):
				if ch.is_valid_int():
					break
				pre += ch
			if not groups.has(pre):
				groups[pre] = [Vector3(1e9, 1e9, 1e9), Vector3(-1e9, -1e9, -1e9), 0]
			groups[pre][0] = (groups[pre][0] as Vector3).min(a.position)
			groups[pre][1] = (groups[pre][1] as Vector3).max(a.end)
			groups[pre][2] += 1
		print("[PH]   LOD0 全体 局部 AABB x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f]" % [lo.x, hi.x, lo.y, hi.y, lo.z, hi.z])
		for pre: String in groups:
			var gg: Array = groups[pre]
			print("[PH]     %-8s n=%-3d x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f]" % [pre, gg[2], (gg[0] as Vector3).x, (gg[1] as Vector3).x, (gg[0] as Vector3).y, (gg[1] as Vector3).y, (gg[0] as Vector3).z, (gg[1] as Vector3).z])
	quit(0)
