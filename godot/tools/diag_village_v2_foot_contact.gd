extends SceneTree
## 道路上的實際玩家落腳量測（village_v2）：真控制器、真動畫、真 TPS 相機。
## 每個地點：站定 → 量 root／膠囊底／腳下碰撞面／可見路面／可見地形／腳骨；再按 move_forward 走 2 s（＋sprint 1.5 s）→ 停，
## 逐物理幀記錄腳骨（Foot／ToeBase）最低點與「可見路面」的差。鞋底＝腳骨 − 綁定姿勢下（腳骨到網格最低點）的距離。
## 需要視窗（--fcshots 時拍低角度足部圖）；量測本身 headless 也能跑。
##   godot --path godot --resolution 1280x720 --script res://tools/diag_village_v2_foot_contact.gd -- [--fcshots=<prefix>] [--csv=<path>]

const SPOTS := [
	["MainStreet", Vector2(261.47, -14.62), Vector2(265.59, -27.78)],
	["EntranceRoad", Vector2(224.43, 159.16), Vector2(226.10, 145.82)],
	["CrossStreetMid", Vector2(286.48, -25.65), Vector2(272.85, -23.07)],
	["HillFootStreet", Vector2(273.83, -141.55), Vector2(260.87, -146.73)],
	["WestAlley", Vector2(202.49, -13.45), Vector2(205.72, 0.01)],
	["NWLane", Vector2(185.03, -200.50), Vector2(189.64, -187.60)],
	["MidLane", Vector2(241.28, -85.75), Vector2(228.36, -88.98)],
	["FarmPath_2", Vector2(439.60, 10.67), Vector2(440.40, 3.33)],
	["FarmPath_1", Vector2(371.24, 49.67), Vector2(372.26, 39.67)],
	["CrossStreetSouth", Vector2(345.31, 40.85), Vector2(355.38, 42.70)],
]
const TMP_ROAD := 1 << 21
const TMP_TERR := 1 << 22

var main: Node
var player: CharacterBody3D
var skel: Skeleton3D
var foot_bones: Array[int] = []
var sole_pts: Array = []   # [MeshInstance3D 的 skin, v, bones, weights]（綁定時 y 最低的鞋底頂點，CPU 線性蒙皮）
var bone_h := {}   # 骨 → 綁定姿勢下離鞋底（網格最低點）的高度（世界尺度）
var shots := ""


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fcshots="):
			shots = a.get_slice("=", 1)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _phys(n: int) -> void:
	for i in n:
		await physics_frame


func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)


func _tmp_body(nodes: Array, layer: int) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	main.map_root.add_child(sb)
	for mi: MeshInstance3D in nodes:
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape()
		sb.add_child(cs)
		cs.global_transform = mi.global_transform


func _ray(x: float, z: float, y0: float, mask: int) -> Dictionary:
	var sp := player.get_world_3d().direct_space_state
	var span := 3.0 if y0 < 30.0 else 80.0
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, y0 + span, z), Vector3(x, y0 - span, z), mask)
	q.exclude = [player.get_rid()]
	return sp.intersect_ray(q)


func _foot_min() -> Array:
	# [鞋底頂點（CPU 線性蒙皮，與 GPU 同公式）的最低 y, 該點]
	var best := INF
	var at := Vector3.ZERO
	var gx := skel.global_transform
	var cache := {}
	for e in sole_pts:
		var skin: Skin = e[0]
		var v: Vector3 = e[1]
		var bs: PackedInt32Array = e[2]
		var ws: PackedFloat32Array = e[3]
		var acc := Vector3.ZERO
		for k in bs.size():
			if ws[k] <= 0.0:
				continue
			var key := bs[k]
			if not cache.has(key):
				var bi := skin.get_bind_bone(key)
				if bi < 0:
					bi = skel.find_bone(skin.get_bind_name(key))
				cache[key] = skel.get_bone_global_pose(bi) * skin.get_bind_pose(key)
			acc += ws[k] * ((cache[key] as Transform3D) * v)
		var w := gx * acc
		if w.y < best:
			best = w.y
			at = w
	return [best, at]


