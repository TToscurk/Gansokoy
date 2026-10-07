extends SceneTree
## 人間之里 V2 P9 R3：竹 Kit 獨立審圖場景＋ART_REVIEW 截圖（不植入 village_v2；竹林美術核准後才進西林與村緣）。
##   建場景（headless 可）：godot --headless --path . --script res://tools/village_v2_bamboo_review.gd -- --build
##   截圖（Forward+ 視窗）：godot --rendering-method forward_plus --path . --resolution 1920x1080 --script res://tools/village_v2_bamboo_review.gd -- --shots [--out=r3]
## 場景：res://assets/village_v2/bamboo_kit/review/bamboo_review.tscn
##   Lighting  ＝ village_v2 天象系統深拷貝（10:00）；Ground ＝ 共享地面 shader（林床配比）
##   Subjects/Live/<id>      單株自動 LOD（近／中／斜俯視）
##   Subjects/LODs/<id>/LOD<k> 強制單一 LOD 並排
##   Subjects/Grove          試作竹林 46×36 m（密核心、疏林緣、若竹、枯竹、傾き竹、折れ竹、筍、落葉、中央小徑與空洞）——
##                          只為審「竹林空間感」，不是正式擺放（正式擺放＝核准後的 R3 placement）
## 只有使用者能給 ART_APPROVED；本工具只產審圖證據。
const BLib := preload("res://tools/village_v2_bamboo_lib.gd")
const VegLib := preload("res://tools/village_v2_veg_lib.gd")
const KIT := "res://assets/village_v2/bamboo_kit"
const SCENE := KIT + "/review/bamboo_review.tscn"
const V2 := "res://maps/village_v2/village_v2.tscn"
const GROUND_SHADER := "res://assets/village_v2/_matlib/ground/ground.gdshader"
const EYE := 1.7
const HOUR := 10.0
const GROVE_Z := -70.0

var man: Dictionary
var out_dir := ""


func _init() -> void:
	man = JSON.parse_string(FileAccess.get_file_as_string(KIT + "/src/modules_blender.json"))
	var args := OS.get_cmdline_user_args()
	var rnd := "r3"
	for a: String in args:
		if a.begins_with("--out="):
			rnd = a.substr(6)
	out_dir = (ProjectSettings.globalize_path("res://") + "../docs/art_review/village_v2_p9_vegetation/%s/shots" % rnd).simplify_path()
	if "--build" in args:
		quit(_build())
		return
	if "--shots" in args:
		_shots.call_deferred()
		return
	printerr("用法：-- --build ｜ -- --shots")
	quit(1)


func _inst(tid: String) -> Node3D:
	return (load(BLib.TREE_DIR + "/%s.tscn" % tid) as PackedScene).instantiate()


func _own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		if c.scene_file_path == "":
			_own(c, owner)


