extends SceneTree
## R4b 設計用の下調べ（唯讀）：住宅候補の順位と、矩形ごとの置ける／置けない地図。
## godot --headless --path godot --script res://tools/survey_village_v2_human_use_exp.gd -- --meadow-cache=<json> [--rank] [--survey=x,z,w,h;…]
const HX := preload("res://tools/village_v2_human_use_exp_lib.gd")
const HU := preload("res://tools/village_v2_human_use_lib.gd")
const MD := preload("res://tools/village_v2_meadow_lib.gd")


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var args := OS.get_cmdline_user_args()
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	var own := v.get_node_or_null(HX.NODE_NAME)
	if own:
		own.get_parent().remove_child(own)
		own.free()
	root.add_child(v)
	await physics_frame
	var cache := ""
	for s: String in args:
		if s.begins_with("--meadow-cache="):
			cache = s.trim_prefix("--meadow-cache=")
	var raw: Array = JSON.parse_string(FileAccess.get_file_as_string(cache))
	var mp := PackedVector2Array()
	for i in range(0, raw.size(), 2):
		mp.append(Vector2(raw[i], raw[i + 1]))
	var C := HX.context(v, mp)
	print("[HUX] INFO 文脈 R4 %d ms＋拡張 %d ms、地面 decal %d、R4 件 %d" % [C["ms"], C["exp_ms"], C["n_ground_decal"], C["n_r4"]])
	if "--rank" in args:
		var rk := HX.rank_backyards(C)
		for r: Dictionary in rk.slice(0, 60):
			print("[HUX] RANK %s back(%.1f,%.1f) free %.2f npc %.1f core %.0f w %.1f %s road=%s kinds=%s" % [r["name"], (r["back"] as Vector2).x, (r["back"] as Vector2).y,
				r["free"], r["npc_d"], r["core_d"], r["w"], r["type"], r["road"], str(r["kinds"])])
	for s: String in args:
		if s.begins_with("--survey="):
			for one in s.trim_prefix("--survey=").split(";"):
				var a := one.split(",")
				var r := Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
				print("[HUX] SURVEY %s（. 可 / R 路 B 建物 W 水 w P7 b 橋 H Hero A P8 S 封存 T 幹 E Env P P10 N NPC d 背戸 D 戸口 g 草 / 坂 c 商業 r R4 z R4区）" % str(r))
				for row in HX.survey(C, r, 1.0):
					print("[HUX] " + row)
	quit(0)
