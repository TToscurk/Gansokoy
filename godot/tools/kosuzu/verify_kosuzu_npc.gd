extends SceneTree
## 驗證 characters/kosuzu/kosuzu.tscn：朝向（正面＝+Z）、身高、袖子穩定（邊長拉伸、NaN、離手臂距離）、物理耗時、截圖。
## godot --path godot -s res://tools/kosuzu/verify_kosuzu_npc.gd -- [--out=<dir>] [--clip=idle] [--sec=8] [--scene=res://characters/akyuu/akyuu.tscn]
## 共用：阿求等同樣掛 kosuzu_sleeves.gd 的角色用 --scene；骨名找不到 mixamorig 名時改找 GeneralSkeleton 名。
var npc: Node3D
var t := 0.0
var out := ""
var sec := 8.0
var scene := "res://characters/kosuzu/kosuzu.tscn"
var clip := ""
var rest_len := {}
var edges := {}
var phys_ms := []
var shot_done := false
var vp: SubViewport

func _initialize() -> void:
	out = "D:/神社/proto/kosuzu_sleeve/verify"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--sec="): sec = float(a.substr(6))
		if a.begins_with("--scene="): scene = a.substr(8)
		if a.begins_with("--clip="): clip = a.substr(7)
	DirAccess.make_dir_recursive_absolute(out)
	_setup.call_deferred()

func _setup() -> void:
	var w := Node3D.new(); get_root().add_child(w)
	var env := WorldEnvironment.new(); var e := Environment.new(); e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.33, 0.34, 0.37); e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.82); env.environment = e; w.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 30, 0); w.add_child(sun)
	npc = (load(scene) as PackedScene).instantiate()
	if clip != "": npc.set("animation", StringName(clip))
	w.add_child(npc)
	npc.position = Vector3(0, 0, 0)
	var cam := Camera3D.new(); w.add_child(cam); cam.fov = 38
	cam.look_at_from_position(Vector3(1.3, 1.25, 2.6), Vector3(0, 0.85, 0)); cam.current = true   # 正面（+Z 側）
	vp = SubViewport.new(); vp.size = Vector2i(900, 900); vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS; w.add_child(vp)
	var c2 := Camera3D.new(); vp.add_child(c2); c2.fov = 38; c2.look_at_from_position(Vector3(-1.6, 1.25, -2.4), Vector3(0, 0.85, 0)); c2.current = true

func _physics_process(dt: float) -> bool:
	if npc == null: return false
	t += dt
	if t > 2.5: phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	var sl = npc.get_node("Sleeves")
	if rest_len.is_empty() and sl.get_sleeve("L") != null:
		for s in ["L", "R"]:
			var sb: SoftBody3D = sl.get_sleeve(s)
			var arr := sb.mesh.surface_get_arrays(0)
			var I: PackedInt32Array = arr[Mesh.ARRAY_INDEX]; var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var E := []; var L := []
			for k in range(0, I.size(), 3):
				for p in [[I[k], I[k + 1]], [I[k + 1], I[k + 2]], [I[k + 2], I[k]]]:
					var l := V[p[0]].distance_to(V[p[1]])
					if l > 0.002: E.append(p); L.append(l)
			edges[s] = E; rest_len[s] = L
	if t >= sec:
		_report(); return true
	return false

func _process(_d: float) -> bool:
	if not shot_done and t >= sec - 0.5:
		shot_done = true; _shot()
	return false

func _shot() -> void:
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out + "/front.png")
	vp.get_texture().get_image().save_png(out + "/back.png")

func _report() -> void:
	var sk: Skeleton3D = npc.get_node("Model").find_children("*", "Skeleton3D", true, false)[0]
	var HUM := {"mixamorig:LeftToe_End": "LeftToes", "mixamorig:RightToe_End": "RightToes", "mixamorig:HeadTop_End": "Head",
		"mixamorig:LeftForeArm": "LeftLowerArm", "mixamorig:RightForeArm": "RightLowerArm"}
	var bi := func(n):
		for c in [n, n.replace(":", "_"), n.split(":")[-1], HUM.get(n, "")]:
			if c != "" and sk.find_bone(c) >= 0: return sk.find_bone(c)
		return -1
	var g := func(n): return (sk.global_transform * sk.get_bone_global_pose(bi.call(n))).origin
	var hips: Vector3 = g.call("mixamorig:Hips"); var toeL: Vector3 = g.call("mixamorig:LeftToe_End"); var toeR: Vector3 = g.call("mixamorig:RightToe_End")
	var fwd := ((toeL + toeR) * 0.5 - hips); fwd.y = 0
	var head: Vector3 = g.call("mixamorig:HeadTop_End")
	var res := {"facing_xz": [snappedf(fwd.normalized().x, 0.01), snappedf(fwd.normalized().z, 0.01)], "head_top_y": snappedf(head.y, 0.01),
		"clip": npc.get("animation"), "anim": (npc.player as AnimationPlayer).current_animation}
	var sl = npc.get_node("Sleeves")
	for s in ["L", "R"]:
		var sb: SoftBody3D = sl.get_sleeve(s)
		var n: int = sb.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
		var P := []
		var nan := 0
		for i in n:
			var p := sb.get_point_transform(i); P.append(p)
			if not p.is_finite(): nan += 1
		var mx := 0.0; var over := 0
		for k in edges[s].size():
			var e = edges[s][k]; var r: float = (P[e[0]] as Vector3).distance_to(P[e[1]]) / rest_len[s][k]
			mx = maxf(mx, r); if r > 1.5: over += 1
		var arm: Vector3 = g.call("mixamorig:%sForeArm" % ("Left" if s == "L" else "Right"))
		var far := 0.0
		for p in P: far = maxf(far, (p as Vector3).distance_to(arm))
		res["sleeve_" + s] = {"nan": nan, "edge_stretch_max": snappedf(mx, 0.01), "edges_over_1.5x": over, "max_dist_to_forearm_m": snappedf(far, 0.01)}
	phys_ms.sort()
	res["physics_ms_p50_p95"] = [snappedf(phys_ms[phys_ms.size() / 2], 0.01), snappedf(phys_ms[int(phys_ms.size() * 0.95)], 0.01)]
	print("VERIFY " + JSON.stringify(res))
	quit(0)
