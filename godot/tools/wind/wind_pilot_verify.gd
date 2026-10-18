extends SceneTree
## Wind V1.1 pilot 驗證（headless，物理固定 60 Hz）。
##
##   Godot_v4.7.2-stable_win64_console.exe --headless --path godot \
##     --script res://tools/wind/wind_pilot_verify.gd
##
## 驗的是「行為」不是外觀：
##   P1 類別 E（石燈籠）在整個測試中完全不動
##   P2 calm：落葉／籃子幾乎不動、燈籠幾乎不擺
##   P3 breeze：燈籠開始擺、落葉只輕微移動、籃子仍不動
##   P4 gust：落葉明顯位移、籃子慢慢滑動、燈籠大幅擺動（且延遲起擺）
##   P5 恢復：風停後燈籠衰減、落葉減速
##   P6 無瞬移：任何一步的位移 < 上限；燈籠吊點位置不變
##   P7 決定性：同一 seed、同一串 dt，重跑結果相同

const PILOT := "res://scenes/wind_pilot.tscn"
const DT := 1.0 / 60.0
const SHELTER_POS := Vector3(8.0, 1.2, 0.0)

var fails := 0
var v: Node
var wind: Node
var heavy_xf: Transform3D
var _lantern_pivots := {}
var _max_step := 0.0


func _init() -> void:
	_run.call_deferred()


