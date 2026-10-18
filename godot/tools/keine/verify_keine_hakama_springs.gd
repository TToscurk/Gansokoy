extends SceneTree
## 慧音 袴骨鏈 SpringBone 實測（需要顯示；mesh 陣列與截圖在 headless 下讀不到）。
## godot --path . --fixed-fps 60 --script res://tools/keine/verify_keine_hakama_springs.gd
## 同一場景、同一 clip、同樣格數下 springs 關／開 A/B：
##   - 胯部露出：身體網格胯部頂點（|x|<0.10 m、兩腰關節下 0.16 m 到上 0.03 m、主權重 Hips／大腿）
##     用 CPU 蒙皮（skeleton_updated 時取彈簧後的骨姿）建全身三角網格，從低角度鏡頭逐點射線，數看得到的點。
##   - 走路：同指標＋小腿露出點數、袴骨末端相對無彈簧的位移、NaN 檢查。
## 輸出：數字到 stdout，4 張圖＋總表到 docs/keine/hakama_springs/。

const SCENE := "res://characters/keine/keine.tscn"
const SIT := "res://animations/npc_activity_p10/setomono_f01/sitting_breathing_a030_grounded.res"
const OUT := "res://../docs/keine/hakama_springs/"

var vis: Node3D
var sk: Skeleton3D
var springs: Node
var sim: SpringBoneSimulator3D
var player: AnimationPlayer
var meshes: Array = []        # [{mi, verts, bones, weights, idx, bind_bone:PackedInt32Array, bind:Array}]
var body_mi: MeshInstance3D
var crotch: PackedInt32Array   # 身體網格頂點索引
var shin: PackedInt32Array
var frame := 0
var want := {}                 # frame -> true
var got := {}                  # frame -> Array[Transform3D]
var space: PhysicsDirectSpaceState3D
var occ_body: StaticBody3D


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.66)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.environment.ambient_light_energy = 0.6
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var floor_ := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(6, 6)
	floor_.mesh = pm
	root.add_child(floor_)

	vis = (load(SCENE) as PackedScene).instantiate()
	vis.set("start_time", 0.0)
	root.add_child(vis)
	await process_frame
	sk = vis.find_child("GeneralSkeleton", true, false) as Skeleton3D
	springs = vis.get_node("HakamaSprings")
	sim = sk.get_node("Spring_Hakama") as SpringBoneSimulator3D
	player = vis.get("player")
	await process_frame
	print("has sit ", player.has_animation(&"sit"))
	print("sim settings ", sim.setting_count, " collisions ", sim.get_collision_count(0), " children ", sim.get_children().map(func(n): return n.name))
	sk.skeleton_updated.connect(_on_updated)
	_load_meshes()
	_select_regions()
	occ_body = StaticBody3D.new()
	occ_body.collision_layer = 1 << 19
	occ_body.collision_mask = 0
	root.add_child(occ_body)
	space = root.get_world_3d().direct_space_state

	# 0) 靜止誤差：用 rest 骨姿 CPU 蒙皮 vs 原始頂點
	var rest_pose: Array = []
	for b in sk.get_bone_count(): rest_pose.append(sk.get_bone_global_rest(b))
	var e := 0.0
	var P := _skin(body_mi, rest_pose)
	var raw: PackedVector3Array = meshes.filter(func(m): return m.mi == body_mi)[0].verts
	for i in range(0, P.size(), 37): e = maxf(e, P[i].distance_to(sk.global_transform * raw[i]))
	print("REST_SKIN_ERR_m ", e, "  crotch verts ", crotch.size(), "  shin verts ", shin.size())

	var res := {}
	# 0b) 站姿基準：idle、彈簧關，用坐姿那組鏡頭（與胯同高）
	var st := await _case(&"idle", false, [60])
	res["stand_idle"] = await _measure(st[60], "sit")
	# 1) 坐姿：sit clip 播 4 秒（240 格）後取一格；垂放 0／1 × 彈簧關／開
	for dr in [0.0, 1.0]:
		springs.set("sit_drape", dr)
		for on in [false, true]:
			var poses := await _case(&"sit", on, [240])
			res["sit_drape%d_springs_%s" % [int(dr), str(on)]] = await _measure(poses[240], "sit")
	# 1b) 坐→走：不帶袴軌道的 clip 是否把袴骨放回靜止（彈簧關）
	var sw := await _case(&"walk", false, [2])
	var dev := 0.0
	for c in springs.get("_data").chains:
		for bn in c.bones:
			var b := sk.find_bone(bn)
			var pl: Transform3D = (sw[2][sk.get_bone_parent(b)] as Transform3D).affine_inverse() * (sw[2][b] as Transform3D)
			dev = maxf(dev, rad_to_deg(pl.basis.get_rotation_quaternion().angle_to(sk.get_bone_rest(b).basis.get_rotation_quaternion())))
	print("SIT_TO_WALK_HAKAMA_LOCAL_DEV_deg ", dev)
	# 2) 走路：播 3 秒穩定後，取一個步伐循環內 4 格
	var wl := player.get_animation(&"walk").length
	var wf: Array = []
	for k in 4: wf.append(180 + int(round(k * wl * 60.0 / 4.0)))
	var walk_poses := {}
	for on in [false, true]:
		walk_poses[on] = await _case(&"walk", on, wf)
		for f in wf:
			res["walk%d_%s" % [f, str(on)]] = await _measure(walk_poses[on][f], "walk")
	# 3) 袴骨末端：彈簧開 vs 關的位移（走路 4 格）、NaN
	var tipdev := 0.0
	var nan := 0
	for f in wf:
		for c in springs.get("_data").chains:
			var b := sk.find_bone(c.bones[2])
			var t_on: Transform3D = walk_poses[true][f][b]
			var t_off: Transform3D = walk_poses[false][f][b]
			var len_: float = c.lengths[2]
			var p_on := t_on * Vector3(0, len_, 0)
			if not p_on.is_finite(): nan += 1
			tipdev = maxf(tipdev, p_on.distance_to(t_off * Vector3(0, len_, 0)))
	print("WALK_TIP_DEV_MAX_m ", tipdev, " NaN ", nan)
	# 4) 站著不動的靜態下垂：idle 2 秒，彈簧開 vs 關的袴骨末端位移
	var i_off := await _case(&"idle", false, [120])
	var i_on := await _case(&"idle", true, [120])
	var idev := {}
	for c in springs.get("_data").chains:
		var b := sk.find_bone(c.bones[2])
		var len2: float = c.lengths[2]
		idev[c.dir] = snappedf(((i_on[120][b] as Transform3D) * Vector3(0, len2, 0)).distance_to((i_off[120][b] as Transform3D) * Vector3(0, len2, 0)), 0.001)
	print("IDLE_TIP_DEV_m ", idev)
	for k in res: print("RESULT ", k, " ", JSON.stringify(res[k]))
	await _shots()
	quit()


