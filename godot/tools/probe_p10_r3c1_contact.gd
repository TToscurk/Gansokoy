extends SceneTree
## R3c.1 prop contact probe (read-only): CPU-skinned body vertices vs the Carry crate and the Sit bench,
## on the bare NPC, every 30 fps frame, using the same placement rules as npc_activity_overlay.gd.
##  Carry: vertices inside the crate box (hands / forearm-sleeve / torso-legs), crate float gap to each palm.
##  Sit:   vertices below the bench top inside its footprint (= through the seat), hip→seat gap (floating).
## Usage: godot --headless --path godot --script res://tools/probe_p10_r3c1_contact.gd -- <out.json>
const R := preload("res://tools/probe_p10_drink_ab2.gd")
const OV := preload("res://scripts/npc_activity_overlay.gd")
var sk: Skeleton3D

func _initialize():
	run.call_deferred()

func gp(nm: String) -> Transform3D:
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(nm))

func setup(cid: String, clip: Animation) -> Array:
	var n: Node3D = load("res://characters/npc/%s/%s.tscn" % [cid, cid]).instantiate()
	root.add_child(n)
	await process_frame
	sk = n.find_child("GeneralSkeleton", true, false)
	var probe = R.new(); probe.sk = sk; probe.prepare()
	var ap: AnimationPlayer = n.player
	var lib := AnimationLibrary.new(); lib.add_animation(&"c", clip)
	ap.add_animation_library(&"r", lib); ap.play(&"r/c"); ap.speed_scale = 0.0
	return [n, probe, ap]

func region(bn: String) -> String:
	if bn.contains("Hand") or bn.contains("Thumb") or bn.contains("Index") or bn.contains("Middle") or bn.contains("Ring") or bn.contains("Little"): return "hands"
	if bn.contains("LowerArm") or bn.contains("UpperArm") or bn.contains("Shoulder"): return "arms_sleeves"
	if bn.contains("Leg") or bn.contains("Foot") or bn.contains("Toes"): return "legs_feet"
	return "torso_head"