func _ok(cond: bool, msg: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


func _run() -> void:
	wind = root.get_node_or_null("Wind")
	if wind == null:
		print("FAIL 找不到 Wind")
		quit(1)
		return
	v = (load(PILOT) as PackedScene).instantiate()
	root.add_child(v)
	await process_frame
	await process_frame
	wind.set_frozen(true)
	wind.debug_reset()
	wind.add_shelter(SHELTER_POS, 4.0, 0.30)
	_ok(v.objects("PILOT_lantern").size() == 3, "燈籠 3 個（實際 %d）" % v.objects("PILOT_lantern").size())
	_ok(v.objects("PILOT_leaf").size() == 14, "落葉 14 片（實際 %d）" % v.objects("PILOT_leaf").size())
	_ok(v.objects("PILOT_basket").size() == 1, "竹籃 1 個")
	_ok(v.objects("PILOT_heavy").size() == 1, "石燈籠 1 個")
	_ok(wind.cloth_count() >= 1, "暖簾已接線（%d）" % wind.cloth_count())
	heavy_xf = (v.objects("PILOT_heavy")[0] as Node3D).global_transform
	for l in v.objects("PILOT_lantern"):
		_lantern_pivots[(l as Node3D).get_instance_id()] = (l as Node3D).position

	print("\n[P2] calm")
	# debug_reset 從 BREEZE 開始：先讓它衰減完，再把物件歸位，否則量到的是暫態殘留。
	await _sim(6.0, 0, false)
	_reset_objects()
	print("  DBG after reset: ", _leaf_debug())
	await _sim(3.0, 0, false)
	print("  DBG after 3s calm: ", _leaf_debug(), " wind=", wind.get_wind()["strength"])
	var calm_leaf: float = _leaf_max_disp()
	var calm_basket: float = _basket_disp()
	var calm_swing: float = _lantern_max_swing()
	_ok(calm_leaf < 0.05, "落葉位移 %.3f m（<0.05）" % calm_leaf)
	_ok(calm_basket < 0.01, "竹籃位移 %.3f m（<0.01）" % calm_basket)
	_ok(calm_swing < 4.0, "燈籠擺角 %.1f°（<4°）" % calm_swing)

	print("\n[P3] breeze")
	await _sim(6.0, 1, false)
	var br_leaf: float = _leaf_max_disp()
	var br_basket: float = _basket_disp()
	var br_swing: float = _lantern_max_swing()
	_ok(br_swing > 2.5, "燈籠開始擺：%.1f°（>2.5°）" % br_swing)
	_ok(br_leaf < 0.5, "落葉只輕微移動：%.3f m（<0.5）" % br_leaf)
	_ok(br_basket < 0.02, "竹籃在微風中不動：%.3f m（<0.02）" % br_basket)

	print("\n[P4] strong gust（延遲起擺）")
	_max_step = 0.0
	wind.set_preset(3)
	wind.trigger_gust(0.8, 3.0)
	var prev := _leaf_positions()
	for i in 24:   # 0.4 s
		await physics_frame
		wind.debug_advance(DT)
		_track_step(prev)
		prev = _leaf_positions()
	var early_swing: float = _lantern_max_swing()
	for i in 300:  # 5 s
		await physics_frame
		wind.debug_advance(DT)
		_track_step(prev)
		prev = _leaf_positions()
	var g_leaf: float = _leaf_max_disp()
	var g_basket: float = _basket_disp()
	var g_swing: float = _lantern_max_swing()
	_ok(early_swing < g_swing * 0.6, "燈籠起擺有延遲：0.4 s 時 %.1f° < 5 s 的 %.1f°" % [early_swing, g_swing])
	_ok(g_leaf > 0.15, "落葉被吹動：最大位移 %.3f m（>0.15）" % g_leaf)
	_ok(g_basket > 0.008, "竹籃慢慢滑動：%.3f m（>0.008）" % g_basket)
	_ok(g_basket < 0.75, "竹籃仍在邊界內：%.3f m（<0.75）" % g_basket)
	_ok(g_swing > 8.0, "燈籠大幅擺動：%.1f°（>8°）" % g_swing)
	_ok(_max_step < 0.20, "沒有任何一步瞬移：最大 %.3f m／1/60 s（<0.20）" % _max_step)

	print("\n[P5] 恢復")
	var peak_swing := g_swing
	await _sim(10.0, 0, false)
	var r_swing: float = _lantern_max_swing()
	var r_speed: float = _leaf_max_speed()
	_ok(r_swing < peak_swing * 0.5, "燈籠擺角衰減：%.1f° → %.1f°（<50%%）" % [peak_swing, r_swing])
	_ok(r_speed < 0.6, "落葉減速：%.2f m/s（<0.6）" % r_speed)

	print("\n[P6] 錨定／重量")
	var heavy_now := (v.objects("PILOT_heavy")[0] as Node3D).global_transform
	_ok(heavy_now.origin.is_equal_approx(heavy_xf.origin) and heavy_now.basis.is_equal_approx(heavy_xf.basis),
		"石燈籠（類別 E）座標完全不變")
	var pivot_ok := true
	for l in v.objects("PILOT_lantern"):
		var n := l as Node3D
		var p0: Vector3 = _lantern_pivots.get(n.get_instance_id(), n.position)
		if n.position.distance_to(p0) > 0.001:
			pivot_ok = false
	_ok(pivot_ok, "燈籠吊點沒有位移（只有旋轉）")

	print("\n[P7] 決定性（同 seed、同 dt 重跑）")
	var d1: float = await _repeat_gust()
	var d2: float = await _repeat_gust()
	_ok(absf(d1 - d2) < 0.002, "重跑落葉位移相同：%.4f vs %.4f（Δ<0.002）" % [d1, d2])

	print("\n結果：%s（fails=%d）" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)


func _reset_objects() -> void:
	for o in v.objects("PILOT_leaf") + v.objects("PILOT_basket"):
		(o as Node).call("reset_to_origin")
	for l in v.objects("PILOT_lantern"):
		(l as Node).call("settle")


func _repeat_gust() -> float:
	wind.debug_reset()
	wind.add_shelter(SHELTER_POS, 4.0, 0.30)
	_reset_objects()
	await physics_frame
	wind.set_preset(3)
	wind.trigger_gust(0.8, 3.0)
	for i in 240:
		await physics_frame
		wind.debug_advance(DT)
	return _leaf_max_disp()


func _sim(seconds: float, preset: int, gust: bool) -> void:
	wind.set_preset(preset)
	if gust:
		wind.trigger_gust(0.8, 3.0)
	for i in int(seconds * 60.0):
		await physics_frame
		wind.debug_advance(DT)


func _leaf_max_disp() -> float:
	var m := 0.0
	for o in v.objects("PILOT_leaf"):
		m = maxf(m, float((o as Node).call("displacement")))
	return m


func _leaf_max_speed() -> float:
	var m := 0.0
	for o in v.objects("PILOT_leaf"):
		m = maxf(m, float((o as Node).call("speed")))
	return m


func _basket_disp() -> float:
	return float((v.objects("PILOT_basket")[0] as Node).call("displacement"))


func _lantern_max_swing() -> float:
	var m := 0.0
	for o in v.objects("PILOT_lantern"):
		m = maxf(m, float((o as Node).call("swing_deg")))
	return m


func _leaf_positions() -> Array:
	var a := []
	for o in v.objects("PILOT_leaf"):
		a.append((o as Node3D).global_position)
	return a


func _track_step(prev: Array) -> void:
	var now := _leaf_positions()
	for i in now.size():
		_max_step = maxf(_max_step, (now[i] as Vector3).distance_to(prev[i] as Vector3))


func _leaf_debug() -> String:
	var o: Node = v.objects("PILOT_leaf")[0]
	return "disp=%.3f moving=%s speed=%.3f pos=%s orig=%s" % [
		float(o.call("displacement")), str(o.call("is_moving")), float(o.call("speed")),
		str((o as Node3D).global_position), str(o.call("origin"))]
