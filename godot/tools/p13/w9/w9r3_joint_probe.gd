extends SceneTree
## 診断用（読み取りのみ）：庇の付け根が壁面に接しているかを『壁の被覆』で数える。
##   godot --headless --path godot --script res://tools/p13/w9/w9r3_joint_probe.gd -- B_P_MKT_011
## 庇の付け根の帯（y±0.45 m）を 4 cm の格子に切り、壁面（z≈zf・法線 ±z の三角形）に覆われない格子（＝壁と庇の隙間）を数える。
const L := preload("res://tools/p13/w9/w9r2_lib.gd")


func _init() -> void:
	_run.call_deferred()


func _tris(mesh: Mesh) -> Array:
	var out: Array = []
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in idx.size() / 3:
			out.append([v[idx[t * 3]], v[idx[t * 3 + 1]], v[idx[t * 3 + 2]]])
	return out


func _in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if absf(d) < 1.0e-9:
		return false
	var l1 := ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / d
	var l2 := ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / d
	return l1 >= -1.0e-6 and l2 >= -1.0e-6 and (1.0 - l1 - l2) >= -1.0e-6


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[0] if args.size() > 0 else "B_P_MKT_011"
	var meta := JSON.parse_string(FileAccess.get_file_as_string(L.META)) as Dictionary
	var m := load("res://assets/village_v2/w9r2_arch/mesh/%s_L0.res" % id) as Mesh
	var T := _tris(m)
	for e: Dictionary in (meta["eaves"][id] as Array):
		var zf := float(e["zf"])
		var y := float(e["y"])
		var x0 := float(e["x0"])
		var x1 := float(e["x1"])
		var cell := 0.04
		var ys := y - 0.45
		var ye := y + 0.45
		var slab: Array = []
		for t in T:
			var okz := true
			for q: Vector3 in t:
				if absf(q.z - zf) > 0.15:
					okz = false
			if not okz:
				continue
			var n: Vector3 = (t[1] - t[0]).cross(t[2] - t[0])
			if n.length() < 1.0e-9 or absf(n.normalized().z) < 0.5:
				continue
			slab.append(t)
		var nx := int((x1 - x0) / cell)
		var ny := int((ye - ys) / cell)
		var holes := 0
		var rows := {}
		var mnx := 1.0e9
		var mxx := -1.0e9
		for ix in nx:
			for iy in ny:
				var p := Vector2(x0 + (ix + 0.5) * cell, ys + (iy + 0.5) * cell)
				var cov := false
				for t in slab:
					if _in_tri(p, Vector2(t[0].x, t[0].y), Vector2(t[1].x, t[1].y), Vector2(t[2].x, t[2].y)):
						cov = true
						break
				if not cov:
					holes += 1
					var k := "%.2f" % snappedf(p.y, 0.04)
					rows[k] = int(rows.get(k, 0)) + 1
					mnx = minf(mnx, p.x)
					mxx = maxf(mxx, p.x)
		print("[JNT] %s eave x %.2f..%.2f y %.2f depth %.2f：壁面三角形 %d・格子 %d・隙間 %d %s x %.2f..%.2f" % [id, x0, x1, y, float(e["depth"]), slab.size(), nx * ny, holes, str(rows), mnx, mxx])
		# 袖卯建（端の防火壁）の底面と庇の屋面の隙間：|x| 3.1–3.56 の三角形のうち、庇の高さより上へ伸びるもの（卯建）の最低点
		var ud_lo := 1.0e9
		var ud_zmin := 1.0e9
		var ud_zmax := -1.0e9
		var ud_xmin := 1.0e9
		var ud_xmax := -1.0e9
		for t in T:
			var hi := false
			var inx := true
			for q: Vector3 in t:
				if q.y > y + 0.35:
					hi = true
				if absf(q.x) < 3.1 or absf(q.x) > 3.56 or q.z < zf - 0.05:
					inx = false
			if hi and inx and t[0].x > 0.0:
				for q: Vector3 in t:
					ud_lo = minf(ud_lo, q.y)
					ud_zmin = minf(ud_zmin, q.z)
					ud_zmax = maxf(ud_zmax, q.z)
					ud_xmin = minf(ud_xmin, q.x)
					ud_xmax = maxf(ud_xmax, q.x)
		if ud_lo < 1.0e8:
			var roof_y := y - (ud_zmax - zf) * float(e["p"])            # 庇の屋面の高さ（卯建の前端 z で）
			var lap := roof_y - ud_lo                                    # 正＝卯建が庇の屋面より下まで食い込む（隙間なし）／負＝宙に浮く隙間
			print("[JNT]   右の卯建 x %.2f..%.2f z %.2f..%.2f 最低点 y %.2f／庇の屋面 y %.2f → 食い込み %+.2f m（%s）" % [ud_xmin, ud_xmax, ud_zmin, ud_zmax, ud_lo, roof_y, lap, "隙間なし" if lap >= 0.0 else "隙間あり"])
	quit(0)
