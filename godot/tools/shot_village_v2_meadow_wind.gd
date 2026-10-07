extends SceneTree
## P9 R5-3 wind review 撮影：同じ TPS 機位で MeadowP9 の風を連続撮影（非 headless、Forward+、10:00）。
##   Godot --path . --script res://tools/shot_village_v2_meadow_wind.gd -- <views.json> <outdir/> names=a,b strengths=0.6,1.0 frames=40
##   出力：<outdir>/<name>_s<strength>_<NNN>.png と frames.json（各フレームの實時刻 ms）——GIF 化は外部（時刻どおりの間隔）。
## 資產・場景・shader の既定値は変えない（material の shader parameter を實行中のみ一時的に設定）。
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var views: Array = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var outdir: String = a[1]
	var names: PackedStringArray = []
	var strengths: Array = [1.0]
	var frames := 40
	for s: String in a:
		if s.begins_with("names="):
			names = s.trim_prefix("names=").split(",")
		elif s.begins_with("strengths="):
			strengths = Array(s.trim_prefix("strengths=").split(",")).map(func(x: String) -> float: return float(x))
		elif s.begins_with("frames="):
			frames = int(s.trim_prefix("frames="))
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
	var mats := {}
	for g in v.get_node("Vegetation/MeadowP9").find_children("*", "GeometryInstance3D", true, false):
		var m := (g as GeometryInstance3D).material_override as ShaderMaterial
		if m != null:
			mats[m.get_instance_id()] = m
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.1
	cam.far = 900.0
	root.add_child(cam)
	cam.make_current()
	var sp := v.get_world_3d().direct_space_state
	for i in 20:
		await process_frame
	var log := {}
	for vw in views:
		if not names.is_empty() and not (String(vw[0]) in names):
			continue
		var pp := Vector2(float(vw[1]), float(vw[2]))
		var tt := Vector2(float(vw[3]), float(vw[4]))
		var q := PhysicsRayQueryParameters3D.create(Vector3(pp.x, 60.0, pp.y), Vector3(pp.x, -20.0, pp.y))
		var gy := 0.0
		var ex: Array[RID] = []
		for k in 12:
			q.exclude = ex
			var hit := sp.intersect_ray(q)
			if hit.is_empty():
				break
			if String((hit.collider as Node).name).begins_with("TerrainCollision"):
				gy = hit.position.y
				break
			ex.append(hit.rid)
		var f := (tt - pp).normalized()
		var side := Vector2(-f.y, f.x)
		var pitch := float(vw[5])
		var piv := Vector3(pp.x, gy + 1.6, pp.y) + Vector3(side.x, 0.0, side.y) * float(vw[7]) * 0.5
		var look := Vector3(f.x * cos(pitch), sin(pitch), f.y * cos(pitch))
		var cp := piv - look * float(vw[6]) + Vector3(side.x, 0.0, side.y) * float(vw[7]) * 0.5
		cam.global_transform = Transform3D(Basis(), cp).looking_at(cp + look, Vector3.UP)
		for st: float in strengths:
			for m: ShaderMaterial in mats.values():
				m.set_shader_parameter("wind_strength", st)
			for i in 10:
				await process_frame
			var key := "%s_s%.1f" % [vw[0], st]
			var ts: Array = []
			for i in frames:
				await RenderingServer.frame_post_draw
				ts.append(Time.get_ticks_msec())
				root.get_texture().get_image().save_png(outdir + "%s_%03d.png" % [key, i])
				await process_frame
			log[key] = ts
			print("WIND ", key, " ", frames, " frames ", ts[-1] - ts[0], " ms")
	var fl := FileAccess.open(outdir + "frames.json", FileAccess.WRITE)
	fl.store_string(JSON.stringify(log))
	fl.close()
	quit()
