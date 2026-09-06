extends SceneTree
## Playtest: can you actually WALK from 博麗神社 to 人間之里?
##
## Drives the real controller through the real InputMap (move_forward + sprint),
## steering by rotating an input-yaw node — no teleporting, no velocity pokes.
## The route is shrine → (portal) → trail → (portal) → village.

const RUN_TIMEOUT := 400.0        # 每段的模擬秒數上限
## 傳送 Area3D 的半徑只有 1.6 m（main.gd `_spawn_portals`）——停在 3 m 外
## 會「走到門口卻沒進門」，所以要走進去而不是走到附近。
const ARRIVE_RADIUS := 1.0
const STUCK_WINDOW := 4.0         # 連續這麼久幾乎沒前進 = 卡住
const STUCK_DIST := 1.0

var failures := 0
var main: Node = null
var player: Node = null
var yaw: Node3D = null
var _log: Array = []


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[WALK] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _hold(action: String, down: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = down
	Input.parse_input_event(e)


## 直線撞到東西（獸道有 7000 棵個別樹）時，往旁邊繞。
## 這模擬玩家會做的事：看到樹就繞過去，而不是站著推它。
var _detour := 0.0
var _detour_side := 1.0
var _detour_angle := 70.0  # 每次起繞重設，不累加

func _steer(target: Vector3) -> void:
	var d: Vector3 = target - player.global_position
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return
	d = d.normalized()

	if _detour > 0.0:
		_detour -= get_root().get_process_delta_time()
		d = d.rotated(Vector3.UP, deg_to_rad(_detour_angle) * _detour_side)
	elif _blocked_ahead(d):
		# 挑左右比較空的一側繞；兩側都堵就加大角度。
		# ⚠ 角度必須在「繞成功後」歸位，否則會一路斜著走、連空曠處都偏航
		#   （第一版忘了重置，神社 4 m 的短程都會失敗）。
		var angle := 70.0
		_detour_side = 1.0
		if _blocked_ahead(d.rotated(Vector3.UP, deg_to_rad(70.0))):
			_detour_side = -1.0
			if _blocked_ahead(d.rotated(Vector3.UP, deg_to_rad(-70.0))):
				# 兩側都堵：改用大角度，左右各再試一次。
				angle = 115.0
				_detour_side = 1.0 if not _blocked_ahead(
					d.rotated(Vector3.UP, deg_to_rad(115.0))) else -1.0
		_detour_angle = angle
		_detour = 0.9 if angle < 100.0 else 1.4

	# move_forward 送出 (0,0,-1)，旋轉 yaw 後即為世界方向。
	yaw.rotation.y = atan2(-d.x, -d.z)


func _blocked_ahead(dir: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = main.get_viewport().get_world_3d().direct_space_state
	var from: Vector3 = player.global_position + Vector3(0, 0.9, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 2.6)
	q.collide_with_areas = false
	q.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	if not hit.has("normal"):
		return false
	# 斜坡不算阻擋，只有近乎垂直的面（樹幹、牆）才繞。
	return absf(Vector3(hit.normal).y) < 0.55


## 走向一個世界座標直到換圖（expect_map）或抵達。
## 回傳 {arrived, seconds, distance, reason}。
func _walk_to(target: Vector3, label: String, expect_map: String = "") -> Dictionary:
	var t := 0.0
	var last_check := 0.0
	var last_pos: Vector3 = player.global_position
	var best := INF
	_hold("sprint", true)
	_hold("move_forward", true)
	while t < RUN_TIMEOUT:
		_steer(target)
		await physics_frame
		await process_frame
		t += get_root().get_process_delta_time()
		var flat: Vector3 = player.global_position
		var to := Vector3(target.x - flat.x, 0.0, target.z - flat.z)
		var dist := to.length()
		best = minf(best, dist)
		# 換圖才算真的過去了；只是站到傳送區旁邊不算。
		if expect_map != "" and main.current_id == expect_map:
			_hold("move_forward", false)
			_hold("sprint", false)
			return {"arrived": true, "seconds": t, "distance": dist, "reason": "transitioned to %s" % expect_map}
		if expect_map == "" and dist <= ARRIVE_RADIUS:
			_hold("move_forward", false)
			_hold("sprint", false)
			return {"arrived": true, "seconds": t, "distance": dist, "reason": "reached"}
		# 掉出世界
		if player.global_position.y < -80.0:
			_hold("move_forward", false)
			_hold("sprint", false)
			return {"arrived": false, "seconds": t, "distance": dist, "reason": "fell out of the world at y=%.1f" % player.global_position.y}
		# 卡住偵測
		if t - last_check >= STUCK_WINDOW:
			var moved := last_pos.distance_to(player.global_position)
			if moved < STUCK_DIST:
				_hold("move_forward", false)
				_hold("sprint", false)
				return {"arrived": false, "seconds": t, "distance": dist,
					"reason": "stuck at %s (moved %.2f m in %.1f s)" % [_v(player.global_position), moved, STUCK_WINDOW]}
			last_pos = player.global_position
			last_check = t
			_log.append("  %s t=%5.1f pos=%s dist=%6.1f" % [label, t, _v(player.global_position), dist])
	_hold("move_forward", false)
	_hold("sprint", false)
	return {"arrived": false, "seconds": t, "distance": best, "reason": "timed out after %.0f s" % RUN_TIMEOUT}


func _v(p: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [p.x, p.y, p.z]


func _portal_in_current_map(target_id: String) -> Vector3:
	var meta: Dictionary = _load_meta(main.current_id)
	for p in meta.get("portals", []):
		if String(p.get("target", "")) == target_id:
			return Vector3(float(p.x), float(p.y), float(p.z))
	return Vector3.INF


func _load_meta(id: String) -> Dictionary:
	var f := FileAccess.open("res://data/%s.meta.json" % id, FileAccess.READ)
	if f == null:
		return {}
	var j: Variant = JSON.parse_string(f.get_as_text())
	return j if j is Dictionary else {}


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	# main.gd 讀 --map= 決定起圖；這裡直接強制從神社出發。
	await process_frame
	await process_frame
	main.load_map("shrine", "")
	for i in 30:
		await physics_frame
		await process_frame

	player = main.get_node_or_null("Player")
	check("the world loader booted", main != null and player != null)
	check("we start in 博麗神社", main.current_id == "shrine")
	if player == null or main.current_id != "shrine":
		print("[WALK] failures=%d" % failures)
		quit(maxi(failures, 1))
		return

	# 用一個 yaw 節點把 move_forward 轉成任意世界方向（走的是真的輸入路徑）。
	yaw = Node3D.new()
	main.add_child(yaw)
	player.input_yaw_node = yaw

	print("[WALK] 起點 %s @ %s" % [main.current_id, _v(player.global_position)])

	# --- 第一段：神社 → 通往獸道的傳送區 -------------------------------
	var p1 := _portal_in_current_map("trail")
	check("神社有通往獸道的傳送區", p1 != Vector3.INF)
	if p1 == Vector3.INF:
		print("[WALK] failures=%d" % failures)
		quit(maxi(failures, 1))
		return
	print("[WALK] 段1 神社→獸道口 目標=%s" % _v(p1))
	var r1: Dictionary = await _walk_to(p1, "shrine", "trail")
	print("[WALK] 段1 %s (%.1f s, 剩 %.1f m)" % [r1.reason, r1.seconds, r1.distance])
	check("能從神社走到獸道傳送區：%s" % r1.reason, r1.arrived)

	# 傳送需要幾幀
	for i in 30:
		await physics_frame
		await process_frame
	print("[WALK] 傳送後所在=%s @ %s" % [main.current_id, _v(player.global_position)])
	check("走進傳送區後真的到了獸道", main.current_id == "trail")
	if main.current_id != "trail":
		for line in _log:
			print("[WALK]" + line)
		print("[WALK] failures=%d" % failures)
		quit(maxi(failures, 1))
		return

	# --- 第二段：獸道南下 → 人里口 -------------------------------------
	# 獸道南端已改指 slice（village.tscn 是凍結的舊基線）。
	var p2 := _portal_in_current_map("slice")
	check("獸道有通往人間之里（slice）的傳送區", p2 != Vector3.INF)
	if p2 != Vector3.INF:
		print("[WALK] 段2 獸道→人里口 目標=%s（全長約 %.0f m）"
			% [_v(p2), player.global_position.distance_to(p2)])
		var r2: Dictionary = await _walk_to(p2, "trail", "slice")
		print("[WALK] 段2 %s (%.1f s, 剩 %.1f m)" % [r2.reason, r2.seconds, r2.distance])
		check("能從獸道走到人里傳送區：%s" % r2.reason, r2.arrived)

		for i in 30:
			await physics_frame
			await process_frame
		print("[WALK] 傳送後所在=%s @ %s" % [main.current_id, _v(player.global_position)])
		check("走完獸道後真的到了人間之里", main.current_id == "slice")

		# --- 落地檢查：不能卡在半空或地底 ---------------------------
		if main.current_id == "slice":
			for i in 60:
				await physics_frame
				await process_frame
			check("在人間之里站得住（沒有無限下墜）", player.global_position.y > -20.0)
			check("在人間之里踩得到地面", player.is_on_floor())
			print("[WALK] 人里落地 %s on_floor=%s" % [_v(player.global_position), str(player.is_on_floor())])

	for line in _log:
		print("[WALK]" + line)
	print("[WALK] failures=%d" % failures)
	quit(failures)
