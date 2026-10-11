extends SceneTree
## P11 R2D 可行性檢查（只讀、headless、一次載入）：竜骨車系統の実際の水面 → N0／T0 落とし桝までの路線を 1 m ごとに取樣。
## 各点：地形（TerrainCollision）、最上面の碰撞体（NodePath）、道路面（Roads ribbon）、幅 1.2 m・高さ 0.6 m の箱に入る碰撞体。
##   godot --headless --path . --script res://tools/p11r2d/probe_branch_routes.gd
const FL := preload("res://tools/village_v2_farmland_lib.gd")
const FZ := preload("res://tools/village_v2_farmland_zone.gd")
const TLib := preload("res://tools/village_v2_terrain_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")

var v: Node3D
var sp: PhysicsDirectSpaceState3D
var terr: RID

static func _at(pts: PackedVector2Array, s: float) -> Vector2:
	var acc := 0.0
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		if acc + seg >= s:
			return pts[i].lerp(pts[i + 1], (s - acc) / maxf(seg, 1e-6))
		acc += seg
	return pts[pts.size() - 1]

func _init() -> void:
	_run.call_deferred()

func _terrain(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -20, z))
	var ex: Array[RID] = []
	for t in 24:
		q.exclude = ex
		var h := sp.intersect_ray(q)
		if h.is_empty():
			return NAN
		if h.rid == terr:
			return h.position.y
		ex.append(h.rid)
	return NAN

func _top(x: float, z: float) -> Array:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60, z), Vector3(x, -20, z))
	var h := sp.intersect_ray(q)
	if h.is_empty():
		return [NAN, ""]
	return [h.position.y, String(v.get_path_to(h.collider as Node))]

func _box_hits(p: Vector2, d: Vector2, g: float) -> Array:
	var q := PhysicsShapeQueryParameters3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(1.2, 0.6, 1.0)
	q.shape = b
	q.transform = Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)), Vector3(p.x, g + 0.32, p.y))
	q.exclude = [terr]
	var out := []
	for h in sp.intersect_shape(q, 16):
		var s := String(v.get_path_to(h.collider as Node))
		if not s in out:
			out.append(s)
	return out

func _route(name: String, pts: PackedVector2Array, w0: float, w1: float, R: RLib.TriSampler) -> void:
	var L := FL._length(pts)
	var n := ceili(L)
	print("[RT] ===== %s 長 %.1f m  水面 %.3f → %.3f（水頭 %.3f、勾配 %.3f %%）" % [name, L, w0, w1, w0 - w1, (w0 - w1) / L * 100.0])
	var worst_above := 0.0
	var worst_cut := 0.0
	var obst := {}
	var roads := []
	for k in n + 1:
		var s := minf(k, L)
		var p := _at(pts, s)
		var t := s / L
		var wl := lerpf(w0, w1, t)
		var g := _terrain(p.x, p.y)
		var tp := _top(p.x, p.y)
		var ry := R.h(p.x, p.y)
		var d := (_at(pts, minf(s + 0.5, L)) - _at(pts, maxf(s - 0.5, 0.0))).normalized()
		var hits := _box_hits(p, d, g)
		for hname in hits:
			if not obst.has(hname):
				obst[hname] = [s, p]
		if not is_nan(ry):
			roads.append("s%.0f 路面 %.2f（水面 %.2f）" % [s, ry, wl])
		worst_above = maxf(worst_above, wl - g)
		worst_cut = maxf(worst_cut, g - (wl - 0.10))
		if k % 3 == 0 or not hits.is_empty() or not is_nan(ry):
			print("[RT]  s %5.1f (%.2f, %.2f) 地形 %.3f 水面 %.3f 水面−地形 %+.3f  最上面 %.3f %s  道路 %s  箱 %s" % [s, p.x, p.y, g, wl, wl - g, tp[0], tp[1].get_file(), "—" if is_nan(ry) else "%.3f" % ry, str(hits)])
	print("[RT]  水面が地形より最大 %.3f m 上（盛土／木槽が必要な高さ）、地形が水面−0.10 より最大 %.3f m 上（掘削）" % [worst_above, worst_cut])
	print("[RT]  道路 %d 点 %s" % [roads.size(), str(roads.slice(0, 6))])
	for k in obst:
		print("[RT]  障害 %s 初出 s %.1f %s" % [k, obst[k][0], obst[k][1]])

func _run() -> void:
	v = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await physics_frame
	sp = v.get_world_3d().direct_space_state
	terr = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/village_v2/layout_v2.json"))
	var drop_w := TLib.farm_level(L, FL.DROP_BOX) + FL.UPPER_LIFT + 0.01
	var feed_w := [FL.FEED[0].y + 0.06, FL.FEED[1].y + 0.06]
	print("[RT] 竜骨車 吐き口樋底 %.2f／送り樋 水面 %.3f→%.3f（壁頂 %.3f→%.3f）／落とし桝 %s 水面 %.3f（地形 %.3f）／上段土渠 %.3f" % [
		FL.RYU_HIGH.y, feed_w[0], feed_w[1], FL.FEED[0].y + FL.FEED_WALL - 0.04, FL.FEED[1].y + FL.FEED_WALL - 0.04, FL.DROP_BOX, drop_w, _terrain(FL.DROP_BOX.x, FL.DROP_BOX.y), TLib.farm_level(L, FL.DROP_BOX) + FL.UPPER_LIFT])
	var P := FL.plan()
	var R := RLib.road_sampler(v)
	var fd := {}
	for f: Dictionary in P["zone"]["feeders"]:
		fd[f["block"]] = f
		print("[RT] feeder %s：桝 %s 水面 %.3f 地形 %.3f、木槽 %s 槽底 %.3f→%.3f、block lv %.3f（主渠水面 %.3f）" % [f["block"], f["box"], float(f["box_w"]), _terrain((f["box"] as Vector2).x, (f["box"] as Vector2).y), f["trough"], float(f["bot"][0]), float(f["bot"][1]), float(f["lv"]), float(f["lv"]) + FZ.MAIN_WATER])
	# N0：落とし桝 → N0 桝（直線）
	var n0: Dictionary = fd["N0"]
	_route("N0 ← 落とし桝", PackedVector2Array([FL.DROP_BOX + Vector2(0.0, -0.5), n0["box"]]), drop_w - 0.01, float(n0["box_w"]) + 0.02, R)
	# T0：送り樋の末端（落とし桝の手前）→ T0 桝（直線）
	var t0: Dictionary = fd["T0"]
	_route("T0 ← 送り樋末端", PackedVector2Array([Vector2(FL.FEED[1].x, FL.FEED[1].z) + Vector2(0.0, 0.5), t0["box"]]), feed_w[1] - 0.02, float(t0["box_w"]) + 0.02, R)
	quit(0)
