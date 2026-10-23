extends SceneTree
## 暫用探針：判定 riverbank 構件的「可見面」朝向——+Z 還是 −Z。
## 做法：比較朝 +Z 與朝 −Z 的面積（野面積み的可見面凹凸多、面積大）、以及各自頂點的 z 範圍與點數。
## 用法：godot --headless --path . --script res://tools/_probe_kit_orient.gd

const RLib := preload("res://tools/village_v2_riverbank_lib.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var lib := RLib.load_lib()
	var names: Array = lib.keys()
	names.sort()
	var want := ["rb_rev_a", "rb_rev_c", "rb_rev_e", "rb_revb_a", "rb_bld_a", "rb_cap_a", "rb_flag_a", "rb_cob_a"]
	for n: String in names:
		if not n in want:
			continue
		var m: Mesh = lib[n]
		var a: Array = m.surface_get_arrays(0)
		var V: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var I: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var az := m.get_aabb()
		var pos_a := 0.0
		var neg_a := 0.0
		var pos_z := [INF, -INF]
		var neg_z := [INF, -INF]
		var pv := {}
		var nv := {}
		for t in range(0, I.size(), 3):
			var p0 := V[I[t]]
			var p1 := V[I[t + 1]]
			var p2 := V[I[t + 2]]
			var ar := (p1 - p0).cross(p2 - p0).length() * 0.5
			if ar < 1e-9:
				continue
			var nn := (p1 - p0).cross(p2 - p0).normalized()
			var c := (p0 + p1 + p2) / 3.0
			if nn.z > 0.7:
				pos_a += ar
				pos_z[0] = minf(pos_z[0], c.z)
				pos_z[1] = maxf(pos_z[1], c.z)
				pv[int(round(c.z * 1000.0))] = true
			elif nn.z < -0.7:
				neg_a += ar
				neg_z[0] = minf(neg_z[0], c.z)
				neg_z[1] = maxf(neg_z[1], c.z)
				nv[int(round(c.z * 1000.0))] = true
		print("%-11s AABB z[%.3f, %.3f] len %.2f | 朝+Z 面積 %.3f 面心 z[%.3f, %.3f]（%.0f 種 z）| 朝−Z 面積 %.3f 面心 z[%.3f, %.3f]（%.0f 種 z）| 可見面＝%s" % [
			n, az.position.z, az.end.z, az.size.z, pos_a, pos_z[0], pos_z[1], pv.size(),
			neg_a, neg_z[0], neg_z[1], nv.size(),
			("+Z" if pos_a > neg_a else "−Z")])
	quit()
