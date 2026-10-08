extends SceneTree
## P10 R4 Human-Use Pilot 審圖撮影（ART_REVIEW 用・再現可能）：非 headless、F5 と同じ village_v2 場景・天象、時刻 10:00、Forward+。
##   godot --path godot --script res://tools/shot_p10_human_use.gd -- <views.json> <outdir/>
##   views＝[name, px, pz, tx, tz, pitch, dist, lateral]（shot_village_v2_props.gd と同じ TPS 相機：立ち位置の地表＋1.6 m の樞軸）。
##   同じ視點で 3 枚：<name>_before（HumanUseP10 非表示・NPC あり）／<name>_after（HumanUseP10・NPC あり＝実際の遊戲）／
##   <name>_npcoff（HumanUseP10 あり・Population 全部非表示）。
const HU := preload("res://tools/village_v2_human_use_lib.gd")


func _init() -> void:
	var a := OS.get_cmdline_user_args()
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
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.1
	cam.far = 900.0
	root.add_child(cam)
	cam.make_current()
	var sp := v.get_world_3d().direct_space_state
	var hu := v.get_node(HU.NODE_NAME) as Node3D
	var pop := v.get_node("Population") as Node3D
	for i in 20:
		await process_frame
	for vw in views:
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
		var dist := float(vw[6])
		var piv := Vector3(pp.x, gy + 1.6, pp.y) + Vector3(side.x, 0.0, side.y) * float(vw[7]) * 0.5
		var look := Vector3(f.x * cos(pitch), sin(pitch), f.y * cos(pitch))
		var cp := piv - look * dist + Vector3(side.x, 0.0, side.y) * float(vw[7]) * 0.5
		cam.global_transform = Transform3D(Basis(), cp).looking_at(cp + look, Vector3.UP)
		for st in [["before", false, true], ["after", true, true], ["npcoff", true, false]]:
			hu.visible = st[1]
			pop.visible = st[2]
			for i in 12:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(outdir + String(vw[0]) + "_" + String(st[0]) + ".png")
		print("SHOT ", vw[0], " ground ", snappedf(gy, 0.01), " cam ", cp.snapped(Vector3.ONE * 0.01))
	hu.visible = true
	pop.visible = true
	quit()
