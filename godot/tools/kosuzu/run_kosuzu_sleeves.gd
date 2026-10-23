extends SceneTree
## 小鈴雙袖 SoftBody3D（Jolt）測試：播 Mixamo 動作序列，輸出布點取樣與截圖。
## godot --path godot -s res://tools/kosuzu/run_kosuzu_sleeves.gd -- --tag=x [--clips=idle_female:4,walk_female:4]
##   [--stiff=0.8 --prec=10 --mass=0.2 --damp=0.05 --pressure=0 --shots=1 --out=<abs dir>]
const DIR := "res://characters/kosuzu/"
const S := 1.5642                     # Tripo 匯出縮成 0.639 → 還原為原始 1.56 m
const LOOP := ["idle_female", "idle_happy", "walk_female", "look_around", "talk_funny", "sit_chair_idle", "thinking"]
var A := {}
var kroot: Node3D
var skel: Skeleton3D
var ap: AnimationPlayer
var bones := {}
var sleeves := {}                    # side -> {sb, nverts, pin_count}
var att := {}                        # bone -> Node3D（世界、正交）
var bodies := []                     # [AnimatableBody3D, bone, local_xform]
var caps := []                       # [AnimatableBody3D, bone_a, bone_b]
var seq := []                        # [[clip, sec], ...]
var seq_i := -1
var seq_t := 0.0
var t := 0.0
var nphys := 0
var hz := 60
var ramp := 2.0                      # 由 T-pose 漸入動作的秒數
var settle := 1.0                    # 開始前 T-pose 靜置秒數
var samples := []
var out_dir := ""
var vp_b: SubViewport
var shot_q := []
var rest_pose := {}
var ready_ok := false

func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="): return a.split("=", true, 1)[1]
	return d

func _initialize() -> void:
	A.tag = _arg("tag", "base")
	A.stiff = float(_arg("stiff", "0.8")); A.prec = int(_arg("prec", "10")); A.mass = float(_arg("mass", "0.2"))
	A.damp = float(_arg("damp", "0.05")); A.pressure = float(_arg("pressure", "0")); A.shots = _arg("shots", "1") == "1"
	for c in _arg("clips", "idle_female:4,walk_female:4,waving:3,bow_formal:3,pickup_onehand:4,bashful:4").split(","):
		var p := c.split(":"); seq.append([p[0], float(p[1])])
	hz = int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second"))
	out_dir = _arg("out", "D:/神社/proto/kosuzu_sleeve/shrine_runs/" + A.tag)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_setup.call_deferred()

func _bone(n: String) -> int:
	for cand in [n, n.replace(":", "_"), "mixamorig_" + n.split(":")[-1], n.split(":")[-1]]:
		var i := skel.find_bone(cand)
		if i >= 0: return i
	push_error("bone not found " + n); return -1

func _bw(i: int) -> Transform3D:
	var g := skel.global_transform * skel.get_bone_global_pose(i)
	return Transform3D(g.basis.orthonormalized(), g.origin)

func _bw_rest(i: int) -> Transform3D:
	var g := skel.global_transform * skel.get_bone_global_rest(i)
	return Transform3D(g.basis.orthonormalized(), g.origin)

func _b2g(p: Array) -> Vector3:
	return Vector3(p[0], p[2], -p[1]) * S

