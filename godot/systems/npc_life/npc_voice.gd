extends Node
## NPC 語音（NpcLife 的子節點）：依 data/npc_life/voices.json 替每名 HERO 指定聲線，交談台詞配本機 TTS 語音。
##   查快取順序：記憶體 → res://assets/voice/voice_index.json（離線烘焙、隨遊戲出貨）→ user://voice_cache（執行期生成過的）
##   都沒有且本機引擎有開（開發機）→ HTTP 生成（AivisSpeech／VOICEVOX 相容 API：audio_query＋synthesis），
##   存進 user://voice_cache 並記錄，之後自動走快取。引擎沒開 → 回空，交談照常只顯示字幕。
##   引擎有開時，啟動後在背景預熱目前語言用到的聲線（/initialize_speaker），避免第一句等模型載入（AivisSpeech 每個模型約 7 s）。
##   不呼叫任何付費／雲端語音服務；遊戲本身不啟動也不重啟引擎。
## 嘴型：每段語音附 30 Hz 音量包絡（env），actor 用它驅動嘴部開合。

signal clip_ready(key: String)

const VOICES_PATH := "res://data/npc_life/voices.json"
const INDEX_PATH := "res://assets/voice/voice_index.json"
const USER_DIR := "user://voice_cache"
const ENV_HZ := 30.0

var cfg := {}
var lang := "ja"
var _index := {}          # key -> {file, dur, env}
var _mem := {}            # key -> {stream, dur, env}
var _pending := {}        # key -> true
var _engine_ok := {}      # engine -> bool（啟動時探測一次）
var stats := {"hit_res": 0, "hit_user": 0, "hit_mem": 0, "gen": 0, "gen_fail": 0, "gen_ms": []}


func _ready() -> void:
	cfg = _json(VOICES_PATH)
	lang = String(cfg.get("lang", "ja"))
	var env_lang := OS.get_environment("NPC_VOICE_LANG")
	if env_lang != "":
		lang = env_lang
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--voice_lang="):
			lang = a.substr(13)
	_index = _json(INDEX_PATH).get("clips", {})
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var ui := _json(USER_DIR + "/index.json")
	for k in ui.get("clips", {}):
		if not _index.has(k):
			_index[k] = ui.clips[k]
	if bool(cfg.get("warmup", true)):
		_warmup.call_deferred()


## 目前語言用到的聲線（引擎 → 聲線 id 清單）
func speakers_in_use() -> Dictionary:
	var out := {}
	for h in cfg.get("heroes", {}):
		var v: Dictionary = cfg.heroes[h].get(lang, {})
		if v.is_empty():
			continue
		var e := String(v.engine)
		if not out.has(e):
			out[e] = []
		if not (out[e] as Array).has(int(v.speaker)):
			(out[e] as Array).append(int(v.speaker))
	return out


## 預熱：引擎有開才做（沒開就安靜跳過）；只在背景送請求，不擋遊戲
var warm_ms := {}          # 聲線 id -> 預熱耗時（ms）
func _warmup() -> void:
	var use := speakers_in_use()
	for e in use:
		var eng: Dictionary = cfg.get("engines", {}).get(e, {})
		if eng.is_empty():
			continue
		# 引擎剛啟動時可能還沒回應：每 5 s 再試，最多 6 次（不吃 30 s 的離線快取）
		var up := false
		for attempt in 6:
			_engine_ok.erase(String(eng.url))
			if await _engine_alive(e, eng):
				up = true
				break
			await get_tree().create_timer(5.0).timeout
		if not up:
			continue
		for spk in use[e]:
			var t0 := Time.get_ticks_msec()
			await _http(String(eng.url) + "/initialize_speaker?speaker=%d&skip_reinit=true" % spk, HTTPClient.METHOD_POST, "", PackedStringArray(), 60.0, true)
			warm_ms[spk] = Time.get_ticks_msec() - t0


func hero_voice(hero: String) -> Dictionary:
	return cfg.get("heroes", {}).get(hero, {}).get(lang, {})


