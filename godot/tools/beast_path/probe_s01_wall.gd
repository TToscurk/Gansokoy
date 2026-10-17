extends SceneTree
## S01 R2 谷壁探針（唯讀、離線）：輸出 S01 tile 的 1 m 格網——高度、坡度、谷緣 SDF、離主路距離、沿主路進度 u，
## 以及現行 forest_plan.json 的 S01 樹位置，供 evidence/scripts 畫谷壁分布圖、決定『土袋／岩塊』該放哪裡。
##   godot --headless --path godot --script res://tools/beast_path/probe_s01_wall.gd -- --out=<json>
const BP := preload("res://tools/beast_path/bp_lib.gd")


func _initialize() -> void:
	var out := "user://s01_wall_probe.json"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var lib := BP.new()
	lib.setup(true, true)
	var s0 := lib.st_s("village")
	var L := lib.st_s("s01_s02") - s0
	var cells: Array = []
	var z := 30.0
	while z >= -104.0:
		var x := -110.0
		while x <= 110.0:
			var p := Vector2(x, z)
			var q: Dictionary = lib.main.q(p)
			cells.append([x, z, snappedf(lib.h_at(x, z), 0.01), snappedf(lib.slope_deg_at(x, z), 0.1), snappedf(lib.mask_sdf(p), 0.01),
				snappedf(float(q["d"]), 0.01), snappedf((float(q["s"]) - s0) / L, 0.001)])
			x += 1.0
		z -= 1.0
	var path: Array = []
	var s := s0 - 30.0
	while s <= s0 + L + 20.0:
		var c: Vector2 = lib.main.pos_at(clampf(s, 0.0, lib.main.length))
		path.append([snappedf(c.x, 0.01), snappedf(c.y, 0.01), snappedf((s - s0) / L, 0.001), snappedf(lib.main.w_at(clampf(s, 0.0, lib.main.length)), 0.01)])
		s += 1.0
	var live: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://maps/beast_path/gen/forest_plan.json"))
	var trees: Array = []
	for e: Dictionary in (live as Dictionary)["trees"]:
		if float(e["z"]) > -125.0:
			trees.append([String(e["id"]), String(e["kind"]), float(e["x"]), float(e["z"]), float(e["y"]), float(e["s"]), String(e["scene"]), String(e["pin"])])
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify({"cells": cells, "path": path, "trees": trees, "s0": s0, "L": L}))
	f.close()
	print("[probe] cells %d path %d trees %d → %s" % [cells.size(), path.size(), trees.size(), out])
	quit(0)
