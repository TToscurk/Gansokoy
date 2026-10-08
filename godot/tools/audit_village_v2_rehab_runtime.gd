extends SceneTree
## P10 R5–R6 MASTER AUDIT：P0 邊界／傳送落點的實機測試（只讀；不寫場景／封存）。
##   Godot --headless --path godot --script res://tools/audit_village_v2_rehab_runtime.gd -- --review=kirisame --out=<json>
## 正式 main.tscn（ReviewStart → village_v2）、真實 CharacterBody3D 玩家與輸入動作（move_forward＋sprint＋jump）。
##  walls  ：對每個邊界測點，把玩家放在邊緣內 6 m（測試用放置，非審圖走訪）、視線朝外，跑＋連跳 3.5 s，
##           記錄朝外最遠座標、最低 y、是否越出 frame。PASS＝不越出 frame 且 y > −10。
##  portals：照 main.gd 的 headless 換圖路徑（load_map(target, "village_v2")），記錄落點與 4 s 內最低 y／是否著地。
const FX0 := 0.0
const FX1 := 560.0
const FZ0 := -340.0
const FZ1 := 220.0
## [name, x, z, outward dir x, outward dir z]
const PTS := [
	["N_river_exit", 390.0, -334.0, 0.0, -1.0], ["N_hill", 200.0, -334.0, 0.0, -1.0], ["N_east", 470.0, -334.0, 0.0, -1.0],
	["S_canal_exit", 289.0, 214.0, 0.0, 1.0], ["S_stream_exit", 122.0, 214.0, 0.0, 1.0], ["S_portal_forest", 224.0, 214.0, 0.0, 1.0],
	["E_river_exit", 554.0, -112.0, 1.0, 0.0], ["E_farm_flat", 554.0, -50.0, 1.0, 0.0], ["E_south", 554.0, 100.0, 1.0, 0.0],
	["W_ridge", 6.0, -100.0, -1.0, 0.0], ["W_south", 6.0, 150.0, -1.0, 0.0],
	["C_NW", 6.0, -334.0, -0.7071, -0.7071], ["C_SE", 554.0, 214.0, 0.7071, 0.7071], ["C_NE", 554.0, -334.0, 0.7071, -0.7071], ["C_SW", 6.0, 214.0, -0.7071, 0.7071],
]

var main: Node
var player: CharacterBody3D
var adapter: Node
var R := {"walls": [], "portals": []}

func _initialize() -> void:
	_go.call_deferred()

func _p(s: String) -> void:
	print("[RT] " + s)

func _go() -> void:
	var out := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var t0 := Time.get_ticks_msec()
	while true:
		await physics_frame
		player = main.get("player")
		if player and String(main.get("current_id")) == "village_v2" and player.is_on_floor():
			break
		if Time.get_ticks_msec() - t0 > 120000:
			_p("boot timeout")
			quit(2)
			return
	for i in 30:
		await physics_frame
	adapter = player.get_node_or_null("CameraAdapter")
	if adapter:
		adapter.set_process_unhandled_input(false)
	player.set_process_unhandled_input(false)
	R["boot"] = {"ms": Time.get_ticks_msec() - t0, "map": String(main.get("current_id")), "pos": _v(player.global_position),
		"collision_layer": player.collision_layer, "collision_mask": player.collision_mask,
		"floor_max_deg": snappedf(rad_to_deg(player.floor_max_angle), 0.1)}
	_p("boot " + JSON.stringify(R["boot"]))
	for pt in PTS:
		R["walls"].append(await _wall(pt))
	# portals
	for tgt in ["trail", "hieda1f", "kourindou"]:
		R["portals"].append(await _portal(tgt))
	var fails := 0
	for w: Dictionary in R["walls"]:
		if not w["pass"]:
			fails += 1
	for p: Dictionary in R["portals"]:
		if p["void_fall"]:
			fails += 1
	R["fail_count"] = fails
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(R, "\t"))
		f.close()
	_p("done fails=%d" % fails)
	quit(0)

func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)]

func _ground(x: float, z: float) -> float:
	var sp := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 150.0, z), Vector3(x, -80.0, z))
	q.exclude = [player.get_rid()]
	var h := sp.intersect_ray(q)
	return float(h["position"].y) if not h.is_empty() else NAN

func _release() -> void:
	for a in ["move_forward", "sprint", "jump"]:
		Input.action_release(a)

func _wall(pt: Array) -> Dictionary:
	_release()
	var x := float(pt[1])
	var z := float(pt[2])
	var dir := Vector2(float(pt[3]), float(pt[4])).normalized()
	var g := _ground(x, z)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(x, g + 0.4, z)
	var yaw := atan2(-dir.x, -dir.y)
	if adapter:
		adapter.set("_target_yaw", yaw)
		adapter.set("_current_yaw", yaw)
	for i in 20:
		await physics_frame
	var max_out := -INF
	var min_y := INF
	var outside := false
	var ticks := 0
	while ticks < 210:
		if adapter:
			adapter.set("_target_yaw", yaw)
		Input.action_press("move_forward")
		Input.action_press("sprint")
		if ticks % 40 == 10:
			Input.action_press("jump")
		elif ticks % 40 == 14:
			Input.action_release("jump")
		await physics_frame
		ticks += 1
		var p := player.global_position
		var o := p.x * dir.x + p.z * dir.y
		max_out = maxf(max_out, o)
		min_y = minf(min_y, p.y)
		if p.x < FX0 or p.x > FX1 or p.z < FZ0 or p.z > FZ1:
			outside = true
	_release()
	var fp := player.global_position
	var rec := {"name": pt[0], "start": [x, snappedf(g, 0.01), z], "final": _v(fp), "min_y": snappedf(min_y, 0.01),
		"left_frame": outside, "pass": (not outside) and min_y > -10.0}
	_p("wall %s %s final %s min_y %.2f" % [pt[0], "PASS" if rec["pass"] else "FAIL", str(rec["final"]), min_y])
	return rec

func _portal(tgt: String) -> Dictionary:
	_release()
	main.call("load_map", tgt, "village_v2")
	for i in 3:
		await physics_frame
	var arrive := player.global_position
	var min_y := INF
	var floor_t := -1.0
	for i in 240:
		await physics_frame
		min_y = minf(min_y, player.global_position.y)
		if floor_t < 0.0 and player.is_on_floor():
			floor_t = i / 60.0
	var fin := player.global_position
	var g_under := _ground(fin.x, fin.z)
	var rec := {"target": tgt, "map_now": String(main.get("current_id")), "arrival": _v(arrive), "final": _v(fin), "min_y_4s": snappedf(min_y, 0.01),
		"on_floor_after_s": snappedf(floor_t, 0.01), "ground_under_final": snappedf(g_under, 0.01) if not is_nan(g_under) else null,
		"void_fall": min_y < -30.0 or (floor_t < 0.0 and is_nan(g_under))}
	_p("portal %s arrival %s final %s min_y %.2f floor_t %.2f void=%s" % [tgt, str(rec["arrival"]), str(rec["final"]), min_y, floor_t, rec["void_fall"]])
	# 回 village_v2
	main.call("load_map", "village_v2", "")
	for i in 30:
		await physics_frame
	return rec
