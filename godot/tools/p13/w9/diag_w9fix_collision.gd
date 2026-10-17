extends SceneTree
## P13 W9 FIX（2026-10-17）：ArchW9R2P13 で作り直した建物の『見た目』と『碰撞』の対応を実測する（唯讀・場景ファイルは書かない）。
##   godot --headless --path godot --script res://tools/p13/w9/diag_w9fix_collision.gd -- --out=<json> [--mode=runtime|editor]
## mode=runtime：正式の載入（全 overlay 腳本が走る）。mode=editor：@tool でない腳本を外す（編輯器で走るのは @tool だけ）。
## 各棟（w9r2_lib SPECS）について：
##   碰撞の持ち主：body（StaticBody3D）の CollisionShape3D（形・寸法・局部変換・disabled・layer/mask）＋ overlay の Posts（庇柱）
##   ＋ overlay の Shell（W9 FIX の外形碰撞箱。有効なら body と同じ扱い）。disabled の形は数えない（実際の物理と同じ）。
##   見た目：実行時に見えている MeshInstance3D（Kit LOD0 の残り＋overlay L0。Frontage＝地面の過渡は除く）の頂点 → 局部 AABB・世界 AABB。
##   射線比較（局部座標・4 面×高さ帯）：見た目の面までの距離（見た目の三角形だけの一時碰撞体＝layer 20 に physics ray）と、
##     自分の碰撞（Box の解析的な ray-OBB）までの距離。差 = d_vis − d_col。
##       col_ahead：碰撞が見た目より TOL 以上手前（見えない余白）／col_only：見た目の無い所に碰撞（見えない壁）
##       vis_ahead：見た目が碰撞より TOL 以上手前（突き抜ける）／vis_only：碰撞の無い見た目
##     高さ帯：player（0.25／0.9／1.5 m＝capsule 1.7 m の中）と camera（2.5〜7.5 m）。
##   上からの射線：碰撞箱の上面と見た目の屋根の高さ（碰撞が屋根より上に出る面積＝カメラの見えない天井）。
##   戸口：Kit meta door_cx／door_w の前（立面から 0.05〜2.0 m・高さ 0.1〜1.8 m）に入る碰撞体（地形を除く）。
##   隣棟：body の箱どうしの実接触（collide_shape、地形と自分を除く）。
## 全村：見える mesh を持たない（または見える mesh と AABB が重ならない）有効な碰撞体＝見えない壁の候補。ArchW9R2P13 が隠した節點の碰撞体。
const L := preload("res://tools/p13/w9/w9r2_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const TOL := 0.15
const PLAYER_H := [0.25, 0.9, 1.5]
const CAMERA_H := [2.5, 3.5, 4.5, 5.5, 6.5, 7.5]
const STEP := 0.5
const VIS_LAYER := 1 << 19

var out_path := ""
var mode := "runtime"
var arch_off := false     # --arch-off：ArchW9R2P13.enabled=false（元の Kit＝W9 以前の見た目）で同じ計測（比較の基準）


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.trim_prefix("--out=")
		elif a.begins_with("--mode="):
			mode = a.trim_prefix("--mode=")
		elif a == "--arch-off":
			arch_off = true
	_run.call_deferred()


static func ray_obb(o: Vector3, d: Vector3, xf: Transform3D, half: Vector3) -> float:
	## o, d はワールド（d は単位）。箱は xf（中心）と half。当たらなければ INF。o が中に入っていれば 0。
	var inv := xf.affine_inverse()
	var lo := inv * o
	var ld := inv.basis * d
	var tmin := -INF
	var tmax := INF
	for i in 3:
		if absf(ld[i]) < 1e-9:
			if lo[i] < -half[i] or lo[i] > half[i]:
				return INF
		else:
			var t1 := (-half[i] - lo[i]) / ld[i]
			var t2 := (half[i] - lo[i]) / ld[i]
			tmin = maxf(tmin, minf(t1, t2))
			tmax = minf(tmax, maxf(t1, t2))
	if tmax < maxf(tmin, 0.0):
		return INF
	return maxf(tmin, 0.0)


func _boxes_of(body: CollisionObject3D, owner_tag: String) -> Array:
	var out: Array = []
	for cs in body.get_children():
		if cs is CollisionShape3D and not (cs as CollisionShape3D).disabled and (cs as CollisionShape3D).shape != null:
			var sh := (cs as CollisionShape3D).shape
			var gx := (cs as CollisionShape3D).global_transform
			if sh is BoxShape3D:
				out.append({"owner": owner_tag, "node": String(cs.get_path()), "xf": gx, "half": (sh as BoxShape3D).size * 0.5, "cls": "Box"})
			else:
				out.append({"owner": owner_tag, "node": String(cs.get_path()), "xf": gx, "half": Vector3.ZERO, "cls": sh.get_class()})
	return out


func _vis_meshes(body: Node3D, ov_b: Node) -> Array:
	var out: Array = []
	var kit := body.get_node_or_null("Kit")
	if kit and kit.get_node_or_null("LOD0"):
		for mi in kit.get_node("LOD0").get_children():
			if mi is MeshInstance3D and (mi as MeshInstance3D).is_visible_in_tree() and (mi as MeshInstance3D).mesh != null:
				out.append(mi)
	for c in body.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).is_visible_in_tree() and (c as MeshInstance3D).mesh != null:
			out.append(c)
	if ov_b != null:
		for c in ov_b.get_children():
			if c is MeshInstance3D and String(c.name) == "L0" and (c as MeshInstance3D).is_visible_in_tree():
				out.append(c)
	return out


