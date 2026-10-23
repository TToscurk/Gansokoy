extends SceneTree
## 釘死 Skeleton3D 的語意：rest / pose / global / 世界 四者關係。
##   <godot_console.exe> --path godot --headless --script res://tools/_probe_skel_semantics.gd
const BODY := "res://characters/yoriichi/yoriichi_body.fbx"


func _init() -> void:
	_run.call_deferred()


func _f(t: Transform3D) -> String:
	return "o=%s e=%s" % [str(t.origin.snappedf(0.001)), str(t.basis.get_euler().snappedf(0.01))]


func _run() -> void:
	var body := (load(BODY) as PackedScene).instantiate()
	root.add_child(body)
	await process_frame
	await process_frame
	var sk := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var h := sk.find_bone("Hips")
	var s := sk.find_bone("Spine02")
	print("[語意] 骨架 global=%s" % _f(sk.global_transform))
	print("[語意] ── 預設（沒有任何動畫）")
	print("   Hips rest=%s" % _f(sk.get_bone_rest(h)))
	print("   Hips pose=%s" % _f(sk.get_bone_pose(h)))
	print("   Hips global=%s" % _f(sk.get_bone_global_pose(h)))
	print("   Hips global × 骨架 = %s" % _f(sk.global_transform * sk.get_bone_global_pose(h)))
	print("   Spine02 pose=%s global=%s" % [_f(sk.get_bone_pose(s)), _f(sk.get_bone_global_pose(s))])

	print("[語意] ── 手動把 Hips 的 pose 位置設成 A=(0.03,-0.03,0.34)")
	sk.set_bone_pose_position(h, Vector3(0.03, -0.03, 0.34))
	await process_frame
	print("   pose=%s" % _f(sk.get_bone_pose(h)))
	print("   global=%s" % _f(sk.get_bone_global_pose(h)))

	print("[語意] ── 改用 set_bone_global_pose(Hips, B=(0.03,-0.03,0.34))")
	var g := sk.get_bone_global_pose(h)
	sk.set_bone_global_pose(h, Transform3D(g.basis, Vector3(0.03, -0.03, 0.34)))
	await process_frame
	print("   pose=%s" % _f(sk.get_bone_pose(h)))
	print("   global=%s" % _f(sk.get_bone_global_pose(h)))
	print("   global × 骨架 = %s（世界）" % _f(sk.global_transform * sk.get_bone_global_pose(h)))
	print("[語意] 結論判讀：global 是否等於 pose？rest 有沒有被乘進去？")
	body.free()
	quit(0)
