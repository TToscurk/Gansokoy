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
		for a in ["Wolf_Idle", "Wolf_Walk", "Wolf_Run", "Wolf_Attack_Claw",
				"Wolf_Attack_Lunge", "Wolf_Attack_Pounce"]:
			check("動畫 %s 存在" % a, anim.has_animation(a))
		for a in ["Wolf_Idle", "Wolf_Walk", "Wolf_Run"]:
			var an := anim.get_animation(a)
			check("%s 是循環" % a, an != null and an.loop_mode != Animation.LOOP_NONE)
		check("預設播 Idle（實 %s）" % anim.current_animation, anim.current_animation == "Wolf_Idle")

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

	# ── 視覺朝向：狼的「模型」必須正面朝玩家，不是屁股 ──
	# ⚠ 這項是 2026-09-10 換模型後回報的實機 bug：碰撞體 rotation 正確、
	#   但 .tscn 的 Transform3D 是 column-major（與 GDScript 建構子的
	#   row-major 相反），寫成轉置後 yaw 差 180°，玩家看到屁股。
	#   只驗 rotation.y 抓不到，必須量骨骼實際世界座標。
	var skel := wolf.find_child("Skeleton3D", true, false) as Skeleton3D
	check("找得到 Skeleton3D", skel != null)
	if skel != null:
		var head_w: Vector3 = skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Head")).origin
		var pelvis_w: Vector3 = skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Pelvis")).origin
		var fwd := head_w - pelvis_w
		fwd.y = 0.0
		var to_p := fake.global_position - wolf.global_position
		to_p.y = 0.0
		var facing := fwd.normalized().dot(to_p.normalized()) if fwd.length() > 0.01 and to_p.length() > 0.01 else 0.0
		check("模型正面朝玩家（dot=%.2f，負值=屁股對玩家）" % facing, facing > 0.5)

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
	check("突進咬擊前搖 ≥0.4 s（實 %.2f）" % wolf.lunge_windup, wolf.lunge_windup >= 0.4)
	check("爪擊前搖 ≥0.4 s（實 %.2f）" % wolf.claw_windup, wolf.claw_windup >= 0.4)

	# ── 撲擊的發動距離帶必須存在（曾經因 d<=attack_range 與 d>=pounce_min_range
	#    互斥而整段是死碼，一次都沒發動過）──
	check("撲擊發動帶不與近身範圍互斥（%.1f > %.1f）" % [wolf.pounce_min_range, wolf.attack_range],
		wolf.pounce_min_range > wolf.attack_range)
	check("撲擊發動帶有寬度（%.1f–%.1f）" % [wolf.pounce_min_range, wolf.pounce_max_range],
		wolf.pounce_max_range > wolf.pounce_min_range)

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

	# ── 狼的網格根節點（旋風/死亡特效之後要用）──
	check("找得到狼的網格根", wolf.get("_wolf_mesh") != null)

	# ── 撲擊旋風特效 ──
	# ⚠ 2026-09-10：Blender 的旋風是 NURBS 曲線 + bevel trim，glTF 搬不過去，
	#   第一次換模型時整批遺失（匯出的 GLB 裡 Vortex 節點數 = 0）卻沒被驗收抓到。
	#   現在改成靜態管狀網格 + shader trim，這裡驗它真的有建起來。
	check("旋風節點已建立", wolf.get("_vortex_root") != null)
	var vmats: Array = wolf.get("_vortex_mats")
	check("旋風材質數 = 10（實 %d）" % vmats.size(), vmats.size() == 10)
	var vroot: Node3D = wolf.get("_vortex_root")
	check("旋風預設隱藏", vroot != null and not vroot.visible)
	# ⚠ 旋風必須與狼網格共用同一個變換（縮放 2.06 + 朝向修正）。
	#   掛在 Visual 底下卻用單位變換的話，會是 1:1 的 Blender 原始尺寸 ——
	#   使用者實機回報「旋風特小」（實測尺寸比只有 0.416）。
	if vroot != null and wolf.get("_wolf_mesh") != null:
		var wm: Node3D = wolf.get("_wolf_mesh")
		var vs := vroot.transform.basis.get_scale()
		var ws := wm.transform.basis.get_scale()
		check("旋風縮放對齊狼網格（%.2f vs %.2f）" % [vs.x, ws.x],
			is_equal_approx(vs.x, ws.x))
		# 實際幾何尺寸比：旋風要包住狼身，太小就是沒對齊
		vroot.visible = true
		for m in vmats:
			(m as ShaderMaterial).set_shader_parameter("trim_start", 0.0)
			(m as ShaderMaterial).set_shader_parameter("trim_end", 1.0)
		await _settle(2)
		var va := _aabb(vroot)
		var wa := _aabb(wm)
		var ratio: float = va.size.length() / maxf(wa.size.length(), 0.001)
		check("旋風尺寸與狼身相稱（比值 %.2f，應 >0.5）" % ratio, ratio > 0.5)
		vroot.visible = false
		for m in vmats:
			(m as ShaderMaterial).set_shader_parameter("trim_end", 0.0)

	# ── 跑步／撲擊風線 ──
	# ⚠ 與旋風同一類問題：Blender 的風線也是 NURBS bevel trim，glTF 搬不過去。
	#   44 條靜態管狀網格 + shader trim，跑步版 16 幀循環（與 Wolf_Run 同週期）、
	#   撲擊版一次性。使用者實機回報「跑步的那個風沒有出來」才補上。
	check("風線節點已建立", wolf.get("_streak_root") != null)
	var smats: Array = wolf.get("_streak_mats")
	check("風線材質數 = 44（實 %d）" % smats.size(), smats.size() == 44)
	var sroot: Node3D = wolf.get("_streak_root")
	check("風線預設隱藏", sroot != null and not sroot.visible)
	if sroot != null and wolf.get("_wolf_mesh") != null:
		var wm2: Node3D = wolf.get("_wolf_mesh")
		check("風線縮放對齊狼網格（%.2f vs %.2f）" % [
			sroot.transform.basis.get_scale().x, wm2.transform.basis.get_scale().x],
			is_equal_approx(sroot.transform.basis.get_scale().x,
				wm2.transform.basis.get_scale().x))

	# ── 軀幹崩解 → 可忍殺 ──
	wolf.posture.apply_damage(0.0, 999.0)
	await _settle(4)
	check("軀幹崩解後可忍殺", wolf.can_deathblow())

	# ── 死亡：Wolf_Death 化光上浮 ──
	var ok_dead: bool = wolf.execute_deathblow()
	await _settle(4)
	check("忍殺成功", ok_dead)
	check("死亡狀態", wolf.state == 7)
	var ap := wolf._anim as AnimationPlayer
	check("死亡播 Wolf_Death", ap != null and ap.current_animation == "Wolf_Death")
	var skel_d := wolf.get_node_or_null("Visual") as Node3D
	var bone_y := func() -> float:
		var st: Array[Node] = [wolf]
		while st.size() > 0:
			var n: Node = st.pop_back()
			for c in n.get_children():
				st.push_back(c)
			if n is Skeleton3D:
				var sk := n as Skeleton3D
				return (sk.global_transform * sk.get_bone_global_pose(0).origin).y
		return 0.0
	var y0: float = bone_y.call()
	check("死亡溶解材質已換上", (wolf._dissolve_mats as Array).size() > 0)
	var col := wolf.get_node_or_null("CollisionShape3D") as CollisionShape3D
	# set_deferred 要等一幀才生效（見 enemy_wolf.gd _on_died 的註解）
	await _settle(2)
	check("死後碰撞關閉（屍體不擋路）", col != null and col.disabled)
	# 浮空：3 秒後 Root 骨骼應明顯高於死亡當下
	for i in 180:
		await physics_frame
	if is_instance_valid(wolf):
		var y1: float = bone_y.call()
		print("[WOLF] 死亡浮空 Root y: %.3f → %.3f（skel_d=%s）" % [y0, y1, skel_d != null])
		check("死亡浮空（不倒地）", y1 > y0 + 0.25)
	for i in 200:
		await physics_frame
	check("死亡延遲後自我移除", not is_instance_valid(wolf))

	print("[WOLF] failures=%d" % fails)
	quit(fails)
