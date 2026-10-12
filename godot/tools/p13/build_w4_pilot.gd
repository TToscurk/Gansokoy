extends SceneTree
## P13 Wave 4：参道試作 overlay の生成（gen/sando_pilot_w4_p13.scn）と village_v2.tscn への掛載／撤去（root 直下の最後に 1 個）。
##   godot --headless --path . --script res://tools/p13/build_w4_pilot.gd -- --build
##   godot --headless --path . --script res://tools/p13/build_w4_pilot.gd -- --attach
##   godot --headless --path . --script res://tools/p13/build_w4_pilot.gd -- --detach
## --build は MultiMesh を使わない（通常 Mesh だけ）ので headless でよい。
const W4 := preload("res://tools/village_v2_sando_w4_lib.gd")
const SA := preload("res://tools/village_v2_shrine_approach_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const EXT_ID := "p13w4_sando_pilot"


func _init() -> void:
	_run.call_deferred()


func _stat(a: Array) -> String:
	if a.is_empty():
		return "n=0"
	var s := 0.0
	for v in a:
		s += float(v)
	var m := s / a.size()
	var q := 0.0
	for v in a:
		q += (float(v) - m) * (float(v) - m)
	var sd := sqrt(q / a.size())
	return "n=%d 平均 %.1f cm・標準偏差 %.1f cm・変動係数 %.0f %%・最小 %.1f・最大 %.1f" % [a.size(), m * 100.0, sd * 100.0, sd / maxf(m, 1e-6) * 100.0, (a.min() as float) * 100.0, (a.max() as float) * 100.0]


func _metrics(tag: String, cells: Array, y0: float) -> void:
	var risers := []
	var treads := []
	var yp := y0
	for c: Dictionary in cells:
		if String(c["kind"]) != "step":
			yp = float(c["y1"])
			continue
		risers.append(float(c["y0"]) - yp)
		treads.append((int(c["k1"]) - int(c["k0"])) * 0.05)
		yp = float(c["y1"])
	print("[W4B] %s 蹴上 %s" % [tag, _stat(risers)])
	print("[W4B] %s 踏面 %s" % [tag, _stat(treads)])


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	if "--attach" in a:
		quit(_attach())
		return
	if "--detach" in a:
		quit(_detach())
		return
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	var old := v.get_node_or_null(W4.NODE_NAME)
	if old:
		v.remove_child(old)
		old.free()
	root.add_child(v)
	for i in 4:
		await physics_frame
	var cl := SA.centerline()
	var H := SA.ramp_profile(v, cl)
	var st := SA.steps(cl, H)
	var rp := SA.ramp_points(st, H)
	var rg := W4.pilot_indices(st)
	var kr := W4.pilot_k_range(st)
	var t0 := Time.get_ticks_msec()
	var plan := W4.replan(cl, H, st, rp)
	print("[W4B] 計画 %d ms：r8 の区間 %d 要素（s=%.2f–%.2f m）→ 試作 %d 要素" % [Time.get_ticks_msec() - t0, rg.y - rg.x + 1, kr.x * 0.05, kr.y * 0.05, plan.size()])
	var kinds := {}
	for e: Dictionary in st.slice(rg.x, rg.y + 1):
		kinds[e["kind"]] = int(kinds.get(e["kind"], 0)) + 1
	print("[W4B] r8 区間の種別：", kinds)
	_metrics("r8  ", st.slice(rg.x, rg.y + 1), H[int(st[rg.x]["k0"])])
	_metrics("試作", plan, H[int(st[rg.x]["k0"])])
	var sp := v.get_world_3d().direct_space_state
	var touts := [W4.outer_profile(sp, cl, kr, -1.0), W4.outer_profile(sp, cl, kr, 1.0)]
	var tfars := [W4.outer_profile(sp, cl, kr, -1.0, W4.U_FAR), W4.outer_profile(sp, cl, kr, 1.0, W4.U_FAR)]
	var lanterns := []
	for ls in SA.lantern_specs(cl, H, st, sp):
		var s_l := float(ls["s"])
		if s_l >= kr.x * 0.05 - 2.0 and s_l <= kr.y * 0.05 + 2.0 and not lanterns.has(s_l):
			lanterns.append(s_l)
	print("[W4B] 区間内の燈籠 s=%s" % str(lanterns))
	var ss := v.get_node("ShrineApproachP10/StoneSteps") as MeshInstance3D
	t0 = Time.get_ticks_msec()
	var rest := W4.r8_without_range(ss.mesh as ArrayMesh, cl, kr)
	print("[W4B] r8 StoneSteps から区間を除外：三角形 %d 個中 %d 個を除去（残り %d）・%d ms" % [int(rest.get_meta("total")), int(rest.get_meta("removed")), int(rest.get_meta("total")) - int(rest.get_meta("removed")), Time.get_ticks_msec() - t0])
	t0 = Time.get_ticks_msec()
	var ov := W4.build(cl, H, plan, touts, tfars, lanterns, rest)
	var mi := ov.get_node("W4Steps") as MeshInstance3D
	var tris := 0
	for s in mi.mesh.get_surface_count():
		tris += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	var wb := SA.winding_bad(ov)
	var cnt := {}
	var em: Array = []
	for e: Dictionary in W4.side_log:
		cnt[e["mode"]] = int(cnt.get(e["mode"], 0)) + 1
		em.append(float(e["e_max"]))
	em.sort()
	var tl := 0
	var tm := 0
	var th := 0
	var by_side := {-1.0: [0, 0, 0], 1.0: [0, 0, 0]}
	for e: Dictionary in W4.side_log:
		tl += int(e["n_lo"])
		tm += int(e["n_mid"])
		th += int(e["n_hi"])
		var bs: Array = by_side[float(e["sd"])]
		bs[0] += int(e["n_lo"])
		bs[1] += int(e["n_mid"])
		bs[2] += int(e["n_hi"])
	var tt := float(maxi(tl + tm + th, 1))
	print("[W4B] 局所露出量〔笠石頂線 − 外側地形、0.05 m ごと〕：< 0.12 m %.0f %%・0.12–0.30 m %.0f %%・> 0.30 m %.0f %%（左 %s・右 %s）" % [100.0 * tl / tt, 100.0 * tm / tt, 100.0 * th / tt, str(by_side[-1.0]), str(by_side[1.0])])
	print("[W4B] 側面 run %d：%s｜e_max 分布 最小 %.2f・中央値 %.2f・最大 %.2f m" % [W4.side_log.size(), str(cnt), em[0] if em.size() > 0 else 0.0, em[em.size() / 2] if em.size() > 0 else 0.0, em[em.size() - 1] if em.size() > 0 else 0.0])
	print("[W4B] W4Steps %d 三角形・W4Soil %d 三角形・%d ms・巻き順不正 %d／%d・石垣／笠石ブロック %d" % [tris, W4.soil_n, Time.get_ticks_msec() - t0, int(wb[0]), int(wb[1]), W4.diag.size()])
	var ps := PackedScene.new()
	var ok := ps.pack(ov) == OK and ResourceSaver.save(ps, W4.OUTPUT, ResourceSaver.FLAG_COMPRESS) == OK
	print("[W4B] save %s %s" % [W4.OUTPUT, "OK" if ok else "FAIL"])
	var cols := ov.find_children("*", "CollisionObject3D", true, false)
	print("[W4B] overlay の碰撞体 %d 個（0 であること）" % cols.size())
	ov.free()
	quit(0 if ok and cols.is_empty() and int(wb[0]) == 0 else 1)


func _attach() -> int:
	var f := FileAccess.open(SCENE, FileAccess.READ)
	var t := f.get_as_text()
	f.close()
	if t.contains("id=\"%s\"" % EXT_ID):
		print("[W4B] 既に掛載済み")
		return 0
	var nl := "\r\n" if t.contains("\r\n") else "\n"
	var ext := "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"%s\"]" % [W4.OUTPUT, EXT_ID]
	var last := t.rfind("[ext_resource ")
	var eol := t.find(nl, last)
	t = t.substr(0, eol + nl.length()) + ext + nl + t.substr(eol + nl.length())
	t = t.rstrip("\r\n") + nl + nl + "[node name=\"%s\" parent=\".\" instance=ExtResource(\"%s\")]" % [W4.NODE_NAME, EXT_ID] + nl
	var w := FileAccess.open(SCENE, FileAccess.WRITE)
	w.store_string(t)
	w.close()
	var v: Node3D = (ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var n := v.get_node_or_null(W4.NODE_NAME)
	print("[W4B] attach：%s（root 子の最後＝%s、同名 %d）" % ["OK" if n != null else "FAIL", v.get_child(v.get_child_count() - 1).name,
		v.get_children().filter(func(c: Node) -> bool: return c.name == W4.NODE_NAME).size()])
	var okk := n != null and v.get_child(v.get_child_count() - 1).name == W4.NODE_NAME
	v.free()
	return 0 if okk else 1


func _detach() -> int:
	var f := FileAccess.open(SCENE, FileAccess.READ)
	var t := f.get_as_text()
	f.close()
	if not t.contains("id=\"%s\"" % EXT_ID):
		print("[W4B] 掛載されていない")
		return 0
	var nl := "\r\n" if t.contains("\r\n") else "\n"
	var ext := "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"%s\"]" % [W4.OUTPUT, EXT_ID] + nl
	var node := nl + "[node name=\"%s\" parent=\".\" instance=ExtResource(\"%s\")]" % [W4.NODE_NAME, EXT_ID] + nl
	t = t.replace(ext, "").replace(nl + node, nl).replace(node, "")
	var w := FileAccess.open(SCENE, FileAccess.WRITE)
	w.store_string(t)
	w.close()
	print("[W4B] detach 完了（残り参照 %d）" % t.count(EXT_ID))
	return 0 if not t.contains(EXT_ID) else 1
