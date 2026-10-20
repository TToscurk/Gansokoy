extends SceneTree
## NPC Living World：烘焙 village_v2 HERO 活動區的可走格（0.5 m）＋地面高度。
## godot --headless --path godot -s res://tools/npc_life/bake_npc_life_walkgrid.gd -- [--map=village_v2]
## 輸出 res://data/npc_life/<map>_walk.bin（zstd 壓縮）：[w*h 位元組 code][w*h int16 高度 cm]
##   code 0＝不可走；1＝主街／道路；2＝巷；3＝空地；4＝貼近障礙（走得過但不偏好）
## 判定（每格中心）：
##   由上往下收集表面（最多 5 層）；每層「法線 y ≥ 0.75、y ≥ -0.25（非河床／水渠）、頭頂淨空 ≥ 1.9 m、
##   半徑 0.25 m 膠囊（底離地 0.35 m）不碰撞」即為候選站立層。
##   再從 hub 地面層做 3D 連通（相鄰格高差 ≤ 0.45 m 才相連），每格取被連到的那一層：屋頂成孤島、橋面接上道路。
##   與四鄰高差 > 0.45 m 的邊緣格不可走（緣側等落差改用資料裡的 link 直線）。
##   站著不動（mode=idle）的群眾 NPC 周圍 0.55 m 不可走。
## 烘完讀 data/npc_life/<map>.json 的 places／objects，逐點回報可走與否、從 hub 是否連通（擺放驗證）。

var MAP := "village_v2"
const CELL := 0.5
const X0 := 176.0
const Z0 := -76.0
const W := 512
const H := 568

var scene: Node3D
var _frame := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			MAP = a.substr(6)
	scene = (load("res://maps/%s/%s.tscn" % [MAP, MAP]) as PackedScene).instantiate()
	root.add_child(scene)


func _physics_process(_d: float) -> bool:
	_frame += 1
	if _frame < 4:
		return false
	_bake()
	quit(0)
	return true


func _bake() -> void:
	var t0 := Time.get_ticks_msec()
	var ss := scene.get_world_3d().direct_space_state
	var excl: Array[RID] = []
	var idle_npcs: Array[Vector2] = []
	for b in scene.find_children("*", "PhysicsBody3D", true, false):
		if String(b.get_path()).find("Population") >= 0:
			excl.append((b as PhysicsBody3D).get_rid())
			if b.get_script() != null and str(b.get("mode")) == "idle" and b.get_node_or_null("NPC") != null:
				# HERO 自己（之後會走動）不算障礙
				if not (String(b.name) in ["K1_keine", "M1_marisa", "K1_kosuzu", "A1_akyuu", "R1_reimu"]):
					idle_npcs.append(Vector2(b.global_position.x, b.global_position.z))
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25
	cap.height = 1.2
	var qp := PhysicsShapeQueryParameters3D.new()
	qp.shape = cap
	qp.exclude = excl
	qp.collide_with_areas = false
	var code := PackedByteArray()
	code.resize(W * H)
	var hgt := PackedFloat32Array()
	hgt.resize(W * H)
	# 每格的候選站立層（可能多層：橋面／橋下、緣側／庭、屋頂…）
	var layers: Array = []
	layers.resize(W * H)
	for j in H:
		var z := Z0 + (j + 0.5) * CELL
		for i in W:
			var x := X0 + (i + 0.5) * CELL
			var surf: Array = []   # [y, normal_y]
			var from_y := 60.0
			for _k in 5:
				var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, -12.0, z))
				q.exclude = excl
				var r := ss.intersect_ray(q)
				if r.is_empty():
					break
				surf.append([r.position.y, (r.normal as Vector3).y])
				from_y = r.position.y - 0.03
			var cand := PackedFloat32Array()
			for k in surf.size():
				var y: float = surf[k][0]
				if surf[k][1] < 0.75 or y < -0.25:
					continue
				var head := INF if k == 0 else float(surf[k - 1][0]) - y
				if head < 1.9:
					continue
				qp.transform = Transform3D(Basis.IDENTITY, Vector3(x, y + 0.95, z))
				if not ss.intersect_shape(qp, 1).is_empty():
					continue
				cand.append(y)
			layers[j * W + i] = cand
	# 從 hub 的地面層做 3D 連通（相鄰格高差 ≤ 0.45 m 才相連）：屋頂成孤島、橋面接上道路
	var seed_p := Vector2(234.0, 104.0)
	var dp0 := "res://data/npc_life/%s.json" % MAP
	if FileAccess.file_exists(dp0):
		var d0: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dp0))
		seed_p = _v2(d0.places[d0.get("hub", "gate")])
	var sc := _cell(seed_p)
	var sl: PackedFloat32Array = layers[sc.y * W + sc.x]
	if sl.is_empty():
		push_error("[BAKE] hub 格沒有可站層")
		return
	var seen := PackedByteArray()
	seen.resize(W * H)
	var queue: Array[int] = [sc.y * W + sc.x]
	seen[sc.y * W + sc.x] = 1
	hgt[sc.y * W + sc.x] = sl[sl.size() - 1]
	code[sc.y * W + sc.x] = 3
	var qi := 0
	while qi < queue.size():
		var idx: int = queue[qi]
		qi += 1
		var ci := idx % W
		var cj := idx / W
		var y0: float = hgt[idx]
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ii: int = ci + d.x
			var jj: int = cj + d.y
			if ii < 0 or jj < 0 or ii >= W or jj >= H:
				continue
			var n2 := jj * W + ii
			if seen[n2] == 1:
				continue
			var best := INF
			for y in (layers[n2] as PackedFloat32Array):
				if absf(y - y0) <= 0.45 and absf(y - y0) < absf(best - y0):
					best = y
			if best == INF:
				continue
			seen[n2] = 1
			hgt[n2] = best
			code[n2] = 3
			queue.append(n2)
	# 站立群眾
	for p in idle_npcs:
		_disc(code, p, 0.55, 0)
	# 與四鄰高差過大 → 邊緣
	var edge := PackedByteArray()
	edge.resize(W * H)
	for j in H:
		for i in W:
			var idx := j * W + i
			if code[idx] == 0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ii: int = i + d.x
				var jj: int = j + d.y
				if ii < 0 or jj < 0 or ii >= W or jj >= H:
					continue
				var n2 := jj * W + ii
				if code[n2] != 0 and absf(hgt[n2] - hgt[idx]) > 0.45:
					edge[idx] = 1
	for k in W * H:
		if edge[k] == 1:
			code[k] = 0
	# 貼近障礙（1 格內有不可走）→ 4
	var near := PackedByteArray()
	near.resize(W * H)
	for j in range(1, H - 1):
		for i in range(1, W - 1):
			var idx := j * W + i
			if code[idx] == 0:
				continue
			if code[idx - 1] == 0 or code[idx + 1] == 0 or code[idx - W] == 0 or code[idx + W] == 0:
				near[idx] = 1
	# 道路／巷（layout 中心線）
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/village_v2/layout_v2.json")) if MAP == "village_v2" else {}
	for r in layout.get("roads", []):
		_polyline(code, r.pts, float(r.half_w) - 0.5, 1)
	for r in layout.get("lanes", []):
		_polyline(code, r.pts, float(r.half_w) - 0.3, 2)
	for k in W * H:
		if near[k] == 1 and code[k] != 0:
			code[k] = 4
	var walk := 0
	for k in W * H:
		if code[k] != 0:
			walk += 1
	var path := "res://data/npc_life/%s_walk.bin" % MAP
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/npc_life"))
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	f.store_buffer(code)
	var hb := PackedByteArray()
	hb.resize(W * H * 2)
	for k in W * H:
		hb.encode_s16(k * 2, clampi(roundi(hgt[k] * 100.0), -32000, 32000))
	f.store_buffer(hb)
	f.close()
	print("[BAKE] %s %dx%d cell %.2f walkable %d (%.1f%%) idle_npc %d  %.1fs → %s" % [MAP, W, H, CELL, walk, 100.0 * walk / (W * H), idle_npcs.size(), (Time.get_ticks_msec() - t0) / 1000.0, path])
	_validate(code)


