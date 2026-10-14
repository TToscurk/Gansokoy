extends SceneTree
## P13 W9 診断（唯読・headless）：区域の町家の開間（bay_x／bay_kind／door_cx／door_w／style／roof 種別）と建物の局部座標を一覧する。
##   godot --headless --path . --script res://tools/p13/w9/w9_probe_bays.gd -- B_P_RSW_045 B_P_RSW_046 …（名前の前方一致 RSW_ も可）
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 4:
		await process_frame
	var pats := OS.get_cmdline_user_args()
	for b in v.get_node("Districts").find_children("B_*", "", true, false):
		var n3 := b as Node3D
		if n3 == null or not n3.has_meta("width_m"):
			continue
		var hit := false
		for p: String in pats:
			if String(n3.name).begins_with(p) or String(n3.name).contains(p):
				hit = true
		if not hit:
			continue
		var kit := n3.get_node_or_null("Kit")
		var m := {}
		if kit:
			for k in ["door_cx", "door_w", "door_rec", "bays", "bay_scale", "bay_x", "bay_kind", "style", "roof_cls", "roof_h", "roof_ove", "r3"]:
				m[k] = kit.get_meta(k, null)
		print("[PB] %s y=%.2f type=%s w=%.2f d=%.2f eave=%s ridge=%s base_h=%s setback=%s" % [n3.name, n3.global_position.y, n3.get_meta("type", ""), float(n3.get_meta("width_m")), float(n3.get_meta("depth_m")), str(n3.get_meta("eave_m", "")), str(n3.get_meta("ridge_m", "")), str(n3.get_meta("base_h", "")), str(n3.get_meta("setback_m", ""))])
		print("[PB]    ", JSON.stringify(m))
	quit(0)
