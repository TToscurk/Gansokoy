extends SceneTree
## 村裡驗證小鈴：位置／腳底與路面距離／袖子 NaN 與拉伸／物理耗時；玩家視角兩張圖。
## godot --path godot -s res://tools/kosuzu/verify_kosuzu_village.gd -- [--out=<dir>]
var scene: Node3D
var t := 0.0
var out := "D:/神社/proto/kosuzu_sleeve/verify_village"
var vp: SubViewport
var done_shot := false
var ms := []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	scene = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	get_root().add_child(scene)

func _physics_process(dt: float) -> bool:
	t += dt
	if vp == null and t > 0.2: _cams()
	if t > 3.0: ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	if t >= 8.0:
		_report(); return true
	return false

func _cams() -> void:
	var actor := scene.get_node("Population/KosuzuNPC/K1_kosuzu") as Node3D
	var p := actor.global_position; var f := actor.global_transform.basis.z
	var cam := Camera3D.new(); scene.add_child(cam); cam.fov = 50
	cam.look_at_from_position(p + f * 4.0 + Vector3(0, 1.6, 0) + actor.global_transform.basis.x * 1.2, p + Vector3(0, 1.0, 0)); cam.current = true
	vp = SubViewport.new(); vp.size = Vector2i(1280, 720); vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; scene.add_child(vp)
	var c2 := Camera3D.new(); vp.add_child(c2); c2.fov = 50
	c2.look_at_from_position(p + f * 1.6 - actor.global_transform.basis.x * 1.4 + Vector3(0, 1.4, 0), p + Vector3(0, 0.9, 0)); c2.current = true

func _process(_d: float) -> bool:
	if not done_shot and t >= 7.5:
		done_shot = true; _shot()
	return false

func _shot() -> void:
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out + "/village_front.png")
	vp.get_texture().get_image().save_png(out + "/village_close.png")

func _report() -> void:
	var actor := scene.get_node("Population/KosuzuNPC/K1_kosuzu") as Node3D
	var npc := actor.get_node("NPC")
	var sk: Skeleton3D = npc.get_node("Model").find_children("*", "Skeleton3D", true, false)[0]
	var fb := func(n): return sk.find_bone(n) if sk.find_bone(n) >= 0 else sk.find_bone(n.replace(":", "_"))
	var g := func(n): return (sk.global_transform * sk.get_bone_global_pose(fb.call(n))).origin
	var ss := scene.get_world_3d().direct_space_state
	var res := {"rest_foot_bone_height_m": 0.058, "actor": [snappedf(actor.global_position.x, 0.01), snappedf(actor.global_position.y, 0.001), snappedf(actor.global_position.z, 0.01)], "anim": (npc.player as AnimationPlayer).current_animation}
	for foot in ["LeftToeBase", "RightToeBase", "LeftFoot", "RightFoot"]:
		var p: Vector3 = g.call("mixamorig:" + foot)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.5, 0), p + Vector3(0, -1.5, 0)); q.exclude = [actor.get_rid()]; q.collision_mask = 0xFFFFFFFF & ~(1 << 19)   # 不打小鈴袖子代理（圖層 20）
		var r := ss.intersect_ray(q)
		res[foot + "_bone_above_surface_m"] = [snappedf(p.y - r.position.y, 0.001), str(r.collider.name)] if r else null
	var sl = npc.get_node("Sleeves")
	for s in ["L", "R"]:
		var sb: SoftBody3D = sl.get_sleeve(s)
		var n: int = sb.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
		var nan := 0; var far := 0.0
		var arm: Vector3 = g.call("mixamorig:%sForeArm" % ("Left" if s == "L" else "Right"))
		for i in n:
			var p := sb.get_point_transform(i)
			if not p.is_finite(): nan += 1
			else: far = maxf(far, p.distance_to(arm))
		res["sleeve_" + s] = {"nan": nan, "max_dist_to_forearm_m": snappedf(far, 0.01)}
	ms.sort()
	res["physics_ms_p50_p95"] = [snappedf(ms[ms.size() / 2], 0.01), snappedf(ms[int(ms.size() * 0.95)], 0.01)]
	print("VILLAGE " + JSON.stringify(res))
	quit(0)
