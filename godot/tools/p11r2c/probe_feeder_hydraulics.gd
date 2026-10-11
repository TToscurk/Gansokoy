extends SceneTree
## P11 R2C B（只讀、headless）：水車 1／3 の feeder（N0／T0）の高程表と、重力供水できる水面が近くにあるか。
##   godot --headless --path . --script res://tools/p11r2c/probe_feeder_hydraulics.gd
const FZ := preload("res://tools/village_v2_farmland_zone.gd")
const FL := preload("res://tools/village_v2_farmland_lib.gd")

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 3:
		await process_frame
	var P: Dictionary = FL.plan()
	if P.is_empty() or not P.has("zone"):
		print("[HYD] plan() が取れない")
	var Z: Dictionary = P.get("zone", {})
	# 水面メッシュ（Water 以下全部）の頂点
	var wpts: Array = []
	for mi in v.get_node("Water").find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		var xf := (mi as Node3D).global_transform
		for s in m.get_surface_count():
			var vs: PackedVector3Array = m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for k in range(0, vs.size(), 3):
				wpts.append([xf * vs[k], String(v.get_path_to(mi))])
	print("[HYD] water verts ", wpts.size())
	for f: Dictionary in Z.get("feeders", []):
		var ch: Array = f["chute"]
		var I: Vector2 = (f["trough"] as PackedVector2Array)[(f["trough"] as PackedVector2Array).size() - 1]
		var need: float = float(f["bot"][1]) + 0.05   # 田区進水口で槽底＋最低水深
		print("[HYD] ===== %s → %s  block lv %.3f" % [f["wheel"], f["block"], float(f["lv"])])
		print("[HYD]   受け樋頭 %s  中間 %s  落とし桝側 %s" % [ch[0], ch[1], ch[2]])
		print("[HYD]   落とし桝 %s 地面 %.3f  桝水面 %.3f" % [f["box"], FZ.ground_h(f["box"]), float(f["box_w"])])
		print("[HYD]   木槽 %s  槽底 %.3f→%.3f  進水口 I %s 地面 %.3f  要求水面 ≥ %.3f" % [f["trough"], float(f["bot"][0]), float(f["bot"][1]), I, FZ.ground_h(I), need])
		# 半径 150 m 以内で、要求水面＋0.10 以上の水面を持つ点（重力で届く可能性）
		var best := {}
		for w in wpts:
			var p: Vector3 = w[0]
			var d := Vector2(p.x, p.z).distance_to(I)
			if d > 150.0 or p.y < need + 0.10:
				continue
			var key: String = w[1]
			if not best.has(key) or d < float(best[key][0]):
				best[key] = [d, p]
		if best.is_empty():
			print("[HYD]   150 m 以内に水面 ≥ %.2f の水源なし" % (need + 0.10))
		for k in best:
			print("[HYD]   候補水源 %-44s 距離 %.1f m  水面 %.2f  （落差 %.2f m）" % [k, best[k][0], (best[k][1] as Vector3).y, (best[k][1] as Vector3).y - need])
		# 最寄りの水面（どの高さでも）
		var nd := INF
		var np := Vector3()
		var nk := ""
		for w in wpts:
			var p: Vector3 = w[0]
			var d := Vector2(p.x, p.z).distance_to(Vector2(ch[0].x, ch[0].z))
			if d < nd:
				nd = d
				np = p
				nk = w[1]
		print("[HYD]   水車脇の水面 %s 水位 %.3f（距離 %.1f）→ 必要揚程 %.2f m（田区要求水面まで）" % [nk, np.y, nd, need - np.y])
	quit(0)
