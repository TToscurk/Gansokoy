extends SceneTree
## NpcVoice 測試：烘焙快取、預熱、執行期生成＋自動快取（ja／en）、引擎離線退回（需開 VOICEVOX、AivisSpeech、Kokoro：D:\Tools\TTS\start_*.cmd）
## godot --headless --path godot -s res://tools/npc_voice/verify_npc_voice.gd
const V := preload("res://systems/npc_life/npc_voice.gd")
var fails := 0

func _ok(name: String, ok: bool, detail := "") -> void:
	if not ok: fails += 1
	print("[%s] %s %s" % ["PASS" if ok else "FAIL", name, detail])

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var stamp := str(Time.get_unix_time_from_system())
	# 1) 烘焙快取命中（res://）
	var v1: Node = V.new()
	root.add_child(v1)
	await process_frame
	v1.set("lang", "ja")
	var c: Dictionary = v1.call("lookup", "marisa", "よう、慧音！今日も見回りか？")
	_ok("烘焙快取命中（res://assets/voice）", not c.is_empty() and c.stream != null, "dur %.2f env %d" % [float(c.get("dur", 0)), (c.get("env", PackedFloat32Array()) as PackedFloat32Array).size()])
	# 2) 預熱：引擎有開時，_ready 會在背景對用到的聲線呼叫 /initialize_speaker；等它做完再量第一次生成
	var tw := Time.get_ticks_msec()
	var want := 0
	for e in (v1.call("speakers_in_use") as Dictionary).values():
		want += (e as Array).size()
	while (v1.get("warm_ms") as Dictionary).size() < want and Time.get_ticks_msec() - tw < 90000:
		await process_frame
	_ok("預熱日文聲線（含情緒 style）%d 個" % want, want >= 3 and (v1.get("warm_ms") as Dictionary).size() == want, "各聲線預熱耗時 ms %s" % v1.get("warm_ms"))
	# 3) 執行期生成（日文 AivisSpeech）→ 自動存 user:// 快取；預熱後第一次生成應 < 3 s（交談最多只等 3 s）
	v1.set("lang", "ja")
	for h in ["marisa", "keine", "reimu"]:
		var text := "テストだぜ、%s番。" % [stamp + h]
		var t0 := Time.get_ticks_msec()
		v1.call("prefetch", h, text)
		while bool(v1.call("is_pending", h, text)) and Time.get_ticks_msec() - t0 < 30000:
			await process_frame
		var g: Dictionary = v1.call("lookup", h, text)
		var ms := Time.get_ticks_msec() - t0
		_ok("執行期生成 ja %s（預熱後 < 3000 ms）" % h, not g.is_empty() and ms < 3000, "%d ms, dur %.2f" % [ms, float(g.get("dur", 0))])
		if h == "marisa":
			var v2: Node = V.new()
			root.add_child(v2)
			await process_frame
			v2.set("lang", "ja")
			var hh: Dictionary = v2.call("lookup", h, text)
			_ok("重開後從 user://voice_cache 命中", not hh.is_empty() and int(v2.get("stats").hit_user) == 1, str(v2.get("stats")))
			v2.queue_free()
	# 英文：Kokoro（引擎有開才測得到生成；沒開時只顯示字幕）
	v1.set("lang", "en")
	var etext := "Runtime test number %s." % stamp
	var te := Time.get_ticks_msec()
	v1.call("prefetch", "marisa", etext, "surprised")
	while bool(v1.call("is_pending", "marisa", etext, "surprised")) and Time.get_ticks_msec() - te < 30000:
		await process_frame
	var ge: Dictionary = v1.call("lookup", "marisa", etext, "surprised")
	_ok("lang=en：Kokoro 執行期生成（情緒 surprised）", not ge.is_empty(), "%d ms, dur %.2f" % [Time.get_ticks_msec() - te, float(ge.get("dur", 0))])
	var social: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/npc_life/social.json"))
	var en_subs := 0
	for t in social.topics:
		if t.has("voice") and (t.voice as Dictionary).has("en") and (t.voice.en as Array).size() == (t.lines as Array).size():
			en_subs += 1
	_ok("英文台詞（social.json voice.en）與繁中逐句對應", en_subs >= 4, "%d 個主題" % en_subs)
	# 4) 引擎離線：生成失敗、lookup 回空（交談只顯示字幕，不卡）
	v1.set("lang", "ja")
	# 讓魔理沙實際用的引擎離線（聲線換過引擎也照樣測得到）
	var eng_name := String((v1.call("hero_voice", "marisa") as Dictionary).engine)
	(v1.get("cfg").engines[eng_name] as Dictionary)["url"] = "http://127.0.0.1:1"
	var tx := "オフラインテスト%s" % stamp
	var t1 := Time.get_ticks_msec()
	v1.call("prefetch", "marisa", tx)
	while bool(v1.call("is_pending", "marisa", tx)) and Time.get_ticks_msec() - t1 < 20000:
		await process_frame
	_ok("引擎離線 → 生成失敗、回空", (v1.call("lookup", "marisa", tx) as Dictionary).is_empty() and int(v1.get("stats").gen_fail) >= 1, "%d ms" % (Time.get_ticks_msec() - t1))
	print("STATS ", v1.get("stats"))
	quit(1 if fails > 0 else 0)