func _collect_sole() -> void:
	for mi: MeshInstance3D in skel.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null or mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bn = arr[Mesh.ARRAY_BONES]
			var wt = arr[Mesh.ARRAY_WEIGHTS]
			if bn == null or wt == null:
				continue
			var per := (bn as PackedInt32Array).size() / vs.size()
			# 綁定姿勢的世界 y：用 rest（get_bone_global_rest）算一次
			for i in vs.size():
				var bs := PackedInt32Array()
				var ws := PackedFloat32Array()
				var acc := Vector3.ZERO
				for k in per:
					var b: int = bn[i * per + k]
					var w: float = wt[i * per + k]
					bs.append(b)
					ws.append(w)
					if w > 0.0:
						var bi := mi.skin.get_bind_bone(b)
						if bi < 0:
							bi = skel.find_bone(mi.skin.get_bind_name(b))
						acc += w * ((skel.get_bone_global_rest(bi) * mi.skin.get_bind_pose(b)) * vs[i])
				if acc.y < 0.045:
					sole_pts.append([mi.skin, vs[i], bs, ws])


func _run() -> void:
	var sf := root.get_node("/root/StoryFlags")
	sf.set_flag("woke_in_trail", true)
	sf.set_flag("met_reimu", true)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(30)
	main.load_map("village_v2", "")
	await _frames(60)
	player = main.player
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	skel = player.find_children("*", "Skeleton3D", true, false)[0]
	for i in skel.get_bone_count():
		var nm := skel.get_bone_name(i)
		if nm.ends_with("Foot") or nm.ends_with("ToeBase") or nm.ends_with("Toe_End"):
			foot_bones.append(i)
	# 綁定姿勢：腳骨最低點 − 身體網格最低點（鞋底在腳骨下方多少）
	var rest_bone := INF
	for b in foot_bones:
		rest_bone = minf(rest_bone, (skel.get_bone_global_rest(b).origin).y)
	var mesh_min := INF
	for mi: MeshInstance3D in skel.find_children("*", "MeshInstance3D", true, false):
		var ab: AABB = (skel.global_transform.affine_inverse() * mi.global_transform) * mi.mesh.get_aabb()
		mesh_min = minf(mesh_min, ab.position.y)
	_collect_sole()
	print("[foot] 鞋底頂點（綁定姿勢 skeleton 局部 y < 0.045）= %d 個" % sole_pts.size())
	var sc := skel.global_transform.basis.get_scale().y
	var sole_below_bone := 0.0
	for b in foot_bones:
		bone_h[b] = (skel.get_bone_global_rest(b).origin.y - mesh_min) * sc
	print("[foot] 綁定姿勢各腳骨離鞋底 ", foot_bones.map(func(b): return "%s=%.3f" % [skel.get_bone_name(b).trim_prefix("mixamorig_"), bone_h[b]]))
	print("[foot] bones=%s  rest 最低腳骨 %.3f、網格最低 %.3f（skeleton 局部）→ 鞋底在腳骨下 %.3f m（世界）  mask=%d step_height=%.2f floor_snap=%.2f safe_margin=%.3f" % [
		foot_bones.map(func(b): return skel.get_bone_name(b)), rest_bone, mesh_min, sole_below_bone,
		player.collision_mask, player.get("step_height"), player.floor_snap_length, player.safe_margin])
	assert(player.collision_mask & (TMP_ROAD | TMP_TERR) == 0)
	var roads: Array = []
	for g in ["MainStreet", "SecondaryRoads", "Alleys", "FarmPaths"]:
		_meshes(main.map_root.get_node("Roads/" + g), roads)
	_tmp_body(roads, TMP_ROAD)
	var terr: Array = []
	_meshes(main.map_root.get_node("Terrain"), terr)
	_tmp_body(terr, TMP_TERR)
	await _phys(3)
	print("[foot] %-16s %7s %7s %7s %7s | %7s %7s | %8s %8s %8s %8s  %s" % ["spot", "root", "col", "road", "terr", "r-col", "r-root", "idleSole", "walkMin", "runMin", "stopSole", "walk-col", "floor collider"])
	var cam: Camera3D = null
	for s in SPOTS:
		var a: Vector2 = s[1]
		var b: Vector2 = s[2]
		var h0 := _ray(a.x, a.y, 40.0, player.collision_mask)
		var y0: float = h0.position.y if not h0.is_empty() else 0.0
		player.global_position = Vector3(a.x, y0 + 0.3, a.y)
		player.velocity = Vector3.ZERO
		var d := (b - a).normalized()
		player.snap_yaw(atan2(-d.x, -d.y))
		await _phys(50)
		var pp := player.global_position
		var hc := _ray(pp.x, pp.z, pp.y, player.collision_mask)
		var hr := _ray(pp.x, pp.z, pp.y, TMP_ROAD)
		var ht := _ray(pp.x, pp.z, pp.y, TMP_TERR)
		var col_y: float = hc.position.y if not hc.is_empty() else NAN
		var road_y: float = hr.position.y if not hr.is_empty() else NAN
		var terr_y: float = ht.position.y if not ht.is_empty() else NAN
		var cname := String((hc.collider as Node).name) if not hc.is_empty() else "-"
		var fm: Array = _foot_min()
		var idle_sole: float = float(fm[0]) - sole_below_bone - _road_at(fm[1])
		if shots != "":
			cam = _shot_cam(cam, pp, d)
			await _frames(4)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s_%s_idle.png" % [shots, s[0]])
		# 走 2 s → 跑 1.5 s → 停 1 s；逐物理幀：鞋底 − 該點可見路面
		var walk_min := INF
		var run_min := INF
		var walk_col := INF
		var series := PackedFloat32Array()
		var shot_done := false
		Input.action_press("move_forward")
		for i in 120:
			await physics_frame
			var f: Array = _foot_min()
			walk_min = minf(walk_min, float(f[0]) - sole_below_bone - _road_at(f[1]))
			var hcf := _ray((f[1] as Vector3).x, (f[1] as Vector3).z, (f[1] as Vector3).y, player.collision_mask)
			if not hcf.is_empty():
				walk_col = minf(walk_col, float(f[0]) - hcf.position.y)
				if i >= 30:
					series.append(float(f[0]) - hcf.position.y)
			if shots != "" and not shot_done and i == 75:
				cam = _shot_cam(cam, player.global_position, d)
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("%s_%s_walk.png" % [shots, s[0]])
				shot_done = true
		Input.action_press("sprint")
		for i in 90:
			await physics_frame
			var f: Array = _foot_min()
			run_min = minf(run_min, float(f[0]) - sole_below_bone - _road_at(f[1]))
		Input.action_release("sprint")
		Input.action_release("move_forward")
		await _phys(60)
		var fs: Array = _foot_min()
		var stop_sole: float = float(fs[0]) - sole_below_bone - _road_at(fs[1])
		series.sort()
		if series.size() > 0:
			var below := 0
			for x in series:
				if x < -0.025:
					below += 1
			print("[foot] %-16s 走路穩態 %d 幀：最低鞋底−碰撞 p10 %+.3f p50 %+.3f p90 %+.3f；< −2.5 cm 的幀 %d（%.0f%%）" % [s[0], series.size(), series[int(series.size() * 0.1)], series[series.size() / 2], series[int(series.size() * 0.9)], below, 100.0 * below / series.size()])
		print("[foot] %-16s %7.3f %7.3f %7.3f %7.3f | %+7.3f %+7.3f | %+8.3f %+8.3f %+8.3f %+8.3f %+8.3f  %s" % [s[0], pp.y, col_y, road_y, terr_y,
			road_y - col_y, road_y - pp.y, idle_sole, walk_min, run_min, stop_sole, walk_col, cname])
	if cam:
		cam.queue_free()
	print("[foot] done")
	quit(0)


## 腳下可見路面（沒有路面就用地形）
func _road_at(p: Vector3) -> float:
	var h := _ray(p.x, p.z, p.y, TMP_ROAD)
	if h.is_empty():
		h = _ray(p.x, p.z, p.y, TMP_TERR)
	return h.position.y if not h.is_empty() else p.y


## 低角度側視：在玩家側面 1.8 m、離可見路面 0.18 m，看腳
func _shot_cam(cam: Camera3D, pp: Vector3, d: Vector2) -> Camera3D:
	if cam == null:
		cam = Camera3D.new()
		cam.fov = 40.0
		cam.near = 0.02
		main.map_root.add_child(cam)
	var side := Vector3(d.y, 0, -d.x)
	var ry := _road_at(pp + side * 1.8)
	cam.global_position = pp + side * 1.8 + Vector3(0, 0, 0)
	cam.global_position.y = ry + 0.18
	cam.look_at(Vector3(pp.x, ry + 0.12, pp.z), Vector3.UP)
	cam.make_current()
	return cam
