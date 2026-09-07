extends SceneTree
## Regression: 位移方向、身體朝向、步態選擇三者必須一致。
##
## 使用者回報「動畫方向跟移動方向完全顛倒」：按 W 時角色背對位移方向
## （滑向鏡頭）。根因是模型面朝 -basis.z，但 _update_visual_yaw 用
## atan2(d.x,d.z)（無 +PI）算目標朝向；扇區分類與招式前衝也用了
## +basis.z 假設，方向全反。這支測試從外部量，不改內部假設。

var failures := 0
var main: Node = null
var player: Node = null
var cam_pivot: Node3D = null

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[FACING] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _hold(a: String, down: bool) -> void:
	var e := InputEventAction.new()
	e.action = a
	e.pressed = down
	Input.parse_input_event(e)

func _press_combo(a: String, b: String) -> void:
	_hold(a, true)
	_hold(b, true)
	await _wait(6)
	_hold(b, false)
	await _wait(4)
	_hold(a, false)

## 角色面朝向量（模型面朝 -basis.z）
func _body_fwd() -> Vector3:
	var v: Node3D = player.get("_visual")
	var n: Node3D = v if v != null else player
	var f: Vector3 = -n.global_transform.basis.z
	f.y = 0.0
	return f.normalized()

func _ang(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0)))

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("slice", "")
	await _wait(60)
	player = main.get_node("Player")
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	player.global_position = Vector3(235, 0.2, 40)
	cam_pivot = player.get_node("Pivot")
	await _wait(5)

	# --- 八方向：W、A、S、D 與四斜角 -------------------------------
	# 每個 yaw 下按「forward」，位移必須跟鏡頭前向一致、身體最終收斂到
	# 同一個方向（turn_speed 8 rad/s，走 0.5 s 內至少轉 220°）。
	print("[FACING] === 鏡頭 yaw → 位移/身體 一致性 ===")
	for deg_y in [0.0, 45.0, 90.0, 135.0, 180.0, -135.0, -90.0, -45.0]:
		player.velocity = Vector3.ZERO
		cam_pivot.global_rotation.y = deg_to_rad(deg_y)
		# adapter 內部狀態同步（否則會被 lerp 拉回去）
		var adapter: Node = player.get_node("CameraAdapter")
		adapter.set("_target_yaw", deg_to_rad(deg_y))
		adapter.set("_current_yaw", deg_to_rad(deg_y))
		await _wait(2)
		_hold("move_forward", true)
		await _wait(30)  # 0.5 s
		var vel: Vector3 = player.velocity
		vel.y = 0.0
		# 位移方向（這是「玩家實際去了哪裡」）
		var cam_f := -cam_pivot.global_transform.basis.z
		cam_f.y = 0.0
		var v_vs_cam := _ang(vel, cam_f)
		await _wait(40)  # 讓身體收斂
		_hold("move_forward", false)
		var b_vs_v := _ang(_body_fwd(), vel)
		print("[FACING] yaw %4.0f°: 位移vs鏡頭 %5.1f°  身體vs位移 %5.1f°" % [deg_y, v_vs_cam, b_vs_v])
		check("yaw %4.0f°：位移跟隨鏡頭（%5.1f°<25°）" % [deg_y, v_vs_cam], v_vs_cam < 25.0)
		check("yaw %4.0f°：身體面向收斂到位移方向（%5.1f°<25°）" % [deg_y, b_vs_v], b_vs_v < 25.0)
		await _wait(10)

	# --- 步態扇區：往前走選前进步態，往後退才 BackPedal ----------
	print("[FACING] === 扇區動畫 ===")
	player.velocity = Vector3.ZERO
	cam_pivot.global_rotation.y = 0.0
	var ad: Node = player.get_node("CameraAdapter")
	ad.set("_target_yaw", 0.0)
	ad.set("_current_yaw", 0.0)
	await _wait(5)
	_hold("move_forward", true)
	await _wait(40)
	var fwd_state := str(player.get("_sector_state"))
	_hold("move_forward", false)
	await _wait(5)
	print("[FACING] 按 forward 40幀 → sector=%s" % fwd_state)
	check("前進時步態是正向（%s 不是 BackPedal）" % fwd_state, fwd_state != "BackPedal")

	# BackPedal 的真實情境 = 身體還朝著前進方向時速度反向：
	# (a) 正向走動中突然按 S（轉向率 8 rad/s 還沒轉完的窗口）
	# (b) lock-on 中後退（身體被鎖在敵人身上，不跟速度轉）
	# 從静止按 S 不算——身體會同步轉過去，那是 Walk 不是倒退。
	player.velocity = Vector3.ZERO
	await _wait(10)
	_hold("move_forward", true)
	await _wait(45)
	_hold("move_forward", false)
	_hold("move_back", true)
	await _wait(10)  # 速度已反向，身體只轉了 ~12°：這段必須是 BackPedal
	var back_state := str(player.get("_sector_state"))
	await _wait(50)
	_hold("move_back", false)
	print("[FACING] 前進中切後退 → sector=%s" % back_state)
	check("速度反向瞬間步態是 BackPedal（實得 %s）" % back_state, back_state == "BackPedal")

	# --- 招式前衝方向：日之呼吸 spin 不測位移，測重斬 lunge ------
	# 拔刀重斬有前衝；朝位移方向 = 面朝方向。量「衝刺後位移 vs 身體朝向」。
	print("[FACING] === 前衝方向 ===")
	player.global_position = Vector3(235, 0.2, 40)
	player.velocity = Vector3.ZERO
	await _wait(5)
	var pos0: Vector3 = player.global_position
	_hold("attack_heavy", true)
	await _wait(2)
	_hold("attack_heavy", false)
	await _wait(35)
	var disp: Vector3 = player.global_position - pos0
	disp.y = 0.0
	if disp.length() > 0.5:
		var lunge_ang := _ang(disp, _body_fwd())
		print("[FACING] 重斬位移 %.2f m，位移vs身體 %5.1f°" % [disp.length(), lunge_ang])
		check("招式前衝往面朝方向（%5.1f°<60°）" % lunge_ang, lunge_ang < 60.0)
	else:
		print("[FACING] 這一刀沒有位移（跳過前衝檢查）")

	print("[FACING] failures=%d" % failures)
	quit(failures)
