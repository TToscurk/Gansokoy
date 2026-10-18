extends SceneTree
## Wind V2 Phase F：WindSecondaryMotion 驗證（headless；骨架修改器不需要算繪）。
##   Godot_v4.7.2-stable_win64_console.exe --headless --path godot --script res://tools/wind/secondary_verify.gd
## 方法＝「雙胞胎」：同位置、同動畫、同時間的兩隻狼，一隻掛元件、一隻不掛；比較兩者骨頭全域姿勢的差。
## ⚠ Skeleton3D 在修改器跑完、蒙皮用完後會把姿勢還原成修改前（4.3+ 非破壞式修改器）→ 從外面讀永遠是純動畫。
##   所以在 skeleton_updated（修改器之後發出）裡把最終姿勢記下來比。
## F1 骨鏈驗證  F2 無風靜止不漂移  F3 風→尾巴順風偏  F4 加速→尾巴往後  F5 轉向→往外
## F6 風停回彈收斂  F7 Tier 0＝零影響  F8 非鏈骨（頭、腿）與動畫完全相同  F9 不相容 rig 安全失效

var fails := 0
var w: Node
var pilot: Node3D
var A: Node3D   # 有元件
var B: Node3D   # 對照（純動畫）
var skA: Skeleton3D
var skB: Skeleton3D
var mod: Node
var _snap := {"A": {}, "B": {}}
const WATCH := ["Tail5", "ManeB.L2", "HFoot.L", "Head", "FToe.R"]


func _init() -> void:
	_run.call_deferred()


func _ok(c: bool, m: String) -> void:
	print(("  PASS  " if c else "  FAIL  ") + m)
	if not c:
		fails += 1


