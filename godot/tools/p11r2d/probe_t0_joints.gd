extends SceneTree
## P11 R2D-Fix（只讀、headless）：T0 支線の区間（土渠／木槽）境界と折れ角を列挙。
const ZL := preload("res://tools/village_v2_farmland_zone.gd")
const FL := preload("res://tools/village_v2_farmland_lib.gd")

func _init() -> void:
	for br: Dictionary in ZL.branch_specs():
		if br["id"] != "T0":
			continue
		var ri := 0
		for r: Dictionary in br["runs"]:
			var line: PackedVector2Array = r["line"]
			if r["kind"] != "open":
				print("[TJ] run %d siphon %s" % [ri, line])
				ri += 1
				continue
			for sp: Array in ZL.branch_spans(r):
				var p0: Vector2 = FL.at_s(line, sp[1])[0]
				var p1: Vector2 = FL.at_s(line, sp[2])[0]
				print("[TJ] run %d %-6s s %.1f–%.1f  %s → %s" % [ri, sp[0], sp[1], sp[2], p0.snappedf(0.01), p1.snappedf(0.01)])
			var acc := 0.0
			for i in range(1, line.size() - 1):
				acc += line[i - 1].distance_to(line[i])
				var a := (line[i] - line[i - 1]).normalized()
				var b := (line[i + 1] - line[i]).normalized()
				var ang := rad_to_deg(a.angle_to(b))
				if absf(ang) > 20.0:
					print("[TJ]   折れ %s s %.1f 角 %.0f°" % [line[i], acc, ang])
			ri += 1
	quit(0)
