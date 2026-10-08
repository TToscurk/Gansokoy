extends SceneTree
## P10 R5–R6 MASTER AUDIT 的 BEFORE 證據撮影（只讀、非 headless、Forward+、10:00）。
## 由 shot_village_v2_props.gd 的 TPS 機位重現法延伸（同一換算；不改原工具）：
##   Godot --path . --script res://tools/shot_village_v2_rehab_audit.gd -- <views.json> <outdir/> [toggle=Population]
## views：
##   ["name", px, pz, tx, tz, pitch, dist, lateral]                → TPS：樞軸＝地表＋1.6 m，臂長 dist，橫移 lateral
##   ["name", "free", cx, cy, cz, tx, ty, tz, fov]                   → 自由機位（高視角）
## toggle＝同機位 _a（顯示）／_b（隱藏）；預設 Population（NPC ON／OFF）。toggle=none → 只拍一張。
## toggle 節點若有 `enabled` 屬性（P10 R5a／R6a 材質覆寫 pilot）→ _a＝enabled、_b＝disabled（＝BEFORE）。
## 每張另寫 stats：全畫面 sRGB 平均亮度、平均飽和度（HSV S）、亮度 < 0.2 的像素比例。
func _init() -> void:
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
	var views: Array = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var outdir: String = a[1]
	var toggle := "Population"
	for s: String in a:
		if s.begins_with("toggle="):
			toggle = s.trim_prefix("toggle=")
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.1
	cam.far = 1200.0
	root.add_child(cam)
	cam.make_current()
	var sp := v.get_world_3d().direct_space_state
	var g: Node3D = null if toggle == "none" else v.get_node_or_null(toggle) as Node3D
	for i in 30:
		await process_frame
	var stats := {}
	for vw in views:
		var nm := str(vw[0])
		if typeof(vw[1]) == TYPE_STRING and str(vw[1]) == "free":
			var cp := Vector3(float(vw[2]), float(vw[3]), float(vw[4]))
			var tp := Vector3(float(vw[5]), float(vw[6]), float(vw[7]))
			cam.fov = float(vw[8])
			cam.global_transform = Transform3D(Basis(), cp).looking_at(tp, Vector3.UP)
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
				if String((hit.collider as Node).name).begins_with("TerrainCollision"):
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
		var states := [true] if g == null else [true, false]
		for vis in states:
			if g:
				# 有 enabled 屬性的 pilot overlay（材質覆寫類）→ 切 enabled；其他 → 切 visible
				if "enabled" in g:
					g.set("enabled", vis)
				else:
					g.visible = vis
			for i in 14:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			var fn := nm + ("" if g == null else ("_a" if vis else "_b")) + ".png"
			img.save_png(outdir + fn)
			stats[fn] = _stats(img)
		print("SHOT ", nm, " cam ", cam.global_position)
	if g:
		if "enabled" in g:
			g.set("enabled", true)
		else:
			g.visible = true
	var f2 := FileAccess.open(outdir + "_stats.json", FileAccess.WRITE)
	f2.store_string(JSON.stringify(stats, "\t"))
	f2.close()
	quit()

func _stats(img: Image) -> Dictionary:
	var im := img.duplicate() as Image
	im.resize(320, 180, Image.INTERPOLATE_BILINEAR)
	var ls := 0.0
	var ss := 0.0
	var dark := 0
	var n := 0
	for y in 180:
		for x in 320:
			var c := im.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			ls += l
			ss += c.s
			if l < 0.2:
				dark += 1
			n += 1
	return {"mean_luma_srgb": snappedf(ls / n, 0.001), "mean_sat": snappedf(ss / n, 0.001), "frac_luma_lt_0.2": snappedf(float(dark) / n, 0.001)}
