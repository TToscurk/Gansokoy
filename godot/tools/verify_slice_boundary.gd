extends SceneTree
## 邊界牆驗證：從場中央往四面八方真的用鍵盤跑，看有沒有人跑得出去。
##   Godot --headless --path godot --script tools/verify_slice_boundary.gd
##
## ⚠ 用 Input.action_press 不是 InputEventAction —— 後者不會讓 Input.get_vector
##   回傳非零向量，角色會原地不動（假通過）。
var main: Node
var fails := 0
var bd: Dictionary = {}


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[BOUND] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _settle(n: int = 4) -> void:
	for i in n:
		await physics_frame
		await process_frame


## 從 start 朝 yaw 方向跑 frames 幀，回傳最終位置
func _run_towards(start: Vector3, yaw: float, frames: int) -> Vector3:
	main.player.velocity = Vector3.ZERO
	main.player.global_position = start
	if main.player.has_method("snap_yaw"):
		main.player.snap_yaw(yaw)
	await _settle(8)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	for i in frames:
		await physics_frame
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await _settle(4)
	return main.player.global_position


func _run() -> void:
	var raw := FileAccess.get_file_as_string("res://data/slice_manual_collision.json")
	var j: Variant = JSON.parse_string(raw)
	if j is Dictionary:
		bd = (j as Dictionary).get("boundary", {})
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _settle(20)
	# 開局獨白會鎖住玩家（input_locked），先演完
	var dm: Node = root.get_node("/root/DialogueManager")
	while dm.is_active():
		var e := InputEventAction.new()
		e.action = "ui_accept"; e.pressed = true
		Input.parse_input_event(e)
		await physics_frame
		e = InputEventAction.new()
		e.action = "ui_accept"; e.pressed = false
		Input.parse_input_event(e)
		await physics_frame
	main.load_map("slice", "")
	await _settle(50)
	check("玩家未被鎖住", not bool(main.player.get("input_locked")))

	var x0 := float(bd.get("min_x", 190.0))
	var x1 := float(bd.get("max_x", 475.0))
	var z0 := float(bd.get("min_z", -210.0))
	var z1 := float(bd.get("max_z", 225.0))
	print("[BOUND] 牆 x[%.0f, %.0f] z[%.0f, %.0f]" % [x0, x1, z0, z1])

	# 中心點出發，四個方向各跑 900 幀（約 15 秒，疾跑約 8 m/s → 120 m）
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var gy := 2.0
	# yaw: 0 = -z(北)、PI = +z(南)、PI/2 與 -PI/2 = 東西
	var dirs := [
		["北 (-z)", 0.0], ["南 (+z)", PI], ["東 (+x)", -PI * 0.5], ["西 (-x)", PI * 0.5],
	]
	for d in dirs:
		var p := await _run_towards(Vector3(cx, gy, cz), float(d[1]), 900)
		var inside: bool = p.x >= x0 - 3.0 and p.x <= x1 + 3.0 \
			and p.z >= z0 - 3.0 and p.z <= z1 + 3.0
		check("往%s 跑 900 幀仍在牆內（%.0f, %.0f）" % [d[0], p.x, p.z], inside)

	# 四個角落各往外斜衝
	var corners := [
		["西北角", Vector3(x0 + 20.0, gy, z0 + 20.0), PI * 0.75],
		["東北角", Vector3(x1 - 20.0, gy, z0 + 20.0), -PI * 0.75],
		["西南角", Vector3(x0 + 20.0, gy, z1 - 20.0), PI * 0.25],
		["東南角", Vector3(x1 - 20.0, gy, z1 - 20.0), -PI * 0.25],
	]
	for c in corners:
		var p := await _run_towards(c[1], float(c[2]), 400)
		var inside: bool = p.x >= x0 - 3.0 and p.x <= x1 + 3.0 \
			and p.z >= z0 - 3.0 and p.z <= z1 + 3.0
		check("%s 往外衝仍在牆內（%.0f, %.0f）" % [c[0], p.x, p.z], inside)

	# 傳送點必須在牆內，否則玩家一落地就卡在牆外
	for p in main.current_portals():
		var px := float(p.x)
		var pz := float(p.z)
		check("傳送點 %s (%.0f, %.0f) 在牆內"
			% [String(p.get("target", "保留")), px, pz],
			px > x0 and px < x1 and pz > z0 and pz < z1)
	print("[BOUND] failures=%d" % fails)
	quit(fails)
