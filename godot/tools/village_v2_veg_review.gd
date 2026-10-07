extends SceneTree
## 人間之里 V2 P9 R1：植被庫獨立審圖場景（species × variant × LOD）＋ ART_REVIEW 截圖。
##   建場景（headless 可）：godot --headless --path . --script res://tools/village_v2_veg_review.gd -- --build
##   截圖（要 GPU 視窗）： godot --path . --resolution 1920x1080 --script res://tools/village_v2_veg_review.gd -- --shots[=<id 或 group,…>] [--out=<輪次>]
##     --out＝輸出到 docs/art_review/village_v2_p9_vegetation/<輪次>/shots（預設 r1；重做輪用 r1b 等，不覆寫前一輪證據）
##     篩選含 lineup → 另拍 Subjects/Lineup（杉／檜／御神木杉並排，R1b 審圖要求）的 20／50／100 m
## 場景：res://assets/village_v2/veg_kit/review/veg_review.tscn（不植入 village_v2；P9 R2 才正式替換六塊佔位林冠）
##   Lighting  ＝ village_v2 天象系統的深拷貝（同一套太陽／天空／霧），截圖固定 10:00
##   Ground    ＝ 共享地面 shader（_matlib/ground，固定 grass 配比）＋平面碰撞
##   Subjects/Live/<group>/<id>   自動 LOD（抖動交叉換檔）——近／中／遠／斜俯視、群組遠景剪影
##   Subjects/LODs/<id>/LOD<k>    強制單一 LOD 並排——LOD 階梯比較
##   Subjects/Colors/<group>/<preset>  群組代表樹 × 色彩變體（VegLib.GROUP_COLORS）
## LOD 換檔證據：<id>_sweep.png＝每個換檔距離 d 的「前／交叉中點／後」三格（相機距 lod_ref 恰為該距離、
##   FOV 依距離縮放讓樹在畫面等高），左到右 LOD0 → 最後一級。
## 鏡位（規格）：1.7 m 近景（眼高 1.7）、10–20 m 中景、50–100 m 遠景剪影（群組並排，50 m／100 m）、斜俯視 35°。
##   相機朝向依 10:00 太陽方位自動選「側逆光 40°」（整個 Subjects 繞 Y 轉，場景內排列不變）。
## 輸出：docs/art_review/village_v2_p9_vegetation/r1/shots/<id>_{near,mid,top,lods,sweep}.png、
##   group_<g>_far{50,100}.png、group_<g>_colors.png
## 只有使用者能給 ART_APPROVED；本工具只產審圖證據。

const VegLib := preload("res://tools/village_v2_veg_lib.gd")
const KIT := "res://assets/village_v2/veg_kit"
const SCENE := KIT + "/review/veg_review.tscn"
const V2 := "res://maps/village_v2/village_v2.tscn"
const GROUND_SHADER := "res://assets/village_v2/_matlib/ground/ground.gdshader"
const GROUP_ORDER := ["conifer", "broad", "sakura", "momiji", "matsu", "yanagi", "hero", "young", "dead", "under"]
const EYE := 1.7
## 杉／檜／御神木杉並排（R1b：杉 A／B／C、檜 A／B、御神木杉同一列、同一地面）
const LINEUP := ["sugi_c", "sugi_a", "hinoki_a", "sugi_hero", "hinoki_b", "sugi_b"]
const HOUR := 10.0

var man: Dictionary
var out_dir := ""


func _init() -> void:
	man = JSON.parse_string(FileAccess.get_file_as_string(KIT + "/src/modules_blender.json"))
	var args := OS.get_cmdline_user_args()
	var rnd := "r1"
	for a: String in args:
		if a.begins_with("--out="):
			rnd = a.substr(6)
	out_dir = (ProjectSettings.globalize_path("res://") + "../docs/art_review/village_v2_p9_vegetation/%s/shots" % rnd).simplify_path()
	if "--build" in args:
		quit(_build())
		return
	for a: String in args:
		if a.begins_with("--shots"):
			_shots.call_deferred(a.substr(8) if a.begins_with("--shots=") else "")
			return
	printerr("用法：-- --build ｜ -- --shots[=<id/group,…>]")
	quit(1)


# ───────────────────────── 建場景 ─────────────────────────

func _own(n: Node, owner: Node) -> void:
	## instance 進來的 prefab 只設根的 owner（內部節點屬於 prefab，不另存）
	for c in n.get_children():
		c.owner = owner
		if c.scene_file_path == "":
			_own(c, owner)


