extends SceneTree
## P10 R6b.1 Shrine Approach Redesign：代表区間（s 38–68 m）の石段 Kit Pilot を r8 と同機位で比較撮影（只讀、非 headless、Forward+、10:00）。
##   Godot --path . --script res://tools/shot_village_v2_sando_r6b1.gd -- <views.json> <outdir/>
## 各機位：<name>_r8.png（現行 ShrineApproachP10）／<name>_p1.png（区間内だけ R6b.1 Kit、区間外は r8 のまま）。
## 場景・overlay は書き換えない（記憶體内で r8 の StoneSteps を区間除外版に差し替え＋Pilot mesh を足すだけ）。
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")
const KIT := preload("res://tools/village_v2_sando_kit_r6b1_lib.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		if v.has_node(nm):
			v.get_node(nm).visible = false
	for n in v.get_node("Districts").find_children("*ParcelLines*", "", true, false):
		n.visible = false
	await process_frame
	for c in root.get_children():
		if c.has_method("set_hour"):
			c.set_hour(10.0)
	for i in 4:
		await physics_frame
	var sa := v.get_node(SA.NODE_NAME)
	var ramp := sa.get_node("RampCollision/Ramp") as CollisionShape3D
	var cl := SA.centerline()
	ramp.disabled = true
	await physics_frame
	await physics_frame
	var H := SA.ramp_profile(v, cl)
	ramp.disabled = false
	await physics_frame
	var st := SA.steps(cl, H)
	var sp := v.get_world_3d().direct_space_state
	var terr := v.get_node("Collision/TerrainCollision")
	var pilot := KIT.build_pilot(cl, H, st, sp, terr)
	var r8 := sa.get_node("StoneSteps") as MeshInstance3D
	var r8_mesh := r8.mesh
	var r8_cut := KIT.r8_without_range(r8_mesh as ArrayMesh, cl)
	print("[R6B1] pilot counts %s、r8 三角形 %d → 区間外 %d、pilot 三角形 %d" % [JSON.stringify(pilot.get_meta("counts")), (r8_mesh as ArrayMesh).surface_get_array_index_len(0) / 3 if (r8_mesh as ArrayMesh).surface_get_array_index_len(0) > 0 else (r8_mesh as ArrayMesh).surface_get_array_len(0) / 3, r8_cut.surface_get_array_index_len(0) / 3, (pilot.mesh as ArrayMesh).surface_get_array_len(0) / 3])
	pilot.visible = false
	sa.add_child(pilot)
	var views: Array = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var outdir: String = a[1]
	DirAccess.make_dir_recursive_absolute(outdir)
	var cam := Camera3D.new()
	cam.near = 0.1
	cam.far = 1200.0
	root.add_child(cam)
	cam.make_current()
	for i in 30:
		await process_frame
	for vw in views:
		var nm := str(vw[0])
		if typeof(vw[1]) == TYPE_STRING and str(vw[1]) == "free":
			cam.fov = float(vw[8])
			cam.global_transform = Transform3D(Basis(), Vector3(float(vw[2]), float(vw[3]), float(vw[4]))).looking_at(Vector3(float(vw[5]), float(vw[6]), float(vw[7])), Vector3.UP)
		else:
			cam.fov = 70.0
			var pp := Vector2(float(vw[1]), float(vw[2]))
			var tt := Vector2(float(vw[3]), float(vw[4]))
			var q := PhysicsRayQueryParameters3D.create(Vector3(pp.x, 120.0, pp.y), Vector3(pp.x, -40.0, pp.y))
			var gy := 0.0
			var ex: Array[RID] = []
			for k in 16:
				q.exclude = ex
				var hit := sp.intersect_ray(q)
				if hit.is_empty():
					break
				var cn := String((hit.collider as Node).name)
				if cn.begins_with("TerrainCollision") or cn == "RampCollision":
					gy = hit.position.y
					break
				ex.append(hit.rid)
			var f := (tt - pp).normalized()
			var side := Vector2(-f.y, f.x)
			var pitch := float(vw[5])
			var dist := float(vw[6])
			var piv := Vector3(pp.x, gy + 1.6, pp.y) + Vector3(side.x, 0.0, side.y) * float(vw[7]) * 0.5
			var look := Vector3(f.x * cos(pitch), sin(pitch), f.y * cos(pitch))
			var cp2 := piv - look * dist + Vector3(side.x, 0.0, side.y) * float(vw[7]) * 0.5
			cam.global_transform = Transform3D(Basis(), cp2).looking_at(cp2 + look, Vector3.UP)
		for variant in ["r8", "p1"]:
			if variant == "r8":
				r8.mesh = r8_mesh
				pilot.visible = false
			else:
				r8.mesh = r8_cut
				pilot.visible = true
			for i in 14:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(outdir + "%s_%s.png" % [nm, variant])
		print("SHOT ", nm)
	r8.mesh = r8_mesh
	quit(0)
