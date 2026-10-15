extends SceneTree
## P13 W9 Phase 3 gate：EnrichW9P3（B3 住宅巷の庭木・板塀／C3 農家の屋敷林・竹・生垣・菜園・柴棚・路肩）を「保存された場景」から読み戻して独立に検査 ＋ 反向案例。
##   godot --headless --path godot --script res://tools/p13/w9/verify_w9p3.gd
## 計画段階の規則（W9.why）を焼いた後のノードの実座標で再評価する。さらに『設計の意図』を数値で守る：
##   屋敷林（高木 ≥ 5・樹種 ≥ 6・同種 ≤ 35 %）／竹叢（≥ 8 本）／生垣（高さ ≤ 1.8 m・途中に ≥ 2.2 m の切れ目）／菜園（畝 ≥ 3＋竹垣 ≥ 3）／柴棚 1／路肩の木 ≥ 3 と低木群。
## MultiMesh なし（headless 可）。meadow（立ち草）の回避は計画時のみ。
const P3 := preload("res://tools/p13/w9/w9p3_lib.gd")
const W9 := preload("res://tools/p13/w9/w9_lib.gd")
const SL := preload("res://tools/village_v2_street_lib.gd")
const HU := preload("res://tools/village_v2_human_use_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")

const MIN_ZONE := {"B3": 12, "C3": 55}
const MAX_TRI_LOD0 := 300000
const MAX_MESH := 900
const MAX_SHAPES := 80
const A1 := Vector2(318.0, 82.0)
const A2 := Vector2(323.0, 71.0)
const HEDGE_MAX_H := 1.8
const HEDGE_GAP_MIN := 2.2
const TREE_MIN_H := 8.0

## R1（0fdea17・bce7cf4）の農路の南の路肩：同じ配合の群れ 4 つ（反向案例の固定データ＝p3_environment_plan の C3_road・z ≥ 72・x 333–359）
const R1_VERGE := [
	{"id": "shrub_a", "p": Vector2(334.7, 75.3), "sx": 1.40, "sy": 1.43},
	{"id": "sasa_a", "p": Vector2(335.2, 73.0), "sx": 1.21, "sy": 1.21},
	{"id": "sasa_a", "p": Vector2(335.2, 74.3), "sx": 1.50, "sy": 1.46},
	{"id": "shrub_a", "p": Vector2(336.7, 74.3), "sx": 1.30, "sy": 1.36},
	{"id": "shrub_a", "p": Vector2(340.2, 75.6), "sx": 1.30, "sy": 1.31},
	{"id": "shrub_a", "p": Vector2(340.9, 74.2), "sx": 1.04, "sy": 1.02},
	{"id": "tsutsuji_a", "p": Vector2(342.5, 74.9), "sx": 1.00, "sy": 0.96},
	{"id": "shrub_a", "p": Vector2(342.6, 73.8), "sx": 1.22, "sy": 1.29},
	{"id": "young_broad_b", "p": Vector2(348.5, 76.0), "sx": 1.10, "sy": 1.16},
	{"id": "tsutsuji_a", "p": Vector2(348.7, 73.9), "sx": 1.45, "sy": 1.51},
	{"id": "tsutsuji_a", "p": Vector2(349.6, 75.3), "sx": 1.38, "sy": 1.37},
	{"id": "tsutsuji_a", "p": Vector2(350.1, 73.3), "sx": 1.01, "sy": 1.06},
	{"id": "fern_a", "p": Vector2(350.8, 75.9), "sx": 1.42, "sy": 1.35},
	{"id": "sasa_a", "p": Vector2(351.5, 73.3), "sx": 1.43, "sy": 1.38},
	{"id": "shrub_a", "p": Vector2(354.4, 73.7), "sx": 1.20, "sy": 1.17},
	{"id": "sasa_a", "p": Vector2(355.1, 73.1), "sx": 1.04, "sy": 1.09},
	{"id": "shrub_a", "p": Vector2(355.2, 74.6), "sx": 1.10, "sy": 1.16},
	{"id": "shrub_a", "p": Vector2(356.0, 74.9), "sx": 1.13, "sy": 1.10},
	{"id": "tsutsuji_a", "p": Vector2(357.1, 74.0), "sx": 1.32, "sy": 1.39},
]