func _rows() -> Array:
	## [[group, [tid…]], …]（依 GROUP_ORDER、組內依 modules_blender.json 順序）
	var by := {}
	for tid: String in man["trees"]:
		var g := String(man["trees"][tid]["group"])
		if not by.has(g):
			by[g] = []
		by[g].append(tid)
	var out := []
	for g: String in GROUP_ORDER:
		if by.has(g):
			out.append([g, by[g]])
	return out


func _build() -> int:
	var root := Node3D.new()
	root.name = "VegReview"
	# Lighting：village_v2 天象系統深拷貝（Environment／Sky 也 duplicate，不依賴 village_v2.tscn）
	var v2: Node = (load(V2) as PackedScene).instantiate()
	var lt: Node = v2.get_node("Lighting").duplicate()
	for n in lt.find_children("*", "WorldEnvironment", true, false):
		(n as WorldEnvironment).environment = (n as WorldEnvironment).environment.duplicate(true)
	v2.free()
	root.add_child(lt)
	# Ground
	var g := MeshInstance3D.new()
	g.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = Vector2(3000, 3000)
	pm.subdivide_width = 0
	pm.subdivide_depth = 0
	g.mesh = pm
	var gm := ShaderMaterial.new()
	gm.shader = load(GROUND_SHADER)
	gm.set_shader_parameter("albedo_arr", load("res://assets/village_v2/_matlib/ground/V2G_albedo.jpg"))
	gm.set_shader_parameter("nrh_arr", load("res://assets/village_v2/_matlib/ground/V2G_nrh.jpg"))
	gm.set_shader_parameter("noise_tex", load("res://assets/village_v2/_matlib/ground/V2G_noise.png"))
	gm.set_shader_parameter("ground_k", 0.19)
	gm.set_shader_parameter("mode", 0)
	gm.set_shader_parameter("use_vertex_weights", false)
	# fix_a＝trodden,gravel,mud,rock；fix_b＝forest,farm,wet,street；其餘＝grass → 林床草地混一點 forest
	gm.set_shader_parameter("fix_a", Vector4(0.0, 0.0, 0.0, 0.0))
	gm.set_shader_parameter("fix_b", Vector4(0.35, 0.0, 0.0, 0.0))
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
	var lods := Node3D.new()
	lods.name = "LODs"
	subj.add_child(lods)
	# 自動 LOD 列：群組一列（沿 X），列距＝組內最大冠幅＋14
	var z := 0.0
	for row: Array in _rows():
		var gn := Node3D.new()
		gn.name = String(row[0])
		live.add_child(gn)
		var wmax := 0.0
		for tid: String in row[1]:
			wmax = maxf(wmax, float(man["trees"][tid]["crown_w"]))
		var xs := _row_x(row[1])
		var i := 0
		for tid: String in row[1]:
			var t: Node3D = (load(VegLib.TREE_DIR + "/%s.tscn" % tid) as PackedScene).instantiate()
			t.position = Vector3(float(xs[i]), 0, z)
			gn.add_child(t)
			i += 1
		gn.set_meta("row_z", z)
		gn.set_meta("row_x", [xs[0], xs[-1]])
		z -= wmax + 14.0
	# 強制 LOD 階梯：每個變體一列（從 Live 區後方 60 m 開始）
	z -= 60.0
	for row: Array in _rows():
		for tid: String in row[1]:
			var info: Dictionary = man["trees"][tid]
			var w := float(info["crown_w"])
			var holder := Node3D.new()
			holder.name = tid
			holder.set_meta("row_z", z)
			lods.add_child(holder)
			var n := (info["lods"] as Array).size()
			for k in n:
				# 強制單一 LOD：用 lib 直接組一棵（純節點，不是 instance），刪掉其他級、關掉換檔
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
				t.position = Vector3((k - (n - 1) * 0.5) * (w + 4.0), 0, z)
				holder.add_child(t)
			z -= w + 16.0
	# 並排列：杉／檜／御神木杉（自動 LOD，間距 4 m）
	z -= 30.0
	var lu := Node3D.new()
	lu.name = "Lineup"
	lu.set_meta("row_z", z)
	subj.add_child(lu)
	var lids: Array = LINEUP.filter(func(x): return man["trees"].has(x))
	var lxs := _row_x(lids)
	for i in lids.size():
		var t: Node3D = (load(VegLib.TREE_DIR + "/%s.tscn" % lids[i]) as PackedScene).instantiate()
		t.position = Vector3(float(lxs[i]), 0, z)
		lu.add_child(t)
	z -= 60.0
	# 色彩變體列：每群組代表樹（組內第一棵）× 該組色彩預設
	var cols := Node3D.new()
	cols.name = "Colors"
	subj.add_child(cols)
	z -= 40.0
	for row: Array in _rows():
		var g2 := String(row[0])
		if not VegLib.GROUP_COLORS.has(g2):
			continue
		var tid0 := String(row[1][0])
		var w0 := float(man["trees"][tid0]["crown_w"])
		var pres: Array = VegLib.GROUP_COLORS[g2]
		var gh := Node3D.new()
		gh.name = g2
		gh.set_meta("row_z", z)
		gh.set_meta("tid", tid0)
		cols.add_child(gh)
		for k in pres.size():
			var t: Node3D = (load(VegLib.TREE_DIR + "/%s.tscn" % tid0) as PackedScene).instantiate()
			t.name = String(pres[k])
			t.position = Vector3((k - (pres.size() - 1) * 0.5) * (w0 + 3.0), 0, z)
			VegLib.apply_color(t, String(pres[k]))
			gh.add_child(t)
		z -= w0 + 16.0
	_own(root, root)
	var ps := PackedScene.new()
	var e := ps.pack(root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENE.get_base_dir()))
	if e == OK:
		e = ResourceSaver.save(ps, SCENE)
	print("[veg-review] 場景 %s：%s（%d 變體）" % [SCENE, error_string(e), (man["trees"] as Dictionary).size()])
	root.free()
	return 0 if e == OK else 1


