extends SceneTree
## P11 R2D 可行性檢查 2（只讀、一次載入）：N0／T0 支線を地形格網（1 m）上で等高線沿いに探索する。
## 狀態＝(格, 水面 0.01 m 量子化)。水面は下流へ非増加。
##   土渠：地面＋0.03 ≤ 水面 ≤ 地面＋0.15（既存の上段土渠＝階面＋0.07 と同じ語彙）
##   木槽：地面＋0.15 < 水面 ≤ 地面＋0.35（既存地面木槽の頂 ≤ 0.29 と同級）→ 距離コスト ×4（短区間のみに寄せる）
##   障害＝地形以外の碰撞体（幅 1.2 m 箱、Population 除外）。起終点 2.5 m 以内は免除。
##   道路（Roads ribbon）を跨ぐ格はコスト ×6、跨いだ回数と路面・水面を報告（伏越し要否）。
## 出力：支線ごとの経路・長さ・水面プロファイル・土渠／木槽の長さ・道路交差・最大高低差。
const FL := preload("res://tools/village_v2_farmland_lib.gd")
const FZ := preload("res://tools/village_v2_farmland_zone.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const X0 := 300
const X1 := 366
const Z0 := -62
const Z1 := 86
const WQ := 0.01
const EARTH_HI := 0.15
const TROUGH_HI := 0.35
const LO := 0.03

var v: Node3D
var sp: PhysicsDirectSpaceState3D
var terr: RID
var nx := X1 - X0 + 1
var nz := Z1 - Z0 + 1
var G := PackedFloat32Array()
var blocked := PackedByteArray()
var road := PackedFloat32Array()

func _init() -> void:
	_run.call_deferred()

func _idx(i: int, j: int) -> int:
	return j * nx + i

func _blocked_at(p: Vector2) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(1.8, 0.5, 1.8)   # 盛土土渠の半幅 0.85 を見込む
	q.shape = b
	q.transform = Transform3D(Basis(), Vector3(p.x, FZ.ground_h(p) + 0.32, p.y))
	q.exclude = [terr]
	for h in sp.intersect_shape(q, 8):
		var n := h.collider as Node
		if n == null:
			continue
		var path := String(v.get_path_to(n))
		if path.begins_with("Population"):
			continue
		return true
	return false

func _road_name(p: Vector2) -> String:
	for mi: MeshInstance3D in v.get_node("Roads").find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var f := mi.mesh.get_faces()
		var xf := mi.global_transform
		for t in range(0, f.size(), 3):
			var a := xf * f[t]
			var b := xf * f[t + 1]
			var c := xf * f[t + 2]
			if Geometry2D.point_is_inside_triangle(p, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)):
				return String(mi.name)
	return "?"


