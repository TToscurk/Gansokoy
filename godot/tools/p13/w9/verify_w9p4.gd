extends SceneTree
## P13 W9 Phase 4 gate：EnrichW9P4（B4 西巷の暮らしの痕跡・宅間・庭木／C4 中橫街の裏の空き地の植栽）を「保存された場景」から読み戻して独立に検査する。
##   godot --headless --path godot --script res://tools/p13/w9/verify_w9p4.gd
## W9／Phase 3 と同じ規則（W9.why＝道・建物・戸口・水・田・封存物・NPC 動線・Hero への不侵入と接地）を、烘焙後のノードの実座標で再評価する。
## さらに設計の意図を数値で守る：各戸の小物の組が同じにならない／C4 の植栽が三層（高木・中層・低層）で等間隔でない／高木は道の路面から離れる。
## MultiMesh なし（headless 可）。meadow（立ち草）の回避は計画時のみ。
const P4 := preload("res://tools/p13/w9/w9p4_lib.gd")
const P3 := preload("res://tools/p13/w9/w9p3_lib.gd")
const W9 := preload("res://tools/p13/w9/w9_lib.gd")
const SL := preload("res://tools/village_v2_street_lib.gd")
const HU := preload("res://tools/village_v2_human_use_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")

const MIN_ZONE := {"B4": 40, "C4": 20}
const MAX_TRI_LOD0 := 150000
const MAX_MESH := 450
const MAX_SHAPES := 60
const TALL_H := 8.0
const CV_MIN := 0.25           ## 隣の株までの距離の変動係数（等間隔の並びは ≈ 0）
const TREE_ROAD_GAP := 3.0     ## 高木は路面の縁からこの距離以上離す（視線の通路）

var passed := 0
var failed := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("[W9P4G] PASS ", msg)
	else:
		failed += 1
		print("[W9P4G] FAIL ", msg)


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
		"sx": gt.basis.x.length(), "sy": gt.basis.y.length(), "sz": gt.basis.z.length(), "b": String(n.get_meta("w9_b", "")), "mode": String(n.get_meta("w9_mode", "ground")),
		"zone": String(n.get_meta("w9_zone", "")), "cluster": String(n.get_meta("w9_cluster", ""))}
	for f in String(n.get_meta("w9_flags", "")).split(",", false):
		it[f] = true
	return it


func _why_mode(it: Dictionary) -> String:
	if bool(it.get("soft", false)):
		return "soft"
	var m := String(it.get("mode", "ground"))
	return "wall" if (m == "wall" or m == "gap") else "ground"


## 1 件の検査：置けない理由（"" なら適合）。接地も含む（R1 gate＝verify_w9_enrichment.gd と同じ判定）
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


## 隣の株までの距離の変動係数（点が 3 未満は 1.0＝問題なし）。等間隔の並びは小さい値になる。
static func spacing_cv(pts: Array) -> float:
	if pts.size() < 4:
		return 1.0
	var d: Array = []
	for i in pts.size():
		var best := 1e9
		for j in pts.size():
			if i != j:
				best = minf(best, (pts[i] as Vector2).distance_to(pts[j]))
		d.append(best)
	var m := 0.0
	for x: float in d:
		m += x
	m /= float(d.size())
	var s := 0.0
	for x: float in d:
		s += (x - m) * (x - m)
	return sqrt(s / float(d.size())) / maxf(m, 0.001)


## 各戸の小物の組（id の集合）が同じ組で 3 戸以上に使われていないか
static func sets_ok(houses: Dictionary) -> bool:
	var cnt := {}
	for h in houses:
		var a: Array = (houses[h] as Array).duplicate()
		a.sort()
		var k := ",".join(PackedStringArray(a))
		cnt[k] = int(cnt.get(k, 0)) + 1
	for k in cnt:
		if int(cnt[k]) >= 3:
			return false
	return true


func _layers(recs: Array, cl: String) -> Dictionary:
	var tall := 0
	var mid := 0
	var low := 0
	var pts: Array = []
	for it: Dictionary in recs:
		if String(it["cluster"]) != cl:
			continue
		var id := String(it["id"])
		pts.append(it["p"])
		if P3.TREES.has(id) and P3.tree_h(id) * float(it["sy"]) >= TALL_H:
			tall += 1
		elif id.begins_with("young_broad") or id.begins_with("shrub") or id.begins_with("tsutsuji"):
			mid += 1
		elif id.begins_with("fern") or id.begins_with("sasa") or id.begins_with("w9_hana"):
			low += 1
	return {"tall": tall, "mid": mid, "low": low, "cv": spacing_cv(pts), "n": pts.size()}


