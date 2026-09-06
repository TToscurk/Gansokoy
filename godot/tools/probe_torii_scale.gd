extends SceneTree
## 大鳥居縮放換算：規格 §2 要高 6.0-7.5 m、淨開口寬 4.5-6.0 m。
##
##   Godot --headless --path godot --script tools/probe_torii_scale.gd
##
## slice 用 scale=20 → 實高 14.6 m，是規格上限的兩倍。
## 這支量原始 AABB 與**柱間淨空**，算出符合規格的 scale 區間。
## 淨開口不能用整體寬度推——鳥居的笠木比柱間寬，兩者差很多。

const PATH := "res://assets/landmark/大鳥居.glb"


func _init() -> void:
	var ps := load(PATH) as PackedScene
	if ps == null:
		print("[TORII] 載入失敗：%s" % PATH)
		quit(1)
		return
	var inst := ps.instantiate() as Node3D

	var box: Variant = null
	var meshes := _meshes(inst)
	for m in meshes:
		var mi := m as MeshInstance3D
		var b := _rel(mi, inst) * mi.get_aabb()
		box = b if box == null else (box as AABB).merge(b)
	var bb := box as AABB
	print("[TORII] 原始 AABB  寬 %.4f  高 %.4f  深 %.4f" % [bb.size.x, bb.size.y, bb.size.z])
	print("[TORII] y 範圍 %.4f → %.4f（原點在%s）"
		% [bb.position.y, bb.end.y,
			"底" if absf(bb.position.y) < bb.size.y * 0.1 else "中心/其他"])

	# ── 柱間淨空：在柱子高度處掃描頂點的 x 分布，找中央的空隙 ──
	# 取 y 在整體高度 25%~55% 的頂點（避開笠木與貫、抓柱身）
	var y0 := bb.position.y + bb.size.y * 0.25
	var y1 := bb.position.y + bb.size.y * 0.55
	var xs := PackedFloat32Array()
	for m in meshes:
		var mi := m as MeshInstance3D
		var xf := _rel(mi, inst)
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in vs:
				var w: Vector3 = xf * v
				if w.y >= y0 and w.y <= y1:
					xs.append(w.x)
	if xs.is_empty():
		print("[TORII] 柱身高度帶取不到頂點")
		inst.free()
		quit(1)
		return
	var sorted := Array(xs)
	sorted.sort()
	# 中央最大空隙 = 柱間淨空
	var cx := bb.get_center().x
	var left_max := -INF     # 左柱的最右緣
	var right_min := INF     # 右柱的最左緣
	for x in sorted:
		if x < cx and x > left_max:
			left_max = x
		if x > cx and x < right_min:
			right_min = x
	var clear := right_min - left_max
	print("[TORII] 柱身帶頂點 %d 個；柱間淨空 %.4f（左柱右緣 %.4f、右柱左緣 %.4f）"
		% [xs.size(), clear, left_max, right_min])

	# ── 換算 ──
	print("[TORII] ── 規格 §2：高 6.0-7.5 m、淨開口 4.5-6.0 m ──")
	var s_h_lo := 6.0 / bb.size.y
	var s_h_hi := 7.5 / bb.size.y
	print("[TORII] 由高度定 scale：%.3f ~ %.3f" % [s_h_lo, s_h_hi])
	if clear > 0.001:
		var s_w_lo := 4.5 / clear
		var s_w_hi := 6.0 / clear
		print("[TORII] 由淨開口定 scale：%.3f ~ %.3f" % [s_w_lo, s_w_hi])
		var lo := maxf(s_h_lo, s_w_lo)
		var hi := minf(s_h_hi, s_w_hi)
		if lo <= hi:
			var pick := (lo + hi) * 0.5
			print("[TORII] ✓ 交集 scale %.3f ~ %.3f → 建議 %.2f" % [lo, hi, pick])
			print("[TORII]   → 高 %.2f m、淨開口 %.2f m" % [bb.size.y * pick, clear * pick])
		else:
			print("[TORII] ✗ 高度與開口的 scale 區間**沒有交集**")
			print("[TORII]   這座鳥居的長寬比不符規格，等比縮放無法同時滿足兩項。")
			print("[TORII]   以高度為準 scale %.2f 時，淨開口 = %.2f m（規格要 4.5-6.0）"
				% [(s_h_lo + s_h_hi) * 0.5, clear * (s_h_lo + s_h_hi) * 0.5])
	inst.free()
	quit(0)


func _meshes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		o.append(n)
	for c in n.get_children():
		o.append_array(_meshes(c))
	return o


func _rel(n: Node3D, root: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
