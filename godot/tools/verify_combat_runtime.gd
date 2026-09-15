extends SceneTree
## main.tscn 實際開機後，戰鬥層有沒有真的掛上去。
##
## 執行：
##   godot --headless --path godot -s tools/verify_combat_runtime.gd
##
## verify_form_menu.gd 驗的是規則；這支驗的是「接線在真實開機路徑上成立」——
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
	check("型選單已生成", combat.menu != null)
	check("Tab 已註冊為 form_menu", InputMap.has_action("form_menu"))

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

	# --- 選單開關會不會鎖玩家輸入 ---
	if combat.menu != null and player != null:
		check("選單預設關閉", not combat.menu.open)
		var scale_before: float = Engine.time_scale
		combat.menu.open_menu()
		await process_frame
		check("開選單後時間變慢",
			Engine.time_scale < scale_before,
			"%.2f → %.2f" % [scale_before, Engine.time_scale])
		check("開選單鎖住玩家輸入", bool(player.get("input_locked")))
		combat.menu.close()
		await process_frame
		check("關選單還原時間",
			is_equal_approx(Engine.time_scale, scale_before),
			"%.2f" % Engine.time_scale)
		check("關選單解鎖玩家輸入", not bool(player.get("input_locked")))

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