var passed := 0
var failed := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("[W9P3G] PASS ", msg)
	else:
		failed += 1
		print("[W9P3G] FAIL ", msg)


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


func _rec(n: Node3D) -> Dictionary:
	var gt := n.global_transform
	var bz := gt.basis.z
	var it := {"id": String(n.get_meta("w9_id")), "p": Vector2(gt.origin.x, gt.origin.z), "yaw": atan2(bz.x, bz.z), "y": gt.origin.y,
		"sx": gt.basis.x.length(), "sy": gt.basis.y.length(), "sz": gt.basis.z.length(), "b": "", "mode": String(n.get_meta("w9_mode", "ground")),
		"zone": String(n.get_meta("w9_zone", "")), "cluster": String(n.get_meta("w9_cluster", ""))}
	for f in String(n.get_meta("w9_flags", "")).split(",", false):
		it[f] = true
	return it


func _why_mode(it: Dictionary) -> String:
	if bool(it.get("soft", false)):
		return "soft"
	return "ground"


func _check(C: Dictionary, it: Dictionary) -> String:
	var w := W9.why(C, it, [], _why_mode(it))
	if w != "":
		return w
	var gy := W9.ground_y(C, it)
	if absf(float(it["y"]) - gy) > 0.12:
		return "float(%.2f vs ground %.2f)" % [float(it["y"]), gy]
	return ""


func _rect_poly(cs: CollisionShape3D) -> PackedVector2Array:
	var gt := cs.global_transform
	var h := Vector3(0.2, 1.0, 0.2)
	if cs.shape is BoxShape3D:
		h = (cs.shape as BoxShape3D).size * 0.5
	elif cs.shape is CylinderShape3D:
		var r := (cs.shape as CylinderShape3D).radius
		h = Vector3(r, 1.0, r)
	var pts := PackedVector2Array()
	for sg in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var q := gt * Vector3(h.x * sg.x, 0.0, h.z * sg.y)
		pts.append(Vector2(q.x, q.z))
	return pts


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


## 樹種の多様性：種類 ≥ 6 かつ最多の割合 ≤ 35 %
static func variety_ok(ids: Array) -> bool:
	var cnt := {}
	for id in ids:
		cnt[id] = int(cnt.get(id, 0)) + 1
	if cnt.size() < 6:
		return false
	var top := 0
	for k in cnt:
		top = maxi(top, int(cnt[k]))
	return float(top) / float(ids.size()) <= 0.35


## 生垣に切れ目があるか：並び順の z の最大の隙間 ≥ min_gap
static func hedge_gap_ok(zs: Array, min_gap: float) -> bool:
	var a := zs.duplicate()
	a.sort()
	var best := 0.0
	for i in range(1, a.size()):
		best = maxf(best, float(a[i]) - float(a[i - 1]))
	return best >= min_gap


