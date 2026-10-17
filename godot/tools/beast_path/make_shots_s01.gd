extends SceneTree
## S01 入口林道（R1）審圖鏡位產生器：輸出 main.gd 的 --shots 清單（自由攝影機、絕對座標）。
##   godot --headless --path godot --script res://tools/beast_path/make_shots_s01.gd -- --out=<json> [--hour=10]
## 同一份 JSON 在 Before（V1.3 基準）與 After（S01 R1）各跑一次 → 鏡位、時刻、渲染設定完全相同。
## 高度＝晶格地面（lib.h_at）＋偏移；地形高度在 S01 R1 不改（s01_terrain_shape.res 雜湊不變，gate 檢查），所以兩邊的相機是同一個世界點。
## 沿主路「相對進度」p∈[0,1]：p＝0 在 village 站、p＝1 在 s01_s02 站（S01 主路約 117 m）。
const BP := preload("res://tools/beast_path/bp_lib.gd")

var lib: BP
var hour := 10.0
var shots: Array = []
var s0 := 0.0
var s1 := 0.0


func _initialize() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--hour="):
			hour = float(a.trim_prefix("--hour="))
	if out == "":
		push_error("需要 --out=<json>")
		quit(2)
		return
	lib = BP.new()
	lib.setup(true, true)
	s0 = lib.st_s("village")
	s1 = lib.st_s("s01_s02")
	# --- 沿路視角（人眼高；看前方 18 m 的路面）：p＝進度
	for e: Array in [["e03", 0.03], ["e12", 0.12], ["e22", 0.22], ["e31", 0.31], ["e42", 0.42], ["e52", 0.52], ["e62", 0.62], ["e72", 0.72], ["e82", 0.82], ["e92", 0.92]]:
		_eye(String(e[0]) + "_eye", float(e[1]), 18.0, 0.0)
	# --- 回望（朝南看來時路）
	_eye("b55_back", 0.55, -18.0, 0.0)
	_eye("b92_back", 0.92, -18.0, 0.0)
	# --- 特寫：路面、路緣、草地
	_ground("g35_road_close", 0.35, 0.4, 1.15, 5.5, 0.0)
	_ground("g60_edge_close", 0.60, 2.2, 1.2, 5.0, -0.5)
	_ground("g75_floor_close", 0.75, -2.0, 1.2, 5.0, 0.0)
	# --- 柵欄（V1.3 的 fence_village_L／R／R2、fence_torii_L／R、fence_field_edge、fence_end）
	_look("f_village_fence", Vector2(0.0, 0.0), 0.0, "village", 7.0, 1.0, 1.75, "village", 26.0, -3.7, 0.9)
	_look("f_village_fence_R", Vector2(0.0, 0.0), 0.0, "village", 9.0, -1.0, 1.75, "village", 24.0, 3.7, 0.9)
	_look("f_torii_fence", Vector2(0.0, 0.0), 0.0, "torii", -17.0, 0.5, 1.75, "torii", -4.0, -4.3, 1.0)
	_look("f_field_edge", Vector2(0.0, 0.0), 0.0, "farm_edge", -14.0, 2.5, 1.75, "farm_edge", 6.0, 14.8, 1.0)
	# --- 接縫（S01／S02 在 z＝−100 共用邊界列）
	_seam("x_seam_north", -86.0, -118.0, 2.3, 1.6)
	_seam("x_seam_south", -116.0, -84.0, 2.3, 1.6)
	_seam("x_seam_high", -84.0, -116.0, 14.0, 0.0)
	# --- 全覽（V0.1 的 o_s01 原樣，另加一張更高更正的）
	shots.append({"name": "o_s01", "cam": [40.0, 73.6, 34.0], "look": [-4.0, 3.6, -50.0], "time": hour, "hud": false})
	shots.append({"name": "o_s01_top", "cam": [3.0, 150.0, -22.0], "look": [-3.0, 0.0, -52.0], "time": hour, "hud": false})
	# --- V0.1 審圖的原始鏡位（w01–w06）：絕對座標原樣，供與 V0.1 圖對照
	var f := FileAccess.open("res://../docs/art_review/beast_path_v01/shots_f.json", FileAccess.READ)
	if f != null:
		var src: Variant = JSON.parse_string(f.get_as_text())
		if src is Array:
			for e: Dictionary in src:
				if String(e["name"]) in ["w01_village_start", "w02_field_edge", "w03_torii_approach", "w03b_torii_close", "w04_torii_through", "w05_meadow_cherry", "w06_forest_gate"]:
					var ee := (e as Dictionary).duplicate()
					ee["time"] = hour
					shots.append(ee)
	var w := FileAccess.open(out, FileAccess.WRITE)
	w.store_string(JSON.stringify(shots, "\t"))
	w.close()
	print("[shots_s01] %d → %s（s0=%.2f s1=%.2f 長 %.1f m）" % [shots.size(), out, s0, s1, s1 - s0])
	quit(0)


