extends SceneTree
## V1.3：S04 草叢凍結檔（frozen/meadow_plan_v12_s04.json）的來源工具——只在「V1.2 狀態」下跑才有意義：
##   swap_v12.sh 把 V1.2 備份換進專案 → 先跑 V1.2 的 generate_beast_path.gd（寫出 V1.2 的 user://beast_path_gctx.bin 與 gen/s04_meadow_inputs.json）
##   → 跑本檔，以 meadow_s04.plan() 原樣重算 V1.2 的草叢規劃並輸出 JSON（float 全精度）；結果 3196 叢＝V1.2 s04_meadow.scn 的掛載數。
##   流程與紀錄：docs/art_review/beast_path_v13_s04_final/evidence/scripts/{swap_v12.sh, inner_export_meadow.sh}、evidence/logs/v12_meadow_export.log
##   godot --headless --path godot --script res://tools/beast_path/freeze_meadow_s04_v12.gd -- --out=<json>
const BP := preload("res://tools/beast_path/bp_lib.gd")
const Meadow := preload("res://tools/beast_path/meadow_s04.gd")


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var lib := BP.new()
	lib.setup(true, true)
	var f := FileAccess.open("user://beast_path_gctx.bin", FileAccess.READ)
	var ctx := {}
	for key: String in ["canopy", "rock_d"]:
		var n := f.get_32()
		ctx[key] = f.get_buffer(n * 4).to_float32_array()
	f.close()
	var inp_path := "res://maps/beast_path/gen/s04_meadow_inputs.json"
	var inp: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(inp_path))
	var M: Dictionary = Meadow.plan(lib, ctx, inp["feet"], inp["stems"])
	var P: PackedVector2Array = M["p"]
	var K: PackedByteArray = M["k"]
	var Y: PackedFloat32Array = M["y"]
	var COL: PackedColorArray = M["col"]
	var S: PackedFloat32Array = M["s"]
	var W: PackedFloat32Array = M["w"]
	var YAW: PackedFloat32Array = M["yaw"]
	var d := {"n": int(M["n"]), "seed": Meadow.SEED, "inputs_sha256": FileAccess.get_sha256(inp_path), "stats": M["stats"],
		"p": [], "k": [], "y": [], "col": [], "s": [], "w": [], "yaw": []}
	for i in int(M["n"]):
		(d["p"] as Array).append([P[i].x, P[i].y])
		(d["k"] as Array).append(K[i])
		(d["y"] as Array).append(Y[i])
		(d["col"] as Array).append([COL[i].r, COL[i].g, COL[i].b, COL[i].a])
		(d["s"] as Array).append(S[i])
		(d["w"] as Array).append(W[i])
		(d["yaw"] as Array).append(YAW[i])
	var fo := FileAccess.open(out, FileAccess.WRITE)
	fo.store_string(JSON.stringify(d, "", false, true))
	fo.close()
	print("[EXPORT] meadow V1.2 規劃 %d 叢 → %s  stats=%s" % [int(M["n"]), out, str(M["stats"])])
	quit(0)