func _row_x(ids: Array) -> Array:
	var xs: Array = []
	var x := 0.0
	var prev := 0.0
	for tid: String in ids:
		var w := float(man["trees"][tid]["crown_w"])
		if not xs.is_empty():
			x += prev * 0.5 + w * 0.5 + 5.0
		xs.append(x)
		prev = w
	var mid: float = (float(xs[0]) + float(xs[-1])) * 0.5
	for i in xs.size():
		xs[i] = float(xs[i]) - mid
	return xs


# ───────────────────────── 截圖 ─────────────────────────

var scene: Node3D
var subj: Node3D
var cam: Camera3D


func _set_vis(only: Array) -> void:
	## only：要顯示的 Node3D；其餘 Live／LODs 下的樹全藏
	for gn in subj.get_node("Live").get_children():
		for t in gn.get_children():
			(t as Node3D).visible = t in only
		(gn as Node3D).visible = true
	for h in subj.get_node("LODs").get_children():
		(h as Node3D).visible = h in only
	for h in subj.get_node("Colors").get_children():
		(h as Node3D).visible = h in only
	var lu := subj.get_node_or_null("Lineup") as Node3D
	if lu:
		lu.visible = lu in only


func _snap(name: String, frames := 14) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var p := out_dir.path_join(name + ".png")
	var err := root.get_texture().get_image().save_png(p)
	print("[veg-review] %s %s" % [name, error_string(err)])


func _aim(pos: Vector3, look: Vector3) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)


