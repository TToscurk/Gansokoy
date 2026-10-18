extends SceneTree
## 道路「GPU 實際畫出的地面 ↔ 玩家碰撞」對照（village_v2，2026-10-18）。需要視窗（不可 --headless）。
##   godot --path godot --resolution 1024x1024 --script res://tools/diag_village_v2_road_visible_collision.gd
##
## 為什麼要這支：CPU 幾何對照（diag_village_v2_road_vs_collision.gd）看不到 shader 的 discard。
##   7a892c9 就是這樣漏掉的：ground_p10_pilot.gdshader 在草舌與參道石段挖洞段 discard，
##   但碰撞照烘 → 約 640 m² 有碰撞卻沒有畫出來，玩家浮在草上（中位 0.10、最大 0.24 m）。
## 做法：正交俯視 0.05 m/px、51.2 m 一格，同一機位拍兩張（純色 ID／真材質、真 shader、執行期 overlay 都已套用），
##   每 0.25 m 取樣：
##   A 路面：純色有、真材質是背景 → 沒畫出來；從上往下打玩家碰撞遮罩，最上層若是 Collision/DirtRoadCollision
##     且下面有地形 → 「看不到路面卻踩在路面碰撞上」。必須 0。
##   B 路肩（Roads/RoadShoulder）：有網格但沒畫出來的取樣數。必須 0（路肩有碰撞，沒畫就是隱形台階）。
## 改了道路網格、ground pilot shader、路肩或道路碰撞後跑一次。結束碼＝A＋B 的取樣數。

const LAYER := 1 << 19
const TILE := 51.2
const STEP := 5   # 0.25 m
const ROAD_GROUPS := ["MainStreet", "SecondaryRoads", "Alleys", "FarmPaths"]
var main: Node


func _init() -> void:
	_run.call_deferred()


func _shot() -> Image:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


static func _is_bg(c: Color) -> bool:
	return c.r8 > 240 and c.g8 < 15 and c.b8 > 240


