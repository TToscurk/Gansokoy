extends SceneTree
## P10 R4b Human-Use Expansion 審圖撮影（ART_REVIEW 用・再現可能）：非 headless、F5 と同じ village_v2 場景・天象、時刻 10:00、Forward+。
##   godot --path godot --script res://tools/shot_p10_human_use_exp.gd -- --pick=<views.json>            視點を選んで書く（撮らない）
##   godot --path godot --script res://tools/shot_p10_human_use_exp.gd -- <views.json> <outdir/>          撮る
##   視點の選び方（--pick）：各群について、玩家（樞軸＝地表＋1.6 m、相機は 3.6 m 後ろ・横 0.5 m、shot_p10_human_use.gd と同じ TPS）を
##     群の中心から near＝相機 5–10 m／mid＝相機 10–15 m に置き、15° ごとに回して、①玩家の足元が地形（建物・橋の上でない）②相機が樞軸から見通せる
##     ③相機から群の件へ ray が通る割合 が最大、農道・路地の上（玩家が普段歩く所）＋0.15、相機の脇 3 m に壁 −0.12／本、依附先（橋・水）が画面に入る＋0.1。
##     high＝俯瞰 -0.62 rad・10 m。
##   同じ視點で 3 枚：<name>_before（HumanUseExpansionP10 非表示・NPC あり）／<name>_after（擴張あり・NPC あり＝実際の遊戲）／
##     <name>_npcoff（擴張あり・Population 全部非表示）。R4 の HumanUseP10（封存）は常に表示。
const HX := preload("res://tools/village_v2_human_use_exp_lib.gd")
const HU := preload("res://tools/village_v2_human_use_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const CAM_BACK := 3.6
const LAT := 1.0


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
	for i in 4:
		await physics_frame
	var sp := v.get_world_3d().direct_space_state
	var hx := v.get_node(HX.NODE_NAME) as Node3D
	if a.size() > 0 and String(a[0]).begins_with("--pick="):
		_pick(v, sp, hx, String(a[0]).trim_prefix("--pick="))
		quit()
		return
	var views: Array = JSON.parse_string(FileAccess.get_file_as_string(a[0]))
	var outdir: String = a[1]
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.1
	cam.far = 900.0
	root.add_child(cam)
	cam.make_current()
	var pop := v.get_node("Population") as Node3D
	for i in 20:
		await process_frame
	for vw in views:
		var pp := Vector2(float(vw[1]), float(vw[2]))
		var tt := Vector2(float(vw[3]), float(vw[4]))
		var cp := _cam(sp, pp, tt, float(vw[5]), float(vw[6]), float(vw[7]))
		var look := _look(pp, tt, float(vw[5]))
		cam.global_transform = Transform3D(Basis(), cp).looking_at(cp + look, Vector3.UP)
		for st in [["before", false, true], ["after", true, true], ["npcoff", true, false]]:
			hx.visible = st[1]
			pop.visible = st[2]
			for i in 12:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(outdir + String(vw[0]) + "_" + String(st[0]) + ".png")
		print("SHOT ", vw[0], " cam ", cp.snapped(Vector3.ONE * 0.01), " → 群まで %.1f m" % Vector2(cp.x, cp.z).distance_to(Vector2(float(vw[8]) if vw.size() > 8 else tt.x, float(vw[9]) if vw.size() > 9 else tt.y)))
	hx.visible = true
	pop.visible = true
	quit()


func _ground(sp: PhysicsDirectSpaceState3D, p: Vector2) -> Array:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 60.0, p.y), Vector3(p.x, -20.0, p.y))
	var hit := sp.intersect_ray(q)
	if hit.is_empty():
		return [false, 0.0, ""]
	var nm := String((hit.collider as Node).name) if hit.collider is Node else ""
	return [nm.begins_with("TerrainCollision"), float(hit.position.y), nm]


func _look(pp: Vector2, tt: Vector2, pitch: float) -> Vector3:
	var f := (tt - pp).normalized()
	return Vector3(f.x * cos(pitch), sin(pitch), f.y * cos(pitch))


func _cam(sp: PhysicsDirectSpaceState3D, pp: Vector2, tt: Vector2, pitch: float, dist: float, lat: float) -> Vector3:
	var g := _ground(sp, pp)
	var f := (tt - pp).normalized()
	var side := Vector2(-f.y, f.x)
	var piv := Vector3(pp.x, float(g[1]) + 1.6, pp.y) + Vector3(side.x, 0.0, side.y) * lat * 0.5
	return piv - _look(pp, tt, pitch) * dist + Vector3(side.x, 0.0, side.y) * lat * 0.5


