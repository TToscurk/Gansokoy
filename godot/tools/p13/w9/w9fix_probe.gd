extends SceneTree
## P13 W9 FIX：外形碰撞箱（Shell）の BEFORE／AFTER を実際の物理照会で比べる（唯讀・場景ファイルは書かない）。
##   godot --headless --path godot --script res://tools/p13/w9/w9fix_probe.gd -- --out=<json> [--ids=a,b]
## 同じ読み込み状態で 2 つの碰撞構成を切り替える（物理だけ。見た目は同じ W9R2）：
##   before＝修正前（body の元の箱が有効・Shell 無効）／after＝修正後（arch_w9r2.gd の _shell の結果：元の箱無効・Shell 有効）
## 1. 歩行（玩家 capsule：characters/yoriichi/player_yoriichi.tscn の実寸・底を +0.36 m＝Auto-Step 0.35 を越えない物だけ当たる）
##    各立面に垂直に、立面の外 3 m から建物の中へ cast_motion。止まった相手がこの建物の碰撞（body／Shell／Posts）のときだけ数える。
##    d_col＝碰撞で止まる距離・d_vis＝同じ capsule が建物の見た目（三角形）に触れる距離。
##      ghost＝d_vis − d_col > 0.30（何も見えない所で止まる＝見えない壁）／pen＝d_col − d_vis > 0.30（見た目にめり込む）
## 2. SpringArm（player_camera_adapter と同じ条件：足元 +1.70 m・背後・7.5 m・mask 1・ray）。俯仰は既定 −0.18 と、使用者がマウスで
##    下げた −0.5／−0.9（pitch_min −1.1 の範囲内）の 3 つ。立面の外 1.0／2.5 m・立面に沿って 1 m ごと・16 方位。
##    見た目＝W9R2 の 46 棟全部の三角形（隣の棟も含む）。腕の長さ a（碰撞）と av（見た目）：
##      inv＝a が av より 0.30 m 以上短く、当たったのが 46 棟の碰撞（見えない天井・壁）／clip＝a が av を 0.30 m 以上越える（壁・屋根の中にカメラ）
##      after と before の差：worse_bad＝after が 0.30 m 以上短くなり、しかも見た目より手前（新しい見えない縮み）
##                          worse_ok＝after が短くなったが見た目の面で止まる（以前は壁・屋根を通り抜けていた）
##                          better＝after が長くなり見た目を越えない／better_clip＝長くなったが見た目を越える（以前は見えない所で止まり、今は屋根などに入る）
const L := preload("res://tools/p13/w9/w9r2_lib.gd")
const VIS_LAYER := 1 << 19
const TOL := 0.30
const STEP_UP := 0.36
const ARM_UP := 1.70
const ARM_ELEV := [0.18, 0.5, 0.9]
const VIS_ALL := 1 << 18
const ARM_MAX := 7.5

var space: PhysicsDirectSpaceState3D
var terrain_rid: RID
var cap_r := 0.3
var cap_h := 1.7


func _init() -> void:
	_run.call_deferred()


func _arg(k: String, d: String) -> String:
	for s in OS.get_cmdline_user_args():
		if s.begins_with(k + "="):
			return s.trim_prefix(k + "=")
	return d


func _set_cfg(v: Node, ov: Node, after: bool) -> void:
	for b in ov.get_children():
		var sh := b.get_node_or_null("Shell")
		if sh == null:
			continue
		var body := v.get_node(NodePath(String(b.get_meta("body_path"))))
		for cs in body.get_children():
			if cs is CollisionShape3D:
				(cs as CollisionShape3D).disabled = after
		for cs in sh.get_children():
			if cs is CollisionShape3D:
				(cs as CollisionShape3D).disabled = not after


func _ground(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 30, 0), p - Vector3(0, 30, 0), 1)
	q.collide_with_bodies = true
	var h := space.intersect_ray(q)
	# 地形だけを見る（建物の上を地面としない）
	var tries := 0
	while not h.is_empty() and h["rid"] != terrain_rid and tries < 4:
		q.exclude = q.exclude + [h["rid"]]
		h = space.intersect_ray(q)
		tries += 1
	return (h["position"] as Vector3).y if not h.is_empty() else p.y


