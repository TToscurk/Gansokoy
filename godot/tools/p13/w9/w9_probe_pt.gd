extends SceneTree
## W9 診断：指定点の「置けない理由」と rootp／p10／meadow の命中（x,z を複数）
## godot --headless --path . --script res://tools/p13/w9/w9_probe_pt.gd -- <id> x,z [x,z ...]
const W9 := preload("res://tools/p13/w9/w9_lib.gd")


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var id: String = a[0]
	var v: Node3D = (load(W9.SCENE) as PackedScene).instantiate()
	root.add_child(v)
	var mp := PackedVector2Array()
	var cache := "C:/Users/B365/AppData/Local/hermes/cache/scratch/w9_meadow.json"
	if FileAccess.file_exists(cache):
		var arr: Array = JSON.parse_string(FileAccess.get_file_as_string(cache))
		for i in range(0, arr.size() - 1, 2):
			mp.append(Vector2(float(arr[i]), float(arr[i + 1])))
	var C := W9.context(v, mp)
	print("[PT] n_rootp=", C["n_rootp"], " bld=", (C["bld"] as Array).size(), " meadow pts=", mp.size())
	if a.size() > 1 and (a[1] as String).begins_with("grid="):
		# grid=x0,z0,w,h,step ：置けない理由の文字地図（id の足元で判定）
		var g := (a[1] as String).trim_prefix("grid=").split(",")
		var x0 := float(g[0]); var z0 := float(g[1]); var gw := float(g[2]); var gh := float(g[3]); var st := float(g[4])
		var code := {"": ".", "terrain": " ", "road": "R", "frontage": "F", "building": "B", "water": "W", "p7": "w", "bridge": "b", "hero": "H", "p8": "A", "sealed": "S", "trunk": "T",
			"env": "E", "p10": "P", "npc": "N", "backdoor": "d", "door": "D", "meadow": "g", "slope": "/", "r4": "r", "road_pad": "~"}
		print("[PT] 地図 x=%.1f.. 左→右 step %.2f、z 行 %.1f.." % [x0, st, z0])
		for j in int(gh / st) + 1:
			var zz := z0 + j * st
			var row := "%7.1f " % zz
			for i2 in int(gw / st) + 1:
				var xx := x0 + i2 * st
				var it2 := W9.item(C, id, Vector2(xx, zz), Vector2(1, 0), {})
				var w2 := W9.why(C, it2, [], "ground")
				if w2 == "" and W9.relief(C, it2) > W9.RELIEF_MAX:
					w2 = "slope"
				row += String(code.get(w2.split("(")[0].split(":")[0], "?"))
			print("[PT] ", row)
		quit()
		return
	for i in range(1, a.size()):
		var xz := (a[i] as String).split(",")
		var p := Vector2(float(xz[0]), float(xz[1]))
		var it := W9.item(C, id, p, Vector2(1, 0), {})
		var w := W9.why(C, it, [], "ground")
		var wl := W9.why(C, it, [], "wall")
		print("[PT] %s (%.1f,%.1f) ground='%s' wall='%s' rootp=%s p10=%s foot=%s top=%.2f" % [id, p.x, p.y, w, wl, W9._hit(C["rootp_g"], p), W9._hit(C["p10_g"], p), str(W9.foot(it)), W9.top_h(C, p)])
	quit()
