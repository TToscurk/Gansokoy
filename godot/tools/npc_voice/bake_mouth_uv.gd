extends SceneTree
## 嘴部 UV 烘焙：在 HERO 的「身體」網格（臉畫在這張貼圖上）找出嘴所在的貼圖位置，
## 給 systems/npc_life/npc_mouth.gd 在臉的表面上畫張嘴（跟著曲面與骨架，側面不偏）。
## 做法：以 voices.json 的 mouth（Skeleton 空間、rest 姿勢；只用 x、y）為中心，在嘴的範圍內每 2 mm
##   往臉正面打射線，只取朝外（正面）的最前面一層（排除頭殼內側）；依 UV 分群（嘴跨在貼圖接縫上時
##   會分成兩塊），每塊把「嘴中心」外插到該塊的 UV，並附 UV→臉部公尺的 2×2 矩陣。
## godot --headless --path godot -s res://tools/npc_voice/bake_mouth_uv.gd
##   → 每名 HERO 印 `MOUTH_UV <id> <JSON>`（正面，最多 2 塊）與 `MOUTH_UV_BACK <id> <JSON>`（頭殼內側，最多 1 塊），
##     寫進 voices.json 的 heroes.<id>.mouth_uv／mouth_uv_back（每個元素 [u, v, c0x, c0y, c1x, c1y]）；
##     `MOUTH_INNER`＝開縫嘴的唇內壁 UV 塊 [u, v, 半徑]（空＝沒有開縫）→ mouth_inner
##   只有正面取樣有漏洞（嘴是開縫的模型）時才需要 mouth_uv_back／mouth_inner。
func _initialize() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/npc_life/voices.json"))
	for h in cfg.heroes:
		var vc: Dictionary = cfg.heroes[h]
		if not vc.has("mouth"):
			continue
		var n := (load("res://characters/%s/%s.tscn" % [h, h]) as PackedScene).instantiate()
		root.add_child(n)
		var sk := n.find_child("GeneralSkeleton", true, false) as Skeleton3D
		var body := n.find_child(String(vc.get("body_mesh", "身體")), true, false) as MeshInstance3D
		var to_sk: Transform3D = sk.global_transform.affine_inverse() * body.global_transform
		var arr := body.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var cx := float(vc.mouth[0])
		var cy := float(vc.mouth[1])
		var sz: Array = vc.get("mouth_size", [0.016, 0.010])
		var front := _anchors(v, uv, idx, to_sk, cx, cy, sz, true)
		# 背面：嘴是開縫的模型（慧音），縫裡看得到頭殼內側——內側也畫，縫裡才是暗的
		var back := _anchors(v, uv, idx, to_sk, cx, cy, sz, false)
		print("%s：正面 %s；背面 %s" % [h, front.info, back.info])
		print("MOUTH_UV ", h, " ", JSON.stringify(front.anchors))
		print("MOUTH_UV_BACK ", h, " ", JSON.stringify(back.anchors.slice(0, 1)))
		# 開縫的嘴：縫內的唇內壁（法線接近水平向上／下、射線平行掃不到）所在的 UV 塊 → [u, v, 半徑]
		print("MOUTH_INNER ", h, " ", JSON.stringify(_inner(v, uv, idx, to_sk, cx, cy, sz)))
		n.free()
	quit()


