extends SceneTree
## P10 R5–R6 MASTER AUDIT：建物材質「灰暗」根因量測（只讀、非 headless、Forward+、10:00；場景不存檔）。
##   Godot --path . --script res://tools/probe_village_v2_rehab_albedo.gd -- <outdir/>
## 在 village_v2 的開闊地（記憶體中）立 2×2 m 色卡：V2_Plaster／V2_Wood／V2_Kawara／V2_Stone／V2_MachiyaKit（原樣），
## 同材質但 albedo_color＝白（去掉 albedo_k 0.42）、以及中性灰參考（線性 0.18／0.50）。
## 色卡一組朝太陽水平方向（受光面）、一組背向（陰面）；拍一張、讀每張卡中心 40×40 px 的 sRGB 平均。
const MATS := ["res://assets/village_v2/_matlib/V2_Plaster.tres", "res://assets/village_v2/_matlib/V2_Wood.tres",
	"res://assets/village_v2/_matlib/V2_Kawara.tres", "res://assets/village_v2/_matlib/V2_Stone.tres",
	"res://assets/village_v2/machiya_kit/V2_MachiyaKit.tres"]
const SPOT := Vector2(424.0, 96.0)

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
	var to_sun := sun.global_transform.basis.z   # 光線沿 -z 射出 → +z 指向太陽
	var hs := Vector2(to_sun.x, to_sun.z).normalized()
	var sp := v.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(SPOT.x, 80, SPOT.y), Vector3(SPOT.x, -20, SPOT.y))
	var gy: float = sp.intersect_ray(q)["position"].y
	var cards := []
	for m in MATS:
		cards.append([m.get_file().get_basename(), load(m) as Material, false])
		var w := (load(m) as StandardMaterial3D).duplicate() as StandardMaterial3D
		w.albedo_color = Color(1, 1, 1)
		cards.append([m.get_file().get_basename() + "_k1", w, false])
	for g in [0.18, 0.5]:
		var r := StandardMaterial3D.new()
		var s := Color(g, g, g).linear_to_srgb()
		r.albedo_color = s
		r.roughness = 1.0
		cards.append(["ref_lin%.2f" % g, r, false])
	# 一列：卡寬 2 m、間距 0.6；面向太陽水平方向
	var side := Vector2(-hs.y, hs.x)
	var n := cards.size()
	var holder := Node3D.new()
	v.add_child(holder)
	var centers := []
	for face in [1.0, -1.0]:
		for i in n:
			var off := (i - (n - 1) * 0.5) * 2.6
			var c2: Vector2 = SPOT + side * off + hs * (0.0 if face > 0 else -6.0)
			var mi := MeshInstance3D.new()
			var pm := QuadMesh.new()
			pm.size = Vector2(2.0, 2.0)
			mi.mesh = pm
			mi.material_override = cards[i][1]
			holder.add_child(mi)
			var normal := Vector3(hs.x * face, 0, hs.y * face)
			mi.global_position = Vector3(c2.x, gy + 1.4, c2.y)
			mi.look_at(mi.global_position - normal, Vector3.UP)
			centers.append([cards[i][0] + ("_sun" if face > 0 else "_shade"), mi.global_position, normal])
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.make_current()
	var res := {"sun_energy": sun.light_energy, "sun_dir_to_sun": [to_sun.x, to_sun.y, to_sun.z], "spot": [SPOT.x, gy, SPOT.y], "cards": {}}
	for face in [1.0, -1.0]:
		var back: Vector3 = Vector3.ZERO if face > 0 else Vector3(-hs.x, 0, -hs.y) * 6.0
		var cp: Vector3 = Vector3(SPOT.x, gy + 1.6, SPOT.y) + Vector3(hs.x, 0, hs.y) * (22.0 * face) + back
		var tgt: Vector3 = Vector3(SPOT.x, gy + 1.4, SPOT.y) + back
		cam.global_transform = Transform3D(Basis(), cp).looking_at(tgt, Vector3.UP)
		for i in 16:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(outdir + ("albedo_cards_sun.png" if face > 0 else "albedo_cards_shade.png"))
		for c in centers:
			if (face > 0) != String(c[0]).ends_with("_sun"):
				continue
			var sp2 := cam.unproject_position(c[1])
			var acc := Color(0, 0, 0)
			var k := 0
			for yy in range(-20, 20):
				for xx in range(-20, 20):
					var px := int(sp2.x) + xx
					var py := int(sp2.y) + yy
					if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
						acc += img.get_pixel(px, py)
						k += 1
			acc /= maxf(k, 1)
			res["cards"][c[0]] = {"srgb": [snappedf(acc.r, 0.001), snappedf(acc.g, 0.001), snappedf(acc.b, 0.001)],
				"luma": snappedf(0.2126 * acc.r + 0.7152 * acc.g + 0.0722 * acc.b, 0.001), "sat": snappedf(acc.s, 0.001), "screen": [int(sp2.x), int(sp2.y)]}
	var f := FileAccess.open(outdir + "albedo_cards.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "\t"))
	f.close()
	print("[ALB] ", JSON.stringify(res["cards"]))
	quit()
