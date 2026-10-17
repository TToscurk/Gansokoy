extends "res://tools/beast_path/tps_shots.gd"
## S01 玩家第三人稱（TPS）實景：玩家站在主路中心線上、朝路向前進方向，相機走遊戲真正的 CameraAdapter／SpringArm。
##   godot --path godot --script res://tools/beast_path/s01_tps_shots.gd -- --map=beast_path --out=<dir> --hour=10 --w=1600 --h=900
## 進度 u＝沿主路（村口→S01/S02 接縫）的相對位置。朝向由主路切線算出（不是寫死的角度）。
const U_FWD := [0.04, 0.18, 0.32, 0.46, 0.60, 0.74, 0.90]
const U_BACK := [0.30, 0.70]


func _views() -> Array:
	var v: Array = []
	var s0 := lib.st_s("village")
	var s1 := lib.st_s("s01_s02")
	for u: float in U_FWD:
		v.append(_road_view("p%02d_fwd" % int(round(u * 100.0)), s0 + u * (s1 - s0), false))
	for u2: float in U_BACK:
		v.append(_road_view("p%02d_back" % int(round(u2 * 100.0)), s0 + u2 * (s1 - s0), true))
	return v


func _road_view(nm: String, s: float, back: bool) -> Dictionary:
	var c: Vector2 = lib.main.pos_at(s)
	var c2: Vector2 = lib.main.pos_at(s + 2.0)
	var d: Vector2 = (c2 - c).normalized()
	var face := rad_to_deg(atan2(d.x, -d.y))        # face＝0 朝 −z（_put 的 yaw ＝ −face）
	if back:
		face += 180.0
	return {"name": nm, "at": [c.x, c.y], "face": face}