func _on_updated() -> void:
	frame += 1
	if want.has(frame):
		var a: Array = []
		for b in sk.get_bone_count(): a.append(sk.get_bone_global_pose(b))
		got[frame] = a


## 同一程序：clip 從 0 開始、彈簧 reset、跑到最大格；回傳 {frame: poses}
func _case(clip: StringName, on: bool, frames: Array) -> Dictionary:
	springs.set("springs_enabled", on)
	vis.call("play_clip", clip, 0.0)
	sim.reset()
	frame = 0
	want.clear(); got.clear()
	for f in frames: want[f] = true
	var last: int = frames.max()
	while frame < last:
		await process_frame
	return got.duplicate()


func _load_meshes() -> void:
	for n in vis.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var a := mi.mesh.surface_get_arrays(0)
		var skin := mi.skin
		var bb := PackedInt32Array(); var bind: Array = []
		for j in skin.get_bind_count():
			var bi := skin.get_bind_bone(j)
			if bi < 0: bi = sk.find_bone(skin.get_bind_name(j))
			bb.append(bi); bind.append(skin.get_bind_pose(j))
		meshes.append({"mi": mi, "verts": a[Mesh.ARRAY_VERTEX], "bones": a[Mesh.ARRAY_BONES], "weights": a[Mesh.ARRAY_WEIGHTS], "idx": a[Mesh.ARRAY_INDEX], "bb": bb, "bind": bind})
		if mi.name == "身體": body_mi = mi
		print("mesh ", mi.name, " v ", (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), " w/v ", (a[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array).size() / maxi(1, (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()))


func _select_regions() -> void:
	var m: Dictionary = meshes.filter(func(x): return x.mi == body_mi)[0]
	var hy := sk.get_bone_global_rest(sk.find_bone("LeftUpperLeg")).origin.y
	var ky := sk.get_bone_global_rest(sk.find_bone("LeftLowerLeg")).origin.y
	var fy := sk.get_bone_global_rest(sk.find_bone("LeftFoot")).origin.y
	var ok_c := [sk.find_bone("Hips"), sk.find_bone("LeftUpperLeg"), sk.find_bone("RightUpperLeg")]
	var ok_s := [sk.find_bone("LeftLowerLeg"), sk.find_bone("RightLowerLeg")]
	var V: PackedVector3Array = m.verts
	var B: PackedInt32Array = m.bones
	var W: PackedFloat32Array = m.weights
	for i in V.size():
		var dom: int = m.bb[B[i * 4]]
		var wbest := W[i * 4]
		for k in range(1, 4):
			if W[i * 4 + k] > wbest: wbest = W[i * 4 + k]; dom = m.bb[B[i * 4 + k]]
		var p := V[i]
		if absf(p.x) < 0.10 and p.y > hy - 0.16 and p.y < hy + 0.03 and dom in ok_c: crotch.append(i)
		elif p.y > fy + 0.05 and p.y < ky and dom in ok_s: shin.append(i)


func _skin(mi: MeshInstance3D, poses: Array) -> PackedVector3Array:
	var m: Dictionary = meshes.filter(func(x): return x.mi == mi)[0]
	var M: Array = []
	for j in (m.bb as PackedInt32Array).size():
		M.append(sk.global_transform * (poses[m.bb[j]] as Transform3D) * (m.bind[j] as Transform3D))
	var V: PackedVector3Array = m.verts
	var B: PackedInt32Array = m.bones
	var W: PackedFloat32Array = m.weights
	var out := PackedVector3Array(); out.resize(V.size())
	for i in V.size():
		var v := V[i]
		var k := i * 4
		var p: Vector3 = (M[B[k]] as Transform3D) * v * W[k]
		if W[k + 1] > 0.0: p += (M[B[k + 1]] as Transform3D) * v * W[k + 1]
		if W[k + 2] > 0.0: p += (M[B[k + 2]] as Transform3D) * v * W[k + 2]
		if W[k + 3] > 0.0: p += (M[B[k + 3]] as Transform3D) * v * W[k + 3]
		out[i] = p
	return out


## 用這組骨姿蒙皮全身、建遮擋網格，從鏡頭射線數胯部／小腿看得到的點。
func _measure(poses: Array, kind: String) -> Dictionary:
	var faces := PackedVector3Array()
	var body_p: PackedVector3Array
	for m in meshes:
		var P := _skin(m.mi, poses)
		if m.mi == body_mi: body_p = P
		var I: PackedInt32Array = m.idx
		var base := faces.size()
		faces.resize(base + I.size())
		for t in I.size(): faces[base + t] = P[I[t]]
	for c in occ_body.get_children(): c.free()
	var cs := CollisionShape3D.new()
	var sh := ConcavePolygonShape3D.new(); sh.set_faces(faces)
	cs.shape = sh
	occ_body.add_child(cs)
	await physics_frame
	await physics_frame
	var g := sk.global_transform
	var lh: Vector3 = g * (poses[sk.find_bone("LeftUpperLeg")] as Transform3D).origin
	var rh: Vector3 = g * (poses[sk.find_bone("RightUpperLeg")] as Transform3D).origin
	var lk: Vector3 = g * (poses[sk.find_bone("LeftLowerLeg")] as Transform3D).origin
	var rk: Vector3 = g * (poses[sk.find_bone("RightLowerLeg")] as Transform3D).origin
	var aim := (lh + rh) * 0.5
	var cams: Array = []
	if kind == "sit":
		# 6 個低角度：正面、±30°、±60° 與胯同高，再加正面低 0.25 m 往上看
		for az in [0.0, 30.0, -30.0, 60.0, -60.0]:
			cams.append(aim + Vector3(sin(deg_to_rad(az)), 0, cos(deg_to_rad(az))) * 1.6)
		cams.append(aim + Vector3(0, -0.25, 1.6))
	else:
		for az in [0.0, 90.0, 180.0, 270.0]:
			cams.append(Vector3(sin(deg_to_rad(az)) * 1.8, 0.6, cos(deg_to_rad(az)) * 1.8))
	var r := {"crotch_visible": _count(body_p, crotch, cams), "shin_visible": _count(body_p, shin, cams)}
	r["hip_y"] = snappedf(aim.y, 0.001)
	r["knee_y"] = snappedf((lk.y + rk.y) * 0.5, 0.001)
	var f3: Transform3D = poses[sk.find_bone("Hakama_F_3")]
	var tip := g * (f3 * Vector3(0, 0.25, 0))
	r["front_tip"] = [snappedf(tip.x, 0.001), snappedf(tip.y, 0.001), snappedf(tip.z, 0.001)]
	r["knee_z"] = snappedf((lk.z + rk.z) * 0.5, 0.001)
	return r


func _count(P: PackedVector3Array, sel: PackedInt32Array, cams: Array) -> Array:
	var per: Array = []
	var any := {}
	for c in cams:
		var n := 0
		for i in sel:
			var v := P[i]
			var d := v - (c as Vector3)
			var q := PhysicsRayQueryParameters3D.create(c, (c as Vector3) + d * (1.0 + 0.02 / d.length()), 1 << 19)
			var h := space.intersect_ray(q)
			if h.is_empty() or (h.position as Vector3).distance_to(c) >= d.length() - 0.01:
				n += 1; any[i] = true
		per.append(n)
	return [any.size(), per]


func _shots() -> void:
	for c in occ_body.get_children(): c.free()
	var cam := Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	cam.make_current()
	var imgs: Array = []
	var specs := [[&"sit", Vector3(0.0, 0.62, 2.3), Vector3(0, 0.62, 0.2), "sit_front_low"],
		[&"sit", Vector3(2.3, 0.75, 0.6), Vector3(0, 0.6, 0.2), "sit_side"],
		[&"walk", Vector3(0.0, 0.85, 3.2), Vector3(0, 0.8, 0), "walk_front"],
		[&"walk", Vector3(3.2, 0.85, 0.0), Vector3(0, 0.8, 0), "walk_side"]]
	for s in specs:
		await _case(s[0], true, [200])
		cam.look_at_from_position(s[1], s[2])
		await process_frame
		await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_jpg(ProjectSettings.globalize_path(OUT + s[3] + ".jpg"), 0.9)
		imgs.append(img)
		print("SHOT ", s[3])
	var im0: Image = imgs[0]
	var w: int = im0.get_width() / 2
	var h: int = im0.get_height() / 2
	var sheet := Image.create(w * 2, h * 2, false, im0.get_format())
	for k in 4:
		var im: Image = imgs[k].duplicate()
		im.resize(w, h)
		sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((k % 2) * w, (k / 2) * h))
	sheet.save_jpg(ProjectSettings.globalize_path(OUT + "sheet.jpg"), 0.88)
