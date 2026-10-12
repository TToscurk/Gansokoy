extends SceneTree
## 人間之里 V2 P13 W3B 土渠美術 gate（N0／T0 支線）。検査対象＝保存された gen/farmland_p8.scn（プレイヤーが見る実物）＋計画（FLib.plan）。
##   godot --headless --path . --script res://tools/verify_village_v2_canal_art.gd
##   godot --headless --path . --script res://tools/verify_village_v2_canal_art.gd -- --negatives   （記憶體内で壊した 5 案がそれぞれ狙った項だけ FAIL）
##   godot --headless --path . --script res://tools/verify_village_v2_canal_art.gd -- --scene=res://.godot/w3b_backup/farmland_p8_before.scn   （旧場景＝W3B 以前は C1／C3／C4／C5 が FAIL）
## 項目（構造の證據であって美術判定ではない）：
##   C1 土渠の地面重みが全幅一様でない（旧＝全頂点 COLOR(0.12,0.25,1.0,0)／UV2(1,0)＝濡れ泥 100 %）：異なる重み ≥ 20 種、旧一様重み 0、草（全重み 0）の頂点 ≥ 15 %
##   C2 外縁は必ず草＝重み関数 branch_bank_weights(±1, s) が全 s で草
##   C3 支線の水面は泥水材質（tint 0.22/0.20/0.13・clarity 0.42・rough_base ≥ 0.34）。他の水（桝＝deep 等）は検査しない
##   C4 木槽の台：木槽の各取樣点で、台の頂（槽中心の真上からの最上面）が槽底の下面の 4–20 mm 下（隙間を塞ぐ）、槽内（±0.12）に土が槽底の上面より出ない、
##      板の外面（±0.215）で台が側板の下端以上（側板の下に隙間なし）。自由端（分水口側 TB_FADE）は槽内の判定だけ
##   C5 木槽の口で水幅が槽内に絞られる：口から 0.2 m 以内の水面頂点の横ずれ ≤ 0.22 m（旧＝土渠水面の半幅 0.30）
const FLib := preload("res://tools/village_v2_farmland_lib.gd")
const ZLib := preload("res://tools/village_v2_farmland_zone.gd")
const SCENE := "res://maps/village_v2/gen/farmland_p8.scn"
const BR := "ZoneWorks/ZoneIrrigation/Branches"
const LEGACY_C := Color(0.12, 0.25, 1.0, 0.0)
const LEGACY_U := Vector2(1.0, 0.0)

var fails := 0
var quiet := false