func _pp(p: float, off: float) -> Vector2:
	var s := s0 + p * (s1 - s0)
	var c := lib.main.pos_at(s)
	var t := lib.main.tan_at(s)
	return c + Vector2(-t.y, t.x) * off


## 人眼高度沿路：相機在 p 的路心，往 ahead（m，負＝朝南）處的路面看。
func _eye(nm: String, p: float, ahead: float, off: float) -> void:
	var s := s0 + p * (s1 - s0)
	var c := _pp(p, off)
	var t := lib.main.tan_at(s)
	var q := c + t * ahead
	shots.append({"name": nm, "cam": [c.x, lib.h_at(c.x, c.y) + 1.75, c.y], "look": [q.x, lib.h_at(q.x, q.y) + 1.0, q.y], "time": hour, "hud": false})


func _ground(nm: String, p: float, off: float, h: float, ahead: float, look_dy: float) -> void:
	var s := s0 + p * (s1 - s0)
	var c := _pp(p, off)
	var t := lib.main.tan_at(s)
	var q := c + t * ahead
	shots.append({"name": nm, "cam": [c.x, lib.h_at(c.x, c.y) + h, c.y], "look": [q.x, lib.h_at(q.x, q.y) + look_dy, q.y], "time": hour, "hud": false})


## 站在 (st, ds_a, off_a) 看 (st2, ds_b, off_b)
func _look(nm: String, _unused: Vector2, _u2: float, st_a: String, ds_a: float, off_a: float, up_a: float, st_b: String, ds_b: float, off_b: float, up_b: float) -> void:
	var sa := lib.st_s(st_a) + ds_a
	var sb := lib.st_s(st_b) + ds_b
	var ca := lib.main.pos_at(sa) + Vector2(-lib.main.tan_at(sa).y, lib.main.tan_at(sa).x) * off_a
	var cb := lib.main.pos_at(sb) + Vector2(-lib.main.tan_at(sb).y, lib.main.tan_at(sb).x) * off_b
	shots.append({"name": nm, "cam": [ca.x, lib.h_at(ca.x, ca.y) + up_a, ca.y], "look": [cb.x, lib.h_at(cb.x, cb.y) + up_b, cb.y], "time": hour, "hud": false})


## 接縫：沿主路 z 座標找路心 x（主路 z 單調遞減）
func _seam(nm: String, za: float, zb: float, up: float, look_up: float) -> void:
	var ca := _path_at_z(za)
	var cb := _path_at_z(zb)
	shots.append({"name": nm, "cam": [ca.x, lib.h_at(ca.x, ca.y) + up, ca.y], "look": [cb.x, lib.h_at(cb.x, cb.y) + look_up, cb.y], "time": hour, "hud": false})


func _path_at_z(z: float) -> Vector2:
	var best := lib.main.pos_at(0.0)
	var bd := 1e9
	var s := 0.0
	while s <= lib.main.length:
		var q := lib.main.pos_at(s)
		if absf(q.y - z) < bd:
			bd = absf(q.y - z)
			best = q
		s += 0.5
	return best