func has_voice(hero: String) -> bool:
	return not hero_voice(hero).is_empty()


## 快取鍵（與 tools/npc_voice/bake_voice_cache.py 的 clip_key 必須一致）
static func clip_key(hero: String, lng: String, v: Dictionary, text: String) -> String:
	var spk: Variant = v.get("speaker", "")
	var spk_s := str(int(spk)) if (spk is float or spk is int) else str(spk)
	var sig := "%s|%s|%s|%s|%.2f|%s" % [hero, lng, v.get("engine", ""), spk_s, float(v.get("speed", 1.0)), text]
	return sig.sha1_text().substr(0, 16)


## 已有就回 {stream, dur, env}；沒有回 {}
func lookup(hero: String, text: String) -> Dictionary:
	var v := hero_voice(hero)
	if v.is_empty() or text == "":
		return {}
	var key := clip_key(hero, lang, v, text)
	if _mem.has(key):
		stats.hit_mem += 1
		return _mem[key]
	if not _index.has(key):
		return {}
	var e: Dictionary = _index[key]
	var path := String(e.file)
	var stream: AudioStream = null
	if path.begins_with("res://"):
		stream = load(path) as AudioStream
		stats.hit_res += 1
	else:
		stream = AudioStreamWAV.load_from_file(path)
		stats.hit_user += 1
	if stream == null:
		return {}
	var c := {"stream": stream, "dur": float(e.dur), "env": PackedFloat32Array(e.get("env", [])), "key": key}
	_mem[key] = c
	return c


## 預先生成（交談一開始就呼叫，等走到位時通常已經好了）
func prefetch(hero: String, text: String) -> void:
	var v := hero_voice(hero)
	if v.is_empty() or text == "":
		return
	var key := clip_key(hero, lang, v, text)
	if _mem.has(key) or _index.has(key) or _pending.has(key):
		return
	var eng: Dictionary = cfg.get("engines", {}).get(String(v.engine), {})
	if eng.is_empty():
		return
	_pending[key] = true
	_generate(key, hero, v, eng, text)


func is_pending(hero: String, text: String) -> bool:
	var v := hero_voice(hero)
	return not v.is_empty() and _pending.has(clip_key(hero, lang, v, text))


## 引擎是否在線：1.5 s 探測一次，結果記 30 s（沒開引擎時不要每句都卡在連線逾時）
func _engine_alive(name: String, eng: Dictionary) -> bool:
	var ck := String(eng.url)       # 以網址記（設定改了網址就重新探測）
	var rec: Dictionary = _engine_ok.get(ck, {})
	if not rec.is_empty() and Time.get_ticks_msec() - int(rec.t) < 30000:
		return bool(rec.ok)
	var probe := String(eng.url) + "/version"
	var r := await _http(probe, HTTPClient.METHOD_GET, "", PackedStringArray(), 1.5)
	var ok := not r.is_empty()
	_engine_ok[ck] = {"ok": ok, "t": Time.get_ticks_msec(), "engine": name}
	return ok


func _generate(key: String, hero: String, v: Dictionary, eng: Dictionary, text: String) -> void:
	var t0 := Time.get_ticks_msec()
	if not await _engine_alive(String(v.engine), eng):
		_gen_fail(key)
		return
	var url := String(eng.url)
	var q := await _http(url + "/audio_query?speaker=%d&text=%s" % [int(v.speaker), text.uri_encode()], HTTPClient.METHOD_POST, "", PackedStringArray(), 15.0)
	if q.is_empty():
		_gen_fail(key)
		return
	var query: Variant = JSON.parse_string(q.get_string_from_utf8())
	if not (query is Dictionary):
		_gen_fail(key)
		return
	if v.has("speed"): query["speedScale"] = float(v.speed)
	if v.has("pitch"): query["pitchScale"] = float(v.pitch)
	if v.has("intonation"): query["intonationScale"] = float(v.intonation)
	var wav := await _http(url + "/synthesis?speaker=%d" % int(v.speaker), HTTPClient.METHOD_POST, JSON.stringify(query), PackedStringArray(["Content-Type: application/json"]))
	if wav.size() < 64:
		_gen_fail(key)
		return
	wav = fix_wav(wav)
	var path := "%s/%s.wav" % [USER_DIR, key]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(wav)
	f.close()
	var stream := AudioStreamWAV.load_from_buffer(wav)
	if stream == null:
		_gen_fail(key)
		return
	var env := envelope_from_wav(wav)
	var dur := stream.get_length()
	_mem[key] = {"stream": stream, "dur": dur, "env": env, "key": key}
	_index[key] = {"file": path, "dur": dur, "env": Array(env), "hero": hero, "lang": lang, "text": text}
	_save_user_index()
	_pending.erase(key)
	stats.gen += 1
	(stats.gen_ms as Array).append(Time.get_ticks_msec() - t0)
	clip_ready.emit(key)


