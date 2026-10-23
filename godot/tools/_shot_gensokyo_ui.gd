extends SceneTree
## 幻想鄉 UI 第一階段驗收截圖（ART_REVIEW 用）＋版面量測。
##   <godot_console.exe> --path godot --script res://tools/_shot_gensokyo_ui.gd -- --res=1920x1080 --scale=1.0
## 不開 --headless（要真的畫出像素）。輸出 work/shots/gensokyo_ui/<res>_s<scale>/。
##
## 拍：a 探索 HUD（任務掛紙＋互動提示）  b 新委託橫幅  c 長對話（換行）  d 選項
##     e 日文長句  f 戰鬥 HUD（生命／軀幹／呼吸徽記＋快捷列，呼吸滿）  g 御札燃燒中段
## 並印出每個元件的 rect、文字是否被截斷（Label/RichText 的可見字數 vs 總字數）。

var OUT := "D:/神社/shrine/work/shots/gensokyo_ui/"

var _main: Node
var _dm: Node
var _qm: Node
var _sf: Node
var _fails := 0


func _init() -> void:
	_run.call_deferred()


func _settle(n: int) -> void:
	for i in n:
		_pin_cam()
		await physics_frame
		await process_frame


## 桌面上的真滑鼠會轉動被 capture 的鏡頭（上一輪就是這樣拍到整片天空）：每幀鎖回固定俯角。
var _cam_adapter: Node = null


func _pin_cam() -> void:
	if _main == null:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _cam_adapter == null or not is_instance_valid(_cam_adapter):
		for n in _main.player.find_children("*", "Node", true, false):
			var sc: Script = n.get_script()
			if sc != null and sc.resource_path.ends_with("player_camera_adapter.gd"):
				_cam_adapter = n
				break
	if _cam_adapter != null:
		_cam_adapter.set("_target_pitch", -0.30)
		_cam_adapter.set("_current_pitch", -0.30)


func _shot(name: String, pre := 30) -> void:
	await _settle(pre)
	await RenderingServer.frame_post_draw
	await process_frame
	var cam := root.get_viewport().get_camera_3d()
	if cam != null:
		print("[CAM] %s cam=%s pos=%s fwd=%s player=%s" % [name, cam.get_path(), str(cam.global_position.snapped(Vector3.ONE * 0.01)),
			str((-cam.global_basis.z).snapped(Vector3.ONE * 0.01)), str(_main.player.global_position.snapped(Vector3.ONE * 0.01))])
	DirAccess.make_dir_recursive_absolute(OUT)
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(OUT + name + ".png")
	print("[SHOT] %s  %dx%d" % [name, img.get_width(), img.get_height()])


