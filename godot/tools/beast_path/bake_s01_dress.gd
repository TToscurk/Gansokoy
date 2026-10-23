extends SceneTree
## 獸道 S01 R4 Demo 環境資產烘焙——必須非 headless（MultiMesh Build Rule：headless 的 dummy RenderingServer 會把 instance transform 全存成 0）。
##   godot --path godot --script res://tools/beast_path/bake_s01_dress.gd
## 輸入：tools/beast_path/s01_dress.json、assets/beast_path/s01_kit/glb/*.glb（Blender：assets/beast_path/s01_kit/src/build_s01_kit.py）
## 輸出：maps/beast_path/gen/s01_dress.scn（generate_beast_path.gd 在 enabled 時掛進 S01）＋ s01_dress_report.json（擺放量測）
## 存檔後以 CACHE_MODE_IGNORE 回讀並稽核 instance 矩陣（tools/village_v2_mm_bake_guard.gd）。
const BP := preload("res://tools/beast_path/bp_lib.gd")
const ForestPlanner := preload("res://tools/beast_path/forest_planner.gd")
const S01Ground := preload("res://tools/beast_path/s01_ground.gd")
const S01Wall := preload("res://tools/beast_path/s01_wall.gd")
const Dress := preload("res://tools/beast_path/s01_dress.gd")
const Guard := preload("res://tools/village_v2_mm_bake_guard.gd")
const ZoneGround := preload("res://tools/beast_path/zone_ground.gd")
## 全區美術完成：--zone=S02｜S03 → 設定 tools/beast_path/<s0x>_dress.json、輸出 gen/<s0x>_dress.scn／_report.json（同一套擺放與烘焙；不帶 --zone＝S01，行為不變）
const INPUTS := "res://maps/beast_path/gen/s01_forest_inputs.json"
const OUT := "res://maps/beast_path/gen/s01_dress.scn"
const REPORT := "res://maps/beast_path/gen/s01_dress_report.json"


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	if not Guard.display_ok():
		push_error("[dress] 這個行程沒有 rendering display（headless？）——MultiMesh 會存成全 0。請去掉 --headless。")
		quit(3)
		return
	var t0 := Time.get_ticks_msec()
	var zone := ""
	for a0 in OS.get_cmdline_user_args():
		if a0.begins_with("--zone="):
			zone = a0.trim_prefix("--zone=").to_upper()
	var cfg_path := Dress.CFG if zone == "" else "res://tools/beast_path/%s_dress.json" % zone.to_lower()
	var out_path := OUT if zone == "" else "res://maps/beast_path/gen/%s_dress.scn" % zone.to_lower()
	var rep_path := REPORT if zone == "" else "res://maps/beast_path/gen/%s_dress_report.json" % zone.to_lower()
	var cfg: Dictionary = Dress.load_cfg() if zone == "" else (JSON.parse_string(FileAccess.get_file_as_string(cfg_path)) as Dictionary)
	var lib := BP.new()
	lib.setup(true, true)
	var jf: Variant = JSON.parse_string(FileAccess.get_file_as_string(INPUTS))
	var foot: Array = []
	for e: Dictionary in (jf as Dictionary)["footprints"]:
		foot.append({"id": String(e["id"]), "p": Vector2(float(e["p"][0]), float(e["p"][1])), "r": float(e["r"])})
	var pa = ForestPlanner.new()
	pa.setup(lib, foot)
	pa.plan()
	var ctx := S01Ground.build_ctx(lib, pa.trees, pa.kit, foot, pa.s01_wall)
	var wall: Dictionary = pa.s01_wall
	var rm: Dictionary
	var bb := Rect2(-112, -104, 224, 136)         # 2026-10-18 荒野化：S01 林床改沿整條路（band＋bbox）→ 範圍＝整個 S01 tile（原 R5：Rect2(-62, -112, 152, 142)）
	var drop: Array = []
	if zone != "":
		ctx = ZoneGround.build_ctx_zone(lib, pa.trees, pa.kit, foot, ctx, {})
		wall = {}
		var zc: Dictionary = (lib.L["forest"] as Dictionary).get("zone_candidate", {})
		if bool(zc.get("enabled", false)):
			drop = ((zc.get(zone, {}) as Dictionary).get("drop_kinds", []) as Array)
		if zone == "S02":
			rm = S01Wall.reach_map(lib, 50.0, -222, 124, "s01_s02", "rootstep")
			bb = Rect2(-112, -224, 224, 128)
		else:
			rm = S01Wall.reach_map(lib, 50.0, -342, 124, "bridge_n", "s03_s04")
			bb = Rect2(-112, -344, 224, 128)
	else:
		rm = S01Wall.reach_map(lib, 50.0)
	var F := Dress.Fields.new()
	F.lib = lib
	F.ctx = ctx
	F.g = ctx["s01"]
	# 只留範圍附近的腳印／樹／谷壁岩（逐點檢查用）；候選中不載入的 V0.1 林下 prefab 不算（林床改由這一層）
	var foot_r := foot.filter(func(f: Dictionary) -> bool: return bb.has_point(f["p"]) or float(f["r"]) > 6.0)
	var trees_r: Array = pa.trees.filter(func(t: Dictionary) -> bool: return bb.has_point(Vector2(float(t["x"]), float(t["z"]))) and not (drop.has(String(t["kind"])) and String(t["scene"]) == zone))
	var t1 := Time.get_ticks_msec()
	var P := Dress.plan(lib, cfg, F, trees_r, foot_r, wall, rm)
	var t2 := Time.get_ticks_msec()
	print("[dress] 規劃：岩／木 %d 件（略過 %s）；地被 %s（setup %.1f s、plan %.1f s）" % [(P["hard"] as Array).size(), str(P["skipped"]), str(P["counts"]), (t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
	var pts_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pts="):
			pts_path = arg.trim_prefix("--pts=")
	if pts_path != "":
		# 除錯用點位圖（不進 repo）：地被 [x, z, 類]、岩木 [x, z, id]、主路取樣
		var cats: Array = Dress.CATS
		var pts := {"cover": [], "hard": [], "road": []}
		for an: String in (P["cover"] as Dictionary):
			for it: Dictionary in P["cover"][an]:
				var o: Vector3 = (it["xf"] as Transform3D).origin
				(pts["cover"] as Array).append([snappedf(o.x, 0.01), snappedf(o.z, 0.01), cats.find(String(it["cat"]))])
		for h: Dictionary in P["hard"]:
			(pts["hard"] as Array).append([(h["p"] as Vector2).x, (h["p"] as Vector2).y, h["id"]])
		var s := lib.st_s("village")
		while s < lib.st_s("s01_s02"):
			var c: Vector2 = lib.main.pos_at(s)
			(pts["road"] as Array).append([snappedf(c.x, 0.01), snappedf(c.y, 0.01)])
			s += 1.0
		var pf := FileAccess.open(pts_path, FileAccess.WRITE)
		pf.store_string(JSON.stringify(pts))
		pf.close()
	var root: Node3D = Dress.build(lib, cfg, P)
	if zone == "":
		root.set_meta("art_revision", "S01 R5：R4 Demo 精修＋南段擴區（Blender 環境資產 assets/beast_path/s01_kit；tools/beast_path/s01_dress.gd＋s01_floor.gd 擺放）；ART_REVIEW")
	else:
		root.set_meta("art_revision", "%s 全區美術完成候選（Blender 環境資產 assets/beast_path/s01_kit；s01_dress.gd＋s01_floor.gd 同一套擺放、zone_ground 地表情境）；ART_REVIEW" % zone)
	root.set_meta("cfg_sha", FileAccess.get_sha256(cfg_path))
	var ps := PackedScene.new()
	var e := ps.pack(root)
	if e != OK:
		push_error("[dress] pack 失敗：%s" % error_string(e))
		quit(1)
		return
	e = ResourceSaver.save(ps, out_path)
	print("[dress] 存 %s：%s  岩／木 %d（碰撞 %d）、地被 %d 叢／%d 個 MultiMesh" % [out_path, error_string(e), int(root.get_meta("hard")), int(root.get_meta("collide")), int(root.get_meta("items")), int(root.get_meta("mm_nodes"))])
	# ---- 擺放量測報告（岩／木：AABB、埋深、凸出、底面空隙、離主路、碰撞）
	var rep := {"hard": [], "cover_counts": P["counts"], "skipped": P["skipped"], "tris": {}}
	for h: Dictionary in P["hard"]:
		var st: Dictionary = h["stats"]
		st["id"] = h["id"]
		st["asset"] = h["asset"]
		st["collide"] = h["collide"]
		st["pos"] = [snappedf((h["xf"] as Transform3D).origin.x, 0.01), snappedf((h["xf"] as Transform3D).origin.y, 0.01), snappedf((h["xf"] as Transform3D).origin.z, 0.01)]
		(rep["hard"] as Array).append(st)
	var tri_total := 0
	for an: String in (P["counts"] as Dictionary):
		var a := Dress.glb(an)
		var nt := (a["I"] as PackedInt32Array).size() / 3
		rep["tris"][an] = nt
		tri_total += nt * int(P["counts"][an])
	rep["cover_tris_total"] = tri_total
	# R5：有 LOD1 的種類，遠級的面數（近級只在 LOD1 換手距離內顯示）
	var tri_lod1 := 0
	for an3: String in (P["counts"] as Dictionary):
		if FileAccess.file_exists(Dress.GLB_DIR + an3 + "_lod1.glb"):
			var a3 := Dress.glb(an3 + "_lod1")
			tri_lod1 += (a3["I"] as PackedInt32Array).size() / 3 * int(P["counts"][an3])
	rep["cover_tris_lod1_total"] = tri_lod1
	rep["mm_nodes"] = int(root.get_meta("mm_nodes"))
	rep["mm_lod1_nodes"] = int(root.get_meta("mm_lod1_nodes", 0))
	# 地被離主路路緣的最近距離（各類）：主路淨空
	var pe_min := {}
	var n_on_road := 0
	for an2: String in (P["cover"] as Dictionary):
		for it: Dictionary in P["cover"][an2]:
			var o: Vector3 = (it["xf"] as Transform3D).origin
			var de := S01Wall.path_edge_d(lib, Vector2(o.x, o.z))
			var c := String(it["cat"])
			pe_min[c] = minf(float(pe_min.get(c, 1e9)), snappedf(de, 0.01))
			if de < 0.0:
				n_on_road += 1
	rep["cover_path_edge_min_m"] = pe_min
	rep["cover_on_road"] = n_on_road
	# 報告檔偶爾被外部程式暫時鎖住（FileAccess.open 回 null：第二次發生，2026-10-18）——重試；仍失敗就明確退出，不要卡在 SCRIPT ERROR 等逾時
	var f: FileAccess = null
	for _try in 20:
		f = FileAccess.open(rep_path, FileAccess.WRITE)
		if f != null:
			break
		OS.delay_msec(500)
	if f == null:
		push_error("[dress] 報告檔 %s 開不了（%s）——.scn 已存，報告未更新" % [rep_path, error_string(FileAccess.get_open_error())])
		root.free()
		quit(3)
		return
	f.store_string(JSON.stringify(rep, "  "))
	f.close()
	root.free()
	var r: Dictionary = Guard.audit_saved_scene(out_path)
	print("[dress] MMBAKE 回讀稽核：", Guard.summary(r))
	if not Guard.ok(r):
		push_error("[dress] 回讀發現退化的 instance——烘焙失敗")
		quit(1)
		return
	quit(0)