func _run() -> void:
	w = root.get_node("Wind")
	w.set_frozen(true)
	w.set_preset(0)
	w.set_wind(0.0, 0.0)
	for i in 600:
		w.debug_advance(1.0 / 30.0)
	pilot = (load("res://scenes/secondary_motion_pilot.tscn") as PackedScene).instantiate()
	pilot.set("running", false)
	root.add_child(pilot)
	await process_frame
	A = pilot.call("spawn_wolf", "TwinA", Vector3(0, 0, 0), "Wolf_Idle", true)
	B = pilot.call("spawn_wolf", "TwinB", Vector3(0, 0, 0), "Wolf_Idle", false)
	skA = A.find_children("*", "Skeleton3D", true, false)[0]
	skB = B.find_children("*", "Skeleton3D", true, false)[0]
	mod = skA.get_node("WindSecondaryMotion")
	mod.set("tier", 2)
	skA.skeleton_updated.connect(_record.bind("A", skA))
	skB.skeleton_updated.connect(_record.bind("B", skB))
	await process_frame

	print("\n[F1] 骨鏈驗證")
	_ok(int(mod.call("chain_count")) == 8, "wolf profile 8 條鏈全部通過父子／骨長驗證（%d）" % int(mod.call("chain_count")))
	var found: Array = WindSecondaryMotion.discover(skA)
	var names := found.map(func(c): return "%s→%s" % [c.root_bone, c.tip_bone])
	_ok(names.has("Tail1→Tail5"), "名稱探索（只當線索）找到 Tail1→Tail5（共 %d 條：%s）" % [found.size(), ", ".join(names)])

	print("\n[F2] 無風、靜止：不漂移")
	_ok((w.sample_wind(Vector3(0, 1, 0)) as Vector3).length() < 0.01, "前提：風已停（%.4f m/s）" % (w.sample_wind(Vector3(0, 1, 0)) as Vector3).length())
	await _frames(300)
	var d_tail := _diff("Tail5")
	_ok(d_tail < 0.01, "5 s 後尾尖與純動畫差 %.4f m（< 1 cm，無累積）" % d_tail)

	print("\n[F3] 風 +X 6 m/s → 尾巴順風偏")
	w.set_wind(0.0, 1.0)
	for i in 120:
		w.debug_advance(1.0 / 30.0)
	await _frames(180)
	var off := _off("Tail5")
	_ok(off.x > 0.03, "尾尖順風（+X）偏 %.3f m（全向量 %s）" % [off.x, off])
	var mane := _off("ManeB.L2")
	_ok(mane.length() > 0.003 and mane.length() < off.length(), "鬃毛也偏（%.3f m）但比尾巴小（較硬、較短）" % mane.length())
	var leg := maxf(_diff("HFoot.L"), maxf(_diff("Head"), _diff("FToe.R")))
	_ok(leg < 1e-4, "F8 非鏈骨（腳、頭、爪）與純動畫相同（最大差 %.6f m）" % leg)

	print("\n[F6] 風停回彈（set_enabled(false)：風場 TAU_OFF 0.45 s 內淡出）")
	w.set_enabled(false)
	for i in 150:
		w.debug_advance(1.0 / 30.0)
	var peak := 0.0
	var seq := []
	for i in 180:
		await process_frame
		var d := _diff("Tail5")
		seq.append(d)
	_ok(float(seq[-1]) < off.length() * 0.2, "3 s 後尾尖偏移 %.4f m（< 風中 %.3f 的 20 %%）" % [float(seq[-1]), off.length()])
	var jumps := 0.0
	for i in range(1, seq.size()):
		jumps = maxf(jumps, absf(float(seq[i]) - float(seq[i - 1])))
	_ok(jumps < 0.02, "回彈平滑：每幀最大變化 %.4f m" % jumps)

	print("\n[F4／F5] 身體加速／轉向（無風）")
	w.set_enabled(true)
	w.set_wind(0.0, 0.0)
	for i in 600:
		w.debug_advance(1.0 / 30.0)
	# 兩隻同步移動：+Z 加速 3 m/s²，2 s
	var vz := 0.0
	var pz := 0.0
	for i in 120:
		vz += 3.0 / 60.0
		pz += vz / 60.0
		A.position.z = pz
		B.position.z = pz
		await process_frame
	var acc_off := _off("Tail5")
	_ok(acc_off.z < -0.02, "往 +Z 加速 → 尾尖往後（−Z）%.3f m（相對空氣＋慣性）" % acc_off.z)
	# 轉向：等速 4 m/s 繞圈（半徑 4 m，往左轉）→ 尾巴往外（右側）
	var ang := 0.0
	var c0 := Vector3(A.position.x - 4.0, 0, A.position.z)
	var lat := 0.0
	for i in 240:
		ang += 1.0 / 60.0
		var p := c0 + Vector3(cos(ang), 0, sin(ang)) * 4.0
		var vdir := Vector3(-sin(ang), 0, cos(ang))
		for n in [A, B]:
			n.position = p
			n.rotation.y = atan2(vdir.x, vdir.z)
		await process_frame
		if i > 120:
			var outward := Vector3(cos(ang), 0, sin(ang))
			lat += _off("Tail5").dot(outward)
	_ok(lat / 119.0 > 0.01, "等速轉彎 → 尾尖往彎外偏平均 %.3f m（向心加速度的慣性）" % (lat / 119.0))

	print("\n[F7] Tier 0（關）")
	mod.set("tier", 0)
	await _frames(10)
	_ok(_diff("Tail5") < 1e-4 and _diff("ManeB.L2") < 1e-4, "Tier 0：尾尖與鬃毛與純動畫完全相同（%.6f m）" % _diff("Tail5"))
	mod.set("tier", 2)

	print("\n[F9] 不相容 rig")
	var bad := SecondaryMotionProfile.new()
	var c1 := SecondaryChain.new()
	c1.label = "hair_missing"
	c1.root_bone = "Hair_01"
	c1.tip_bone = "Hair_05"
	var c2 := SecondaryChain.new()
	c2.label = "not_a_chain"
	c2.root_bone = "Tail3"
	c2.tip_bone = "Ear.L"
	bad.chains = [c1, c2]
	mod.set("profile", bad)
	mod.call("_rebuild")
	await _frames(10)
	_ok(int(mod.call("chain_count")) == 0 and _diff("Tail5") < 1e-4, "缺骨名／非父子鏈 → 兩條都停用、骨架＝純動畫（%.6f m）" % _diff("Tail5"))
	print("\n結果：%s（fails=%d）" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _record(key: String, sk: Skeleton3D) -> void:
	var d: Dictionary = _snap[key]
	for b in WATCH:
		d[b] = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b)).origin


## A（有元件）相對 B（純動畫）的骨頭世界位置差（修改器之後的最終姿勢）
func _off(bone: String) -> Vector3:
	var a: Dictionary = _snap["A"]
	var b: Dictionary = _snap["B"]
	if not a.has(bone) or not b.has(bone):
		return Vector3.ZERO
	return (a[bone] as Vector3) - (b[bone] as Vector3)


func _diff(bone: String) -> float:
	return _off(bone).length()
