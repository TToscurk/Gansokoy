extends SceneTree
## P12 Final Cleanup A（只讀、headless）：三項 plan gate の重算入力に P11 R2D の新幾何（ZoneIrrigation/Branches）が入っているかの切り分け。
##   godot --headless --path . --script res://tools/p12/probe_branch_replay.gd -- [--hide-branches]
## MeadowP9 規劃株数（ENV と同じ前処理）・HUX 015／016 の計画位置・WATER の wk_reed_s 近傍、を同一プロセスで出す。
const MD := preload("res://tools/village_v2_meadow_lib.gd")
const WS := preload("res://tools/village_v2_waterside_lib.gd")
const HX := preload("res://tools/village_v2_human_use_exp_lib.gd")
const HU := preload("res://tools/village_v2_human_use_lib.gd")
const SCENE := "res://maps/village_v2/village_v2.tscn"
const BR := "Districts/FarmlandEast/FarmlandP8/ZoneWorks/ZoneIrrigation/Branches"

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var hide := "--hide-branches" in OS.get_cmdline_user_args()
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/village_v2/layout_v2.json"))
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	for nm in ["Vegetation/GroundcoverP9", "Vegetation/MeadowP9", "Vegetation/" + WS.NODE_NAME, HX.NODE_NAME]:
		var o := v.get_node_or_null(nm)
		if o:
			o.get_parent().remove_child(o)
			o.free()
	if hide:
		var b := v.get_node_or_null(BR)
		print("[REPLAY] Branches node ", b != null)
		if b:
			b.get_parent().remove_child(b)
			b.free()
	root.add_child(v)
	await physics_frame
	await physics_frame
	# HUX の _meadow と同じ：EnvironmentP9・R4・R4b を不可視
	var hid := []
	for nm in ["Props/EnvironmentP9", HU.NODE_NAME]:
		var o := v.get_node_or_null(nm) as Node3D
		if o and o.visible:
			o.visible = false
			hid.append(o)
	var Pm: Dictionary = MD.base_plan(v)
	var MC := MD.context(Pm, v)
	var Fm := MD.fields(Pm, MC)
	var Mm := MD.plan(Pm, MC, Fm)
	var mp: PackedVector2Array = Mm["p"]
	for o in hid:
		o.visible = true
	print("[REPLAY] hide_branches=%s MeadowP9 規劃株 %d（封存 114105）" % [hide, mp.size()])
	var P := HX.plan(v, mp)
	var snap: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/village_v2_p10r4b_snapshot.json"))
	var by := {}
	for w: Dictionary in snap["items"]:
		by[String(w["name"])] = w
	var nbad := 0
	for i in (P["items"] as Array).size():
		var it: Dictionary = P["items"][i]
		var nm := "%03d_%s" % [i, it["id"]]
		var w: Dictionary = by.get(nm, {})
		if w.is_empty():
			nbad += 1
			continue
		var q: Array = w["position"]
		var p2: Vector2 = it["p"]
		var d := Vector3(p2.x, float(it["y"]), p2.y).distance_to(Vector3(q[0], q[1], q[2]))
		if d > 0.01:
			nbad += 1
			print("[REPLAY]   HUX %s 計画 (%.2f,%.3f,%.2f) snapshot %s 差 %.3f" % [nm, p2.x, it["y"], p2.y, str(q), d])
	print("[REPLAY] HUX snapshot 不符 %d" % nbad)
	var Pw: Dictionary = WS.plan(v, L)
	var H: Dictionary = Pw["H"]
	var nblk := 0
	for it: Dictionary in Pw["items"]:
		var pts := WS.prop_corners(it) if String(it["kind"]) == "mesh" else PackedVector2Array([it["p"]])
		var rr := 0.4 if String(it["kind"]) == "plant" else 0.0
		for q in pts:
			if WS._blocked(q, rr, Pw["R"], {"boxes": [], "walkways": H["walkways"], "entries": H["entries"], "dragon_walkway": H["dragon_walkway"]}, []):
				nblk += 1
				print("[REPLAY]   WATER 通路 %s@%s" % [it["id"], it["p"]])
				break
	print("[REPLAY] WATER 計画 %d 件・通路障害 %d" % [(Pw["items"] as Array).size(), nblk])
	quit(0)
