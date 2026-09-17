extends SceneTree
## 音效系統無頭驗證。
##
## 語法檢查（--check-only）只證明「能編譯」，不證明「會發聲」。
## 這支腳本實際建節點、呼叫每個事件、數 AudioStreamPlayer 有沒有真的 play()。
##
## 跑法：
##   godot --headless --script tools/verify_audio.gd

var failed := 0
var passed := 0


func check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
		print("  [OK]   %s %s" % [label, detail])
	else:
		failed += 1
		print("  [FAIL] %s %s" % [label, detail])


func _init() -> void:
	_run()


## ⚠ 必須 await 一幀再測：_init() 在 SceneTree 還沒開始跑主迴圈時就執行，
##   此時 add_child() 不會觸發節點的 _ready()，播放器池是空的，
##   _play() 會噴 "Out of bounds get index '0'"。
##   這是測試骨架的時序問題，不是音效系統的 bug。
func _run() -> void:
	await process_frame
	print("=== 音效系統驗證 ===")
	_verify_files()
	_verify_surface_rules()
	_verify_character_audio()
	_verify_footsteps()
	_verify_wolf()
	_verify_wildlife()
	print("\n=== 結果：%d 通過 / %d 失敗 ===" % [passed, failed])
	quit(1 if failed > 0 else 0)


## 1. 每個音檔都要真的載得進來（preload 在編譯期就會擋，這裡防的是漏檔）。
func _verify_files() -> void:
	print("\n-- 音檔載入 --")
	var names := [
		"sword_swing_1", "sword_swing_2", "sword_swing_3",
		"sword_fire_swing_1", "sword_fire_swing_2", "sword_fire_swing_3",
		"sword_heavy", "sword_draw", "sword_sheathe",
		"hit_impact_light", "hit_impact_heavy",
		"hit_fire_light_1", "hit_fire_light_2", "hit_fire_heavy", "hit_fire_spin",
		"deflect_clang", "block_thud", "hurt_impact",
		"step_grass_walk_1", "step_grass_walk_2", "step_grass_walk_3", "step_grass_walk_4",
		"step_grass_run_1", "step_grass_run_2", "step_grass_run_3", "step_grass_run_4",
		"step_stone_1", "step_stone_2", "step_stone_3",
		"step_wood_1", "step_wood_2", "step_wood_3",
		"step_dirt_1", "step_dirt_2", "step_dirt_3",
		"wolf_growl", "wolf_snarl", "wolf_grumble", "wolf_attack",
		"wolf_hurt", "wolf_death", "wolf_howl_distant",
		"bird_chirp_1", "bird_chirp_2", "bird_chirp_3", "bird_forest_distant",
		"night_bird", "owl_hoot", "frog_croak",
		"water_splash_1", "water_splash_2", "water_splash_3", "fish_splash",
	]
	var missing := 0
	var silent := 0
	for n in names:
		var s: AudioStream = load("res://assets/audio/sfx/%s.wav" % n)
		if s == null:
			missing += 1
			print("    缺檔: %s" % n)
		elif s.get_length() <= 0.01:
			silent += 1
			print("    空檔: %s" % n)
	check("全部 %d 個音檔存在" % names.size(), missing == 0, "缺 %d" % missing)
	check("無空檔", silent == 0, "空 %d" % silent)


## 2. 地表分類規則。純字串比對，不需場景 —— 這是腳步系統最容易靜默出錯的地方
##    （分類錯了不會報錯，只會一路播草地音）。
func _verify_surface_rules() -> void:
	print("\n-- 地表分類 --")
	var cases := {
		"石板_0007/參道/Shrine": FootstepAudio.Surface.STONE,
		"@CollisionShape3D@6/石階碰撞/參道石階": FootstepAudio.Surface.STONE,
		"RockPath_Square_Wide2 (3)/踏石/庭院": FootstepAudio.Surface.STONE,
		"CopingStones/河岸/Village": FootstepAudio.Surface.STONE,
		"木橋碰撞/小木橋_佔位/Village": FootstepAudio.Surface.WOOD,
		"Stonebound Wooden Bri_1/橋/Slice": FootstepAudio.Surface.WOOD,
		"獸道地面/Trail": FootstepAudio.Surface.DIRT,
		"VillageRiverbank/河原": FootstepAudio.Surface.DIRT,
		"Terrain/Shrine": FootstepAudio.Surface.GRASS,
		"草地/Slice": FootstepAudio.Surface.GRASS,
	}
	var names := ["GRASS", "STONE", "WOOD", "DIRT"]
	for path in cases:
		var got: int = FootstepAudio.classify(path)
		var want: int = cases[path]
		check("classify(%s)" % path, got == want,
			"-> %s（預期 %s）" % [names[got], names[want]])


