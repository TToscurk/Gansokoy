extends SceneTree
## P10 R1b Market West Rework：Kit 整理図の撮影（ART_REVIEW 用・再現可能；非 headless、Forward+）。
##   Godot --path . --script res://tools/shot_village_v2_market_west_kit.gd -- <outdir/>
##   ① 北側の店列・② 南側の店列：実際の場景（10:00）を正投影・やや俯瞰で（向かいの店列は撮影中だけ隠す）
##   ③–⑥ 構件：村の外の独立した撮影台（地面・壁・太陽・空）に並べる——③ 日除け幕・軒提灯 ④ 木戸・吊り提灯 ⑤ 下屋・反物・縁台・吊るし物
##   ⑥ 重用した既存 Kit（前列＝陳列、後列＝後場・補充・生活痕跡）
const MW := preload("res://tools/village_v2_market_west_lib.gd")

var cam: Camera3D


func _mod(parent: Node3D, id: String, pos: Vector3, yaw := 0.0, sc := Vector3.ONE) -> Node3D:
	var n := Node3D.new()
	n.transform = Transform3D(Basis(Vector3.UP, yaw).scaled_local(sc), pos)
	var mi := MeshInstance3D.new()
	mi.mesh = load(MW.mesh_dir(id) + id + ".res")
	n.add_child(mi)
	parent.add_child(n)
	return n


func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.95
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)


