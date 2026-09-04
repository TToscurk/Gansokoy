extends SceneTree
## Measure the CURRENT state of 鯢吞亭 / 霧雨店 / 龍石像橋 and the colliders that
## claim to cover them: mesh AABB vs hull AABB (offset = stale bake), triangle
## counts (does a trimesh fit the budget), and a walk sweep across the bridge
## deck (an arched bridge under a convex hull is a sealed lump, not a walkway).
##
## Run: godot --headless --path godot --script tools/probe_teahouse_bridge.gd

const TARGETS := ["鯢吞亭", "霧雨店", "龍石像橋"]
const RADIUS := 0.45
const HEIGHT := 1.7

var _main: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	_main.load_map("slice", "")
	for i in 6:
		await physics_frame
	var map: Node = _main.map_root
	# The runtime LOD swap replaces meshes in place, so an un-disabled cull
	# makes every per-mesh AABB / triangle count read as the decimated one.
	var cull := map.get_node_or_null("場景效能裁剪")
	if cull != null:
		cull.set("啟用", false)
		await process_frame
	var space: PhysicsDirectSpaceState3D = map.get_world_3d().direct_space_state
	var mask: int = _main.player.collision_mask

	var bc := map.get_node_or_null("建物碰撞")

	for t in TARGETS:
		var n := map.get_node_or_null(t)
		print("── %s ──" % t)
		if n == null:
			print("  節點不存在")
			continue
		var total_tris := 0
		var box := AABB()
		var first := true
		for mi in _meshes(n):
			if mi.mesh == null:
				continue
			var tris := _tris(mi.mesh)
			total_tris += tris
			var b: AABB = mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
			print("  mesh %-42s tris %7d  y %.2f→%.2f" % [
				mi.name, tris, b.position.y, b.position.y + b.size.y])
		print("  合計 tris %d  世界 AABB pos(%.1f, %.2f, %.1f) size(%.1f, %.2f, %.1f)" % [
			total_tris, box.position.x, box.position.y, box.position.z,
			box.size.x, box.size.y, box.size.z])

		if bc == null:
			continue
		for c in bc.get_children():
			if String(c.name).findn(t) == -1:
				continue
			var cs: CollisionShape3D = c.get_child(0)
			if cs == null or cs.shape == null:
				print("  hull %-40s 無形狀" % c.name)
				continue
			var hb: AABB = cs.global_transform * cs.shape.get_debug_mesh().get_aabb()
			var d := hb.get_center() - box.get_center()
			print("  碰撞 %-38s %s pos(%.1f, %.2f, %.1f) size(%.1f, %.2f, %.1f) 中心偏移 %.2f m" % [
				c.name, cs.shape.get_class(),
				hb.position.x, hb.position.y, hb.position.z,
				hb.size.x, hb.size.y, hb.size.z, d.length()])

	# ── bridge walkability ──
	var bn := map.get_node_or_null("龍石像橋")
	if bn != null:
		var bb := AABB()
		var f := true
		for mi in _meshes(bn):
			if mi.mesh == null:
				continue
			var b: AABB = mi.global_transform * mi.get_aabb()
			bb = b if f else bb.merge(b)
			f = false
		print("── 橋面行走測試 ──")
		# Sample along the BRIDGE'S OWN long axis, not the world AABB centreline:
		# 龍石像橋 is yawed ~17°, so a world-axis walk drifts off the deck at both
		# ends and reads the revetment as a 2.8 m step.
		var bx: Vector3 = (bn as Node3D).global_transform.basis.x.normalized()
		var bz: Vector3 = (bn as Node3D).global_transform.basis.z.normalized()
		var long_axis := bx if bb.size.x >= bb.size.z else bz
		var span: float = maxf(bb.size.x, bb.size.z)
		var centre := bb.get_center()
		var n_samples := 41
		var prev := Vector3.INF
		var worst_step := 0.0
		var worst_at := 0.0
		for i in n_samples:
			var tt := float(i) / float(n_samples - 1)
			var p: Vector3 = centre + long_axis * (span * (tt - 0.5))
			var from := Vector3(p.x, bb.position.y + bb.size.y + 5.0, p.z)
			var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -400, 0), mask)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				print("  t=%.3f (%.1f, %.1f)  無地面（會掉下去）" % [tt, p.x, p.z])
				prev = Vector3.INF
				continue
			var col: Node = hit["collider"]
			var here: Vector3 = hit["position"]
			var slope := ""
			if prev != Vector3.INF:
				var dy: float = here.y - prev.y
				var dxz := Vector2(here.x - prev.x, here.z - prev.z).length()
				var ang := rad_to_deg(atan2(absf(dy), maxf(dxz, 0.0001)))
				slope = "Δy %+6.2f  %4.1f°%s" % [dy, ang, "  ✗超過45°" if ang > 45.0 else ""]
				if absf(dy) > worst_step:
					worst_step = absf(dy)
					worst_at = tt
			print("  t=%.3f (%.1f, %.1f)  y=%7.2f  %-28s %s" % [
				tt, p.x, p.z, here.y, col.name, slope])
			prev = here
		print("  最大單步落差 %.2f m @ t=%.3f" % [worst_step, worst_at])

		# Deck width: where does the railing stop you? Sweep across the short
		# axis at the crown, from outside in on both sides.
		var short_axis := bz if bb.size.x >= bb.size.z else bx
		var short_span: float = minf(bb.size.x, bb.size.z)
		var crown := centre
		crown.y = bb.position.y + bb.size.y
		var cq := PhysicsRayQueryParameters3D.create(
			crown + Vector3(0, 5, 0), crown + Vector3(0, -400, 0), mask)
		var chit := space.intersect_ray(cq)
		var deck_y: float = crown.y if chit.is_empty() else float(chit["position"].y)
		var shape := CapsuleShape3D.new()
		shape.radius = RADIUS
		shape.height = HEIGHT
		for side in [1.0, -1.0]:
			var start: Vector3 = centre + short_axis * (short_span * 0.5 + 4.0) * side
			start.y = deck_y + HEIGHT * 0.5 + 0.1
			var goal: Vector3 = centre
			goal.y = start.y
			var sq := PhysicsShapeQueryParameters3D.new()
			sq.shape = shape
			sq.transform = Transform3D(Basis.IDENTITY, start)
			sq.motion = goal - start
			sq.collision_mask = mask
			var r := space.cast_motion(sq)
			var travelled: float = r[0] * sq.motion.length()
			print("  橋面橫向（%s側）從外緣走 %.1f m 到中線，走了 %.1f m（%.0f%%）%s" % [
				"＋" if side > 0.0 else "－", sq.motion.length(), travelled, r[0] * 100.0,
				"欄杆擋住 ✓" if r[0] < 0.999 else "沒有欄杆碰撞 ✗"])

		# Real-player truth: step a capsule along the deck the way move_and_slide
		# would, snapping down each step. Raycasts say what geometry is there;
		# only this says whether a body actually gets across.
		print("── 膠囊實走（步長 0.5 m，最大爬升 0.5 m）──")
		var step_len := 0.5
		var max_climb := 0.5
		var steps := int(span / step_len)
		var pos: Vector3 = centre - long_axis * (span * 0.5)
		pos.y = bb.position.y + bb.size.y + 5.0
		var gq := PhysicsRayQueryParameters3D.create(pos, pos + Vector3(0, -400, 0), mask)
		var gh := space.intersect_ray(gq)
		if gh.is_empty():
			print("  起點下方無地面")
		else:
			pos.y = gh["position"].y
			var blocked_at := -1.0
			var max_drop := 0.0
			for i in steps:
				var nxt: Vector3 = pos + long_axis * step_len
				# climb allowance: start the sweep at foot + max_climb
				var from_c := Vector3(pos.x, pos.y + max_climb + HEIGHT * 0.5, pos.z)
				var to_c := Vector3(nxt.x, from_c.y, nxt.z)
				var wq := PhysicsShapeQueryParameters3D.new()
				wq.shape = shape
				wq.transform = Transform3D(Basis.IDENTITY, from_c)
				wq.motion = to_c - from_c
				wq.collision_mask = mask
				var wr := space.cast_motion(wq)
				if wr[0] < 0.5:
					blocked_at = float(i) / float(steps)
					print("  ✗ 第 %d 步 (%.1f, %.1f) 被擋，只走了 %.0f%%" % [
						i, nxt.x, nxt.z, wr[0] * 100.0])
					break
				# snap down onto whatever is under the new spot
				var sq2 := PhysicsRayQueryParameters3D.create(
					Vector3(nxt.x, from_c.y, nxt.z),
					Vector3(nxt.x, from_c.y - 400.0, nxt.z), mask)
				var sh := space.intersect_ray(sq2)
				if sh.is_empty():
					print("  ✗ 第 %d 步 (%.1f, %.1f) 腳下沒東西" % [i, nxt.x, nxt.z])
					blocked_at = float(i) / float(steps)
					break
				var new_y: float = sh["position"].y
				var drop: float = pos.y - new_y
				if drop > max_drop:
					max_drop = drop
				pos = Vector3(nxt.x, new_y, nxt.z)
			if blocked_at < 0.0:
				print("  ✓ 全程走完 %.1f m，終點 y=%.2f，最大單步落差 %.2f m" % [
					span, pos.y, max_drop])

	print("done")
	quit(0)


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _tris(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var idx = arr[Mesh.ARRAY_INDEX]
		t += (idx.size() / 3) if idx != null and idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX].size() / 3)
	return t