func check(label: String, ok: bool) -> void:
	if not quiet:
		print("[CANAL] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _init() -> void:
	_run.call_deferred()


func _kind(mi: MeshInstance3D) -> String:
	var m := mi.material_override
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		var sp := String((m as ShaderMaterial).shader.resource_path)
		if sp.ends_with("ground.gdshader"):
			return "earth"
		if sp.ends_with("p8_paddy_water.gdshader"):
			return "water"
	return "struct"


func _meshes(bid: String, root_n: Node) -> Dictionary:
	var out := {"earth": [], "water": []}
	var g := root_n.get_node_or_null("%s/Branch_%s" % [BR, bid])
	if g == null:
		return out
	for mi: Node in g.find_children("*", "MeshInstance3D", true, false):
		var k := _kind(mi as MeshInstance3D)
		if out.has(k):
			(out[k] as Array).append(mi)
	return out


## 水面の見た目パラメータ（泥水材質）：water_tint が (0.22,0.20,0.13) 近傍で、深い桝水（tint 0.16）は除く
func _is_branch_water(mi: MeshInstance3D) -> bool:
	var sm := mi.material_override as ShaderMaterial
	var t: Color = sm.get_shader_parameter("water_tint")
	return t.r > 0.19


func _stations(P: Dictionary, bid: String) -> Array:
	var out: Array = []
	for br: Dictionary in P["zone"]["branches"]:
		if br["id"] != bid:
			continue
		for r: Dictionary in br["runs"]:
			if r["kind"] != "open":
				continue
			var line: PackedVector2Array = r["line"]
			var spans := ZLib.branch_spans(r)
			for si in spans.size():
				var sp: Array = spans[si]
				if sp[0] != "trough":
					continue
				var s: float = float(sp[1]) + 0.25
				while s < float(sp[2]) - 0.2:
					var at: Array = FLib.at_s(line, s)
					out.append({"p": at[0], "d": at[1], "w": ZLib.branch_water(r, s), "g": ZLib.ground_h(at[0]), "s_from_start": s - float(sp[1]),
						"free_start": si == 0})
					s += 0.5
	return out


func _hit_y(tm: TriangleMesh, xf: Transform3D, x: float, z: float, y0: float) -> float:
	var inv := xf.affine_inverse()
	var a := inv * Vector3(x, y0, z)
	var h := tm.intersect_ray(a, (inv.basis * Vector3.DOWN).normalized())
	if h.is_empty():
		return NAN
	return (xf * (h["position"] as Vector3)).y


## 全項を実行して {label: ok} を返す（negatives はこの関数を壊した場面に対して呼ぶ）
func run_checks(v: Node, P: Dictionary) -> Dictionary:
	var res := {}
	for bid: String in ["N0", "T0"]:
		var ms := _meshes(bid, v)
		# C1
		var distinct := {}
		var legacy := 0
		var grass := 0
		var total := 0
		for mi: MeshInstance3D in ms["earth"]:
			var a := mi.mesh.surface_get_arrays(0)
			var cs: PackedColorArray = a[Mesh.ARRAY_COLOR]
			var u2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
			for i in cs.size():
				distinct["%s|%s" % [cs[i], u2[i]]] = true
				if cs[i].is_equal_approx(LEGACY_C) and u2[i].is_equal_approx(LEGACY_U):
					legacy += 1
				if cs[i].is_equal_approx(Color(0, 0, 0, 0)) and is_zero_approx(u2[i].x):
					grass += 1
				total += 1
		res["C1 %s 土渠の重み非一様（異なる重み %d・旧一様重み %d・草 %.0f %% / %d 頂点）" % [bid, distinct.size(), legacy, 100.0 * grass / maxf(total, 1), total]] = distinct.size() >= 20 and legacy == 0 and total > 0 and float(grass) / total >= 0.15
		# C3
		var wok := true
		var wn := 0
		var wdesc := ""
		for mi: MeshInstance3D in ms["water"]:
			if not _is_branch_water(mi):
				continue
			wn += 1
			var sm := mi.material_override as ShaderMaterial
			var t: Color = sm.get_shader_parameter("water_tint")
			wok = wok and absf(t.r - 0.22) < 0.01 and absf(t.g - 0.20) < 0.01 and absf(t.b - 0.13) < 0.01 and absf(float(sm.get_shader_parameter("clarity")) - 0.42) < 0.01 and float(sm.get_shader_parameter("rough_base")) >= 0.34 - 1e-4
			wdesc = "tint %s clarity %s rough %s" % [t, sm.get_shader_parameter("clarity"), sm.get_shader_parameter("rough_base")]
		res["C3 %s 水面は泥水材質（支線水面メッシュ %d：%s）" % [bid, wn, wdesc]] = wok and wn > 0
	# C2
	var edge_ok := true
	var s_ := 0.0
	while s_ < 300.0:
		for sg: float in [-1.0, 1.0]:
			var w: Array = ZLib.branch_bank_weights(sg, s_)
			edge_ok = edge_ok and (w[0] as Color).is_equal_approx(Color(0, 0, 0, 0)) and is_zero_approx((w[1] as Vector2).x)
		s_ += 0.37
	res["C2 外縁（|u|=1）は全 s で草（重み 0）"] = edge_ok
	# C4（T0 の木槽）
	var st := _stations(P, "T0")
	var ms0 := _meshes("T0", v)
	var bad_center := 0
	var bad_poke := 0
	var bad_side := 0
	var n_c := 0
	var n_s := 0
	var worst_c := 0.0
	var worst_p := -1.0
	if not (ms0["earth"] as Array).is_empty():
		var tms: Array = []
		var xfs: Array = []
		for mi: MeshInstance3D in ms0["earth"]:
			tms.append(mi.mesh.generate_triangle_mesh())
			xfs.append(mi.global_transform)
		for q: Dictionary in st:
			var p: Vector2 = q["p"]
			var d: Vector2 = q["d"]
			var nrm := Vector2(-d.y, d.x)
			var w: float = q["w"]
			var under := w - 0.11
			var top_at := func(pt: Vector2) -> float:
				var best := NAN
				for i in tms.size():
					var y := _hit_y(tms[i], xfs[i], pt.x, pt.y, w + 1.0)
					if not is_nan(y):
						best = y if is_nan(best) else maxf(best, y)
				return best
			var yc: float = top_at.call(p)
			var free: bool = q["free_start"] and float(q["s_from_start"]) < 1.7
			if not is_nan(yc):
				var gap := under - yc
				worst_c = maxf(worst_c, gap)
				if not free:
					n_c += 1
					if gap < 0.004 - 1e-4 or gap > 0.02 + 1e-4:
						bad_center += 1
			# 槽内（±0.12）に土が槽底の上面（w−0.07）より出ない
			for sd: float in [-0.12, 0.12]:
				var yi: float = top_at.call(p + nrm * sd)
				if not is_nan(yi):
					worst_p = maxf(worst_p, yi - (w - 0.075))
					if yi > w - 0.075:
						bad_poke += 1
			# 板の外面：台が側板の下端（w−0.13）以上
			if not free:
				for sd: float in [-0.215, 0.215]:
					var yo: float = top_at.call(p + nrm * sd)
					n_s += 1
					if is_nan(yo) or yo < w - 0.13 - 0.003:
						bad_side += 1
	res["C4a 木槽の台：槽底の下面と台の頂の隙間 4–20 mm（点 %d、不良 %d、最大隙間 %.3f m）" % [n_c, bad_center, worst_c]] = n_c > 0 and bad_center == 0
	res["C4b 槽内（±0.12）に土が槽底の上面より出ない（不良 %d、最大の出 %+.3f m）" % [bad_poke, worst_p]] = bad_poke == 0 and worst_p < 0.0
	res["C4c 板の外面で台が側板の下端以上（点 %d、不良 %d）" % [n_s, bad_side]] = n_s > 0 and bad_side == 0
	# C5：木槽の口の水幅
	var neck_max := 0.0
	var neck_n := 0
	for br: Dictionary in P["zone"]["branches"]:
		if br["id"] != "T0":
			continue
		for r: Dictionary in br["runs"]:
			if r["kind"] != "open":
				continue
			var line: PackedVector2Array = r["line"]
			var spans := ZLib.branch_spans(r)
			for si in spans.size():
				if spans[si][0] != "trough":
					continue
				for e in 2:
					var nb := si - 1 if e == 0 else si + 1
					if nb < 0 or nb >= spans.size():
						continue
					var sj: float = float(spans[si][1]) if e == 0 else float(spans[si][2])
					var at: Array = FLib.at_s(line, sj)
					var J: Vector2 = at[0]
					var d: Vector2 = at[1]
					for mi: MeshInstance3D in ms0["water"]:
						if not _is_branch_water(mi):
							continue
						var xf := mi.global_transform
						var vs: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
						for vv in vs:
							var wv := xf * vv
							var rel := Vector2(wv.x, wv.z) - J
							if absf(rel.dot(d)) <= 0.2:
								neck_max = maxf(neck_max, absf(rel.cross(d)))
								neck_n += 1
	res["C5 木槽の口の水幅が槽内に絞られる（口から 0.2 m 以内の水面頂点 %d、最大の横ずれ %.3f m ≤ 0.22）" % [neck_n, neck_max]] = neck_n > 0 and neck_max <= 0.22
	return res


func _load_scene() -> Node:
	var path := SCENE
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			path = a.substr(8)       # 旧版（W3B 以前）の farmland_p8.scn に対して gate が FAIL することの確認用
	var v: Node = (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	root.add_child(v)
	return v


func _report(res: Dictionary) -> void:
	for k: String in res:
		check(k, bool(res[k]))


func _run() -> void:
	var P: Dictionary = FLib.plan()
	var v := _load_scene()
	await process_frame
	var base := run_checks(v, P)
	if "--negatives" in OS.get_cmdline_user_args():
		quiet = true
		_report(base)
		quiet = false
		var base_fail := fails
		check("基準場面は全項 PASS（反向の前提）", base_fail == 0)
		_negatives(v, P, base)
		print("[CANAL] 結果：%d 項失敗（negatives）" % fails)
		quit(fails)
		return
	_report(base)
	print("[CANAL] 結果：%d 項失敗" % fails)
	quit(fails)


## 反向：場面を記憶體内で壊す→狙った項（接頭辞）だけが FAIL に変わること
func _negatives(v: Node, P: Dictionary, base: Dictionary) -> void:
	var cases := {
		"uniform": {"expect": ["C1 T0", "C1 N0"], "fn": _neg_uniform},
		"gap": {"expect": ["C4a", "C4c"], "fn": _neg_gap},      # 台を消す＝槽底の隙間（C4a）と側板の下の隙間（C4c）が同時に開く
		"poke": {"expect": ["C4a", "C4b"], "fn": _neg_poke},    # 槽内へ土を出す＝C4b、同じ土が槽底の下面を越える（C4a）
		"wide": {"expect": ["C5"], "fn": _neg_wide},
		"mat": {"expect": ["C3 T0", "C3 N0"], "fn": _neg_mat},
	}
	for name: String in cases:
		var c: Dictionary = cases[name]
		var restore: Array = (c["fn"] as Callable).call(v, P)
		var res := run_checks(v, P)
		for r: Callable in restore:
			r.call()
		var failed: Array = []
		for k: String in res:
			if not bool(res[k]):
				failed.append(k)
		# 狙った項は FAIL、それ以外は基準どおり PASS
		var hit := true
		for pre: String in c["expect"]:
			var any := false
			for k: String in failed:
				if k.begins_with(pre):
					any = true
			hit = hit and any
		var others := 0
		for k: String in failed:
			var targeted := false
			for pre: String in c["expect"]:
				if k.begins_with(pre):
					targeted = true
			if not targeted:
				others += 1
		check("反向 %s：狙った項 %s が FAIL（実際の FAIL：%s）、他の項は PASS のまま（巻き込み %d）" % [name, str(c["expect"]), str(failed.map(func(k): return String(k).substr(0, 5))), others], hit and others == 0)


func _earth_mesh(v: Node, bid: String) -> MeshInstance3D:
	var ms := _meshes(bid, v)
	return (ms["earth"] as Array)[0] if not (ms["earth"] as Array).is_empty() else null


func _neg_uniform(v: Node, _P: Dictionary) -> Array:
	var restore: Array = []
	for bid: String in ["N0", "T0"]:
		for mi: MeshInstance3D in _meshes(bid, v)["earth"]:
			var old := mi.mesh
			var a := old.surface_get_arrays(0)
			var cs: PackedColorArray = a[Mesh.ARRAY_COLOR]
			var u2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
			for i in cs.size():
				cs[i] = LEGACY_C
				u2[i] = LEGACY_U
			a[Mesh.ARRAY_COLOR] = cs
			a[Mesh.ARRAY_TEX_UV2] = u2
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			mi.mesh = m
			restore.append(func() -> void: mi.mesh = old)
	return restore


## 台を消した状態：木槽の取樣点から 0.9 m 以内の土渠頂点のうち地面より高いものを 0.12 m 下げる
func _shift_near_troughs(v: Node, P: Dictionary, within: float, dy: float, only_above_ground: bool) -> Array:
	var mi := _earth_mesh(v, "T0")
	var old := mi.mesh
	var a := old.surface_get_arrays(0)
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var xf := mi.global_transform
	var st := _stations(P, "T0")
	for i in vs.size():
		var w := xf * vs[i]
		var p := Vector2(w.x, w.z)
		var near := false
		for q: Dictionary in st:
			if (q["p"] as Vector2).distance_to(p) <= within:
				near = true
				break
		if near and (not only_above_ground or w.y > ZLib.ground_h(p) + 0.015):
			vs[i].y += dy
	a[Mesh.ARRAY_VERTEX] = vs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	mi.mesh = m
	return [func() -> void: mi.mesh = old]


func _neg_gap(v: Node, P: Dictionary) -> Array:
	return _shift_near_troughs(v, P, 0.9, -0.12, true)


func _neg_poke(v: Node, P: Dictionary) -> Array:
	return _shift_near_troughs(v, P, 0.25, 0.12, false)


func _neg_wide(v: Node, P: Dictionary) -> Array:
	# 木槽の口の近く（0.9 m 以内）の水面頂点を中心線から外へ 1.8 倍に広げる（水の耳を戻す）
	var restore: Array = []
	var junctions: Array = []
	for br: Dictionary in P["zone"]["branches"]:
		if br["id"] != "T0":
			continue
		for r: Dictionary in br["runs"]:
			if r["kind"] != "open":
				continue
			var line: PackedVector2Array = r["line"]
			var spans := ZLib.branch_spans(r)
			for si in spans.size():
				if spans[si][0] != "trough":
					continue
				for e in 2:
					var nb := si - 1 if e == 0 else si + 1
					if nb < 0 or nb >= spans.size():
						continue
					var sj: float = float(spans[si][1]) if e == 0 else float(spans[si][2])
					var at: Array = FLib.at_s(line, sj)
					junctions.append({"p": at[0], "d": at[1]})
	for mi: MeshInstance3D in _meshes("T0", v)["water"]:
		if not _is_branch_water(mi):
			continue
		var old := mi.mesh
		var a := old.surface_get_arrays(0)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var xf := mi.global_transform
		var inv := xf.affine_inverse()
		for i in vs.size():
			var w := xf * vs[i]
			var p := Vector2(w.x, w.z)
			for j: Dictionary in junctions:
				var rel := p - (j["p"] as Vector2)
				var d: Vector2 = j["d"]
				if absf(rel.dot(d)) <= 0.9:
					var along := d * rel.dot(d)
					var lat := rel - along
					var np: Vector2 = (j["p"] as Vector2) + along + lat * 1.8
					vs[i] = inv * Vector3(np.x, w.y, np.y)
					break
		a[Mesh.ARRAY_VERTEX] = vs
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mi.mesh = m
		restore.append(func() -> void: mi.mesh = old)
	return restore


func _neg_mat(v: Node, _P: Dictionary) -> Array:
	var restore: Array = []
	for bid: String in ["N0", "T0"]:
		for mi: MeshInstance3D in _meshes(bid, v)["water"]:
			if not _is_branch_water(mi):
				continue
			var old := mi.material_override
			var m := (old as ShaderMaterial).duplicate() as ShaderMaterial
			m.set_shader_parameter("water_tint", Color(0.36, 0.36, 0.30))
			m.set_shader_parameter("clarity", 0.7)
			m.set_shader_parameter("rough_base", 0.2)
			mi.material_override = m
			restore.append(func() -> void: mi.material_override = old)
	return restore
