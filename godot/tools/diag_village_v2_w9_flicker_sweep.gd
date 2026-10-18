extends SceneTree
## W9 全 46 棟的「畫面閃爍」掃描（需要視窗）。對每棟、每個方位（body 的 ±X／±Z）、每組 Kit 網格：
##   base＝Kit/LOD0..2/base_0；kit＝其餘仍可見的 Kit 構件（overlay 沒藏的）。
## 把該組換成不受光洋紅哨兵 → 相機 2 mm 側移 12 幀 → 數「內部像素在哨兵↔非哨兵間翻轉」次數；
## 同條件把 overlay（ArchW9R2P13/<id>）隱藏再數一次（solo 對照）。翻轉 ≫ solo ⇒ overlay ⟷ Kit 共面 z-fighting（畫面上會閃）。
##   godot --path godot --resolution 640x360 --script res://tools/diag_village_v2_w9_flicker_sweep.gd -- [--dist=12] [--ids=..] [--shots=<prefix>] [--shotall] [--still]
## --rays：對被標記（或 --shotall）的機位，從翻轉像素打射線，印出 overlay 與 Kit 各自命中的網格／surface／三角形與深度差（找出確切的衝突幾何）。
## --still：隱藏植被／NPC／水／粒子，排除會自己動的東西造成的翻轉（用來判定剩餘翻轉是不是建築 z-fighting）。

var dist := 12.0
var ids := PackedStringArray()
var shots := ""
var shot_all := false
var still := false
var rays := false
var main: Node
var last_mask := PackedByteArray()


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dist="):
			dist = float(a.get_slice("=", 1))
		elif a.begins_with("--ids="):
			ids = a.get_slice("=", 1).split(",")
		elif a == "--rays":
			rays = true
		elif a == "--still":
			still = true
		elif a == "--shotall":
			shot_all = true
		elif a.begins_with("--shots="):
			shots = a.get_slice("=", 1)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _grab() -> PackedByteArray:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	return img.get_data()


func _sent(d: PackedByteArray, i: int) -> bool:
	return d[i] > 215 and d[i + 2] > 215 and d[i + 1] < 64


func _count(cam: Camera3D, pos: Vector3, w: int, h: int) -> Array:
	var right := cam.global_transform.basis.x
	cam.global_position = pos
	await _frames(6)
	var prev := await _grab()
	var flips := 0
	var spx := 0
	last_mask = PackedByteArray()
	last_mask.resize(w * h)
	for k in 12:
		cam.global_position = pos + right * 0.002 * (k + 1)
		await _frames(1)
		var cur := await _grab()
		for y in range(1, h - 1, 1):
			for x in range(1, w - 1, 1):
				var i := (y * w + x) * 3
				var a := _sent(cur, i)
				if a:
					spx += 1
				if a == _sent(prev, i):
					continue
				var inner := true
				for o in [-3, 3, -w * 3, w * 3]:
					if not (_sent(cur, i + o) or _sent(prev, i + o)):
						inner = false
						break
				if inner:
					flips += 1
					last_mask[y * w + x] = 255
		prev = cur
	return [flips, spx / 12]


static func _alpha_mat(m: Material) -> bool:
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	if m is ShaderMaterial and (m as ShaderMaterial).shader:
		var c := (m as ShaderMaterial).shader.code
		return c.contains("ALPHA") or c.contains("discard")
	return false


static func _alpha_geo(g: GeometryInstance3D) -> bool:
	if g.material_override and _alpha_mat(g.material_override):
		return true
	var mesh: Mesh = null
	if g is MeshInstance3D:
		mesh = (g as MeshInstance3D).mesh
		for i in (g as MeshInstance3D).get_surface_override_material_count():
			var o := (g as MeshInstance3D).get_surface_override_material(i)
			if o and _alpha_mat(o):
				return true
	elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
		mesh = (g as MultiMeshInstance3D).multimesh.mesh
	if mesh:
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if m and _alpha_mat(m):
				return true
	return false


## 每個 (網格, surface) 一個 ConcavePolygonShape3D：shape 索引 → [標籤, surface]；face_index＝該 surface 的三角形序
func _ray_body(parent: Node, meshes: Array, layer: int) -> Array:
	var sb := StaticBody3D.new()
	sb.collision_layer = layer
	sb.collision_mask = 0
	parent.add_child(sb)
	var map := []
	for mi: MeshInstance3D in meshes:
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var f := PackedVector3Array()
			if arr[Mesh.ARRAY_INDEX] != null:
				for i: int in arr[Mesh.ARRAY_INDEX]:
					f.append(mi.global_transform * vs[i])
			else:
				for v in vs:
					f.append(mi.global_transform * v)
			var sh := ConcavePolygonShape3D.new()
			sh.backface_collision = true
			sh.set_faces(f)
			var cs := CollisionShape3D.new()
			cs.shape = sh
			sb.add_child(cs)
			map.append(["%s(%s)" % [String(main.map_root.get_path_to(mi)), mi.mesh.resource_path.get_file()], si])
	return [sb, map]


