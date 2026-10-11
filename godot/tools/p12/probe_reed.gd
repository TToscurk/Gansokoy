extends SceneTree
## P12 Final Cleanup A1（只讀、headless）：wk_reed_s@(329.7,-47.2) — 現在の計画と封存 overlay の実物を比較し、
## _blocked() のどの条件で通路衝突になっているかを出す。
const WS := preload("res://tools/village_v2_waterside_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const P0 := Vector2(329.7, -47.2)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/village_v2/layout_v2.json"))
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	# 封存 overlay 実物：近くの wk_reed_s ノード
	var ov := v.get_node("Vegetation/" + WS.NODE_NAME)
	for n in ov.find_children("*", "Node3D", true, false):
		var p := (n as Node3D).position
		if String(n.name).contains("wk_reed_s") and Vector2(p.x, p.z).distance_to(P0) < 3.0:
			print("[REED] overlay 実物 %s pos %s" % [ov.get_path_to(n), p])
	ov.get_parent().remove_child(ov)
	ov.free()
	root.add_child(v)
	await physics_frame
	await physics_frame
	var P: Dictionary = WS.plan(v, L)
	var H: Dictionary = P["H"]
	var R = P["R"]
	for it: Dictionary in P["items"]:
		if String(it["id"]) != "wk_reed_s" or (it["p"] as Vector2).distance_to(P0) > 3.0:
			continue
		var p: Vector2 = it["p"]
		var why := []
		if not is_nan(R.h(p.x, p.y)):
			why.append("道路面の上")
		for q in 6:
			var a := q * TAU / 6.0
			if not is_nan(R.h(p.x + cos(a) * 0.4, p.y + sin(a) * 0.4)):
				why.append("道路 0.4 m 以内（方向 %d）" % q)
				break
		for wk: Array in H["walkways"]:
			if WS.GL.poly_d(PackedVector2Array(wk), p) < 1.0 or Geometry2D.is_point_in_polygon(p, PackedVector2Array(wk)):
				why.append("水車 walkway %.2f m" % WS.GL.poly_d(PackedVector2Array(wk), p))
		for e: Vector2 in H["entries"]:
			if p.distance_to(e) < 1.8:
				why.append("水車入口 %.2f m" % p.distance_to(e))
		print("[REED] 計画 %s y %.3f 衝突=%s" % [p, float(it["y"]), str(why)])
	# 道路：どの Roads の三角形が (329.7,-47.2) から 0.6 m 以内か
	for mi: MeshInstance3D in v.get_node("Roads").find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var f := mi.mesh.get_faces()
		var best := INF
		for t in range(0, f.size(), 3):
			var a3 := mi.global_transform * f[t]
			for k in 3:
				var w := mi.global_transform * f[t + k]
				best = minf(best, Vector2(w.x, w.z).distance_to(P0))
		if best < 3.0:
			print("[REED] 近い道路 %s 頂点最短 %.2f m mesh %s" % [v.get_path_to(mi), best, mi.mesh.resource_path])
	quit(0)
