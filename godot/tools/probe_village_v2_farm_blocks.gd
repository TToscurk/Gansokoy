extends SceneTree
## P8 全區：凍結地形上「可切田」平台塊的量測（資料推導工具，不是 validator、不改任何場景）。
## 載入 village_v2.tscn，對農田多邊形 bbox 每 1 m 垂直射線：
##   平＝地形碰撞高與 TLib.farm_level 差 < FLAT_TOL；
##   空＝該點沒有農田以外的碰撞體（Districts/FarmlandEast 自身的田埂／水路忽略），
##       且不在道路緩衝、r5 取水水路、水車、傳送門、平台 pad 附近；
## 平且空的格先侵蝕 ERODE 格（田埂腳與外側草坡落在平面上），再依階面高 flood fill，
## 每個連通塊逐列取最長連續段 → 西緣 L(z)／東緣 R(z) 折線（Douglas–Peucker 簡化）。
## 另沿各農路中心線每 1 m 取路面高（跨路水理判定：暗渠／涵洞 vs 伏越し）。
## 輸出 res://data/village_v2_p8_blocks.json＋village_v2_p8_ground.json（全 bbox 地面高）；地形凍結，所以只在場景結構變動時重跑：
##   Godot --headless --path . --script res://tools/probe_village_v2_farm_blocks.gd
const TLib := preload("res://tools/village_v2_terrain_lib.gd")
const FL := preload("res://tools/village_v2_farmland_lib.gd")
const OUT := "res://data/village_v2_p8_blocks.json"
const GROUND_OUT := "res://data/village_v2_p8_ground.json"
const FLAT_TOL := 0.012
const ERODE := 1
const MIN_AREA := 250.0
const ROAD_PAD := {"farm": 1.4, "secondary": 2.0}
const DEFAULT_ROAD_PAD := 2.5

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/village_v2/layout_v2.json"))
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	await physics_frame
	await physics_frame
	var trid := (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	var space := v.get_world_3d().direct_space_state
	var own := v.get_node_or_null("Districts/FarmlandEast")
	var poly := TLib.pts(L["districts"]["Farmland"]["poly"])
	var bb := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		bb = bb.expand(p)
	bb = bb.grow(2.0)
	var x0 := floori(bb.position.x)
	var z0 := floori(bb.position.y)
	var nx := ceili(bb.size.x) + 1
	var nz := ceili(bb.size.y) + 1
	# 排除：道路緩衝、r5 取水、水車、傳送門、平台 pad
	var lines: Array = []   # [PackedVector2Array, 半寬]
	for road: Dictionary in L["roads"]:
		lines.append([TLib.pts(road["pts"]), float(road["half_w"]) + float(ROAD_PAD.get(String(road.get("class", "")), DEFAULT_ROAD_PAD))])
	lines.append([FL._pa(FL.UPPER), 1.9])
	lines.append([FL._pa(FL.TROUGH), 1.4])
	var chute := PackedVector2Array()
	for c: Vector3 in FL.CHUTE:
		chute.append(Vector2(c.x, c.z))
	lines.append([chute, 1.8])
	var discs: Array = [[FL.DROP_BOX, 2.0], [FL.SIPHON[0], 1.6], [FL.SIPHON[1], 1.6]]
	for lm: Dictionary in L["landmarks"]:
		if String(lm["id"]).begins_with("LANDMARK_WATERWHEEL"):
			discs.append([Vector2(lm["at"][0], lm["at"][1]), 7.0])
	for pt: Dictionary in L.get("portals", []):
		var a: Variant = pt.get("at", null)
		if a is Array:
			discs.append([Vector2(a[0], a[1]), 5.0])
	var pads: Array = TLib.pads(L)
	# 格：0＝不可用、1＝平且空
	var level := PackedFloat32Array()
	level.resize(nx * nz)
	var ok := PackedByteArray()
	ok.resize(nx * nz)
	var blocked_by := {}
	# 全 bbox 地形碰撞高（ground）與「有農田以外碰撞體」旗標（occ）：供全區生成器的跨路／出水口／連接水路取地面高
	var ground := PackedFloat32Array()
	ground.resize(nx * nz)
	var occ := PackedByteArray()
	occ.resize(nx * nz)
	for ix in nx:
		for iz in nz:
			var p := Vector2(x0 + ix, z0 + iz)
			var i := ix * nz + iz
			var fl := TLib.farm_level(L, p)
			level[i] = fl
			var inside := Geometry2D.is_point_in_polygon(p, poly)
			var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 20, p.y), Vector3(p.x, -20, p.y))
			var ex: Array[RID] = []
			var hit := {}
			var other := ""
			for k in 24:
				q.exclude = ex
				hit = space.intersect_ray(q)
				if hit.is_empty() or hit["rid"] == trid:
					break
				var col := hit["collider"] as Node
				if other == "" and not (own != null and own.is_ancestor_of(col)):
					other = String(v.get_path_to(col))
				ex.append(hit["rid"])
			ground[i] = -99.0 if hit.is_empty() else float(hit["position"].y)
			occ[i] = 1 if other != "" else 0
			if not inside:
				continue
			if hit.is_empty() or absf(float(hit["position"].y) - fl) > FLAT_TOL:
				continue
			if other != "":
				blocked_by[other.get_slice("/", 0) + "/" + other.get_slice("/", 1)] = true
				continue
			var bad := false
			for ln: Array in lines:
				if TLib.polyline_d(ln[0], p) < float(ln[1]):
					bad = true
					break
			if not bad:
				for dc: Array in discs:
					if p.distance_to(dc[0]) < float(dc[1]):
						bad = true
						break
			if not bad:
				for pd: Variant in pads:
					if pd is Dictionary and (pd as Dictionary).has("poly"):
						var pp := TLib.pts((pd as Dictionary)["poly"])
						if Geometry2D.is_point_in_polygon(p, pp):
							bad = true
							break
			if not bad:
				ok[i] = 1
	# 侵蝕（四鄰）
	for it in ERODE:
		var nxt := ok.duplicate()
		for ix in nx:
			for iz in nz:
				var i := ix * nz + iz
				if ok[i] == 0:
					continue
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var jx := ix + d.x
					var jz := iz + d.y
					if jx < 0 or jz < 0 or jx >= nx or jz >= nz or ok[jx * nz + jz] == 0 or absf(level[jx * nz + jz] - level[i]) > 1e-4:
						nxt[i] = 0
						break
		ok = nxt
	# flood fill（同階面）
	var comp := PackedInt32Array()
	comp.resize(nx * nz)
	comp.fill(-1)
	var blocks: Array = []
	for i0 in nx * nz:
		if ok[i0] == 0 or comp[i0] >= 0:
			continue
		var cid := blocks.size()
		var stack := [i0]
		comp[i0] = cid
		var cells: Array = []
		while not stack.is_empty():
			var i: int = stack.pop_back()
			cells.append(i)
			var ix := i / nz
			var iz := i % nz
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var jx := ix + d.x
				var jz := iz + d.y
				if jx < 0 or jz < 0 or jx >= nx or jz >= nz:
					continue
				var j := jx * nz + jz
				if ok[j] == 1 and comp[j] < 0 and absf(level[j] - level[i]) < 1e-4:
					comp[j] = cid
					stack.append(j)
		blocks.append({"cells": cells, "level": level[i0]})
	var out_blocks: Array = []
	for b: Dictionary in blocks:
		var cells: Array = b["cells"]
		if cells.size() < MIN_AREA:
			continue
		var rows := {}
		for i: int in cells:
			var z := z0 + i % nz
			if not rows.has(z):
				rows[z] = []
			rows[z].append(x0 + i / nz)
		var zs: Array = rows.keys()
		zs.sort()
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		for z: int in zs:
			var xs: Array = rows[z]
			xs.sort()
			var best := [xs[0], xs[0]]
			var s: int = xs[0]
			for k in range(1, xs.size() + 1):
				if k == xs.size() or int(xs[k]) != int(xs[k - 1]) + 1:
					if int(xs[k - 1]) - s > best[1] - best[0]:
						best = [s, int(xs[k - 1])]
					if k < xs.size():
						s = xs[k]
			if best[1] - best[0] < 6:
				continue
			left.append(Vector2(best[0], z))
			right.append(Vector2(best[1], z))
		if left.size() < 8:
			continue
		out_blocks.append({"level": snappedf(float(b["level"]), 0.001), "area": cells.size(),
			"L": _arr(_dp(left, 0.8)), "R": _arr(_dp(right, 0.8)), "z0": left[0].y, "z1": left[left.size() - 1].y})
	# 農路路面高（每 1 m）
	var surf := {}
	for road: Dictionary in L["roads"]:
		if String(road.get("class", "")) != "farm":
			continue
		var pts := TLib.pts(road["pts"])
		var arr: Array = []
		for j in pts.size() - 1:
			var n := ceili(pts[j].distance_to(pts[j + 1]))
			for k in n:
				var p := pts[j].lerp(pts[j + 1], float(k) / n)
				var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 20, p.y), Vector3(p.x, -20, p.y))
				q.exclude = []
				var hit := {}
				var ex: Array[RID] = []
				for m in 24:
					q.exclude = ex
					hit = space.intersect_ray(q)
					if hit.is_empty() or hit["rid"] == trid:
						break
					ex.append(hit["rid"])
				if not hit.is_empty():
					arr.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(float(hit["position"].y), 0.001)])
		surf[road["name"]] = arr
	var names: Array = blocked_by.keys()
	names.sort()
	var gh: Array = []
	var oc := ""
	for iz in nz:
		for ix in nx:
			gh.append(snappedf(ground[ix * nz + iz], 0.001))
			oc += "1" if occ[ix * nz + iz] == 1 else "0"
	var gf := FileAccess.open(GROUND_OUT, FileAccess.WRITE)
	gf.store_string(JSON.stringify({"_note": "P8 全區生成器用地形碰撞高（1 m 格，列優先：index = iz*nx + ix；-99＝無地形）；occ＝該格有農田以外的碰撞體。由 tools/probe_village_v2_farm_blocks.gd 產生，勿手改。",
		"x0": x0, "z0": z0, "nx": nx, "nz": nz, "h": gh, "occ": oc}))
	gf.close()
	var data := {"_note": "P8 全區可切田平台塊（凍結地形實測；由 tools/probe_village_v2_farm_blocks.gd 產生，勿手改）。L／R＝各列最長連續平且空段的西／東端（侵蝕 %d m 後，D-P 0.8 m 簡化）；road_surface＝農路中心線每 1 m 地形碰撞高。" % ERODE,
		"flat_tol": FLAT_TOL, "road_pad": ROAD_PAD, "blocks": out_blocks, "road_surface": surf, "blocked_by": names}
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	for b: Dictionary in out_blocks:
		print("[BLOCKS] level %.2f area %d z %.0f..%.0f L0 %s R0 %s" % [b["level"], b["area"], b["z0"], b["z1"], str(b["L"][0]), str(b["R"][0])])
	print("[BLOCKS] %d blocks; blocked_by %s" % [out_blocks.size(), ", ".join(names)])
	quit(0)

static func _arr(p: PackedVector2Array) -> Array:
	var out: Array = []
	for q in p:
		out.append([q.x, q.y])
	return out

static func _dp(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var a := pts[0]
	var b := pts[pts.size() - 1]
	var best := -1.0
	var bi := 0
	for i in range(1, pts.size() - 1):
		var d := Geometry2D.get_closest_point_to_segment(pts[i], a, b).distance_to(pts[i])
		if d > best:
			best = d
			bi = i
	if best > eps:
		var l := _dp(pts.slice(0, bi + 1), eps)
		var r := _dp(pts.slice(bi), eps)
		l.remove_at(l.size() - 1)
		l.append_array(r)
		return l
	return PackedVector2Array([a, b])
