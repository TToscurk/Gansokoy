extends SceneTree
## 審圖鏡位產生器：讀 layout＋晶格，輸出 main.gd 的 --shots 清單（JSON）。
##   godot --headless --path godot --script res://tools/beast_path/make_shots.gd -- --out=D:/.../shots.json [--set=walk|over|all] [--hour=11]
## 相機座標是絕對值；高度＝晶格地面＋偏移（和白模地形同一份高度）。
const BP := preload("res://tools/beast_path/bp_lib.gd")

var lib: BP
var hour := 11.0
var shots: Array = []


func _initialize() -> void:
	var out := "res://../docs/art_review/beast_path_v01/shots.json"
	var which := "all"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--set="):
			which = a.trim_prefix("--set=")
		elif a.begins_with("--hour="):
			hour = float(a.trim_prefix("--hour="))
	lib = BP.new()
	lib.setup(true, true)
	if which == "walk" or which == "all":
		_walk()
	if which == "over" or which == "all":
		_overview()
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(shots, "\t"))
	f.close()
	print("[shots] %d → %s" % [shots.size(), out])
	quit(0)


func _g(x: float, z: float) -> float:
	return lib.h_at(x, z)


## 第三人稱鏡位：站在 (st, ds) 的路上，相機在身後 back m、高 up m，看前方 ahead m 處
func tps(nm: String, st: String, ds: float, ahead := 9.0, back := 4.2, up := 2.5, look_up := 1.3, off := 0.0) -> void:
	var s := lib.st_s(st) + ds
	var t := lib.main.tan_at(s)
	var p := lib.main.pos_at(s) + BP.right_of(t) * off
	var c := p - t * back
	var l := p + t * ahead
	shots.append({"name": nm, "cam": [c.x, _g(c.x, c.y) + up, c.y], "look": [l.x, _g(l.x, l.y) + look_up, l.y], "time": hour, "hud": false})


func free_view(nm: String, c: Vector3, l: Vector3) -> void:
	shots.append({"name": nm, "cam": [c.x, c.y, c.z], "look": [l.x, l.y, l.z], "time": hour, "hud": false})


func at_ground(nm: String, p: Vector2, up: float, look: Vector2, look_up := 1.5) -> void:
	shots.append({"name": nm, "cam": [p.x, _g(p.x, p.y) + up, p.y], "look": [look.x, _g(look.x, look.y) + look_up, look.y], "time": hour, "hud": false})


