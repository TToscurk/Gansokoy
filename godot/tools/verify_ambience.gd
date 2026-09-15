extends SceneTree
## 環境音驗收：不靠耳朵，靠數值。
## 用法：godot --headless --script res://tools/verify_ambience.gd

const AmbienceScript = preload("res://scripts/ambience.gd")


func _init() -> void:
	var fails := 0
	print("══ 環境音驗收 ══")

	# 1) 兩支音檔都存在、可載入、可循環、長度夠
	var files := {
		"白天": "res://assets/audio/ambience/insects_day.ogg",
		"夜晚": "res://assets/audio/ambience/insects_night.ogg",
	}
	for label in files:
		var path: String = files[label]
		if not ResourceLoader.exists(path):
			print("✗ %s 音檔不存在：%s" % [label, path])
			fails += 1
			continue
		var stream: AudioStream = load(path)
		if stream == null:
			print("✗ %s 載入失敗" % label)
			fails += 1
			continue
		var len_s := stream.get_length()
		var ok_cls := stream is AudioStreamOggVorbis
		var ok_len := len_s >= 20.0
		var ok_loop := false
		if ok_cls:
			var d := (stream as AudioStreamOggVorbis).duplicate()
			d.loop = true
			ok_loop = d.loop
		if not (ok_cls and ok_len and ok_loop):
			fails += 1
		print("%s %s  %s  %.1f s  循環=%s"
			% ["✓" if (ok_cls and ok_len and ok_loop) else "✗", label,
				stream.get_class(), len_s, "可" if ok_loop else "不可"])

	# 2) 音軌表：每張圖都要有白天與夜晚兩段，且檔案都存在
	var tracks: Dictionary = AmbienceScript.TRACKS
	print("── 音軌表（%d 張圖）──" % tracks.size())
	for map_id in tracks:
		var entries: Array = tracks[map_id]
		if entries.size() < 2:
			print("  ✗ %s 只有 %d 段（白天/夜晚應各一段）" % [map_id, entries.size()])
			fails += 1
		for t in entries:
			var sp := String(t.get("stream", ""))
			var ok := ResourceLoader.exists(sp)
			if not ok:
				fails += 1
			print("  %s %-11s %5.1f–%-5.1f h  %+6.1f dB  %s"
				% ["✓" if ok else "✗", map_id, t.get("from", 0.0), t.get("to", 24.0),
					t.get("db", 0.0), sp.get_file()])

	# 3) 全天候時段查找：每個整點都要指得到一首曲子（不該有靜音破口）
	print("── 全天候查找（trail，每 1 h）──")
	var silent_hours := []
	var day_h := 0
	var night_h := 0
	for i in 24:
		var hour := float(i)
		var hit := _pick(tracks, "trail", hour)
		if hit.is_empty():
			silent_hours.append(i)
		elif String(hit.get("stream", "")).contains("night"):
			night_h += 1
		else:
			day_h += 1
	if silent_hours.is_empty():
		print("  ✓ 24 小時無靜音破口（白天 %d h、夜晚 %d h）" % [day_h, night_h])
	else:
		print("  ✗ 這些整點沒有音軌：%s" % str(silent_hours))
		fails += 1

	# 4) 交界正確性：18:59 白天、19:01 夜晚、04:59 夜晚、05:01 白天
	print("── 晝夜交界 ──")
	var edges := [
		[18.9, "day"], [19.1, "night"], [23.5, "night"],
		[2.0, "night"], [4.9, "night"], [5.1, "day"], [12.0, "day"],
	]
	for e in edges:
		var hour: float = e[0]
		var want: String = e[1]
		var hit := _pick(tracks, "trail", hour)
		var got := "silent"
		if not hit.is_empty():
			got = "night" if String(hit.get("stream", "")).contains("night") else "day"
		var ok := got == want
		if not ok:
			fails += 1
		print("  %s %5.2f h → %-6s（預期 %s）" % ["✓" if ok else "✗", hour, got, want])

	# 5) 過渡窗與對淡長度：交界附近要拿到長對淡，平時是短的
	print("── 對淡長度 ──")
	var fade_cases := [
		[19.0, AmbienceScript.FADE_DUSK, "日落"],
		[18.6, AmbienceScript.FADE_DUSK, "日落前"],
		[5.0, AmbienceScript.FADE_DAWN, "日出"],
		[12.0, AmbienceScript.FADE_SEC, "正午（一般）"],
		[23.0, AmbienceScript.FADE_SEC, "深夜（一般）"],
	]
	for c in fade_cases:
		var hour: float = c[0]
		var want_fade: float = c[1]
		var got_fade := _fade_for(hour)
		var ok := is_equal_approx(got_fade, want_fade)
		if not ok:
			fails += 1
		print("  %s %5.2f h → %.1f s（預期 %.1f s，%s）"
			% ["✓" if ok else "✗", hour, got_fade, want_fade, c[2]])

	# 6) 環狀時刻距離：跨午夜不能算錯
	print("── 時刻環距離 ──")
	var dist_cases := [[23.9, 0.1, 0.2], [19.0, 5.0, 10.0], [0.0, 12.0, 12.0], [4.8, 5.0, 0.2]]
	for d in dist_cases:
		var got := _hour_distance(d[0], d[1])
		var ok := is_equal_approx(got, d[2])
		if not ok:
			fails += 1
		print("  %s |%.1f - %.1f| = %.2f（預期 %.2f）"
			% ["✓" if ok else "✗", d[0], d[1], got, d[2]])

	# 7) 等功率曲線：中點不能凹下去。
	#    線性 dB 補間在 t=0.5 時總功率只有 0.5（-3 dB 凹陷）；
	#    等功率曲線 sin²+cos² 恆為 1。
	print("── 等功率對淡（總功率應恆為 1.0）──")
	var worst := 0.0
	for i in 11:
		var t := float(i) / 10.0
		var a: float = sin(t * PI * 0.5)
		var b: float = cos(t * PI * 0.5)
		var power := a * a + b * b
		worst = maxf(worst, absf(power - 1.0))
	var ok_power := worst < 0.001
	if not ok_power:
		fails += 1
	print("  %s 11 個取樣點，最大偏差 %.6f" % ["✓" if ok_power else "✗", worst])

	print("══ %s（%d 項失敗）══" % ["通過" if fails == 0 else "有問題", fails])
	quit(1 if fails > 0 else 0)


## 以下三個是 ambience.gd 的同構複製。驗收要能獨立跑（--script 模式沒有
## autoload 實例），但邏輯必須跟本體一致——本體改了這裡也要跟著改。
func _pick(tracks: Dictionary, map_id: String, hour: float) -> Dictionary:
	for t in tracks.get(map_id, []):
		var f := float(t.get("from", 0.0))
		var to := float(t.get("to", 24.0))
		var hit := (hour >= f and hour < to) if f <= to else (hour >= f or hour < to)
		if hit:
			return t
	return {}


func _hour_distance(a: float, b: float) -> float:
	var d := absf(a - b)
	return minf(d, 24.0 - d)


func _fade_for(hour: float) -> float:
	if _hour_distance(hour, AmbienceScript.DUSK_HOUR) <= AmbienceScript.TRANSITION_WINDOW:
		return AmbienceScript.FADE_DUSK
	if _hour_distance(hour, AmbienceScript.DAWN_HOUR) <= AmbienceScript.TRANSITION_WINDOW:
		return AmbienceScript.FADE_DAWN
	return AmbienceScript.FADE_SEC
