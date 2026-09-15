extends SceneTree
## Smoke test for the Yoriichi player in the main game: does main.tscn load,
## is $Player the Yoriichi CharacterBody3D, did the AnimationTree build, are
## the sockets and camera wired, and does the body stand on the slice ground
## after a few physics frames instead of falling through?
##
## Run: godot --headless --path godot --script tools/verify_yoriichi_player.gd

var _main: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	_main = packed.instantiate()
	root.add_child(_main)
	await process_frame
	_main.load_map("slice", "")
	for i in 6:
		await physics_frame

	var p: CharacterBody3D = _main.player
	var fails := 0
	print("Player: %s  script=%s" % [p.name, p.get_script().resource_path if p.get_script() else "無"])
	fails += _check("script 是 yoriichi_character.gd", String(p.get_script().resource_path).ends_with("yoriichi_character.gd"))
	fails += _check("有 interaction_prompt_changed 信號", p.has_signal("interaction_prompt_changed"))
	fails += _check("有 interaction_message 信號", p.has_signal("interaction_message"))

	var tree := p.find_children("*", "AnimationTree", true, false)
	fails += _check("AnimationTree 已建立", tree.size() == 1)
	if tree.size() == 1:
		var t: AnimationTree = tree[0]
		fails += _check("AnimationTree active", t.active)
		var pb = t.get("parameters/loco/playback")
		fails += _check("loco 狀態機有 playback", pb != null)
		if pb != null:
			print("  loco 目前節點: %s" % pb.get_current_node())

	var ap := p.find_children("*", "AnimationPlayer", true, false)
	fails += _check("AnimationPlayer 存在", ap.size() >= 1)
	if ap.size() >= 1:
		var a: AnimationPlayer = ap[0]
		var want := ["Idle_Grounded", "RunFast", "Run_FL", "Run_FR", "Roll_Dodge", "Jump",
			"Attack_Combo", "Draw_Sword"]
		var missing := []
		for w in want:
			if not a.has_animation(w):
				missing.append(w)
		fails += _check("衍生動畫全部載入 %s" % (("缺 " + str(missing)) if not missing.is_empty() else ""), missing.is_empty())

	fails += _check("Sword_Hand 存在", p.find_children("Sword_Hand", "", true, false).size() == 1)
	fails += _check("Sword_Sheathed 存在", p.find_children("Sword_Sheathed", "", true, false).size() == 1)
	var cam := p.find_children("*", "Camera3D", true, false)
	fails += _check("Camera3D 存在且 current", cam.size() == 1 and (cam[0] as Camera3D).current)
	fails += _check("input_yaw_node 指向 Pivot", p.get("input_yaw_node") != null and (p.get("input_yaw_node") as Node).name == "Pivot")

	# Let the body settle for 1 s of physics.
	var y0 := p.global_position.y
	for i in 60:
		await physics_frame
	var y1 := p.global_position.y
	print("  出生 y=%.2f → 1 s 後 y=%.2f  on_floor=%s" % [y0, y1, p.is_on_floor()])
	fails += _check("落地站穩（is_on_floor）", p.is_on_floor())
	fails += _check("沒掉穿地面（y > -5）", y1 > -5.0)

	# Drive it: simulate 1 s of move_forward and confirm it moved and stayed up.
	# ⚠ 開場會鎖住玩家，鎖有**兩層**，只解一層仍然不動（位移 0.00 m，看起來像
	#   「緣一不會走路」，實測獨立場景同一個 move_forward 走 4.00 m）：
	#   1) OpeningFade 黑幕（1.4 s 停留 + 2.2 s 淡入）期間 input_locked = true。
	#      不能只 await physics_frame 等它跑完 —— 淡入是 Tween，走 process_frame，
	#      純 physics 迴圈等 600 幀也不會前進。用它自備的 skip()。
	#   2) skip() 會立刻發 fade_finished → main 起 yoriichi_wake 獨白 → 又鎖一次。
	#      所以還要把對話推完。
	var fade := _main.get_node_or_null("OpeningFade")
	if fade != null and fade.has_method("skip"):
		fade.call("skip")
	await process_frame
	var dm: Node = root.get_node_or_null("/root/DialogueManager")
	var g := 0
	while dm != null and dm.call("is_active") and g < 120:
		dm.call("advance")
		await process_frame
		g += 1
	var wait := 0
	while bool(p.get("input_locked")) and wait < 240:
		await physics_frame
		await process_frame
		wait += 1
	print("  開場已跳過（推了 %d 句對話，等 %d 幀）input_locked=%s" % [g, wait, p.get("input_locked")])
	Input.action_press("move_forward")
	var p0 := p.global_position
	for i in 60:
		await physics_frame
	Input.action_release("move_forward")
	var moved := (p.global_position - p0).length()
	print("  按住 move_forward 1 s 位移 %.2f m（walk speed %.1f）" % [moved, p.get("speed")])
	fails += _check("會走路（位移 > 2 m）", moved > 2.0)
	fails += _check("走完還在地上", p.is_on_floor())
	if tree.size() == 1:
		var pb = (tree[0] as AnimationTree).get("parameters/loco/playback")
		print("  走路中 loco 節點: %s" % pb.get_current_node())

	print("[緣一] 失敗 %d" % fails)
	print("done")
	quit(0)


func _check(label: String, ok: bool) -> int:
	print("  %s %s" % ["✓" if ok else "✗", label])
	return 0 if ok else 1
