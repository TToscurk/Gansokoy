extends SceneTree
## P13 W7 診断（唯読・headless）：Kit／Hero の各 LOD の visibility_range（begin／end／margin／fade_mode）を集計する。
##   godot --headless --path . --script res://tools/p13/w7/w7_probe_lodranges.gd
## 歴史依存の LOD 切替（fade_mode=DISABLED のとき margin は hysteresis になる）が起きうるかを実測で確かめる。
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _fmt(g: GeometryInstance3D) -> String:
	return "[%.0f,%.0f] margin(b=%.1f,e=%.1f) fade=%d" % [g.visibility_range_begin, g.visibility_range_end, g.visibility_range_begin_margin, g.visibility_range_end_margin, g.visibility_range_fade_mode]


func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 6:
		await process_frame
	var gate := v.get_node("Landmarks/LANDMARK_SOUTH_GATE/Hero")
	for l in ["LOD0", "LOD1", "LOD2"]:
		print("[W7R] gate ", l, " ", _fmt(gate.get_node(l) as GeometryInstance3D))
	var b := v.get_node("Districts/SouthGate/Buildings/B_P_SGT_002/Kit")
	var seen := {}
	for lod in ["LOD0", "LOD1", "LOD2"]:
		var ln := b.get_node_or_null(lod)
		if ln == null:
			continue
		for mi in ln.find_children("*", "GeometryInstance3D", true, false):
			var k: String = lod + " " + _fmt(mi as GeometryInstance3D)
			seen[k] = int(seen.get(k, 0)) + 1
	for k: String in seen:
		print("[W7R] SGT_002 Kit ", k, " ×", seen[k])
	# 全 Landmarks／Kit の margin と fade の統計
	var stat := {}
	for mi in v.find_children("*", "GeometryInstance3D", true, false):
		var g := mi as GeometryInstance3D
		if g.visibility_range_end <= 0.0 and g.visibility_range_begin <= 0.0:
			continue
		var key: String = "fade=%d  margin_b>0:%s  margin_e>0:%s" % [g.visibility_range_fade_mode, g.visibility_range_begin_margin > 0.0, g.visibility_range_end_margin > 0.0]
		stat[key] = int(stat.get(key, 0)) + 1
	for k: String in stat:
		print("[W7R] 全村の visibility_range 持ち：", k, " → ", stat[k], " 個")
	quit(0)
