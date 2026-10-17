extends SceneTree
## S01 R2 審圖探針（唯讀，不寫產物）：同一份規劃輸入，分別用 mode＝r1 與 mode＝r2（記憶體內切換）規劃，
## 輸出群落中心、植被條目、谷壁點綴、主路中心線、空地／谷壁外遮罩、地標位置 → 給 evidence/scripts/r2_maps.py 畫分布圖。
##   godot --headless --path godot --script res://tools/beast_path/probe_s01_r2_map.gd -- --out=<json>
const BP := preload("res://tools/beast_path/bp_lib.gd")
const FP := preload("res://tools/beast_path/forest_planner.gd")


func _initialize() -> void:
	var out := "user://s01_r2_map.json"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var lib := BP.new()
	lib.setup(true, true)
	var inp: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://maps/beast_path/gen/s01_forest_inputs.json"))
	var feet: Array = []
	for e: Dictionary in (inp as Dictionary)["footprints"]:
		feet.append({"id": String(e["id"]), "p": Vector2(float(e["p"][0]), float(e["p"][1])), "r": float(e["r"])})
	var cand: Dictionary = lib.L["forest"]["s01_candidate"]
	var mode0 := String(cand["mode"])
	var res := {"modes": {}}
	for mode: String in ["r1", "r2"]:
		cand["mode"] = mode
		var fp := FP.new()
		fp.setup(lib, feet)
		fp.plan()
		var trees: Array = []
		for t: Dictionary in fp.trees:
			if String(t["scene"]) != "S01":
				continue
			var kd: Dictionary = fp.kit[String(t["id"])]
			trees.append({"id": String(t["id"]), "kind": String(t["kind"]), "pin": String(t["pin"]), "x": float(t["x"]), "z": float(t["z"]),
				"h": float(kd["h"]) * float(t["s"]), "r": float(t.get("r", float(kd["r"]) * float(t["s"])))})
		var groves: Array = []
		for g: Dictionary in fp.get_meta("s01_groves", []):
			var c: Vector2 = g["c"]
			groves.append({"x": c.x, "z": c.y, "R": float(g["R"]), "n": int(g["n"]), "placed": int(g.get("placed", 0)), "u": float(g["u"]),
				"side": int(g["side"]), "drop": bool(g.get("drop", false)), "added": bool(g.get("added", false))})
		var wall := {"rocks": [], "pockets": [], "roots": []}
		if not fp.s01_wall.is_empty():
			for r: Dictionary in fp.s01_wall["rocks"]:
				wall["rocks"].append({"id": String(r["id"]), "kind": String(r["kind"]), "x": float(r["x"]), "z": float(r["z"]), "w": float(r["w"])})
			for pk: Dictionary in fp.s01_wall["pockets"]:
				wall["pockets"].append({"x": float(pk["x"]), "z": float(pk["z"]), "R": float(pk["R"]), "trees": int(pk.get("trees", 0)), "under": int(pk.get("under", 0))})
			for rt: Dictionary in fp.s01_wall.get("roots", []):
				wall["roots"].append({"x": float(rt["x"]), "z": float(rt["z"])})
		res["modes"][mode] = {"trees": trees, "groves": groves, "wall": wall, "info": fp.s01_info}
	cand["mode"] = mode0
	var s0 := lib.st_s("village")
	var s1 := lib.st_s("s01_s02")
	var path: Array = []
	var s := s0
	while s <= s1 + 0.01:
		var p: Vector2 = lib.main.pos_at(s)
		path.append([p.x, p.y, (s - s0) / (s1 - s0), float(lib.main.w_at(s))])
		s += 1.0
	var fp2 := FP.new()
	fp2.setup(lib, feet)
	var mask: Array = []
	var z := -100.0
	while z <= 30.0:
		var x := -110.0
		while x <= 110.0:
			var q := Vector2(x, z)
			mask.append([x, z, 1 if lib.mask_sdf(q) > 0.0 else 0, 1 if fp2._clear_dist(q) < 0.0 else 0])
			x += 2.0
		z += 2.0
	var lm := {}
	for nm: String in ["village", "farm_edge", "meadow", "cherry", "torii", "s01_s02"]:
		var p2: Vector2 = lib.main.pos_at(lib.st_s(nm))
		lm[nm] = [p2.x, p2.y, (lib.st_s(nm) - s0) / (s1 - s0)]
	for poi: Dictionary in lib.L["pois"]:
		if String(poi["id"]) == "shrine_hut_entrance":
			var pp: Vector2 = lib.resolve(poi["at"])["p"]
			lm["shrine_hut"] = [pp.x, pp.y, -1.0]
	res["path"] = path
	res["mask"] = mask
	res["landmarks"] = lm
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(res))
	f.close()
	print("[r2map] → %s  r1 trees=%d groves=%d ／ r2 trees=%d groves=%d rocks=%d pockets=%d" % [out, (res["modes"]["r1"]["trees"] as Array).size(), (res["modes"]["r1"]["groves"] as Array).size(),
		(res["modes"]["r2"]["trees"] as Array).size(), (res["modes"]["r2"]["groves"] as Array).size(), (res["modes"]["r2"]["wall"]["rocks"] as Array).size(), (res["modes"]["r2"]["wall"]["pockets"] as Array).size()])
	quit(0)