func _search(name: String, srcs: Array, dst: Vector2, w_need: float) -> void:
	# srcs: [[Vector2, 水面], ...]
	var NW := int(0.70 / WQ) + 1   # 水面 0–0.70
	var dist := {}
	var prev := {}
	var heap: Array = []   # [cost, key]
	var exempt := func(p: Vector2) -> bool:
		for s in srcs:
			if p.distance_to(s[0]) < 1.2:
				return true
		return p.distance_to(dst) < 2.5
	for s in srcs:
		var p: Vector2 = s[0]
		var i := roundi(p.x) - X0
		var j := roundi(p.y) - Z0
		var wq := int(floor(float(s[1]) / WQ))
		var key := (_idx(i, j)) * NW + wq
		dist[key] = 0.0
		heap.append([0.0, key])
	var di := roundi(dst.x) - X0
	var dj := roundi(dst.y) - Z0
	var best_key := -1
	var steps := 0
	while not heap.is_empty():
		# 二分ヒープ代わりに最小を線形探索すると遅いので、cost でソート済み挿入
		var top: Array = heap.pop_front()
		var key: int = top[1]
		var c: float = top[0]
		if c > float(dist.get(key, INF)) + 1e-6:
			continue
		steps += 1
		var cell := key / NW
		var wq := key % NW
		var i := cell % nx
		var j := cell / nx
		if i == di and j == dj and wq * WQ >= w_need - 1e-6:
			best_key = key
			break
		for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var ni: int = i + dd.x
			var nj: int = j + dd.y
			if ni < 0 or nj < 0 or ni >= nx or nj >= nz:
				continue
			var nc := _idx(ni, nj)
			var p := Vector2(X0 + ni, Z0 + nj)
			if blocked[nc] != 0 and not exempt.call(p):
				continue
			var g: float = G[nc]
			var step := Vector2(dd).length()
			var is_road := not is_nan(road[nc])
			# 選択肢：土渠（水面を地面＋0.15 まで自発的に落とす＝落差工）／木槽（水面を保つ、地面＋0.35 まで）
			var opts := []
			var w_e := minf(wq * WQ, g + EARTH_HI)
			if w_e >= g + LO:
				opts.append([w_e, 1.0])
			var w_t := minf(wq * WQ, g + TROUGH_HI)
			if w_t > g + EARTH_HI:
				opts.append([w_t, 4.0])   # 木槽は短区間に寄せる
			if is_road:
				# 道路の下は伏越し（地上構件なし）：水面は地面と無関係、入口→出口で 0.02 m／格 落とす
				opts = [[wq * WQ - 0.002, 6.0]]
			for o in opts:
				var w: float = o[0]
				var nwq := int(floor(w / WQ + 1e-6))
				if nwq < 0:
					continue
				var ncost: float = c + step * float(o[1])
				var nkey := nc * NW + nwq
				if ncost < float(dist.get(nkey, INF)) - 1e-6:
					dist[nkey] = ncost
					prev[nkey] = key
					var lo := 0
					var hi := heap.size()
					while lo < hi:
						var mid := (lo + hi) >> 1
						if float(heap[mid][0]) < ncost:
							lo = mid + 1
						else:
							hi = mid
					heap.insert(lo, [ncost, nkey])
	if best_key < 0:
		# 診断：到達できた格のうち dst に最も近いもの、その水面と地面、dst 周り 5×5 の障害／地面
		var bd := INF
		var bk := -1
		for kk in dist:
			var cc: int = int(kk) / NW
			var pp := Vector2(X0 + cc % nx, Z0 + cc / nx)
			var d0 := pp.distance_to(dst)
			if d0 < bd or (absf(d0 - bd) < 1e-3 and int(kk) % NW > bk % NW):
				bd = d0
				bk = int(kk)
		var bc := bk / NW
		var bp := Vector2(X0 + bc % nx, Z0 + bc / nx)
		var ring := []
		for dj2 in range(-2, 3):
			var row := ""
			for di2 in range(-2, 3):
				var ii := clampi(roundi(dst.x) - X0 + di2, 0, nx - 1)
				var jj := clampi(roundi(dst.y) - Z0 + dj2, 0, nz - 1)
				var c2 := _idx(ii, jj)
				row += "%s%.2f " % ["#" if blocked[c2] == 1 else ("v" if blocked[c2] == 2 else "."), G[c2]]
			ring.append(row)
		print("[BR] %s：経路なし（%d 状態）。dst %s に最も近い到達点 %s（距離 %.1f m、水面 %.2f、地面 %.2f）、要求水面 %.3f。dst 周り（#碰撞/田/水路 v植生 .空き）：%s" % [
			name, steps, dst, bp, bd, (bk % NW) * WQ, G[bc], w_need, " | ".join(ring)])
		return
	var path: Array = []
	var k2 := best_key
	while true:
		path.push_front(k2)
		if not prev.has(k2):
			break
		k2 = prev[k2]
	var L := 0.0
	var earth := 0.0
	var trough := 0.0
	var roads := []
	var worst_up := 0.0
	var pts := []
	var lastp := Vector2.INF
	var w_first := 0.0
	var w_last := 0.0
	var prof := []
	for idx in path.size():
		var key: int = path[idx]
		var cell := key / NW
		var p := Vector2(X0 + cell % nx, Z0 + cell / nx)
		var g: float = G[cell]
		var w := (key % NW) * WQ
		if idx == 0:
			w_first = w
		w_last = w
		if lastp != Vector2.INF:
			var s := p.distance_to(lastp)
			L += s
			if w - g > EARTH_HI:
				trough += s
			else:
				earth += s
		worst_up = maxf(worst_up, w - g)
		if not is_nan(road[cell]):
			roads.append("(%d,%d) %s 路面 %.2f 水面 %.2f" % [p.x, p.y, _road_name(p), road[cell], w])
		lastp = p
		pts.append([p.x, p.y, snappedf(w, 0.001), snappedf(g, 0.001), 0 if is_nan(road[cell]) else 1])
		if idx % 4 == 0 or idx == path.size() - 1:
			prof.append("(%d,%d) g%.2f w%.2f" % [p.x, p.y, g, w])
	print("[BR] ===== %s：長 %.1f m（土渠 %.1f／木槽 %.1f）水面 %.2f → %.2f（水頭 %.2f、勾配 %.3f %%）最大 水面−地面 %.2f、道路格 %d %s" % [
		name, L, earth, trough, w_first, w_last, w_first - w_last, (w_first - w_last) / maxf(L, 1.0) * 100.0, worst_up, roads.size(), str(roads.slice(0, 4))])
	print("[BR]   %s" % " → ".join(prof))
	print("[BR]   PATH %s" % JSON.stringify(pts))

