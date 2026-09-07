extends SceneTree
## 人里口實走驗證：從獸道傳送落地後，真的用鍵盤往里內走，看 MQ05 何時完成。
##   Godot --headless --path godot --script tools/verify_village_gate.gd
var main: Node
var qm: Node
var sf: Node
var dm: Node
var fails := 0


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[GATE] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await physics_frame
	e = InputEventAction.new()
	e.action = action
	e.pressed = false
	Input.parse_input_event(e)
	await physics_frame


func _settle(n: int = 4) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _ray_chain(x: float, z: float) -> String:
	var space := main.get_viewport().get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -100.0, z))
	var ex: Array[RID] = [main.player.get_rid()]
	var parts := []
	for k in 5:
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if not hit.has("position"):
			break
		var col: Object = hit.get("collider")
		parts.append("%s y=%.2f" % [col.name if col else "?", hit.position.y])
		ex.append(hit.rid)
	return " ← ".join(parts)


func _run() -> void:
	qm = root.get_node("/root/QuestManager")
	sf = root.get_node("/root/StoryFlags")
	dm = root.get_node("/root/DialogueManager")
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(20)
	# 開局在獸道會自動播醒來獨白；沒把它演完就換圖，玩家會一直被鎖著
	# （input_locked=true，走不動）。先讓它結束。
	while dm.is_active():
		await _press("ui_accept")
		await _press("ui_accept")
	# 直接進入序章終點狀態
	sf.set_flag("met_reimu", true)
	qm.reset()
	qm.start_quest("MQ05")
	main.load_map("slice", "trail")
	await _settle(40)
	var p: Vector3 = main.player.global_position
	print("[GATE] 傳送落地點 (%.1f, %.2f, %.1f)" % [p.x, p.y, p.z])
	check("落地在里口附近", Vector2(p.x - 234.0, p.z - 110.0).length() < 12.0)
	print("[GATE] 觸發區上空射線 (234,101)：%s" % _ray_chain(234.0, 101.0))
	print("[GATE] 落地點射線 (%.1f,%.1f)：%s" % [p.x, p.z, _ray_chain(p.x, p.z)])
	# 真的往北（-z，里內）走。
	# ⚠ Input.parse_input_event(InputEventAction) 不會讓 Input.get_vector 回傳
	#   非零向量（移動讀的是 action strength），headless 下角色會原地不動。
	#   要用 Input.action_press。
	# ⚠ 移動方向是「相機 yaw 旋轉後」的方向，不是角色模型朝向。實測 snap_yaw(PI)
	#   往 +z（離開里）走，所以里內（-z）對應 yaw=0。
	if main.player.has_method("snap_yaw"):
		main.player.snap_yaw(0.0)
	Input.action_press("move_forward")
	var frames := 0
	while frames < 900 and not qm.is_completed("MQ05"):
		await physics_frame
		frames += 1
		if frames % 200 == 0:
			var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			print("[GATE]   f=%d cls=%s locked=%s vec=%s vel=%s pos=(%.1f,%.2f,%.1f) floor=%s"
				% [frames, main.player.get_class(), str(main.player.get("input_locked")), str(v),
				str(main.player.velocity), main.player.global_position.x,
				main.player.global_position.y, main.player.global_position.z,
				str(main.player.is_on_floor())])
	Input.action_release("move_forward")
	var q: Vector3 = main.player.global_position
	print("[GATE] 走了 %d 幀後在 (%.1f, %.2f, %.1f)" % [frames, q.x, q.y, q.z])
	check("實際走進里口即完成 MQ05（未瞬移）", qm.is_completed("MQ05"))
	check("visited_human_village 旗標", sf.get_flag("visited_human_village"))
	print("[GATE] failures=%d" % fails)
	quit(fails)
