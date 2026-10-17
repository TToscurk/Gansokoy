extends SceneTree
## 一時（W9 FIX 最終驗收・軽い効能比較）：village_v2 を読み、BEFORE（元の箱 22）／AFTER（Shell 401 箱）を交互に 3 回ずつ、
## 22 棟の周り（立面の外 0.5–3.5 m・建物の中も含む格子）で玩家と同じ capsule の cast_motion＋get_rest_info を 4000 回ずつ打ち、1 回あたりの時間を量る。
const L := preload("res://tools/p13/w9/w9r2_lib.gd")


func _init() -> void:
	_run.call_deferred()


func _cfg(v: Node, cf: Dictionary, after: bool) -> void:
	var ov := v.get_node("ArchW9R2P13")
	for id: String in cf:
		for c in v.get_node(NodePath(String(L.SPECS[id]["path"]))).get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).disabled = after
		for c in ov.get_node(id + "/Shell").get_children():
			(c as CollisionShape3D).disabled = not after
	for i in 3:
		await physics_frame


func _run() -> void:
	var t0 := Time.get_ticks_usec()
	var v := (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	var t1 := Time.get_ticks_usec()
	root.add_child(v)
	for i in 8:
		await process_frame
	print("[W9PERF] village_v2 load+instantiate %.0f ms・add_child+8 frames %.0f ms" % [(t1 - t0) / 1000.0, (Time.get_ticks_usec() - t1) / 1000.0])
	var cf: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(L.COLFIT)) as Dictionary)["buildings"]
	var space := (v as Node3D).get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	var pts: Array = []
	for id: String in cf:
		var b := v.get_node(NodePath(String(L.SPECS[id]["path"]))) as Node3D
		var o: Dictionary = (cf[id] as Dictionary)["orig"]
		for i in 182:
			var lx := lerpf(float(o["x0"]) - 1.0, float(o["x1"]) + 1.0, float(i % 14) / 13.0)
			var lz := lerpf(float(o["z0"]) - 1.0, float(o["z1"]) + 3.5, float(i / 14) / 12.0)
			pts.append(b.global_transform * Vector3(lx, 1.0, lz))
	var res := {"before": [], "after": []}
	for rep in 3:
		for cfg in ["before", "after"]:
			await _cfg(v, cf, cfg == "after")
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cap
			q.collision_mask = 1
			var t := Time.get_ticks_usec()
			var n := 0
			for p: Vector3 in pts:
				q.transform = Transform3D(Basis.IDENTITY, p)
				q.motion = Vector3(0.6, 0.0, 0.0)
				space.cast_motion(q)
				q.motion = Vector3.ZERO
				space.get_rest_info(q)
				n += 1
			(res[cfg] as Array).append((Time.get_ticks_usec() - t) / float(n))
	for cfg in res:
		var a: Array = res[cfg]
		a.sort()
		print("[W9PERF] %s：capsule cast_motion+rest_info 1 組 %.2f µs（3 回の中央値・%d 点）・%s" % [cfg, a[1], pts.size(), str(a)])
	quit(0)
