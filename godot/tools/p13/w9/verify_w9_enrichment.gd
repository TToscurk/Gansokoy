extends SceneTree
## P13 W9 gate：EnrichW9P13 を「保存された場景」から読み戻して独立に検査する（掛載・実体・配置・接地・碰撞・予算）＋ 反向案例。
##   godot --headless --path godot --script res://tools/p13/w9/verify_w9_enrichment.gd
## 計画段階の規則（W9.why）を、焼いた後のノードの実座標で再評価する：道・建物・戸口・水・田・封存物・NPC の動線に触れていないこと。
## MultiMesh なし（headless 可）。meadow（立ち草）の回避は計画時のみ（キャッシュ依存のため gate では検査しない）。
const W9 := preload("res://tools/p13/w9/w9_lib.gd")
const SL := preload("res://tools/village_v2_street_lib.gd")

const MIN_ZONE := {"R": 100, "M": 20, "F": 40}
const MAX_TRI_LOD0 := 450000
const MAX_MESH := 700
const MAX_SHAPES := 120

var passed := 0
var failed := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("[W9G] PASS ", msg)
	else:
		failed += 1
		print("[W9G] FAIL ", msg)


func _init() -> void:
	_run.call_deferred()


func _items(own: Node3D) -> Array:
	var out: Array = []
	for z in own.get_children():
		if not String(z.name).begins_with("Zone"):
			continue
		for cl in z.get_children():
			for n in cl.get_children():
				if n is Node3D and n.has_meta("w9_id"):
					out.append(n)
	return out


## ノード → W9 の item 辞書（world xz・yaw・scale・flags）
func _rec(n: Node3D) -> Dictionary:
	var gt := n.global_transform
	var bz := gt.basis.z
	var it := {"id": String(n.get_meta("w9_id")), "p": Vector2(gt.origin.x, gt.origin.z), "yaw": atan2(bz.x, bz.z), "y": gt.origin.y,
		"sx": gt.basis.x.length(), "sy": gt.basis.y.length(), "sz": gt.basis.z.length(), "b": String(n.get_meta("w9_b", "")), "mode": String(n.get_meta("w9_mode", "ground"))}
	for f in String(n.get_meta("w9_flags", "")).split(",", false):
		it[f] = true
	return it


func _why_mode(it: Dictionary) -> String:
	if bool(it.get("soft", false)):
		return "soft"
	var m := String(it.get("mode", "ground"))
	return "wall" if (m == "wall" or m == "gap") else "ground"


## 1 件の検査：置けない理由（"" なら適合）。接地も含む
func _check(C: Dictionary, it: Dictionary) -> String:
	var w := W9.why(C, it, [], _why_mode(it))
	if w != "":
		return w
	var hang := bool(it.get("hang", false))
	var gy := W9.ground_y(C, it)
	if not hang:
		if absf(float(it["y"]) - gy) > 0.10:
			return "float(%.2f vs ground %.2f)" % [float(it["y"]), gy]
	elif String(it.get("b", "")) != "":
		var fy := float((C["bld_y"] as Dictionary).get(String(it["b"]), 0.0)) + W9.FLOOR_Y
		var dy := float(it["y"]) - fy
		if dy < -0.7 or dy > 2.2:
			return "hang_height(%.2f)" % dy
	elif absf(float(it["y"]) - gy) > 0.15:
		return "hang_float(%.2f)" % (float(it["y"]) - gy)
	return ""


func _rect_poly(cs: CollisionShape3D) -> PackedVector2Array:
	var bx := cs.shape as BoxShape3D
	var gt := cs.global_transform
	var h := bx.size * 0.5
	var pts := PackedVector2Array()
	for sg in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var q := gt * Vector3(h.x * sg.x, 0.0, h.z * sg.y)
		pts.append(Vector2(q.x, q.z))
	return pts


## 碰撞箱が戸口の空け帯・NPC の巡回路に触れていないか
func _coll_bad(C: Dictionary, poly: PackedVector2Array) -> String:
	var c := Vector2.ZERO
	for q in poly:
		c += q
	c /= float(poly.size())
	for b: Dictionary in C["bld"]:
		if (b["o"] as Vector2).distance_to(c) < 14.0:
			for g: PackedVector2Array in Geometry2D.offset_polygon(SL.door_poly(b), 0.02):
				if not Geometry2D.intersect_polygons(poly, g).is_empty():
					return "door(%s)" % String(b["name"])
	for pts: PackedVector2Array in C["npc_paths"]:
		for k in range(1, pts.size()):
			for q in poly:
				if Geometry2D.get_closest_point_to_segment(q, pts[k - 1], pts[k]).distance_to(q) < 0.35:
					return "npc_path"
	return ""


