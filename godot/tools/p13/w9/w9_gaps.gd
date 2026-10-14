extends SceneTree
## W9 診断：道沿いの宅間（gaps）の一覧。godot --headless --path . --script res://tools/p13/w9/w9_gaps.gd -- WestBankLane [--bays]
const W9 := preload("res://tools/p13/w9/w9_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await process_frame
	var C := W9.context(v, PackedVector2Array())
	print("[GAP] context %d ms（W9 追加 %d ms）・rootp %d" % [int(C["ms"]), int(C["w9_ms"]), int(C["n_rootp"])])
	for g: Dictionary in W9.gaps(C, a[0]):
		print("[GAP] %s | %s  w=%.2f side=%d front=(%.1f,%.1f) ax=(%.2f,%.2f) az=(%.2f,%.2f) dmin=%.2f" % [g["a"], g["b"], g["w"], g["side"], (g["front"] as Vector2).x, (g["front"] as Vector2).y, (g["ax"] as Vector2).x, (g["ax"] as Vector2).y, (g["az"] as Vector2).x, (g["az"] as Vector2).y, g["dmin"]])
	if "--bays" in a:
		for b: Dictionary in C["bld"]:
			if String(b["road"]) == a[0]:
				var bs: Array = W9.bays(b)
				var s := ""
				for e: Dictionary in bs:
					s += " %s[%.2f,%.2f]" % [e["kind"], e["x0"], e["x1"]]
				print("[GAP] %s %s w=%.2f d=%.2f door_cx=%.2f doorbay=%d y=%.2f%s" % [b["name"], b["type"], b["w"], b["d"], b["door_cx"], W9.door_bay(b), float(C["bld_y"][b["name"]]), s])
	quit(0)
