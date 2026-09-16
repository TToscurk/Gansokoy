extends SceneTree
## main.tscn 實際開機後，戰鬥層有沒有真的掛上去。
##
## 執行：
##   godot --headless --path godot -s tools/verify_combat_runtime.gd
##
## 這支驗的是「接線在真實開機路徑上成立」——
## CombatRuntime 生出來了嗎、HUD 在不在、Tab 有沒有註冊、玩家數值有沒有流到 HUD。

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
	print("=== 戰鬥層開機接線驗證 ===")
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		check("載入 main.tscn", false)
		quit(1)
		return
	var main: Node = scene.instantiate()
	get_root().add_child(main)
	# 載圖 + _ready 鏈需要幾幀才走完
	for i in 12:
		await process_frame

	var combat: Node = main.get("combat")
	check("CombatRuntime 已建立", combat != null)
	if combat == null:
		print("=== %d passed, %d failed ===" % [_pass, _fail])
		quit(1)
		return

	check("在 combat_runtime 群組裡", combat.is_in_group("combat_runtime"))
	check("HUD 已生成", combat.hud != null)
	check("死亡演出已生成", combat.death_screen != null)
	check("型選單已移除（FF7R 式，2026-09-16 裁定）", combat.get_node_or_null("FormMenu") == null and not InputMap.has_action("form_menu"))

	var player: Node = main.get("player")
	check("玩家在 player 群組", player != null and player.is_in_group("player"))

	# --- 玩家數值有沒有流到 HUD ---
	if combat.hud != null and player != null and player.posture != null:
		player.posture.apply_damage(30.0, 0.0)
		await process_frame
		check("扣血有傳到 HUD",
			combat.hud.player_health_ratio < 1.0,
			"HUD 血量比例 %.2f" % combat.hud.player_health_ratio)
		player.add_breath(40.0)
		await process_frame
		check("呼吸有傳到 HUD",
			combat.hud.player_breath_ratio > 0.0,
			"HUD 呼吸比例 %.2f" % combat.hud.player_breath_ratio)

	# --- 死亡 → 「死」演出 → 重生 ---
	if combat.death_screen != null and player != null and player.posture != null:
		var ds: Node = combat.death_screen
		var before: Vector3 = player.global_position
		player.global_position = before + Vector3(3.0, 0.0, 0.0)
		player.take_hit({"damage": 100000.0, "posture_damage": 0.0})
		await process_frame
		check("死亡後演出啟動", ds.is_running())
		check("死亡鎖輸入", bool(player.get("input_locked")))
		var respawned := [false]
		combat.respawn_requested.connect(func() -> void: respawned[0] = true)
		# 音效：倒地那一聲已由角色 CharacterAudio 播；「死」字浮現與重生淡入各一聲由 DeathScreen 播。
		var audio: Node = player.get_node("CharacterAudio")
		check("倒地音效 death_collapse 已載入", audio.call("_snd", "death_collapse.wav") != null)
		var sfx: AudioStreamPlayer = ds.get_node("Sfx")
		check("DeathScreen 有「死」字音效", ds.kanji_sound != null and ds.kanji_sound.resource_path.ends_with("death_kanji.wav"))
		check("DeathScreen 有重生音效", ds.respawn_sound != null and ds.respawn_sound.resource_path.ends_with("respawn_breath.wav"))
		var heard: Array[String] = []
		var t0 := Time.get_ticks_msec()
		while ds.is_running() and Time.get_ticks_msec() - t0 < 15000:
			await process_frame
			if sfx.playing and sfx.stream != null:
				var nm := sfx.stream.resource_path.get_file()
				if heard.is_empty() or heard.back() != nm:
					heard.append(nm)
		check("演出中依序播了 死字太鼓 → 重生吸氣", heard == ["death_kanji.wav", "respawn_breath.wav"], str(heard))
		check("演出在 %.1f s 內結束" % (ds.total_time() + 1.0), not ds.is_running(), "%.2f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
		check("有發 respawn_requested", respawned[0])
		check("重生後活著", not player.posture.is_dead())
		check("重生後血量全滿", is_equal_approx(player.posture.health, player.posture.max_health))
		check("重生後解鎖輸入", not bool(player.get("input_locked")))
		check("重生後 AnimationTree 重開", bool(player.get_node("Tree").active))
		check("重生後回到出生點（不是死亡點）", player.global_position.distance_to(before + Vector3(3.0, 0.0, 0.0)) > 1.0,
			"死點 %s → 重生 %s" % [before + Vector3(3.0, 0, 0), player.global_position])
		var black: ColorRect = ds.get_node("Black")
		check("黑幕已淡出", black.color.a < 0.01, "a=%.3f" % black.color.a)

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