func _disc(code: PackedByteArray, p: Vector2, r: float, v: int) -> void:
	var c := _cell(p)
	var n := ceili(r / CELL)
	for dj in range(-n, n + 1):
		for di in range(-n, n + 1):
			var i := c.x + di
			var j := c.y + dj
			if i < 0 or j < 0 or i >= W or j >= H:
				continue
			var cx := X0 + (i + 0.5) * CELL
			var cz := Z0 + (j + 0.5) * CELL
			if Vector2(cx, cz).distance_to(p) <= r:
				code[j * W + i] = v


func _polyline(code: PackedByteArray, pts: Array, hw: float, v: int) -> void:
	for s in range(pts.size() - 1):
		var a := Vector2(pts[s][0], pts[s][1])
		var b := Vector2(pts[s + 1][0], pts[s + 1][1])
		var steps := ceili(a.distance_to(b) / (CELL * 0.5))
		for t in steps + 1:
			var p := a.lerp(b, float(t) / maxf(steps, 1))
			var c := _cell(p)
			var n := ceili(hw / CELL)
			for dj in range(-n, n + 1):
				for di in range(-n, n + 1):
					var i := c.x + di
					var j := c.y + dj
					if i < 0 or j < 0 or i >= W or j >= H:
						continue
					var idx := j * W + i
					if code[idx] == 0 or code[idx] == 1:
						continue
					if Vector2(X0 + (i + 0.5) * CELL, Z0 + (j + 0.5) * CELL).distance_to(p) <= hw:
						code[idx] = mini(code[idx], v) if code[idx] != 4 else v


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - X0) / CELL), floori((p.y - Z0) / CELL))


## 讀 places／objects，逐點檢查：所在格可走、與 hub 連通。
func _validate(code: PackedByteArray) -> void:
	var dp := "res://data/npc_life/%s.json" % MAP
	if not FileAccess.file_exists(dp):
		print("[BAKE] 無 %s，略過擺放驗證" % dp)
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dp))
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, W, H)
	g.cell_size = Vector2(CELL, CELL)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.update()
	for j in H:
		for i in W:
			if code[j * W + i] == 0:
				g.set_point_solid(Vector2i(i, j), true)
	var hub := _cell(_v2(data.places[data.get("hub", "gate")]))
	var pts := {}
	for k in data.places:
		pts["place:" + k] = _v2(data.places[k])
	for o in data.get("objects", []):
		pts["obj:%s.stand" % o.id] = _v2(o.get("link", o.stand))
	for h in data.get("homes", {}):
		var hd: Dictionary = data.homes[h]
		pts["home:%s" % h] = _v2(hd.get("link", hd.at))
	var bad := 0
	for k in pts:
		var p: Vector2 = pts[k]
		var c := _cell(p)
		var ok_cell := c.x >= 0 and c.y >= 0 and c.x < W and c.y < H and code[c.y * W + c.x] != 0
		var reach := false
		if ok_cell:
			reach = g.get_id_path(hub, c).size() > 0
		if not (ok_cell and reach):
			bad += 1
		print("[PLACE] %s %s (%.1f, %.1f) cell=%s reach=%s" % ["PASS" if ok_cell and reach else "FAIL", k, p.x, p.y, ok_cell, reach])
	print("[BAKE] 擺放驗證 %d 點，FAIL %d" % [pts.size(), bad])


func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))
