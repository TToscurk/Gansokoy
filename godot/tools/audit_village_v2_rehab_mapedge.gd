extends SceneTree
## P10 R5–R6 MASTER AUDIT：地圖「可抵達地面 → 無地面」出口掃描（只讀，headless）。
##   Godot --headless --path godot --script res://tools/audit_village_v2_rehab_mapedge.gd -- --scene=res://maps/trail/trail.tscn --start=x,z [--step=2] [--out=<json>]
## 方法：2 m 格向下射線（任何碰撞體，邊界牆頂不算地面）→ 從 --start 做 BFS：
##   地面→地面：上坡每格 ≤ step×tan(52°)（玩家 floor_max_angle）、下坡不限（可跳下）；線段穿過邊界牆＝擋。
##   地面→無地面：若線段不穿邊界牆，再以玩家膠囊（r 0.3、h 1.7，地面 +1.3 m）向外 cast step+0.5 m；沒被擋＝VOID_EXIT。
## 建物不當阻擋（可達集合取上界，對「找出界點」是保守的）。own_colliders=false 的圖照 main.gd 在記憶體補 trimesh。
var R := {}
var walls: Array = []   # [AABB]

func _init() -> void:
	_run.call_deferred()

func _isb(n: String) -> bool:
	return n.contains("Boundary") or n.contains("邊界") or n.contains("boundary")

func _seg_wall(a: Vector3, b: Vector3) -> bool:
	for w: AABB in walls:
		var ww := w.grow(0.3)
		if ww.intersects_segment(a, b) or ww.has_point(a) or ww.has_point(b):
			return true
	return false

func _run() -> void:
	var scene := ""
	var step := 2.0
	var out := ""
	var start := Vector2.ZERO
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene = a.trim_prefix("--scene=")
		elif a.begins_with("--step="):
			step = a.trim_prefix("--step=").to_float()
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--start="):
			var s := a.trim_prefix("--start=").split(",")
			start = Vector2(s[0].to_float(), s[1].to_float())
	var m: Node3D = (load(scene) as PackedScene).instantiate()
	root.add_child(m)
	var own: bool = m.get_meta("own_colliders", false)
	var ntm := 0
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var n := mi as MeshInstance3D
		if own and not (String(n.name) == "Terrain" or n.has_meta("needs_trimesh")):
			continue
		if not n.is_visible_in_tree() or n.mesh == null:
			continue
		var bb := n.get_aabb()
		if maxf(bb.size.x, bb.size.z) >= 8.0:
			n.create_trimesh_collision()
			ntm += 1
	for i in 4:
		await physics_frame
	var sp := m.get_world_3d().direct_space_state
	var wl := []
	for b in m.find_children("*", "StaticBody3D", true, false):
		if not _isb(String(b.name)):
			continue
		for cs in b.get_children():
			if cs is CollisionShape3D and (cs as CollisionShape3D).shape is BoxShape3D and not (cs as CollisionShape3D).disabled:
				var sz := ((cs as CollisionShape3D).shape as BoxShape3D).size
				var wb: AABB = (cs as Node3D).global_transform * AABB(-sz * 0.5, sz)
				walls.append(wb)
				wl.append([String(b.name) + "/" + String(cs.name), [snappedf(wb.position.x, 0.1), snappedf(wb.position.y, 0.1), snappedf(wb.position.z, 0.1)], [snappedf(wb.size.x, 0.1), snappedf(wb.size.y, 0.1), snappedf(wb.size.z, 0.1)]])
	var cache := {}
	var gfn := func(i: int, j: int) -> float:
		var key := Vector2i(i, j)
		if cache.has(key):
			return cache[key]
		var x := start.x + i * step
		var z := start.y + j * step
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 260.0, z), Vector3(x, -150.0, z))
		var ex: Array[RID] = []
		var y := NAN
		for k in 10:
			q.exclude = ex
			var h := sp.intersect_ray(q)
			if h.is_empty():
				break
			var c := h["collider"] as Node
			if c and _isb(String(c.name)):
				ex.append(h["rid"])
				continue
			y = float(h["position"].y)
			break
		cache[key] = y
		return y
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	var up_max := step * tan(deg_to_rad(52.0))
	var seen := {Vector2i(0, 0): true}
	var queue: Array[Vector2i] = [Vector2i(0, 0)]
	var exits := []
	var nreach := 0
	var maxr := 2000
	var y0: float = gfn.call(0, 0)
	if is_nan(y0):
		print("[EDGE] start has no ground")
		quit(2)
		return
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		nreach += 1
		var yc: float = gfn.call(c.x, c.y)
		var pc := Vector3(start.x + c.x * step, yc, start.y + c.y * step)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = c + d
			if seen.has(nb) or absi(nb.x) > maxr or absi(nb.y) > maxr:
				continue
			var yn: float = gfn.call(nb.x, nb.y)
			var pn := Vector3(start.x + nb.x * step, (yc if is_nan(yn) else yn), start.y + nb.y * step)
			if _seg_wall(pc + Vector3(0, 1.0, 0), pn + Vector3(0, 1.0, 0)):
				continue
			if is_nan(yn):
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = cap
				q.transform = Transform3D(Basis(), pc + Vector3(0, 1.3, 0))
				q.motion = Vector3(d.x, 0, d.y) * (step + 0.5)
				var r := sp.cast_motion(q)
				if r.size() == 2 and r[0] >= 0.999:
					if exits.size() < 400:
						exits.append([snappedf(pc.x, 0.1), snappedf(yc, 0.01), snappedf(pc.z, 0.1), [d.x, d.y]])
				continue
			if yn - yc > up_max:
				continue
			seen[nb] = true
			queue.append(nb)
	R = {"scene": scene, "start": [start.x, start.y], "own_colliders": own, "trimesh_added": ntm, "step": step,
		"reachable_cells": nreach, "void_exit_count": exits.size(), "void_exits": exits, "boundary_walls": wl}
	print("[EDGE] %s start=%s reachable=%d VOID_EXIT=%d walls=%d" % [scene, str(start), nreach, exits.size(), wl.size()])
	if exits.size() > 0:
		print("[EDGE] exits sample: ", exits.slice(0, 20))
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(R, "\t"))
		f.close()
	m.queue_free()
	await process_frame
	quit(0)
