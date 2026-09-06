extends SceneTree
## 量產出物，不量參數：載入 gen/b1_street.tscn，回報每棟世界 AABB、
## 各排 z 覆蓋、以及建築之間的實際重疊（XZ 投影）。

func _wbox(n: Node3D) -> AABB:
	var acc: AABB = AABB()
	var has: bool = false
	var stack: Array = [[n, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var pair: Array = stack.pop_back()
		var node: Node = pair[0]
		var xf: Transform3D = pair[1]
		if node is Node3D:
			xf = xf * (node as Node3D).transform
		if node is MeshInstance3D:
			var mi: MeshInstance3D = node
			if mi.mesh != null:
				var a: AABB = xf * mi.mesh.get_aabb()
				if has:
					acc = acc.merge(a)
				else:
					acc = a
					has = true
		for c in node.get_children():
			stack.push_back([c, xf])
	return acc

func _init() -> void:
	var scn: PackedScene = load("res://maps/slice/gen/b1_street.tscn")
	var root: Node3D = scn.instantiate() as Node3D
	var boxes: Array = []
	var y_min: float = 1e9
	var y_max: float = -1e9
	for c in root.get_children():
		if not (c is Node3D):
			continue
		var nm: String = String(c.name)
		if nm in ["StreetPaving", "PlazaGround", "AlleyWest", "AlleyEast"]:
			continue
		if nm == "PlazaMarket":
			# 市集道具逐件量：必須在廣場範圍內，且不得插進建築
			for p in (c as Node3D).get_children():
				if not (p is Node3D):
					continue
				var pb: AABB = _wbox(p as Node3D)
				boxes.append(["市集/" + String(p.name), pb])
			continue
		var bb: AABB = _wbox(c as Node3D)
		boxes.append([nm, bb])
		y_min = minf(y_min, bb.position.y)
		y_max = maxf(y_max, bb.position.y + bb.size.y)
	print("BUILDINGS %d" % boxes.size())
	print("Y_RANGE %.3f .. %.3f" % [y_min, y_max])
	# 底面偏差：全部應落在 -0.15 附近
	var worst: float = 0.0
	var worst_n: String = ""
	for b in boxes:
		# 市集道具的沉降基準是 -0.04（幾乎貼地），建築是 -0.15
		var base: float = -0.04 if String(b[0]).begins_with("市集/") else -0.15
		var d: float = absf(b[1].position.y - base)
		if d > worst:
			worst = d
			worst_n = b[0]
	print("WORST_BOTTOM_DEV %.3f (%s)" % [worst, worst_n])
	# XZ 重疊（容許 0.05 誤差）
	var hits: int = 0
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			var a: AABB = boxes[i][1]
			var b2: AABB = boxes[j][1]
			var ox: float = minf(a.position.x + a.size.x, b2.position.x + b2.size.x) - maxf(a.position.x, b2.position.x)
			var oz: float = minf(a.position.z + a.size.z, b2.position.z + b2.size.z) - maxf(a.position.z, b2.position.z)
			if ox > 0.05 and oz > 0.05:
				hits += 1
				if hits <= 12:
					print("OVERLAP %s <-> %s  x=%.2f z=%.2f" % [boxes[i][0], boxes[j][0], ox, oz])
	print("OVERLAPS %d" % hits)
	# 市集道具是否越出広場（x 214.5..231, z 6..44，容許 2.5 m 溢出）
	var stray: int = 0
	for b3 in boxes:
		if not String(b3[0]).begins_with("市集/"):
			continue
		var a3: AABB = b3[1]
		if a3.position.x < 212.0 or a3.position.x + a3.size.x > 233.5 				or a3.position.z < 3.5 or a3.position.z + a3.size.z > 46.5:
			stray += 1
			if stray <= 6:
				print("STRAY %s  x %.1f..%.1f z %.1f..%.1f" % [
					b3[0], a3.position.x, a3.position.x + a3.size.x,
					a3.position.z, a3.position.z + a3.size.z])
	print("MARKET_STRAY %d (必須是 0)" % stray)
	# 各群 x/z 範圍
	var groups: Dictionary = {}
	for b in boxes:
		var key: String = "front_W"
		var nm2: String = b[0]
		if nm2.contains("_東裏_"):
			key = "back_E"
		elif nm2.contains("_西裏_"):
			key = "back_W"
		elif nm2.contains("_東_"):
			key = "front_E"
		elif nm2 == "大鳥居":
			key = "torii"
		if not groups.has(key):
			groups[key] = [1e9, -1e9, 1e9, -1e9]
		var g: Array = groups[key]
		g[0] = minf(g[0], b[1].position.x)
		g[1] = maxf(g[1], b[1].position.x + b[1].size.x)
		g[2] = minf(g[2], b[1].position.z)
		g[3] = maxf(g[3], b[1].position.z + b[1].size.z)
		groups[key] = g
	for k in groups:
		var g2: Array = groups[k]
		print("GROUP %-8s x %.1f..%.1f   z %.1f..%.1f" % [k, g2[0], g2[1], g2[2], g2[3]])
	root.free()
	quit()