func _run() -> void:
	var v := (load(SCENE) as PackedScene).instantiate()
	var stripped := 0
	if mode == "editor":
		for n in [v] + v.find_children("*", "", true, false):
			var sc: Script = n.get_script()
			if sc != null and not sc.is_tool():
				n.set_script(null)
				stripped += 1
	root.add_child(v)
	for i in 8:
		await process_frame
	for i in 3:
		await physics_frame
	var space := (v as Node3D).get_world_3d().direct_space_state
	var terrain := v.get_node("Collision/TerrainCollision") as CollisionObject3D
	var ov := v.get_node("ArchW9R2P13")
	if arch_off:
		ov.set("enabled", false)
		for i in 3:
			await physics_frame
	var report := {"arch_off": arch_off, "mode": mode, "stripped": stripped, "buildings": {}, "ghost_candidates": [], "hidden_with_collision": [], "collision_sig": []}
	var ids: Array = L.SPECS.keys()
	ids.sort()
	var bodies := {}
	for id: String in ids:
		bodies[id] = v.get_node(NodePath(String(L.SPECS[id]["path"])))
	for id: String in ids:
		var body := bodies[id] as StaticBody3D
		var ov_b := ov.get_node_or_null(id)
		if arch_off:
			ov_b = null
		var bxf := body.global_transform
		var inv := bxf.affine_inverse()
		var boxes := _boxes_of(body, "body")
		var posts := ov_b.get_node_or_null("Posts") if ov_b else null
		if posts is CollisionObject3D:
			boxes += _boxes_of(posts, "Posts")
		var shell := ov_b.get_node_or_null("Shell") if ov_b else null
		if shell is CollisionObject3D:
			boxes += _boxes_of(shell, "Shell")
		var meshes := _vis_meshes(body, ov_b)
		# 見た目の三角形（局部・世界）
		var wfaces := PackedVector3Array()
		var laabb := AABB()
		var waabb := AABB()
		var first := true
		for mi: MeshInstance3D in meshes:
			var gx := mi.global_transform
			for p in mi.mesh.get_faces():
				var wp := gx * p
				wfaces.append(wp)
				var lp := inv * wp
				if first:
					laabb = AABB(lp, Vector3.ZERO)
					waabb = AABB(wp, Vector3.ZERO)
					first = false
				else:
					laabb = laabb.expand(lp)
					waabb = waabb.expand(wp)
		var vb := StaticBody3D.new()
		vb.collision_layer = VIS_LAYER
		vb.collision_mask = 0
		var vcs := CollisionShape3D.new()
		var cps := ConcavePolygonShape3D.new()
		cps.backface_collision = true
		cps.set_faces(wfaces)
		vcs.shape = cps
		vb.add_child(vcs)
		root.add_child(vb)
		await physics_frame
		# 碰撞の局部範囲（body の Box）
		var cb := AABB()
		var cfirst := true
		var shapes_info: Array = []
		for bx in boxes:
			var lxf: Transform3D = inv * (bx["xf"] as Transform3D)
			var half: Vector3 = bx["half"]
			shapes_info.append({"owner": bx["owner"], "cls": bx["cls"], "local_center": _v(lxf.origin), "size": _v(half * 2.0), "node": bx["node"]})
			if not bx["owner"] in ["body", "Shell"]:
				continue
			for sx in [-1, 1]:
				for sy in [-1, 1]:
					for sz in [-1, 1]:
						var cp := lxf * Vector3(half.x * sx, half.y * sy, half.z * sz)
						if cfirst:
							cb = AABB(cp, Vector3.ZERO)
							cfirst = false
						else:
							cb = cb.expand(cp)
		var ext := cb.merge(laabb)
		# 4 面の射線
		var sides := {"front(+z)": [Vector3(0, 0, 1), Vector3(1, 0, 0)], "back(-z)": [Vector3(0, 0, -1), Vector3(1, 0, 0)],
			"right(+x)": [Vector3(1, 0, 0), Vector3(0, 0, 1)], "left(-x)": [Vector3(-1, 0, 0), Vector3(0, 0, 1)]}
		var side_res := {}
		for sname: String in sides:
			var nrm: Vector3 = sides[sname][0]
			var tan: Vector3 = sides[sname][1]
			var far_n: float = maxf(absf(ext.position.dot(nrm)), absf((ext.position + ext.size).dot(nrm))) + 3.0
			var u0: float = minf(ext.position.dot(tan), (ext.position + ext.size).dot(tan)) - 0.5
			var u1: float = maxf(ext.position.dot(tan), (ext.position + ext.size).dot(tan)) + 0.5
			var bands := {"player": PLAYER_H, "camera": CAMERA_H}
			var bres := {}
			for band: String in bands:
				var st := {"n": 0, "col_ahead": 0, "col_only": 0, "vis_ahead": 0, "vis_only": 0, "max_col_ahead": 0.0, "max_vis_ahead": 0.0, "worst": []}
				for h: float in bands[band]:
					var u := u0
					while u <= u1 + 1e-4:
						var lo := nrm * far_n + tan * u + Vector3(0, h, 0)
						var wo := bxf * lo
						var wd := (bxf.basis * -nrm).normalized()
						var length := far_n * 2.0
						var d_col := INF
						var who := ""
						for bx in boxes:
							if (bx["half"] as Vector3) == Vector3.ZERO:
								continue
							var t := ray_obb(wo, wd, bx["xf"], bx["half"])
							if t < d_col:
								d_col = t
								who = bx["owner"]
						if d_col > length:
							d_col = INF
						var q := PhysicsRayQueryParameters3D.create(wo, wo + wd * length, VIS_LAYER)
						q.hit_back_faces = true
						var hit := space.intersect_ray(q)
						var d_vis: float = wo.distance_to(hit["position"]) if not hit.is_empty() else INF
						if d_col == INF and d_vis == INF:
							u += STEP
							continue
						st["n"] += 1
						var kind := ""
						var amt := 0.0
						if d_col < INF and d_vis == INF:
							kind = "col_only"
						elif d_vis < INF and d_col == INF:
							kind = "vis_only"
						elif d_vis - d_col > TOL:
							kind = "col_ahead"
							amt = d_vis - d_col
							st["max_col_ahead"] = maxf(st["max_col_ahead"], amt)
						elif d_col - d_vis > TOL:
							kind = "vis_ahead"
							amt = d_col - d_vis
							st["max_vis_ahead"] = maxf(st["max_vis_ahead"], amt)
						if kind != "":
							st[kind] += 1
							if (st["worst"] as Array).size() < 400:
								(st["worst"] as Array).append([kind, snappedf(u, 0.01), h, snappedf(amt, 0.01), who])
						u += STEP
				bres[band] = st
			side_res[sname] = bres
		# 上からの射線（屋根と碰撞の上面）
		var top := {"n": 0, "box_above_roof": 0, "max_box_above": 0.0, "box_no_vis": 0, "vis_no_box": 0, "roof_above_box_max": 0.0}
		var x := ext.position.x
		while x <= ext.position.x + ext.size.x + 1e-4:
			var z := ext.position.z
			while z <= ext.position.z + ext.size.z + 1e-4:
				var lo := Vector3(x, ext.position.y + ext.size.y + 3.0, z)
				var wo := bxf * lo
				var wd := Vector3.DOWN
				var length := ext.size.y + 6.0
				var t_col := INF
				for bx in boxes:
					if not bx["owner"] in ["body", "Shell"] or (bx["half"] as Vector3) == Vector3.ZERO:
						continue
					t_col = minf(t_col, ray_obb(wo, wd, bx["xf"], bx["half"]))
				var q := PhysicsRayQueryParameters3D.create(wo, wo + wd * length, VIS_LAYER)
				q.hit_back_faces = true
				var hit := space.intersect_ray(q)
				var t_vis: float = wo.distance_to(hit["position"]) if not hit.is_empty() else INF
				if t_col < INF or t_vis < INF:
					top["n"] += 1
					if t_col < INF and t_vis == INF:
						top["box_no_vis"] += 1
					elif t_vis < INF and t_col == INF:
						top["vis_no_box"] += 1
					elif t_vis - t_col > 0.3:
						top["box_above_roof"] += 1
						top["max_box_above"] = maxf(top["max_box_above"], t_vis - t_col)
					elif t_col - t_vis > 0.0:
						top["roof_above_box_max"] = maxf(top["roof_above_box_max"], t_col - t_vis)
				z += STEP
			x += STEP
		# 戸口の前（碰撞体・地形以外）
		var kit := body.get_node_or_null("Kit")
		var dcx := float(kit.get_meta("door_cx", 0.0)) if kit else 0.0
		var dw := float(kit.get_meta("door_w", 1.7)) if kit else 1.7
		var zf := cb.position.z + cb.size.z
		var door_hits: Array = []
		var qs := PhysicsShapeQueryParameters3D.new()
		var dbox := BoxShape3D.new()
		dbox.size = Vector3(maxf(dw - 0.2, 0.6), 1.7, 1.95)
		qs.shape = dbox
		qs.transform = bxf * Transform3D(Basis.IDENTITY, Vector3(dcx, 0.1 + 0.85, zf + 0.05 + 0.975))
		qs.collision_mask = 1
		qs.exclude = [terrain.get_rid(), body.get_rid()] + ([shell.get_rid()] if shell is CollisionObject3D else [])
		for r in space.intersect_shape(qs, 32):
			var co := r["collider"] as Node
			if co:
				door_hits.append(String(v.get_path_to(co)))
		var qv := PhysicsShapeQueryParameters3D.new()
		qv.shape = dbox
		qv.transform = qs.transform
		qv.collision_mask = VIS_LAYER
		var door_vis := space.intersect_shape(qv, 4).size() > 0
		# 隣棟との実接触
		var contacts: Array = []
		for bx in boxes:
			if not bx["owner"] in ["body", "Shell"] or (bx["half"] as Vector3) == Vector3.ZERO:
				continue
			var qc := PhysicsShapeQueryParameters3D.new()
			var bs := BoxShape3D.new()
			bs.size = (bx["half"] as Vector3) * 2.0
			qc.shape = bs
			qc.transform = bx["xf"]
			qc.collision_mask = 1
			qc.exclude = [terrain.get_rid(), body.get_rid()] + ([posts.get_rid()] if posts is CollisionObject3D else []) + ([shell.get_rid()] if shell is CollisionObject3D else [])
			var pts := space.collide_shape(qc, 32)
			var maxd := 0.0
			for k in range(0, pts.size(), 2):
				maxd = maxf(maxd, (pts[k] as Vector3).distance_to(pts[k + 1]))
			var rest := space.intersect_shape(qc, 32)
			for r in rest:
				var co := r["collider"] as Node
				if co and co != body:
					contacts.append([String(v.get_path_to(co)), snappedf(maxd, 0.001)])
		report["buildings"][id] = {
			"path": String(L.SPECS[id]["path"]), "hide": L.SPECS[id]["hide"],
			"layer": body.collision_layer, "mask": body.collision_mask,
			"collision": shapes_info, "collision_local_aabb": _aabb(cb),
			"visual_meshes": meshes.size(), "visual_tris": wfaces.size() / 3,
			"visual_local_aabb": _aabb(laabb), "visual_world_aabb": _aabb(waabb),
			"sides": side_res, "top": top,
			"door": {"cx": dcx, "w": dw, "colliders": door_hits, "visual_in_corridor": door_vis},
			"contacts": contacts,
		}
		vb.queue_free()
		await physics_frame
		var fs: Dictionary = side_res["front(+z)"]
		print("[W9FIX] %s %-22s vis L(%.2f..%.2f, y..%.2f, %.2f..%.2f) col L(%.2f..%.2f, y..%.2f, %.2f..%.2f) | player col_only %d col_ahead %d vis_ahead %d vis_only %d | top box_above %d (max %.2f) | door %s" % [
			mode, id, laabb.position.x, laabb.end.x, laabb.end.y, laabb.position.z, laabb.end.z, cb.position.x, cb.end.x, cb.end.y, cb.position.z, cb.end.z,
			_sum(side_res, "player", "col_only"), _sum(side_res, "player", "col_ahead"), _sum(side_res, "player", "vis_ahead"), _sum(side_res, "player", "vis_only"),
			top["box_above_roof"], top["max_box_above"], str(door_hits)])
	# 全村：見えない碰撞体の候補・隠された節點の碰撞体・碰撞の署名
	var hidden_nodes: Array = []
	for h in ov.get("_hidden"):
		if is_instance_valid(h[0]):
			hidden_nodes.append(h[0])
	for co in v.find_children("*", "CollisionObject3D", true, false):
		var c := co as CollisionObject3D
		var shapes: Array = []
		for cs in c.get_children():
			if cs is CollisionShape3D and (cs as CollisionShape3D).shape != null:
				shapes.append(cs)
		var en := 0
		var caabb := AABB()
		var cf := true
		for cs: CollisionShape3D in shapes:
			if cs.disabled:
				continue
			en += 1
			var a := _shape_aabb(cs)
			if cf:
				caabb = a
				cf = false
			else:
				caabb = caabb.merge(a)
		var path := String(v.get_path_to(c))
		report["collision_sig"].append([path, c.get_class(), c.collision_layer, c.collision_mask, en, shapes.size(), _aabb(caabb) if en > 0 else []])
		if en == 0 or (c.collision_layer & 1) == 0 or c is Area3D:
			continue
		for hn: Node in hidden_nodes:
			if hn == c or hn.is_ancestor_of(c) or c.is_ancestor_of(hn) and hn.get_parent() == c:
				report["hidden_with_collision"].append([path, String(v.get_path_to(hn))])
		if path.begins_with("Collision/") or path.begins_with("Roads/") and path.contains("Ramp"):
			continue
		var unit: Node = c
		if c.find_children("*", "MeshInstance3D", true, false).is_empty() and c.get_parent() != v:
			unit = c.get_parent()
		var seen_vis := false
		var any_mesh := false
		for mi in unit.find_children("*", "MeshInstance3D", true, false):
			any_mesh = true
			if (mi as MeshInstance3D).is_visible_in_tree() and (mi as MeshInstance3D).mesh != null:
				var ma := (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
				if ma.grow(0.1).intersects(caabb):
					seen_vis = true
					break
		if not seen_vis and unit is MeshInstance3D and (unit as MeshInstance3D).is_visible_in_tree():
			seen_vis = true
		if not seen_vis:
			var mm_vis := false
			for mmi in unit.find_children("*", "MultiMeshInstance3D", true, false):
				if (mmi as Node3D).is_visible_in_tree():
					mm_vis = true
			report["ghost_candidates"].append([path, _aabb(caabb), "no_mesh_in_unit" if not any_mesh else "no_visible_mesh_overlapping", "multimesh_visible" if mm_vis else ""])
	print("[W9FIX] %s 見えない碰撞体の候補 %d・隠された節點の碰撞体 %d・碰撞体 %d" % [mode, report["ghost_candidates"].size(), report["hidden_with_collision"].size(), report["collision_sig"].size()])
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(report, " "))
		f.close()
		print("[W9FIX] → ", out_path)
	quit(0)


