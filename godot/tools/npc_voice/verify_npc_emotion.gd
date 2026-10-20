extends SceneTree
## NPC 情緒對話驗證（不需引擎；要先跑 bake_voice_cache.py）
## godot --headless --path godot -s res://tools/npc_voice/verify_npc_emotion.gd
##  1 同一件事（魔理沙說撿到怪東西）→ 不同 HERO 反應不同（情緒與台詞）
##  2 世界狀態改變反應（有異變時靈夢認真、慧音驚訝）；心情改變反應機率
##  3 台本解析：反應行換成聽者自己的台詞、beats（情緒／停頓／打斷）帶進台本
##  4 快取鍵：同句不同情緒鍵不同；改任一參數鍵就變；遊戲算的鍵＝烘焙工具算的鍵（全部索引重算比對）
##  5 三組測試對話（ja／en）每一行、每個可能的反應都有快取音檔
const D := preload("res://systems/npc_life/npc_life_director.gd")
const V := preload("res://systems/npc_life/npc_voice.gd")
var fails := 0

func _ok(name: String, ok: bool, detail := "") -> void:
	if not ok: fails += 1
	print("[%s] %s %s" % ["PASS" if ok else "FAIL", name, detail])

func _json(p: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(p))

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var heroes := _json("res://data/npc_life/heroes.json")
	var social := _json("res://data/npc_life/social.json")
	var dir: Node = D.new()
	var defs := {}
	for h in heroes:
		if not String(h).begins_with("_"):
			defs[h] = heroes[h]
	dir.set("defs", defs)
	dir.set("world", {})
	dir.set("mood", {})
	dir.set("clock", 1000.0)
	# 1 同刺激不同反應
	var got := {}
	for h in ["reimu", "keine", "kosuzu", "akyuu"]:
		var r: Dictionary = dir.call("pick_reaction", h, "strange_find", "marisa", false)
		got[h] = "%s「%s」" % [r.emo, r.ja]
	var emos := {}
	for h in got: emos[got[h].split("「")[0]] = true
	_ok("同一件事、四名 HERO 反應不同", emos.size() >= 3, str(got))
	# 2 世界狀態
	dir.set("world", {"anomaly_south_forest": 1})
	var rw: Dictionary = dir.call("pick_reaction", "reimu", "strange_find", "marisa", false)
	var kw: Dictionary = dir.call("pick_reaction", "keine", "strange_find", "marisa", false)
	_ok("有異變時：靈夢轉為認真、慧音驚訝", rw.emo == "serious" and kw.emo == "surprised", "靈夢 %s「%s」／慧音 %s「%s」" % [rw.emo, rw.ja, kw.emo, kw.ja])
	dir.set("world", {})
	# 心情：靈夢剛嘆過氣 → 「唉……又來了」機率上升
	var cnt := func(md: Dictionary) -> float:
		dir.set("mood", md)
		var n := 0
		for i in 3000:
			if (dir.call("pick_reaction", "reimu", "strange_find", "marisa") as Dictionary).emo == "sigh":
				n += 1
		return n / 3000.0
	var p0: float = cnt.call({})
	var p1: float = cnt.call({"reimu": {"emo": "sigh", "t": 990.0}})
	_ok("心情影響反應（靈夢剛嘆氣 → 再嘆氣機率上升）", p1 > p0 + 0.1, "%.2f → %.2f" % [p0, p1])
	dir.set("mood", {})
	# 3 台本解析
	var topics := {}
	for t in social.topics: topics[t.id] = t
	var sc: Array = dir.call("resolve_script", topics["emo_news_mk"], "marisa", "keine")
	_ok("台本：反應行換成聽者（慧音）自己的台詞", sc.size() == 6 and sc[1].spk == "keine" and String(sc[1].react) == "strange_find" and String(sc[1].ja) != "", "%s「%s」" % [sc[1].emo, sc[1].ja])
	_ok("台本：打斷與停頓帶進台本", float(sc[0].get("cut", 0)) == 0.8 and float(sc[4].get("pause", 0)) == 0.4 and sc[3].emo == "surprised", "cut=%s pause=%s emo=%s" % [sc[0].get("cut"), sc[4].get("pause"), sc[3].emo])
	# 4 快取鍵
	var v: Node = V.new()
	root.add_child(v)
	await process_frame
	v.set("lang", "ja")
	var t := "テストだぜ。"
	var k_n := V.clip_key("marisa", "ja", v.call("hero_voice", "marisa", "neutral"), t)
	var k_s := V.clip_key("marisa", "ja", v.call("hero_voice", "marisa", "surprised"), t)
	var hv: Dictionary = v.call("hero_voice", "marisa", "surprised")
	hv["intonation"] = float(hv.get("intonation", 1.0)) + 0.1
	var k_s2 := V.clip_key("marisa", "ja", hv, t)
	_ok("快取鍵：情緒不同鍵不同、改參數鍵就變", k_n != k_s and k_s != k_s2, "%s／%s／%s" % [k_n, k_s, k_s2])
	var idx: Dictionary = _json("res://assets/voice/voice_index.json").clips
	var bad := []
	for key in idx:
		var c: Dictionary = idx[key]
		v.set("lang", String(c.lang))
		var kk := V.clip_key(String(c.hero), String(c.lang), v.call("hero_voice", String(c.hero), String(c.get("emo", "neutral"))), String(c.text))
		if kk != key:
			bad.append("%s≠%s %s" % [kk, key, c.text])
	_ok("遊戲算的快取鍵＝烘焙工具算的鍵（全部 %d 筆）" % idx.size(), bad.is_empty(), str(bad.slice(0, 3)))
	# 5 三組測試每行都有快取（含所有可能的反應）
	var miss := []
	var n := 0
	for lang in ["ja", "en"]:
		v.set("lang", lang)
		for tid in ["emo_daily_mk", "emo_news_mk", "emo_news_mr", "emo_banter_rm"]:
			var tp: Dictionary = topics[tid]
			for i in tp.lines.size():
				var spk := String(tp.lines[i][0])
				var cands: Array = []
				if String(tp.lines[i][1]).begins_with("@"):
					for r in defs[spk].speech.reactions[String(tp.lines[i][1]).substr(1)]:
						cands.append([r[lang], r.emo])
				else:
					cands.append([tp.voice[lang][i], tp.beats[i].get("emo", "neutral")])
				for cd in cands:
					n += 1
					if (v.call("lookup", spk, cd[0], cd[1]) as Dictionary).is_empty():
						miss.append("%s %s %s" % [lang, spk, cd[0]])
	_ok("三組測試（ja／en）每一行與每個可能反應都有快取", miss.is_empty(), "%d 句，缺 %s" % [n, miss.slice(0, 4)])
	dir.free()
	quit(1 if fails > 0 else 0)
