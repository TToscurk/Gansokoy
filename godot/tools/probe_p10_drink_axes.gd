extends SceneTree
## R3c W3 Drink — print LeftHand axes and hand→mouth direction in the body frame at chosen times
## (read-only diagnostic for the cup orientation). Usage: ... -- <clip> <t1> <t2> ...
func _initialize():
	run.call_deferred()
func run():
	var a := OS.get_cmdline_user_args()
	var n: Node3D = load("res://characters/npc/chaya_f01/chaya_f01.tscn").instantiate()
	root.add_child(n)
	await process_frame
	var sk: Skeleton3D = n.find_child("GeneralSkeleton", true, false)
	var ap: AnimationPlayer = n.player
	var lib := AnimationLibrary.new(); lib.add_animation(&"c", load("res://animations/npc_activity_p10/chaya_f01/%s_grounded.res" % a[0]))
	ap.add_animation_library(&"o", lib); ap.play(&"o/c"); ap.speed_scale = 0.0
	var g := func(nm): return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(nm))
	for s in a.slice(1):
		ap.seek(float(s), true)
		var fwd := n.global_basis.z; var up := Vector3.UP; var left := n.global_basis.x
		var h: Transform3D = g.call("LeftHand")
		var head: Transform3D = g.call("Head")
		var f := func(v: Vector3): return "(fwd %+.2f up %+.2f left %+.2f)" % [v.dot(fwd), v.dot(up), v.dot(left)]
		var thumb: Vector3 = (g.call("LeftThumbProximal").origin - h.origin).normalized()
		var pinky: Vector3 = (g.call("LeftLittleProximal").origin - h.origin).normalized()
		var mouth := head.origin + head.basis * Vector3(0, 0.03, 0.10)
		print("t=%s hand.x %s hand.y %s hand.z %s thumb %s pinky %s hand->mouth %s head.z %s" % [s, f.call(h.basis.x), f.call(h.basis.y), f.call(h.basis.z), f.call(thumb), f.call(pinky), f.call((mouth - h.origin).normalized()), f.call(head.basis.z)])
	quit(0)
