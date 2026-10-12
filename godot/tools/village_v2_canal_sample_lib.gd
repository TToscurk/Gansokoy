extends RefCounted
## 人間之里 V2 P13 W3 — 土渠の美術樣本（T0 支線、伏越し出口 (335,46) → 末端 (330.2,78) の 1 区間だけ）。
##
## 根因（tools/p13/shot_w3.gd の計測）：支線の土渠 ribbon（village_v2_farmland_zone.gd branch_art）は u＝−1…1 の全幅
##   （渠底・内法・堤頂・外法）に同じ頂点色 Color(0.12, 0.25, 1.0, 0.0)＋UV2 (1.0, 0) を塗っている
##   ＝ ground shader で mud 1.0・gravel 0.25・trodden 0.12・wet 1.0（albedo ×0.6）。地面 shader の ground_k は地形と同値。
##   → 堤の外法まで一様な濡れ泥色の帯になり、外縁 u＝±0.95 で地形の草へ直線で切り替わる。外法は 7 列の粗い格子なので面が多角形に見える。
## 樣本の修正（幾何・高さ・碰撞は不変、頂点の重みと水面材質だけ）：
##   渠底＝濡れ泥／内法＝泥→土／堤頂＝踏み固め土（ゆらぎ）／外法＝草へ漸減（ゆらぎで外縁を不規則に）。
##   水面：樣本区間の三角形だけ別メッシュ・別材質へ（灰白い空の映り込みを抑えた泥水色・粗さ↑）。
## runtime overlay（CanalSampleP13）が適用し、OFF で元のメッシュに戻す。封存 farmland_p8.scn は書き換えない。
const ZL := preload("res://tools/village_v2_farmland_zone.gd")
const BR := "Districts/FarmlandEast/FarmlandP8/ZoneWorks/ZoneIrrigation/Branches/Branch_T0"
const WIN := Rect2(323.0, 45.5, 15.0, 33.5)     # x 323–338、z 45.5–79
const S_FROM := 46.0                             # T0 中心線上 z ≥ この点から（伏越し出口）
const HALF := 1.0                                # ZL.BR_HALF


static func t0_line() -> PackedVector2Array:
	var out := PackedVector2Array()
	for q: Array in ZL.BRANCHES["T0"]["pts"]:
		if float(q[1]) >= S_FROM - 0.01:
			out.append(Vector2(float(q[0]), float(q[1])))
	return out


static func _closest(p: Vector2, pl: PackedVector2Array) -> Array:
	var best := INF
	var s_best := 0.0
	var acc := 0.0
	for k in pl.size() - 1:
		var a := pl[k]
		var b := pl[k + 1]
		var c := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := c.distance_to(p)
		if d < best:
			best = d
			s_best = acc + a.distance_to(c)
		acc += a.distance_to(b)
	return [best, s_best]


static func _h(x: float) -> float:
	return fposmod(sin(x * 12.9898) * 43758.5453, 1.0)


## 樣本の頂点重み（u＝中心線からの距離／半幅、s＝沿い距離）。戻り値 [COLOR, UV2]
static func bank_weights(u: float, s: float, mode: String) -> Array:
	var au := absf(u)
	var j := _h(s * 3.1 + (7.0 if u > 0.0 else 0.0))          # 沿い方向のゆらぎ 0..1
	var j2 := _h(s * 1.7 + 3.3)
	if mode == "diag_grass":
		return [Color(0, 0, 0, 0), Vector2(0, 0)]
	if au <= 0.45:
		return [Color(0.05, 0.05, 0.9, 0.0), Vector2(0.85, 0.0)]                 # 渠底：濡れ泥
	if au <= 0.7:
		var t := (au - 0.45) / 0.25
		return [Color(lerpf(0.1, 0.45, t), 0.08, lerpf(0.75, 0.25, t), 0.0), Vector2(lerpf(0.6, 0.2, t), 0.0)]   # 内法：泥→土
	# 外法（0.7–1.0）：堤頂の踏み固め土から草へ。ゆらぎで草の侵入位置を沿い方向に変える
	var t2 := clampf((au - 0.7) / 0.3 + (j - 0.5) * 0.7, 0.0, 1.0)
	var tro := lerpf(0.55 + 0.25 * j2, 0.0, t2)
	return [Color(tro, 0.06 * (1.0 - t2), 0.12 * (1.0 - t2), 0.03 * j2 * (1.0 - t2)), Vector2(0.05 * (1.0 - t2), 0.0)]


static func _find(vroot: Node, which: String) -> MeshInstance3D:
	var g := vroot.get_node_or_null(BR)
	if g == null:
		return null
	for c in g.get_children():
		var mi := c as MeshInstance3D
		if mi == null or not (mi.material_override is ShaderMaterial):
			continue
		var sp := String((mi.material_override as ShaderMaterial).shader.resource_path)
		if which == "earth" and sp.ends_with("ground.gdshader"):
			return mi
		if which == "water" and sp.ends_with("p8_paddy_water.gdshader"):
			return mi
	return null