func _gen_fail(key: String) -> void:
	_pending.erase(key)
	stats.gen_fail += 1


func _http(url: String, method: int, body: String, headers: PackedStringArray, timeout := 60.0, accept_204 := false) -> PackedByteArray:
	var h := HTTPRequest.new()
	h.timeout = timeout
	add_child(h)
	var err := h.request(url, headers, method, body)
	if err != OK:
		h.queue_free()
		return PackedByteArray()
	var res: Array = await h.request_completed
	h.queue_free()
	if accept_204 and int(res[0]) == HTTPRequest.RESULT_SUCCESS and int(res[1]) == 204:
		return PackedByteArray([1])
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS or int(res[1]) != 200:
		return PackedByteArray()
	return res[3]


func _save_user_index() -> void:
	var out := {}
	for k in _index:
		if String(_index[k].file).begins_with("user://"):
			out[k] = _index[k]
	var f := FileAccess.open(USER_DIR + "/index.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"clips": out}))
	f.close()


## 串流式 WAV 的 RIFF／data 長度可能是 0xFFFFFFFF（Godot 讀不了）：改成實際長度
static func fix_wav(b: PackedByteArray) -> PackedByteArray:
	if b.size() < 44 or b.slice(0, 4).get_string_from_ascii() != "RIFF":
		return b
	b.encode_u32(4, b.size() - 8)
	var i := 12
	while i + 8 <= b.size():
		var cid := b.slice(i, i + 4).get_string_from_ascii()
		var size := b.decode_u32(i + 4)
		if cid == "data":
			b.encode_u32(i + 4, b.size() - i - 8)
			break
		i += 8 + size + (size & 1)
	return b


## 16-bit PCM WAV → 30 Hz 音量包絡（0..1，已正規化）
static func envelope_from_wav(b: PackedByteArray) -> PackedFloat32Array:
	var env := PackedFloat32Array()
	var i := 12
	var ch := 1
	var sr := 24000
	var bits := 16
	var data_at := -1
	var data_len := 0
	while i + 8 <= b.size():
		var cid := b.slice(i, i + 4).get_string_from_ascii()
		var size := b.decode_u32(i + 4)
		if cid == "fmt ":
			ch = b.decode_u16(i + 10)
			sr = b.decode_u32(i + 12)
			bits = b.decode_u16(i + 22)
		elif cid == "data":
			data_at = i + 8
			data_len = mini(size, b.size() - data_at)
			break
		i += 8 + size + (size & 1)
	if data_at < 0 or bits != 16:
		return env
	var frame := int(sr / ENV_HZ)
	var n := data_len / (2 * ch)
	var peak := 1e-6
	var k := 0
	while k < n:
		var s := 0.0
		var m := mini(frame, n - k)
		for j in range(0, m, 4):
			var v := b.decode_s16(data_at + (k + j) * 2 * ch) / 32768.0
			s += v * v
		var rms := sqrt(s / maxf(m / 4.0, 1.0))
		env.append(rms)
		peak = maxf(peak, rms)
		k += frame
	for q in env.size():
		env[q] = clampf(env[q] / peak, 0.0, 1.0)
	return env


func _json(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	return v if v is Dictionary else {}
