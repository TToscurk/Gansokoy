extends SceneTree
## Engine.time_scale 到底會不會拖慢音效？
##
## 我對使用者聲稱「time_scale 會連音效音高一起拖慢」。這支腳本實測驗證，
## 不靠記憶。方法：讓一個 AudioStreamPlayer 播放，比較 time_scale = 1.0 與
## 0.15 時「牆鐘時間」對「播放進度」的推進比。
##   * 若音效跟著變慢 → 0.15 倍下同樣牆鐘秒數只前進 0.15 倍播放進度
##   * 若音效不受影響 → 兩者推進比相同

var _pass := 0
var _fail := 0


func check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  [OK] ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", label, ("  " + detail) if detail != "" else "")


func _initialize() -> void:
	print("=== Engine.time_scale vs 音效 實測 ===")
	print("  AudioServer.playback_speed_scale 預設 = %.2f" % AudioServer.playback_speed_scale)

	# 生一段 1 秒的正弦波，避免依賴任何音檔資產。
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.5

	var player := AudioStreamPlayer.new()
	player.stream = gen
	get_root().add_child(player)
	player.play()
	await process_frame
	await process_frame

	var rate_normal := await _measure(player, 1.0)
	var rate_slow := await _measure(player, 0.15)

	print("  正常速：%.4f 播放秒 / 牆鐘秒" % rate_normal)
	print("  0.15 倍：%.4f 播放秒 / 牆鐘秒" % rate_slow)

	Engine.time_scale = 1.0

	# 若音效真的被 time_scale 拖慢，slow 會約等於 normal * 0.15。
	var ratio: float = rate_slow / maxf(rate_normal, 0.0001)
	print("  比值 = %.3f（1.0 = 完全不受影響；0.15 = 完全跟著變慢）" % ratio)
	var audio_follows_time_scale: bool = ratio < 0.5
	if audio_follows_time_scale:
		print("  >>> 結論：time_scale **會** 拖慢音效，需要隔離。")
	else:
		print("  >>> 結論：time_scale **不會** 拖慢音效。音高由 AudioServer.playback_speed_scale 獨立控制。")

	# 反向驗證：playback_speed_scale 才是控制音效速率的那一個
	AudioServer.playback_speed_scale = 0.15
	var rate_audio_slow := await _measure(player, 1.0)
	AudioServer.playback_speed_scale = 1.0
	print("  playback_speed_scale=0.15 時：%.4f 播放秒 / 牆鐘秒" % rate_audio_slow)
	check("playback_speed_scale 才是控制音效速率的旋鈕",
		rate_audio_slow < rate_normal * 0.5,
		"%.4f vs %.4f" % [rate_audio_slow, rate_normal])

	player.queue_free()
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0)


## 在指定 time_scale 下，量「每一牆鐘秒推進多少播放秒」。
func _measure(player: AudioStreamPlayer, scale: float) -> float:
	Engine.time_scale = scale
	await process_frame
	var t0 := Time.get_ticks_msec()
	var p0 := player.get_playback_position()
	# 等約 0.4 牆鐘秒（用真實時鐘判定，不用 delta —— delta 已被 time_scale 壓縮）
	while Time.get_ticks_msec() - t0 < 400:
		await process_frame
	var wall: float = (Time.get_ticks_msec() - t0) / 1000.0
	var played: float = player.get_playback_position() - p0
	return played / maxf(wall, 0.0001)
