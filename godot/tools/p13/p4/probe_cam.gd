extends SceneTree
## 診断（唯読）：カメラ位置（world）を含む／近くにある MeshInstance3D を列挙する（どの屋根・庇の中／下にカメラがいるか）。
##   godot --headless --path godot --script res://tools/p13/p4/probe_cam.gd -- x,y,z [--r=0.4]
func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var c := Vector3.ZERO
	var r := 0.4
	for a: String in args:
		if a.begins_with("--r="):
			r = float(a.trim_prefix("--r="))
		elif "," in a:
			var q := a.split(",")
			c = Vector3(float(q[0]), float(q[1]), float(q[2]))
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 6:
		await process_frame   # arch_w9r2.gd は process_frame 2 回後に Kit を隠す
	var hit := 0
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		if g.mesh == null or not g.is_visible_in_tree():
			continue
		if g.visibility_range_begin > 0.5:
			continue   # LOD1 以降（近景では LOD0 だけ）
		if g.visibility_range_end > 0.0 and g.visibility_range_end < 5.0:
			continue
		var ab: AABB = g.global_transform * g.mesh.get_aabb()
		if not ab.grow(r).has_point(c):
			continue
		hit += 1
		var pth := String(g.get_path()).replace("/root/VillageV2/", "")
		print("[CAM] %-78s x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f]%s" % [pth.substr(maxi(0, pth.length() - 78)), ab.position.x, ab.end.x, ab.position.y, ab.end.y, ab.position.z, ab.end.z, "  ←内側" if ab.has_point(c) else ""])
	print("[CAM] camera=%s r=%.2f → %d meshes" % [c, r, hit])
	quit(0)
