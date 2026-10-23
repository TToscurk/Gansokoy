extends RefCounted
## 刀的幾何定位（由網格頂點實測，不用固定偏移）。只讀：不改刀的節點或網格。
##
## analyze(sword_root) 回傳（全部在「刀網格 MeshInstance3D 的本地座標」，單位＝網格單位）：
##   ok, mesh_path（相對 sword_root）, vertex_count, long_axis（0/1/2）, axis_sign（+1：刀尖在長軸正向）,
##   tip_local     ＝長軸最遠端的頂點（刀尖；彎刀時不在軸線上）
##   tip_cluster   ＝距刀尖 5 mm 內的頂點數（>1 表示是一個尖端而不是單點雜訊）
##   guard_local   ＝截面最寬的 2 cm 段（鍔；兩端 6 cm 除外）的頂點質心
##   hilt_local    ＝鍔與柄頭之間（柄）的頂點質心＝握柄中心
##   pommel_local  ＝刀尖反向最遠端的頂點（柄頭；可能含下垂的繩結）
## world(geo, mesh_instance) 把上述點轉到世界座標（含 Sword_Hand 的縮放）。
const BIN := 0.02
const END_SKIP := 0.06

static func find_mesh(sword_root: Node) -> MeshInstance3D:
	if sword_root is MeshInstance3D:
		return sword_root as MeshInstance3D
	for c in sword_root.find_children("*", "MeshInstance3D", true, false):
		return c as MeshInstance3D
	return null

static func analyze(sword_root: Node3D) -> Dictionary:
	var mi := find_mesh(sword_root)
	if mi == null or mi.mesh == null:
		return {"ok": false, "reason": "no MeshInstance3D under %s" % sword_root.name}
	var verts := PackedVector3Array()
	for s in mi.mesh.get_surface_count():
		verts.append_array(mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	if verts.size() < 8:
		return {"ok": false, "reason": "mesh has %d vertices" % verts.size()}
	var aabb := mi.mesh.get_aabb()
	var ax := 0
	for i in 3:
		if aabb.size[i] > aabb.size[ax]:
			ax = i
	var lo := aabb.position[ax]
	# 沿長軸分段，找截面最寬的一段（鍔）
	var nb := int(ceil(aabb.size[ax] / BIN)) + 1
	var ext := []
	var cen := []
	var cnt := []
	for b in nb:
		ext.append([1e9, -1e9, 1e9, -1e9])
		cen.append(Vector3.ZERO)
		cnt.append(0)
	var o1 := (ax + 1) % 3
	var o2 := (ax + 2) % 3
	for p in verts:
		var b := clampi(int((p[ax] - lo) / BIN), 0, nb - 1)
		var e: Array = ext[b]
		e[0] = minf(e[0], p[o1]); e[1] = maxf(e[1], p[o1]); e[2] = minf(e[2], p[o2]); e[3] = maxf(e[3], p[o2])
		cen[b] += p
		cnt[b] += 1
	var gb := 0
	var gw := -1.0
	var skip := int(ceil(END_SKIP / BIN))
	for b in range(skip, nb - skip):          # 兩端各 6 cm 不算（柄頭的繩結／刀尖不可能是鍔）
		if cnt[b] == 0:
			continue
		var e: Array = ext[b]
		var w := maxf(e[1] - e[0], e[3] - e[2])
		if w > gw:
			gw = w
			gb = b
	var guard: Vector3 = cen[gb] / float(cnt[gb])
	# 刀尖在離鍔較遠的那一端
	var far_pos := aabb.position[ax] + aabb.size[ax] - guard[ax]
	var far_neg := guard[ax] - aabb.position[ax]
	var sgn := 1.0 if far_pos >= far_neg else -1.0
	var tip := verts[0]
	var pom := verts[0]
	for p in verts:
		if p[ax] * sgn > tip[ax] * sgn:
			tip = p
		if p[ax] * sgn < pom[ax] * sgn:
			pom = p
	var cluster := 0
	for p in verts:
		if p.distance_to(tip) < 0.005:
			cluster += 1
	# 柄：鍔段之外、柄頭 3 cm 以內除外（排除繩結／柄頭金具）
	var g_edge := lo + (gb + (0 if sgn > 0 else 1)) * BIN      # 鍔段靠柄的一側
	var hsum := Vector3.ZERO
	var hn := 0
	for p in verts:
		var a := p[ax]
		var inside := (a < g_edge and a > pom[ax] + 0.03) if sgn > 0 else (a > g_edge and a < pom[ax] - 0.03)
		if inside:
			hsum += p
			hn += 1
	var hilt := hsum / float(hn) if hn > 0 else Vector3(INF, INF, INF)
	return {"ok": hn > 0, "reason": "" if hn > 0 else "no hilt vertices found", "mesh_path": str(sword_root.get_path_to(mi)),
		"vertex_count": verts.size(), "long_axis": ax, "axis_sign": int(sgn), "aabb": [_v(aabb.position), _v(aabb.size)],
		"tip_local": tip, "tip_cluster": cluster, "guard_local": guard, "guard_width": gw, "guard_bin": [lo + gb * BIN, lo + (gb + 1) * BIN],
		"hilt_local": hilt, "hilt_vertex_count": hn, "pommel_local": pom, "method": "mesh_vertex_extremum+widest_cross_section"}

static func world(geo: Dictionary, mi: MeshInstance3D) -> Dictionary:
	var xf := mi.global_transform
	var tip: Vector3 = xf * (geo["tip_local"] as Vector3)
	var guard: Vector3 = xf * (geo["guard_local"] as Vector3)
	return {"tip": tip, "guard": guard, "hilt": xf * (geo["hilt_local"] as Vector3), "pommel": xf * (geo["pommel_local"] as Vector3),
		"dir": (tip - guard).normalized(), "blade_len": tip.distance_to(guard)}

static func _v(v: Vector3) -> Array:
	return [v.x, v.y, v.z]
