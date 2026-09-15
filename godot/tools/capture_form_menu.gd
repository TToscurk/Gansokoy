extends SceneTree
## 型選單截圖：開機 → 給呼吸 → 開選單 → 存 PNG。
##
## 執行：
##   godot --path godot -s tools/capture_form_menu.gd
##   （需要視窗，不能 --headless —— CanvasLayer UI 要真的畫出來才截得到）

const OUT := "user://form_menu.png"


func _initialize() -> void:
	# ⚠ 序章冷開機會演開場淡入（黑幕 1.4 s + 淡入 2.2 s）。先立起 woke_in_trail，
	#   main._ready() 的 is_cold_start 就不成立，畫面不會是全黑。
	# ⚠ -s 腳本裡 autoload 的全域識別字沒註冊（Identifier not found: StoryFlags），
	#   要從 root 取節點。
	var flags: Node = get_root().get_node_or_null("StoryFlags")
	if flags != null:
		flags.set_flag("woke_in_trail", true)
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main: Node = scene.instantiate()
	get_root().add_child(main)
	for i in 60:
		await process_frame

	var player: Node = main.get("player")
	var combat: Node = main.get("combat")
	if player == null or combat == null or combat.menu == null:
		push_error("[截圖] 戰鬥層沒掛上")
		quit(1)
		return

	# 讓畫面有東西看：拔刀、給呼吸、掉一點血與軀幹。
	player.set("sword_state", 2)          # DRAWN
	player.set("sun_mastery", 2)          # 修得到柒ノ型，灰／亮兩種狀態都看得到
	player.add_breath(58.0)
	player.posture.apply_damage(26.0, 34.0)
	# 冷卻中的樣子也入鏡
	player._form_cooldowns[9] = 2.4
	for i in 4:
		await process_frame

	combat.menu.open_menu()
	for i in 12:
		await process_frame

	# ⚠ 一定要等一個真正畫完的幀，否則抓到的是還沒繪製的空白 viewport。
	await RenderingServer.frame_post_draw
	var img: Image = get_root().get_texture().get_image()
	img.save_png(OUT)
	print("[截圖] ", ProjectSettings.globalize_path(OUT))
	quit(0)