func _run() -> void:
	var v: Node3D = (load(P3.SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 3:
		await physics_frame
	P3.register_dims()
	# ── 掛載
	var txt := FileAccess.get_file_as_string(P3.SCENE)
	var ext_line := "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p13w9p3_enrich\"]" % P3.OUTPUT
	var node_line := "[node name=\"%s\" parent=\".\" instance=ExtResource(\"p13w9p3_enrich\")]" % P3.NODE_NAME
	_ok(txt.count(ext_line) == 1 and txt.count(node_line) == 1, "保存された village_v2.tscn に ext_resource 1＋node 1 だけ掛かっている（%d＋%d）" % [txt.count(ext_line), txt.count(node_line)])
	var order: PackedStringArray = []
	for l: String in txt.split("\n"):
		if l.begins_with("[node name=\"") and l.contains("parent=\".\""):
			order.append(l.split("\"")[1])
	_ok(order.find(P3.NODE_NAME) == order.find(P3.AFTER) + 1 and order.find(P3.AFTER) >= 0, "%s は %s の直後（順序）" % [P3.NODE_NAME, P3.AFTER])
	for keep in ["EnrichW9P13", "ArchW9R2P13", "FarmsteadP13", "MeadowP9", "EnvironmentP9", "HumanUseP10"]:
		_ok(order.has(keep) or v.get_node_or_null(keep) != null or v.get_node_or_null("Vegetation/" + keep) != null or v.get_node_or_null("Props/" + keep) != null, "既存 overlay %s は残っている" % keep)
	var owns := v.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with(P3.NODE_NAME))
	_ok(owns.size() == 1, "EnrichW9P3 は root に 1 つだけ（%d）" % owns.size())
	var own := v.get_node_or_null(P3.NODE_NAME) as Node3D
	if own == null:
		print("[W9P3G] 結果：掛載なし")
		quit(1)
		return
	var nodes := _items(own)
	_ok(nodes.size() == int(own.get_meta("items", -1)) and nodes.size() > 0, "烘焙した件数と meta items が一致（%d）" % nodes.size())
	# ── 文書化・区域
	var by_zone := {}
	var undocumented := 0
	for n in nodes:
		var zname := String(n.get_parent().get_parent().name).trim_prefix("Zone")
		by_zone[zname] = int(by_zone.get(zname, 0)) + 1
		if String(n.get_meta("w9_who")) == "" or String(n.get_meta("w9_why")) == "" or not (String(n.get_meta("w9_kind")) in ["new", "reuse"]):
			undocumented += 1
	_ok(undocumented == 0, "全構件に who／why と kind（new／reuse）がある（欠落 %d）" % undocumented)
	for z: String in MIN_ZONE:
		_ok(int(by_zone.get(z, 0)) >= int(MIN_ZONE[z]), "区域 %s の構件数 %d ≥ %d" % [z, int(by_zone.get(z, 0)), MIN_ZONE[z]])
	var recs: Array = []
	for n in nodes:
		recs.append(_rec(n))
	# ── 設計の意図（数値）
	var c3_trees: Array = []
	var belt := 0
	var bamboo := 0
	var hedge_zs: Array = []
	var hedge_hmax := 0.0
	var hatake := 0
	var fences := 0
	var sheds: Array = []
	var verge_trees := 0
	var verge_plants := 0
	var tall := 0
	for it: Dictionary in recs:
		var id := String(it["id"])
		var p: Vector2 = it["p"]
		var isC := String(it["cluster"]).begins_with("C3")
		if isC and (P3.TREES.has(id) or id.begins_with("young_broad")):
			c3_trees.append(id)
		if isC and P3.TREES.has(id) and P3.tree_h(id) * float(it["sy"]) >= TREE_MIN_H and p.distance_to(A1) <= 16.0:
			belt += 1
		if P3.BAMBOO.has(id) and p.distance_to(Vector2(311.8, 94.5)) <= 3.5:
			bamboo += 1
		if String(it["cluster"]) == "C3_hedge":
			hedge_zs.append(p.y if (p.y <= 92.2 and p.x >= 327.0) else p.x + 1000.0)       # 東縁は z、南縁は別の系（+1000）で見る
			var hd: Array = W9.dims(id)
			hedge_hmax = maxf(hedge_hmax, float(hd[4]) * float(it["sy"]))
		if id == "hx_hatake" and p.x >= 313.0 and p.x <= 324.0 and p.y >= 88.0 and p.y <= 94.0:
			hatake += 1
		if id == "w9_takegaki" and String(it["cluster"]) == "C3_garden":
			fences += 1
		if id == "farm_shed":
			sheds.append(it)
		if String(it["cluster"]) == "C3_road":
			if P3.TREES.has(id) or id.begins_with("young_broad"):
				verge_trees += 1
			else:
				verge_plants += 1
		if P3.TREES.has(id) and P3.tree_h(id) * float(it["sy"]) >= TREE_MIN_H:
			tall += 1
	_ok(belt >= 5, "屋敷林：主屋 A1 から 16 m 以内に高さ ≥ %.0f m の樹が %d 本（≥ 5）" % [TREE_MIN_H, belt])
	_ok(variety_ok(c3_trees), "C3 の樹種：%d 種・同種の最多 ≤ 35 %%（%s）" % [(c3_trees as Array).size(), str(c3_trees.size())])
	_ok(bamboo >= 8, "屋敷竹：竹叢の本数 %d ≥ 8" % bamboo)
	var east_zs: Array = hedge_zs.filter(func(z: float) -> bool: return z < 1000.0)
	_ok(east_zs.size() >= 6 and hedge_gap_ok(east_zs, HEDGE_GAP_MIN), "生垣（東縁）：%d 株・途中に ≥ %.1f m の切れ目（茅葺きの正面を隠さない）" % [east_zs.size(), HEDGE_GAP_MIN])
	_ok(hedge_hmax > 0.0 and hedge_hmax <= HEDGE_MAX_H, "生垣の最大高 %.2f m ≤ %.1f m" % [hedge_hmax, HEDGE_MAX_H])
	_ok(hatake >= 3 and fences >= 3, "菜園：畝 %d ≥ 3・竹垣 %d ≥ 3" % [hatake, fences])
	_ok(sheds.size() == 1 and (sheds[0]["p"] as Vector2).distance_to(A2) <= 12.0, "柴棚 B_P_FARM_SHED が 1 棟・納屋 A2 の近く（%d）" % sheds.size())
	_ok(verge_trees >= 3 and verge_plants >= 20, "農路の路肩：木 %d ≥ 3・低木と笹の群れ %d ≥ 20" % [verge_trees, verge_plants])
	# ── R2（使用者 2026-10-15 ART_REVIEW ACCEPTED の局所調整）：cT4 の前景樹・cT7 の南の路肩
	var c3_recs: Array = recs.filter(func(it: Dictionary) -> bool: return String(it["cluster"]).begins_with("C3"))
	var cam_trees: Array = P3.cam_in_crown(c3_recs, P3.CT4_CAM)
	_ok(cam_trees.is_empty(), "cT4：相機 (%.1f, %.1f, %.1f) が C3 の樹冠の中・すぐ脇にない（%s）" % [P3.CT4_CAM.x, P3.CT4_CAM.y, P3.CT4_CAM.z, str(cam_trees)])
	var view: Dictionary = P3.ct4_view(c3_recs)
	_ok(float(view["farm"]) <= P3.CT4_BLOCK_MAX and float(view["canal"]) <= P3.CT4_BLOCK_MAX, "cT4：相機から農舎 A1（北の壁面 %d 点）への視線の遮られ率 %.0f %%・運河（%d 点）%.0f %% ≤ %.0f %%（%s）" % [int(view["farm_n"]), 100.0 * float(view["farm"]), int(view["canal_n"]), 100.0 * float(view["canal"]), 100.0 * P3.CT4_BLOCK_MAX, str(view["who"])])
	var vc: Dictionary = P3.verge_check(c3_recs.filter(func(it: Dictionary) -> bool: return String(it["cluster"]) == "C3_road"))
	print("[W9P3G]   路肩（南）の群れ：", JSON.stringify((vc["G"] as Array).map(func(g: Dictionary) -> Dictionary: return {"x": "%.1f–%.1f" % [g["x0"], g["x1"]], "w": snappedf(float(g["w"]), 0.1), "tall": snappedf(float(g["tall"]), 0.1), "ids": g["ids"]})), " 隙間 ", str((vc["gaps"] as Array).map(func(x: float) -> float: return snappedf(x, 0.1))))
	_ok(bool(vc["ok"]), "cT7 の左（南の路肩）：群れ %d・最大の帯 %.1f m ≤ %.1f・切れ目（≥ %.1f m）%d ≥ 3・隣と同配合 %d・種類 %d ≥ 5・高い群 %d・低い群 %d（%s）" % [int(vc["groups"]), float(vc["widest"]), P3.VERGE_WIDE_MAX, P3.VERGE_GAP_MIN, int(vc["open_gaps"]), int(vc["same_adj"]), int(vc["species"]), int(vc["tall"]), int(vc["low"]), str(vc["why"])])
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
	print("[W9P3G] INFO LOD0 三角面 %d・MeshInstance %d・材質 %d 種・碰撞箱 %d・MultiMesh %d・高木 %d" % [tri, mesh, mats.size(), shapes.size(), mm.size(), tall])
	_ok(tri <= MAX_TRI_LOD0 and mesh <= MAX_MESH and shapes.size() <= MAX_SHAPES, "予算：LOD0 %d ≤ %d・Mesh %d ≤ %d・碰撞箱 %d ≤ %d" % [tri, MAX_TRI_LOD0, mesh, MAX_MESH, shapes.size(), MAX_SHAPES])
	_ok(mm.is_empty(), "MultiMesh なし（headless 烘焙の零行列問題の対象外）")
	# ── 配置の再評価（自分自身を外して context を作る）
	v.remove_child(own)
	var C := W9.context(v, PackedVector2Array())
	var r1 := v.get_node_or_null("EnrichW9P13")
	var r1_rects: Array = []
	if r1 != null:
		for mi in r1.find_children("*", "MeshInstance3D", true, false):
			var g2 := mi as MeshInstance3D
			if g2.mesh == null or g2.visibility_range_begin > 0.001:
				continue
			var rr: Rect2 = HU._rect_of(g2, v)
			if rr.size.x <= 12.0 and rr.size.y <= 12.0:
				r1_rects.append(rr)
	v.add_child(own)
	var bad := 0
	var bad_msgs: Array = []
	var near_road := 0
	var on_r1 := 0
	for it: Dictionary in recs:
		var w := _check(C, it)
		if w != "":
			bad += 1
			if bad_msgs.size() < 20:
				bad_msgs.append("%s@(%.1f,%.1f) %s [%s]" % [it["id"], it["p"].x, it["p"].y, w, it["cluster"]])
		# 路面：中心から 0.6 m の輪の 8 点が路面に乗らない（樹・低木が道を塞がない）
		var Rr: RLib.TriSampler = C["R"]
		var p2: Vector2 = it["p"]
		var onroad := false
		for k in 8:
			var q := p2 + Vector2.from_angle(TAU * k / 8.0) * 0.6
			if not is_nan(Rr.h(q.x, q.y)):
				onroad = true
		if onroad and P3.is_plant(String(it["id"])):
			near_road += 1
		if not P3.is_plant(String(it["id"])):
			var fp := W9.foot(it)
			var fr := Rect2(fp[0], Vector2.ZERO)
			for q in fp:
				fr = fr.expand(q)
			for rr2: Rect2 in r1_rects:
				if fr.grow(0.05).intersects(rr2):
					on_r1 += 1
					print("[W9P3G]   R1 と重なる地面物 %s@(%.1f,%.1f) rect=%s" % [it["id"], p2.x, p2.y, str(rr2)])
					break
	for m in bad_msgs:
		print("[W9P3G]   不適合 ", m)
	_ok(bad == 0, "全 %d 構件が道・建物・戸口・水・田・封存物・NPC 動線・Hero に触れず、接地している（不適合 %d）" % [recs.size(), bad])
	_ok(near_road == 0, "樹・竹・低木は路面の縁から 0.6 m 以内に乗らない（%d）" % near_road)
	_ok(on_r1 == 0, "地面物（畝・垣・小屋）が W9 R1 の構件と重ならない（%d）" % on_r1)
	# 構件同士の重なり
	var ov := 0
	for i in recs.size():
		var a: Dictionary = recs[i]
		if bool(a.get("nov", false)):
			continue
		for j in range(i + 1, recs.size()):
			var b: Dictionary = recs[j]
			if bool(b.get("nov", false)) or (a["p"] as Vector2).distance_to(b["p"]) > 8.0:
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
						print("[W9P3G]   重なり %s × %s @(%.1f,%.1f) %.2f m²" % [a["id"], b["id"], a["p"].x, a["p"].y, absf(area)])
	_ok(ov == 0, "構件同士が重ならない（重なり %d）" % ov)
	# ── 碰撞
	var cbad := 0
	for cs in shapes:
		var r := _coll_bad(C, _rect_poly(cs as CollisionShape3D))
		if r != "":
			cbad += 1
			if cbad <= 5:
				print("[W9P3G]   碰撞不適合 %s %s" % [cs.name, r])
	_ok(cbad == 0, "碰撞箱 %d 個が戸口の空け帯と NPC の巡回路に触れない（%d）" % [shapes.size(), cbad])
	var shed_shapes := 0
	for cs in shapes:
		if String(cs.name).contains("farm_shed"):
			shed_shapes += 1
	_ok(shed_shapes >= 8, "柴棚の碰撞箱 %d ≥ 8（奥壁 4＋西壁 2＋前の柱 3）" % shed_shapes)
	var trunk_shapes := 0
	for cs in shapes:
		if (cs as CollisionShape3D).shape is CylinderShape3D:
			trunk_shapes += 1
	var n_trees := 0
	for it: Dictionary in recs:
		if P3.TREES.has(String(it["id"])):
			n_trees += 1
	_ok(trunk_shapes == n_trees and n_trees > 0, "高木の幹の碰撞（円柱 %d）が樹の本数（%d）と一致" % [trunk_shapes, n_trees])
	# ── 反向案例（gate が本当に落ちる）
	var sample: Dictionary = recs[0].duplicate()
	sample["hang"] = false
	# N1 道の上の樹
	var n1 := sample.duplicate()
	n1["id"] = "momiji_a"
	n1["soft"] = true
	n1["mode"] = "soft"
	n1["p"] = Vector2(236.0, 20.0)
	n1["y"] = W9.top_h(C, n1["p"])
	_ok(_check(C, n1) != "", "反向：主街の路面に置いた樹は落ちる（%s）" % _check(C, n1))
	# N2 田（P8）の中の畝
	var n2 := sample.duplicate()
	n2["id"] = "hx_hatake"
	n2["mode"] = "ground"
	n2.erase("soft")
	n2["p"] = Vector2(335.0, 86.0)
	n2["y"] = W9.top_h(C, n2["p"])
	_ok(_check(C, n2) != "", "反向：P8 の田の中に置いた畝は落ちる（%s）" % _check(C, n2))
	# N3 建物の中の小屋
	var bld0: Dictionary = (C["bld"] as Array)[0]
	var n3 := sample.duplicate()
	n3["id"] = "farm_shed"
	n3["mode"] = "ground"
	n3.erase("soft")
	n3["p"] = bld0["o"]
	n3["yaw"] = 0.0
	n3["y"] = W9.top_h(C, n3["p"])
	_ok(_check(C, n3) != "", "反向：建物の中に置いた小屋は落ちる（%s）" % _check(C, n3))
	# N4 浮き
	var n4: Dictionary = {}
	for it: Dictionary in recs:
		if not bool(it.get("hang", false)) and _check(C, it) == "":
			n4 = it.duplicate()
			break
	n4["y"] = float(n4["y"]) + 0.6
	_ok(_check(C, n4).begins_with("float"), "反向：地面から 0.6 m 浮いた構件は落ちる（%s）" % _check(C, n4))
	# N5 二重掛載
	var dup := own.duplicate()
	dup.name = P3.NODE_NAME + "_dup"
	v.add_child(dup)
	var owns2 := v.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with(P3.NODE_NAME))
	_ok(owns2.size() == 2, "反向：二重掛載は件数 2 として検出できる（%d）" % owns2.size())
	v.remove_child(dup)
	dup.free()
	# N6 樹種が一種類
	_ok(not variety_ok(["keyaki_a", "keyaki_a", "keyaki_a", "keyaki_a", "keyaki_a", "keyaki_a", "keyaki_a"]), "反向：同じ樹種ばかりは多様性 gate が落ちる")
	_ok(not variety_ok(["keyaki_a", "shii_a", "konara_a", "enoki_a", "momiji_a", "momiji_b", "momiji_c", "keyaki_a", "keyaki_a", "keyaki_a", "keyaki_a", "keyaki_a", "keyaki_a"]), "反向：種類は足りても一種が 35 % を超えれば落ちる")
	# N7 切れ目のない生垣
	_ok(not hedge_gap_ok([78.6, 79.8, 81.0, 82.2, 83.4, 84.6, 85.8, 87.0, 88.2, 89.4, 90.6], HEDGE_GAP_MIN), "反向：切れ目のない生垣は落ちる")
	_ok(hedge_gap_ok([78.6, 80.0, 81.4, 85.0, 86.4, 88.0], HEDGE_GAP_MIN), "正：3.6 m の切れ目がある生垣は通る")
	# N8 戸口をまたぐ碰撞箱
	var dp := SL.door_poly(bld0)
	var dc := (dp[0] + dp[1] + dp[2] + dp[3]) * 0.25
	var fake := PackedVector2Array([dc + Vector2(-0.3, -0.3), dc + Vector2(0.3, -0.3), dc + Vector2(0.3, 0.3), dc + Vector2(-0.3, 0.3)])
	_ok(_coll_bad(C, fake) != "", "反向：戸口の空け帯にかかる碰撞箱は落ちる（%s）" % _coll_bad(C, fake))
	# N9 R1 の榎（相機の 3.6 m 前）を戻すと cT4 の相機が樹冠の中になる
	var neg_enoki: Array = c3_recs.duplicate()
	neg_enoki.append({"id": "enoki_a", "p": Vector2(317.4, 61.3), "y": 0.15, "sx": 0.80, "sy": 0.75, "cluster": "C3_belt"})
	_ok(not P3.cam_in_crown(neg_enoki, P3.CT4_CAM).is_empty(), "反向：R1 の榎（相機の 3.6 m 前）を戻すと『相機が樹冠の中』として落ちる（%s）" % str(P3.cam_in_crown(neg_enoki, P3.CT4_CAM)))
	# N10 農舎の真正面（相機の視線の上）に大木を置くと、農舎への視線が遮られる
	var neg_block: Array = c3_recs.duplicate()
	neg_block.append({"id": "keyaki_a", "p": Vector2(317.2, 66.0), "y": 0.1, "sx": 0.60, "sy": 0.60, "cluster": "C3_belt"})
	var vb: Dictionary = P3.ct4_view(neg_block)
	_ok(float(vb["farm"]) > P3.CT4_BLOCK_MAX, "反向：相機と農舎の間に大木を置くと農舎への視線の遮られ率が %.0f %% に跳ね上がり落ちる（> %.0f %%）" % [100.0 * float(vb["farm"]), 100.0 * P3.CT4_BLOCK_MAX])
	# N11 運河への視線の上に幹を置くと、運河への視線が遮られる
	var neg_canal: Array = c3_recs.duplicate()
	neg_canal.append({"id": "shii_a", "p": Vector2(311.36, 66.41), "y": 0.0, "sx": 0.80, "sy": 0.80, "cluster": "C3_belt"})
	var vcn: Dictionary = P3.ct4_view(neg_canal)
	_ok(float(vcn["canal"]) > P3.CT4_BLOCK_MAX, "反向：相機と運河の間に幹を置くと運河への視線の遮られ率が %.0f %% になり落ちる（> %.0f %%）" % [100.0 * float(vcn["canal"]), 100.0 * P3.CT4_BLOCK_MAX])
	# N11b R1 の榎を戻すと、農舎の遮られ率も落ちる
	var ve: Dictionary = P3.ct4_view(neg_enoki)
	_ok(float(ve["farm"]) > P3.CT4_BLOCK_MAX, "反向：R1 の榎を戻すと農舎への視線の遮られ率が %.0f %% になり落ちる" % (100.0 * float(ve["farm"])))
	# N12 R1 の路肩（同じ配合の群れ・11 m 続く帯）は落ちる
	var vr1: Dictionary = P3.verge_check(R1_VERGE)
	_ok(not bool(vr1["ok"]), "反向：R1 の南の路肩（群れ %d・最大の帯 %.1f m）は落ちる（%s）" % [int(vr1["groups"]), float(vr1["widest"]), str(vr1["why"])])
	# N13 同じ低木を 1.8 m おきに並べた帯は落ちる
	var comb: Array = []
	for k in 13:
		comb.append({"id": "shrub_a", "p": Vector2(334.0 + 1.8 * k, 74.6), "sx": 1.2, "sy": 1.2})
	_ok(not bool(P3.verge_check(comb)["ok"]), "反向：同じ低木を 1.8 m おきに並べた帯は落ちる（%s）" % str(P3.verge_check(comb)["why"]))
	# N14 群れの間を詰める（B を A と C の間いっぱいに広げる）と切れ目が足りず落ちる
	var packed: Array = (c3_recs.filter(func(it: Dictionary) -> bool: return String(it["cluster"]) == "C3_road")).duplicate()
	for dx in [-2.0, 2.2, 4.0, 5.6]:
		packed.append({"id": "tsutsuji_a", "p": Vector2(341.5 + dx, 74.4), "sx": 1.2, "sy": 1.2})
	_ok(not bool(P3.verge_check(packed)["ok"]), "反向：群れの間を詰めると『切れ目』が足りず落ちる（%s）" % str(P3.verge_check(packed)["why"]))
	print("[W9P3G] PASS %d  FAIL %d" % [passed, failed])
	print("[W9P3G] 結果：%d 項失敗" % failed)
	quit(1 if failed > 0 else 0)
