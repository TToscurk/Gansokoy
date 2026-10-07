extends SceneTree
## R3c W3 Drink A/B — skinned contact + pose probe (read-only; never saves scenes/resources).
## Per candidate clip on chaya_f01 (30 fps):
##  * skins every body/cloth/hair vertex on the CPU (Skin bind poses × skeleton pose) and counts
##    vertices that lie INSIDE the tea-cup volume, grouped by dominant bone region
##    (face/head, left hand = grip, left arm/sleeve, torso, other) → real cup-through-mesh test;
##  * same for the left-hand vertices vs the head/face surface (hand-through-face);
##  * pose at the sip peak: rim→mouth, rim height on face (0 chin … 1 brow), upper-arm abduction,
##    elbow height vs shoulder, elbow lateral flare, shoulder lift vs neck, head pitch back.
## Usage: godot --headless --path godot --script res://tools/probe_p10_drink_ab2.gd -- <out.json> [clip=key ...]
const CLIPS := {"A_drinking_a030": "drinking_a030", "B1_drinking_im1_a030": "drinking_im1_a030", "B2_watercooler_a030": "watercooler_a030"}
var sk: Skeleton3D
var meshes: Array = []   # [{mi, verts, bones, weights, stride, binds:[bone_idx], bind_poses, region:PackedByteArray}]
const REG := ["face_head", "hand_L", "arm_sleeve_L", "torso", "other"]

func _initialize():
	run.call_deferred()

func bone(nm: String) -> Transform3D:
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(nm))

const OV := preload("res://scripts/npc_activity_overlay.gd")
var grip := Vector3(0.020, 0.0, 0.022)   # cup foot offset from LeftMiddleProximal in LeftHand axes; --grip=x,y,z
var axis := Vector3(-1, 0, 0)            # cup up-axis in LeftHand axes; --axis=x,y,z (old fixed grip = −hand.x)
func cup_xf() -> Transform3D:
	# Same formula as npc_activity_overlay.gd (W3 holds the cup in the left hand).
	var hand := bone("LeftHand")
	var palm := bone("LeftMiddleProximal").origin
	return Transform3D(hand.basis * OV.cup_basis(axis), palm + hand.basis * grip)

func region_of(bn: String) -> int:
	if bn in ["Head", "Neck", "Jaw", "LeftEye", "RightEye"]: return 0
	if bn.begins_with("Left") and (bn == "LeftHand" or bn.contains("Thumb") or bn.contains("Index") or bn.contains("Middle") or bn.contains("Ring") or bn.contains("Little")): return 1
	if bn in ["LeftShoulder", "LeftUpperArm", "LeftLowerArm"]: return 2
	if bn in ["Hips", "Spine", "Chest", "UpperChest"]: return 3
	return 4

func prepare():
	for mi in sk.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.skin == null: continue
		var a := m.mesh.surface_get_arrays(0)
		for s in range(1, m.mesh.get_surface_count()):
			push_warning("multi-surface mesh %s: only surface 0 probed" % m.name)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bo = a[Mesh.ARRAY_BONES]
		var we = a[Mesh.ARRAY_WEIGHTS]
		var stride: int = bo.size() / v.size()
		var binds: Array = []
		var poses: Array = []
		for i in m.skin.get_bind_count():
			var bi := m.skin.get_bind_bone(i)
			if bi < 0: bi = sk.find_bone(m.skin.get_bind_name(i))
			binds.append(bi)
			poses.append(m.skin.get_bind_pose(i))
		var reg := PackedByteArray(); reg.resize(v.size())
		for i in v.size():
			var best := -1.0; var bb := 0
			for k in stride:
				if we[i * stride + k] > best: best = we[i * stride + k]; bb = int(bo[i * stride + k])
			reg[i] = region_of(sk.get_bone_name(binds[bb]))
		meshes.append({"mi": m, "verts": v, "bones": bo, "weights": we, "stride": stride, "binds": binds, "poses": poses, "region": reg})

func skinned(md: Dictionary) -> PackedVector3Array:
	var xf: Array = []
	for i in md.binds.size():
		xf.append(sk.global_transform * sk.get_bone_global_pose(md.binds[i]) * md.poses[i])
	var v: PackedVector3Array = md.verts
	var out := PackedVector3Array(); out.resize(v.size())
	var st: int = md.stride
	for i in v.size():
		var p := Vector3.ZERO
		for k in st:
			var w: float = md.weights[i * st + k]
			if w > 0.0: p += w * (xf[int(md.bones[i * st + k])] * v[i])
		out[i] = p
	return out

func cup_r(y: float) -> float:
	return lerpf(0.027, 0.036, clampf(y / 0.072, 0.0, 1.0))

