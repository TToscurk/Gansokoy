extends SceneTree
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	for p in ["res://maps/village_v2/gen/drape_fix_p13.scn", "res://maps/village_v2/gen/road_edge_blend_p13.scn", "res://maps/village_v2/gen/sando_pilot_w4_p13.scn", "res://maps/village_v2/gen/edge_closure_p10.scn"]:
		var t0 := Time.get_ticks_usec()
		var ps := load(p) as PackedScene
		var t1 := Time.get_ticks_usec()
		var n := ps.instantiate()
		var t2 := Time.get_ticks_usec()
		print("[LOADT] ", p.get_file(), " load=", (t1 - t0) / 1000, " ms  instantiate=", (t2 - t1) / 1000, " ms")
		n.free()
	quit(0)