func _build() -> int:
	var root := Node3D.new()
	root.name = "BambooReview"
	var v2: Node = (load(V2) as PackedScene).instantiate()
	var lt: Node = v2.get_node("Lighting").duplicate()
	for n in lt.find_children("*", "WorldEnvironment", true, false):
		(n as WorldEnvironment).environment = (n as WorldEnvironment).environment.duplicate(true)
	v2.free()
	root.add_child(lt)
	var g := MeshInstance3D.new()
	g.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = Vector2(3000, 3000)
	g.mesh = pm
	var gm := ShaderMaterial.new()
	gm.shader = load(GROUND_SHADER)
	gm.set_shader_parameter("albedo_arr", load("res://assets/village_v2/_matlib/ground/V2G_albedo.jpg"))
	gm.set_shader_parameter("nrh_arr", load("res://assets/village_v2/_matlib/ground/V2G_nrh.jpg"))
	gm.set_shader_parameter("noise_tex", load("res://assets/village_v2/_matlib/ground/V2G_noise.png"))
	gm.set_shader_parameter("ground_k", 0.19)
	gm.set_shader_parameter("mode", 0)
	gm.set_shader_parameter("use_vertex_weights", false)
	gm.set_shader_parameter("fix_a", Vector4(0.0, 0.0, 0.0, 0.0))
	gm.set_shader_parameter("fix_b", Vector4(0.55, 0.0, 0.0, 0.0))   # 竹林床：forest 多一點
	g.material_override = gm
	root.add_child(g)
	var sb := StaticBody3D.new()
	sb.name = "GroundCollision"
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(3000, 1, 3000)
	cs.shape = bx
	cs.position = Vector3(0, -0.5, 0)
	sb.add_child(cs)
	root.add_child(sb)
	var subj := Node3D.new()
	subj.name = "Subjects"
	root.add_child(subj)
	var live := Node3D.new()
	live.name = "Live"
	subj.add_child(live)
	var ids: Array = (man["trees"] as Dictionary).keys()
	var x := -float(ids.size() - 1) * 3.0
	for tid: String in ids:
		var t := _inst(tid)
		t.position = Vector3(x, 0, 0)
		live.add_child(t)
		x += 6.0
	var lods := Node3D.new()
	lods.name = "LODs"
	subj.add_child(lods)
	var z := -25.0
	for tid: String in ids:
		var info: Dictionary = man["trees"][tid]
		var holder := Node3D.new()
		holder.name = tid
		holder.set_meta("row_z", z)
		lods.add_child(holder)
		var n := (info["lods"] as Array).size()
		var w := maxf(float(info["crown_w"]), 1.0)
		for k in n:
			var t: Node3D = VegLib.tree_node(tid, info, KIT + "/mesh")
			t.name = "LOD%d" % k
			for c in t.get_children():
				if c is MeshInstance3D:
					var mi := c as MeshInstance3D
					if String(mi.name) != "LOD%d" % k:
						t.remove_child(mi)
						mi.free()
					else:
						mi.set_instance_shader_parameter("lod_band", Vector4(0, 0, 0, 0))
						mi.visibility_range_begin = 0.0
						mi.visibility_range_end = 0.0
			t.position = Vector3((k - (n - 1) * 0.5) * (w + 2.0), 0, 0)
			holder.add_child(t)
		holder.position = Vector3(400, 0, z)
		z -= 0.0
	_grove(subj)
	_own(root, root)
	var ps := PackedScene.new()
	var e := ps.pack(root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENE.get_base_dir()))
	if e == OK:
		e = ResourceSaver.save(ps, SCENE)
	print("[bamboo-review] 場景 %s：%s（%d 變體）" % [SCENE, error_string(e), ids.size()])
	root.free()
	return 0 if e == OK else 1


