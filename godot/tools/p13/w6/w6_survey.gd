extends "res://tools/p13/w6/w6_base.gd"
## P13 Wave 6 調査：P10 final の歩行路線に沿って step m ごとに「通常 TPS」を撮る（＋ID パス）。
##   godot --path . --script res://tools/p13/w6/w6_survey.gd -- <outdir/> <tag> [--step=25] [--id] [--only=seg1_gate_main,...] [--max=N]
## 出力：<tag>_NNN_<seg>.png（通常）／<tag>_NNN_id.png（--id）／<tag>_index.json（位置・相機）／<tag>_idtable.json
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	var tag := args[1]
	var step := 25.0
	var want_id := false
	var only := PackedStringArray()
	var mx := 100000
	for a: String in args:
		if a.begins_with("--step="):
			step = float(a.trim_prefix("--step="))
		elif a == "--id":
			want_id = true
		elif a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
		elif a.begins_with("--max="):
			mx = int(a.trim_prefix("--max="))
	DirAccess.make_dir_recursive_absolute(out)
	cl = SA.centerline()
	await _boot()
	var samples := route_samples(step, only)
	if samples.size() > mx:
		samples = samples.slice(0, mx)
	print("[W6S] samples ", samples.size(), " step ", step)
	var index: Array = []
	for i in samples.size():
		var s: Dictionary = samples[i]
		await _tpw(s["pos"], s["face"])
		var nm := "%s_%03d_%s" % [tag, i, String(s["seg"]).substr(0, 4) + String(s["seg"]).get_slice("_", 1)]
		await _shot(nm, 6)
		var rec := cam_record()
		rec["i"] = i
		rec["seg"] = s["seg"]
		rec["s"] = snappedf(float(s["s"]), 0.1)
		rec["name"] = nm
		rec["face"] = [snappedf(s["face"].x, 0.001), snappedf(s["face"].y, 0.001)]
		index.append(rec)
	if want_id:
		var n := id_begin()
		print("[W6S] ID パス：節点 ", n, " bits ", _id_bits)
		await _frames(6)
		for i in samples.size():
			var s: Dictionary = samples[i]
			await _tpw(s["pos"], s["face"])
			await _shot("%s_%03d_id" % [tag, i], 6)
		id_end()
		id_table_save(out + tag + "_idtable.json")
	var f := FileAccess.open(out + tag + "_index.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(index, "\t") + "\n")
	f.close()
	print("[W6S] DONE")
	quit(0)
