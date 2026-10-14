extends SceneTree
## P13 W5C read-only diagnostic: stone-top coverage of the upper approach (s=84..100 m).
## Writes nothing. godot --headless --path . --script res://tools/p13/diag_w5c_cover.gd -- [s0 s1]
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")
const ZONE := 0.85            # the contract walking width (SWALK: 0, ±0.5, ±0.85)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var s0 := float(a[0]) if a.size() > 0 else 84.0
	var s1 := float(a[1]) if a.size() > 1 else 100.0
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	await process_frame
	for n in 3:
		await physics_frame
	var cl := SA.centerline()
	var tris: Array = []
	var srcs: Array = [v.get_node("ShrineApproachP10/StoneSteps")]
	var base_scene: Node = null
	if "--r8-baseline" in a:
		# BEFORE reference from the saved r8 stair (shrine_approach_p10.scn), independent of the W4/W5 overlays
		base_scene = (load("res://maps/village_v2/gen/shrine_approach_p10.scn") as PackedScene).instantiate()
		v.add_child(base_scene)
		srcs = [base_scene.get_node("StoneSteps")]
	var ovn := v.get_node_or_null("SandoPilotW4P13")
	if ovn != null and not ("--no-w4" in a) and not ("--r8-baseline" in a):
		for nm in ["W4Steps", "W5Upper/W4Steps", "W5C/W4Steps"]:
			var nn := ovn.get_node_or_null(nm)
			if nn != null:
				srcs.append(nn)
	for src in srcs:
		var mi := src as MeshInstance3D
		var xf := mi.global_transform
		var arr := mi.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		var n_tri: int = (idx.size() if idx != null and idx.size() > 0 else vs.size()) / 3
		for t in n_tri:
			var i0: int = idx[t * 3] if idx != null and idx.size() > 0 else t * 3
			var i1: int = idx[t * 3 + 1] if idx != null and idx.size() > 0 else t * 3 + 1
			var i2: int = idx[t * 3 + 2] if idx != null and idx.size() > 0 else t * 3 + 2
			var A := xf * vs[i0]
			var B := xf * vs[i1]
			var C := xf * vs[i2]
			var nrm := (B - A).cross(C - A)
			if absf(nrm.y) < 1e-9:
				continue
			tris.append([A, B, C, nrm.y < 0.0])  # Godot: clockwise from above = front = up-facing
	print("[COVER] stair tris=%d (StoneSteps + W4 overlay meshes)" % tris.size())
	# bounding region filter
	var kmin := int(s0 / 0.05)
	var kmax := mini(int(s1 / 0.05), cl.size() - 1)
	var bb := Rect2(cl[kmin], Vector2.ZERO).grow(6.0)
	for k in range(kmin, kmax + 1, 10):
		bb = bb.expand(cl[k])
	bb = bb.grow(6.0)
	var local: Dictionary = {}   # 0.5 m cell -> Array of tris
	var n_local := 0
	for t in tris:
		if not t[3]:
			continue
		var r := Rect2(Vector2(t[0].x, t[0].z), Vector2.ZERO).expand(Vector2(t[1].x, t[1].z)).expand(Vector2(t[2].x, t[2].z))
		if not bb.intersects(r):
			continue
		n_local += 1
		for cx in range(int(floor(r.position.x / 0.5)), int(floor(r.end.x / 0.5)) + 1):
			for cz in range(int(floor(r.position.y / 0.5)), int(floor(r.end.y / 0.5)) + 1):
				var key := Vector2i(cx, cz)
				if not local.has(key):
					local[key] = []
				(local[key] as Array).append(t)
	print("[COVER] up-facing tris in region: %d" % n_local)
	# sample grid: stone-top height vs terrain collision height (poke-through = terrain above stone top)
	var sp := v.get_world_3d().direct_space_state
	var tmi := v.get_node("Terrain/MainTerrain") as MeshInstance3D
	var ttm: TriangleMesh = tmi.mesh.generate_triangle_mesh()
	var txf_inv := tmi.global_transform.affine_inverse()
	_vis = [ttm, txf_inv, tmi.global_transform]
	var lat_n := 25
	var ds := 0.1
	var s := s0
	var lines: Array = []
	var gap_rows := 0
	var poke_cells := 0
	var poke_max := 0.0
	var tread_cells := 0
	while s <= s1 + 1e-6:
		var k := clampi(int(round(s / 0.05)), 0, cl.size() - 1)
		var tg := SA.tangent(cl, k)
		var nr := Vector2(-tg.y, tg.x)
		var row := ""
		var stone_in := 0
		var tot_in := 0
		var poke_row := 0.0
		for j in range(-lat_n, lat_n + 1):
			var lat := j * 0.1
			var p := cl[k] + nr * lat
			var sy := _stone_y(Vector2(p.x, p.y), local)
			var ty := _vis_y(p) if "--visual" in a else _terr_y(sp, p)
			if "--dbg" in a and j % 10 == 0 and int(round(s * 10)) % 5 == 0:
				print("[DBG] s=%.2f lat=%.1f stone=%.3f coll=%.3f vis=%.3f" % [s, lat, sy, ty if not "--visual" in a else _terr_y(sp, p), _vis_y(Vector2(p.x, p.y))])
			var ch := "."
			if not is_nan(sy):
				ch = "#"
				if absf(lat) <= ZONE:
					tread_cells += 1
				if not is_nan(ty) and ty > sy + 0.005:
					ch = "X"
					poke_cells += 1
					poke_max = maxf(poke_max, ty - sy)
					poke_row = maxf(poke_row, ty - sy)
			row += ch
			if absf(lat) <= ZONE:
				tot_in += 1
				if not is_nan(sy):
					stone_in += 1
		if stone_in < tot_in:
			gap_rows += 1
		lines.append("s=%6.2f %s cover=%d/%d poke_max=%.3f" % [s, row, stone_in, tot_in, poke_row])
		s += ds
	for l in lines:
		print(l)
	print("[COVER] rows with any uncovered cell (|lat|<=%.2f): %d of %d" % [ZONE, gap_rows, lines.size()])
	print("[COVER] terrain-above-stone cells (collision terrain, incl. riser feet / rear lips): %d of %d stone cells in |lat|<=%.2f; max poke %.3f m" % [poke_cells, tread_cells, ZONE, poke_max])
	v.queue_free()
	await process_frame
	quit(0)

