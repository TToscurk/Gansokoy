extends "res://tools/beast_path/s01_r6_shots.gd"
## 獸道全區審圖鏡位（S02／S03 美術重製＋全線整合）：沿用 S01 R2–R6 全部鏡位，再加 S02／S03／接縫／S04 銜接（位置全由 layout 站點與支線點算）。
##   godot --path godot --script res://tools/beast_path/bp_zone_shots.gd -- --map=beast_path --out=<dir> --hour=10 [--only=a,b]
## z2_* ＝ S02（森林深處）、z3_* ＝ S03（森林岔路）、zs_* ＝ 接縫、z4_* ＝ S04 銜接（只看、不改）。
## *_fwd／*_back＝TPS（玩家站主路中心、朝前／朝後）；*_in＝自由鏡位（林內 1.6 m 眼高，看主路或林床）；*_wide＝自由鏡位高處。


func _views() -> Array:
	var v: Array = super._views()
	# ---- S02
	v.append(_road_view("z2_gate_fwd", lib.st_s("forest_gate") - 6.0, false))
	v.append(_road_view("z2_corridor_fwd", lib.st_s("corridor") - 4.0, false))
	v.append(_road_view("z2_lung_fwd", lib.st_s("lung") - 6.0, false))
	v.append(_road_view("z2_descent_fwd", lib.st_s("descent") - 2.0, false))
	v.append(_road_view("z2_bridge_fwd", lib.st_s("bridge_s") - 7.0, false))
	v.append(_road_view("z2_lung_back", lib.st_s("lung") + 4.0, true))
	v.append(_side_in("z2_corridor_in", lib.st_s("corridor") + 3.0, -13.0, 9.0))
	v.append(_side_in("z2_lung_in", lib.st_s("lung") + 2.0, 12.0, 8.0))
	v.append(_branch_view("z2_hollow", "hollow_loop", 0, 1))
	v.append(_free("z2_stream", _sp("bridge_s", 6.0, 14.0), _sp("bridge_s", 12.0, -6.0), 2.2, 0.5))
	v.append(_free("z2_wide", _sp("forest_gate", -16.0, -14.0), _sp("lung", 0.0, 0.0), 14.0, 2.0))
	# ---- S03
	v.append(_road_view("z3_rootstep_fwd", lib.st_s("rootstep") - 4.0, false))
	v.append(_road_view("z3_glade_fwd", lib.st_s("glade") - 6.0, false))
	v.append(_road_view("z3_fork_fwd", lib.st_s("fork") - 8.0, false))
	v.append(_road_view("z3_north_fwd", lib.st_s("north_a") + 2.0, false))
	v.append(_road_view("z3_glade_back", lib.st_s("glade") + 6.0, true))
	v.append(_side_in("z3_glade_in", lib.st_s("glade"), 14.0, 10.0))
	v.append(_side_in("z3_north_in", lib.st_s("north_b") - 4.0, -12.0, 8.0))
	v.append(_branch_view("z3_bamboo", "bamboo", 0, 1))
	v.append(_branch_view("z3_return", "return_lane", 0, 1))
	v.append(_free("z3_wide", _sp("rootstep", -6.0, 16.0), _sp("fork", 6.0, 0.0), 14.0, 2.0))
	# ---- 接縫與 S04 銜接
	v.append(_road_view("zs_12", lib.st_s("s01_s02") - 6.0, false))
	v.append(_road_view("zs_23", lib.st_s("bridge_n") + 6.0, false))
	v.append(_road_view("zs_34", lib.st_s("s03_s04") - 10.0, false))
	v.append(_road_view("z4_buffer_fwd", lib.st_s("buffer_s") - 2.0, false))
	v.append(_road_view("z4_arena_fwd", lib.st_s("arena_s") - 4.0, false))      # 總審：S04 代表圖（只看）
	# 最終整合：站在土留め階段上（S02 往橋的下坡、S03 往林窗的上坡）
	v.append(_road_view("z2_steps_on", lib.st_s("descent") + 7.0, false))
	v.append(_road_view("z3_steps_on", lib.st_s("rootstep") + 12.5, false))
	return v


## 主路站點 st、沿路 ds、側向 off（＋＝右）的世界 XZ
func _sp(st: String, ds: float, off: float) -> Vector2:
	var s := lib.st_s(st) + ds
	var tg: Vector2 = lib.main.tan_at(s)
	return lib.main.pos_at(s) + Vector2(-tg.y, tg.x) * off


## 林內自由鏡位：站在主路側 off（＋右）處 1.6 m 眼高，往前方 ahead m 的主路中心看
func _side_in(nm: String, s: float, off: float, ahead: float) -> Dictionary:
	var tg: Vector2 = lib.main.tan_at(s)
	var cam: Vector2 = lib.main.pos_at(s) + Vector2(-tg.y, tg.x) * off
	var look: Vector2 = lib.main.pos_at(s + ahead)
	return _free(nm, cam, look, 1.6, 0.9)


## 支線 TPS：站在支線第 i 點、朝第 j 點
func _branch_view(nm: String, bid: String, i: int, j: int) -> Dictionary:
	for b: Dictionary in lib.L["branches"]:
		if String(b["id"]) == bid:
			var p: Array = b["points"]
			var a := Vector2(float(p[i]["x"]), float(p[i]["z"]))
			var c := Vector2(float(p[j]["x"]), float(p[j]["z"]))
			var d := c - a
			return {"name": nm, "at": [a.x, a.y], "face": rad_to_deg(atan2(d.x, -d.y)), "pitch": -0.08}
	return {"name": nm, "at": [0.0, 0.0], "face": 0.0}
