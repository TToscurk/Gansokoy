extends SceneTree
## 實機確認：本輪新接的兩個動作，在真實渲染下實拍。
##
##   Godot.exe --path godot --script tools/capture_ingame_new.gd
##
## 為什麼自己搭場景：`--script` 模式不會建立 autoload，直接 instance
## scenes/combat_arena.tscn（含 CombatHUD）會卡死（已踩過一次）。這裡只放
## 「地面 ＋ 玩家 ＋ 武士 ＋ 相機」，跑的是玩家真的按 G 走的那條路
## （try_deathblow → _play_deathblow → full 層 OneShot）。
##
## 輸出：D:/神社/shrine/work/shots/ingame_new/

const OUT := "D:/神社/shrine/work/shots/ingame_new/"
const PLAYER := "res://characters/yoriichi/player_yoriichi.tscn"
const SAMURAI := "res://characters/combat/enemy_samurai.tscn"


func _init() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _shoot(path: String) -> void:
	await _wait(2)
	root.get_viewport().get_texture().get_image().save_png(path)
	print("[CAP] %s" % path)


func _hit(dmg: float, pdmg: float, dir: Vector3) -> Dictionary:
	return {"damage": dmg, "posture_damage": pdmg, "hit_dir": dir, "hit_pos": Vector3(0, 1, 0)}


func _sel(player: Node) -> String:
	var t: AnimationTree = player.get_node_or_null("Tree") as AnimationTree
	if t == null:
		return "(no Tree)"
	return str(t.get("parameters/full_sel/current_state"))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.66, 0.72)
	e.ambient_light_energy = 1.0
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 34, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)

	var floor_body := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(60, 1, 60)
	fc.shape = fb
	fc.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fc)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.28, 0.29, 0.26)
	pm.material = gm
	fm.mesh = pm
	floor_body.add_child(fm)
	world.add_child(floor_body)

	var player: CharacterBody3D = (load(PLAYER) as PackedScene).instantiate()
	world.add_child(player)
	player.global_position = Vector3(0, 0, 0)
	var enemy: CharacterBody3D = (load(SAMURAI) as PackedScene).instantiate()
	world.add_child(enemy)
	enemy.global_position = Vector3(0, 0, 2.2)
	await _wait(40)
	print("[CAP] 玩家 %s｜武士 %s" % [str(player != null), str(enemy != null)])

	# 相機：玩家右後上方，同時看得見刀與武士。
	for c in player.find_children("*", "Camera3D", true, false):
		(c as Camera3D).current = false
	var cam := Camera3D.new()
	cam.fov = 45.0
	world.add_child(cam)
	cam.global_position = Vector3(2.9, 2.0, -3.2)
	cam.look_at(enemy.global_position + Vector3(0, 1.0, 0), Vector3.UP)
	cam.current = true
	await _wait(8)
	await _shoot(OUT + "00_對峙.png")

	# 拔刀：忍殺演出時刀要在手（實測拔刀 45 格還只是 1=拔刀中，要等到 2=已拔）。
	player.request_draw()
	var draw_wait := 0
	for i in 200:
		if player.sword_state == 2:
			break
		draw_wait += 1
		await _wait(1)
	print("[CAP] 拔刀完成 sword_state=%d（等了 %d 格）" % [player.sword_state, draw_wait])

	# 崩軀幹 → 按 G。
	enemy.posture.apply_damage(0.0, 999.0)
	await _wait(4)
	print("[CAP] 距離 %.2f m｜可處決 %s" % [
		player.global_position.distance_to(enemy.global_position),
		str(enemy.can_deathblow())])
	var ok: bool = player.try_deathblow()
	print("[CAP] try_deathblow()=%s｜段落=%s｜鎖操作=%s" % [str(ok), _sel(player), str(player.input_locked)])
	await _wait(4)
	await _shoot(OUT + "01_忍殺_入場.png")
	await _wait(10)
	await _shoot(OUT + "02_忍殺_落刀.png")
	await _wait(14)
	await _shoot(OUT + "03_忍殺_收勢.png")
	# 等忍殺演完（1.1667 s ≒ 35 格，加淡出與解鎖）：演出中 _deathblow_left > 0，
	# take_hit 會走「只跑重力」的提早返回分支，打不出破綻（第一次拍就踩到）。
	var tail: int = 0
	for i in 140:
		if not player.input_locked and player.get("_deathblow_left") <= 0.0:
			break
		tail += 1
		await _wait(1)
	print("[CAP] 忍殺收尾完成（等了 %d 格）｜鎖操作=%s" % [tail, str(player.input_locked)])

	# 方向性軀幹爆：從左側打進來（hit_dir = 由左往右），打到真的破綻為止。
	for i in 14:
		if player.posture.is_broken():
			break
		player.take_hit(_hit(1.0, 60.0, Vector3(1, 0, 0)))
		await _wait(2)
	await _wait(2)
	print("[CAP] 軀幹爆：破綻=%s｜段落=%s" % [str(player.posture.is_broken()), _sel(player)])
	await _shoot(OUT + "04_軀幹爆_左_入場.png")
	await _wait(14)
	await _shoot(OUT + "05_軀幹爆_左_中段.png")
	await _wait(20)
	await _shoot(OUT + "06_軀幹爆_左_收尾.png")

	print("[CAP] ===== 完成 =====")
	quit()
