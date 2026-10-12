extends SceneTree
## P13 W3B：計画の ground_h（碰撞由来 1 m 格雙線性）と、実際に見えている地形メッシュ（FarmlandTerrain の三角形）の高さ差を、
## 支線に沿って計測（唯讀、headless 可）。土渠の外法の足（g+0.005）・堤頂・木槽の槽底下面と実可見地面の関係を出す。
const SCENE := "res://maps/village_v2/village_v2.tscn"
const FLib := preload("res://tools/village_v2_farmland_lib.gd")
const ZLib := preload("res://tools/village_v2_farmland_zone.gd")


var _tms: Array = []    # [TriangleMesh…]：FarmlandTerrain（細）＋MainTerrain（FarmlandTerrain に面が無い所を担当）


func _vis(_unused, p: Vector2) -> float:
	var best := NAN
	for tm: TriangleMesh in _tms:
		var h := tm.intersect_ray(Vector3(p.x, 20.0, p.y), Vector3.DOWN)
		if not h.is_empty():
			var y := float(h["position"].y)
			best = y if is_nan(best) else maxf(best, y)
	return best


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	await process_frame
	var ft := v.get_node("Terrain/FarmlandTerrain") as MeshInstance3D
	print("FarmlandTerrain xform=", ft.global_transform)
	var tm := ft.mesh.generate_triangle_mesh()
	_tms = [tm, (v.get_node("Terrain/MainTerrain") as MeshInstance3D).mesh.generate_triangle_mesh()]
	var P: Dictionary = FLib.plan()
	for br: Dictionary in P["zone"]["branches"]:
		for r: Dictionary in br["runs"]:
			if r["kind"] != "open":
				continue
			var line: PackedVector2Array = r["line"]
			var L: float = r["length"]
			var spans := ZLib.branch_spans(r)
			for sp: Array in spans:
				var d_c := []     # 中心：可見−碰撞
				var d_toe := []   # 外法の足（u=±1）
				var d_crest := [] # 堤頂（u=±0.67）
				var gap_vis := [] # 槽底下面 − 可見地面（trough のみ）
				var s: float = float(sp[1])
				while s <= float(sp[2]) + 1e-3:
					var at: Array = FLib.at_s(line, minf(s, L))
					var c: Vector2 = at[0]
					var d: Vector2 = at[1]
					var n := Vector2(-d.y, d.x)
					var gc := ZLib.ground_h(c)
					var gv := _vis(tm, c)
					if not is_nan(gv):
						d_c.append(gv - gc)
						if sp[0] == "trough":
							gap_vis.append(ZLib.branch_water(r, minf(s, L)) - 0.11 - gv)
					for sd: float in [-1.0, 1.0]:
						var q := c + n * sd * 1.0
						var qc := c + n * sd * 0.67
						var vq := _vis(tm, q)
						var vqc := _vis(tm, qc)
						if not is_nan(vq):
							d_toe.append(vq - ZLib.ground_h(q))
						if not is_nan(vqc):
							d_crest.append(vqc - ZLib.ground_h(qc))
					s += 0.5
				print("%s %-6s s%.0f–%.0f  中心(可見−碰撞) %s  足 %s  堤頂位置 %s%s" % [br["id"], sp[0], sp[1], sp[2], _st(d_c), _st(d_toe), _st(d_crest),
					("  槽底下面−可見地面 " + _st(gap_vis)) if sp[0] == "trough" else ""])
	quit(0)


func _st(a: Array) -> String:
	if a.is_empty():
		return "-"
	var mn := INF
	var mx := -INF
	var sm := 0.0
	for x in a:
		mn = minf(mn, float(x))
		mx = maxf(mx, float(x))
		sm += float(x)
	return "[%+.3f..%+.3f 平均%+.3f]" % [mn, mx, sm / a.size()]