## front=true：朝外的面（Godot 正面＝順時針：從 +Z 看法線 z < 0）；false：頭殼內側
func _anchors(v: PackedVector3Array, uv: PackedVector2Array, idx: PackedInt32Array, to_sk: Transform3D, cx: float, cy: float, sz: Array, front: bool) -> Dictionary:
	var tris: Array = []
	for t in range(0, idx.size(), 3):
		var a := to_sk * v[idx[t]]
		if Vector2(a.x - cx, a.y - cy).length() > 0.04:
			continue
		var b := to_sk * v[idx[t + 1]]
		var c := to_sk * v[idx[t + 2]]
		if ((b - a).cross(c - a).z < 0.0) != front:
			continue
		tris.append([a, b, c, uv[idx[t]], uv[idx[t + 1]], uv[idx[t + 2]]])
	var samples: Array = []
	for ix in range(-5, 6):
		for iy in range(-3, 4):
			var o := Vector3(cx + ix * 0.002, cy + iy * 0.002, 1.0)
			if absf(o.x - cx) > float(sz[0]) * 0.6 or absf(o.y - cy) > float(sz[1]) * 0.6:
				continue
			var best := -INF
			var hit: Array = []
			for tr in tris:
				var p: Variant = Geometry3D.ray_intersects_triangle(o, Vector3(0, 0, -1), tr[0], tr[1], tr[2])
				if p != null and (p as Vector3).z > best:
					best = (p as Vector3).z
					hit = [p, tr]
			if not hit.is_empty():
				samples.append(_sample(hit[0], hit[1]))
	# UV 分群（嘴跨在貼圖接縫上時會分成兩塊）
	var groups: Array = []
	for s in samples:
		var placed := false
		for g in groups:
			if (g[0].uv as Vector2).distance_to(s.uv) < 0.05:
				g.append(s)
				placed = true
				break
		if not placed:
			groups.append([s])
	groups.sort_custom(func(a, b): return a.size() > b.size())
	var anchors: Array = []
	for g in groups.filter(func(g): return g.size() >= 2).slice(0, 2):
		var bs: Dictionary = g[0]
		for s in g:
			if Vector2(s.p.x - cx, s.p.y - cy).length() < Vector2(bs.p.x - cx, bs.p.y - cy).length():
				bs = s
		var M := Transform2D(bs.c0, bs.c1, Vector2.ZERO)     # duv → 公尺
		var cuv: Vector2 = bs.uv + M.affine_inverse().basis_xform(Vector2(cx - bs.p.x, cy - bs.p.y))
		anchors.append([snappedf(cuv.x, 0.00001), snappedf(cuv.y, 0.00001), snappedf(bs.c0.x, 0.0001), snappedf(bs.c0.y, 0.0001), snappedf(bs.c1.x, 0.0001), snappedf(bs.c1.y, 0.0001)])
	var zs := samples.map(func(s): return s.p.z)
	var info := "樣本 %d、UV 塊 %s、z %.4f～%.4f" % [samples.size(), groups.map(func(g): return g.size()), zs.min() if zs.size() else 0.0, zs.max() if zs.size() else 0.0]
	return {"anchors": anchors, "info": info}


func _inner(v: PackedVector3Array, uv: PackedVector2Array, idx: PackedInt32Array, to_sk: Transform3D, cx: float, cy: float, sz: Array) -> Array:
	var pts: Array = []
	for t in range(0, idx.size(), 3):
		var a := to_sk * v[idx[t]]
		var b := to_sk * v[idx[t + 1]]
		var c := to_sk * v[idx[t + 2]]
		var cen := (a + b + c) / 3.0
		if absf(cen.x - cx) > float(sz[0]) * 0.55 or absf(cen.y - cy) > float(sz[1]) * 0.35:
			continue
		if absf((b - a).cross(c - a).normalized().y) < 0.75:
			continue
		pts.append((uv[idx[t]] + uv[idx[t + 1]] + uv[idx[t + 2]]) / 3.0)
	if pts.size() < 3:
		return []
	var lo: Vector2 = pts[0]
	var hi: Vector2 = pts[0]
	for q in pts:
		lo = lo.min(q)
		hi = hi.max(q)
	var cu := (lo + hi) * 0.5
	return [snappedf(cu.x, 0.00001), snappedf(cu.y, 0.00001), snappedf((hi - lo).length() * 0.5 + 0.004, 0.0001)]


func _sample(p: Vector3, tr: Array) -> Dictionary:
	var a: Vector3 = tr[0]
	var b: Vector3 = tr[1]
	var c: Vector3 = tr[2]
	var bc := Geometry3D.get_triangle_barycentric_coords(p, a, b, c)
	var u: Vector2 = tr[3] * bc.x + tr[4] * bc.y + tr[5] * bc.z
	var e1 := b - a
	var e2 := c - a
	var d1: Vector2 = tr[4] - tr[3]
	var d2: Vector2 = tr[5] - tr[3]
	var det := d1.x * d2.y - d1.y * d2.x
	var T := (e1 * d2.y - e2 * d1.y) / det
	var B := (e2 * d1.x - e1 * d2.x) / det
	return {"p": p, "uv": u, "c0": Vector2(T.x, T.y), "c1": Vector2(B.x, B.y)}
