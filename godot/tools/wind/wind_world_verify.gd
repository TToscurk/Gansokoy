extends SceneTree
## Wind V2 Phase G／H：正式地圖整合驗證（headless；走 main.tscn 真正的換圖流程）。
##   Godot_v4.7.2-stable_win64_console.exe --headless --path godot --script res://tools/wind/wind_world_verify.gd
## G1 進人里：主河接線、暖簾＋竹簾、吊燈籠鉸鏈（靜止＝原擺位、無碰撞體）、小舟繫留、正式不生成測試漂流物
## G2 進獸道：植被接線（樹／竹／草物種分佈）、離開主河後水面場清空
## G3 人里→獸道→人里：Wind 只有一個、風時鐘連續、燈籠／河重新接線、沒有重複鉸鏈
## G4 存讀檔（空槽才用，用完刪）  G5 暫停：風時鐘停、恢復接著走  G6 生物：狼 rig 自動接、緣一不接
## 任何 FAIL → quit(1)

var fails := 0
var w: Node
var main: Node


func _init() -> void:
	_run.call_deferred()


func _ok(c: bool, m: String) -> void:
	print(("  PASS  " if c else "  FAIL  ") + m)
	if not c:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _map() -> Node:
	for c in main.get_children():
		if c is Node3D and c.scene_file_path.begins_with("res://maps/"):
			return c
	return main.find_child("village_v2", false, false)


func _count_winds() -> int:
	var n := 0
	for c in root.get_children():
		if String(c.name) == "Wind" or (c.get_script() != null and String(c.get_script().resource_path).ends_with("scripts/wind.gd")):
			n += 1
	return n


func _village_checks(tag: String) -> void:
	var m := _map()
	var mr := m.find_child("MainRiver", true, false) as MeshInstance3D if m else null
	_ok(w.has_water() and mr != null and mr.material_override is ShaderMaterial, "[%s] 主河接線（water.gdshader 主河模式）" % tag)
	var cloth := 0
	var sudare := 0
	for n in m.find_children("nr_*", "MeshInstance3D", true, false):
		var mm := (n as MeshInstance3D).material_override as ShaderMaterial
		if mm and mm.shader.resource_path.ends_with("wind_cloth.gdshader"):
			if String(n.name).begins_with("nr_sudare"):
				sudare += 1
			else:
				cloth += 1
	_ok(cloth >= 50 and sudare >= 30, "[%s] 布料接線：暖簾 %d、竹簾 %d" % [tag, cloth, sudare])
	var pivots := m.find_children("WindPivot_*", "Node3D", true, false)
	var lanterns := 0
	var bodies := 0
	for p in pivots:
		lanterns += p.get_child_count()
		bodies += p.find_children("*", "CollisionObject3D", true, false).size()
	_ok(pivots.size() >= 20 and lanterns == pivots.size() and bodies == 0, "[%s] 吊燈籠鉸鏈 %d 個（每個 1 顆燈籠、底下無碰撞體）" % [tag, pivots.size()])
	var boat := m.find_child("BoatTether", true, false)
	_ok(boat != null, "[%s] 碼頭小舟繫留（既有資產）" % tag)
	_ok(m.find_child("LEAF_PROXY_0", true, false) == null and m.find_child("Taru_0", true, false) == null,
		"[%s] 正式遊玩不生成測試漂流物（落葉 proxy／酒樽）" % tag)


