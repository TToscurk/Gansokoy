extends SceneTree
## P13 W8 診断（唯読・headless）：町家 Kit の各 LOD 群の部品について visibility_range の組（begin,end,margin,fade）の分布を出す。
##   godot --headless --path . --script res://tools/p13/w8/w8_probe_kit_ranges.gd -- B_P_MKT_032 [B_P_SGT_002 …]
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 6:
		await process_frame
	for id: String in OS.get_cmdline_user_args():
		var b := v.get_node("Districts").find_child(id, true, false)
		if b == null:
			print("[W8K] not found ", id)
			continue
		var kit := b.get_node("Kit")
		print("[W8K] ", id, "  Kit 直下の子: ", kit.get_children().map(func(c): return String(c.name) + ":" + c.get_class()))
		for k in 3:
			var lod := kit.get_node("LOD%d" % k)
			var hist := {}
			var ex := {}
			for g in lod.find_children("*", "GeometryInstance3D", true, false):
				var gi := g as GeometryInstance3D
				var key := "[%.0f,%.0f] mb=%.0f me=%.0f fade=%d" % [gi.visibility_range_begin, gi.visibility_range_end, gi.visibility_range_begin_margin, gi.visibility_range_end_margin, gi.visibility_range_fade_mode]
				hist[key] = int(hist.get(key, 0)) + 1
				if not ex.has(key):
					ex[key] = String(gi.name)
			for key: String in hist:
				print("[W8K]   LOD%d  %s  ×%d  例 %s" % [k, key, hist[key], ex[key]])
		# LOD 群ノード自身
		for k in 3:
			var lod2 := kit.get_node("LOD%d" % k)
			print("[W8K]   LOD%d 群 class=%s visible=%s" % [k, lod2.get_class(), str(lod2.get("visible"))])
	quit(0)
