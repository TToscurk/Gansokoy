extends SceneTree
## P11 R1 診斷（只讀、headless）：walk_r1 の BLOCKED／STUCK・ARM_PULL 地点で、進行方向・相機方向に何があるか。
##   godot --headless --path godot --script res://tools/diag_p11_walk_events.gd -- --log=<walk_log.json> [--out=<json>]

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var lp := ""
	var out := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--log="):
			lp = a.trim_prefix("--log=")
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(lp))
	var v := (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(v)
	for i in 6:
		await process_frame
	await physics_frame
	await physics_frame
	var sp := v.get_world_3d().direct_space_state
	var rows := []
	for e: Dictionary in L["events"]:
		var k := String(e["kind"])
		if not (k in ["BLOCKED", "ARM_PULL", "LIFT"]):
			continue
		var p := Vector3(float(e["pos"][0]), float(e["pos"][1]), float(e["pos"][2]))
		var row := {"kind": k, "seg": e["seg"], "pos": e["pos"]}
		if k == "BLOCKED":
			var g := Vector3(float(e["goal"][0]), p.y, float(e["goal"][1]))
			for hh in [0.4, 1.2]:
				var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, hh, 0), g + Vector3(0, hh, 0))
				var h := sp.intersect_ray(q)
				row["ahead_%.1f" % hh] = ("%s @ %.2f m" % [String(v.get_path_to(h["collider"] as Node)), (h["position"] as Vector3).distance_to(p + Vector3(0, hh, 0))]) if not h.is_empty() else "なし"
			row["goal_inside_building"] = _inside_building(v, sp, Vector2(g.x, g.z))
		elif k == "ARM_PULL":
			var c := Vector3(float(e["cam"][0]), float(e["cam"][1]), float(e["cam"][2]))
			var piv := p + Vector3(0, 1.65, 0)
			var far := piv + (c - piv).normalized() * 8.5
			var q := PhysicsRayQueryParameters3D.create(piv, far)
			var h := sp.intersect_ray(q)
			row["arm_hit"] = ("%s @ %.2f m" % [String(v.get_path_to(h["collider"] as Node)), (h["position"] as Vector3).distance_to(piv)]) if not h.is_empty() else "なし"
		rows.append(row)
		print("[EV] %s" % JSON.stringify(row))
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(rows, "\t") + "\n")
		f.close()
	quit(0)


func _inside_building(v: Node3D, sp: PhysicsDirectSpaceState3D, q: Vector2) -> String:
	var pq := PhysicsPointQueryParameters3D.new()
	var ty := 0.0
	var r := sp.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(q.x, 80, q.y), Vector3(q.x, -40, q.y)))
	if not r.is_empty():
		ty = float((r["position"] as Vector3).y)
	pq.position = Vector3(q.x, ty - 0.3, q.y)
	for h in sp.intersect_point(pq, 4):
		return String(v.get_path_to(h["collider"] as Node))
	return String(v.get_path_to(r["collider"] as Node)) if not r.is_empty() else ""
