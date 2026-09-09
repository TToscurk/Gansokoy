extends SceneTree
## 山犬（雙尾狼）驗收：動畫、碰撞、狀態機、戰鬥契約、死亡流程。
##   Godot --headless --path godot --script tools/verify_enemy_wolf.gd
const WOLF := "res://characters/combat/enemy_wolf.tscn"
var fails := 0
var wolf: CharacterBody3D
var world: Node3D


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[WOLF] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _settle(n: int = 4) -> void:
	for i in n:
		await physics_frame
		await process_frame


func _aabb(n: Node) -> AABB:
	var wb := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while stack.size() > 0:
		var c: Node = stack.pop_back()
		for k in c.get_children():
			stack.push_back(k)
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null \
				and (c as Node3D).is_visible_in_tree():
			var b: AABB = (c as Node3D).global_transform * (c as MeshInstance3D).get_aabb()
			if first:
				wb = b
				first = false
			else:
				wb = wb.merge(b)
	return wb


func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(60, 1, 60)
	fc.shape = fb
	fc.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fc)
	world.add_child(floor_body)

	check("場景可載入", ResourceLoader.exists(WOLF))
	wolf = (load(WOLF) as PackedScene).instantiate()
	world.add_child(wolf)
	await _settle(10)

	# ── 尺寸與落地 ──
	var wb := _aabb(wolf)
	check("身長 2.0 m 級（實 %.2f m）" % wb.size.z, wb.size.z > 1.8 and wb.size.z < 2.3)
	check("站在地面上（腳底 y=%.3f）" % wb.position.y, absf(wb.position.y) < 0.15)
	check("有落地（is_on_floor）", wolf.is_on_floor())

	# ── 動畫 ──
	var anim: AnimationPlayer = null
	var stack: Array[Node] = [wolf]
	while stack.size() > 0:
		var c: Node = stack.pop_back()
		for k in c.get_children():
			stack.push_back(k)
		if c is AnimationPlayer:
			anim = c
	check("找得到 AnimationPlayer", anim != null)
	if anim != null:
		for a in ["Idle", "Walk", "Run", "Charge", "Slam", "Gatsuga", "Dissolve"]:
			check("動畫 %s 存在" % a, anim.has_animation(a))
		for a in ["Idle", "Walk", "Run"]:
			var an := anim.get_animation(a)
			check("%s 是循環" % a, an != null and an.loop_mode != Animation.LOOP_NONE)
		check("預設播 Idle（實 %s）" % anim.current_animation, anim.current_animation == "Idle")

	# ── 戰鬥契約（與 enemy_samurai 相同介面）──
	for m in ["take_hit", "can_deathblow", "execute_deathblow"]:
		check("有 %s()" % m, wolf.has_method(m))
	check("在 hittable 群組", wolf.is_in_group("hittable"))
	check("在 enemies 群組", wolf.is_in_group("enemies"))
	check("軀幹元件存在", wolf.get("posture") != null)

	# ── 受擊 ──
	var hp0: float = wolf.posture.health
	var r: Variant = wolf.take_hit({"damage": 12.0, "posture_damage": 10.0,
		"hit_pos": wolf.global_position + Vector3(0, 0.9, 0), "hit_dir": Vector3.FORWARD})
	await _settle(2)
	check("take_hit 回傳 hit", r is Dictionary and String((r as Dictionary).get("result", "")) == "hit")
	check("受擊後血量下降（%.0f → %.0f）" % [hp0, wolf.posture.health], wolf.posture.health < hp0)

	# ── 追擊 ──
	var fake := CharacterBody3D.new()
	# ⚠ 用有腳本的假玩家：裸 CharacterBody3D 用 set("action_state", 1)
	#   不會建立屬性，狼的閃避判定永遠讀到 null。
	fake.set_script(load("res://tools/_fake_player.gd"))
	var pc := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.7
	cap.radius = 0.3
	pc.shape = cap
	pc.position = Vector3(0, 0.85, 0)
	fake.add_child(pc)
	world.add_child(fake)
	fake.global_position = Vector3(0, 0.1, 10.0)
	wolf.target = fake
	var d0 := wolf.global_position.distance_to(fake.global_position)
	for i in 90:
		await physics_frame
	var d1 := wolf.global_position.distance_to(fake.global_position)
	check("會朝玩家逼近（%.1f → %.1f m）" % [d0, d1], d1 < d0 - 1.0)

	# ── 出招 ──
	wolf.global_position = fake.global_position + Vector3(0, 0, 2.5)
	var saw_windup := false
	var saw_strike := false
	for i in 240:
		await physics_frame
		if wolf.state == 2:
			saw_windup = true
		if wolf.state == 3:
			saw_strike = true
	check("貼身後會起手（WINDUP）", saw_windup)
	check("起手後會出招（STRIKE）", saw_strike)

	# ── 前搖長度：必須讀得出來 ──
	check("衝撞前搖 ≥0.4 s（實 %.2f）" % wolf.charge_windup, wolf.charge_windup >= 0.4)
	check("砸地前搖 ≥0.4 s（實 %.2f）" % wolf.slam_windup, wolf.slam_windup >= 0.4)

	# ── 跑步動畫倍速 ──
	check("Run 倍速 = 1.5（實 %.2f）" % wolf.run_anim_speed,
		is_equal_approx(wolf.run_anim_speed, 1.5))
	wolf.global_position = fake.global_position + Vector3(0, 0, 9.0)
	wolf._set_state(1)          # APPROACH
	await _settle(12)
	if anim != null:
		check("追擊時 speed_scale 套用 1.5（實 %.2f）" % anim.speed_scale,
			is_equal_approx(anim.speed_scale, 1.5))

	# ── 閃避：玩家揮刀 → 側躍 ──
	check("閃避預設開啟", wolf.dodge_enabled)
	wolf.global_position = fake.global_position + Vector3(0, 0, 3.0)
	wolf._dodge_cd = 0.0
	wolf.dodge_chance = 1.0     # 測試要確定會閃
	await _settle(6)
	var p_before: Vector3 = wolf.global_position
	# 假玩家進入 ATTACKING（ActionState.ATTACKING = 1）
	fake.set("action_state", 0)
	await physics_frame
	fake.set("action_state", 1)
	var saw_dodge := false
	for i in 40:
		await physics_frame
		if wolf.state == 8:      # DODGE
			saw_dodge = true
			break
	check("玩家揮刀 → 進入 DODGE", saw_dodge)
	if saw_dodge and anim != null:
		check("閃避時 speed_scale 加速到 2.2（實 %.2f）" % anim.speed_scale,
			is_equal_approx(anim.speed_scale, 2.2))
	for i in 40:
		await physics_frame
	var moved := p_before.distance_to(wolf.global_position)
	check("閃避有實際位移（%.2f m）" % moved, moved > 1.0)
	check("閃避後回到 APPROACH（實 %d）" % wolf.state, wolf.state == 1)
	# 冷卻：連續揮刀不該一直跳
	wolf.global_position = fake.global_position + Vector3(0, 0, 3.0)
	await _settle(4)
	fake.set("action_state", 0)
	await physics_frame
	fake.set("action_state", 1)
	var dodged_again := false
	for i in 30:
		await physics_frame
		if wolf.state == 8:
			dodged_again = true
	check("冷卻中不再閃（cd=%.2f）" % wolf._dodge_cd, not dodged_again)
	wolf.dodge_enabled = false   # 後面的死亡測試不要被閃避打斷

	# ── 牙通牙特效節點 ──
	check("鑽體已建立", wolf.get("_drill") != null)
	check("鑽體預設隱藏", wolf._drill != null and not wolf._drill.visible)
	check("找得到狼的網格根（旋轉段要藏它）", wolf.get("_wolf_mesh") != null)

	# ── 軀幹崩解 → 可忍殺 ──
	wolf.posture.apply_damage(0.0, 999.0)
	await _settle(4)
	check("軀幹崩解後可忍殺", wolf.can_deathblow())

	# ── 死亡：Dissolve 且會自我移除 ──
	var ok_dead: bool = wolf.execute_deathblow()
	await _settle(4)
	check("忍殺成功", ok_dead)
	check("死亡狀態", wolf.state == 7)
	if anim != null:
		check("死亡播 Dissolve（實 %s）" % anim.current_animation, anim.current_animation == "Dissolve")
	var col := wolf.get_node_or_null("CollisionShape3D") as CollisionShape3D
	check("死後碰撞關閉（屍體不擋路）", col != null and col.disabled)
	# 化光 4 s + 粒子殘留 1.7 s ≈ 5.7 s。60 fps → 至少 342 幀，抓 420 幀留餘裕。
	for i in 420:
		await physics_frame
	check("化光後自我移除", not is_instance_valid(wolf))

	print("[WOLF] failures=%d" % fails)
	quit(fails)