func _ray_report(cam: Camera3D, mask: PackedByteArray, w: int, ov_meshes: Array, kit_meshes: Array) -> void:
	var a: Array = _ray_body(main.map_root, ov_meshes, 1 << 25)
	var b: Array = _ray_body(main.map_root, kit_meshes, 1 << 26)
	await physics_frame
	await physics_frame
	var sp: PhysicsDirectSpaceState3D = main.map_root.get_world_3d().direct_space_state
	var px := []
	for i in mask.size():
		if mask[i] > 0:
			px.append(i)
	var step := maxi(1, px.size() / 10)
	var tally := {}
	for k in range(0, px.size(), step):
		var i: int = px[k]
		var sxy := Vector2(i % w + 0.5, i / w + 0.5)
		var o := cam.project_ray_origin(sxy)
		var dv := cam.project_ray_normal(sxy)
		var res := []
		for e in [[1 << 25, a], [1 << 26, b]]:
			var q := PhysicsRayQueryParameters3D.create(o, o + dv * 200.0, e[0])
			q.hit_back_faces = true
			var h := sp.intersect_ray(q)
			if h.is_empty():
				res.append(null)
			else:
				var m: Array = (e[1] as Array)[1][int(h.shape)]
				res.append([o.distance_to(h.position), m[0], m[1], int(h.face_index), h.position, h.normal])
		var line := "[fsw-ray]   px(%d,%d) " % [int(sxy.x), int(sxy.y)]
		for j in 2:
			var r = res[j]
			line += ("overlay " if j == 0 else " | kit ") + ("-" if r == null else "%.4f m %s s%d t%d @(%.3f,%.3f,%.3f) n(%.2f,%.2f,%.2f)" % [r[0], r[1], r[2], r[3], r[4].x, r[4].y, r[4].z, r[5].x, r[5].y, r[5].z])
		if res[0] != null and res[1] != null:
			line += "  深度差 %+.4f m" % [float(res[0][0]) - float(res[1][0])]
			var key := "%s s%d t%d ⟷ %s s%d t%d" % [res[0][1], res[0][2], res[0][3], res[1][1], res[1][2], res[1][3]]
			tally[key] = int(tally.get(key, 0)) + 1
		print(line)
	for key in tally:
		print("[fsw-ray]   配對 ×%d：%s" % [tally[key], key])
	(a[0] as Node).queue_free()
	(b[0] as Node).queue_free()
	await physics_frame


