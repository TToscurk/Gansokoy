extends SceneTree
## 岩壁節奏量測（唯讀）：godot --headless --path godot --script res://tools/beast_path/probe_rock_rhythm.gd [-- --out=<json>]
## 用法：量 V1.2 現況；要量 V1.1 就把 V1.1 的 maps／materials 換進來（見 evidence/scripts/ab_perf.sh 的做法）再跑同一支。
const BP := preload("res://tools/beast_path/bp_lib.gd")
const Rhythm := preload("res://tools/beast_path/rhythm_lib.gd")

func _initialize() -> void:
	_go.call_deferred()

func _go() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var lib := BP.new()
	lib.setup(true, true)
	var inst := (ResourceLoader.load("res://maps/beast_path/beast_path.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	root.add_child(inst)
	for i in 4:
		await physics_frame
	var m: Dictionary = Rhythm.measure(root.world_3d.direct_space_state, lib)
	var c: Dictionary = m["center"]
	print("[RHYTHM] 中央視野：岩壁岩（≥ %.0f m）佔 %.0f%%（≥ %.0f m 的高岩佔 %.0f%%）、最長連續岩壁弧 %.0f°、缺口 %d 個 %s" % [Rhythm.WALL_M, float(c["rock_frac"]) * 100.0, Rhythm.TALL_M, float(c["tall_frac"]) * 100.0, float(c["max_arc_deg"]), int(c["gaps"]), str(c["gap_arcs"])])
	print("[RHYTHM] 9 個站點平均：岩壁岩 %.0f%%、高岩 %.0f%%；最長連續岩壁弧（最差站點）%.0f°" % [float(m["rock_frac_mean"]) * 100.0, float(m["tall_frac_mean"]) * 100.0, float(m["max_arc_worst"])])
	print("[RHYTHM] 中央一圈（每字 2°，R 岩壁岩 L 矮石 T 樹 G 地形 N 無 X 北崖不計）：", c["cls"])
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(m, "\t") + "\n")
		f.close()
	quit(0)
