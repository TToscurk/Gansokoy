extends SceneTree
## W9 診断：町家の正面の壁から外へ、各開間の中心で「何が最初に来るか」（road／frontage／p10／r4／npc …）の距離。
## godot --headless --path . --script res://tools/p13/w9/w9_probe_front.gd -- <名前接頭 例 B_P_MKT_> [step]
const W9 := preload("res://tools/p13/w9/w9_lib.gd")


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var pre: String = a[0] if a.size() > 0 else "B_P_MKT_"
	var v: Node3D = (load(W9.SCENE) as PackedScene).instantiate()
	root.add_child(v)
	var C := W9.context(v, PackedVector2Array())
	var names: Array = []
	for b: Dictionary in C["bld"]:
		if String(b["name"]).begins_with(pre):
			names.append(String(b["name"]))
	names.sort()
	for nm: String in names:
		var b := W9.bld(C, nm)
		var line := "%s %s w=%.1f d=%.1f door_cx=%.2f rec=%.2f |" % [nm, b["type"], b["w"], b["d"], b["door_cx"], float((C["bld_rec"] as Dictionary).get(nm, [0, 0])[0])]
		for e: Dictionary in W9.bays(b):
			var cx := (float(e["x0"]) + float(e["x1"])) * 0.5
			var first := ""
			var dist := -1.0
			var zl := W9.front_z(b)
			var k := 3
			while k <= 40:
				var q := W9.bw(b, cx, zl + k * 0.1)
				var it := W9.item(C, "_probe", q, b["az"], {"w": 0.1})
				var w := W9.why(C, it, [], "wall")
				if w != "":
					first = w
					dist = k * 0.1
					break
				k += 1
			line += " [%s %s→%s@%.1f]" % [e["i"], e["kind"], first if first != "" else "-", dist + 0.0]
		print(line)
	quit()
