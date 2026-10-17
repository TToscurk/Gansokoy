extends SceneTree
## 獸道 S04 草叢層烘焙（V1.2 C）——必須非 headless（MultiMesh Build Rule：headless 的 dummy RenderingServer 會把 instance transform 全存成 0）。
##   godot --path godot --script res://tools/beast_path/bake_meadow_s04.gd
## 前提：先跑過 generate_beast_path.gd（它會寫 user://beast_path_gctx.bin 與 gen/s04_meadow_inputs.json）；烘焙後再生成一次，generator 才會把它掛進 S04。
## 輸出：maps/beast_path/gen/s04_meadow.scn（PackedScene，generate_beast_path.gd 會把它掛進 S04）；存檔後以 CACHE_MODE_IGNORE 回讀並稽核 instance 矩陣。
const BP := preload("res://tools/beast_path/bp_lib.gd")
const Meadow := preload("res://tools/beast_path/meadow_s04.gd")
const Guard := preload("res://tools/village_v2_mm_bake_guard.gd")
const OUT := "res://maps/beast_path/gen/s04_meadow.scn"


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	if not Guard.display_ok():
		push_error("[meadow] 這個行程沒有 rendering display（headless？）——MultiMesh 會存成全 0。請去掉 --headless。")
		quit(3)
		return
	var lib := BP.new()
	lib.setup(true, true)
	var f := FileAccess.open("user://beast_path_gctx.bin", FileAccess.READ)
	if f == null:
		push_error("[meadow] 沒有 user://beast_path_gctx.bin：先跑 generate_beast_path.gd")
		quit(2)
		return
	var ctx := {}
	for key: String in ["canopy", "rock_d"]:
		var n := f.get_32()
		ctx[key] = f.get_buffer(n * 4).to_float32_array()
	f.close()
	var inp_path := "res://maps/beast_path/gen/s04_meadow_inputs.json"
	var inp: Variant = JSON.parse_string(FileAccess.get_file_as_string(inp_path))
	if not (inp is Dictionary):
		push_error("[meadow] 讀不到 s04_meadow_inputs.json：先跑 generate_beast_path.gd")
		quit(2)
		return
	var t0 := Time.get_ticks_msec()
	var M: Dictionary
	var fz: Dictionary = (lib.L["forest"] as Dictionary).get("freeze_s04_meadow", {})
	var frozen := not fz.is_empty() and bool(fz.get("enabled", true))
	if frozen:
		# V1.3：V1.2 凍結（見 layout.forest.freeze_s04_meadow 與 meadow_s04.adopt_frozen）
		var fpath := String(fz["file"])
		if FileAccess.get_sha256(fpath) != String(fz["sha256"]):
			push_error("[meadow] 凍結檔 %s 的 sha256 與 layout 不符——拒絕烘焙" % fpath)
			quit(1)
			return
		var F: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fpath))
		M = Meadow.adopt_frozen(lib, ctx, (inp as Dictionary)["feet"], (inp as Dictionary)["stems"], F)
		var st: Dictionary = M["stats"]
		print("[meadow] S04 草叢＝V1.2 凍結：%d 叢 → 原樣 %d、剔除 %d %s、重新落地 %d、為維持中級 LOD 的 index 而搬位 %d（%.1f s）" % [
			int(st["frozen"]), int(st["kept"]) - int(st["reground_n"]), int(st["dropped_n"]), str(st["why"]), int(st["reground_n"]), int(st["moved_for_mid"]), (Time.get_ticks_msec() - t0) / 1000.0])
		print("[meadow]   剔除=%s" % str(st["dropped"]))
		print("[meadow]   落地=%s" % str((st["reground"] as Array).slice(0, 12)))
	else:
		M = Meadow.plan(lib, ctx, (inp as Dictionary)["feet"], (inp as Dictionary)["stems"])
		print("[meadow] 規劃 %d 叢（%.1f s）  %s" % [int(M["n"]), (Time.get_ticks_msec() - t0) / 1000.0, str(M["stats"])])
	var root: Node3D = Meadow.ML.bake(M)
	root.name = "MeadowS04"
	root.set_meta("art_revision", "V1.2 C：獸道 S04 草叢層（重用 P9 R5-3 叢 Kit；planner＝tools/beast_path/meadow_s04.gd）" + ("；V1.3：V1.2 凍結（adopt_frozen）" if frozen else ""))
	root.set_meta("inputs_sha", FileAccess.get_sha256(inp_path))
	root.set_meta("planned", int(M["n"]))
	if frozen:
		var st2: Dictionary = M["stats"]
		root.set_meta("frozen_sha", String(fz["sha256"]))
		root.set_meta("frozen_n", int(st2["frozen"]))
		root.set_meta("frozen_dropped", int(st2["dropped_n"]))
		root.set_meta("frozen_reground", int(st2["reground_n"]))
	# V1.2 G：S04 的草叢不投影（量測：草叢陰影 pass 約 0.25 ms／幀；草葉的影子在這個尺度幾乎看不到）。
	#   近級／中級的 MultiMesh 都關；其餘（叢 Kit、材質、距離淡出）維持 P9 R5-3 的設定。
	var n_shadow_off := 0
	for mmi in root.find_children("*", "MultiMeshInstance3D", true, false):
		(mmi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n_shadow_off += 1
	root.set_meta("shadow_off_nodes", n_shadow_off)
	Meadow.ML.own(root, root)
	var ps := PackedScene.new()
	var e := ps.pack(root)
	if e != OK:
		push_error("[meadow] pack 失敗：%s" % error_string(e))
		quit(1)
		return
	e = ResourceSaver.save(ps, OUT)
	print("[meadow] 存 %s：%s  近級 %d 塊／%d 叢、中級 %d 塊／%d 叢" % [OUT, error_string(e), int(root.get_meta("near_nodes")), int(root.get_meta("items")), int(root.get_meta("mid_nodes")), int(root.get_meta("mid_items"))])
	root.free()
	var r: Dictionary = Guard.audit_saved_scene(OUT)
	print("[meadow] MMBAKE 回讀稽核：", Guard.summary(r))
	if not Guard.ok(r):
		push_error("[meadow] 回讀發現退化的 instance——烘焙失敗")
		quit(1)
		return
	quit(0)
