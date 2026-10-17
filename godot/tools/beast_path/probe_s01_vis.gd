extends SceneTree
## scratch：S01 站點進度、谷寬、背景林可見性（視線）分析。
##   godot --headless --path godot --script res://tools/beast_path/probe_s01_vis.gd -- --out=<json>
const BP := preload("res://tools/beast_path/bp_lib.gd")
const ForestPlanner := preload("res://tools/beast_path/forest_planner.gd")


func _initialize() -> void:
	var out := "user://s01_vis.json"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var lib := BP.new()
	lib.setup(true, true)
	var s0: float = lib.st_s("village")
	var s1: float = lib.st_s("s01_s02")
	var L := s1 - s0
	print("[stations] s0=%.1f s1=%.1f L=%.1f" % [s0, s1, L])
	var rows: Array = []
	for i in lib.main.ctrl_id.size():
		var nm := String(lib.main.ctrl_id[i])
		var s: float = lib.main.ctrl_s[i]
		var u := (s - s0) / L
		if u > -0.3 and u < 1.2:
			rows.append([u, nm, s])
	rows.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for r in rows:
		var p: Vector2 = lib.main.pos_at(float(r[2]))
		print("  u=%5.2f  %-14s s=%6.1f  pos=(%.1f, %.1f)  w=%.1f" % [float(r[0]), r[1], float(r[2]), p.x, p.y, lib.main.w_at(float(r[2]))])
	# 谷寬：沿路 11 點，往左右量 mask_sdf 轉正的距離
	print("[valley] u: 左緣 m / 右緣 m（mask_sdf>0 的最近 off）")
	for i in 11:
		var s := s0 + L * float(i) / 10.0
		var c: Vector2 = lib.main.pos_at(s)
		var tg: Vector2 = lib.main.tan_at(s)
		var rv := Vector2(-tg.y, tg.x)
		var edge := [0.0, 0.0]
		for side in 2:
			var sg := -1.0 if side == 0 else 1.0
			var e := 0.0
			while e < 90.0 and lib.mask_sdf(c + rv * sg * e) < 0.0:
				e += 1.0
			edge[side] = e
		print("  u=%.1f  左 %.0f  右 %.0f   路心 y=%.2f  坡 %.1f°" % [float(i) / 10.0, edge[0], edge[1], lib.h_at(c.x, c.y), lib.slope_deg_at(c.x, c.y)])
	# 背景林可見性
	var fp := ForestPlanner.new()
	fp.setup(lib, [])
	var fz: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/beast_path/frozen/forest_plan_v01_s01_s03.json"))
	var s01: Array = (fz as Dictionary)["scenes"]["S01"]
	var eyes: Array = []
	var ss := s0 - 20.0
	while ss <= s1 + 6.0:
		var c2: Vector2 = lib.main.pos_at(clampf(ss, 0.0, lib.main.length))
		var tg2: Vector2 = lib.main.tan_at(clampf(ss, 0.0, lib.main.length))
		for off in [-6.0, 0.0, 6.0]:
			var q: Vector2 = c2 + Vector2(-tg2.y, tg2.x) * off
			eyes.append(Vector3(q.x, lib.h_at(q.x, q.y) + 1.7, q.y))
		ss += 5.0
	var vis_rows: Array = []
	var n_vis := 0
	for e: Dictionary in s01:
		var kind := String(e["kind"])
		var id := String(e["id"])
		var ph := float(e["y"]) + float((fp.kit[id] as Dictionary)["h"]) * float(e["s"])
		var top := Vector3(float(e["x"]), ph, float(e["z"]))
		var seen := false
		for ey: Vector3 in eyes:
			var dd := Vector2(top.x - ey.x, top.z - ey.z).length()
			if dd > 170.0:
				continue
			var steps := int(dd / 2.0) + 1
			var blocked := false
			for k in range(1, steps):
				var t := float(k) / float(steps)
				var px := lerpf(ey.x, top.x, t)
				var pz := lerpf(ey.z, top.z, t)
				var py := lerpf(ey.y, top.y, t)
				if lib.h_at(px, pz) > py:
					blocked = true
					break
			if not blocked:
				seen = true
				break
		if seen:
			n_vis += 1
		vis_rows.append({"id": id, "kind": kind, "x": e["x"], "z": e["z"], "seen": seen, "sdf": lib.mask_sdf(Vector2(float(e["x"]), float(e["z"])))})
	print("[vis] S01 380 筆中，從路廊（%d 個眼點）看得到樹冠頂的：%d；看不到：%d" % [eyes.size(), n_vis, 380 - n_vis])
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(vis_rows))
	f.close()
	quit(0)
