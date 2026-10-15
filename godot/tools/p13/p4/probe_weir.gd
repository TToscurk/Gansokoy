extends SceneTree
## 診断（唯読）：跌水 placeholder（B7／F7）の周りの水面高・河床（地形）高・水路の向きを測る。
func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var W9 := load("res://tools/p13/w9/w9_lib.gd")
	var P3 := load("res://tools/p13/w9/w9p3_lib.gd")
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await process_frame
	P3.register_dims()
	var C: Dictionary = W9.context(v, PackedVector2Array())
	var S = C["S"]
	var WS = C["WS"]
	var pts := {"F7": [Vector2(307.0, 70.0), Vector2(322, 40), Vector2(302, 80)], "B7": [Vector2(142.8, 42.0), Vector2(146, 30), Vector2(138, 60)]}
	for k: String in pts:
		var c: Vector2 = pts[k][0]
		var d: Vector2 = (pts[k][2] as Vector2 - pts[k][1] as Vector2).normalized()   # 下流向き（polyline の向き）
		var n := Vector2(-d.y, d.x)
		print("[WEIR] %s at (%.1f, %.1f) dir=(%.3f, %.3f)" % [k, c.x, c.y, d.x, d.y])
		for off in [-24.0, -16.0, -8.0, -4.0, 0.0, 4.0, 8.0, 16.0, 24.0]:
			var q: Vector2 = c + d * off
			var wh: float = WS.h(q.x, q.y)
			var gh: float = S.h(q.x, q.y)
			print("[WEIR]   s=%+5.1f  water=%s  ground=%.2f  depth=%s" % [off, ("%.2f" % wh) if not is_nan(wh) else "nan", gh, ("%.2f" % (wh - gh)) if not is_nan(wh) else "-"])
		for lat in [-4.0, -2.0, 2.0, 4.0]:
			var q2: Vector2 = c + n * lat
			var wh2: float = WS.h(q2.x, q2.y)
			print("[WEIR]   lat=%+.1f water=%s ground=%.2f" % [lat, ("%.2f" % wh2) if not is_nan(wh2) else "nan", S.h(q2.x, q2.y)])
	var wf := v.get_node_or_null("Water/Waterfalls")
	if wf != null:
		for m in wf.get_children():
			print("[WEIR] node %s pos=%s label=%s conf=%s" % [m.name, (m as Node3D).global_position, str(m.get_meta("label", "")), str(m.get_meta("conf", ""))])
	quit(0)