func _walk() -> void:
	tps("w01_village_start", "village", 4.0)
	tps("w02_field_edge", "farm_edge", -14.0, 10.0)
	tps("w03_torii_approach", "torii", -13.0, 12.0)
	tps("w03b_torii_close", "torii", -7.0, 9.0, 3.5, 2.0, 1.8)
	tps("w04_torii_through", "torii", 4.0, 14.0)
	tps("w05_meadow_cherry", "meadow", 6.0, 16.0)
	tps("w06_forest_gate", "forest_gate", -10.0, 12.0)
	tps("w07_corridor", "corridor", -2.0, 14.0)
	tps("w08_lung_clearing", "lung", -6.0, 12.0)
	tps("w09_descent", "descent", -4.0, 14.0)
	tps("w10_bridge", "bridge_s", 3.0, 14.0)
	tps("w11_rootstep", "rootstep", -9.0, 12.0)
	tps("w12_glade", "glade", 0.0, 14.0)
	tps("w13_fork", "fork", -14.0, 14.0)
	tps("w14_north_a", "north_a", -6.0, 14.0)
	tps("w15_north_b", "north_b", -6.0, 14.0)
	tps("w16_threshold", "buffer_s", -4.0, 14.0)
	tps("w17_arena_reveal", "arena_s", -8.0, 16.0)
	# BOSS 場內
	var c0 := lib.arena_c()
	var A: Dictionary = lib.L["boss_arena"]
	var ps := lib.arena_pos(float(A["player_spawn"]["deg"]), float(A["player_spawn"]["r"]))
	var dir_n := (c0 - ps).normalized()
	at_ground("w18_arena_north", ps - dir_n * 3.5, 2.6, c0 + dir_n * 14.0, 2.0)
	var wf := Vector2(float(A["waterfall"]["x"]), float(A["waterfall"]["z"]))
	at_ground("w19_arena_waterfall", c0 + Vector2(0, 6), 2.4, wf, 12.0)
	at_ground("w18b_arena_wide_n", c0 + Vector2(4, 14), 3.2, wf, 10.0)
	at_ground("w29_arena_wall_west", lib.arena_pos(95.0, 8.0), 2.4, lib.arena_pos(280.0, 31.0), 5.0)
	at_ground("w30_arena_wall_east", lib.arena_pos(265.0, 8.0), 2.4, lib.arena_pos(105.0, 31.0), 5.0)
	at_ground("w31_arena_paving", c0 + Vector2(6, 9), 1.7, c0 + Vector2(-6, -5), 0.2)
	at_ground("w32_pool", Vector2(3.0, -417.0), 2.4, Vector2(-8.0, -435.0), 3.0)
	var lm := lib.arena_pos(float(A["landmark"]["deg"]), float(A["landmark"]["r"]))
	at_ground("w20_arena_landmark", c0 + Vector2(-8, 10), 2.4, lm, 9.0)
	var al := lib.arena_pos(float(A["altar"]["deg"]), float(A["altar"]["r"]))
	at_ground("w21_arena_altar", c0 + Vector2(8, 8), 2.4, al, 1.2)
	var tp := Vector2.ZERO
	for f: Dictionary in lib.L["terrain"]["features"]:
		if String(f["id"]) == "torii_broken_platform":
			tp = Vector2(float(f["c"][0]), float(f["c"][1]))
	at_ground("w22_arena_broken_torii", c0 + Vector2(-4, 6), 2.4, tp, 3.0)
	# 支線
	var br: BP.Poly = lib.branches["hollow_loop"]
	var bp0 := br.pos_at(br.length * 0.45)
	var bp1 := br.pos_at(br.length * 0.7)
	at_ground("w23_lair", bp0, 2.4, bp1, 1.0)
	var bb: BP.Poly = lib.branches["bamboo"]
	var b0 := bb.pos_at(bb.length * 0.25)
	var b1 := bb.pos_at(bb.length * 0.6)
	at_ground("w24_bamboo_branch", b0, 2.2, b1, 1.5)
	at_ground("w28_bamboo_steps", bb.pos_at(bb.length * 0.50), 2.2, bb.pos_at(bb.length * 0.72), 1.2)
	at_ground("w25_bamboo_end", bb.pos_at(bb.length * 0.85), 2.2, bb.pos_at(bb.length), 2.0)
	# 小溪
	var st: BP.Poly = lib.streams["stream_main"]
	var s0 := st.pos_at(st.length * 0.30)
	var s1 := st.pos_at(st.length * 0.45)
	at_ground("w26_stream_cascade", s0 + Vector2(0, 5), 2.4, s1, 0.5)
	var f0 := st.pos_at(st.length * 0.62)
	at_ground("w27_stream_ford", f0 + Vector2(-6, 6), 2.4, f0, 0.3)


func _overview() -> void:
	# 每個場景從東南高處斜看（上空 70 m）
	for sc: Dictionary in lib.L["scenes"]:
		var r: Array = sc["play_rect"]
		var cx := (float(r[0]) + float(r[2])) * 0.5
		var cz := (float(r[1]) + float(r[3])) * 0.5
		var gy := _g(cx, cz)
		var c := Vector3(cx + 40.0, gy + 72.0, cz + 76.0)
		var l := Vector3(cx - 4.0, gy + 2.0, cz - 8.0)
		free_view("o_%s" % String(sc["id"]).to_lower(), c, l)
	# 全線（沿路抬高 40 m 看 S02→S04）
	free_view("o_full_north", Vector3(60, 80, -170), Vector3(0, 8, -330))
	free_view("o_full_south", Vector3(-70, 70, -380), Vector3(10, 6, -230))