func _stone_y(p: Vector2, local: Dictionary) -> float:
	var best := NAN
	var cell: Array = local.get(Vector2i(int(floor(p.x / 0.5)), int(floor(p.y / 0.5))), [])
	for t in cell:
		if _inside(p, t):
			var a: Vector3 = t[0]
			var b: Vector3 = t[1]
			var c: Vector3 = t[2]
			var d := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
			if absf(d) < 1e-12:
				continue
			var w1 := ((b.z - c.z) * (p.x - c.x) + (c.x - b.x) * (p.y - c.z)) / d
			var w2 := ((c.z - a.z) * (p.x - c.x) + (a.x - c.x) * (p.y - c.z)) / d
			var y := w1 * a.y + w2 * b.y + (1.0 - w1 - w2) * c.y
			if is_nan(best) or y > best:
				best = y
	return best

var _vis: Array = []
func _vis_y(p: Vector2) -> float:
	var ttm: TriangleMesh = _vis[0]
	var inv: Transform3D = _vis[1]
	var o := inv * Vector3(p.x, 90.0, p.y)
	var d := (inv.basis * Vector3.DOWN).normalized()
	var h := ttm.intersect_ray(o, d)
	if h.is_empty():
		return NAN
	return float((_vis[2] as Transform3D * (h["position"] as Vector3)).y)

func _terr_y(sp: PhysicsDirectSpaceState3D, p: Vector2) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 80.0, p.y), Vector3(p.x, -20.0, p.y))
	var ex: Array[RID] = []
	for t in 12:
		q.exclude = ex
		var h := sp.intersect_ray(q)
		if h.is_empty():
			return NAN
		if String((h["collider"] as Node).name).begins_with("TerrainCollision"):
			return float(h["position"].y)
		ex.append(h["rid"])
	return NAN

func _inside(p: Vector2, t: Array) -> bool:
	var a := Vector2(t[0].x, t[0].z)
	var b := Vector2(t[1].x, t[1].z)
	var c := Vector2(t[2].x, t[2].z)
	var d1 := (p - b).cross(a - b)
	var d2 := (p - c).cross(b - c)
	var d3 := (p - a).cross(c - a)
	var neg := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var pos := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return not (neg and pos)