func _run() -> void:
	var v: Node3D = (load(P4.SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 3:
		await physics_frame
	P3.register_dims()
	# ── 掛載（保存された village_v2.tscn に ext_resource 1＋node 1 だけ・EnrichW9P3 の直後）
	var txt := FileAccess.get_file_as_string(P4.SCENE)
	var ext_line := "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p13w9p4_enrich\"]" % P4.OUTPUT
	var node_line := "[node name=\"%s\" parent=\".\" instance=ExtResource(\"p13w9p4_enrich\")]" % P4.NODE_NAME
	_ok(txt.count(ext_line) == 1 and txt.count(node_line) == 1, "保存された village_v2.tscn に ext_resource 1＋node 1 だけ掛かっている（%d＋%d）" % [txt.count(ext_line), txt.count(node_line)])
	var order: PackedStringArray = []
	for l: String in txt.split("\n"):
		if l.begins_with("[node name=\"") and l.contains("parent=\".\""):
			order.append(l.split("\"")[1])
	_ok(order.find(P4.NODE_NAME) == order.find(P4.AFTER) + 1 and order.find(P4.AFTER) >= 0, "%s は %s の直後（順序）" % [P4.NODE_NAME, P4.AFTER])
	for keep in ["EnrichW9P13", "EnrichW9P3", "ArchW9R2P13", "FarmsteadP13", "MeadowP9", "EnvironmentP9", "HumanUseP10"]:
		_ok(order.has(keep) or v.get_node_or_null(keep) != null or v.get_node_or_null("Vegetation/" + keep) != null or v.get_node_or_null("Props/" + keep) != null, "既存 overlay %s は残っている" % keep)
	var owns := v.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with(P4.NODE_NAME))
	_ok(owns.size() == 1, "EnrichW9P4 は root に 1 つだけ（%d）" % owns.size())
	var own := v.get_node_or_null(P4.NODE_NAME) as Node3D
	if own == null:
		print("[W9P4G] 結果：掛載なし")
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
	# ── 設計の意図：B4（各戸の暮らしが違う・宅間に垣・背後の樹冠）
	var houses := {}
	var gap_fence := 0
	var back_tall := 0
	var ids_b := {}
	for it: Dictionary in recs:
		var cl := String(it["cluster"])
		var id := String(it["id"])
		if cl.begins_with("B4") or String(it["zone"]) == "B4" or cl.begins_with("AH_") or cl.begins_with("AG_") or cl.begins_with("AB_"):
			ids_b[id] = true
		if cl.begins_with("AH_"):
			if not houses.has(cl):
				houses[cl] = []
			(houses[cl] as Array).append(id)
		if cl.begins_with("AG_") and (id.begins_with("gk_") or id == "w9_takegaki"):
			gap_fence += 1
		if cl.begins_with("AB_back") and P3.TREES.has(id) and P3.tree_h(id) * float(it["sy"]) >= TALL_H:
			back_tall += 1
	_ok(houses.size() >= 8, "西巷の暮らしの痕跡：小物を置いた戸が %d ≥ 8" % houses.size())
	_ok(sets_ok(houses), "各戸の小物の組：同じ組が 3 戸以上に使われていない（戸 %d）" % houses.size())
	_ok(ids_b.size() >= 14, "B4 の構件の種類 %d ≥ 14（同じ一組の複製ではない）" % ids_b.size())
	_ok(gap_fence >= 3, "宅間の垣・塀の部材 %d ≥ 3" % gap_fence)
	_ok(back_tall >= 5, "棟の背後の樹冠：高さ ≥ %.0f m の樹 %d ≥ 5（屋根並みの単調さを破る）" % [TALL_H, back_tall])
	# ── 設計の意図：C4（三層・不規則・高木は道から離す）
	for cl: String in ["C4_pocket_N", "C4_pocket_S"]:
		var L := _layers(recs, cl)
		var need_tall := 2 if cl.ends_with("N") else 1
		_ok(int(L["tall"]) >= need_tall and int(L["mid"]) >= 4 and int(L["low"]) >= 4, "%s：高木 %d ≥ %d・中層 %d ≥ 4・低層 %d ≥ 4（三層）" % [cl, int(L["tall"]), need_tall, int(L["mid"]), int(L["low"])])
		_ok(float(L["cv"]) >= CV_MIN, "%s：隣の株までの距離の変動係数 %.2f ≥ %.2f（等間隔でない・%d 株）" % [cl, float(L["cv"]), CV_MIN, int(L["n"])])
	# ── 予算
	var tri := 0
	var mesh := 0
	for mi in own.find_children("*", "MeshInstance3D", true, false):
		var g := mi as MeshInstance3D
		mesh += 1
		if g.visibility_range_begin <= 0.001 and g.mesh != null:
			for s in g.mesh.get_surface_count():
				var arrays := g.mesh.surface_get_arrays(s)
				var idx = arrays[Mesh.ARRAY_INDEX]
				tri += (idx.size() if idx != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	var shapes := own.find_children("*", "CollisionShape3D", true, false)
	var mm := own.find_children("*", "MultiMeshInstance3D", true, false)
	print("[W9P4G] INFO LOD0 三角面 %d・MeshInstance %d・碰撞箱 %d・MultiMesh %d" % [tri, mesh, shapes.size(), mm.size()])
	_ok(tri <= MAX_TRI_LOD0 and mesh <= MAX_MESH and shapes.size() <= MAX_SHAPES, "予算：LOD0 %d ≤ %d・Mesh %d ≤ %d・碰撞箱 %d ≤ %d" % [tri, MAX_TRI_LOD0, mesh, MAX_MESH, shapes.size(), MAX_SHAPES])
	_ok(mm.is_empty(), "MultiMesh なし（headless 烘焙の零行列問題の対象外）")
	# ── 配置の再評価（自分自身を外して context を作る）
	v.remove_child(own)
	var C := W9.context(v, PackedVector2Array())
	var prev_rects: Array = []
	for ov_name in ["EnrichW9P13", "EnrichW9P3"]:
		var ov := v.get_node_or_null(ov_name)
		if ov == null:
			continue
		for mi in ov.find_children("*", "MeshInstance3D", true, false):
			var g2 := mi as MeshInstance3D
			if g2.mesh == null or g2.visibility_range_begin > 0.001:
				continue
			var rr: Rect2 = HU._rect_of(g2, v)
			if rr.size.x <= 12.0 and rr.size.y <= 12.0:
				prev_rects.append([rr, String(g2.get_parent().name)])
	v.add_child(own)
	var bad := 0
	var bad_msgs: Array = []
	var near_road := 0
	var tree_road := 0
	var on_prev := 0
	var Rr: RLib.TriSampler = C["R"]
	for it: Dictionary in recs:
		var w := _check(C, it)
		if w != "":
			bad += 1
			if bad_msgs.size() < 20:
				bad_msgs.append("%s@(%.1f,%.1f) %s [%s]" % [it["id"], it["p"].x, it["p"].y, w, it["cluster"]])
		var p2: Vector2 = it["p"]
		var onroad := false
		for k in 8:
			var q := p2 + Vector2.from_angle(TAU * k / 8.0) * 0.6
			if not is_nan(Rr.h(q.x, q.y)):
				onroad = true
		if onroad and P3.is_plant(String(it["id"])):
			near_road += 1
		if P3.TREES.has(String(it["id"])) and P3.tree_h(String(it["id"])) * float(it["sy"]) >= TALL_H:
			var near := false
			for k in 12:
				var q2 := p2 + Vector2.from_angle(TAU * k / 12.0) * TREE_ROAD_GAP
				if not is_nan(Rr.h(q2.x, q2.y)):
					near = true
			if near:
				tree_road += 1
		if not P3.is_plant(String(it["id"])):
			var fp := W9.foot(it)
			var fr := Rect2(fp[0], Vector2.ZERO)
			for q in fp:
				fr = fr.expand(q)
			for pr: Array in prev_rects:
				if fr.grow(0.05).intersects(pr[0] as Rect2):
					on_prev += 1
					print("[W9P4G]   既存（%s）と重なる地面物 %s@(%.1f,%.1f)" % [pr[1], it["id"], p2.x, p2.y])
					break
	for m in bad_msgs:
		print("[W9P4G]   不適合 ", m)
	_ok(bad == 0, "全 %d 構件が道・建物・戸口・水・田・封存物・NPC 動線・Hero に触れず、接地している（不適合 %d）" % [recs.size(), bad])
	_ok(near_road == 0, "樹・竹・低木は路面の縁から 0.6 m 以内に乗らない（%d）" % near_road)
	_ok(tree_road == 0, "高木は路面の縁から %.0f m 以上離れる＝道の視線の通路を塞がない（%d）" % [TREE_ROAD_GAP, tree_road])
	_ok(on_prev == 0, "地面物が W9 R1／Phase 3 の構件と重ならない（%d）" % on_prev)
	var ov_n := 0
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
					ov_n += 1
					if ov_n <= 5:
						print("[W9P4G]   重なり %s × %s @(%.1f,%.1f) %.2f m²" % [a["id"], b["id"], a["p"].x, a["p"].y, absf(area)])
	_ok(ov_n == 0, "構件同士が重ならない（重なり %d）" % ov_n)
	var cbad := 0
	for cs in shapes:
		var r := _coll_bad(C, _rect_poly(cs as CollisionShape3D))
		if r != "":
			cbad += 1
			if cbad <= 5:
				print("[W9P4G]   碰撞不適合 %s %s" % [cs.name, r])
	_ok(cbad == 0, "碰撞箱 %d 個が戸口の空け帯と NPC の巡回路に触れない（%d）" % [shapes.size(), cbad])
	# ── 反向案例（gate が本当に落ちる）
	var sample: Dictionary = recs[0].duplicate()
	sample["hang"] = false
	# 主街の路面の上の点（z＝20 を西から走査して最初に路面がある x）
	var road_pt := Vector2.ZERO
	var xr := 240.0
	while xr < 262.0:
		if not is_nan(Rr.h(xr, 20.0)):
			road_pt = Vector2(xr, 20.0)
			break
		xr += 0.5
	var n1 := sample.duplicate()
	n1["id"] = "momiji_a"
	n1["soft"] = true
	n1["mode"] = "soft"
	n1["p"] = road_pt
	n1["y"] = W9.top_h(C, n1["p"])
	_ok(road_pt != Vector2.ZERO and _check(C, n1) == "road", "反向：主街の路面（%.1f, %.1f）に置いた樹は『road』で落ちる（%s）" % [road_pt.x, road_pt.y, _check(C, n1)])
	var bld0: Dictionary = (C["bld"] as Array)[0]
	var n3 := sample.duplicate()
	n3["id"] = "farm_shed"
	n3["mode"] = "ground"
	n3.erase("soft")
	n3["p"] = bld0["o"]
	n3["yaw"] = 0.0
	n3["y"] = W9.top_h(C, n3["p"])
	_ok(_check(C, n3) != "", "反向：建物の中に置いた小屋は落ちる（%s）" % _check(C, n3))
	var n4: Dictionary = {}
	for it: Dictionary in recs:
		if not bool(it.get("hang", false)) and _check(C, it) == "":
			n4 = it.duplicate()
			break
	n4["y"] = float(n4["y"]) + 0.6
	_ok(_check(C, n4).begins_with("float"), "反向：地面から 0.6 m 浮いた構件は落ちる（%s）" % _check(C, n4))
	var dp := SL.door_poly(bld0)
	var dc := (dp[0] + dp[1] + dp[2] + dp[3]) * 0.25
	var fake := PackedVector2Array([dc + Vector2(-0.3, -0.3), dc + Vector2(0.3, -0.3), dc + Vector2(0.3, 0.3), dc + Vector2(-0.3, 0.3)])
	_ok(_coll_bad(C, fake) != "", "反向：戸口の空け帯にかかる碰撞箱は落ちる（%s）" % _coll_bad(C, fake))
	var dup := own.duplicate()
	dup.name = P4.NODE_NAME + "_dup"
	v.add_child(dup)
	var owns2 := v.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with(P4.NODE_NAME))
	_ok(owns2.size() == 2, "反向：二重掛載は件数 2 として検出できる（%d）" % owns2.size())
	v.remove_child(dup)
	dup.free()
	_ok(not sets_ok({"a": ["x", "y"], "b": ["y", "x"], "c": ["x", "y"], "d": ["z"]}), "反向：同じ小物の組が 3 戸に使われると落ちる")
	_ok(sets_ok({"a": ["x", "y"], "b": ["y", "x"], "c": ["z"]}), "正：同じ組が 2 戸までなら通る")
	var comb: Array = []
	for k in 8:
		comb.append(Vector2(280.0 + 1.5 * k, -40.0))
	_ok(spacing_cv(comb) < CV_MIN, "反向：1.5 m 等間隔の並びは変動係数 %.2f で落ちる（< %.2f）" % [spacing_cv(comb), CV_MIN])
	var tall_on_road := false
	for k in 12:
		var q3: Vector2 = road_pt + Vector2.from_angle(TAU * k / 12.0) * TREE_ROAD_GAP
		if not is_nan(Rr.h(q3.x, q3.y)):
			tall_on_road = true
	_ok(road_pt != Vector2.ZERO and tall_on_road, "反向：主街の路面（%.1f, %.1f）に置いた高木は『路面から離れる』判定で落ちる" % [road_pt.x, road_pt.y])
	print("[W9P4G] PASS %d  FAIL %d" % [passed, failed])
	print("[W9P4G] 結果：%d 項失敗" % failed)
	quit(1 if failed > 0 else 0)