func _setup() -> void:
	var world := Node3D.new(); world.name = "World"; get_root().add_child(world)
	kroot = Node3D.new(); kroot.name = "KosuzuRoot"; kroot.scale = Vector3.ONE * S; world.add_child(kroot)
	var rig: Node3D = (load(DIR + "kosuzu.glb") as PackedScene).instantiate(); kroot.add_child(rig)
	skel = rig.find_children("*", "Skeleton3D", true, false)[0]
	ap = rig.find_children("*", "AnimationPlayer", true, false)[0]
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for n in ap.get_animation_list():
		var an := ap.get_animation(n)
		an.loop_mode = Animation.LOOP_LINEAR if n in LOOP else Animation.LOOP_NONE
	A.anims = Array(ap.get_animation_list())
	for i in skel.get_bone_count(): rest_pose[i] = skel.get_bone_rest(i)
	# 環境
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.32, 0.33, 0.36)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.78, 0.78, 0.8); e.ambient_light_energy = 0.9
	env.environment = e; world.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, -60, 0); sun.light_energy = 1.3; world.add_child(sun)
	# 正面 = -X
	var cam := Camera3D.new(); world.add_child(cam); cam.fov = 38
	cam.look_at_from_position(Vector3(-2.6, 1.15, -1.4), Vector3(0, 0.85, 0)); cam.current = true
	vp_b = SubViewport.new(); vp_b.size = Vector2i(960, 960); vp_b.render_target_update_mode = SubViewport.UPDATE_ALWAYS; world.add_child(vp_b)
	var cb := Camera3D.new(); vp_b.add_child(cb); cb.fov = 38
	cb.look_at_from_position(Vector3(1.9, 1.15, 2.0), Vector3(0, 0.85, 0)); cb.current = true
	# 碰撞代理
	var cj = JSON.parse_string(FileAccess.get_file_as_string(DIR + "kosuzu_colliders.json"))
	for sd in cj.slabs:
		var bi := _bone(sd.bone); var inv := _bw_rest(bi).affine_inverse()
		var pv := PackedVector3Array()
		for q in sd.pts_blender: pv.append(inv * _b2g(q))
		var ab := _body(world, "Slab%.2f" % sd.z); var cs := CollisionShape3D.new(); var sh := ConvexPolygonShape3D.new(); sh.points = pv
		cs.shape = sh; ab.add_child(cs); bodies.append([ab, bi])
	for c in cj.capsules:
		var ab := _body(world, "Cap_" + str(c.name)); var cs := CollisionShape3D.new(); var sh := CapsuleShape3D.new()
		sh.radius = float(c.r) * S; sh.height = 0.1; cs.shape = sh; ab.add_child(cs)
		caps.append([ab, _bone(c.a), _bone(c.b)])
	for n in ["LeftArm", "RightArm", "LeftShoulder", "RightShoulder"]:
		var nd := Node3D.new(); nd.name = "Att_" + n; world.add_child(nd); att[n] = nd
	_update_proxies()
	# 袖
	for side in ["L", "R"]:
		var sl: Node = (load(DIR + "kosuzu_sleeve_%s.glb" % side) as PackedScene).instantiate()
		var mi: MeshInstance3D = sl.find_children("*", "MeshInstance3D", true, false)[0]
		var arr := mi.mesh.surface_get_arrays(0)
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in V.size(): V[i] = V[i] * S
		arr[Mesh.ARRAY_VERTEX] = V
		var am := ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := mi.mesh.surface_get_material(0)
		if mat:
			var m2: Material = mat.duplicate()
			if m2 is BaseMaterial3D: (m2 as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
			am.surface_set_material(0, m2)
		var sb := SoftBody3D.new(); sb.name = "Sleeve" + side; sb.mesh = am
		sb.simulation_precision = A.prec; sb.total_mass = A.mass; sb.linear_stiffness = A.stiff
		sb.damping_coefficient = A.damp; sb.pressure_coefficient = A.pressure
		sb.collision_layer = 0; sb.collision_mask = 2
		world.add_child(sb)
		var C: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var side_n := "Left" if side == "L" else "Right"
		var np := 0
		for i in V.size():
			var c := C[i]
			var a_name := ""
			if c.r > 0.5: a_name = side_n + "Arm"
			elif c.b > 0.5: a_name = side_n + "Shoulder"
			if a_name != "":
				sb.set_point_pinned(i, true, sb.get_path_to(att[a_name])); np += 1
		sleeves[side] = {"sb": sb, "n": V.size(), "pins": np}
		var f := FileAccess.open(out_dir + "/topology_%s.json" % side, FileAccess.WRITE)
		var Vb := []
		for v in V: Vb.append([snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)])
		f.store_string(JSON.stringify({"rest": Vb, "index": Array(arr[Mesh.ARRAY_INDEX])})); f.close()
	var drv := Node.new(); drv.set_script(load("res://tools/kosuzu/_physics_driver.gd")); drv.process_physics_priority = -1000
	drv.cb = _step; world.add_child(drv)
	print("SETUP tag=%s anims=%s sleeves=%s slabs=%d caps=%d hz=%d" % [A.tag, str(A.anims), str({"L": [sleeves.L.n, sleeves.L.pins], "R": [sleeves.R.n, sleeves.R.pins]}), bodies.size(), caps.size(), hz])
	ready_ok = true