func _shots(filter: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	scene = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	# 時刻權威＝DayNight autoload（有的話）；比照 walk_village_v2_farmland.gd _zone_shots
	var daynight := root.get_node_or_null("/root/DayNight")
	if daynight:
		daynight.flowing = false
		daynight.set_hour(HOUR)
	var sky := scene.get_node_or_null("Lighting/天象系統")
	if sky:
		sky.set("一日長度分鐘", 0.0)
		sky.set("時刻", HOUR)
	subj = scene.get_node("Subjects")
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.far = 4000.0
	scene.add_child(cam)
	cam.current = true
	for i in 30:
		await process_frame
	# 側逆光：相機前進方向＝太陽光行進方向（水平）偏 40°（太陽在相機後側方）
	var sun := scene.get_node_or_null("Lighting/天象系統/太陽") as DirectionalLight3D
	var s := Vector3(0, 0, -1)
	if sun:
		s = -sun.global_transform.basis.z
		s.y = 0.0
		s = s.normalized() if s.length() > 0.01 else Vector3(0, 0, -1)
	var f := s.rotated(Vector3.UP, deg_to_rad(40.0))
	# Subjects 局部 −Z（相機看樹的方向）→ 世界 f
	subj.rotation.y = atan2(-f.x, -f.z)
	var sd := -sun.global_transform.basis.z if sun else Vector3.DOWN
	print("[veg-review] DayNight=%s 時刻=%s 太陽仰角 %.1f° 能量 %.2f；水平 %s → 相機前進 %s、Subjects 轉 %.1f°" % [
		daynight != null, sky.get("時刻") if sky else "?", rad_to_deg(asin(clampf(-sd.y, -1, 1))),
		sun.light_energy if sun else 0.0, s, f, rad_to_deg(subj.rotation.y)])
	var want := filter.split(",", false)
	var live := subj.get_node("Live")
	for gn in live.get_children():
		var g := String(gn.name)
		var trees: Array = gn.get_children()
		var group_hit := want.is_empty() or g in want
		# 群組遠景剪影（50 m／100 m，眼高 1.7，自動 LOD）
		if group_hit:
			_set_vis(trees)
			var rz := float(gn.get_meta("row_z"))
			var hmax := 0.0
			for t in trees:
				hmax = maxf(hmax, float(man["trees"][String(t.name)]["height"]))
			for D in [50.0, 100.0]:
				var c := subj.to_global(Vector3(0, EYE, rz + D))
				var l := subj.to_global(Vector3(0, hmax * 0.42, rz))
				_aim(c, l)
				await _snap("group_%s_far%d" % [g, int(D)], 24)
		for t: Node3D in trees:
			var tid := String(t.name)
			if not (want.is_empty() or g in want or tid in want):
				continue
			var info: Dictionary = man["trees"][tid]
			var H := float(info["height"])
			var W := float(info["crown_w"])
			var dbh := float(info["dbh_m"])
			var P := t.position
			_set_vis([t])
			var under := g == "under" or g == "dead"
			# 近景 1.7 m：站在樹前，看根部＋下枝（接地、root flare、樹幹 taper）
			var dn := clampf(W * 0.22 + dbh * 2.0 + 2.0, 3.0, 8.0) if not under else clampf(W * 0.9 + 1.2, 2.2, 5.0)
			var ly := minf(H * 0.22, 2.4) if not under else minf(H * 0.4, 0.5)
			_aim(subj.to_global(P + Vector3(0.6, EYE, dn)), subj.to_global(P + Vector3(0, ly, 0)))
			await _snap("%s_near" % tid)
			# 中景 10–20 m：整棵入鏡
			var dm := clampf(H * 0.72 + 3.0, 10.0, 20.0)
			_aim(subj.to_global(P + Vector3(0, EYE, dm)), subj.to_global(P + Vector3(0, H * 0.46, 0)))
			await _snap("%s_mid" % tid)
			# 斜俯視 35°
			var R := maxf(H, W) * 1.25 + 4.0
			var ctr := P + Vector3(0, H * 0.45, 0)
			var dir := Vector3(0.35, sin(deg_to_rad(35.0)), cos(deg_to_rad(35.0))).normalized()
			_aim(subj.to_global(ctr + dir * R), subj.to_global(ctr))
			await _snap("%s_top" % tid)
			# LOD 階梯（強制單一 LOD 並排，中景距離、眼高 1.7）
			var h: Node3D = subj.get_node("LODs/" + tid)
			_set_vis([h])
			var n := h.get_child_count()
			var span := (n - 1) * (W + 4.0) + W
			var dl := maxf(span * 0.62, H * 0.9 + 4.0)
			var rz2 := float(h.get_meta("row_z"))
			_aim(subj.to_global(Vector3(0, EYE + dl * 0.12, rz2 + dl)), subj.to_global(Vector3(0, H * 0.42, rz2)))
			await _snap("%s_lods" % tid)
			# LOD 換檔掃描
			_set_vis([t])
			await _sweep(t, tid, info)
			cam.fov = 75.0
	# 並排：杉／檜／御神木杉（眼高 1.7；20 m 看下半＋樹形、50／100 m 看剪影）
	var lu := subj.get_node_or_null("Lineup") as Node3D
	if lu and "lineup" in want:
		_set_vis([lu])
		var rzl := float(lu.get_meta("row_z"))
		var hl := 0.0
		var xl := 0.0
		for t in lu.get_children():
			hl = maxf(hl, float(man["trees"][String(t.name)]["height"]))
			xl = maxf(xl, absf((t as Node3D).position.x) + float(man["trees"][String(t.name)]["crown_w"]) * 0.5)
		for D in [50.0, 100.0]:
			_aim(subj.to_global(Vector3(0, EYE, rzl + D)), subj.to_global(Vector3(0, hl * 0.42, rzl)))
			await _snap("lineup_far%d" % int(D), 24)
		# 20 m：整列寬於畫面 → 左右兩半各一張
		for side in [-1, 1]:
			_aim(subj.to_global(Vector3(side * xl * 0.5, EYE, rzl + 20.0)), subj.to_global(Vector3(side * xl * 0.5, hl * 0.45, rzl)))
			await _snap("lineup_mid20_%s" % ("L" if side < 0 else "R"), 20)
	# 色彩變體
	for gh: Node3D in subj.get_node("Colors").get_children():
		var g3 := String(gh.name)
		if not (want.is_empty() or g3 in want or String(gh.get_meta("tid")) in want):
			continue
		_set_vis([gh])
		var info3: Dictionary = man["trees"][String(gh.get_meta("tid"))]
		var H3 := float(info3["height"])
		var W3 := float(info3["crown_w"])
		var n3 := gh.get_child_count()
		var span3 := (n3 - 1) * (W3 + 3.0) + W3
		var d3 := maxf(span3 * 0.62, H3 * 0.9 + 4.0)
		var rz3 := float(gh.get_meta("row_z"))
		_aim(subj.to_global(Vector3(0, EYE + d3 * 0.12, rz3 + d3)), subj.to_global(Vector3(0, H3 * 0.42, rz3)))
		await _snap("group_%s_colors" % g3)
	print("[veg-review] 完成 → %s" % out_dir)
	quit(0)


## LOD 換檔掃描：每個換檔距離 d 拍 d−0.6w（只有上一級）／d（兩級都滿）／d+0.3w（上一級退到 40 %），相機到 lod_ref 的距離恰為該值、
## 眼高 1.7、FOV 依距離縮放（樹高佔畫面約 70 %），裁中央拼成一條。
func _sweep(t: Node3D, tid: String, info: Dictionary) -> void:
	var dist: Array = info["lod_dist"]
	var n := (info["lods"] as Array).size()
	var H := float(info["height"])
	var lod0 := t.get_node("LOD0") as MeshInstance3D
	var ref: Vector3 = lod0.get_instance_shader_parameter("lod_ref")
	var refg := t.to_global(ref)
	# 相機水平方向＝目前 Subjects 的「看樹方向」反向（局部 +Z）
	var back := subj.global_transform.basis.z.normalized()
	var ds: Array = []
	for k in range(1, n):
		var d := float(dist[k])
		var w := VegLib.xfade_w(d)
		ds.append_array([d - 0.6 * w, d, d + 0.3 * w])
	var tile_h := 300
	var tiles: Array[Image] = []
	for d: float in ds:
		var dy := refg.y - EYE
		var hz := sqrt(maxf(d * d - dy * dy, 1.0))
		var cpos := Vector3(refg.x, EYE, refg.z) + back * hz
		cam.fov = clampf(rad_to_deg(2.0 * atan(H * 0.72 / d)), 1.0, 75.0)
		_aim(cpos, t.to_global(Vector3(ref.x, H * 0.5, ref.z)))
		for i in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var sz := img.get_size()
		var cw := int(sz.y * 0.8)
		var reg := img.get_region(Rect2i((sz.x - cw) / 2, 0, cw, sz.y))
		reg.resize(int(tile_h * 0.8), tile_h, Image.INTERPOLATE_LANCZOS)
		tiles.append(reg)
	var tw := int(tile_h * 0.8)
	var strip := Image.create(tw * tiles.size() + 4 * (tiles.size() - 1), tile_h, false, Image.FORMAT_RGB8)
	strip.fill(Color(0.1, 0.1, 0.1))
	for i in tiles.size():
		var tl: Image = tiles[i]
		tl.convert(Image.FORMAT_RGB8)
		strip.blit_rect(tl, Rect2i(0, 0, tw, tile_h), Vector2i(i * (tw + 4), 0))
	var p := out_dir.path_join("%s_sweep.png" % tid)
	print("[veg-review] %s_sweep %s（距離 %s）" % [tid, error_string(strip.save_png(p)),
		", ".join(ds.map(func(x): return "%.1f" % x))])
