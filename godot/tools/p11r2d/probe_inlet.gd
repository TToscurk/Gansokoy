extends SceneTree
## P11 R2D：T0／N0 支線末端と田区の進水口 I・支渠（lat_line）・主渠の位置と水面、末端 3 m 以内の P8 可見構件。
const FL := preload("res://tools/village_v2_farmland_lib.gd")
const ZL := preload("res://tools/village_v2_farmland_zone.gd")
func _init() -> void:
	var P := FL.plan()
	var Z: Dictionary = P["zone"]
	for bid in ["N0", "T0"]:
		var b: Dictionary = Z["blocks"][bid]
		var pts: Array = ZL.BRANCHES[bid]["pts"]
		var e := Vector2(pts[pts.size() - 1][0], pts[pts.size() - 1][1])
		var lat: PackedVector2Array = b["lat_line"]
		print("[INL] %s lv %.3f I %s 末端 %s（距離 %.2f）main %s lat_line 始 %s 終 %s" % [bid, b["lv"], b["I"], e, e.distance_to(b["I"]), str(b.get("main", PackedVector2Array()).slice(0, 4)) if b.has("main") else "-", lat[0], lat[lat.size() - 1]])
		for bn in P["bunds"]:
			var d: Dictionary = P["bunds"][bn]
			if d.get("zone", "") != bid:
				continue
			var pl: PackedVector2Array = d["pts"]
			var best := INF
			for k in pl.size() - 1:
				best = minf(best, Geometry2D.get_closest_point_to_segment(e, pl[k], pl[k + 1]).distance_to(e))
			if best < 3.0:
				print("[INL]   埂 %s cls %s 距離 %.2f notches %s" % [bn, d["cls"], best, str((d["notches"] as Array).map(func(n): return [n["kind"], snappedf(n["s"], 0.1)]))])
	quit(0)
