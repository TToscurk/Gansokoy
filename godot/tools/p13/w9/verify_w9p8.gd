extends SceneTree
## P13 W9 Phase 8 gate：EnrichW9P8（A8 稗田邸の西の参道／B8 東北聚落・香霖堂口）を「保存された overlay 場景」から読み戻して独立に検査する。
##   godot --headless --path godot --script res://tools/p13/w9/verify_w9p8.gd
## 掛載：village_v2.tscn に掛かっていれば 1 つだけ・EnrichW9P4 の直後を検査。掛かっていなければ（Phase 8 は共有編輯器の都合で未掛載）
##   記憶の中で EnrichW9P4 の直後に掛けて同じ検査をし、場景ファイルに半端な行（ext_resource だけ等）が無いことを確かめる。
## 規則は Phase 4 gate（verify_w9p4.gd）と同じ W9.why（道・建物・戸口・水・田・封存物・NPC 動線・Hero への不侵入）と接地。
## 追加：任務の出入口（香霖堂・稗田邸の portal、阿求の quest anchor）から 6 m 以内に置かない／稲の置き場は 2 m 未満（塀と屋敷を隠さない）／
##   各通行帯で EnrichW9P8 の碰撞が SpringArm を大きく縮めない（同じ地点・同じ向きで自分の碰撞を除いた ray と比較）／可逆（外すと元の root 構成に戻る）。
const P8 := preload("res://tools/p13/w9/w9p8_lib.gd")
const P3 := preload("res://tools/p13/w9/w9p3_lib.gd")
const W9 := preload("res://tools/p13/w9/w9_lib.gd")
const SL := preload("res://tools/village_v2_street_lib.gd")
const HU := preload("res://tools/village_v2_human_use_lib.gd")
const RLib := preload("res://tools/village_v2_riverbank_lib.gd")

const MIN_ZONE := {"A8": 30, "B8": 60}
const MAX_TRI_LOD0 := 150000
const MAX_MESH := 450
const MAX_SHAPES := 80
const TALL_H := 8.0
const CV_MIN := 0.25
const TREE_ROAD_GAP := 3.0
const KEEP_CLEAR := {"PORTAL_KOURINDOU": Vector2(428.0, -205.0), "PORTAL_HIEDA1F": Vector2(398.0, 2.0), "akyuu_record": Vector2(398.0, -4.0)}
const KEEP_R := 6.0
const YARD_MAX_H := 2.0
const ARM_UP := 1.70
const ARM_SIN := 0.179
const ARM_MAX := 7.5
const ARM_SEV_LOSS := 2.0
const ARM_SEV_LEN := 3.0

var passed := 0
var failed := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
		print("[W9P8G] PASS ", msg)
	else:
		failed += 1
		print("[W9P8G] FAIL ", msg)


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


static func keep_clear_min(pts: Array) -> Array:
	var best := 1e9
	var who := ""
	for p: Vector2 in pts:
		for k: String in KEEP_CLEAR:
			var d := p.distance_to(KEEP_CLEAR[k])
			if d < best:
				best = d
				who = k
	return [best, who]


