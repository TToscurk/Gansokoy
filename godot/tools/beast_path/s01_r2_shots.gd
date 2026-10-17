extends "res://tools/beast_path/s01_tps_shots.gd"
## S01 R2 審圖鏡位（R1 審圖 §4–§9 要求的對照組）。鏡位全部由主路座標／固定世界座標算出，與規劃無關——
## 所以 R1 與 R2 用同一支腳本、同一組鏡位、同一時刻拍（Before＝mode r1 生成、After＝mode r2 生成）。
##   godot --path godot --script res://tools/beast_path/s01_r2_shots.gd -- --map=beast_path --out=<dir> --hour=10 [--only=a,b]
## 群組（名稱前綴）：w＝谷壁（§4）、t＝20/25/30/35 % 過渡（§6）、c＝群落玩家視高（§5）、k＝釘點櫻（§7）、s＝路肩樹影（§9）、h＝樹高天際線（§8）
## 櫻的鏡位以 R1（V0.1）的五棵釘點位置的中心為準（寫死），After 用同一鏡位。

const K_CENTER := Vector2(-4.24, -75.63)       # R1 五棵釘點櫻的平均位置


func _views() -> Array:
	var v: Array = []
	var s0 := lib.st_s("village")
	var s1 := lib.st_s("s01_s02")
	var L := s1 - s0
	# ---- §4 谷壁：R1 的問題鏡位（p30_back）原樣＋左右偏 35°＋兩個斜角自由鏡位＋一個高角
	var b30 := _road_view("w30_back", s0 + 0.30 * L, true)
	v.append(b30)
	var bl := b30.duplicate()
	bl["name"] = "w30_back_l"
	bl["face"] = float(b30["face"]) - 35.0
	v.append(bl)
	var br := b30.duplicate()
	br["name"] = "w30_back_r"
	br["face"] = float(b30["face"]) + 35.0
	v.append(br)
	v.append(_free("w_obl_left", _at(0.20, 5.0), _at(0.34, -24.0), 1.7, 3.5))
	v.append(_free("w_obl_right", _at(0.42, -5.0), _at(0.28, 24.0), 1.7, 3.5))
	v.append(_free("w_high", _at(0.10, 0.0), _at(0.40, 0.0), 14.0, 2.0))
	# ---- §6 過渡：20／25／30／35 % 朝前
	for u: float in [0.20, 0.25, 0.30, 0.35]:
		v.append(_road_view("t%02d_fwd" % int(round(u * 100.0)), s0 + u * L, false))
	# ---- §5 群落：37–68 % 區間的玩家視高（前＋後）
	for u2: float in [0.40, 0.50, 0.58, 0.66]:
		v.append(_road_view("c%02d_fwd" % int(round(u2 * 100.0)), s0 + u2 * L, false))
	for u3: float in [0.56, 0.70]:
		v.append(_road_view("c%02d_back" % int(round(u3 * 100.0)), s0 + u3 * L, true))
	# ---- §7 釘點櫻：主路上看（TPS）＋側上方自由鏡位
	var ks := _nearest_s(K_CENTER)
	v.append(_road_view("k_road_fwd", ks - 18.0, false))
	v.append(_road_view("k_road_back", ks + 16.0, true))
	v.append(_free("k_side", K_CENTER + Vector2(24.0, 8.0), K_CENTER, 6.0, 2.5))
	# ---- §9 路肩樹影：鳥居前（進鳥居前 12 m、鳥居下）與 90 %
	var st := lib.st_s("torii")
	v.append(_road_view("s_torii_m12", st - 12.0, false))
	v.append(_road_view("s_torii_0", st, false))
	v.append(_road_view("s90_fwd", s0 + 0.90 * L, false))
	v.append(_road_view("s86_fwd", s0 + 0.86 * L, false))
	# ---- §8 天際線：低俯角朝前（pitch 抬高）
	for u4: float in [0.15, 0.45, 0.75]:
		var hv := _road_view("h%02d_sky" % int(round(u4 * 100.0)), s0 + u4 * L, false)
		hv["pitch"] = 0.06
		v.append(hv)
	return v


## 主路上進度 u、側向 off（＋＝右）的世界 XZ
func _at(u: float, off: float) -> Vector2:
	var s0 := lib.st_s("village")
	var s := s0 + u * (lib.st_s("s01_s02") - s0)
	var tg: Vector2 = lib.main.tan_at(s)
	return lib.main.pos_at(s) + Vector2(-tg.y, tg.x) * off


func _free(nm: String, cam: Vector2, look: Vector2, cam_above: float, look_above: float) -> Dictionary:
	return {"name": nm, "free": {"cam": [cam.x, 0.0, cam.y], "look": [look.x, 0.0, look.y], "cam_above": cam_above, "look_above": look_above}}


func _nearest_s(p: Vector2) -> float:
	var s0 := lib.st_s("village")
	var s1 := lib.st_s("s01_s02")
	var best := s0
	var bd := 1e9
	var s := s0
	while s <= s1:
		var d: float = (lib.main.pos_at(s) as Vector2).distance_to(p)
		if d < bd:
			bd = d
			best = s
		s += 0.5
	return best
