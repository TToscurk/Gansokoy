extends SceneTree
## P10 R6a 材質亮度基準 Pilot：色卡候選量測（只讀、非 headless、Forward+、10:00；場景不存檔）。
##   Godot --path . --script res://tools/probe_village_v2_rehab_albedo_cal.gd -- <outdir/>
## 一面朝太陽水平方位的「色卡牆」：列＝材質、欄＝albedo_k 候選；另加一列「瓦（屋面 24° 朝陽）」與 18 %／50 % 中性灰參考。
## 讀每張卡中心 30×30 px 的 sRGB 平均 → albedo_cal.json。
const MATS := [["V2_Plaster", "res://assets/village_v2/_matlib/V2_Plaster.tres"], ["V2_Wood", "res://assets/village_v2/_matlib/V2_Wood.tres"],
	["V2_Kawara", "res://assets/village_v2/_matlib/V2_Kawara.tres"], ["V2_KitStoneTri", "res://assets/village_v2/machiya_kit/V2_KitStoneTri.tres"],
	["V2_MachiyaKit", "res://assets/village_v2/machiya_kit/V2_MachiyaKit.tres"], ["V2_Kawara_roof24", "res://assets/village_v2/_matlib/V2_Kawara.tres"]]
const KS := [0.42, 0.55, 0.65, 0.75, 0.85, 1.0]
const SPOT := Vector2(424.0, 96.0)
const CARD := 1.3
const GAP := 0.25

func _init() -> void:
	var outdir: String = OS.get_cmdline_user_args()[0]
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for nm in ["Debug", "Portals", "QuestAnchors", "Population"]:
		if v.has_node(nm):
			v.get_node(nm).visible = false
	await process_frame
	for c in root.get_children():
		if c.has_method("set_hour"):
			c.set_hour(10.0)
	for i in 20:
		await process_frame
	var sun: DirectionalLight3D = null
	for d in v.find_children("*", "DirectionalLight3D", true, false):
		if (d as DirectionalLight3D).visible:
			sun = d
	var to_sun := sun.global_transform.basis.z
	var hs := Vector2(to_sun.x, to_sun.z).normalized()
	var side := Vector2(-hs.y, hs.x)
	var sp := v.get_world_3d().direct_space_state
	var gy: float = sp.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(SPOT.x, 80, SPOT.y), Vector3(SPOT.x, -20, SPOT.y)))["position"].y
	var holder := Node3D.new()
	v.add_child(holder)
	var cards := []
	var ncol := KS.size() + 1
	for r in MATS.size():
		for c in ncol:
			var mat: Material
			var label := ""
			if c < KS.size():
				var m := (load(MATS[r][1]) as StandardMaterial3D).duplicate() as StandardMaterial3D
				var k: float = KS[c]
				m.albedo_color = Color(k, k, k, 1.0)
				mat = m
				label = "%s@%.2f" % [MATS[r][0], k]
			else:
				if r > 1:
					continue
				var g := 0.18 if r == 0 else 0.5
				var rm := StandardMaterial3D.new()
				rm.albedo_color = Color(g, g, g).linear_to_srgb()
				rm.roughness = 1.0
				mat = rm
				label = "ref_lin%.2f" % g
			var mi := MeshInstance3D.new()
			var pm := QuadMesh.new()
			pm.size = Vector2(CARD, CARD)
			mi.mesh = pm
			mi.material_override = mat
			holder.add_child(mi)
			var off := (c - (ncol - 1) * 0.5) * (CARD + GAP)
			var c2: Vector2 = SPOT + side * off
			var y := gy + 1.2 + (MATS.size() - 1 - r) * (CARD + GAP)
			mi.global_position = Vector3(c2.x, y, c2.y)
			var normal := Vector3(hs.x, 0.0, hs.y)
			if String(MATS[r][0]).ends_with("roof24"):
				# 屋面 24°：法線從水平往上 66°（朝陽坡）
				normal = (Vector3(hs.x, 0.0, hs.y) * cos(deg_to_rad(66.0)) + Vector3.UP * sin(deg_to_rad(66.0))).normalized()
			mi.look_at(mi.global_position - normal, Vector3.UP if absf(normal.y) < 0.95 else Vector3(hs.x, 0, hs.y))
			cards.append([label, mi.global_position])
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.make_current()
	var center := Vector3(SPOT.x, gy + 1.2 + (MATS.size() - 1) * (CARD + GAP) * 0.5, SPOT.y)
	var cp := center + Vector3(hs.x, 0.0, hs.y) * 26.0 + Vector3(0, 1.0, 0)
	cam.global_transform = Transform3D(Basis(), cp).looking_at(center, Vector3.UP)
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(outdir + "albedo_cal_cards.png")
	var res := {"spot": [SPOT.x, gy, SPOT.y], "ks": KS, "cards": {}}
	for c in cards:
		var s2 := cam.unproject_position(c[1])
		var acc := Color(0, 0, 0)
		var k := 0
		for yy in range(-15, 15):
			for xx in range(-15, 15):
				var px := int(s2.x) + xx
				var py := int(s2.y) + yy
				if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
					acc += img.get_pixel(px, py)
					k += 1
		acc /= maxf(k, 1)
		res["cards"][c[0]] = {"luma": snappedf(0.2126 * acc.r + 0.7152 * acc.g + 0.0722 * acc.b, 0.001), "sat": snappedf(acc.s, 0.001),
			"srgb": [snappedf(acc.r, 0.001), snappedf(acc.g, 0.001), snappedf(acc.b, 0.001)], "screen": [int(s2.x), int(s2.y)]}
	var f := FileAccess.open(outdir + "albedo_cal.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "\t"))
	f.close()
	print("[ALBCAL] ", JSON.stringify(res["cards"]))
	quit()
