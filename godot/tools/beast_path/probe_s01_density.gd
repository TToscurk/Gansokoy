extends SceneTree
## S01 森林密度／分布探針（唯讀、離線、秒級）：
##   把 V1.3 的 S01 條目（凍結檔，歷史基準）與現行 R1 的 S01 條目（maps/beast_path/gen/forest_plan.json）
##   各自換算成『沿主路的進度 u、離主路距離 d、離谷緣距離 sdf、樹高』，並輸出主路中心線與谷緣 SDF 網格，
##   供 evidence/scripts/s01_density.py 畫分布圖與算分段表。
##   godot --headless --path godot --script res://tools/beast_path/probe_s01_density.gd -- --out=<json>
const BP := preload("res://tools/beast_path/bp_lib.gd")
const ForestPlanner := preload("res://tools/beast_path/forest_planner.gd")


func _rows(lib: BP, fp: ForestPlanner, entries: Array, s0: float, L: float) -> Array:
	var rows: Array = []
	for e: Dictionary in entries:
		var p := Vector2(float(e["x"]), float(e["z"]))
		var q: Dictionary = lib.main.q(p)
		var kind := String(e["kind"])
		var id := String(e["id"])
		var h := 0.0
		if kind == "tree" or kind == "pin" or kind == "landmark":
			h = float(e.get("s", 1.0)) * fp._kit_h(id)
		rows.append({
			"k": kind, "id": id, "x": float(e["x"]), "z": float(e["z"]), "s": float(e.get("s", 1.0)), "h": snappedf(h, 0.01),
			"u": snappedf((float(q["s"]) - s0) / L, 0.0001), "d": snappedf(float(q["d"]), 0.01), "off": snappedf(float(q["off"]), 0.01),
			"sdf": snappedf(lib.mask_sdf(p), 0.01),
		})
	return rows


func _initialize() -> void:
	var out := "user://s01_density.json"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var lib := BP.new()
	lib.setup(true, true)
	var fp := ForestPlanner.new()
	fp.setup(lib, [])
	var s0 := lib.st_s("village")
	var s1 := lib.st_s("s01_s02")
	var L := s1 - s0
	var src: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/beast_path/frozen/forest_plan_v01_s01_s03.json"))
	var v13: Array = _rows(lib, fp, (src as Dictionary)["scenes"]["S01"], s0, L)
	var live: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://maps/beast_path/gen/forest_plan.json"))
	var r1e: Array = []
	for e: Dictionary in (live as Dictionary)["trees"]:
		if String(e["scene"]) == "S01":
			r1e.append(e)
	var r1: Array = _rows(lib, fp, r1e, s0, L)
	# 主路中心線（每 1 m，從村口前 30 m 到 S01/S02 接縫後 20 m）
	var path: Array = []
	var s := s0 - 30.0
	while s <= s1 + 20.0:
		var c: Vector2 = lib.main.pos_at(s)
		path.append([snappedf(c.x, 0.01), snappedf(c.y, 0.01), snappedf(lib.main.w_at(s), 0.01), snappedf(s, 0.01)])
		s += 1.0
	# 谷緣 SDF 網格（S01 tile 範圍，2 m）
	var tile := Rect2()
	for r: Dictionary in lib.rects:
		if String(r["id"]) == "S01":
			tile = r["tile"]
	var step := 2.0
	var nx := int(ceil(tile.size.x / step))
	var nz := int(ceil(tile.size.y / step))
	var sdf: Array = []
	for iz in nz:
		for ix in nx:
			var pp := Vector2(tile.position.x + (ix + 0.5) * step, tile.position.y + (iz + 0.5) * step)
			sdf.append(snappedf(lib.mask_sdf(pp), 0.1))
	var o := {
		"meta": {"s0": s0, "s1": s1, "L": L, "tile": [tile.position.x, tile.position.y, tile.size.x, tile.size.y], "grid": {"x0": tile.position.x, "z0": tile.position.y, "step": step, "nx": nx, "nz": nz}},
		"v13": v13, "r1": r1, "path": path, "sdf": sdf,
	}
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(o))
	f.close()
	print("[density] v13=%d r1=%d path=%d sdf=%dx%d  s0=%.1f s1=%.1f L=%.1f tile=%s" % [v13.size(), r1.size(), path.size(), nx, nz, s0, s1, L, str(tile)])
	quit(0)