## 計測用：樣本窓の土渠頂点（u、法線、重み）
static func earth_stats(vroot: Node3D) -> Dictionary:
	var mi := _find(vroot, "earth")
	var a := mi.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var cs: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var u2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
	var line := t0_line()
	var xf := mi.global_transform
	var n := 0
	var down := 0
	var outer := 0
	var cset := {}
	var steep := 0
	for i in vs.size():
		var w := xf * vs[i]
		if not WIN.has_point(Vector2(w.x, w.z)):
			continue
		var cl := _closest(Vector2(w.x, w.z), line)
		if float(cl[0]) > HALF + 0.05:
			continue
		n += 1
		var nn := (xf.basis * ns[i]).normalized()
		if nn.y < 0.0:
			down += 1
		if nn.y < 0.7:
			steep += 1
		if float(cl[0]) > 0.7:
			outer += 1
		cset["%s|%s" % [cs[i], u2[i]]] = true
	return {"verts": n, "normal_down": down, "steep_ny_lt_0.7": steep, "outer_slope_verts": outer, "distinct_weights": cset.keys()}


## mode：fix（樣本修正）／diag_grass（重みを全部草に＝原因切り分け用）。戻り値＝元に戻すための記録
static func apply(vroot: Node3D, mode: String) -> Dictionary:
	var keep := {}
	var line := t0_line()
	var em := _find(vroot, "earth")
	if em != null:
		keep["earth_mesh"] = em.mesh
		var a := em.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var cs: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var u2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
		var xf := em.global_transform
		var n := 0
		for i in vs.size():
			var w := xf * vs[i]
			var p := Vector2(w.x, w.z)
			if not WIN.has_point(p):
				continue
			var cl := _closest(p, line)
			if float(cl[0]) > HALF + 0.05:
				continue
			# u の符号：中心線の左右（進行方向に対する外積）
			var at: Array = ZL.FL.at_s(line, float(cl[1]))
			var d: Vector2 = at[1]
			var side := signf(d.cross(p - (at[0] as Vector2)))
			var wt := bank_weights(side * float(cl[0]) / HALF, float(cl[1]), mode)
			cs[i] = wt[0]
			u2[i] = wt[1]
			n += 1
		a[Mesh.ARRAY_COLOR] = cs
		a[Mesh.ARRAY_TEX_UV2] = u2
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		em.mesh = m
		keep["earth_verts"] = n
	var wm := _find(vroot, "water")
	if wm != null and mode == "fix":
		keep["water_mesh"] = wm.mesh
		var a2 := wm.mesh.surface_get_arrays(0)
		var vs2: PackedVector3Array = a2[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a2[Mesh.ARRAY_INDEX]
		var xf2 := wm.global_transform
		var rest := PackedInt32Array()
		var mine := PackedInt32Array()
		for t in range(0, idx.size(), 3):
			var c := (xf2 * vs2[idx[t]] + xf2 * vs2[idx[t + 1]] + xf2 * vs2[idx[t + 2]]) / 3.0
			if WIN.has_point(Vector2(c.x, c.z)) and float(_closest(Vector2(c.x, c.z), line)[0]) < HALF:
				mine.append_array([idx[t], idx[t + 1], idx[t + 2]])
			else:
				rest.append_array([idx[t], idx[t + 1], idx[t + 2]])
		var ar := a2.duplicate()
		ar[Mesh.ARRAY_INDEX] = rest
		var mr := ArrayMesh.new()
		mr.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ar)
		wm.mesh = mr
		var am := a2.duplicate()
		am[Mesh.ARRAY_INDEX] = mine
		var ms := ArrayMesh.new()
		ms.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, am)
		var mat := (wm.material_override as ShaderMaterial).duplicate() as ShaderMaterial
		mat.set_shader_parameter("water_tint", Color(0.22, 0.20, 0.13))
		mat.set_shader_parameter("clarity", 0.42)
		mat.set_shader_parameter("rough_base", 0.34)
		mat.set_shader_parameter("algae", 0.25)
		mat.set_shader_parameter("scum_color", Color(0.27, 0.24, 0.16))
		var node := MeshInstance3D.new()
		node.name = "P13W3_WaterSample"
		node.mesh = ms
		node.material_override = mat
		node.transform = wm.transform
		node.visibility_range_end = wm.visibility_range_end
		node.visibility_range_end_margin = wm.visibility_range_end_margin
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wm.get_parent().add_child(node)
		keep["water_node"] = node
		keep["water_tris"] = mine.size() / 3
	return keep


static func restore(vroot: Node3D, keep: Dictionary) -> void:
	if keep.has("earth_mesh"):
		_find(vroot, "earth").mesh = keep["earth_mesh"]
	if keep.has("water_mesh"):
		_find(vroot, "water").mesh = keep["water_mesh"]
	if keep.has("water_node") and is_instance_valid(keep["water_node"]):
		var n: Node = keep["water_node"]
		n.get_parent().remove_child(n)
		n.free()