## 通行帯（折れ線の軸 ±1.2 m・0.5 m おき・16 方位）で SpringArm の ray を、全碰撞あり／EnrichW9P8 の碰撞なしの 2 回飛ばして縮みを数える
func _arm_scan(v: Node3D, own: Node3D) -> Dictionary:
	var sp := v.get_world_3d().direct_space_state
	var ex: Array = []
	for c in own.find_children("*", "CollisionObject3D", true, false):
		ex.append((c as CollisionObject3D).get_rid())
	var cc := sqrt(1.0 - ARM_SIN * ARM_SIN)
	var res := {"n": 0, "severe": 0, "any": 0, "w_loss": 0.0, "w_pre": ARM_MAX, "w_now": ARM_MAX, "w_lane": "", "by": {}}
	for lane: String in P8.ARM_LANES:
		var pl: Array = P8.ARM_LANES[lane]
		for si in range(1, pl.size()):
			var a: Vector2 = pl[si - 1]
			var b: Vector2 = pl[si]
			var S := (b - a).normalized()
			var N := Vector2(-S.y, S.x)
			for k in int(a.distance_to(b) / 0.5) + 1:
				for o: float in [-1.2, -0.6, 0.0, 0.6, 1.2]:
					var pw := a + S * (0.5 * k) + N * o
					var rg := sp.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(pw.x, 60.0, pw.y), Vector3(pw.x, -20.0, pw.y), 1, ex))
					if rg.is_empty():
						continue
					var o3 := Vector3(pw.x, float((rg["position"] as Vector3).y) + ARM_UP, pw.y)
					for yi in 16:
						var yaw := TAU * float(yi) / 16.0
						var fc := Vector2(sin(yaw), -cos(yaw))
						var to := o3 + Vector3(-fc.x * cc, ARM_SIN, -fc.y * cc) * ARM_MAX
						var r1 := sp.intersect_ray(PhysicsRayQueryParameters3D.create(o3, to, 1))
						var r0 := sp.intersect_ray(PhysicsRayQueryParameters3D.create(o3, to, 1, ex))
						var now := ARM_MAX if r1.is_empty() else o3.distance_to(r1["position"] as Vector3)
						var pre := ARM_MAX if r0.is_empty() else o3.distance_to(r0["position"] as Vector3)
						var loss := pre - now
						res["n"] = int(res["n"]) + 1
						if loss >= 0.30:
							res["any"] = int(res["any"]) + 1
						if loss >= ARM_SEV_LOSS and now < ARM_SEV_LEN:
							res["severe"] = int(res["severe"]) + 1
							var who := "?"
							var co: Object = r1.get("collider")
							if co is CollisionObject3D:
								var ow := (co as CollisionObject3D).shape_find_owner(int(r1.get("shape", 0)))
								var on := (co as CollisionObject3D).shape_owner_get_owner(ow)
								who = String((on as Node).name) if on is Node else String((co as Node).name)
							var by: Dictionary = res["by"]
							by[who] = int(by.get(who, 0)) + 1
						if loss > float(res["w_loss"]):
							res["w_loss"] = loss
							res["w_pre"] = pre
							res["w_now"] = now
							res["w_lane"] = "%s(%.1f,%.1f)" % [lane, pw.x, pw.y]
	return res


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
	var v: Node3D = (load(P8.SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 3:
		await physics_frame
	P3.register_dims()
	var root_before: PackedStringArray = []
	for c in v.get_children():
		root_before.append(String(c.name))
	# ── 掛載
	var txt := FileAccess.get_file_as_string(P8.SCENE)
	var ext_line := "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"p13w9p8_enrich\"]" % P8.OUTPUT
	var node_line := "[node name=\"%s\" parent=\".\" instance=ExtResource(\"p13w9p8_enrich\")]" % P8.NODE_NAME
	var ne := txt.count(ext_line)
	var nn := txt.count(node_line)
	var mounted_on_disk := ne == 1 and nn == 1
	_ok((ne == 0 and nn == 0) or mounted_on_disk, "village_v2.tscn の EnrichW9P8 掛載行：ext_resource %d・node %d（0＋0＝未掛載、1＋1＝掛載。半端な状態ではない）" % [ne, nn])
	var own := v.get_node_or_null(P8.NODE_NAME) as Node3D
	if mounted_on_disk:
		var order: PackedStringArray = []
		for l: String in txt.split("\n"):
			if l.begins_with("[node name=\"") and l.contains("parent=\".\""):
				order.append(l.split("\"")[1])
		_ok(order.find(P8.NODE_NAME) == order.find(P8.AFTER) + 1 and order.find(P8.AFTER) >= 0, "%s は %s の直後（順序）" % [P8.NODE_NAME, P8.AFTER])
	else:
		print("[W9P8G] INFO village_v2.tscn には未掛載 → 記憶の中で %s の直後に掛けて検査する（場景ファイルは書かない）" % P8.AFTER)
		own = (ResourceLoader.load(P8.OUTPUT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as Node3D
		own.name = P8.NODE_NAME
		v.add_child(own)
		v.move_child(own, v.get_node(P8.AFTER).get_index() + 1)
		for i in 4:
			await physics_frame
	for keep in ["EnrichW9P13", "EnrichW9P3", "EnrichW9P4", "ArchW9R2P13", "FarmsteadP13", "HumanUseP10", "EdgeClosureP10"]:
		_ok(v.get_node_or_null(keep) != null, "既存 overlay %s は残っている" % keep)
	var owns := v.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with(P8.NODE_NAME))
	_ok(owns.size() == 1, "EnrichW9P8 は root に 1 つだけ（%d）" % owns.size())
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
	# ── 設計の意図
	var houses := {}
	var gap_fence := 0
	var ids_b := {}
	var yard_hmax := 0.0
	var yard_n := 0
	var canopy_tall := 0
	for it: Dictionary in recs:
		var cl := String(it["cluster"])
		var id := String(it["id"])
		if String(it["zone"]) == "B8":
			ids_b[id] = true
		if cl.begins_with("BH_"):
			if not houses.has(cl):
				houses[cl] = []
			(houses[cl] as Array).append(id)
		if cl.begins_with("BG_") and (id.begins_with("gk_") or id.begins_with("w9_takegaki") or id.begins_with("w9_itabei")):
			gap_fence += 1
		if cl == "A8_rice_yard":
			yard_n += 1
			yard_hmax = maxf(yard_hmax, float(W9.dims(id)[4]) * float(it["sy"]))
		if cl == "B8_canopy" and P3.TREES.has(id) and P3.tree_h(id) * float(it["sy"]) >= TALL_H:
			canopy_tall += 1
	_ok(houses.size() >= 8, "東北聚落の門前：小物を置いた戸 %d ≥ 8" % houses.size())
	_ok(sets_ok(houses), "各戸の小物の組：同じ組が 3 戸以上に使われていない（戸 %d）" % houses.size())
	_ok(ids_b.size() >= 14, "B8 の構件の種類 %d ≥ 14（同じ一組の複製ではない）" % ids_b.size())
	_ok(gap_fence >= 3, "B8 宅間の垣・塀の部材 %d ≥ 3" % gap_fence)
	_ok(canopy_tall >= 3, "B8 屋根並みの背後：高さ ≥ %.0f m の樹 %d ≥ 3" % [TALL_H, canopy_tall])
	_ok(yard_n >= 6 and yard_hmax < YARD_MAX_H, "A8 稲の置き場：%d 件・最も高い物 %.2f m < %.1f m（塀と屋敷を隠さない）" % [yard_n, yard_hmax, YARD_MAX_H])
	var L := _layers(recs, "A8_north_grove")
	_ok(int(L["tall"]) >= 2 and int(L["mid"]) >= 3 and int(L["low"]) >= 4, "A8_north_grove：高木 %d ≥ 2・中層 %d ≥ 3・低層 %d ≥ 4（三層）" % [int(L["tall"]), int(L["mid"]), int(L["low"])])
	_ok(float(L["cv"]) >= CV_MIN, "A8_north_grove：隣の株までの距離の変動係数 %.2f ≥ %.2f（等間隔でない・%d 株）" % [float(L["cv"]), CV_MIN, int(L["n"])])
	var pts_all: Array = []
	for it: Dictionary in recs:
		pts_all.append(it["p"])
	var kc := keep_clear_min(pts_all)
	_ok(float(kc[0]) >= KEEP_R, "任務の出入口（香霖堂・稗田邸の portal、阿求の anchor）から最も近い構件 %.1f m ≥ %.1f m（%s）" % [float(kc[0]), KEEP_R, kc[1]])
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
	print("[W9P8G] INFO LOD0 三角面 %d・MeshInstance %d・碰撞箱 %d・MultiMesh %d" % [tri, mesh, shapes.size(), mm.size()])
	_ok(tri <= MAX_TRI_LOD0 and mesh <= MAX_MESH and shapes.size() <= MAX_SHAPES, "予算：LOD0 %d ≤ %d・Mesh %d ≤ %d・碰撞箱 %d ≤ %d" % [tri, MAX_TRI_LOD0, mesh, MAX_MESH, shapes.size(), MAX_SHAPES])
	_ok(mm.is_empty(), "MultiMesh なし（headless 烘焙の零行列問題の対象外）")
	# ── 配置の再評価（自分を外して context を作る）
	v.remove_child(own)
	var C := W9.context(v, PackedVector2Array())
	var prev_rects: Array = []
	for ov_name in ["EnrichW9P13", "EnrichW9P3", "EnrichW9P4"]:
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
	v.move_child(own, v.get_node(P8.AFTER).get_index() + 1)
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
			print("[W9P8G]   路面の縁 0.6 m 以内の植物 %s@(%.1f,%.1f) [%s]" % [it["id"], p2.x, p2.y, it["cluster"]])
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
					print("[W9P8G]   既存（%s）と重なる地面物 %s@(%.1f,%.1f)" % [pr[1], it["id"], p2.x, p2.y])
					break
	for m in bad_msgs:
		print("[W9P8G]   不適合 ", m)
	_ok(bad == 0, "全 %d 構件が道・建物・戸口・水・田・封存物・NPC 動線・Hero に触れず、接地している（不適合 %d）" % [recs.size(), bad])
	_ok(near_road == 0, "樹・低木は路面の縁から 0.6 m 以内に乗らない（%d）" % near_road)
	_ok(tree_road == 0, "高木は路面の縁から %.0f m 以上離れる＝道の視線の通路を塞がない（%d）" % [TREE_ROAD_GAP, tree_road])
	_ok(on_prev == 0, "地面物が W9 R1／Phase 3／Phase 4 の構件と重ならない（%d）" % on_prev)
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
						print("[W9P8G]   重なり %s × %s @(%.1f,%.1f) %.2f m²" % [a["id"], b["id"], a["p"].x, a["p"].y, absf(area)])
	_ok(ov_n == 0, "構件同士が重ならない（重なり %d）" % ov_n)
	var cbad := 0
	for cs in shapes:
		var r := _coll_bad(C, _rect_poly(cs as CollisionShape3D))
		if r != "":
			cbad += 1
			if cbad <= 5:
				print("[W9P8G]   碰撞不適合 %s %s" % [cs.name, r])
	_ok(cbad == 0, "碰撞箱 %d 個が戸口の空け帯と NPC の巡回路に触れない（%d）" % [shapes.size(), cbad])
	# ── SpringArm：各通行帯で EnrichW9P8 の碰撞による縮み
	for i in 4:
		await physics_frame
	var sv := _arm_scan(v, own)
	for k in sv["by"]:
		print("[W9P8G]   重い縮みの碰撞 %s：%d 件" % [k, int(sv["by"][k])])
	_ok(int(sv["severe"]) == 0, "通行帯 4 本 %d 樣本：EnrichW9P8 の碰撞による SpringArm の重い縮み（≥ %.1f m かつ腕 < %.1f m）%d 件・≥ 0.30 m の縮み %d 件・最悪 %.2f → %.2f m %s" \
		% [int(sv["n"]), ARM_SEV_LOSS, ARM_SEV_LEN, int(sv["severe"]), int(sv["any"]), float(sv["w_pre"]), float(sv["w_now"]), sv["w_lane"]])
	# 反向：田埂道の軸から 1.6 m 横に高さ 2.4 m の箱（EnrichW9P8 の碰撞として記憶の中だけで）を足すと重い縮みを検出できる
	var col := own.get_node("Collision") as StaticBody3D
	var inj := CollisionShape3D.new()
	inj.name = "NEG_inject"
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.2, 2.4, 1.2)
	inj.shape = bx
	col.add_child(inj)
	inj.global_position = Vector3(373.6, W9.top_h(C, Vector2(373.6, -18.0)) + 1.2, -18.0)
	for i in 4:
		await physics_frame
	var sv2 := _arm_scan(v, own)
	_ok(int(sv2["severe"]) >= 1, "反向：田埂道の脇（373.6, −18.0）に高さ 2.4 m の箱を足すと重い縮み %d 件（≥ 1・この検査は縮みを検出できる）" % int(sv2["severe"]))
	col.remove_child(inj)
	inj.free()
	# ── 可逆：EnrichW9P8 を外すと root の構成が元に戻り、見えなくすると全メッシュが消える
	own.visible = false
	var vis_left := 0
	for mi in own.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).is_visible_in_tree():
			vis_left += 1
	_ok(vis_left == 0, "可逆：visible=false で EnrichW9P8 のメッシュがすべて非表示（残り %d）" % vis_left)
	own.visible = true
	v.remove_child(own)
	var root_after: PackedStringArray = []
	for c in v.get_children():
		root_after.append(String(c.name))
	_ok(mounted_on_disk or root_after == root_before, "可逆：EnrichW9P8 を外すと root の節点構成が掛ける前と同じ（%d 節点）" % root_after.size())
	v.add_child(own)
	# ── 反向案例（gate が本当に落ちる）
	var sample: Dictionary = recs[0].duplicate()
	sample["hang"] = false
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
	dup.name = P8.NODE_NAME + "_dup"
	v.add_child(dup)
	var owns2 := v.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with(P8.NODE_NAME))
	_ok(owns2.size() == 2, "反向：二重掛載は件数 2 として検出できる（%d）" % owns2.size())
	v.remove_child(dup)
	dup.free()
	_ok(not sets_ok({"a": ["x", "y"], "b": ["y", "x"], "c": ["x", "y"], "d": ["z"]}), "反向：同じ小物の組が 3 戸に使われると落ちる")
	var comb: Array = []
	for k in 8:
		comb.append(Vector2(280.0 + 1.5 * k, -40.0))
	_ok(spacing_cv(comb) < CV_MIN, "反向：1.5 m 等間隔の並びは変動係数 %.2f で落ちる（< %.2f）" % [spacing_cv(comb), CV_MIN])
	var kc2 := keep_clear_min([Vector2(429.0, -206.5)])
	_ok(float(kc2[0]) < KEEP_R, "反向：香霖堂の portal から %.1f m の点は『出入口から 6 m』で落ちる（%s）" % [float(kc2[0]), kc2[1]])
	print("[W9P8G] PASS %d  FAIL %d" % [passed, failed])
	print("[W9P8G] 結果：%d 項失敗" % failed)
	quit(1 if failed > 0 else 0)
