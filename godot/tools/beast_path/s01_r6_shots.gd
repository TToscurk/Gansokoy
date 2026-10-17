extends "res://tools/beast_path/s01_demo_shots.gd"
## S01 R6 審圖鏡位（鳥居、石燈籠、農田、入口構圖）：沿用 R3／R4 Demo／R5 全部鏡位，再加下列（位置全部由 layout 的站點算，不寫死）。
##   godot --path godot --script res://tools/beast_path/s01_r6_shots.gd -- --map=beast_path --out=<dir> --hour=10 [--only=a,b]
##   h_torii_tps   TPS：主路上鳥居前 12 m，往前（穿過鳥居）
##   h_torii_34    自由鏡位：鳥居右前側（燈籠之後）1.6 m 高、斜 3/4 看整座鳥居（柱腳、貫、島木、笠木）
##   h_lantern     自由鏡位：右側石燈籠斜前方 1.4 m 高（火袋、笠、寶珠、苔）
##   h_farm_tps    TPS：主路上離農田最近處，朝田看
##   h_farm        自由鏡位：田的西北角 1.7 m 高，斜看整片田（畝、溝、作物）
##   h_entrance    自由鏡位：鳥居前方上空 9 m 的入口構圖（主路、燈籠、柵欄、鳥居、小祠、林）


func _views() -> Array:
	var v: Array = super._views()
	var rt: Dictionary = lib.resolve({"st": "torii", "ds": 0.0})
	var T: Vector2 = rt["p"]
	var t: Vector2 = (rt["tan"] as Vector2).normalized()
	var r := Vector2(-t.y, t.x)
	var st := lib.st_s("torii")
	v.append(_road_view("h_torii_tps", st - 12.0, false))
	v.append(_free("h_torii_34", T - t * 4.5 + r * 7.0, T, 1.6, 2.9))
	var L: Vector2 = (lib.resolve({"st": "torii", "ds": -6.5, "off": 3.4}) as Dictionary)["p"]
	v.append(_free("h_lantern", L - t * 2.6 - r * 1.6, L + t * 0.2, 1.45, 1.05))
	var rf: Dictionary = lib.resolve({"st": "farm_edge", "ds": 2.0, "off": 24.0})
	var F: Vector2 = rf["p"]
	var tf: Vector2 = (rf["tan"] as Vector2).normalized()
	var r_f := Vector2(-tf.y, tf.x)
	var sf := _nearest_s(F)
	var cf: Vector2 = lib.main.pos_at(sf)
	var df := F - cf
	v.append({"name": "h_farm_tps", "at": [cf.x, cf.y], "face": rad_to_deg(atan2(df.x, -df.y)), "pitch": -0.10})
	v.append(_free("h_farm", F - r_f * 13.5 - tf * 10.5, F + r_f * 2.0, 1.7, 0.2))
	v.append(_free("h_entrance", T - t * 22.0 + r * 7.0, T + t * 3.0, 9.0, 2.0))
	return v