func _cast(xf: Transform3D, motion: Vector3, mask: int, owners: Array) -> Array:
	## 戻り値 [距離（INF＝当たらない）, 当たった相手がこの建物か]
	var cap := CapsuleShape3D.new()
	cap.radius = cap_r
	cap.height = cap_h
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = xf
	q.motion = motion
	q.collision_mask = mask
	q.exclude = [terrain_rid]
	if not space.intersect_shape(q, 1).is_empty():
		return [-1.0, false]
	var r := space.cast_motion(q)
	if r[1] >= 1.0:
		return [INF, false]
	var d: float = motion.length() * r[0]
	q.transform = Transform3D(xf.basis, xf.origin + motion * r[1])
	q.motion = Vector3.ZERO
	var info := space.get_rest_info(q)
	var mine := not info.is_empty() and owners.has(info["rid"])
	return [d, mine, (info["point"] as Vector3) if not info.is_empty() else Vector3.INF]


func _arm(o: Vector3, dir: Vector3, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(o, o + dir * ARM_MAX, mask)
	q.hit_back_faces = true
	var h := space.intersect_ray(q)
	if h.is_empty():
		return {"d": ARM_MAX, "rid": RID(), "p": Vector3.INF, "n": Vector3.ZERO}
	return {"d": o.distance_to(h["position"]), "rid": h["rid"], "p": h["position"], "n": h["normal"]}


static func _lv(inv_: Transform3D, p: Vector3) -> Array:
	if p == Vector3.INF:
		return []
	var l := inv_ * p
	return [snappedf(l.x, 0.01), snappedf(l.y, 0.01), snappedf(l.z, 0.01)]


static func _lv3(b: Basis, n: Vector3) -> Array:
	var l := b * n
	return [snappedf(l.x, 0.01), snappedf(l.y, 0.01), snappedf(l.z, 0.01)]


func _run() -> void:
	var pl := (load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene).instantiate()
	for c in pl.find_children("*", "CollisionShape3D", true, false):
		if (c as CollisionShape3D).shape is CapsuleShape3D and c.get_parent() == pl:
			cap_r = ((c as CollisionShape3D).shape as CapsuleShape3D).radius
			cap_h = ((c as CollisionShape3D).shape as CapsuleShape3D).height
	pl.free()
	var v := (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 8:
		await process_frame
	for i in 3:
		await physics_frame
	space = (v as Node3D).get_world_3d().direct_space_state
	terrain_rid = (v.get_node("Collision/TerrainCollision") as CollisionObject3D).get_rid()
	var ov := v.get_node("ArchW9R2P13")
	var ids: Array = Array(_arg("--ids", "").split(",")) if _arg("--ids", "") != "" else L.SPECS.keys()
	ids.sort()
	# 46 棟全部の見た目（VIS_ALL）と、46 棟の碰撞の RID（body／Posts／Shell）
	var spec_rids: Array = []
	var rid_name := {}
	var vis_name := {}
	for sid: String in L.SPECS:
		var sb := v.get_node(NodePath(String(L.SPECS[sid]["path"]))) as StaticBody3D
		var so := ov.get_node(sid)
		spec_rids.append(sb.get_rid())
		rid_name[sb.get_rid()] = sid + "/body"
		for nm in ["Posts", "Shell"]:
			var sn := so.get_node_or_null(nm)
			if sn is CollisionObject3D:
				spec_rids.append((sn as CollisionObject3D).get_rid())
				rid_name[(sn as CollisionObject3D).get_rid()] = sid + "/" + nm
		var sms: Array = []
		var sk := sb.get_node_or_null("Kit/LOD0")
		if sk:
			for mi in sk.get_children():
				if mi is MeshInstance3D and (mi as MeshInstance3D).is_visible_in_tree():
					sms.append(mi)
		for c in so.get_children():
			if c is MeshInstance3D and String(c.name) == "L0" and (c as MeshInstance3D).is_visible_in_tree():
				sms.append(c)
		var all_faces := PackedVector3Array()
		for mi: MeshInstance3D in sms:
			for p in mi.mesh.get_faces():
				all_faces.append(mi.global_transform * p)
		var vball := StaticBody3D.new()
		vball.collision_layer = VIS_ALL
		vball.collision_mask = 0
		var vacs := CollisionShape3D.new()
		var vacp := ConcavePolygonShape3D.new()
		vacp.backface_collision = true
		vacp.set_faces(all_faces)
		vacs.shape = vacp
		vball.add_child(vacs)
		root.add_child(vball)
		vis_name[vball.get_rid()] = sid
	await physics_frame
	var out := {"capsule": [cap_r, cap_h], "buildings": {}}
	for id: String in ids:
		var body := v.get_node(NodePath(String(L.SPECS[id]["path"]))) as StaticBody3D
		var ov_b := ov.get_node(id)
		var bxf := body.global_transform
		var inv := bxf.affine_inverse()
		var owners: Array = [body.get_rid()]
		for nm in ["Posts", "Shell"]:
			var n := ov_b.get_node_or_null(nm)
			if n is CollisionObject3D:
				owners.append((n as CollisionObject3D).get_rid())
		# 見た目（Kit LOD0 の見えている構件＋overlay L0）を VIS_LAYER の三角形に
		var faces := PackedVector3Array()
		var la := AABB()
		var first := true
		var meshes: Array = []
		var kit := body.get_node_or_null("Kit/LOD0")
		if kit:
			for mi in kit.get_children():
				if mi is MeshInstance3D and (mi as MeshInstance3D).is_visible_in_tree():
					meshes.append(mi)
		for c in ov_b.get_children():
			if c is MeshInstance3D and String(c.name) == "L0" and (c as MeshInstance3D).is_visible_in_tree():
				meshes.append(c)
		for mi: MeshInstance3D in meshes:
			for p in mi.mesh.get_faces():
				var wp := mi.global_transform * p
				faces.append(wp)
				la = AABB(inv * wp, Vector3.ZERO) if first else la.expand(inv * wp)
				first = false
		var vb := StaticBody3D.new()
		vb.collision_layer = VIS_LAYER
		vb.collision_mask = 0
		var vcs := CollisionShape3D.new()
		var cps := ConcavePolygonShape3D.new()
		cps.backface_collision = true
		cps.set_faces(faces)
		vcs.shape = cps
		vb.add_child(vcs)
		root.add_child(vb)
		var res := {}
		for cfg in ["before", "after"]:
			_set_cfg(v, ov, cfg == "after")
			for i in 2:
				await physics_frame
			var walk := {"n": 0, "ghost": 0, "pen": 0, "max_ghost": 0.0, "max_pen": 0.0, "start_inside": 0, "samples": []}
			var cam := {"inv": 0, "clip": 0, "arm": [], "spec": [], "vis": [], "who": [], "at": [], "in": [], "hp": [], "visinfo": []}
			# 4 面
			for side in [[Vector3(0, 0, 1), Vector3(1, 0, 0)], [Vector3(0, 0, -1), Vector3(1, 0, 0)], [Vector3(1, 0, 0), Vector3(0, 0, 1)], [Vector3(-1, 0, 0), Vector3(0, 0, 1)]]:
				var nrm: Vector3 = side[0]
				var tan: Vector3 = side[1]
				var face_d: float = maxf((la.position).dot(nrm), (la.end).dot(nrm))
				var u0: float = minf(la.position.dot(tan), la.end.dot(tan)) + 0.3
				var u1: float = maxf(la.position.dot(tan), la.end.dot(tan)) - 0.3
				var u := u0
				while u <= u1 + 1e-4:
					# 1. 歩行
					var lp: Vector3 = nrm * (face_d + 3.0) + tan * u
					var wp: Vector3 = bxf * lp
					var gy: float = _ground(wp)
					var feet := Vector3(wp.x, gy, wp.z)
					var cxf := Transform3D(Basis.IDENTITY, feet + Vector3(0, STEP_UP + cap_h * 0.5, 0))
					var motion: Vector3 = (bxf.basis * -nrm).normalized() * 12.0
					var c: Array = _cast(cxf, motion, 1, owners)
					var vv: Array = _cast(cxf, motion, VIS_LAYER, [])
					if c[0] < 0.0:
						walk["start_inside"] += 1
					elif c[1] or (c[0] == INF and vv[0] < INF):
						walk["n"] += 1
						var dc: float = c[0]
						var dv: float = vv[0]
						var kind := ""
						if dv - dc > TOL:
							kind = "ghost"
							walk["max_ghost"] = maxf(walk["max_ghost"], minf(dv, 12.0) - dc)
						elif dc - dv > TOL:
							kind = "pen"
							walk["max_pen"] = maxf(walk["max_pen"], minf(dc, 12.0) - dv)
						if kind != "":
							walk[kind] += 1
							if (walk["samples"] as Array).size() < 60:
								var cpl: Vector3 = inv * (vv[2] as Vector3) if (vv[2] as Vector3) != Vector3.INF else Vector3.INF
								(walk["samples"] as Array).append([kind, nrm, snappedf(u, 0.01), snappedf(minf(dc, 99.0), 0.01), snappedf(minf(dv, 99.0), 0.01),
									[snappedf(cpl.x, 0.01), snappedf(cpl.y - (gy - bxf.origin.y), 0.01), snappedf(cpl.z, 0.01)] if cpl != Vector3.INF else []])
					# 2. SpringArm（立面の外 1.0／2.5 m・16 方位・1 m ごと・俯仰 3 つ）
					if fmod(u - u0, 1.0) < 0.26:
						for off in [1.0, 2.5]:
							var ap: Vector3 = bxf * (nrm * (face_d + float(off)) + tan * u)
							var ag: float = _ground(ap)
							var o := Vector3(ap.x, ag + ARM_UP, ap.z)
							# 玩家がそこに立てない（足元 +0.9／+1.7 が碰撞の中）標本は比べない（中から撃つ ray は箱に当たらない）
							var pq := PhysicsPointQueryParameters3D.new()
							pq.collision_mask = 1
							pq.exclude = [terrain_rid]
							pq.position = o
							var inside := not space.intersect_point(pq, 1).is_empty()
							pq.position = Vector3(ap.x, ag + 0.9, ap.z)
							inside = inside or not space.intersect_point(pq, 1).is_empty()
							for el: float in ARM_ELEV:
								for k in 16:
									var yaw := TAU * k / 16.0
									var dir := Vector3(-sin(yaw) * cos(el), sin(el), -cos(yaw) * cos(el))
									var a: Dictionary = _arm(o, dir, 1)
									(cam["arm"] as Array).append(float(a["d"]))
									(cam["in"] as Array).append(inside)
									(cam["who"] as Array).append(String(rid_name.get(a["rid"], "")))
									(cam["at"] as Array).append([snappedf(o.x, 0.01), snappedf(o.z, 0.01), k, el])
									(cam["spec"] as Array).append(spec_rids.has(a["rid"]))
									(cam["hp"] as Array).append(a["p"])
									if cfg == "before":
										var avd: Dictionary = _arm(o, dir, VIS_ALL)
										(cam["vis"] as Array).append(float(avd["d"]))
										(cam["visinfo"] as Array).append([avd["p"], avd["n"], String(vis_name.get(avd["rid"], ""))])
					u += 0.25
			res[cfg] = {"walk": walk, "cam": cam}
		# 腕：見た目（46 棟）との比較と before／after の比較
		var vis_arr: Array = res["before"]["cam"]["vis"]
		var cmp := {"n": vis_arr.size(), "worse_bad": 0, "worse_ok": 0, "better": 0, "better_clip": 0, "max_worse_bad": 0.0, "bad_by": {}, "bad_samples": [], "skipped_inside": 0, "trans": {}, "reg": []}
		for cfg in ["before", "after"]:
			var cm: Dictionary = res[cfg]["cam"]
			var nin := 0
			var ncl := 0
			for i in vis_arr.size():
				if cm["in"][i]:
					continue
				var a: float = cm["arm"][i]
				var av: float = vis_arr[i]
				if cm["spec"][i] and av - a > TOL:
					nin += 1
				elif a - av > TOL:
					ncl += 1
			cm["inv"] = nin
			cm["clip"] = ncl
		for i in vis_arr.size():
			if res["before"]["cam"]["in"][i] or res["after"]["cam"]["in"][i]:
				cmp["skipped_inside"] += 1
				continue
			var b0: float = res["before"]["cam"]["arm"][i]
			var a0: float = res["after"]["cam"]["arm"][i]
			var av: float = vis_arr[i]
			var sb := "ok" if absf(b0 - av) <= TOL else ("inv" if av - b0 > TOL else "clip")
			var sa := "ok" if absf(a0 - av) <= TOL else ("inv" if av - a0 > TOL else "clip")
			var tk := sb + ">" + sa
			cmp["trans"][tk] = int(cmp["trans"].get(tk, 0)) + 1
			if tk in ["ok>clip", "ok>inv", "clip>inv"] and (cmp["reg"] as Array).size() < 400:
				var vi: Array = res["before"]["cam"]["visinfo"][i]
				var vp: Vector3 = vi[0]
				var hpa: Vector3 = res["after"]["cam"]["hp"][i]
				var hpb: Vector3 = res["before"]["cam"]["hp"][i]
				(cmp["reg"] as Array).append({"tk": tk, "at": res["after"]["cam"]["at"][i], "b": snappedf(b0, 0.01), "a": snappedf(a0, 0.01), "v": snappedf(av, 0.01),
					"vis_b": vi[2], "vis_l": _lv(inv, vp), "vis_n": _lv3(inv.basis, vi[1]), "after_who": res["after"]["cam"]["who"][i], "before_who": res["before"]["cam"]["who"][i],
					"after_l": _lv(inv, hpa), "before_l": _lv(inv, hpb)})
			if b0 - a0 > TOL:
				if av - a0 > TOL:
					cmp["worse_bad"] += 1
					cmp["max_worse_bad"] = maxf(cmp["max_worse_bad"], b0 - a0)
					var who: String = res["after"]["cam"]["who"][i]
					cmp["bad_by"][who] = int(cmp["bad_by"].get(who, 0)) + 1
					if (cmp["bad_samples"] as Array).size() < 12:
						(cmp["bad_samples"] as Array).append([res["after"]["cam"]["at"][i], snappedf(b0, 0.01), snappedf(a0, 0.01), snappedf(av, 0.01), who])
				else:
					cmp["worse_ok"] += 1
			elif a0 - b0 > TOL:
				if a0 - av > TOL:
					cmp["better_clip"] += 1
				else:
					cmp["better"] += 1
		for cfg in ["before", "after"]:
			for k in ["arm", "spec", "vis", "who", "at", "in", "hp", "visinfo"]:
				res[cfg]["cam"].erase(k)
		res["arm_cmp"] = cmp
		res["has_shell"] = ov_b.get_node_or_null("Shell") != null
		out["buildings"][id] = res
		var rb: Dictionary = res["before"]
		var ra: Dictionary = res["after"]
		print("[W9PROBE] %s %s walk ghost %d→%d pen %d→%d (n %d) | cam inv %d→%d clip %d→%d (n %d) | worse_bad %d (max %.2f) worse_ok %d better %d better_clip %d" % [
			id, "SHELL" if res["has_shell"] else "-    ", rb["walk"]["ghost"], ra["walk"]["ghost"], rb["walk"]["pen"], ra["walk"]["pen"], ra["walk"]["n"],
			rb["cam"]["inv"], ra["cam"]["inv"], rb["cam"]["clip"], ra["cam"]["clip"], cmp["n"], cmp["worse_bad"], cmp["max_worse_bad"], cmp["worse_ok"], cmp["better"], cmp["better_clip"]])
		vb.queue_free()
		_set_cfg(v, ov, true)
		await physics_frame
	var f := FileAccess.open(_arg("--out", "user://w9fix_probe.json"), FileAccess.WRITE)
	if f == null:
		push_error("cannot write")
		quit(1)
		return
	f.store_string(JSON.stringify(out))
	f.close()
	quit(0)
