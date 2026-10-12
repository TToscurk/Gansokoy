extends SceneTree
## P13 W3B：N0／T0 支線の区間構成（earth／trough／siphon）と、木槽区間の「槽底〜地面」間隙を計画値から出す（唯讀・headless 可）。
##   godot --headless --path . --script res://tools/p13/probe_w3b_branches.gd
const FLib := preload("res://tools/village_v2_farmland_lib.gd")
const ZLib := preload("res://tools/village_v2_farmland_zone.gd")


func _init() -> void:
	var P: Dictionary = FLib.plan()
	var Z: Dictionary = P["zone"]
	for br: Dictionary in Z["branches"]:
		print("== 支線 %s（源 %s）" % [br["id"], br["src"]])
		var ri := 0
		for r: Dictionary in br["runs"]:
			var line: PackedVector2Array = r["line"]
			if r["kind"] == "siphon":
				print("  run %d siphon  %s → %s  水面 %.3f→%.3f" % [ri, line[0], line[1], float(r["w"][0]), float(r["w"][1])])
				ri += 1
				continue
			var L: float = r["length"]
			print("  run %d open    L=%.2f m  頂点 %d  (%s → %s)" % [ri, L, line.size(), line[0], line[line.size() - 1]])
			var spans := ZLib.branch_spans(r)
			for sp: Array in spans:
				var a: Vector2 = FLib.at_s(line, float(sp[1]))[0]
				var b: Vector2 = FLib.at_s(line, float(sp[2]))[0]
				var wmin := INF
				var wmax := -INF
				var gapmin := INF
				var gapmax := -INF
				var n := 0
				for sm: Dictionary in r["samples"]:
					if float(sm["s"]) < float(sp[1]) - 1e-3 or float(sm["s"]) > float(sp[2]) + 1e-3:
						continue
					var d := float(sm["w"]) - float(sm["g"])
					wmin = minf(wmin, d)
					wmax = maxf(wmax, d)
					# 木槽の槽底の下面＝水面−TROUGH_DEPTH−0.04；地面との間隙
					var gap := float(sm["w"]) - FLib.TROUGH_DEPTH - 0.04 - float(sm["g"])
					gapmin = minf(gapmin, gap)
					gapmax = maxf(gapmax, gap)
					n += 1
				print("    %-6s s %.1f–%.1f (%.1f m)  (%.1f,%.1f)→(%.1f,%.1f)  水面−地面 %.3f–%.3f%s" % [sp[0], sp[1], sp[2], float(sp[2]) - float(sp[1]), a.x, a.y, b.x, b.y, wmin, wmax,
					("  槽底下面−地面 %.3f–%.3f" % [gapmin, gapmax]) if sp[0] == "trough" else ""])
			ri += 1
	quit(0)