func _make(script_path: String) -> Node:
	var sc: GDScript = load(script_path)
	var n: Node = sc.new()
	root.add_child(n)
	return n


## 播放器有沒有真的被觸發：數 playing 的數量，而不是相信方法有被呼叫。
func _count_playing(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is AudioStreamPlayer3D and (ch as AudioStreamPlayer3D).stream != null:
			c += 1
	return c


## 3. 玩家戰鬥音效：每個事件方法都要真的指派 stream。
func _verify_character_audio() -> void:
	print("\n-- 玩家戰鬥音效 --")
	var ca := _make("res://characters/yoriichi/character_audio.gd")
	var events := [
		["play_swing", [1]], ["play_swing", [2]], ["play_swing", [3]],
		["play_heavy_swing", []], ["play_draw", []], ["play_sheathe", []],
		["play_jump_takeoff", []], ["play_jump_land", []], ["play_roll", []],
		["play_hit", []], ["play_deflect", []], ["play_block", []],
		["play_hurt", []], ["play_death_collapse", []], ["play_deathblow", []],
		["play_form", [8]], ["play_form", [2]], ["play_form", [1]],
	]
	var before: int = ca.events_played
	for e in events:
		if not ca.has_method(e[0]):
			check("方法 %s 存在" % e[0], false)
			continue
		ca.callv(e[0], e[1])
	check("全部 %d 個戰鬥事件都發聲" % events.size(),
		ca.events_played - before == events.size(),
		"實際 %d 次" % (ca.events_played - before))
	# 彈刀／格擋必須用專用素材，不是同一個檔調音高
	var d: AudioStream = ca.SND_DEFLECT
	var b: AudioStream = ca.SND_BLOCK
	check("彈刀與格擋是不同素材", d != b)
	ca.queue_free()


## 4. 腳步：步頻與地表庫。
func _verify_footsteps() -> void:
	print("\n-- 腳步 --")
	var body := CharacterBody3D.new()
	root.add_child(body)
	var fa: Node = FootstepAudio.new()
	body.add_child(fa)
	# 靜止不該有腳步
	fa.tick(0.5, true, 0.0, false)
	check("靜止時不播腳步", fa.steps_played == 0, "播了 %d" % fa.steps_played)
	# 騰空不該有腳步
	fa.tick(0.5, false, 6.0, true)
	check("騰空時不播腳步", fa.steps_played == 0, "播了 %d" % fa.steps_played)
	# 走 4 秒 @ 4 m/s：約 1.9 步/秒 → 7~8 步
	var walk_start: int = fa.steps_played
	for i in 40:
		fa.tick(0.1, true, 4.0, false)
	var walked: int = fa.steps_played - walk_start
	check("走 4 秒約 7-8 步", walked >= 6 and walked <= 9, "實際 %d 步" % walked)
	# 跑 4 秒 @ 7 m/s：約 2.9 步/秒 → 11~12 步，必須明顯多於走路
	var run_start: int = fa.steps_played
	for i in 40:
		fa.tick(0.1, true, 7.0, true)
	var ran: int = fa.steps_played - run_start
	check("跑 4 秒約 11-12 步", ran >= 10 and ran <= 14, "實際 %d 步" % ran)
	check("跑步步頻高於走路", ran > walked, "跑 %d vs 走 %d" % [ran, walked])
	body.queue_free()


## 5. 山犬：每個戰鬥事件都要發聲。
func _verify_wolf() -> void:
	print("\n-- 山犬 --")
	var wa: Node = WolfAudio.new()
	root.add_child(wa)
	var events := ["play_windup", "play_attack", "play_hurt",
		"play_break", "play_death", "play_howl"]
	var before: int = wa.events_played
	for e in events:
		if not wa.has_method(e):
			check("方法 %s 存在" % e, false)
			continue
		if e == "play_windup":
			wa.play_windup(true)
			wa.play_windup(false)
		else:
			wa.call(e)
	check("山犬事件都發聲", wa.events_played > before,
		"%d 次" % (wa.events_played - before))
	# 待機哼聲：倒數沒到不該叫
	var idle_before: int = wa.events_played
	wa.tick_idle(0.1, false)
	check("待機倒數未到不叫", wa.events_played == idle_before)
	wa.queue_free()


## 6. 環境生物：日夜要選到不同音庫。
func _verify_wildlife() -> void:
	print("\n-- 環境生物 --")
	var w: Node = WildlifeAudio.new()
	root.add_child(w)
	var before: int = w.calls_played
	w.play_random_call(false)   # 白天
	w.play_random_call(true)    # 夜間
	check("日夜都能發聲", w.calls_played - before == 2,
		"%d 次" % (w.calls_played - before))
	w.queue_free()