func _body(parent: Node, nm: String) -> AnimatableBody3D:
	var ab := AnimatableBody3D.new(); ab.name = nm; ab.collision_layer = 2; ab.collision_mask = 0; ab.sync_to_physics = true
	parent.add_child(ab); return ab

func _update_proxies() -> void:
	for b in bodies: (b[0] as AnimatableBody3D).global_transform = _bw(b[1])
	for c in caps:
		var a := _bw(c[1]).origin; var bb := _bw(c[2]).origin
		var sh: CapsuleShape3D = (c[0].get_child(0) as CollisionShape3D).shape
		sh.height = max(a.distance_to(bb) + 2.0 * sh.radius, 2.0 * sh.radius + 0.001)
		var y := (bb - a).normalized(); var x := y.cross(Vector3.FORWARD)
		if x.length() < 0.1: x = y.cross(Vector3.RIGHT)
		x = x.normalized()
		(c[0] as AnimatableBody3D).global_transform = Transform3D(Basis(x, y, x.cross(y)), (a + bb) * 0.5)
	for n in att: (att[n] as Node3D).global_transform = _bw(_bone("mixamorig:" + n))

func _step() -> void:
	if not ready_ok: return
	nphys += 1
	var dt := 1.0 / hz
	t += dt
	var k := 0.0
	if t > settle:
		if seq_i < 0 or seq_t >= seq[seq_i][1]:
			seq_i += 1; seq_t = 0.0
			if seq_i >= seq.size():
				_finish(); return
			ap.play(seq[seq_i][0], 0.0 if seq_i == 0 else 0.3)
			shot_q.append([seq[seq_i][0], seq[seq_i][1] * 0.5])
			shot_q.append([seq[seq_i][0], seq[seq_i][1] * 0.95])
		ap.advance(dt); seq_t += dt
		k = clamp((t - settle) / ramp, 0.0, 1.0)
		if k < 1.0:
			for i in skel.get_bone_count():
				var r: Transform3D = rest_pose[i]
				var q := r.basis.get_rotation_quaternion().slerp(skel.get_bone_pose_rotation(i), k)
				skel.set_bone_pose_rotation(i, q)
				skel.set_bone_pose_position(i, r.origin.lerp(skel.get_bone_pose_position(i), k))
	_update_proxies()
	# 取樣：每 0.25 s，避開切換後 0.35 s 與漸入
	if nphys % int(hz / 4) == 0 and seq_i >= 0 and (seq_t > 0.35 or seq_i == 0) and k >= 1.0 or (nphys == int(settle * hz) - 1):
		var rec := {"t": t, "clip": seq[seq_i][0] if seq_i >= 0 else "tpose", "pos": ap.current_animation_position if seq_i >= 0 else 0.0, "k": k}
		for side in sleeves:
			var sb: SoftBody3D = sleeves[side].sb
			var P := []
			for i in sleeves[side].n:
				var v := sb.get_point_transform(i); P.append([snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)])
			rec["pts_" + side] = P
		var hl := _bw(_bone("mixamorig:LeftHand")).origin
		rec["handL"] = [hl.x, hl.y, hl.z]
		samples.append(rec)

func _finish() -> void:
	var f := FileAccess.open(out_dir + "/samples.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"args": A, "S": S, "samples": samples})); f.close()
	print("DONE tag=%s samples=%d" % [A.tag, samples.size()])
	quit(0)

func _process(_d: float) -> bool:
	if not ready_ok or not A.shots or shot_q.is_empty(): return false
	var s = shot_q[0]
	if seq_i >= 0 and seq[seq_i][0] == s[0] and seq_t >= s[1]:
		shot_q.pop_front(); _shot("%s_%.1f" % [s[0], s[1]])
	elif seq_i >= 0 and seq[seq_i][0] != s[0] and seq_i > 0:
		shot_q.pop_front()
	return false

func _shot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out_dir + "/shot_%s_a.png" % nm)
	vp_b.get_texture().get_image().save_png(out_dir + "/shot_%s_b.png" % nm)