func _run() -> void:
	var v: Node3D = (load(W9.SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 3:
		await physics_frame
	# ── 掛載
	var owns := v.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with(W9.NODE_NAME))
	_ok(owns.size() == 1, "EnrichW9P13 は village_v2 の root に 1 つだけ掛かっている（%d）" % owns.size())
	var own := v.get_node_or_null(W9.NODE_NAME) as Node3D
	if own == null:
		print("[W9G] 結果：掛載なし")
		quit(1)
		return
	var after := v.get_node_or_null(W9.AFTER)
	_ok(after != null and own.get_index() > after.get_index(), "掛載順：%s の後（index %d > %d）" % [W9.AFTER, own.get_index(), after.get_index() if after else -1])
	var nodes := _items(own)
	_ok(nodes.size() == int(own.get_meta("items", -1)) and nodes.size() > 0, "烘焙した件数と meta items が一致（%d）" % nodes.size())
	# ── 文書化・多様性
	var by_zone := {}
	var by_id := {}
	var undocumented := 0
	for n in nodes:
		var zid := String(n.get_meta("w9_zone")).substr(0, 1)
		by_zone[String(n.get_parent().get_parent().name)] = int(by_zone.get(String(n.get_parent().get_parent().name), 0)) + 1
		by_id[String(n.get_meta("w9_id"))] = int(by_id.get(String(n.get_meta("w9_id")), 0)) + 1
		if String(n.get_meta("w9_who")) == "" or String(n.get_meta("w9_why")) == "" or not (String(n.get_meta("w9_kind")) in ["new", "reuse"]):
			undocumented += 1
		if zid == "":
			undocumented += 1
	_ok(undocumented == 0, "全構件に who／why（用途の理由）と kind（new／reuse）がある（欠落 %d）" % undocumented)
	for z: String in MIN_ZONE:
		var cnt := int(by_zone.get("Zone" + z, 0))
		_ok(cnt >= int(MIN_ZONE[z]), "区域 %s の構件数 %d ≥ %d" % [z, cnt, MIN_ZONE[z]])
	var top := 0
	var top_id := ""
	for k: String in by_id:
		if int(by_id[k]) > top:
			top = int(by_id[k])
			top_id = k
	_ok(by_id.size() >= 20 and float(top) / float(nodes.size()) <= 0.25, "種類の多様性：%d 種・最多 %s %d 件（%.0f %% ≤ 25 %%）" % [by_id.size(), top_id, top, 100.0 * top / nodes.size()])
	# ── 予算
	var tri := 0
	var mesh := 0
	var mats := {}
	for mi in own.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		mesh += 1
		if g.visibility_range_begin <= 0.001 and g.mesh != null:
			for s in g.mesh.get_surface_count():
				var arrays := g.mesh.surface_get_arrays(s)
				var idx = arrays[Mesh.ARRAY_INDEX]
				tri += (idx.size() if idx != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		if g.mesh != null:
			for s in g.mesh.get_surface_count():
				var m := g.mesh.surface_get_material(s)
				if m != null:
					mats[m.resource_path] = true
	var shapes := own.find_children("*", "CollisionShape3D", true, false)
	var mm := own.find_children("*", "MultiMeshInstance3D", true, false)
	print("[W9G] INFO LOD0 三角面 %d・MeshInstance %d・材質 %d 種・碰撞箱 %d・MultiMesh %d" % [tri, mesh, mats.size(), shapes.size(), mm.size()])
	_ok(tri <= MAX_TRI_LOD0 and mesh <= MAX_MESH and shapes.size() <= MAX_SHAPES, "予算：LOD0 %d ≤ %d・Mesh %d ≤ %d・碰撞箱 %d ≤ %d" % [tri, MAX_TRI_LOD0, mesh, MAX_MESH, shapes.size(), MAX_SHAPES])
	_ok(mm.is_empty(), "MultiMesh なし（headless 烘焙の零行列問題の対象外）")
	# ── 配置の再評価（自分自身を外して context を作る）
	v.remove_child(own)
	var C := W9.context(v, PackedVector2Array())
	v.add_child(own)
	var bad := 0
	var bad_msgs: Array = []
	for n in nodes:
		var it := _rec(n)
		var w := _check(C, it)
		if w != "":
			bad += 1
			if bad_msgs.size() < 20:
				bad_msgs.append("%s@(%.1f,%.1f) %s [%s]" % [it["id"], it["p"].x, it["p"].y, w, String(n.get_meta("w9_cluster"))])
	for m in bad_msgs:
		print("[W9G]   不適合 ", m)
	_ok(bad == 0, "全 %d 構件が道・建物・戸口・水・田・封存物・NPC 動線・Hero に触れず、接地している（不適合 %d）" % [nodes.size(), bad])
	# 構件同士の重なり（低い植物 nov は除く）
	var ov := 0
	for i in nodes.size():
		var a := _rec(nodes[i])
		if bool(a.get("nov", false)):
			continue
		for j in range(i + 1, nodes.size()):
			var b := _rec(nodes[j])
			if bool(b.get("nov", false)) or (a["p"] as Vector2).distance_to(b["p"]) > 6.0:
				continue
			if bool(a.get("hang", false)) != bool(b.get("hang", false)):
				continue
			var inter := Geometry2D.intersect_polygons(W9.foot(a), W9.foot(b))
			if not inter.is_empty():
				var area := 0.0
				for pl: PackedVector2Array in inter:
					for k in range(pl.size()):
						area += pl[k].cross(pl[(k + 1) % pl.size()]) * 0.5
				if absf(area) > 0.02:
					ov += 1
					if ov <= 5:
						print("[W9G]   重なり %s × %s @(%.1f,%.1f) %.2f m²" % [a["id"], b["id"], a["p"].x, a["p"].y, absf(area)])
	_ok(ov == 0, "構件同士が重ならない（重なり %d）" % ov)
	# ── 碰撞：戸口の空け帯・巡回路に触れない
	var cbad := 0
	for cs in shapes:
		var r := _coll_bad(C, _rect_poly(cs as CollisionShape3D))
		if r != "":
			cbad += 1
			if cbad <= 5:
				print("[W9G]   碰撞不適合 %s %s" % [cs.name, r])
	_ok(cbad == 0, "碰撞箱 %d 個が戸口の空け帯と NPC の巡回路に触れない（%d）" % [shapes.size(), cbad])
	# ── 反向案例（gate が本当に落ちる）
	var bld0: Dictionary = (C["bld"] as Array)[0]
	var sample := _rec(nodes[0])
	sample["hang"] = false
	sample.erase("band")
	# N1 建物の中
	var n1 := sample.duplicate()
	n1["id"] = "w9_ueki_tana"
	n1["p"] = bld0["o"]
	n1["mode"] = "ground"
	n1["y"] = W9.top_h(C, n1["p"])
	_ok(_check(C, n1).begins_with("inside_building") or _check(C, n1) == "building", "反向：建物の中に置いた構件は落ちる（%s）" % _check(C, n1))
	# N2 道の上
	var n2 := sample.duplicate()
	n2["id"] = "w9_ueki_tana"
	n2["mode"] = "ground"
	var road_pt := Vector2(236.0, 20.0)       # 主街の中央
	n2["p"] = road_pt
	n2["y"] = W9.top_h(C, road_pt)
	_ok(_check(C, n2) != "", "反向：主街の路面に置いた構件は落ちる（%s）" % _check(C, n2))
	# N3 戸口の前
	var n3 := sample.duplicate()
	n3["id"] = "w9_ueki_tana"
	n3["mode"] = "ground"
	var dp := SL.door_poly(bld0)
	var dc := (dp[0] + dp[1] + dp[2] + dp[3]) * 0.25
	n3["p"] = dc
	n3["y"] = W9.top_h(C, dc)
	_ok(_check(C, n3) != "", "反向：戸口の前に置いた構件は落ちる（%s）" % _check(C, n3))
	# N4 田の中（P8）
	var n4 := sample.duplicate()
	n4["id"] = "w9_kakashi"
	n4["mode"] = "ground"
	n4["p"] = Vector2(335.0, 86.0)
	n4["y"] = W9.top_h(C, n4["p"])
	_ok(_check(C, n4) != "", "反向：P8 の田の中に置いた構件は落ちる（%s）" % _check(C, n4))
	# N5 浮き
	var n5 := _rec(nodes[nodes.size() - 1])
	for k in nodes.size():
		var cand := _rec(nodes[k])
		if not bool(cand.get("hang", false)) and _check(C, cand) == "":
			n5 = cand
			break
	n5["y"] = float(n5["y"]) + 0.5
	_ok(_check(C, n5).begins_with("float"), "反向：地面から 0.5 m 浮いた構件は落ちる（%s）" % _check(C, n5))
	# N6 二重掛載
	var dup := own.duplicate()
	dup.name = W9.NODE_NAME + "_dup"
	v.add_child(dup)
	var owns2 := v.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with(W9.NODE_NAME))
	_ok(owns2.size() == 2, "反向：二重掛載は件数 2 として検出できる（%d）" % owns2.size())
	v.remove_child(dup)
	dup.free()
	# N7 戸口をまたぐ碰撞箱
	var fake := PackedVector2Array([dc + Vector2(-0.3, -0.3), dc + Vector2(0.3, -0.3), dc + Vector2(0.3, 0.3), dc + Vector2(-0.3, 0.3)])
	_ok(_coll_bad(C, fake) != "", "反向：戸口の空け帯にかかる碰撞箱は落ちる（%s）" % _coll_bad(C, fake))
	print("[W9G] PASS %d  FAIL %d" % [passed, failed])
	print("[W9G] 結果：%d 項失敗" % failed)
	quit(1 if failed > 0 else 0)
