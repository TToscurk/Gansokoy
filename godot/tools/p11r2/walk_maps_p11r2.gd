extends SceneTree
## P11 R2 — 跨ぎ（候補 A）の他地図確認：正式 main.tscn・実際の CharacterBody3D・入力（move_forward）で、
## 人間之里以外の地図の段差（神社の石段・稗田邸の上がり框／2F 階段口・香霖堂）を歩く。場景・玩家ファイル不変。
##   godot --path godot --script res://tools/p11r2/walk_maps_p11r2.gd -- --review=kirisame [--candidate=A] --out=<json>
## 各区間：到達（≤ 0.6 m）・最大の上昇（区間始点の足元から）・止まった位置。
const P11R2Swap := preload("res://tools/p11r2/p11r2_swap.gd")
const LEGS := [
	# [地図, 来た地図（_place_player の from）, [始点 x,z]（null＝到着点のまま）, [[x,z], ...] 経由点]
	["shrine", "", [0.0, 53.0], [[0.0, 44.0], [0.0, 20.0], [0.0, 0.5], [0.0, -9.0], [0.0, -12.5], [0.0, -18.0], [0.0, -23.0]]],
	["shrine", "", [0.0, -23.0], [[0.0, -18.0], [0.0, -12.5], [0.0, -9.0], [0.0, 0.5], [0.0, 20.0]]],
	["hieda1f", "slice", null, [[0.0, 2.0], [0.0, 0.0], [-4.0, -3.0], [-8.2, -4.9]]],
	["kourindou", "slice", null, [[50.0, 8.0], [40.0, 6.0], [30.0, 4.0]]],
]

var main: Node
var player: CharacterBody3D
var adapter: Node


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var out := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var cand := P11R2Swap.parse(OS.get_cmdline_user_args())
	var R := {"candidate": cand, "legs": []}
	if cand != "":
		R["swapped"] = P11R2Swap.apply(main, cand)
		print("[P11R2] candidate ", R["swapped"])
	root.add_child(main)
	current_scene = main
	var t0 := Time.get_ticks_msec()
	while true:
		await physics_frame
		player = main.get("player")
		if player and String(main.get("current_id")) == "village_v2" and player.is_on_floor():
			break
		if Time.get_ticks_msec() - t0 > 120000:
			quit(2)
			return
	adapter = player.get_node("CameraAdapter")
	adapter.set_process_unhandled_input(false)
	player.set_process_unhandled_input(false)
	R["step_height"] = player.get("step_height")
	var fails := 0
	for L: Array in LEGS:
		if String(main.get("current_id")) != String(L[0]):
			main.call("load_map", String(L[0]), String(L[1]))
			for i in 90:
				await physics_frame
		if L[2] != null:
			var s: Array = L[2]
			await _place(Vector2(float(s[0]), float(s[1])))
		var rec := await _walk(L[3])
		rec["map"] = L[0]
		R["legs"].append(rec)
		if not rec["arrived_all"]:
			fails += 1
		print("[MAPS] %-10s 到達 %s 区間 %s 最大上昇 %.2f m 終点 %s" % [L[0], rec["arrived_all"], str(rec["reached"]), rec["max_rise"], str(rec["end"])])
	R["fails"] = fails
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(R, "\t") + "\n")
		f.close()
	print("[MAPS] 結果：%d 区間、%d 未到達" % [LEGS.size(), fails])
	quit(0 if fails == 0 else 1)


func _place(q: Vector2) -> void:
	var sp := player.get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(Vector3(q.x, 60.0, q.y), Vector3(q.x, -60.0, q.y), player.collision_mask)
	rq.exclude = [player.get_rid()]
	var r := sp.intersect_ray(rq)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(q.x, (float((r["position"] as Vector3).y) if not r.is_empty() else 2.0) + 0.1, q.y)
	for i in 30:
		await physics_frame


func _walk(wps: Array) -> Dictionary:
	var y0 := player.global_position.y
	var maxr := 0.0
	var reached: Array = []
	var ok := true
	for w: Array in wps:
		var b := Vector2(float(w[0]), float(w[1]))
		var t0 := Time.get_ticks_msec()
		var hist: Array = []
		var arrived := false
		while Time.get_ticks_msec() - t0 < 20000:
			var p := Vector2(player.global_position.x, player.global_position.z)
			if p.distance_to(b) < 0.6:
				arrived = true
				break
			var d := b - p
			adapter.set("_target_yaw", atan2(-d.x, -d.y))
			Input.action_press("move_forward")
			await physics_frame
			maxr = maxf(maxr, player.global_position.y - y0)
			hist.append(p)
			if hist.size() > 150:
				hist.pop_front()
				if (hist[-1] as Vector2).distance_to(hist[0]) < 0.15:
					break
		Input.action_release("move_forward")
		reached.append(arrived)
		if not arrived:
			ok = false
			break
	for i in 10:
		await physics_frame
	var e := player.global_position
	return {"arrived_all": ok, "reached": reached, "max_rise": snappedf(maxr, 0.01), "end": [snappedf(e.x, 0.01), snappedf(e.y, 0.01), snappedf(e.z, 0.01)]}
