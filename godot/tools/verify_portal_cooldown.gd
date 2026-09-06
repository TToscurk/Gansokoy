extends SceneTree
## Regression: a portal must still fire if you reach it during the arrival
## cooldown and stay standing inside it.
##
## 真實情境：博麗神社的出生點在 z=49，通往獸道的傳送區在 z=53 —— 疾跑
## 只要 0.6 秒就到，遠短於落地後 2 秒的傳送冷卻。`body_entered` 是一次性
## 訊號，在冷卻中被吞掉之後，玩家站在傳送區裡再也不會觸發第二次，等於
## 卡在門口出不去。

var failures := 0
var main: Node = null
var player: Node = null

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[PORTAL] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _portal(nm: String) -> Area3D:
	for c in main.get_children():
		for g in c.get_children():
			if String(g.name) == nm:
				return g
	return null

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(2)
	main.load_map("shrine", "")
	await _wait(30)
	player = main.get_node_or_null("Player")

	check("we start in 博麗神社", main.current_id == "shrine")
	check("arriving starts a portal cooldown", main.portal_cooldown > 0.0)

	var portal := _portal("Portal_trail")
	check("the shrine has a portal to the trail", portal != null)
	if portal == null:
		print("[PORTAL] failures=%d" % failures)
		quit(maxi(failures, 1))
		return

	# The spawn is close enough that a sprinting player beats the cooldown.
	var dist: float = player.global_position.distance_to(portal.global_position)
	print("[PORTAL] spawn is %.1f m from the portal, cooldown=%.2f s" % [dist, main.portal_cooldown])

	# Step into the portal immediately, while the cooldown is still running.
	player.global_position = Vector3(portal.global_position.x,
		player.global_position.y, portal.global_position.z)
	player.velocity = Vector3.ZERO
	await _wait(3)
	check("the player is standing inside the portal",
		is_instance_valid(portal) and portal.get_overlapping_bodies().has(player))
	check("entering during the cooldown does not teleport yet",
		main.current_id == "shrine" or main.current_id == "trail")

	# Now simply stand still and let the cooldown expire. The transition must
	# happen on its own — the player should never have to walk out and back in.
	await _wait(240)
	print("[PORTAL] after standing still: map=%s cooldown=%.2f" % [main.current_id, main.portal_cooldown])
	check("standing in a portal transports you once the cooldown ends",
		main.current_id == "trail")

	print("[PORTAL] failures=%d" % failures)
	quit(failures)
