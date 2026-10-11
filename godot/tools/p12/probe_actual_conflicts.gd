extends SceneTree
## P12 Final Cleanup A（只讀、非 headless：MultiMesh 實例を讀むため）：封存 overlay の「実物」が現在の幾何と衝突するか。
##   godot --path . --script res://tools/p12/probe_actual_conflicts.gd
## WATER：WatersideP9 実物の wk_* ノード（木の中で global 座標）→ gate と同じ _blocked（植物 r 0.4）。
## MEADOW：MeadowP9 実物（Near／Mid）の株が P11 R2D 支線の土渠外法（中心線 ±BR_HALF）・道路面に入る数。
const WS := preload("res://tools/village_v2_waterside_lib.gd")
const ZL := preload("res://tools/village_v2_farmland_zone.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"

func _init() -> void:
	_run.call_deferred()

func _seg_d(p: Vector2, pl: PackedVector2Array) -> float:
	var b := INF
	for k in pl.size() - 1:
		b = minf(b, Geometry2D.get_closest_point_to_segment(p, pl[k], pl[k + 1]).distance_to(p))
	return b

func _run() -> void:
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/village_v2/layout_v2.json"))
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 6:
		await process_frame
	await physics_frame
	var H := WS.hero_geo(v)
	var R := WS.RLib.road_sampler(v)
	var ov := v.get_node("Vegetation/" + WS.NODE_NAME)
	var n := 0
	var blk := []
	for c in ov.find_children("*", "Node3D", true, false):
		var nm := String(c.name)
		if not (nm.length() > 4 and nm.substr(0, 3).is_valid_int() and nm[3] == "_" and nm.contains("wk_")):
			continue
		n += 1
		var p := (c as Node3D).global_position
		var plant := nm.contains("reed") or nm.contains("iris") or nm.contains("sedge")
		if WS._blocked(Vector2(p.x, p.z), 0.4 if plant else 0.0, R, {"boxes": [], "walkways": H["walkways"], "entries": H["entries"], "dragon_walkway": H["dragon_walkway"]}, []):
			blk.append("%s@%s" % [nm, Vector2(p.x, p.z).snappedf(0.01)])
	print("[ACTUAL] WATER 実物 wk_* %d 件、通路（gate と同じ判定）に入る %d %s" % [n, blk.size(), str(blk.slice(0, 6))])
	# MeadowP9 実物
	var lines := []
	for bid in ZL.BRANCHES:
		var pl := PackedVector2Array()
		for q in ZL.BRANCHES[bid]["pts"]:
			pl.append(Vector2(q[0], q[1]))
		lines.append(pl)
	var area := Rect2(320, -55, 50, 140)
	var tot := 0
	var in_br := 0
	var on_road := 0
	var ex := []
	for mmi: MultiMeshInstance3D in v.get_node("Vegetation/MeadowP9").find_children("*", "MultiMeshInstance3D", true, false):
		var mm := mmi.multimesh
		if mm == null:
			continue
		var xf := mmi.global_transform
		for i in mm.instance_count:
			var o := (xf * mm.get_instance_transform(i)).origin
			tot += 1
			var p2 := Vector2(o.x, o.z)
			if not area.has_point(p2):
				continue
			for pl in lines:
				if _seg_d(p2, pl) < ZL.BR_HALF:
					in_br += 1
					if ex.size() < 4:
						ex.append(p2.snappedf(0.1))
					break
			if not is_nan(R.h(p2.x, p2.y)):
				on_road += 1
	print("[ACTUAL] MEADOW 実物 instance %d（全 LOD）；P11 R2D 支線の土渠外法内 %d %s；支線周辺で道路面上 %d" % [tot, in_br, str(ex), on_road])
	quit(0)