func _run() -> void:
	var sf := root.get_node("/root/StoryFlags")
	sf.set_flag("woke_in_trail", true)
	sf.set_flag("met_reimu", true)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(30)
	main.load_map("village_v2", "")
	await _frames(90)
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	main.player.global_position = Vector3(0, -50, 0)
	main.player.set_physics_process(false)
	if still:
		# 對照：把會自己動的東西（植被風動、NPC、水、粒子）全藏掉 → 剩下的翻轉只可能來自靜態幾何
		for nm in ["Vegetation", "Population", "Water", "WaterLifeP10"]:
			var nd := main.map_root.get_node_or_null(nm) as Node3D
			if nd:
				nd.visible = false
		for g in main.map_root.find_children("*", "GPUParticles3D", true, false):
			(g as Node3D).visible = false
		# 其他圖層裡的葉片／草（alpha 裁切或 discard 的材質）也藏掉；建築本體（Districts／Landmarks／ArchW9R2P13）不動
		var n_alpha := 0
		for g in main.map_root.find_children("*", "GeometryInstance3D", true, false):
			var path := String(main.map_root.get_path_to(g))
			if path.begins_with("Districts/") or path.begins_with("Landmarks/") or path.begins_with("ArchW9R2P13/") or path.begins_with("Terrain/") or path.begins_with("Roads/"):
				continue
			if _alpha_geo(g as GeometryInstance3D):
				(g as Node3D).visible = false
				n_alpha += 1
		print("[fsw] --still：已隱藏 Vegetation／Population／Water／WaterLifeP10／粒子＋其他圖層 alpha 葉片 %d 個" % n_alpha)
	var lg: Node = main.map_root.get_node_or_null("LodGuardP13")
	if lg:
		lg.set("enabled", false)   # 掃描期間不讓 LOD 初始化幀干擾
	var sentinel := StandardMaterial3D.new()
	sentinel.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sentinel.albedo_color = Color(1, 0, 1)
	sentinel.disable_fog = true
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.05
	main.map_root.add_child(cam)
	cam.make_current()
	var w := root.get_texture().get_width()
	var h := root.get_texture().get_height()
	var sp: PhysicsDirectSpaceState3D = main.map_root.get_world_3d().direct_space_state
	var arch: Node = main.map_root.get_node("ArchW9R2P13")
	var hits := 0
	for ov: Node3D in arch.get_children():
		if not ids.is_empty() and not ids.has(String(ov.name)):
			continue
		var body: Node3D = main.map_root.get_node(NodePath(String(ov.get_meta("body_path"))))
		var kit := body.get_node_or_null("Kit")
		if kit == null:
			continue
		var sets := {"base": [], "kit": []}
		for l in 3:
			var g := kit.get_node_or_null("LOD%d" % l)
			if g == null:
				continue
			for mi in g.get_children():
				if mi is MeshInstance3D and (mi as MeshInstance3D).visible:
					(sets["base"] if String(mi.name).begins_with("base") else sets["kit"]).append(mi)
		var l0 := ov.get_node("L0") as MeshInstance3D
		var ab := l0.global_transform * l0.get_aabb()
		var c := ab.get_center()
		var bx := body.global_transform.basis
		for dv in [bx.x, -bx.x, bx.z, -bx.z]:
			var d := Vector3(dv.x, 0, dv.z).normalized()
			var reach := absf(d.dot(Vector3(1, 0, 0))) * ab.size.x * 0.5 + absf(d.dot(Vector3(0, 0, 1))) * ab.size.z * 0.5
			var pos := c + d * (reach + dist)
			var q := PhysicsRayQueryParameters3D.create(Vector3(pos.x, 80, pos.z), Vector3(pos.x, -30, pos.z))
			var gh := sp.intersect_ray(q)
			pos.y = (gh.position.y if not gh.is_empty() else ab.position.y) + 2.5
			cam.global_position = pos
			cam.look_at(Vector3(c.x, ab.position.y + 1.5, c.z), Vector3.UP)
			for sk in ["base", "kit"]:
				var meshes: Array = sets[sk]
				if meshes.is_empty():
					continue
				var saved := []
				for mi: MeshInstance3D in meshes:
					saved.append(mi.material_override)
					mi.material_override = sentinel
				var r: Array = await _count(cam, pos, w, h)
				var rmask := last_mask.duplicate()   # 必須在 solo 之前取（solo 會覆寫 last_mask）
				var solo := [0, 0]
				if int(r[0]) > 0:
					ov.visible = false
					solo = await _count(cam, pos, w, h)
					ov.visible = true
				for i in meshes.size():
					(meshes[i] as MeshInstance3D).material_override = saved[i]
				var flag := int(r[0]) >= 40 and int(r[0]) > 4 * int(solo[0]) + 10
				if flag:
					hits += 1
				print("[fsw] %s %-12s dir(%+.2f,%+.2f) %-4s 哨兵 %6d px 翻轉 %5d  solo %5d %s" % ["!!" if flag else "  ", ov.name, d.x, d.z, sk, r[1], r[0], solo[0], "← overlay 造成" if flag else ""])
				if rays and (flag or shot_all) and int(r[0]) > 0:
					cam.global_position = pos
					var ovm: Array = []
					for n in ov.find_children("*", "MeshInstance3D", true, false):
						var gi := n as MeshInstance3D
						if gi.is_visible_in_tree() and gi.mesh and (gi.visibility_range_end == 0.0 or gi.visibility_range_end > 20.0) and gi.visibility_range_begin < 20.0:
							ovm.append(gi)
					await _ray_report(cam, rmask, w, ovm, meshes.filter(func(m): return String(m.get_parent().name) == "LOD0"))
				if (flag or shot_all) and shots != "":
					for i in meshes.size():
						(meshes[i] as MeshInstance3D).material_override = sentinel
					cam.global_position = pos
					await _frames(4)
					await RenderingServer.frame_post_draw
					var shot := root.get_texture().get_image()
					shot.convert(Image.FORMAT_RGB8)
					for i in w * h:
						if rmask[i] > 0:
							shot.set_pixel(i % w, i / w, Color(0, 1, 0))
					shot.save_png("%s_%s_%d_%s.png" % [shots, ov.name, int(rad_to_deg(atan2(d.x, d.z))), sk])
					for i in meshes.size():
						(meshes[i] as MeshInstance3D).material_override = saved[i]
	print("[fsw] 標記 %d" % hits)
	quit(0)
