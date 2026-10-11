extends SceneTree
## P12 Final Cleanup A（只讀、headless）：三項 plan gate 失敗の「重算計画 vs 封存実物」比較と、実物が今の幾何で衝突するか。
##   godot --headless --path . --script res://tools/p12/probe_plan_drift.gd
## WATER：WatersideP9 実物ノード（名前＝%03d_id）と WS.plan() の同 index 件の位置差、実物の _blocked（通路）。
## HUX ：HumanUseExpansionP10 実物 015／016 と P11 R2D 支線碰撞（ZoneWater Br*）の重なり・中心線距離。
const WS := preload("res://tools/village_v2_waterside_lib.gd")
const ZL := preload("res://tools/village_v2_farmland_zone.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/village_v2/layout_v2.json"))
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	var ov := v.get_node("Vegetation/" + WS.NODE_NAME)
	var actual := {}
	for n in ov.find_children("*", "Node3D", true, false):
		var nm := String(n.name)
		if nm.length() > 4 and nm.substr(0, 3).is_valid_int() and nm[3] == "_":
			actual[nm] = (n as Node3D).global_position
	ov.get_parent().remove_child(ov)
	root.add_child(v)
	await physics_frame
	await physics_frame
	var P: Dictionary = WS.plan(v, L)
	var H: Dictionary = P["H"]
	var R = P["R"]
	var diff := 0
	var first := ""
	var cmp := 0
	for i in (P["items"] as Array).size():
		var it: Dictionary = P["items"][i]
		var nm := "%03d_%s" % [i, it["id"]]
		if not actual.has(nm):
			continue
		cmp += 1
		var a: Vector3 = actual[nm]
		if Vector2(a.x, a.z).distance_to(it["p"]) > 0.01:
			diff += 1
			if first == "":
				first = "%s 実物 %s → 計画 %s" % [nm, Vector2(a.x, a.z), it["p"]]
	# 実物の通路衝突（plan gate 3 と同じ _blocked、地面植物は半径 0.4）
	var blk := []
	for nm in actual:
		var a: Vector3 = actual[nm]
		var plant := String(nm).contains("wk_reed") or String(nm).contains("wk_iris") or String(nm).contains("wk_sedge")
		if not (plant or String(nm).contains("wk_")):
			continue
		if WS._blocked(Vector2(a.x, a.z), 0.4 if plant else 0.0, R, {"boxes": [], "walkways": H["walkways"], "entries": H["entries"], "dragon_walkway": H["dragon_walkway"]}, []):
			blk.append("%s@%s" % [nm, Vector2(a.x, a.z).snappedf(0.01)])
	print("[DRIFT] WATER 実物 %d 件・計画 %d 件・照合 %d：位置が違う %d（最初：%s）；実物の wk_* が通路に入る %d %s" % [
		actual.size(), (P["items"] as Array).size(), cmp, diff, first, blk.size(), str(blk.slice(0, 4))])
	# HUX：実物 015／016 と R2D 支線
	var hx := v.get_node_or_null("HumanUseExpansionP10")
	var zw := v.get_node("Districts/FarmlandEast/FarmlandP8/Irrigation/ZoneWater")
	var sp := v.get_world_3d().direct_space_state
	var t0: Array = ZL.BRANCHES["T0"]["pts"]
	var pl := PackedVector2Array()
	for q in t0:
		pl.append(Vector2(q[0], q[1]))
	for nm in ["015_mk_tsumini", "016_hu_seoikago"]:
		var n := hx.find_child(nm, true, false) as Node3D
		var p := n.global_position
		var best := INF
		for k in pl.size() - 1:
			best = minf(best, Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), pl[k], pl[k + 1]).distance_to(Vector2(p.x, p.z)))
		var ab := AABB()
		var first_mi := true
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			if String(mi.name).contains("LOD1"):
				continue
			var w := mi.global_transform * mi.get_aabb()
			ab = w if first_mi else ab.merge(w)
			first_mi = false
		var q := PhysicsShapeQueryParameters3D.new()
		var bx := BoxShape3D.new()
		bx.size = ab.size
		q.shape = bx
		q.transform = Transform3D(Basis(), ab.get_center())
		var hits := []
		for h in sp.intersect_shape(q, 16):
			if h["collider"] == zw:
				var sh: Node = zw.shape_owner_get_owner(zw.shape_find_owner(h["shape"]))
				if String(sh.name).begins_with("Br"):
					hits.append(String(sh.name))
		print("[DRIFT] HUX 実物 %s %s：T0 中心線まで %.2f m（土渠外法半幅 %.1f）、AABB %s と R2D 支線碰撞の重なり %s" % [nm, p.snappedf(0.01), best, ZL.BR_HALF, ab.size.snappedf(0.01), str(hits)])
	quit(0)