## 試作竹林：橢圓 46×36 m；密度場＝中心密、外緣疏（林緣傾き竹往外）；中央一條小徑＋一個林內空洞；
## 成竹 55 %／孟宗 15 %／淡竹 12 %／若竹 10 %／枯竹 5 %／折れ 3 %；筍與落葉補地面。決定性亂數。
func _grove(subj: Node3D) -> void:
	var gr := Node3D.new()
	gr.name = "Grove"
	gr.position = Vector3(0, 0, GROVE_Z)
	subj.add_child(gr)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3301
	var pts: Array[Vector2] = []
	var tries := 0
	var mix := {"take_mature": 56, "take_thick": 18, "take_thin": 13, "take_young": 9, "take_dead": 2.5, "take_broken": 1.5}
	while tries < 16000:
		tries += 1
		var p := Vector2(rng.randf_range(-23, 23), rng.randf_range(-18, 18))
		var e := (p.x / 23.0) * (p.x / 23.0) + (p.y / 18.0) * (p.y / 18.0)
		if e > 1.0:
			continue
		# 小徑（x 方向蜿蜒，寬 1.6 m）與空洞（半徑 3 m）
		if absf(p.y - 2.5 * sin(p.x * 0.25)) < 0.8 or p.distance_to(Vector2(8, -7)) < 3.5:
			continue
		var dens := lerpf(1.0, 0.25, smoothstep(0.35, 1.0, e))
		var sp := lerpf(0.8, 1.7, smoothstep(0.4, 1.0, e))       # 最小間距（核心 0.8 m、林緣 1.7 m；真竹林 0.5–1 稈/m²）
		if rng.randf() > dens:
			continue
		var ok := true
		for q in pts:
			if q.distance_to(p) < sp:
				ok = false
				break
		if not ok:
			continue
		pts.append(p)
		var tid := "take_lean" if (e > 0.75 and rng.randf() < 0.35) else _pick(rng, mix)
		var t := _inst(tid)
		t.position = Vector3(p.x, 0, p.y)
		# 傾き竹：朝林外（Blender 內傾向方位不固定 → 以 yaw 隨機近似；林緣外傾由 lean 變體＋位置表現）
		t.rotation.y = (atan2(-p.y, p.x) + rng.randf_range(-1.2, 1.2) if e > 0.5 else rng.randf() * TAU) if tid != "take_lean" else atan2(-p.y, p.x) + rng.randf_range(-0.4, 0.4)
		# 高度：中心高、林緣低＋低頻群落雜訊（同齡叢）＋少數突出高稈 → 頂線起伏、不成圓頂
		var clump := 0.85 + 0.3 * (0.5 + 0.5 * sin(p.x * 0.31 + 1.7) * cos(p.y * 0.27 - 0.4))
		var sc := rng.randf_range(0.82, 1.1) * lerpf(1.1, 0.72, smoothstep(0.25, 1.0, e)) * clump
		if rng.randf() < 0.07:
			sc *= 1.22
		t.scale = Vector3.ONE * sc
		gr.add_child(t)
	# 落葉地被（密處多）＋筍（若竹附近）
	# 竹林床：落葉近乎連續（核心覆蓋 ≈ 80–100 %、林緣漸疏到草地）——竹林地面特徵是厚的乾竹葉層
	for i in 900:
		var p := Vector2(rng.randf_range(-24, 24), rng.randf_range(-19, 19))
		var e := (p.x / 23.0) * (p.x / 23.0) + (p.y / 18.0) * (p.y / 18.0)
		if e > 1.15 or rng.randf() > lerpf(1.0, 0.1, smoothstep(0.55, 1.15, e)):
			continue
		var t := _inst("take_litter")
		t.position = Vector3(p.x, 0, p.y)
		t.rotation.y = rng.randf() * TAU
		t.scale = Vector3.ONE * rng.randf_range(0.8, 1.3)
		gr.add_child(t)
	for i in 18:
		var p := Vector2(rng.randf_range(-16, 16), rng.randf_range(-12, 12))
		if absf(p.y - 2.5 * sin(p.x * 0.25)) < 0.9:
			continue
		var t := _inst("takenoko")
		t.position = Vector3(p.x, 0, p.y)
		t.rotation.y = rng.randf() * TAU
		t.scale = Vector3.ONE * rng.randf_range(0.6, 1.4)
		gr.add_child(t)
	gr.set_meta("culms", pts.size())
	print("[bamboo-review] 試作竹林 %d 稈" % pts.size())


func _pick(rng: RandomNumberGenerator, w: Dictionary) -> String:
	var tot := 0.0
	for k in w:
		tot += float(w[k])
	var r := rng.randf() * tot
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return String(k)
	return String(w.keys()[0])


# ───────────────────────── 截圖 ─────────────────────────
var scene: Node3D
var subj: Node3D
var cam: Camera3D


func _snap(name: String, frames := 16) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var p := out_dir.path_join(name + ".png")
	print("[bamboo-review] %s %s" % [name, error_string(root.get_texture().get_image().save_png(p))])


func _aim(pos: Vector3, look: Vector3) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)


func _show(only: Array) -> void:
	for c in subj.get_node("Live").get_children():
		(c as Node3D).visible = c in only
	for c in subj.get_node("LODs").get_children():
		(c as Node3D).visible = c in only
	(subj.get_node("Grove") as Node3D).visible = subj.get_node("Grove") in only