func _shot(path: String, frames := 12) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _look(pos: Vector3, at: Vector3) -> void:
	cam.global_transform = Transform3D(Basis(), pos).looking_at(at, Vector3.UP)


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var outdir: String = a[0]
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		if v.has_node(nm):
			v.get_node(nm).visible = false
	await process_frame
	for c in root.get_children():
		if c.has_method("set_hour"):
			c.set_hour(10.0)
	cam = Camera3D.new()
	cam.far = 900.0
	root.add_child(cam)
	cam.make_current()
	for i in 20:
		await process_frame
	var sp := v.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(216.0, 60, MW.Z_C), Vector3(216.0, -20, MW.Z_C))
	var hit := sp.intersect_ray(q)
	var g: float = hit.position.y if not hit.is_empty() else 1.2
	var bld := v.get_node("Props/MarketWestP10/Buildings")
	# ① 北側の店列（南の店列を隠す；正投影・俯瞰）
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 15.0
	for b in bld.get_children():
		(b as Node3D).visible = String(b.name).begins_with("MW_N")
	_look(Vector3(216.0, g + 9.2, -38.5), Vector3(216.0, g + 0.6, -47.4))
	await _shot(outdir + "row_north.png")
	# ② 南側の店列（北の店列を隠す）
	for b in bld.get_children():
		(b as Node3D).visible = String(b.name).begins_with("MW_S")
	_look(Vector3(214.6, g + 9.2, -50.6), Vector3(214.6, g + 0.6, -41.8))
	await _shot(outdir + "row_south.png")
	for b in bld.get_children():
		(b as Node3D).visible = true
	# ③–⑥ 独立した撮影台
	v.queue_free()
	await process_frame
	var st := Node3D.new()
	root.add_child(st)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.45, 0.62, 0.85)
	sm.sky_horizon_color = Color(0.82, 0.86, 0.9)
	sm.ground_horizon_color = Color(0.7, 0.68, 0.62)
	sm.ground_bottom_color = Color(0.4, 0.38, 0.34)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	st.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 28.0, 0.0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	st.add_child(sun)
	_box(st, Vector3(80.0, 0.2, 60.0), Vector3(0, -0.1, 0), Color(0.6, 0.55, 0.46))
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 46.0
	var hold := Node3D.new()
	st.add_child(hold)
	var plaster := Color(0.84, 0.8, 0.72)
	# ③ 日除け幕 4 色（壁＝店の正面、庇の下 y 2.5）＋軒提灯 赤・白
	_box(hold, Vector3(16.0, 3.4, 0.2), Vector3(0, 1.7, -0.1), plaster)
	var xs := [-5.25, -1.75, 1.75, 5.25]
	var cols := ["ai", "kinari", "beni", "kaki"]
	for i in 4:
		_mod(hold, "ms_maku_" + String(cols[i]), Vector3(xs[i], 0.0, 0.0))
	_mod(hold, "ms_noki_chochin_aka", Vector3(-7.4, 2.4, 0.0))
	_mod(hold, "ms_noki_chochin_shiro", Vector3(7.4, 2.4, 0.0))
	_look(Vector3(0.0, 2.3, 12.0), Vector3(0.0, 1.45, 0.0))
	await _shot(outdir + "kit_maku.png")
	for c in hold.get_children():
		c.queue_free()
	await process_frame
	# ④ 木戸 3（2.6／3.7「市 この奥」／5.0）＋吊り提灯（柱 2 本の間）
	_mod(hold, "ms_kido_26", Vector3(-2.6, 0.0, 0.0))
	_mod(hold, "ms_kido_37", Vector3(2.6, 0.0, 0.0))
	_mod(hold, "ms_kido_50", Vector3(8.7, 0.0, 0.0))
	for x: float in [-10.2, -5.8]:
		_box(hold, Vector3(0.16, 3.6, 0.16), Vector3(x, 1.8, 0.0), Color(0.42, 0.36, 0.3))
	_mod(hold, "ms_tsuna_chochin", Vector3(-8.0, 3.4, 0.0))
	cam.fov = 50.0
	_look(Vector3(0.4, 2.4, 15.5), Vector3(0.4, 1.9, 0.0))
	await _shot(outdir + "kit_kido.png")
	for c in hold.get_children():
		c.queue_free()
	await process_frame
	cam.fov = 46.0
	# ⑤ 下屋 2・反物の台・反物の掛け・緋毛氈の縁台・軒の吊るし物 3
	_box(hold, Vector3(16.0, 3.6, 0.2), Vector3(0, 1.8, -0.1), plaster)
	_mod(hold, "ms_geya_dango", Vector3(-5.6, 0.0, 0.0))
	_mod(hold, "ms_geya_meshi", Vector3(-2.0, 0.0, 0.0))
	_mod(hold, "ms_tanmono_dai", Vector3(1.6, 0.0, 0.55))
	_mod(hold, "ms_endai_mousen", Vector3(1.6, 0.0, 2.3))
	_mod(hold, "ms_nuno_kake", Vector3(4.2, 0.0, 0.35))
	_mod(hold, "ms_tsuri_kaki", Vector3(6.6, 2.9, 0.0))
	_mod(hold, "ms_tsuri_waraji", Vector3(1.6, 2.9, 0.0))
	_mod(hold, "ms_tsuri_oke", Vector3(4.2, 3.05, 0.0))
	_look(Vector3(0.3, 2.3, 11.5), Vector3(0.3, 1.4, 0.0))
	await _shot(outdir + "kit_geya.png")
	for c in hold.get_children():
		c.queue_free()
	await process_frame
	# ⑥ 重用（承認済み Kit）：前列＝陳列、後列＝後場・補充・生活痕跡
	var front := ["st_hiradai_zakka", "st_hinadan_seto", "st_hiradai_kashi", "st_hiradai_yasai", "st_kome_tsumi", "gd_taruzumi", "kr_fukuro", "wk_tawara3",
		"st_kanban_sake", "st_andon_yasumi", "mk_nobori_cha"]
	var back := ["st_ido", "sk_woodpile", "kr_hoshidana", "kr_hakozumi", "mk_tsumini", "sk_tensui", "tk_okeyama", "kr_okeyama", "sk_teoke", "kr_houki"]
	for row: Array in [[front, 1.6], [back, -2.0]]:
		var ids: Array = row[0]
		var tot := 0.0
		for id: String in ids:
			tot += float(MW.box(id)[0]) * 2.0 + 0.35
		var x := -tot * 0.5
		for id: String in ids:
			var b: Array = MW.box(id)
			x += float(b[0]) + 0.175
			_mod(hold, id, Vector3(x - float(b[4]), 0.0, float(row[1]) - float(b[3])))
			x += float(b[0]) + 0.175
	cam.fov = 52.0
	_look(Vector3(0.0, 5.2, 12.5), Vector3(0.0, 0.6, -0.4))
	await _shot(outdir + "kit_reuse.png")
	quit(0)