func _run() -> void:
	v = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await physics_frame
	sp = v.get_world_3d().direct_space_state
	terr = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	var R := RLib.road_sampler(v)
	G.resize(nx * nz)
	blocked.resize(nx * nz)
	road.resize(nx * nz)
	var nb := 0
	for j in nz:
		for i in nx:
			var p := Vector2(X0 + i, Z0 + j)
			var c := _idx(i, j)
			G[c] = FZ.ground_h(p)
			road[c] = R.h(p.x, p.y)
			blocked[c] = 1 if _blocked_at(p) else 0
			nb += blocked[c]
	var P := FL.plan()
	# 田面（全田の loop）と既存の水路（主渠 lat_line・排水 drain・links・上段土渠・木槽）から 0.9 m 以内も障害
	var nf := 0
	var lines: Array = [P["upper"], P["channel"], P["drain"]]
	for bn in P["bunds"]:
		lines.append(P["bunds"][bn]["pts"])
	for bid in P["zone"]["blocks"]:
		var b: Dictionary = P["zone"]["blocks"][bid]
		lines.append(b["lat_line"])
		lines.append(b["drain"])
	for ln: Dictionary in P["zone"]["links"]:
		for key in ["path", "path_a", "path_b"]:
			if ln.has(key):
				lines.append(ln[key])
	for of: Dictionary in P["zone"]["outfalls"]:
		lines.append(of["line"])
	for j in nz:
		for i in nx:
			var c := _idx(i, j)
			if blocked[c] == 1:
				continue
			var p := Vector2(X0 + i, Z0 + j)
			var hit := false
			for fd: Dictionary in P["fields"]:
				if Geometry2D.is_point_in_polygon(p, fd["loop"]):
					hit = true
					break
			if not hit:
				# 休耕田・休耕草地・旱田（P8 内の MultiMesh 草／畝）＋1.0 m
				var polys: Array = []
				for fa: Dictionary in P["zone"]["fallow"]:
					polys.append(fa["loop"])
				for m: Dictionary in P["zone"]["meadow"]:
					polys.append(m["poly"])
				for dfd: Dictionary in P["zone"]["dry"]:
					polys.append(dfd["poly"])
				for pg in polys:
					var pp: PackedVector2Array = pg
					if Geometry2D.is_point_in_polygon(p, pp):
						hit = true
						break
					for k in pp.size():
						if Geometry2D.get_closest_point_to_segment(p, pp[k], pp[(k + 1) % pp.size()]).distance_to(p) < 1.0:
							hit = true
							break
					if hit:
						break
			if not hit:
				for ln in lines:
					var pl: PackedVector2Array = ln
					for k in pl.size() - 1:
						if Geometry2D.get_closest_point_to_segment(p, pl[k], pl[k + 1]).distance_to(p) < 1.0:
							hit = true
							break
					if hit:
						break
			if hit:
				blocked[c] = 1
				nf += 1
	# R2D-3：碰撞を持たない封存層（P9 植生・地被・草地、P10 道具）の可見物も障害（非 headless で MultiMesh 実例も読む）
	var nv := 0
	var vg := {}
	var mark := func(p2: Vector2, tag: String) -> void:
		var i := roundi(p2.x) - X0
		var j := roundi(p2.y) - Z0
		for di in [-1, 0, 1]:
			for dj in [-1, 0, 1]:
				var ii: int = i + di
				var jj: int = j + dj
				if ii < 0 or jj < 0 or ii >= nx or jj >= nz:
					continue
				if Vector2(X0 + ii, Z0 + jj).distance_to(p2) > 0.9:
					continue
				var c := _idx(ii, jj)
				if blocked[c] == 0:
					blocked[c] = 2
					vg[tag] = int(vg.get(tag, 0)) + 1
	var area := Rect2(X0, Z0, nx, nz)
	for mi: MeshInstance3D in v.find_children("*", "MeshInstance3D", true, false):
		var path := String(v.get_path_to(mi))
		if not (path.begins_with("Vegetation") or path.begins_with("Props") or path.begins_with("HumanUse") or path.begins_with("Population")):
			continue
		if mi.mesh == null or not mi.is_visible_in_tree() or String(mi.name).begins_with("LOD1") or String(mi.name).begins_with("LOD2"):
			continue
		var ab := mi.global_transform * mi.get_aabb()
		if not Rect2(ab.position.x, ab.position.z, ab.size.x, ab.size.z).intersects(area):
			continue
		if path.contains("/Ground/"):
			continue   # 地被の地面網格（平面）は渠と重ねられない対象ではなく、地面と同じ扱い
		var xf := mi.global_transform
		for sidx in mi.mesh.get_surface_count():
			var vs: PackedVector3Array = mi.mesh.surface_get_arrays(sidx)[Mesh.ARRAY_VERTEX]
			var stp := maxi(1, vs.size() / 3000)
			for q in range(0, vs.size(), stp):
				var w := xf * vs[q]
				var p2 := Vector2(w.x, w.z)
				if area.has_point(p2) and w.y > FZ.ground_h(p2) + 0.03 and w.y < FZ.ground_h(p2) + 2.5:
					mark.call(p2, path.get_slice("/", 0) + "/" + path.get_slice("/", 1))
	for mmi: MultiMeshInstance3D in v.find_children("*", "MultiMeshInstance3D", true, false):
		var path := String(v.get_path_to(mmi))
		if not path.begins_with("Vegetation") or mmi.multimesh == null or not mmi.is_visible_in_tree():
			continue
		var xf := mmi.global_transform
		for k in mmi.multimesh.instance_count:
			var o := (xf * mmi.multimesh.get_instance_transform(k)).origin
			if area.has_point(Vector2(o.x, o.z)):
				mark.call(Vector2(o.x, o.z), path.get_slice("/", 0) + "/" + path.get_slice("/", 1) + "(MM)")
	for c in blocked.size():
		nv += int(blocked[c] == 2)
	print("[BR] 格 %d×%d、障害格 %d（田面・既存水路 %d、封存植生／道具 %d：%s）" % [nx, nz, nb + nf + nv, nf, nv, str(vg)])
	var fd := {}
	for f: Dictionary in P["zone"]["feeders"]:
		fd[f["block"]] = f
	# 源：上段土渠（水面 0.27、x 339–369 z≈6）の各点 ＋ 落とし桝 0.28
	var upper: PackedVector2Array = P["upper"]
	# 終点 2 種：旧 feeder 桝（桝水面 box_w、後段の旧木槽を残す）／田区進水口 I（主渠水面 lv＋MAIN_WATER、旧木槽ごと置換）
	var n0: Dictionary = fd["N0"]
	var t0: Dictionary = fd["T0"]
	# N0：落とし桝の北面（−z、水面 0.28）／T0：送り樋の南側（+z）脇、落とし桝より西（x 337.9–338.3、水面 0.56）
	# N0：上段土渠 x≈359.5 の南唇（LipSupB）に切欠きを入れて分水（水面 0.265）。落とし桝から並走する 18 m を省く
	var n0_src := [[Vector2(359.5, 4.6), 0.265]]
	var t0_src := [[Vector2(337.9, 5.5), 0.555], [Vector2(338.3, 5.5), 0.555]]
	for f in [["N0", n0, n0_src], ["T0", t0, t0_src]]:
		var F: Dictionary = f[1]
		var tl: PackedVector2Array = F["trough"]
		_search("%s → 旧桝（要求 %.3f）" % [f[0], float(F["box_w"]) + 0.005], f[2], F["box"], float(F["box_w"]) + 0.005)
		_search("%s → 進水口 I（要求 %.3f）" % [f[0], float(F["lv"]) + FZ.MAIN_WATER + 0.005], f[2], tl[tl.size() - 1], float(F["lv"]) + FZ.MAIN_WATER + 0.005)
	quit(0)
