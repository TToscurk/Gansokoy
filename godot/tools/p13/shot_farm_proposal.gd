extends SceneTree
## P13 W2 農舍提案プレビュー（非 headless、10:00）。灰模はこのプロセス内だけ（場景・P8 へ書かない、碰撞なし）。
## あわせて W1 Pilot 各棟の Kit AABB（元 vs Pilot）と MeshInstance 数を出す。
##   godot --path . --script res://tools/p13/shot_farm_proposal.gd -- <outdir/>
const AL := preload("res://tools/village_v2_arch_pilot_lib.gd")
## [名, 中心 x, z, 間口, 奥行, 簷, 棟, yaw(deg), 色]
const SITES := [
	["A1_noka", 398.0, -11.0, 9.1, 6.4, 2.6, 5.4, 0.0, Color(0.62, 0.52, 0.36)],
	["A2_naya", 383.0, -27.0, 5.5, 3.6, 2.3, 3.6, 90.0, Color(0.50, 0.42, 0.32)],
	["B1_noka", 431.0, -56.0, 9.1, 6.4, 2.6, 5.4, 90.0, Color(0.62, 0.52, 0.36)],
	["C1_naya", 323.0, 70.0, 5.5, 3.6, 2.3, 3.6, 0.0, Color(0.50, 0.42, 0.32)],
]

var cam: Camera3D
var sp: PhysicsDirectSpaceState3D

func _init() -> void:
	_run.call_deferred()

func _g(x: float, z: float) -> float:
	var hit := sp.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 80, z), Vector3(x, -40, z)))
	return float(hit.position.y) if not hit.is_empty() else 0.5

func _shot(path: String) -> void:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(path)
	print("SHOT ", path)

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	return m

## 切妻の灰模（壁箱＋屋根 2 枚）
func _house(parent: Node3D, s: Array) -> void:
	var w: float = s[3]
	var d: float = s[4]
	var e: float = s[5]
	var r: float = s[6]
	var y := _g(s[1], s[2])
	var h := Node3D.new()
	h.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(s[7])), Vector3(s[1], y, s[2]))
	parent.add_child(h)
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, e + 0.3, d)
	bm.material = _mat(s[8])
	wall.mesh = bm
	wall.position.y = (e + 0.3) * 0.5 - 0.3
	h.add_child(wall)
	var half := d * 0.5 + 0.6
	var rise := r - e
	var slope := sqrt(half * half + rise * rise)
	for sg in [1.0, -1.0]:
		var rf := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(w + 1.2, 0.18, slope)
		pm.material = _mat(Color(0.55, 0.47, 0.30) if String(s[0]).ends_with("noka") else Color(0.32, 0.31, 0.30))
		rf.mesh = pm
		rf.transform = Transform3D(Basis(Vector3.RIGHT, sg * atan2(rise, half)), Vector3(0, e + rise * 0.5, sg * half * 0.5))
		h.add_child(rf)
	var lb := Label3D.new()
	lb.text = "%s（提案・未施工）" % s[0]
	lb.font_size = 96
	lb.pixel_size = 0.01
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.position.y = r + 1.5
	lb.modulate = Color(1, 0.95, 0.4)
	lb.outline_size = 16
	h.add_child(lb)

func _aabb(k: Node3D) -> AABB:
	var ab := AABB()
	var first := true
	for mi: MeshInstance3D in k.get_node("LOD0").get_children():
		if mi.mesh == null:
			continue
		var a := mi.transform * mi.mesh.get_aabb()
		ab = a if first else ab.merge(a)
		first = false
	return ab

func _run() -> void:
	var outdir: String = OS.get_cmdline_user_args()[0]
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for nm in ["Debug", "Portals", "QuestAnchors"]:
		if v.has_node(nm):
			v.get_node(nm).visible = false
	# W1 Pilot：元 Kit vs Pilot Kit
	var ov := (ResourceLoader.load(AL.OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as Node3D
	var recs := AL.greybox_recs()
	var tot0 := 0
	var tot1 := 0
	for h: Node3D in ov.get_children():
		var id := String(h.name)
		var body := v.get_node("Districts/%s/Buildings/%s" % [recs[id]["district"], id]) as Node3D
		var k0 := body.get_node("Kit") as Node3D
		var k1 := h.get_node("Kit") as Node3D
		var a0 := _aabb(k0)
		var a1 := _aabb(k1)
		var n0 := k0.find_children("*", "MeshInstance3D", true, false).size()
		var n1 := k1.find_children("*", "MeshInstance3D", true, false).size()
		tot0 += n0
		tot1 += n1
		print("[W1] %s %s：x %.2f..%.2f→%.2f..%.2f z %.2f..%.2f→%.2f..%.2f top %.2f→%.2f MI %d→%d" % [id, h.get_meta("p13_cat"),
			a0.position.x, a0.end.x, a1.position.x, a1.end.x, a0.position.z, a0.end.z, a1.position.z, a1.end.z, a0.end.y, a1.end.y, n0, n1])
	print("[W1] MeshInstance 合計 %d→%d（差 %+d）" % [tot0, tot1, tot1 - tot0])
	ov.free()
	await process_frame
	for n in root.find_children("*", "", true, false):
		if n.has_method("set_hour"):
			n.call("set_hour", 10.0)
	cam = Camera3D.new()
	cam.far = 900.0
	root.add_child(cam)
	cam.make_current()
	for i in 30:
		await process_frame
	sp = v.get_world_3d().direct_space_state
	var grp := Node3D.new()
	root.add_child(grp)
	for s: Array in SITES:
		_house(grp, s)
	for i in 5:
		await process_frame
	# ① 俯瞰：全候補
	cam.fov = 55.0
	cam.global_transform = Transform3D(Basis(), Vector3(355, 70, 40)).looking_at(Vector3(400, 0, -30), Vector3.UP)
	await _shot(outdir + "farm_overview.png")
	# ② 農道交差（372,0）付近から A 群を TPS 眼高
	var e := Vector2(366.0, 6.0)
	cam.fov = 60.0
	cam.global_transform = Transform3D(Basis(), Vector3(e.x, _g(e.x, e.y) + 2.6, e.y)).looking_at(Vector3(392, _g(392, -16) + 2.0, -16), Vector3.UP)
	await _shot(outdir + "farm_A_tps.png")
	# ③ C1（水車 3・T0 付近）
	var f := Vector2(338.0, 84.0)
	cam.global_transform = Transform3D(Basis(), Vector3(f.x, _g(f.x, f.y) + 2.6, f.y)).looking_at(Vector3(322, _g(322, 70) + 1.5, 70), Vector3.UP)
	await _shot(outdir + "farm_C_tps.png")
	quit(0)
