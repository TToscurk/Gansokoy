extends SceneTree
## P13 W3B：N0／T0 支線の平面形の折れ（計画値）を出す（唯讀・headless 可）。
##   各 open run の頂点列で、隣り合う区間の向きの差（折れ角）が 20° 以上の頂点を一覧する。
##   godot --headless --path . --script res://tools/p13/probe_w3b_corners.gd
const FLib := preload("res://tools/village_v2_farmland_lib.gd")


func _init() -> void:
	var P: Dictionary = FLib.plan()
	for br: Dictionary in P["zone"]["branches"]:
		var ri := 0
		for r: Dictionary in br["runs"]:
			var line: PackedVector2Array = r["line"]
			if r["kind"] == "siphon":
				ri += 1
				continue
			var n := 0
			var maxa := 0.0
			var items: Array = []
			for i in range(1, line.size() - 1):
				var d0 := (line[i] - line[i - 1]).normalized()
				var d1 := (line[i + 1] - line[i]).normalized()
				var a := rad_to_deg(acos(clampf(d0.dot(d1), -1.0, 1.0)))
				maxa = maxf(maxa, a)
				if a >= 20.0:
					n += 1
					items.append("(%.1f,%.1f) %.0f°" % [line[i].x, line[i].y, a])
			print("%s run%d 頂点 %d：折れ角 ≥ 20° の頂点 %d、最大折れ角 %.0f°  %s" % [br["id"], ri, line.size(), n, maxa, ", ".join(items)])
			ri += 1
	quit(0)