func run():
	var args := OS.get_cmdline_user_args()
	var out_path := args[0]
	var only := []
	for s in args.slice(1):
		if s.begins_with("--grip="):
			var g := s.trim_prefix("--grip=").split(",")
			grip = Vector3(float(g[0]), float(g[1]), float(g[2]))
		elif s.begins_with("--axis="):
			var g := s.trim_prefix("--axis=").split(",")
			axis = Vector3(float(g[0]), float(g[1]), float(g[2]))
		else: only.append(s)
	var n: Node3D = load("res://characters/npc/chaya_f01/chaya_f01.tscn").instantiate()
	root.add_child(n)
	await process_frame
	sk = n.find_child("GeneralSkeleton", true, false)
	prepare()
	# Rest-pose sanity: CPU skinning must reproduce mesh positions at rest (else every number is wrong).
	sk.reset_bone_poses()
	var rest_err := 0.0
	for md in meshes:
		var sp := skinned(md)
		for i in range(0, sp.size(), 97):
			rest_err = maxf(rest_err, sp[i].distance_to(md.mi.global_transform * md.verts[i]))
	print("[DRINKAB2] rest skinning max error %.5f m over %d meshes" % [rest_err, meshes.size()])
	# Face reference (rest): mouth point, chin/brow heights in head-local.
	var head_i := sk.find_bone("Head")
	var head_rest_inv := (sk.global_transform * sk.get_bone_global_rest(head_i)).affine_inverse()
	var fwd := (head_rest_inv.basis * n.global_basis.z).normalized()
	var up := (head_rest_inv.basis * Vector3.UP).normalized()
	var face := PackedVector3Array()
	for md in meshes:
		if md.mi.name != "NPC_Body": continue
		for i in md.verts.size():
			if md.region[i] == 0: face.append(head_rest_inv * (md.mi.global_transform * md.verts[i]))
	var maxf_ := -1e9
	for p in face: maxf_ = maxf(maxf_, p.dot(fwd))
	var ymin := 1e9; var ymax := -1e9
	for p in face:
		if p.dot(fwd) > maxf_ - 0.025: ymin = minf(ymin, p.dot(up)); ymax = maxf(ymax, p.dot(up))
	var mouth_h := ymin + 0.22 * (ymax - ymin)
	var mouth := Vector3.ZERO; var best := 1e9
	for p in face:
		var d := absf(p.dot(up) - mouth_h) + absf(p.dot(fwd) - maxf_) * 0.5
		if d < best: best = d; mouth = p
	var ap: AnimationPlayer = n.player
	var hb := bone("LeftHand").basis
	print("[DRINKAB2] grip ", grip, " axis ", axis, " hand basis scale ", hb.get_scale())
	var report := {"grip": [grip.x, grip.y, grip.z], "axis": [axis.x, axis.y, axis.z], "rest_skin_error_m": rest_err, "mouth_head_local": str(mouth), "regions": REG, "candidates": {}}
	for key in CLIPS:
		if not only.is_empty() and not key in only: continue
		var an: Animation = load("res://animations/npc_activity_p10/chaya_f01/%s_grounded.res" % CLIPS[key])
		var lib := AnimationLibrary.new(); lib.add_animation(&"c", an)
		if ap.has_animation_library(&"ab"): ap.remove_animation_library(&"ab")
		ap.add_animation_library(&"ab", lib)
		ap.play(&"ab/c"); ap.speed_scale = 0.0
		ap.seek(0.0, true)
		var head0 := bone("Head").basis
		var frames := int(an.length * 30.0)
		var inside := [0, 0, 0, 0, 0]; var inside_frames := [0, 0, 0, 0, 0]; var depth := [0.0, 0.0, 0.0, 0.0, 0.0]
		var hand_face_frames := 0; var hand_face_depth := 0.0
		var sips := []   # local minima of rim→mouth under 6 cm
		var dists := []
		var peak := {"d": 1e9}
		var tilt_hold := 0.0; var tilt_max := 0.0; var tilt_max_t := 0.0
		var lip_min := 1e9; var lip_min_t := 0.0
		var trace := []   # per frame near the face: t, cup tilt, rim→mouth, highest cup point on the face (0 chin … 1 brow), lateral offset from the face centre line
		var worst := {"abd": -1e9}
		for f in frames:
			var t := f / 30.0
			ap.seek(t, true)
			var head := bone("Head")
			var cx := cup_xf()
			var rim := head.affine_inverse() * (cx * Vector3(0, 0.072, 0))
			var d := rim.distance_to(mouth)
			dists.append(d)
			var fh := (rim.dot(up) - ymin) / (ymax - ymin)
			var tilt := rad_to_deg(cx.basis.y.normalized().angle_to(Vector3.UP))
			var mq := cx.affine_inverse() * (head * mouth)   # mouth in cup space → distance to the rim lip circle
			var lip := Vector2(Vector2(mq.x, mq.z).length() - 0.0325, mq.y - 0.072).length()
			if lip < lip_min: lip_min = lip; lip_min_t = t
			if d < 0.15:
				var top := -1e9; var lat := 1e9
				var hinv := head.affine_inverse()
				var side := (hinv.basis * Vector3(0, 0, 0)).normalized()
				for j in 2:
					for i in 12:
						var cp := Vector3(sin(TAU * i / 12.0) * [0.027, 0.036][j], [0.0, 0.072][j], cos(TAU * i / 12.0) * [0.027, 0.036][j])
						var hp := hinv * (cx * cp)
						if hp.dot(up) > top: top = hp.dot(up)
						lat = minf(lat, absf(hp.x - mouth.x))
				trace.append([snappedf(t, 0.01), snappedf(tilt, 0.1), snappedf(d, 0.001), snappedf((top - ymin) / (ymax - ymin), 0.01), snappedf(lat, 0.001)])
			if tilt > tilt_max: tilt_max = tilt; tilt_max_t = t
			if d > 0.30: tilt_hold = maxf(tilt_hold, tilt)
			# Pose (body frame from Hips; left = +x of character? use shoulder→shoulder axis).
			var ls := bone("LeftUpperArm").origin; var rs := bone("RightUpperArm").origin
			var le := bone("LeftLowerArm").origin
			var neck := bone("Neck").origin
			var lateral := (ls - rs).normalized()
			var down := -bone("Hips").basis.y.normalized()
			var ua := (le - ls)
			var abd := rad_to_deg(acos(clampf(ua.normalized().dot(down), -1, 1)))
			var pose := {"t": t, "rim_mouth_m": d, "rim_face_h": fh, "cup_tilt_deg": tilt, "upperarm_from_down_deg": abd,
				"elbow_below_shoulder_m": (ls - le).dot(-down), "elbow_lateral_flare_m": ua.dot(lateral),
				"shoulder_above_neck_m": (ls - neck).dot(-down), "head_pitch_back_deg": rad_to_deg(head0.y.angle_to(head.basis.y))}
			if d < peak.d: peak = pose.duplicate(); peak["d"] = d
			if abd > worst.abd: worst = pose.duplicate(); worst["abd"] = abd
			# Contact tests only where something can touch (cup within 25 cm of mouth, or every 6th frame).
			if d > 0.25 and f % 6 != 0: continue
			var cinv := cx.affine_inverse()
			var hit := [0, 0, 0, 0, 0]
			var head_pts := PackedVector3Array(); var hand_pts := PackedVector3Array()
			for md in meshes:
				var sp := skinned(md)
				for i in sp.size():
					var r: int = md.region[i]
					if r == 0 and md.mi.name == "NPC_Body": head_pts.append(sp[i])
					if r == 1: hand_pts.append(sp[i])
					var lp := cinv * sp[i]
					if lp.y < 0.004 or lp.y > 0.068: continue
					var rr := Vector2(lp.x, lp.z).length()
					var dep := cup_r(lp.y) - 0.003 - rr
					if dep > 0.0:
						hit[r] += 1
						depth[r] = maxf(depth[r], dep)
			for r in 5:
				inside[r] += hit[r]
				if hit[r] > 0: inside_frames[r] += 1
			# Hand vs face: hand vertex closer than 6 mm to a face vertex AND behind it along head-forward.
			if d < 0.15:
				var hf := 0.0
				var hfwd := (head.basis * (sk.get_bone_global_rest(head_i).basis.inverse() * (sk.global_transform.basis.inverse() * n.global_basis.z))).normalized()
				for hp in hand_pts:
					var bd := 1e9; var bp := Vector3.ZERO
					for fp in head_pts:
						var dd := hp.distance_squared_to(fp)
						if dd < bd: bd = dd; bp = fp
					if sqrt(bd) < 0.012:
						var dep2 := -(hp - bp).dot(hfwd)
						if dep2 > 0.004: hf = maxf(hf, dep2)
				if hf > 0.0: hand_face_frames += 1; hand_face_depth = maxf(hand_face_depth, hf)
		for i in range(1, dists.size() - 1):
			if dists[i] < 0.06 and dists[i] <= dists[i - 1] and dists[i] < dists[i + 1]:
				if sips.is_empty() or i / 30.0 - float(sips[-1]) > 1.0: sips.append(i / 30.0)
		var cand := {"clip": CLIPS[key], "length_s": an.length, "frames30": frames, "sip_times_s": sips,
			"near_face_trace": trace, "rim_lip_min_m": lip_min, "rim_lip_min_t": lip_min_t, "cup_tilt_hold_max_deg": tilt_hold, "cup_tilt_max_deg": tilt_max, "cup_tilt_max_t": tilt_max_t,
			"peak_sip": peak, "max_abduction_pose": worst,
			"cup_inside_vertex_hits": {}, "cup_inside_frames": {}, "cup_inside_max_depth_m": {},
			"hand_through_face_frames": hand_face_frames, "hand_through_face_max_m": hand_face_depth}
		for r in 5:
			cand.cup_inside_vertex_hits[REG[r]] = inside[r]
			cand.cup_inside_frames[REG[r]] = inside_frames[r]
			cand.cup_inside_max_depth_m[REG[r]] = depth[r]
		report.candidates[key] = cand
		print("[DRINKAB2] ", key, " ", JSON.stringify(cand))
	var fo := FileAccess.open(out_path, FileAccess.WRITE)
	fo.store_string(JSON.stringify(report, "  "))
	quit(0)