func _shots() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	scene = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	var dn := root.get_node_or_null("/root/DayNight")
	if dn:
		dn.flowing = false
		dn.set_hour(HOUR)
	var sky := scene.get_node_or_null("Lighting/天象系統")
	if sky:
		sky.set("一日長度分鐘", 0.0)
		sky.set("時刻", HOUR)
	subj = scene.get_node("Subjects")
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 3000.0
	scene.add_child(cam)
	cam.current = true
	for i in 30:
		await process_frame
	# 側逆光：Subjects 轉到太陽在相機後側方 40°（同 R1 審圖）
	var sun := scene.get_node_or_null("Lighting/天象系統/太陽") as DirectionalLight3D
	var s := Vector3(0, 0, -1)
	if sun:
		s = -sun.global_transform.basis.z
		s.y = 0.0
		s = s.normalized() if s.length() > 0.01 else Vector3(0, 0, -1)
	var f := s.rotated(Vector3.UP, deg_to_rad(40.0))
	subj.rotation.y = atan2(-f.x, -f.z)
	# 單株：近 1.7 m（基部、節、筍皮）／中景全株／斜俯視
	for t: Node3D in subj.get_node("Live").get_children():
		var tid := String(t.name)
		var info: Dictionary = man["trees"][tid]
		var H := float(info["height"])
		var W := float(info["crown_w"])
		_show([t])
		var P := t.position
		var small := H < 1.0
		var dn2 := 2.2 if not small else 1.2
		_aim(subj.to_global(P + Vector3(0.4, EYE if not small else 0.8, dn2)), subj.to_global(P + Vector3(0, minf(H * 0.15, 1.6) if not small else 0.1, 0)))
		await _snap("%s_near" % tid)
		if not small:
			var dm := clampf(H * 0.75 + 2.0, 8.0, 16.0)
			_aim(subj.to_global(P + Vector3(0, EYE, dm)), subj.to_global(P + Vector3(0, H * 0.5, 0)))
			await _snap("%s_mid" % tid)
			# 梢（樹冠）仰看
			_aim(subj.to_global(P + Vector3(0.5, EYE, 3.0)), subj.to_global(P + Vector3(0, H * 0.75, 0)))
			await _snap("%s_up" % tid)
		var R := maxf(H, W) * 1.15 + 2.0
		var ctr := P + Vector3(0, H * 0.45, 0)
		var dir := Vector3(0.35, sin(deg_to_rad(35.0)), cos(deg_to_rad(35.0))).normalized()
		_aim(subj.to_global(ctr + dir * R), subj.to_global(ctr))
		await _snap("%s_top" % tid)
		# LOD 階梯
		var h: Node3D = subj.get_node("LODs/" + tid)
		_show([h])
		var span := 4.0 * (maxf(W, 1.0) + 2.0)
		var dl := maxf(span * 0.65, H * 0.95 + 3.0)
		_aim(subj.to_global(h.position + Vector3(0, EYE + dl * 0.1, dl)), subj.to_global(h.position + Vector3(0, H * 0.45, 0)))
		await _snap("%s_lods" % tid)
	# 試作竹林：林外 30 m／林緣 8 m／林內小徑（1.7 m 眼高、三個方向）／林內仰望／斜俯視／遠景 60、120 m
	var gr := subj.get_node("Grove") as Node3D
	_show([gr])
	var gp := gr.position
	var views := [
		["grove_out30", Vector3(0, EYE, 18 + 30), Vector3(0, 7.0, 0)],
		["grove_edge8", Vector3(-4, EYE, 18 + 8), Vector3(-2, 5.0, 0)],
		["grove_path_a", Vector3(-12, EYE, 2.5 * sin(-12 * 0.25)), Vector3(0, 2.6, 2.5 * sin(0.0))],
		["grove_path_b", Vector3(0, EYE, 0), Vector3(12, 2.8, 2.5 * sin(3.0))],
		["grove_gap", Vector3(8, EYE, -7), Vector3(-4, 3.0, -12)],
		["grove_inside_up", Vector3(-3, EYE, 2.5 * sin(-0.75)), Vector3(-3.5, 14.0, 1.0)],
		["grove_top", Vector3(36, 34, 44), Vector3(0, 0, 0)],
		["grove_far60", Vector3(10, EYE, 18 + 60), Vector3(0, 7.0, 0)],
		["grove_far120", Vector3(25, EYE, 18 + 120), Vector3(0, 7.0, 0)],
	]
	for vv: Array in views:
		_aim(subj.to_global(gp + (vv[1] as Vector3)), subj.to_global(gp + (vv[2] as Vector3)))
		await _snap(String(vv[0]), 24)
	print("[bamboo-review] 完成 → %s" % out_dir)
	quit(0)
