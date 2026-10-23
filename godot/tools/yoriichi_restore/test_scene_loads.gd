extends SceneTree
## 場景載入回歸：正式 main.tscn 依序 load_map 神社／獸道／人間之里 V2，加上三種敵人與 combat_arena，
## 確認移除 R7／R8 後沒有載入錯誤，且場上 Player 是正式控制器。只讀，不寫資源。
##   godot --headless --fixed-fps 60 --path godot -s res://tools/yoriichi_restore/test_scene_loads.gd
var _fail := 0

func _initialize() -> void:
	call_deferred("_run")

func _ck(ok: bool, name: String, info := "") -> void:
	if not ok:
		_fail += 1
	print(("PASS " if ok else "FAIL ") + name + ("  " + info if info != "" else ""))

func _frames(n: int) -> void:
	for i in n:
		await process_frame
		await physics_frame

func _player_ok(main: Node) -> String:
	var p := main.get_node_or_null("Player")
	if p == null:
		return "no Player"
	return str(p.get_script().resource_path)

func _run() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(20)
	_ck(_player_ok(main).ends_with("characters/yoriichi/yoriichi_character.gd"), "main.tscn 開機（Player 正式控制器）", _player_ok(main))
	for m in ["shrine", "beast_path", "village_v2", "slice"]:
		main.call("load_map", m, "")
		await _frames(60)
		var p := main.get_node_or_null("Player") as Node3D
		_ck(p != null and _player_ok(main).ends_with("yoriichi_character.gd"), "load_map(%s)" % m,
			"player_pos=%s" % (str(p.global_position.snapped(Vector3.ONE * 0.1)) if p else "-"))
	main.queue_free()
	await _frames(5)
	for path in ["res://characters/combat/enemy_samurai.tscn", "res://characters/combat/enemy_wolf.tscn",
			"res://characters/combat/training_dummy.tscn", "res://scenes/combat_arena.tscn"]:
		var ps := load(path) as PackedScene
		var inst: Node = ps.instantiate() if ps != null else null
		if inst != null:
			root.add_child(inst)
			await _frames(10)
			if path.ends_with("combat_arena.tscn"):
				_ck(_player_ok(inst).ends_with("yoriichi_character.gd"), "combat_arena（Player 正式控制器）", _player_ok(inst))
			else:
				_ck(true, path.get_file())
			inst.queue_free()
			await _frames(3)
		else:
			_ck(false, path.get_file(), "載入失敗")
	print("SCENE_LOAD_RESULT fail=%d" % _fail)
	quit()
