extends SceneTree
## R3c W3 Drink — dump skinned vertices around the left hand, in LeftHand-bone space, for every
## 30 fps frame of one clip (read-only; never saves scenes/resources). Feeds the cup-grip fit
## (tools/fit_p10_drink_cup.py), which searches the tea-cup offset inside the hand.
## Output JSON: {mouth_in_head, frames:[{t, mouth_h:[x,y,z] (hand space), pts:[[x,y,z,region],...]}]}
## Usage: godot --headless --path godot --script res://tools/probe_p10_drink_dump.gd -- <clip> <out.json>
const R := preload("res://tools/probe_p10_drink_ab2.gd")
var sk: Skeleton3D

func _initialize():
	run.call_deferred()

func gpose(nm: String) -> Transform3D:
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(nm))

func run():
	var args := OS.get_cmdline_user_args()
	var clip := args[0]
	var probe = R.new()   # reuse skinning / region code (SceneTree subclass, never added to a tree)
	var n: Node3D = load("res://characters/npc/chaya_f01/chaya_f01.tscn").instantiate()
	root.add_child(n)
	await process_frame
	sk = n.find_child("GeneralSkeleton", true, false)
	probe.sk = sk
	probe.prepare()
	# mouth point in head-rest space (same estimate as probe_p10_drink_ab2.gd)
	var head_i := sk.find_bone("Head")
	var hri := (sk.global_transform * sk.get_bone_global_rest(head_i)).affine_inverse()
	var fwd := (hri.basis * n.global_basis.z).normalized()
	var up := (hri.basis * Vector3.UP).normalized()
	var face := PackedVector3Array()
	for md in probe.meshes:
		if md.mi.name != "NPC_Body": continue
		for i in md.verts.size():
			if md.region[i] == 0: face.append(hri * (md.mi.global_transform * md.verts[i]))
	var mf := -1e9
	for p in face: mf = maxf(mf, p.dot(fwd))
	var y0 := 1e9; var y1 := -1e9
	for p in face:
		if p.dot(fwd) > mf - 0.025: y0 = minf(y0, p.dot(up)); y1 = maxf(y1, p.dot(up))
	var mh := y0 + 0.22 * (y1 - y0)
	var mouth := Vector3.ZERO; var best := 1e9
	for p in face:
		var d := absf(p.dot(up) - mh) + absf(p.dot(fwd) - mf) * 0.5
		if d < best: best = d; mouth = p
	var ap: AnimationPlayer = n.player
	var an: Animation = load("res://animations/npc_activity_p10/chaya_f01/%s_grounded.res" % clip)
	var lib := AnimationLibrary.new(); lib.add_animation(&"c", an)
	ap.add_animation_library(&"ab", lib)
	ap.play(&"ab/c"); ap.speed_scale = 0.0
	var out := {"clip": clip, "mouth_in_head": [mouth.x, mouth.y, mouth.z], "face_h": [y0, y1], "frames": []}
	for f in int(an.length * 30.0):
		ap.seek(f / 30.0, true)
		var hand := gpose("LeftHand")
		var hinv := hand.affine_inverse()
		var palm := gpose("LeftMiddleProximal").origin
		var m := hinv * (gpose("Head") * mouth)
		var pts := []
		for md in probe.meshes:
			var sp: PackedVector3Array = probe.skinned(md)
			for i in sp.size():
				if sp[i].distance_squared_to(palm) > 0.25 * 0.25: continue
				var lp := hinv * sp[i]
				pts.append([snappedf(lp.x, 0.0001), snappedf(lp.y, 0.0001), snappedf(lp.z, 0.0001), int(md.region[i])])
		var uh := (hinv.basis * Vector3.UP).normalized()
		var fh := (hinv.basis * n.global_basis.z).normalized()
		out.frames.append({"t": f / 30.0, "mouth_h": [m.x, m.y, m.z], "up_h": [uh.x, uh.y, uh.z], "fwd_h": [fh.x, fh.y, fh.z], "palm_h": [(hinv * palm).x, (hinv * palm).y, (hinv * palm).z], "pts": pts})
	var fo := FileAccess.open(args[1], FileAccess.WRITE)
	fo.store_string(JSON.stringify(out))
	print("[DRINKDUMP] ", clip, " frames ", out.frames.size())
	quit(0)