## 回傳每個網格「有網格但沒畫出」的取樣點 [x, z, 網格序號]，以及每個網格的取樣總數
func _coverage(meshes: Array) -> Array:
	var bb := AABB()
	var orig := []
	var flat := []
	for i in meshes.size():
		var mi := meshes[i] as MeshInstance3D
		mi.layers = LAYER
		var b := mi.global_transform * mi.get_aabb()
		bb = b if i == 0 else bb.merge(b)
		orig.append(mi.material_override)
		var f := StandardMaterial3D.new()
		f.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		f.cull_mode = BaseMaterial3D.CULL_DISABLED
		f.albedo_color = Color8(i * 10 + 5, 255, 0)
		flat.append(f)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(1, 0, 1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = TILE
	cam.environment = env
	cam.cull_mask = LAYER
	cam.near = 1.0
	cam.far = 600.0
	root.add_child(cam)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.current = true
	var und := []
	var tot := PackedInt32Array()
	tot.resize(meshes.size())
	var z := bb.position.z
	while z < bb.end.z:
		var x := bb.position.x
		while x < bb.end.x:
			cam.global_position = Vector3(x + TILE * 0.5, 300.0, z + TILE * 0.5)
			for i in meshes.size():
				(meshes[i] as MeshInstance3D).material_override = flat[i]
			var a: Image = await _shot()
			var px := TILE / a.get_width()
			var any := false
			for yy in range(0, a.get_height(), STEP):
				for xx in range(0, a.get_width(), STEP):
					var c := a.get_pixel(xx, yy)
					if c.g8 > 200 and c.b8 < 50:
						any = true
						break
				if any:
					break
			if any:
				for i in meshes.size():
					(meshes[i] as MeshInstance3D).material_override = orig[i]
				var b2: Image = await _shot()
				for yy in range(0, a.get_height(), STEP):
					for xx in range(0, a.get_width(), STEP):
						var c := a.get_pixel(xx, yy)
						if not (c.g8 > 200 and c.b8 < 50):
							continue
						var idx := clampi(roundi((c.r8 - 5) / 10.0), 0, meshes.size() - 1)
						tot[idx] += 1
						if _is_bg(b2.get_pixel(xx, yy)):
							und.append([x + (xx + 0.5) * px, z + (yy + 0.5) * px, idx])
			x += TILE
		z += TILE
	for i in meshes.size():
		(meshes[i] as MeshInstance3D).material_override = orig[i]
		(meshes[i] as MeshInstance3D).layers = 1
	cam.queue_free()
	return [und, tot]


func _run() -> void:
	var sf := root.get_node("/root/StoryFlags")
	sf.set_flag("woke_in_trail", true)
	sf.set_flag("met_reimu", true)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 30:
		await process_frame
	main.load_map("village_v2", "")
	for i in 90:
		await process_frame
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var p: CharacterBody3D = main.player
	var terr := main.map_root.get_node("Collision/TerrainCollision") as CollisionObject3D
	var road := main.map_root.get_node("Collision/DirtRoadCollision") as CollisionObject3D
	var roads: Array = []
	for g in ROAD_GROUPS:
		for mi in main.map_root.get_node("Roads/" + g).find_children("*", "MeshInstance3D", true, false):
			roads.append(mi)
	var res: Array = await _coverage(roads)
	var und: Array = res[0]
	var tot: PackedInt32Array = res[1]
	var sp := p.get_world_3d().direct_space_state
	var per := {}
	var nf := 0
	var hs := PackedFloat32Array()
	for e: Array in und:
		var x := float(e[0])
		var z := float(e[1])
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80, z), Vector3(x, -30, z), p.collision_mask)
		q.exclude = [p.get_rid()]
		var h := sp.intersect_ray(q)
		if h.is_empty() or h.collider != road:
			continue
		var q2 := PhysicsRayQueryParameters3D.create(Vector3(x, 80, z), Vector3(x, -30, z), terr.collision_layer)
		q2.exclude = [p.get_rid(), road.get_rid()]
		var h2 := sp.intersect_ray(q2)
		if h2.is_empty() or h2.collider != terr:
			continue
		var nm := String((roads[int(e[2])] as Node).name)
		per[nm] = int(per.get(nm, 0)) + 1
		nf += 1
		hs.append(h.position.y - h2.position.y)
	var a_tot := 0
	for v in tot:
		a_tot += v
	print("[rvc] A 路面：取樣 %d（≈ %.0f m²），沒畫出 %d（≈ %.1f m²；參道石段挖洞段屬刻意 discard）" % [a_tot, a_tot * 0.0625, und.size(), und.size() * 0.0625])
	print("[rvc]   沒畫出卻踩在 DirtRoadCollision 上：%d 取樣 ≈ %.1f m²%s" % [nf, nf * 0.0625, "" if nf == 0 else "  ← FAIL"])
	if hs.size() > 0:
		hs.sort()
		print("[rvc]   該處碰撞高出地形：p50 %.3f  max %.3f m" % [hs[hs.size() / 2], hs[hs.size() - 1]])
		for k in per:
			print("[rvc]   %-18s %5d 取樣" % [k, per[k]])
	var sh_node: Node = main.map_root.get_node_or_null("Roads/RoadShoulder")
	var nb := 0
	if sh_node == null:
		print("[rvc] B 路肩：找不到 Roads/RoadShoulder  ← FAIL")
		nb = 1
	else:
		var shs: Array = sh_node.find_children("*", "MeshInstance3D", true, false)
		var r2: Array = await _coverage(shs)
		var t2 := 0
		for v in (r2[1] as PackedInt32Array):
			t2 += v
		nb = (r2[0] as Array).size()
		print("[rvc] B 路肩：取樣 %d（≈ %.0f m²），沒畫出 %d%s" % [t2, t2 * 0.0625, nb, "" if nb == 0 else "  ← FAIL"])
	print("[rvc] 結果：%s" % ("PASS" if nf + nb == 0 else "FAIL"))
	quit(nf + nb)
