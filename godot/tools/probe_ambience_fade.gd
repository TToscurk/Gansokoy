extends SceneTree
## 黃昏／黎明過渡實測：真的把時鐘推過交界，逐幀取樣兩個 player 的音量，
## 證明「有沒有凹陷、換曲換得順不順」——不是看常數，是看實際跑出來的曲線。
##
## 用法：godot --headless --script res://tools/probe_ambience_fade.gd
##
## ⚠ --script 模式下 autoload 不會建立，所以這裡自己把 ambience.gd 掛起來，
##   並塞一個假的 DayNight（只要有 .hour 就夠）與假的 Main/map_root。

const AmbienceScript = preload("res://scripts/ambience.gd")


class FakeDayNight extends Node:
	var hour := 12.0


class FakeMain extends Node:
	var map_root: Node = null


func _init() -> void:
	var fails := 0
	print("══ 晝夜過渡實測 ══")

	var dn := FakeDayNight.new()
	dn.name = "DayNight"
	root.add_child(dn)

	var main := FakeMain.new()
	main.name = "Main"
	root.add_child(main)
	var map := Node.new()
	map.name = "Trail"
	main.add_child(map)
	main.map_root = map

	var amb: Node = AmbienceScript.new()
	amb.name = "Ambience"
	root.add_child(amb)

	# 先在白天穩定下來
	dn.hour = 15.0
	await _settle(amb, 3.0)
	var s0: Dictionary = amb.debug_state()
	print("起點 %.1f h：%s  %+.1f dB" % [s0.hour, String(s0.stream).get_file(), s0.db])
	if not String(s0.stream).contains("day"):
		print("✗ 白天沒播白天曲")
		fails += 1

	# ── 日落：18.7 → 19.3 h，逐步推進，取樣總功率 ──
	print("── 日落過渡（18.7 → 19.3 h）──")
	var samples := []
	var switched_at := -1.0
	var prev_stream := String(s0.stream)
	for i in 25:
		dn.hour = 18.7 + float(i) * 0.025
		await _step()
		var st: Dictionary = amb.debug_state()
		if String(st.stream) != prev_stream:
			switched_at = dn.hour
			prev_stream = String(st.stream)
		# 兩個 player 的線性振幅平方和 = 總功率
		var pa: float = db_to_power(st.a_db) if st.a_playing else 0.0
		var pb: float = db_to_power(st.b_db) if st.b_playing else 0.0
		samples.append({"h": dn.hour, "power": pa + pb, "fading": st.fading,
			"fade_total": st.fade_total})

	if switched_at < 0.0:
		print("✗ 推過 19:00 卻沒換曲")
		fails += 1
	else:
		print("✓ 於 %.3f h 換到夜曲" % switched_at)

	var st_after: Dictionary = amb.debug_state()
	if not String(st_after.stream).contains("night"):
		print("✗ 過了 19:00 還不是夜曲：%s" % String(st_after.stream).get_file())
		fails += 1
	if not is_equal_approx(st_after.fade_total, AmbienceScript.FADE_DUSK):
		print("✗ 日落用的對淡是 %.1f s，不是 FADE_DUSK %.1f s"
			% [st_after.fade_total, AmbienceScript.FADE_DUSK])
		fails += 1
	else:
		print("✓ 日落對淡長度 %.1f s" % st_after.fade_total)

	# 對淡期間讓 tween 真的跑，取樣總功率有沒有凹陷。
	# ⚠ 這裡要量的是「對淡曲線本身」，不是音軌的絕對音量。白天 -12 dB、
	#   夜晚 -4 dB 是設計上的增益差，若直接把 volume_db 換成功率再相加，
	#   最高也只到 0.185（因為兩首本來就不是 0 dB），量到的是音軌音量、
	#   不是曲線形狀。正確做法：各自除以「自己的滿刻度功率」再相加，
	#   得到歸一化的 sin²+cos²，這才是等功率該恆為 1 的那個量。
	print("── 對淡中總功率（歸一化，等功率應接近 1.0）──")
	var day_full: float = db_to_power(-12.0)    # trail 白天目標
	var night_full: float = db_to_power(-4.0)   # trail 夜晚目標
	var powers := []
	for i in 12:
		await _step_time(AmbienceScript.FADE_DUSK / 12.0)
		var st: Dictionary = amb.debug_state()
		# 退場的是白天曲、進場的是夜曲；各自對自己的滿刻度歸一化。
		var out_norm := 0.0
		var in_norm := 0.0
		if st.a_playing:
			var pa: float = db_to_power(st.a_db)
			if String(st.active) == "環境音A":
				in_norm = pa / night_full
			else:
				out_norm = pa / day_full
		if st.b_playing:
			var pb: float = db_to_power(st.b_db)
			if String(st.active) == "環境音B":
				in_norm = pb / night_full
			else:
				out_norm = pb / day_full
		powers.append(in_norm + out_norm)
	var mn := 999.0
	var mx := 0.0
	for p in powers:
		mn = minf(mn, p)
		mx = maxf(mx, p)
	print("  取樣 %d 點：最低 %.3f  最高 %.3f" % [powers.size(), mn, mx])
	# 線性 dB 補間在中點會掉到 ~0.5；等功率應該始終在 0.7 以上。
	if mn < 0.65:
		print("  ✗ 中途掉到 %.3f —— 對淡有凹陷（聽得出音量塌一下）" % mn)
		fails += 1
	else:
		print("  ✓ 全程未低於 0.65，無可聞凹陷")

	# ── 日出：4.7 → 5.3 h ──
	print("── 日出過渡（4.7 → 5.3 h）──")
	dn.hour = 3.0
	await _settle(amb, 3.0)
	var pre_dawn: Dictionary = amb.debug_state()
	if not String(pre_dawn.stream).contains("night"):
		print("✗ 凌晨 3 點不是夜曲：%s" % String(pre_dawn.stream).get_file())
		fails += 1
	var dawn_switched := -1.0
	var prev2 := String(pre_dawn.stream)
	for i in 25:
		dn.hour = 4.7 + float(i) * 0.025
		await _step()
		var st: Dictionary = amb.debug_state()
		if String(st.stream) != prev2:
			dawn_switched = dn.hour
			prev2 = String(st.stream)
	var st_dawn: Dictionary = amb.debug_state()
	if dawn_switched < 0.0 or not String(st_dawn.stream).contains("day"):
		print("✗ 日出沒換回白天曲（目前 %s）" % String(st_dawn.stream).get_file())
		fails += 1
	else:
		print("✓ 於 %.3f h 換回白天曲，對淡 %.1f s" % [dawn_switched, st_dawn.fade_total])
	if not is_equal_approx(st_dawn.fade_total, AmbienceScript.FADE_DAWN):
		print("✗ 日出對淡是 %.1f s，不是 FADE_DAWN %.1f s"
			% [st_dawn.fade_total, AmbienceScript.FADE_DAWN])
		fails += 1

	print("══ %s（%d 項失敗）══" % ["通過" if fails == 0 else "有問題", fails])
	quit(1 if fails > 0 else 0)


## volume_db → 線性功率（振幅平方）。-60 dB 視為 0。
func db_to_power(db: float) -> float:
	if db <= -59.0:
		return 0.0
	var amp: float = pow(10.0, db / 20.0)
	return amp * amp


func _step() -> void:
	await process_frame
	await process_frame


func _step_time(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		await process_frame
		elapsed += 1.0 / 60.0


func _settle(amb: Node, seconds: float) -> void:
	await _step_time(seconds)
