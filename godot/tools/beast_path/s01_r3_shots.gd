extends "res://tools/beast_path/s01_r2_shots.gd"
## S01 R3 Stage 1 審圖鏡位：沿用 R2 全部鏡位（同一支相機邏輯、同一時刻），再加谷腳岩組（f02）與一張寬構圖。
## Before＝R2 場景（R3 開工前，未重生成）、After＝R3 生成後；同一支腳本、同一組鏡位。
##   godot --path godot --script res://tools/beast_path/s01_r3_shots.gd -- --map=beast_path --out=<dir> --hour=10 [--only=a,b]
## 新增：
##   g_rock_tps   TPS：玩家站在主路上離 f02（東側谷腳的大岩盤，約 (55, −4)）最近的地方，朝岩看
##   g_rock_near  自由鏡位：谷底 1.7 m 高、離岩約 16 m 的斜角
##   g_wide       自由鏡位：鳥居前上方 9 m 往林內看的寬構圖（地表與林的整合）
##   g_wide_back  自由鏡位：林內上方 8 m 回望村緣（村緣開闊 → 林內林床的過渡）

const F02 := Vector2(55.0, -3.8)


func _views() -> Array:
	var v: Array = super._views()
	var sr := _nearest_s(F02)
	var c: Vector2 = lib.main.pos_at(sr)
	var d := F02 - c
	var rv := {"name": "g_rock_tps", "at": [c.x, c.y], "face": rad_to_deg(atan2(d.x, -d.y)), "pitch": -0.10}
	v.append(rv)
	var dd := d.normalized()
	var side := Vector2(-dd.y, dd.x)
	var cam := F02 - dd * 15.0 + side * 6.0
	v.append(_free("g_rock_near", cam, F02, 1.7, 1.6))
	v.append(_free("g_wide", _at(0.30, -4.0), _at(0.62, 4.0), 9.0, 0.5))
	v.append(_free("g_wide_back", _at(0.74, 3.0), _at(0.36, -3.0), 8.0, 0.5))
	return v
