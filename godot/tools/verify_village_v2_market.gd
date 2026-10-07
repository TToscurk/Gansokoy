extends SceneTree
## 人間之里 V2 P10 R1 市集廣場 gate（構造の機械検査；美術判定は同機位 TPS BEFORE／AFTER）。
##   godot --headless --path . --script res://tools/verify_village_v2_market.gd                 規劃 gate
##   godot --headless --path . --script res://tools/verify_village_v2_market.gd -- --negatives  永久反向（各案が瞄準項を FAIL させる）
##   godot --headless --path . --script res://tools/verify_village_v2_market.gd -- --build      gate PASS 時のみ gen/market_p10.scn を書く
##   godot --headless --path . --script res://tools/verify_village_v2_market.gd -- --attach     village_v2.tscn の Props 下へ MarketP10 を掛ける（1 回だけ）
##   godot --path . --script res://tools/verify_village_v2_market.gd -- --scene                 場景級（掛載・接地射線・碰撞・LOD）
##   godot --headless --path . --script res://tools/verify_village_v2_market.gd -- --seal       封存（data/village_v2_p10r1_seal.json 雜湊＋掛載＋竄改反向；P10 R1 r3 ART_APPROVED 2026-10-04）
## 每項一行 [MKT] PASS/FAIL；結尾 quit(失敗項數)。
const MK := preload("res://tools/village_v2_market_lib.gd")
const SEAL := "res://data/village_v2_p10r1_seal.json"
const GC := preload("res://tools/village_v2_groundcover_lib.gd")
const VL := preload("res://tools/village_v2_groundcover_village.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const VEG_ORDER := ["ForestP9", "BambooP9", "HiedaGardenP9", "ShrineGroveP9", "SchoolYardP9", "WatersideP9", "TowerYardP9", "SuzunaanP9", "GeidonteiP9", "KirisameP9", "GroundcoverP9"]

var fails := 0
var failed_labels: Array = []
var quiet := false


func check(label: String, ok: bool) -> void:
	if not quiet:
		print("[MKT] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1
		failed_labels.append(label)


func info(s: String) -> void:
	if not quiet:
		print("[MKT] INFO " + s)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--attach" in args:
		quit(_attach())
		return
	if "--seal" in args:
		quit(_seal())
		return
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	if "--scene" in args:
		root.add_child(v)
		await _scene(v)
		print("[MKT] 結果：%d 項失敗（scene）" % fails)
		quit(fails)
		return
	var old := v.get_node_or_null(MK.PARENT + "/" + MK.NODE_NAME)
	if old:
		old.get_parent().remove_child(old)
		old.free()
	root.add_child(v)
	await physics_frame
	var P := MK.plan(v)
	var CV: Dictionary = VL.context_v(v, GC.context(v))
	P["CV"] = CV
	info("規劃 %d 件、anchors %d（%d ms）" % [(P["items"] as Array).size(), (P["anchors"] as Array).size(), P["ms"]])
	if "--negatives" in args:
		var target := {"n_float": "接地", "n_road": "路面", "n_building": "建物", "n_overlap": "互不重疊", "n_open": "歩く通り",
			"n_clone": "構圖", "n_vendor": "NPC anchors", "n_sealed": "封存"}
		var bad := 0
		for nm: String in target:
			var P2 := P.duplicate()
			P2["items"] = (P["items"] as Array).duplicate(true)
			P2["anchors"] = (P["anchors"] as Array).duplicate(true)
			fails = 0
			failed_labels.clear()
			quiet = true
			_inject(P2, nm)
			_checks(P2)
			quiet = false
			var hit := failed_labels.any(func(l: String) -> bool: return l.begins_with(String(target[nm])))
			print("[MKT] %s 反向 %s → 「%s」必須 FAIL（失敗項 %d）" % ["PASS" if hit else "FAIL", nm, target[nm], failed_labels.size()])
			if not hit:
				bad += 1
		print("[MKT] 結果：%d 項失敗（negatives）" % bad)
		quit(bad)
		return
	_checks(P)
	if "--build" in args and fails == 0:
		var r := MK.bake(P)
		var holder := Node3D.new()
		holder.add_child(r)
		MK.own(r, r)
		var ps := PackedScene.new()
		var e := ps.pack(r)
		var e2 := ResourceSaver.save(ps, MK.OUTPUT, ResourceSaver.FLAG_COMPRESS) if e == OK else e
		check("save %s（items %d、anchors %d、碰撞 %d）" % [MK.OUTPUT, r.get_meta("items"), r.get_meta("anchors"), r.get_meta("shapes")], e2 == OK)
		holder.free()
	print("[MKT] 結果：%d 項失敗" % fails)
	quit(fails)


func _inject(P: Dictionary, nm: String) -> void:
	var items: Array = P["items"]
	var C: Dictionary = P["C"]
	match nm:
		"n_float":
			items[0]["y"] = float(items[0]["y"]) + 0.3
		"n_road":
			var it: Dictionary = items.filter(func(x: Dictionary) -> bool: return x["id"] == "mk_tenbin")[0]
			it["p"] = (it["p"] as Vector2) + Vector2(0.0, 4.0)
		"n_building":
			var it: Dictionary = items.filter(func(x: Dictionary) -> bool: return x["id"] == "mk_tsumini")[0]
			it["p"] = Vector2(254.0, -30.0)
		"n_overlap":
			var it: Dictionary = items.filter(func(x: Dictionary) -> bool: return x["id"] == "sk_bench")[0]
			it["p"] = (it["p"] as Vector2) + Vector2(0.287, -0.958) * 1.6
		"n_open":
			items.append(MK.item(C, "mk_kanban_dango", Vector2(238.4, -44.0), Vector2(1, 0), "west"))
		"n_clone":
			for k in 3:
				items.append(MK.item(C, "mk_yatai_yasai", Vector2(229.0, -52.0 - k * 3.0), Vector2(1, 0), "west"))
		"n_vendor":
			P["anchors"] = (P["anchors"] as Array).filter(func(a: Dictionary) -> bool: return not String(a["id"]).begins_with("vendor_"))
		"n_sealed":
			var it: Dictionary = items.filter(func(x: Dictionary) -> bool: return x["id"] == "mk_tsumini")[0]
			it["p"] = Vector2(248.0, -8.0)


func _poly(it: Dictionary) -> PackedVector2Array:
	if String(it["id"]) in MK.LINE:
		var out := PackedVector2Array()
		for sx in [-2.5, 2.5]:
			var c := MK.local_to_world(it, Vector2(sx, 0.0))
			out.append_array([c + Vector2(-0.08, -0.08), c + Vector2(0.08, -0.08), c + Vector2(0.08, 0.08), c + Vector2(-0.08, 0.08)])
		return out
	return MK.corners(it)


func _polys(it: Dictionary) -> Array:
	var p := _poly(it)
	if p.size() == 8:
		return [p.slice(0, 4), p.slice(4, 8)]
	return [p]


func _samples(it: Dictionary, step := 0.25) -> PackedVector2Array:
	if String(it["id"]) in MK.LINE:
		return _poly(it)
	var b: Array = MK.BOX[String(it["id"])]
	var out := PackedVector2Array()
	var nx := maxi(1, int(ceil(float(b[0]) * 2.0 / step)))
	var nz := maxi(1, int(ceil(float(b[1]) * 2.0 / step)))
	for i in nx + 1:
		for j in nz + 1:
			var l := Vector2(float(b[4]) - float(b[0]) + float(b[0]) * 2.0 * i / nx, float(b[3]) - float(b[1]) + float(b[1]) * 2.0 * j / nz)
			out.append(MK.local_to_world(it, l))
	return out


func _checks(P: Dictionary) -> void:
	var items: Array = P["items"]
	var anchors: Array = P["anchors"]
	var C: Dictionary = P["C"]
	var CV: Dictionary = P["CV"]
	var S: RLib.TriSampler = C["S"]
	var R: RLib.TriSampler = C["R"]
	var SH: VL.RectHash = CV["SH"]
	# ── M1 Kit：全 id に LOD0／LOD1 の mesh と足元定義
	var miss: Array = []
	for it: Dictionary in items:
		var id := String(it["id"])
		if not MK.BOX.has(id) or not ResourceLoader.exists(MK.mesh_dir(id) + id + ".res") or not ResourceLoader.exists(MK.mesh_dir(id) + id + "_l1.res"):
			miss.append(id)
	check("Kit：%d 件の mesh（LOD0／LOD1）と足元定義（欠 %d %s）" % [items.size(), miss.size(), ", ".join(miss.slice(0, 3))], miss.is_empty() and items.size() >= 30)
	# ── M2 接地：中心の浮き ≤ 0.02 m、足元 4 隅の沈み ≤ 0.15 m
	var fl: Array = []
	var max_sink := 0.0
	for it: Dictionary in items:
		var p: Vector2 = it["p"]
		var y: float = it["y"]
		var top := MK.top_h(S, R, C["Y"], p)
		var sink := top - y
		var pts: PackedVector2Array = _poly(it)
		for q: Vector2 in pts:
			sink = maxf(sink, MK.top_h(S, R, C["Y"], q) - y)
		max_sink = maxf(max_sink, sink)
		var fmin := 1e9
		for q: Vector2 in pts:
			fmin = minf(fmin, y - MK.top_h(S, R, C["Y"], q))
		if not (String(it["id"]) in MK.LINE):
			fmin = minf(fmin, y - top)
		if fmin > 0.02 or sink > 0.15:
			fl.append("%s(浮 %.2f 沈 %.2f)" % [it["id"], fmin, sink])
	check("接地：%d 件 浮き ≤ 0.02 m・沈み ≤ 0.15 m（最大沈み %.2f m）違反 %d %s" % [items.size(), max_sink, fl.size(), ", ".join(fl.slice(0, 3))], fl.is_empty())
	# ── M3 建物・frontage（P6 店先の過渡）を踏まない
	var bad_b: Array = []
	var bad_r: Array = []
	var bad_s: Array = []
	for it: Dictionary in items:
		var nb := 0
		var nr := 0
		var nsl := 0
		for q: Vector2 in _samples(it):
			var br := VL.blocked_v(CV, q)
			if br == "building" or br == "frontage" or VL.wall_d(CV, q) < 0.3:
				nb += 1
			if not is_nan(R.h(q.x, q.y)):
				nr += 1
			if SH.hit(q) != "":
				nsl += 1
		if nb > 0:
			var q0: Vector2 = _samples(it)[0]
			for q: Vector2 in _samples(it):
				var br2 := VL.blocked_v(CV, q)
				if br2 == "building" or br2 == "frontage" or VL.wall_d(CV, q) < 0.3:
					q0 = q
					break
			bad_b.append("%s×%d@(%.1f,%.1f):%s/%.2f" % [it["id"], nb, q0.x, q0.y, VL.blocked_v(CV, q0), VL.wall_d(CV, q0)])
		if nr > 0:
			bad_r.append("%s×%d" % [it["id"], nr])
		if nsl > 0:
			bad_s.append("%s×%d" % [it["id"], nsl])
	check("建物：足元が建物・店先（frontage）・壁 0.3 m 以内に入る件 %d %s" % [bad_b.size(), ", ".join(bad_b.slice(0, 3))], bad_b.is_empty())
	check("路面：足元が路面（主街・中橫街）に載る件 %d %s（軒・幟の張り出しは可、足元は不可＝通行帯を塞がない）" % [bad_r.size(), ", ".join(bad_r.slice(0, 3))], bad_r.is_empty())
	check("封存：足元が封存 Hero 構圖（R4 周邊・竹林）に入る件 %d %s" % [bad_s.size(), ", ".join(bad_s.slice(0, 3))], bad_s.is_empty())
	# ── M4 互不重疊（足元の多角形）
	var ov: Array = []
	for i in items.size():
		for j in range(i + 1, items.size()):
			if (items[i]["p"] as Vector2).distance_to(items[j]["p"]) > 6.0:
				continue
			var hit := false
			for a: PackedVector2Array in _polys(items[i]):
				for b: PackedVector2Array in _polys(items[j]):
					if not Geometry2D.intersect_polygons(a, b).is_empty():
						hit = true
			if hit:
				ov.append("%s×%s" % [items[i]["id"], items[j]["id"]])
	check("互不重疊：足元が重なる組 %d %s" % [ov.size(), ", ".join(ov.slice(0, 3))], ov.is_empty())
	# ── M5 歩く通り（西・東の通り、中の切れ目、入口の口）と屋台・布棚の客の立ち場（前 1.6 m）
	var in_open: Array = []
	var front_block: Array = []
	for it: Dictionary in items:
		for poly: PackedVector2Array in _polys(it):
			for ln: String in MK.LANES:
				if String(it["id"]) in MK.LINE and ln == "cross_gap":
					continue
				var r: Rect2 = MK.LANES[ln]
				var rp := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
				if not Geometry2D.intersect_polygons(poly, rp).is_empty():
					in_open.append("%s∈%s" % [it["id"], ln])
		if String(it["id"]) in MK.STALL:
			var b: Array = MK.BOX[String(it["id"])]
			var fr := PackedVector2Array()
			for s in [Vector2(-0.8, 0.05), Vector2(0.8, 0.05), Vector2(0.8, 1.6), Vector2(-0.8, 1.6)]:
				fr.append(MK.local_to_world(it, Vector2(float(b[0]) * s.x, float(b[3]) + float(b[1]) + s.y)))
			for o: Dictionary in items:
				if o == it or String(o["id"]).begins_with("mk_kanban") or String(o["id"]).begins_with("mk_nobori") or String(o["id"]) in ["sk_bench", "gd_shogi", "gd_taru", "sz_stool", "mk_bangasa"]:
					continue
				for op: PackedVector2Array in _polys(o):
					if not Geometry2D.intersect_polygons(fr, op).is_empty():
						front_block.append("%s←%s" % [it["id"], o["id"]])
	check("歩く通り：西・東の通り・中の切れ目・入口の口に足元が入る件 %d %s；屋台・布棚の前 1.6 m（客の立ち場）を塞ぐ件 %d %s" % [in_open.size(), ", ".join(in_open.slice(0, 3)),
		front_block.size(), ", ".join(front_block.slice(0, 3))], in_open.is_empty() and front_block.is_empty())
	# ── M6 構圖：店 ≥ 6（屋台・布棚・筵の 3 形式とも ≥ 2）、同じ店を 2 回使わない、2.2 m 以上の輪郭 ≥ 8、幟 ≥ 4 種・置き看板 ≥ 3 種、裏手の運搬・荷 ≥ 3、廣場の外 6 m を出ない
	var stalls := {}
	var forms := {"yatai": 0, "tana": 0, "mushiro": 0}
	var tall := 0
	var nob := {}
	var kan := {}
	var back := 0
	var outside: Array = []
	for it: Dictionary in items:
		var id := String(it["id"])
		if id in MK.STALL:
			stalls[id] = int(stalls.get(id, 0)) + 1
			for f: String in forms:
				if id.begins_with("mk_" + f):
					forms[f] += 1
		if float(MK.BOX[id][2]) >= MK.TALL:
			tall += 1
		if id.begins_with("mk_nobori"):
			nob[id] = true
		if id.begins_with("mk_kanban"):
			kan[id] = true
		if String(it["tag"]) == "back":
			back += 1
		if not MK.PLAZA.grow(6.0).has_point(it["p"]):
			outside.append(id)
	var dup := stalls.values().any(func(n: int) -> bool: return n > 1)
	var n_st := 0
	for k: String in stalls:
		n_st += int(stalls[k])
	check("構圖：店 %d（屋台 %d・布棚 %d・筵 %d）、同じ店の重複 %s、2.2 m 以上の輪郭 %d、幟 %d 種・置き看板 %d 種、裏手の運搬・荷 %d、廣場の外 6 m 超 %d" % [n_st, forms["yatai"], forms["tana"],
		forms["mushiro"], "あり" if dup else "なし", tall, nob.size(), kan.size(), back, outside.size()],
		n_st >= 14 and forms.values().all(func(n: int) -> bool: return n >= 2) and not dup and tall >= 14 and nob.size() >= 4 and kan.size() >= 3 and back >= 3 and outside.is_empty())
	# ── M7 NPC anchors：≥ 20、各店に売り手＋客、足元・建物・路面の内に立たない（座る anchor は床几・縁台・腰掛けの上で可）、間隔 ≥ 0.5 m
	var by_ref := {}
	var bad_a: Array = []
	for a: Dictionary in anchors:
		var ref := String(a["ref"])
		if not by_ref.has(ref):
			by_ref[ref] = []
		(by_ref[ref] as Array).append(String(a["activity"]))
		var p: Vector2 = a["p"]
		if VL.wall_d(CV, p) < 0.2 or (not is_nan(R.h(p.x, p.y)) and not String(a["activity"]).begins_with("walk")):
			bad_a.append(String(a["id"]))
			continue
		if String(a["activity"]).begins_with("sit") or String(a["activity"]) == "vendor_sit" or String(a["activity"]) == "vendor_stand":
			continue
		for it: Dictionary in items:
			if not (String(it["id"]) in MK.LINE) and Geometry2D.is_point_in_polygon(p, MK.corners(it)):
				bad_a.append("%s∈%s" % [a["id"], it["id"]])
				break
	var lack: Array = []
	for st: String in MK.STALL:
		if not stalls.has(st):
			continue
		var acts: Array = by_ref.get(st, [])
		if not (acts.any(func(s: String) -> bool: return s.begins_with("vendor")) and acts.any(func(s: String) -> bool: return s.begins_with("customer"))):
			lack.append(st)
	var close: Array = []
	for i in anchors.size():
		for j in range(i + 1, anchors.size()):
			if (anchors[i]["p"] as Vector2).distance_to(anchors[j]["p"]) < 0.5:
				close.append("%s×%s" % [anchors[i]["id"], anchors[j]["id"]])
	check("NPC anchors：%d（≥ 20）、売り手＋客の欠けた店 %d %s、足元・建物・路面の内 %d %s、0.5 m 未満の組 %d %s" % [anchors.size(), lack.size(), ", ".join(lack),
		bad_a.size(), ", ".join(bad_a.slice(0, 3)), close.size(), ", ".join(close.slice(0, 3))], anchors.size() >= 20 and lack.is_empty() and bad_a.is_empty() and close.is_empty())


func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not FileAccess.file_exists(MK.OUTPUT):
		push_error("找不到 %s（先 --build 成功才可 attach）" % MK.OUTPUT)
		return 1
	if txt.contains("gen/market_p10.scn"):
		push_error("已經掛過 MarketP10")
		return 1
	var nl := "\r\n" if txt.contains("\r\n") else "\n"
	var lines := txt.split(nl)
	var out := PackedStringArray()
	var done := false
	var i := 0
	while i < lines.size():
		var ln := lines[i]
		out.append(ln)
		if not done and ln.begins_with("[node name=\"Props\" type=\"Node3D\" parent=\".\""):
			i += 1
			while i < lines.size() and not lines[i].begins_with("["):
				out.append(lines[i])
				i += 1
			out.append("[node name=\"MarketP10\" parent=\"Props\" instance=ExtResource(\"p10r1_market\")]")
			out.append("")
			done = true
			continue
		i += 1
	if not done:
		push_error("找不到 Props")
		return 1
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	out.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p10r1_market\"]" % MK.OUTPUT)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[MKT] attach：加 Props/MarketP10 → %s" % SCENE)
	return 0


func _scene(v: Node3D) -> void:
	var txt := FileAccess.get_file_as_string(SCENE)
	var idx: Array = []
	for nm: String in VEG_ORDER:
		idx.append(txt.find("[node name=\"%s\" parent=\"Vegetation\"" % nm))
	var ord_ok: bool = int(idx[0]) >= 0
	for k in range(1, idx.size()):
		ord_ok = ord_ok and int(idx[k]) > int(idx[k - 1])
	var go := v.get_node_or_null(MK.PARENT + "/" + MK.NODE_NAME)
	check("場景已掛 Props/MarketP10（%s）、P9 Vegetation 掛載順序不變（%s）" % [MK.OUTPUT, " → ".join(VEG_ORDER)], go != null and go.scene_file_path == MK.OUTPUT and ord_ok)
	if go == null:
		return
	for i in 4:
		await physics_frame
	var sp := v.get_world_3d().direct_space_state
	var n_i := 0
	var bad: Array = []
	var nolod: Array = []
	for grp in ["Stalls", "Goods", "Signs", "Back"]:
		for n in go.get_node(grp).get_children():
			n_i += 1
			var o := (n as Node3D).global_position
			var q := PhysicsRayQueryParameters3D.create(o + Vector3(0, 30, 0), o + Vector3(0, -10, 0))
			var ex: Array[RID] = []
			var gy := NAN
			for k in 10:
				q.exclude = ex
				var hit := sp.intersect_ray(q)
				if hit.is_empty():
					break
				var cn := String((hit.collider as Node).name)
				if cn.begins_with("TerrainCollision") or (hit.collider as Node).get_parent().name == "Roads" or cn.contains("Road"):
					gy = hit.position.y
					break
				ex.append(hit.rid)
			if is_nan(gy) or absf(gy - o.y) > 0.2:
				bad.append("%s(Δ%s)" % [n.name, "nan" if is_nan(gy) else "%.2f" % (o.y - gy)])
			var l0 := n.get_node_or_null("LOD0") as MeshInstance3D
			var l1 := n.get_node_or_null("LOD1") as MeshInstance3D
			if l0 == null or l1 == null or l0.mesh == null or l1.mesh == null:
				nolod.append(String(n.name))
	check("接地射線：%d 件の原點と地形（衝突體）の差 ≤ 0.20 m 違反 %d %s" % [n_i, bad.size(), ", ".join(bad.slice(0, 3))], bad.is_empty() and n_i >= 30)
	check("LOD：%d 件に LOD0／LOD1 mesh（欠 %d）" % [n_i, nolod.size()], nolod.is_empty())
	var ns := go.get_node("Collision").get_child_count()
	var na := go.get_node("Anchors").get_child_count()
	var grp_ok := go.get_node("Anchors").get_children().all(func(a: Node) -> bool: return a.is_in_group("npc_activity_anchor") and a.has_meta("activity"))
	check("碰撞 %d shapes、NPC anchors %d（group npc_activity_anchor＋activity meta）" % [ns, na], ns >= 25 and na >= 20 and grp_ok)
	var mm := go.find_children("*", "MultiMeshInstance3D", true, false).size()
	check("MultiMesh を使わない（節點ごとに選べる；MMBAKE 対象外）：%d" % mm, mm == 0)


# ─────────────────────────── 封存（--seal，P10 R1 市集廣場 r3 ART_APPROVED 2026-10-04） ───────────────────────────

func _seal_mismatch(seal: Dictionary) -> PackedStringArray:
	var repo := (ProjectSettings.globalize_path("res://") + "..").simplify_path() + "/"
	var docs := repo + "docs/art_review/village_v2_p10_props/"
	var bad := PackedStringArray()
	for grp: String in ["frozen", "art_review_images", "evidence"]:
		var d: Dictionary = seal[grp]
		for k: String in d:
			var path: String = (repo + k) if grp == "frozen" else (docs + k)
			if not FileAccess.file_exists(path):
				bad.append("%s 不存在" % k)
			elif FileAccess.get_sha256(path) != String(d[k]):
				bad.append("%s 雜湊變了" % k)
	return bad


func _seal() -> int:
	var seal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SEAL))
	var bad := _seal_mismatch(seal)
	var n: int = seal["frozen"].size() + seal["art_review_images"].size() + seal["evidence"].size()
	check("P10 R1 封存 %d 檔雜湊一致（凍結 %d、ART_REVIEW 圖 %d、證據 %d；不符 %d：%s）" % [n, seal["frozen"].size(),
		seal["art_review_images"].size(), seal["evidence"].size(), bad.size(), ", ".join(bad.slice(0, 4))], bad.is_empty())
	var txt := FileAccess.get_file_as_string(SCENE)
	var idx: Array = []
	for nm: String in VEG_ORDER:
		idx.append(txt.find("[node name=\"%s\" parent=\"Vegetation\"" % nm))
	var ord_ok: bool = int(idx[0]) >= 0
	for k in range(1, idx.size()):
		ord_ok = ord_ok and int(idx[k]) > int(idx[k - 1])
	var mk_line := "[node name=\"MarketP10\" parent=\"Props\" instance=ExtResource(\"p10r1_market\")]"
	check("village_v2.tscn 掛載 Props/MarketP10 恰 1 個（%s）、P9 Vegetation 掛載順序不變" % MK.OUTPUT,
		txt.count(mk_line) == 1 and txt.contains(MK.OUTPUT) and ord_ok)
	var neg_seal := seal.duplicate(true)
	var k0: String = neg_seal["frozen"].keys()[0]
	neg_seal["frozen"][k0] = "0".repeat(64)
	var nb := _seal_mismatch(neg_seal)
	check("反向：竄改 %s 期望雜湊 → 偵測到 1 筆不符（實際 %d）" % [k0, nb.size() - bad.size()], nb.size() == bad.size() + 1)
	print("[MKT] 結果：%d 項失敗（seal）" % fails)
	return fails