static func _shape_aabb(cs: CollisionShape3D) -> AABB:
	var sh := cs.shape
	var a := AABB()
	if sh is BoxShape3D:
		a = AABB(-(sh as BoxShape3D).size * 0.5, (sh as BoxShape3D).size)
	elif sh is ConcavePolygonShape3D or sh is ConvexPolygonShape3D:
		var pts: PackedVector3Array = (sh as ConcavePolygonShape3D).get_faces() if sh is ConcavePolygonShape3D else (sh as ConvexPolygonShape3D).points
		if pts.size() > 0:
			a = AABB(pts[0], Vector3.ZERO)
			for p in pts:
				a = a.expand(p)
	elif sh is CylinderShape3D:
		var r := (sh as CylinderShape3D).radius
		a = AABB(Vector3(-r, -(sh as CylinderShape3D).height * 0.5, -r), Vector3(r * 2, (sh as CylinderShape3D).height, r * 2))
	elif sh is CapsuleShape3D:
		var r2 := (sh as CapsuleShape3D).radius
		a = AABB(Vector3(-r2, -(sh as CapsuleShape3D).height * 0.5, -r2), Vector3(r2 * 2, (sh as CapsuleShape3D).height, r2 * 2))
	elif sh is SphereShape3D:
		var r3 := (sh as SphereShape3D).radius
		a = AABB(Vector3(-r3, -r3, -r3), Vector3(r3, r3, r3) * 2)
	else:
		a = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	return cs.global_transform * a


static func _sum(side_res: Dictionary, band: String, key: String) -> int:
	var n := 0
	for s in side_res:
		n += int(side_res[s][band][key])
	return n


static func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]


static func _aabb(a: AABB) -> Array:
	return [_v(a.position), _v(a.end)]