func _pick(v: Node3D, sp: PhysicsDirectSpaceState3D, hx: Node3D, out_path: String) -> void:
	var C := HU.context(v, PackedVector2Array())
	var R: RLib.TriSampler = C["R"]
	var WS: RLib.TriSampler = C["WS"]
	var views: Array = []
	for zone in hx.get_children():
		if not String(zone.name).begins_with("Zone"):
			continue
		for cl in zone.get_children():
			var pts: Array[Vector3] = []
			for n in cl.find_children("*", "Node3D", true, false):
				if n.has_meta("hu_id"):
					var mi := (n as Node3D).get_node("LOD0") as MeshInstance3D
					var ab := mi.global_transform * mi.get_aabb()
					pts.append(ab.get_center() + Vector3(0, ab.size.y * 0.2, 0))
			var cen := Vector3.ZERO
			for q in pts:
				cen += q
			cen /= maxf(1, pts.size())
			var c2 := Vector2(cen.x, cen.z)
			var best_dir := Vector2.ZERO
			for band in [["near", 3.6, 5.6], ["mid", 7.6, 10.6]]:
				var best := -1.0
				var bv: Array = []
				for k in 24:
					var ang := TAU * k / 24.0
					var d := Vector2(cos(ang), sin(ang))
					for dp: float in [float(band[1]), (float(band[1]) + float(band[2])) * 0.5, float(band[2])]:
						var pp: Vector2 = c2 + d * dp
						var g := _ground(sp, pp)
						if not g[0] or not is_nan(WS.h(pp.x, pp.y)):
							continue
						var cp := _cam(sp, pp, c2, -0.1, CAM_BACK, LAT)
						var piv := Vector3(pp.x, float(g[1]) + 1.6, pp.y)
						var arm := sp.intersect_ray(PhysicsRayQueryParameters3D.create(piv, cp))
						if not arm.is_empty():
							continue
						var cd := Vector2(cp.x, cp.z).distance_to(c2)
						var lo := 5.0 if band[0] == "near" else 10.0
						if cd < lo or cd > lo + 5.0:
							continue
						var vis := 0
						for q in pts:
							var h := sp.intersect_ray(PhysicsRayQueryParameters3D.create(cp, q))
							if h.is_empty() or (h.position as Vector3).distance_to(q) < 0.9 or (h.collider is Node and hx.is_ancestor_of(h.collider)):
								vis += 1
						var sc := float(vis) / maxf(1, pts.size())
						if not is_nan(R.h(pp.x, pp.y)):
							sc += 0.15
						# 相機の脇に壁（3 m 以内）＝画面の半分が壁になる：減点
						var lk := _look(pp, c2, 0.0)
						for da in [-35.0, -20.0, 20.0, 35.0]:
							var dv := lk.rotated(Vector3.UP, deg_to_rad(da))
							var hw := sp.intersect_ray(PhysicsRayQueryParameters3D.create(cp, cp + dv * 3.0))
							if not hw.is_empty() and not (hw.collider is Node and String((hw.collider as Node).name).begins_with("TerrainCollision")):
								sc -= 0.12
						# 依附先（橋・水・農道…）が画面に入る：加点
						var rf: Vector2 = cl.get_meta("ref", c2)
						var to_r := rf - Vector2(cp.x, cp.z)
						if rf.distance_to(c2) > 1.0 and absf(Vector2(lk.x, lk.z).angle_to(to_r)) < deg_to_rad(28.0):
							sc += 0.1
						if sc > best:
							best = sc
							bv = ["%s_%s" % [cl.name, band[0]], snappedf(pp.x, 0.1), snappedf(pp.y, 0.1), snappedf(c2.x, 0.1), snappedf(c2.y, 0.1), -0.1, CAM_BACK, LAT,
								snappedf(c2.x, 0.1), snappedf(c2.y, 0.1)]
							if band[0] == "near":
								best_dir = d
				if bv.is_empty():
					print("PICK %s_%s：視點なし" % [cl.name, band[0]])
				else:
					views.append(bv)
					print("PICK %s score %.2f" % [bv[0], best])
			if best_dir != Vector2.ZERO:
				var hp := c2 + best_dir * 6.5
				views.append(["%s_high" % cl.name, snappedf(hp.x, 0.1), snappedf(hp.y, 0.1), snappedf(c2.x, 0.1), snappedf(c2.y, 0.1), -0.62, 10.0, 0.0, snappedf(c2.x, 0.1), snappedf(c2.y, 0.1)])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(views))
	f.close()
	print("PICK → %s（%d 視點）" % [out_path, views.size()])