func run():
	var out := {}
	var A: Dictionary = OV.ASSIGN
	# ---- Carry
	for path in A:
		var a: Array = A[path]
		if a[0] != "Carry": continue
		var opt: Dictionary = (a[4] as Dictionary).duplicate()
		var clip: Animation = load(OV.ROOT_ANIM + a[1] + "/" + a[2] + "_grounded.res")   # contact is pose-only; retiming does not change it
		var s: Array = await setup(a[1], clip)
		var mesh: Mesh = load(opt.crate[0])
		var bounds := mesh.get_aabb()
		var res := {"frames": 0, "inside_frames": {}, "inside_max_m": {}, "palm_gap_max_m": 0.0, "crate_width_m": [1e9, 0.0],
			"body_front_z_max_m": -1e9, "body_z_min_m": 1e9, "head_z": 0.0, "hands_z_range_m": [1e9, -1e9]}
		var zoff := float(opt.get("crate_forward", 0.0)); var yoff := float(opt.get("crate_up", 0.0))
		for ua in OS.get_cmdline_user_args():
			if ua.begins_with("--cf="): zoff = float(ua.trim_prefix("--cf="))
			if ua.begins_with("--cu="): yoff = float(ua.trim_prefix("--cu="))
			if ua.begins_with("--ci="): opt["crate_inset"] = float(ua.trim_prefix("--ci="))
		res["crate_forward"] = zoff; res["crate_up"] = yoff
		var deep := {}
		for f in int(clip.length * 30.0):
			s[2].seek(f / 30.0, true)
			var left := gp("LeftMiddleProximal").origin; var right := gp("RightMiddleProximal").origin
			var x := (left - right).normalized(); var front: Vector3 = s[0].global_basis.z
			var z := (front - x * front.dot(x)).normalized(); var y := z.cross(x).normalized()
			var size := Vector3(left.distance_to(right) - float(opt.get("crate_inset", 0.0)), float(opt.crate[2]), float(opt.crate[1]))
			res.crate_width_m = [minf(res.crate_width_m[0], size.x), maxf(res.crate_width_m[1], size.x)]
			var cxf := Transform3D(Basis(x, y, z), (left + right) * 0.5 + z * zoff + y * yoff)   # overlay rule (+ crate_forward / crate_up)
			var inv := cxf.affine_inverse()
			var half := size * 0.5
			var hit := {}
			var hgapL := 1e9; var hgapR := 1e9
			for md in s[1].meshes:
				var sp: PackedVector3Array = s[1].skinned(md)
				for i in sp.size():
					var q := inv * sp[i]
					var bh: String = sk.get_bone_name(md.binds[md.bones[i * md.stride]])
					if region(bh) == "hands":
						var dv := Vector3(maxf(absf(q.x) - half.x, 0), maxf(absf(q.y) - half.y, 0), maxf(absf(q.z) - half.z, 0)).length()
						if bh.begins_with("Left"): hgapL = minf(hgapL, dv)
						else: hgapR = minf(hgapR, dv)
					var bi0: int = md.bones[i * md.stride]
					var rg0 := region(sk.get_bone_name(md.binds[bi0]))
					var qc := q + Vector3(0, 0, zoff)   # palm-midpoint frame (no forward offset)
					if rg0 in ["torso_head", "legs_feet"] and absf(qc.x) < half.x - 0.04 and absf(q.y) < half.y:
						res.body_front_z_max_m = maxf(res.body_front_z_max_m, qc.z)
						res.body_z_min_m = minf(res.body_z_min_m, qc.z)
					if rg0 == "hands": res.hands_z_range_m = [minf(res.hands_z_range_m[0], qc.z), maxf(res.hands_z_range_m[1], qc.z)]
					var d := minf(minf(half.x - absf(q.x), half.y - absf(q.y)), half.z - absf(q.z))
					if d <= 0.004: continue   # ≤ 4 mm: skin pressing the crate wall
					var bi: int = md.bones[i * md.stride]
					var rg := region(sk.get_bone_name(md.binds[bi]))
					if d > float(hit.get(rg, 0.0)): deep[rg] = [snappedf(q.x, 0.01), snappedf(q.y, 0.01), snappedf(q.z, 0.01), sk.get_bone_name(md.binds[bi]), md.mi.name]
					hit[rg] = maxf(float(hit.get(rg, 0.0)), d)
			for rg in hit:
				res.inside_frames[rg] = int(res.inside_frames.get(rg, 0)) + 1
				res.inside_max_m[rg] = maxf(float(res.inside_max_m.get(rg, 0.0)), hit[rg])
			res.palm_gap_max_m = maxf(res.palm_gap_max_m, maxf(hgapL, hgapR))   # worst hand-to-crate gap (0 = touching)
			res.frames += 1
			res.head_z = (inv * gp("Head").origin + Vector3(0, 0, zoff)).z
			res["toes_z"] = (inv * gp("LeftToes").origin + Vector3(0, 0, zoff)).z
			res["deepest_last_frame_crate_local"] = deep.duplicate()
		out[path] = res
		print("[R31CONTACT] ", path, " ", JSON.stringify(res))
		s[0].queue_free(); await process_frame
	if "--sit-only" in OS.get_cmdline_user_args(): pass
	if "--carry-only" in OS.get_cmdline_user_args():
		print("[R31CONTACT] carry-only"); quit(0); return
	# ---- Sit
	for path in A:
		var a: Array = A[path]
		if a[0] != "Sit": continue
		var opt: Dictionary = a[4] if a.size() > 4 else {}
		var clip: Animation = load(OV.ROOT_ANIM + a[1] + "/" + a[2] + "_grounded.res")
		var s: Array = await setup(a[1], clip)
		var bench: Mesh = load(String(opt.get("seat", "res://assets/village_v2/suzu_kit/mesh/sz_stool.res")))
		var bb := bench.get_aabb()
		s[2].seek(0.0, true)
		var seat: Vector3 = gp("Hips").origin - s[0].global_basis.z * 0.05 - Vector3(0, 0.11, 0)   # overlay rule (first frame)
		var foot := Vector2(float(opt.get("seat_len", bb.size.x)), float(opt.get("seat_depth", bb.size.z))) if opt.has("seat") else Vector2(0.46, 0.36)
		var drop := float(opt.get("seat_drop", 0.11)); var back := float(opt.get("seat_back", 0.05))
		for ua in OS.get_cmdline_user_args():
			if ua.begins_with("--sd="): drop = float(ua.trim_prefix("--sd="))
			if ua.begins_with("--sb="): back = float(ua.trim_prefix("--sb="))
		seat = gp("Hips").origin - s[0].global_basis.z * back - Vector3(0, drop, 0)
		var res := {"frames": 0, "seat_drop_m": drop, "seat_height_m": seat.y, "through_seat_frames": {}, "through_seat_max_m": {}, "hip_gap_max_m": -1.0, "hip_gap_min_m": 1.0}
		for f in range(0, int(clip.length * 30.0), 3):
			s[2].seek(f / 30.0, true)
			var hit := {}
			var low := 1e9
			for md in s[1].meshes:
				var sp: PackedVector3Array = s[1].skinned(md)
				for i in sp.size():
					var lp: Vector3 = sp[i] - Vector3(seat.x, 0, seat.z) - s[0].global_basis.x * float(opt.get("seat_shift", 0.0))
					if absf(lp.x) > foot.x * 0.5 or absf(lp.z) > foot.y * 0.5: continue
					var bi: int = md.bones[i * md.stride]
					var bn := sk.get_bone_name(md.binds[bi])
					if bn in ["Hips", "LeftUpperLeg", "RightUpperLeg"]: low = minf(low, sp[i].y - seat.y)
					var depth := seat.y - sp[i].y
					if depth > 0.01 and sp[i].y > 0.02:   # inside the seat slab / under it but above the floor
						var rg := region(bn)
						hit[rg] = maxf(float(hit.get(rg, 0.0)), minf(depth, 0.04) if depth < 0.04 else depth)
			for rg in hit:
				res.through_seat_frames[rg] = int(res.through_seat_frames.get(rg, 0)) + 1
				res.through_seat_max_m[rg] = maxf(float(res.through_seat_max_m.get(rg, 0.0)), hit[rg])
			res.hip_gap_max_m = maxf(res.hip_gap_max_m, low); res.hip_gap_min_m = minf(res.hip_gap_min_m, low)
			res.frames += 1
		out[path] = res
		print("[R31CONTACT] ", path, " ", JSON.stringify(res))
	FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE).store_string(JSON.stringify(out, "  "))
	quit(0)
