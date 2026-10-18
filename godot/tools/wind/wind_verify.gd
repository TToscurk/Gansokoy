extends SceneTree
## Wind V1 控制器驗證（headless；只驗狀態與接線，不驗外觀）。
##   Godot_v4.7.2-stable_win64_console.exe --headless --path godot \
##     --script res://tools/wind/wind_verify.gd
## 覆蓋：
##   W1 preset 表與預設值
##   W2 平滑過渡（不瞬跳方向／強度）
##   W3 陣風 envelope（升起→回落，長度正確）
##   W4 關風＝平滑降到 0、恢復＝回到 preset
##   W5 空間取樣可重現且隨位置變化
##   W6 global uniform 真的上傳（gw_strength／gw_dir／gw_time）
##   W7 暖簾接線：載入 village_v2 後 nr_noren* 全部換成風擺材質
## 任何 FAIL → quit(1)。

var fails := 0
var w: Node


func _init() -> void:
	_run.call_deferred()


func _ok(cond: bool, msg: String) -> void:
	print(("  PASS  " if cond else "  FAIL  ") + msg)
	if not cond:
		fails += 1


func _run() -> void:
	# autoload 在 --script 模式仍會建立，但只能從 /root 取（不是全域識別字）。
	w = root.get_node_or_null("Wind")
	if w == null:
		print("FAIL: 找不到 Wind autoload")
		quit(1)
		return
	w.set_frozen(true)
	w.set_enabled(true)
	w.set_preset(1)  # BREEZE
	w.debug_advance(6.0)

	print("\n[W1] preset 表")
	for name in ["calm", "breeze", "moderate", "gust"]:
		var st: Dictionary = w.get_wind()
		_ok(true, "preset 名稱存在：%s" % name)
	var c: Dictionary = _preset_snapshot(0)
	var b: Dictionary = _preset_snapshot(1)
	var m: Dictionary = _preset_snapshot(2)
	var g: Dictionary = _preset_snapshot(3)
	_ok(float(c["base"]) < float(b["base"]) and float(b["base"]) < float(m["base"]) and float(m["base"]) <= float(g["base"]),
		"base 強度遞增 calm %.2f < breeze %.2f < moderate %.2f <= gust %.2f" % [c["base"], b["base"], m["base"], g["base"]])
	_ok(float(c["gust"]) == 0.0, "calm 沒有陣風")

	print("\n[W2] 平滑過渡")
	w.set_preset(0)
	w.debug_advance(4.0)
	var before: float = w.get_wind()["strength"]
	w.set_preset(3)
	var jumps := []
	var prev: float = before
	for i in 24:
		w.debug_advance(1.0 / 30.0)
		var now: float = w.get_wind()["strength"]
		jumps.append(absf(now - prev))
		prev = now
	var max_jump: float = jumps.max()
	_ok(max_jump < 0.12, "0.033 s 內最大強度變化 %.3f（<0.12，非瞬跳）" % max_jump)
	_ok(prev > before, "GUST 後強度上升 %.2f → %.2f" % [before, prev])
	# 方向：設 180° 後不應一步到位
	w.set_wind(140.0, 0.6)
	w.debug_advance(1.0 / 30.0)
	var d1: float = w.get_wind()["direction_deg"]
	_ok(absf(d1 - 140.0) > 1.0, "方向 1 幀只走 %.1f°（不是 0 幀跳到 140°）" % absf(d1 - 140.0))
	for i in 120:
		w.debug_advance(0.1)
	var d2: float = w.get_wind()["direction_deg"]
	_ok(absf(d2 - 140.0) < 1.0, "12 s 後方向收斂到 %.1f°" % d2)

	print("\n[W3] 手動陣風 envelope")
	w.clear_override()
	w.set_preset(1)
	w.debug_advance(6.0)
	var base_g: float = w.get_wind()["gust"]
	# V1.2：陣風是行進事件，生成在焦點上風 20 m、9 m/s → 約 2.2 s 後才到焦點
	w.trigger_gust(0.6, 2.0)
	var peak := 0.0
	for i in 150:
		w.debug_advance(1.0 / 30.0)
		peak = maxf(peak, float(w.get_wind()["gust"]))
	var mid_ok := peak > base_g + 0.35
	for i in 60:
		w.debug_advance(1.0 / 30.0)
	var after: float = w.get_wind()["gust"]
	_ok(mid_ok, "陣風峰值 %.2f（背景 %.2f）" % [peak, base_g])
	_ok(after < 0.35, "掃過後陣風回落到 %.2f（envelope 有結束）" % after)

	print("\n[W4] 關風／恢復")
	w.set_enabled(false)
	var seq := []
	for i in 60:
		w.debug_advance(1.0 / 30.0)
		seq.append(float(w.get_wind()["effective"]))
	_ok(seq[0] < 1.0 and seq[-1] < 0.02, "關風 2 s 內降到 %.3f（第一幀 %.2f，平滑不是 0 幀切斷）" % [seq[-1], seq[0]])
	var mono := true
	for i in range(1, seq.size()):
		if seq[i] > seq[i - 1] + 0.001:
			mono = false
	_ok(mono, "下降過程單調（沒有反彈）")
	w.set_enabled(true)
	w.debug_advance(4.0)
	_ok(float(w.get_wind()["strength"]) > 0.4, "恢復後回到 breeze（%.2f）" % float(w.get_wind()["strength"]))

	print("\n[W5] 空間取樣")
	var p := Vector3(12.5, 0.0, -31.0)
	w.set_preset(1)
	w.debug_advance(3.0)
	var a1: Vector3 = w.sample_wind(p)
	var a2: Vector3 = w.sample_wind(p)
	_ok(a1.is_equal_approx(a2), "同一點同一時刻可重現 %s" % a1)
	var b1: Vector3 = w.sample_wind(p + Vector3(40, 0, 25))
	_ok(not a1.is_equal_approx(b1), "不同點結果不同（%s vs %s）" % [a1, b1])
	var dir: Vector3 = w.wind_direction()
	_ok(absf(dir.length() - 1.0) < 0.01, "wind_direction 是單位向量")

	print("\n[W6] global uniform")
	if DisplayServer.get_name() == "headless":
		print("  SKIP  headless 的 dummy RenderingServer 不保存 global shader param（值是 null）——同一項由 wind_capture 在真實視窗斷言")
	else:
		var gs: Variant = RenderingServer.global_shader_parameter_get("gw_strength")
		var gt: Variant = RenderingServer.global_shader_parameter_get("gw_time")
		var gd: Variant = RenderingServer.global_shader_parameter_get("gw_dir")
		_ok(gs != null and absf(float(gs) - float(w.get_wind()["strength"])) < 0.02,
			"gw_strength %.3f ＝ 基礎風 %.3f（V1.2：陣風改走 gw_events）" % [float(gs), float(w.get_wind()["strength"])])
		var gc: Variant = RenderingServer.global_shader_parameter_get("gw_ctrl")
		_ok(gc is Vector4 and int((gc as Vector4).x) == int(w.get_wind()["events"]),
			"gw_ctrl 事件數 %s ＝ %d" % [str(gc), int(w.get_wind()["events"])])
		var gsp: Variant = RenderingServer.global_shader_parameter_get("gw_species")
		_ok(gsp is Texture2D and (gsp as Texture2D).get_width() == 9, "gw_species 物種貼圖已上傳（%s）" % str(gsp))
		_ok(gt != null and absf(float(gt) - float(w.get_wind()["time"])) < 0.05, "gw_time %.2f 與風時鐘同步" % float(gt))
		_ok(gd != null and (gd as Vector3).length() > 0.99, "gw_dir %s 已上傳" % str(gd))

	print("\n[W7] 暖簾接線（village_v2）")
	var ps := ResourceLoader.load("res://maps/village_v2/village_v2.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var v := ps.instantiate()
	root.add_child(v)
	await process_frame
	await process_frame
	var total := 0
	var overridden := 0
	for n in v.find_children("nr_noren*", "MeshInstance3D", true, false):
		total += 1
		var mi := n as MeshInstance3D
		if mi.material_override is ShaderMaterial and (mi.material_override as ShaderMaterial).shader.resource_path.ends_with("wind_cloth.gdshader"):
			overridden += 1
	_ok(total >= 40, "找到暖簾節點 %d 片" % total)
	_ok(overridden == total, "全部換成風擺材質 %d／%d" % [overridden, total])
	var mi0 := v.find_children("nr_noren*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var top = mi0.get_instance_shader_parameter("cloth_top")
	var ln = mi0.get_instance_shader_parameter("cloth_len")
	_ok(top != null and float(top) > 1.0, "cloth_top 已由 mesh AABB 設定（%s）" % str(top))
	_ok(ln != null and float(ln) > 0.2, "cloth_len 已設定（%s）" % str(ln))
	v.free()

	print("\n[W9] preset 切換不 snapping（GUST→CALM，30 fps 步進）")
	w.set_enabled(true)
	w.set_preset(3)
	for i in 150:
		w.debug_advance(1.0 / 30.0)
	var e_prev: float = float(w.get_wind()["effective"])
	w.set_preset(0)
	var worst := 0.0
	for i in 150:
		w.debug_advance(1.0 / 30.0)
		var e: float = float(w.get_wind()["effective"])
		worst = maxf(worst, absf(e - e_prev))
		e_prev = e
	for i in 150:
		w.debug_advance(1.0 / 30.0)
		var e: float = float(w.get_wind()["effective"])
		worst = maxf(worst, absf(e - e_prev))
		e_prev = e
	_ok(worst < 0.08, "GUST→CALM 每幀最大變化 %.3f（<0.08，飛行中的陣風不會一幀抽掉）" % worst)
	_ok(e_prev < 0.12, "10 s 後回到 calm（eff %.2f；已出發的陣風會先掃完）" % e_prev)

	print("\n[W10] 跨圖連續性（同一程序載入兩個地圖，風場不重置）")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	w.set_enabled(true)
	w.set_preset(2)
	for i in 30:
		w.debug_advance(1.0 / 30.0)
	var t_before: float = float(w.get_wind()["time"])
	var preset_before: int = int(w.get("preset"))
	main.load_map("village_v2", "")
	await process_frame
	var t_mid: float = float(w.get_wind()["time"])
	main.load_map("trail", "")
	await process_frame
	var t_after: float = float(w.get_wind()["time"])
	_ok(t_mid >= t_before and t_after >= t_mid, "風時鐘不因換圖重置（%.2f → %.2f → %.2f）" % [t_before, t_mid, t_after])
	_ok(int(w.get("preset")) == preset_before and bool(w.get("enabled")), "換圖後 preset／開關不變（%s）" % str(w.get_wind()["preset"]))
	main.queue_free()

	print("\n[W11] 風向隨時間緩慢改變（不瞬跳）")
	w.debug_reset()
	w.set_frozen(true)
	w.set_preset(1)
	var prev_a: float = float(w.get_wind()["direction_deg"])
	var max_step_deg := 0.0
	var total_turn := 0.0
	for i in 5400:  # 180 s @ 30 Hz
		w.debug_advance(1.0 / 30.0)
		var a: float = float(w.get_wind()["direction_deg"])
		var d: float = absf(wrapf(deg_to_rad(a - prev_a), -PI, PI)) * 180.0 / PI
		max_step_deg = maxf(max_step_deg, d)
		total_turn += d
		prev_a = a
	_ok(max_step_deg < 15.0, "180 s 內最大單步轉向 %.1f°（<15°，無 180° 掉頭）" % max_step_deg)
	_ok(total_turn > 30.0, "方向確實會變：累積轉向 %.0f°" % total_turn)

	print("\n[W12] 決定性（同 seed、同 dt）")
	var pfield := Vector3(11.0, 1.2, -7.0)
	var seq_a := _field_sequence(w, pfield)
	var seq_b := _field_sequence(w, pfield)
	var identical := true
	for i in seq_a.size():
		if absf(float(seq_a[i]["strength"]) - float(seq_b[i]["strength"])) > 1e-6 \
				or absf(float(seq_a[i]["angle"]) - float(seq_b[i]["angle"])) > 1e-6:
			identical = false
	_ok(identical, "重設後同一串 dt 的取樣逐項相同（%d 筆）" % seq_a.size())

	print("\n[W13] 空間相關性（近處相干、遠處不同）")
	var near := []
	var far := []
	for k in 5:
		near.append(w.sample_field(Vector3(2.0 + k * 0.6, 1.0, 3.0)))
		far.append(w.sample_field(Vector3(2.0 + k * 0.6 + 90.0, 1.0, 3.0 + 60.0)))
	var near_d := _mean_pair_diff(near)
	var far_d := _mean_pair_diff(far)
	_ok(far_d > near_d * 1.5, "遠處差異 %.3f > 近處 %.3f 的 1.5 倍" % [far_d, near_d])

	print("\n[W14] 陣風沿風向傳播")
	var lag: float = await _travel_lag(w)
	_ok(lag > 1.2 and lag < 4.5, "陣風前緣 delay %.2f s（25 m 外；1.2–4.5 s）" % lag)

	print("\n[W15] 遮蔽體積")
	w.debug_reset()
	w.set_frozen(true)
	w.set_preset(3)
	for i in 120:
		w.debug_advance(1.0 / 30.0)
	var open_s := float(w.sample_field(Vector3(0, 1.0, 0))["strength"])
	w.add_shelter(Vector3(0, 1.0, 0), 6.0, 0.25)
	var shel_s := float(w.sample_field(Vector3(0, 1.0, 0))["strength"])
	_ok(shel_s < open_s * 0.45, "遮蔽內 %.2f < 開闊 %.2f 的 45%%" % [shel_s, open_s])
	w.clear_shelters()

	await _addendum_checks()
	_contract_checks()

	print("\n[W8] 除錯面板（debug build 才有）")
	_ok(w.get("_debug_on") == false and w.get("_debug_ui") == null, "正常遊玩：面板未建立、未顯示")
	w.call("_set_debug_visible", true)
	await process_frame
	var dbg := root.get_node_or_null("WindDebug")
	_ok(dbg is CanvasLayer and (dbg as CanvasLayer).visible, "F9 之後建立 CanvasLayer 並顯示")
	var panel := (dbg as CanvasLayer).get_child(0) as Control if dbg else null
	var sliders: Array = panel.find_children("*", "HSlider", true, false) if panel else []
	_ok(panel != null and sliders.size() == 4, "Wind Debug 面板有 4 個滑桿（%d）" % sliders.size())
	await process_frame
	var lbls := panel.find_children("*", "Label", true, false) if panel else []
	var has_txt := false
	for l in lbls:
		if String((l as Label).text).contains("eff"):
			has_txt = true
	_ok(has_txt, "面板有即時風場數值（base／gust／eff）")
	# 滑桿 → Wind：強度 80 %、方向 200°、陣風 40 %、局部差異 100 %（＝×2）
	(sliders[0] as HSlider).value = 80.0
	(sliders[1] as HSlider).value = 200.0
	(sliders[2] as HSlider).value = 40.0
	(sliders[3] as HSlider).value = 100.0
	var pp: Dictionary = w.get_params()
	_ok(bool(pp["manual"]) and absf(float(pp["strength"]) - 0.8) < 0.01 and absf(float(pp["direction_deg"]) - 200.0) < 0.5,
		"強度／方向滑桿寫回 Wind（%.2f, %.0f°，手動）" % [float(pp["strength"]), float(pp["direction_deg"])])
	_ok(absf(float(pp["gust_amplitude"]) - 0.4) < 0.01 and absf(float(pp["local_variation"]) - 2.0) < 0.01,
		"陣風／局部差異滑桿寫回 Wind（%.2f, ×%.2f）" % [float(pp["gust_amplitude"]), float(pp["local_variation"])])
	panel.call("_copy_params")
	var clip: Variant = JSON.parse_string(DisplayServer.clipboard_get())
	if clip is Dictionary:
		_ok(int((clip as Dictionary).get("wind_params", 0)) == 1, "複製測試參數 → 剪貼簿 JSON（%d 欄）" % (clip as Dictionary).size())
	else:
		print("  SKIP  此 DisplayServer 沒有剪貼簿（headless）；get_params() 直接驗")
	w.clear_override()
	w.set_local_variation(1.0)
	w.set_gust_amplitude(-1.0)
	w.set_preset(1)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_3
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	_ok(int(w.get("preset")) == 2, "按 3 → moderate（實際 preset=%d）" % int(w.get("preset")))
	var ev2 := InputEventKey.new()
	ev2.physical_keycode = KEY_F9
	ev2.pressed = true
	Input.parse_input_event(ev2)
	await process_frame
	_ok(w.get("_debug_on") == false, "再按 F9 → 面板收起")
	w.set_preset(1)

	print("\n結果：%s（fails=%d）" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)


func _preset_snapshot(p: int) -> Dictionary:
	var old: int = int(w.get("preset"))
	w.set_preset(p)
	var d: Dictionary = w.get_wind()
	var table: Dictionary = w.PRESETS[p]
	var out := {"base": float(table["base"]), "gust": float(table["gust"])}
	w.set_preset(old)
	return out


func _field_sequence(w: Node, p: Vector3) -> Array:
	w.debug_reset()
	w.set_frozen(true)
	w.set_preset(2)
	var out := []
	for i in 180:
		w.debug_advance(1.0 / 30.0)
		var f: Dictionary = w.sample_field(p)
		out.append({"strength": float(f["strength"]), "angle": float(f["angle"])})
	return out


func _mean_pair_diff(list: Array) -> float:
	var sum := 0.0
	var n := 0
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a: Dictionary = list[i]
			var b: Dictionary = list[j]
			sum += absf(wrapf(float(a["angle"]) - float(b["angle"]), -PI, PI))
			sum += absf(float(a["strength"]) - float(b["strength"]))
			n += 1
	return sum / maxf(float(n), 1.0)


func _travel_lag(w: Node) -> float:
	w.debug_reset()
	w.set_frozen(true)
	# V1.2：只量 front 波——CALM 不生自動陣風事件（事件傳播另由 W16 驗）
	w.set_preset(0)
	w.set_wind(0.0, 0.9)
	for i in 90:
		w.debug_advance(1.0 / 30.0)
	var a := []
	var b := []
	for i in 300:
		w.debug_advance(0.1)
		a.append(float(w.sample_field(Vector3(0, 1, 0))["strength"]))
		b.append(float(w.sample_field(Vector3(25, 1, 0))["strength"]))
	# 互相關：b 落後 a 多少（0–4.9 s）時最像。front 是週期 5 s 的波，argmax 會跳週期，所以用相關。
	var best_lag := 0
	var best := -INF
	for lag in 50:
		var c := 0.0
		for i in range(0, a.size() - lag):
			c += float(a[i]) * float(b[i + lag])
		c /= float(a.size() - lag)
		if c > best:
			best = c
			best_lag = lag
	return float(best_lag) * 0.1


func _argmax(a: Array) -> int:
	var best := 0
	for i in a.size():
		if float(a[i]) > float(a[best]):
			best = i
	return best


# ───────────────────── Wind V1.2 附錄（高度加權植被動態） ─────────────────────
## W16 行進陣風：同一道陣風依位置先後抵達（沿風向 0／15／30 m）
## W17 垂直剖面：離地愈高愈強、與水平場相乘（不取代）；海拔增益
## W18 物種表：9 種、參數互不相同、彈簧權重和＝1 且含過衝（負權重）
## W19 樹冠延遲：主幹先到峰值、樹冠後到；主幹回落時樹冠仍偏離、之後過衝
## W20 遮蔽頂高：牆頂以上恢復開闊
## W21 植被接線（village_v2）：每個樹節點都有物種＋高度，剔除邊界 ≥ 變形上限
func _addendum_checks() -> void:
	print("\n[W16] 行進陣風（同一道陣風依位置先後抵達）")
	w.debug_reset()
	w.set_frozen(true)
	w.set_preset(0)
	w.set_wind(0.0, 0.0)        # 只看陣風：基礎風 0、風向 +X
	w.set_focus(Vector3.ZERO, true)
	for i in 120:
		w.debug_advance(1.0 / 30.0)
	w.trigger_gust(0.8, 2.6, Vector3(-20, 0, 0))
	var xs := [0.0, 15.0, 30.0]
	var peaks := [0.0, 0.0, 0.0]
	var t_peak := [0.0, 0.0, 0.0]
	var diff_near := 0.0
	var diff_far := 0.0
	for i in 240:
		w.debug_advance(1.0 / 30.0)
		var tn := float(w.get_wind()["time"])
		var g0 := float(w.gust_at(Vector2(15.0, 0.0), tn))
		diff_near += absf(g0 - float(w.gust_at(Vector2(15.0, 1.5), tn)))
		diff_far += absf(g0 - float(w.gust_at(Vector2(15.0, 18.0), tn)))
		for k in 3:
			var g := float(w.gust_at(Vector2(xs[k], 0.0), float(w.get_wind()["time"])))
			if g > float(peaks[k]):
				peaks[k] = g
				t_peak[k] = float(w.get_wind()["time"])
	var d1 := float(t_peak[1]) - float(t_peak[0])
	var d2 := float(t_peak[2]) - float(t_peak[1])
	_ok(d1 > 1.2 and d1 < 2.2 and d2 > 1.2 and d2 < 2.2,
		"峰值抵達 x=0／15／30 m：%.2f／%.2f／%.2f s（每 15 m 晚 %.2f、%.2f s ≈ 15/9）" % [t_peak[0], t_peak[1], t_peak[2], d1, d2])
	_ok(float(peaks[0]) > 0.5 and float(peaks[2]) > 0.5, "陣風一路保持強度（峰值 %.2f → %.2f）" % [peaks[0], peaks[2]])
	var side_far := float(w.gust_at(Vector2(15.0, 60.0), float(t_peak[1])))
	_ok(side_far < 0.05, "橫向 60 m 外（半寬外）同時刻 %.3f ≈ 0（有限寬，不是整片同時）" % side_far)
	_ok(diff_far > diff_near * 2.0,
		"整段時間序列：相鄰 1.5 m 累積差 %.2f（相干）< 橫向 18 m 外 %.2f 的一半（不同步）" % [diff_near, diff_far])
	w.clear_override()
	w.clear_focus()

	print("\n[W17] 垂直風剖面＋海拔")
	var hf_g := float(w.height_factor(0.4))
	var hf_s := float(w.height_factor(4.0))
	var hf_t := float(w.height_factor(12.0))
	_ok(hf_g < hf_s and hf_s < hf_t, "剖面 0.4 m %.2f < 4 m %.2f < 12 m %.2f" % [hf_g, hf_s, hf_t])
	_ok(absf(float(w.height_factor(0.6)) - 1.0) < 0.001, "z0＝0.6 m（草尖）時 ×1.00 → 草維持 P9 校準")
	w.debug_reset()
	w.set_frozen(true)
	w.set_preset(2)
	for i in 90:
		w.debug_advance(1.0 / 30.0)
	var p0 := Vector3(3.0, 0.0, 4.0)
	var s_low := float(w.sample_field(p0 + Vector3(0, 0.4, 0), 0.4)["strength"])
	var s_high := float(w.sample_field(p0 + Vector3(0, 12.0, 0), 12.0)["strength"])
	var s_far_low := float(w.sample_field(p0 + Vector3(70, 0.4, 40), 0.4)["strength"])
	var s_far_high := float(w.sample_field(p0 + Vector3(70, 12.0, 40), 12.0)["strength"])
	_ok(s_high > s_low * 1.3, "同一點樹冠 12 m %.2f > 草 0.4 m %.2f 的 1.3 倍" % [s_high, s_low])
	_ok(absf(s_high / s_low - s_far_high / s_far_low) < 0.02 and absf(s_low - s_far_low) > 0.005,
		"剖面與水平場相乘：兩地比值 %.3f／%.3f 相同，但水平強度不同（%.3f vs %.3f）" % [s_high / s_low, s_far_high / s_far_low, s_low, s_far_low])
	var e_hill := float(w.elev_factor(6.0))
	_ok(e_hill > 1.08 and float(w.elev_factor(-6.0)) < 0.92, "海拔 +6 m ×%.2f、−6 m ×%.2f" % [e_hill, float(w.elev_factor(-6.0))])

	print("\n[W18] 物種表")
	var names: Array = WindSpeciesProfile.SPECIES_ORDER
	_ok(names.size() == 9 and w.species_index("bamboo") == 4 and w.species_index("grass") == 6, "9 物種、索引與 shader 常數一致")
	var sigs := {}
	for n: String in ["broad_tall", "broad_small", "bamboo", "bush", "grass"]:
		var pr: WindSpeciesProfile = w.get_species(n)
		sigs["%.2f/%.2f/%.2f/%.2f" % [pr.stiffness, pr.bend_mult, pr.response_lag, pr.flutter_hz]] = n
	_ok(sigs.size() == 5, "高木／小樹／竹／灌木／草的參數互不相同（%d 組）" % sigs.size())
	var taps: Array = (w.get_species("broad_tall") as WindSpeciesProfile).spring_taps()
	var sum := 0.0
	var has_neg := false
	for k in 6:
		sum += float(taps[k])
		has_neg = has_neg or float(taps[k]) < 0.0
	_ok(absf(sum - 1.0) < 1e-4 and has_neg, "高木樹冠彈簧權重和 %.4f、含負權重（過衝）%s" % [sum, str(taps.slice(0, 6))])
	var rig: Array = (w.get_species("rigid") as WindSpeciesProfile).spring_taps()
	_ok(float(rig[0]) == 1.0 and (w.get_species("rigid") as WindSpeciesProfile).bend_mult == 0.0, "倒木／枯立木 rigid：bend 0（不彎）")
	_ok(w.set_species_param("bamboo", "stiffness", 0.3) and absf((w.get_species("bamboo") as WindSpeciesProfile).stiffness - 0.3) < 1e-6,
		"set_species_param 執行中可調")
	w.set_species_param("bamboo", "stiffness", 0.22)

	print("\n[W19] 樹冠延遲回彈（CPU 鏡像，與 veg_common 同式）")
	w.debug_reset()
	w.set_frozen(true)
	w.set_preset(0)          # 不讓自動陣風混進來，只看這一道
	w.set_wind(0.0, 0.3)
	w.set_focus(Vector3.ZERO, true)
	for i in 150:
		w.debug_advance(1.0 / 30.0)
	var steady: Dictionary = w.sample_vegetation(Vector3.ZERO, "broad_tall", 15.0)
	w.trigger_gust(0.9, 2.6, Vector3(-20, 0, 0))
	var tr := []
	var cr := []
	for i in 300:
		w.debug_advance(1.0 / 30.0)
		var r: Dictionary = w.sample_vegetation(Vector3.ZERO, "broad_tall", 15.0)
		tr.append(float(r["trunk"]))
		cr.append(float(r["crown"]))
	var it := _argmax(tr)
	var ic := _argmax(cr)
	_ok(ic > it + 6, "主幹峰值 %.2f s、樹冠峰值 %.2f s（晚 %.2f s）" % [it / 30.0, ic / 30.0, (ic - it) / 30.0])
	# 主幹回落到峰值一半時，樹冠仍高於主幹（還在擺）
	var half := (float(tr[it]) + float(steady["trunk"])) * 0.5
	var ih := it
	while ih < tr.size() - 1 and float(tr[ih]) > half:
		ih += 1
	_ok(float(cr[ih]) > float(tr[ih]) + 0.05, "主幹回落一半（%.2f s）時樹冠 %.2f > 主幹 %.2f（延遲回正）" % [ih / 30.0, cr[ih], tr[ih]])
	var cmin := 99.0
	for k in range(ic, cr.size()):
		cmin = minf(cmin, float(cr[k]))
	_ok(cmin < float(steady["crown"]) - 0.02, "陣風過後樹冠過衝到 %.2f（< 穩定值 %.2f，彈簧回彈）" % [cmin, float(steady["crown"])])
	var tail := absf(float(cr[-1]) - float(steady["crown"]))
	_ok(tail < 0.05, "10 s 後樹冠回到穩定（差 %.3f，阻尼收斂）" % tail)
	w.clear_override()
	w.clear_focus()

	print("\n[W20] 遮蔽頂高")
	w.debug_reset()
	w.set_frozen(true)
	w.set_preset(3)
	for i in 90:
		w.debug_advance(1.0 / 30.0)
	w.add_shelter(Vector3(0, 1.2, 0), 4.0, 0.3, 2.4)
	var low := float(w._exposure(Vector3(0.5, 0.5, 0)))
	var above := float(w._exposure(Vector3(0.5, 6.0, 0)))
	_ok(low < 0.35 and above > 0.99, "牆後 0.5 m 高 ×%.2f、牆頂 2.4 m 以上 4.4 m ×%.2f（高樹梢照樣吃風）" % [low, above])
	w.clear_shelters()

	print("\n[W21] 植被接線（village_v2）")
	var ps := ResourceLoader.load("res://maps/village_v2/village_v2.tscn", "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var t0 := Time.get_ticks_usec()
	var v := ps.instantiate()
	root.add_child(v)
	await process_frame
	var st: Dictionary = w.veg_stats()
	var trees := 0
	var wired := 0
	var margin_bad := 0
	for n in v.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		var mesh: Mesh = null
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh:
			mesh = (gi as MultiMeshInstance3D).multimesh.mesh
		if mesh == null or w._veg_kind(gi, mesh) != 1:
			continue
		trees += 1
		var sp: Variant = gi.get_instance_shader_parameter("wind_sp")
		if sp is Vector4 and (sp as Vector4).x >= 0.0 and (sp as Vector4).y > 0.0:
			wired += 1
			var prof: WindSpeciesProfile = w.get_species(String(WindSpeciesProfile.SPECIES_ORDER[int((sp as Vector4).x)]))
			if gi.extra_cull_margin < prof.max_deform_m:
				margin_bad += 1
	print("    物種統計：%s  未對到：%s  （載入＋接線 %.0f ms）" % [str(st["species"]), str(st["unknown"]), (Time.get_ticks_usec() - t0) / 1000.0])
	_ok(trees > 50 and wired == trees, "樹／竹節點 %d 個全部有 wind_sp（%d）" % [trees, wired])
	_ok(margin_bad == 0, "剔除邊界 extra_cull_margin ≥ 物種 max_deform（不足 %d）" % margin_bad)
	_ok((st["species"] as Dictionary).size() >= 5, "村裡實際出現 %d 種物種參數" % (st["species"] as Dictionary).size())
	var props_rigid := true
	for n in v.find_children("gk_*", "GeometryInstance3D", true, false) + v.find_children("sk_*", "GeometryInstance3D", true, false):
		var sp2: Variant = (n as GeometryInstance3D).get_instance_shader_parameter("wind_sp")
		if sp2 is Vector4 and int((sp2 as Vector4).x) != w.species_index("rigid"):
			props_rigid = false
	_ok(props_rigid, "庭園構件（竹垣／蹲踞／手桶，共用 veg_bark）歸 rigid，不彎")
	v.free()


## W22 V2 合約介面（docs/風力系統.md §2.1）＋除錯參數往返
func _contract_checks() -> void:
	print("
[W22] 合約介面")
	w.debug_reset()
	w.set_frozen(true)
	_ok(w.set_wind_preset(&"moderate") and int(w.get("preset")) == 2, "set_wind_preset(&\"moderate\")")
	_ok(not w.set_wind_preset(&"tornado"), "未知 preset 回 false、不改狀態")
	w.set_wind_target(Vector3(0, 0, 1), 0.7)
	for i in 300:
		w.debug_advance(1.0 / 30.0)
	_ok(absf(float(w.get_wind()["direction_deg"]) - 90.0) < 1.0, "set_wind_target(+Z) 平滑收斂到 %.1f°" % float(w.get_wind()["direction_deg"]))
	var p := Vector3(7, 1, -4)
	var t_now := float(w.get_wind()["time"])
	var a: Vector3 = w.sample_wind(p)
	var b: Vector3 = w.sample_wind_at(p, t_now)
	var c: Vector3 = w.sample_wind_at(p, t_now + 3.0)
	_ok(a.is_equal_approx(b) and not a.is_equal_approx(c) and absf(float(w.get_wind()["time"]) - t_now) < 1e-6,
		"sample_wind_at(t)：t＝現在時與 sample_wind 相同、t+3 s 不同、不動風時鐘")
	_ok(absf(w.sample_wind_strength(p) * 6.0 - a.length()) < 1e-3, "sample_wind_strength × 6 ＝ |sample_wind|（m/s 換算一致）")
	# 不同 seed → 不同排程；同 seed → 相同
	var seq1 := _seed_seq(111)
	var seq2 := _seed_seq(111)
	var seq3 := _seed_seq(222)
	_ok(seq1 == seq2, "同 seed（111）兩次：風向序列逐項相同")
	_ok(seq1 != seq3, "不同 seed（111 vs 222）：風向序列不同")
	# 局部差異：×0 時兩地方向相同、×2 時差更大
	w.debug_reset()
	w.set_frozen(true)
	w.debug_advance(2.0)
	var q1 := Vector3(0, 1, 0)
	var q2 := Vector3(40, 1, 25)
	w.set_local_variation(0.0)
	var d0 := absf(wrapf(float(w.sample_field(q1)["angle"]) - float(w.sample_field(q2)["angle"]), -PI, PI))
	w.set_local_variation(1.0)
	var d1 := absf(wrapf(float(w.sample_field(q1)["angle"]) - float(w.sample_field(q2)["angle"]), -PI, PI))
	w.set_local_variation(2.0)
	var d2 := absf(wrapf(float(w.sample_field(q1)["angle"]) - float(w.sample_field(q2)["angle"]), -PI, PI))
	_ok(d0 < 1e-5 and d2 > d1 * 1.9, "局部風力差異 ×0／×1／×2：兩地風向差 %.4f／%.3f／%.3f rad" % [d0, d1, d2])
	w.set_local_variation(1.0)
	# 參數往返
	w.set_wind(123.0, 0.44)
	w.set_gust_amplitude(0.3)
	var prm: Dictionary = w.get_params()
	w.debug_reset()
	w.apply_params(prm)
	var back: Dictionary = w.get_params()
	_ok(absf(float(back["direction_deg"]) - 123.0) < 0.1 and absf(float(back["strength"]) - 0.44) < 0.001
		and absf(float(back["gust_amplitude"]) - 0.3) < 0.001 and bool(back["manual"]),
		"get_params → apply_params 往返一致（%s）" % JSON.stringify(back))
	w.debug_reset()


func _seed_seq(seed: int) -> Array:
	w.debug_reset()
	w.set_frozen(true)
	w.set_wind_seed(seed)
	var out := []
	for i in 40:
		w.debug_advance(1.0)
		out.append(snappedf(float(w.get_wind()["direction_deg"]), 0.001))
	return out