func _run() -> void:
	w = root.get_node("Wind")
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(5)

	print("\n[G1] 進人里")
	# main 開機就載入人里（BOOT 預設）；不要再 load 一次
	await _frames(20)
	if _map() == null or not String(_map().scene_file_path).contains("village_v2"):
		main.load_map("village_v2", "")
		await _frames(20)
	var m := _map()
	# 原擺位＝接線當下記在 meta wind_orig_xf 的 global transform
	var orig := {}
	for p in m.find_children("WindPivot_*", "Node3D", true, false):
		for n in p.get_children():
			if n.has_meta("wind_orig_xf"):
				orig[n] = n.get_meta("wind_orig_xf")
	_village_checks("人里")
	# 關風、擺錘歸零 → 燈籠回到原擺位
	w.set_enabled(false)
	# 關風是 TAU_OFF 0.45 s 平滑淡出：等 2 s 讓殘風真的歸零，再把擺錘歸零
	await create_timer(2.0).timeout
	for p in m.find_children("WindPivot_*", "Node3D", true, false):
		p.call("settle")
	# 遠處燈籠 10 Hz 更新 → 等 0.3 s 讓每一個都至少更新一次
	await create_timer(0.3).timeout
	await _frames(3)
	var worst := 0.0
	for n in orig:
		if is_instance_valid(n):
			worst = maxf(worst, (n as MeshInstance3D).global_transform.origin.distance_to((orig[n] as Transform3D).origin))
			worst = maxf(worst, ((n as MeshInstance3D).global_transform.basis.x - (orig[n] as Transform3D).basis.x).length())
	_ok(orig.size() >= 20 and worst < 1e-3, "靜止時 %d 個燈籠 mesh 與原擺位差 %.5f（吊點與作者擺位保留）" % [orig.size(), worst])
	w.set_enabled(true)
	# 強陣風下燈籠會擺、而且不同步
	w.set_preset(3)
	w.trigger_gust(1.0, 3.0)
	await _frames(240)
	var sw := []
	for p in m.find_children("WindPivot_*", "Node3D", true, false):
		sw.append(float(p.call("swing_deg")))
	sw.sort()
	_ok(sw.size() > 0 and float(sw[-1]) > 2.0 and float(sw[-1]) - float(sw[0]) > 0.5,
		"強陣風燈籠擺角 %.1f°–%.1f°（會擺、不同步）" % [float(sw[0]), float(sw[-1])])

	print("\n[G2] 進獸道")
	var t_before := float(w.get_wind()["time"])
	w.set("_veg_stats", {})
	main.load_map("beast_path", "")
	await _frames(20)
	var st: Dictionary = w.veg_stats()["species"]
	_ok(int(st.get("conifer", 0)) > 1000 and int(st.get("broad_tall", 0)) > 500 and int(st.get("bamboo", 0)) > 500 and int(st.get("grass", 0)) > 1000,
		"獸道植被接線：%s" % str(st))
	_ok(not w.has_water(), "離開人里主河 → 水面場清空（獸道溪流維持原材質）")

	print("\n[G3] 獸道→人里（換圖連續性）")
	main.load_map("village_v2", "")
	await _frames(20)
	var t_after := float(w.get_wind()["time"])
	_ok(_count_winds() == 1, "Wind autoload 只有 1 個（%d）" % _count_winds())
	_ok(t_after > t_before, "風時鐘換圖不重置（%.2f → %.2f）" % [t_before, t_after])
	_village_checks("回人里")
	var dup := 0
	for p in _map().find_children("WindPivot_*", "Node3D", true, false):
		if String(p.get_parent().name).begins_with("WindPivot"):
			dup += 1
	_ok(dup == 0, "沒有重複鉸鏈（鉸鏈套鉸鏈 %d）" % dup)

	print("\n[G4] 存讀檔")
	var sm := root.get_node_or_null("SaveManager")
	var slot := int(sm.get("SLOT_COUNT")) - 1 if sm else -1
	if sm and not sm.has_save(slot):
		var ok_s: bool = sm.save_game(slot, "village_v2", Vector3(237, 1, 72), 0.0)
		var tw := float(w.get_wind()["time"])
		var ok_l: bool = sm.load_game(slot)
		await _frames(30)
		_ok(ok_s and ok_l and _count_winds() == 1 and w.has_water() and float(w.get_wind()["time"]) >= tw,
			"存檔→讀檔（槽 %d）：Wind 1 個、主河接線、風時鐘連續（風不寫進存檔：決定性風場，讀檔後接著走）" % slot)
		sm.delete_save(slot)
	else:
		print("  SKIP  最後一個存檔槽已被使用——不覆蓋玩家存檔")

	print("\n[G5] 暫停／恢復")
	paused = true
	var tp := float(w.get_wind()["time"])
	await _frames(30)
	var tp2 := float(w.get_wind()["time"])
	paused = false
	await _frames(30)
	var tp3 := float(w.get_wind()["time"])
	_ok(absf(tp2 - tp) < 1e-6 and tp3 > tp2, "暫停時風時鐘停（%.3f → %.3f）、恢復後接著走（→ %.3f）" % [tp, tp2, tp3])

	print("\n[G6] 生物")
	var holder := Node3D.new()
	_map().add_child(holder)
	var wolf: Node = (load("res://characters/combat/enemy_wolf.tscn") as PackedScene).instantiate()
	holder.add_child(wolf)
	await _frames(10)
	var mods := wolf.find_children("*", "SkeletonModifier3D", true, false).filter(func(x): return x is WindSecondaryMotion)
	_ok(mods.size() == 1 and int(mods[0].call("chain_count")) == 8, "正式 enemy_wolf 自動接 WindSecondaryMotion（%d 個、%d 條鏈）" % [mods.size(), int(mods[0].call("chain_count")) if mods.size() else 0])
	if mods.size():
		var bp: NodePath = mods[0].get("body_path")
		var body := (mods[0] as Node).get_node_or_null(bp)
		_ok(body is CharacterBody3D, "身體＝CharacterBody3D（%s）" % (body.get_class() if body else "null"))
	var yo: Node = (load("res://characters/yoriichi/player_yoriichi.tscn") as PackedScene).instantiate()
	holder.add_child(yo)
	await _frames(5)
	var ym := yo.find_children("*", "SkeletonModifier3D", true, false).filter(func(x): return x is WindSecondaryMotion)
	_ok(ym.size() == 0, "緣一不被自動接（rig 簽名不符；其骨架由角色 session 持有）")
	holder.queue_free()
	await _frames(3)

	print("\n結果：%s（fails=%d）" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