func _check(label: String, ok: bool) -> void:
	print("[UI] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1


func _vp() -> Rect2:
	return Rect2(Vector2.ZERO, root.get_viewport().get_visible_rect().size)


func _inside(r: Rect2, tag: String) -> void:
	var vp := _vp()
	_check("%s 在畫面內 %s ⊂ %s" % [tag, str(r), str(vp.size)], vp.grow(1.0).encloses(r))


func _run() -> void:
	var res := "1920x1080"
	var ui_scale := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--res="):
			res = a.substr(6)
		elif a.begins_with("--scale="):
			ui_scale = float(a.substr(8))
	var wh := res.split("x")
	var W := int(wh[0])
	var H := int(wh[1])
	root.get_window().size = Vector2i(W, H)
	root.get_window().content_scale_size = Vector2i.ZERO
	OUT += "%s_s%s/" % [res, str(ui_scale)]
	var st: GensokyoStyle = GensokyoStyle.current()
	st.ui_scale = ui_scale
	await _settle(4)
	print("[GEO] viewport=%s ui_scale=%.2f → k=%.3f" % [str(_vp().size), ui_scale, ui_scale * H / 1080.0])

	_dm = root.get_node("/root/DialogueManager")
	_qm = root.get_node("/root/QuestManager")
	_sf = root.get_node("/root/StoryFlags")
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _settle(6)
	var fade := _main.get_node_or_null("OpeningFade")
	if fade != null:
		fade.queue_free()
	# 開場運鏡（CinematicOpeningCamera 仰望天空）會一直佔著 current：UI 驗收直接交回遊戲鏡頭。
	# 不 free（main.gd 的開場 lambda 抓著它），只把 current 交回遊戲鏡頭
	var gcam := _main.player.find_child("Camera3D", true, false) as Camera3D
	if gcam != null:
		gcam.current = true
	_main.player.set("input_locked", false)
	_sf.call("set_flag", "opening_fade_active", false)
	var dn := root.get_node_or_null("/root/DayNight")
	if dn != null and dn.has_method("unlock_time"):
		dn.call("unlock_time", "opening_cutscene")
	var dui := root.find_child("DialogueUI", true, false)
	dui.set_process_unhandled_input(false)
	dui.set("typewriter_cps", 0.0)
	var day := root.get_node_or_null("/root/DayNight")
	if day != null:
		day.set("flowing", false)
		day.call("set_hour", 11.0)
	_main.load_map("slice", "trail")
	await _settle(90)
	while _dm.call("is_active"):
		_dm.call("advance", 0)
		await _settle(2)

	# --- a：探索（任務掛紙 + 互動提示）---
	_qm.call("reset")
	_sf.call("reset")
	_qm.call("start_quest", "MQ04")
	await _settle(260)   # 橫幅走完、掛紙退到 idle
	var prompt: Label = _main.interaction_prompt
	prompt.text = "博麗神社\n[E] 拜訪"
	prompt.visible = true
	await _settle(20)
	var tr := root.find_child("Tracker", true, false) as GensokyoQuestTracker
	_inside(tr.paper.get_global_rect(), "任務掛紙")
	_check("任務文字不截斷（行數=%d）" % tr.objective.get_line_count(), tr.objective.get_visible_line_count() >= tr.objective.get_line_count())
	_inside(prompt.get_global_rect(), "互動提示")
	await _shot("a_explore")
	# 長目標（兩行）
	tr.show_objective("將寺子屋借來的書送到鈴奈庵，交給本居小鈴，並向慧音老師回報", true)
	await _settle(20)
	_check("長任務自動換行（%d 行）且不截斷" % tr.objective.get_line_count(),
		tr.objective.get_line_count() >= 2 and tr.objective.get_visible_line_count() >= tr.objective.get_line_count())
	_inside(tr.paper.get_global_rect(), "任務掛紙（兩行）")
	await _shot("a2_quest_long")
	prompt.visible = false

	# --- b：新委託橫幅 ---
	_qm.call("start_quest", "MQ07")
	await _settle(14)
	await _shot("b_quest_new_banner")
	await _settle(240)

	# --- c：長對話 ---
	_dm.call("start", "kosuzu_suzunaan")
	await _settle(10)
	var box := dui.get_node("Box") as GensokyoDialogueBox
	var txt := box.text
	txt.text = "「可以，不過那批還在後頭待整理的箱子裡，現在不在手邊。下次來，我們先從地名找起。還書已經記好了，你可以向慧音老師交代。這一段再加長一點，確認三行時框會長高，而不是把字擠出紙外。」"
	await _settle(40)
	var pr := box.panel.get_global_rect()
	print("[GEO] dialogue panel=%s  寬 %.1f%% vp  text_lines=%d" % [str(pr), 100.0 * pr.size.x / _vp().size.x, txt.get_line_count()])
	_inside(pr, "對話框")
	_check("對話寬 60–65%% viewport（%.1f%%）" % (100.0 * pr.size.x / _vp().size.x), absf(pr.size.x / _vp().size.x - 0.62) < 0.031)
	_check("長對話自動換行（%d 行）且全部可見" % txt.get_line_count(), txt.get_line_count() >= 2 and txt.get_visible_line_count() >= txt.get_line_count())
	_check("文字區在框內", pr.encloses(txt.get_global_rect()))
	_inside(box.nameplate.get_global_rect(), "名牌")
	_check("名牌壓在框上緣（重疊）", box.nameplate.get_global_rect().intersects(pr))
	await _shot("c_dialogue_long")

	# --- e：日文長句 ---
	box.set_speaker("本居小鈴", "surprised")
	txt.text = "「この本、外の世界から流れてきたものかもしれません。読めない字がいくつかあって……霊夢さんに聞いてみてはどうでしょう？」"
	await _settle(30)
	_check("日文換行且全部可見（%d 行）" % txt.get_line_count(), txt.get_visible_line_count() >= txt.get_line_count())
	_check("日文文字區在框內", box.panel.get_global_rect().encloses(txt.get_global_rect()))
	await _shot("e_dialogue_japanese")
	while _dm.call("is_active"):
		_dm.call("advance", 0)
		await _settle(2)
	await _settle(10)

	# --- d：選項 ---
	_dm.call("start", "yoriichi_wounded_yokai")
	await _settle(10)
	for i in 14:
		if box.choices.get_child_count() > 0:
			break
		_dm.call("advance")
		await _settle(4)
	await _settle(20)
	_check("選項出現（%d 個）" % box.choices.get_child_count(), box.choices.get_child_count() > 0)
	if box.choices.get_child_count() > 0:
		_check("第一個選項是 GensokyoButton 且選中", box.choices.get_child(0) is GensokyoButton and (box.choices.get_child(0) as GensokyoButton).selected)
		_inside(box.panel.get_global_rect(), "對話框（選項）")
	await _shot("d_dialogue_choices")
	while _dm.call("is_active"):
		_dm.call("advance", 0)
		await _settle(2)
	await _settle(10)

	# --- f：戰鬥 HUD ---
	var cr := root.find_child("CombatRuntime", true, false)
	var hud: Node = cr.get("hud") if cr != null else null
	_check("CombatHUD 存在", hud != null)
	if hud != null:
		var player: Node = _main.player
		player.set("sun_breath_gauge", float(player.get("sun_breath_max")))
		hud.set_player_breath(1.0, 1.0)
		hud.set_player_health(62.0, 100.0)
		hud.set_player_posture(45.0, 100.0)
		if player.has_method("request_draw"):
			player.set("input_locked", false)
			player.request_draw()
			for i in 90:
				if int(player.get("sword_state")) == 2:
					break
				await physics_frame
		cr.call("mark_combat")
		await _settle(60)
		var hb := hud.get_node("Root/Hotbar") as GensokyoHotbar
		_inside(hb.get_global_rect(), "快捷列")
		print("[GEO] hotbar=%s slots=%s" % [str(hb.get_global_rect()), str(hb.slot_states())])
		_check("快捷列 C 在呼吸滿＋出鞘時亮起", hb.slot_states()[2].selected)
		_inside((hud.get_node("Root/PlayerBars") as Control).get_global_rect(), "生命列")
		await _shot("f_combat_hud")
		hud.set_player_breath(0.4, 1.0)
		hud.set_player_health(22.0, 100.0)
		hud.set_player_posture(92.0, 100.0)
		player.set("sun_breath_gauge", 40.0)
		await _settle(20)
		await _shot("f2_combat_hud_low")

	# --- g：任務完成（御札燃燒中段）---
	print("[GEO] before complete: active=%s MQ07 active=%s" % [_qm.call("get_active_quest"), str(_qm.call("is_active", "MQ07"))])
	if not bool(_qm.call("is_active", "MQ07")):
		_qm.call("start_quest", "MQ07")
		await _settle(300)
	_qm.call("complete_quest", "MQ07")
	var trk := root.find_child("Tracker", true, false) as GensokyoQuestTracker
	var t0 := Time.get_ticks_msec()
	# 等到真的開始燒（burn 過半）才拍，不靠猜幀數
	while float(trk.banner.get("burn")) < 0.45 and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	print("[GEO] banner burn=%.2f visible=%s after %d ms" % [float(trk.banner.get("burn")), str(trk.banner.visible), Time.get_ticks_msec() - t0])
	_check("完成御札有燃燒", float(trk.banner.get("burn")) >= 0.45 and trk.banner.visible)
	await _shot("g_quest_complete_burning", 0)

	print("[UI] failures=%d" % _fails)
	quit(_fails)
