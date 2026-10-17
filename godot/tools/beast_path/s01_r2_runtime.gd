extends SceneTree
## 獸道 S01 R2：遊戲標記的實機（runtime）檢查——走正式 main.tscn 的載圖／出生／傳送流程，不改任何遊戲系統。
##   godot --path godot --script res://tools/beast_path/s01_r2_runtime.gd -- --map=beast_path --out=<json>
## 1) 出生：玩家站在 meta.spawn 附近的地面上（射線第一個碰到的是地形，不是岩或樹）
## 2) 傳送：站進 Portal_Village 按 portal_enter（呼叫 main 的同一個函式）→ 到人間之里 V2
## 3) 回到獸道（village_v2→beast_path，main._travel 的正式路徑；V2 端的傳送點目前被 meta 停用，所以用同一個函式直接觸發）
##    抵達點在地面上、不在岩裡；重複進出 3 次，抵達點一致、WallDressing 沒有重複
## 4) BOSS 標記：BossTrigger／BossSpawn／PlayerSpawn_Arena 存在於 S04（遊戲腳本目前沒有使用 BossTrigger——只記錄、不改系統）

var main: Node
var player: CharacterBody3D
var res := {"checks": []}


func _initialize() -> void:
	_go.call_deferred()


func _ck(name: String, ok: bool, detail: String) -> void:
	res["checks"].append({"name": name, "ok": ok, "detail": detail})
	print("[RT] %s %-28s %s" % ["PASS" if ok else "FAIL", name, detail])


func _wait_map(id: String, ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await physics_frame
		player = main.get("player")
		if player != null and String(main.get("current_id")) == id and not bool(main.get("_traveling")) and player.is_on_floor():
			for i in 10:
				await physics_frame
			return true
	return false


func _ground_hit(p: Vector3) -> Dictionary:
	var sp := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 30.0, p.z), Vector3(p.x, p.y - 30.0, p.z))
	q.exclude = [player.get_rid()]
	var h := sp.intersect_ray(q)
	if h.is_empty():
		return {}
	var col: Node = h["collider"]
	var chain := ""
	var n: Node = col
	for k in 4:
		if n == null:
			break
		chain = String(n.name) + ("/" + chain if chain != "" else "")
		n = n.get_parent()
	return {"y": float((h["position"] as Vector3).y), "collider": chain}


## main 的 _live_portals（_try_portal_interaction 用的同一份清單）裡往 village_v2 的傳送區
func _find_portal() -> Node3D:
	for e: Dictionary in main.get("_live_portals"):
		if String(e.get("target", "")) == "village_v2" and is_instance_valid(e.get("area")):
			return e["area"]
	return null


func _wall_count() -> int:
	var mr: Node = main.get("map_root")
	return mr.find_children("WallDressing", "Node3D", true, false).size() if mr != null else -1


func _go() -> void:
	var out := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var ok_load := await _wait_map("beast_path", 120000)
	_ck("load.beast_path", ok_load, "main.tscn --map=beast_path 進圖、玩家著地")
	if not ok_load:
		_finish(out)
		return
	# ---- 1) 出生
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/beast_path.meta.json"))
	var sp: Dictionary = meta["spawn"]
	var p := player.global_position
	var g := _ground_hit(p)
	var dxz := Vector2(p.x, p.z).distance_to(Vector2(float(sp["x"]), float(sp["z"])))
	var on_terrain := String(g.get("collider", "")).contains("S01_Entrance") or String(g.get("collider", "")).to_lower().contains("terrain")
	_ck("spawn.position", dxz < 1.0 and not g.is_empty() and absf(p.y - float(g["y"])) < 1.5, "玩家 (%.2f, %.2f, %.2f)，meta.spawn (%.1f, %.1f) 水平差 %.2f m；腳下 %s y=%.2f" % [p.x, p.y, p.z, float(sp["x"]), float(sp["z"]), dxz, str(g.get("collider", "—")), float(g.get("y", NAN))])
	_ck("spawn.on_terrain", on_terrain, "出生點腳下第一個碰撞體＝%s（要求＝S01 地形，不是谷壁岩／樹）" % str(g.get("collider", "—")))
	var wc0 := _wall_count()
	_ck("scene.wall_dressing_once", wc0 == 1, "map_root 裡的 WallDressing 節點 %d 個（要求 1）" % wc0)
	# ---- 2) S01 → 人間之里（Portal_Village）
	var portal: Node3D = _find_portal()
	_ck("portal.exists", portal != null, "S01 的往人間之里傳送區 %s" % (str(portal.global_position) if portal != null else "（沒有）"))
	var arrivals: Array = []
	for round_i in 3:
		if portal == null:
			break
		player.global_position = portal.global_position + Vector3(0, 0.3, 0)
		player.velocity = Vector3.ZERO
		for i in 8:
			await physics_frame
		main.set("portal_cooldown", 0.0)
		var fired: bool = main.call("_try_portal_interaction")
		var ok_v := fired and await _wait_map("village_v2", 120000)
		_ck("portal.to_village#%d" % (round_i + 1), ok_v, "站進傳送區按 portal_enter → current_id＝%s" % String(main.get("current_id")))
		if not ok_v:
			break
		# ---- 3) 回到獸道
		main.set("portal_cooldown", 0.0)
		main.call("_travel", "beast_path", "village_v2")
		var ok_b := await _wait_map("beast_path", 120000)
		var pa := player.global_position
		var ga := _ground_hit(pa)
		arrivals.append(pa)
		var on_t := String(ga.get("collider", "")).contains("S01_Entrance") or String(ga.get("collider", "")).to_lower().contains("terrain")
		_ck("reenter.beast_path#%d" % (round_i + 1), ok_b and on_t and absf(pa.y - float(ga.get("y", -999.0))) < 1.5 and _wall_count() == 1,
			"回到獸道：玩家 (%.2f, %.2f, %.2f)；腳下 %s；WallDressing %d 個" % [pa.x, pa.y, pa.z, str(ga.get("collider", "—")), _wall_count()])
		portal = _find_portal()
	if arrivals.size() >= 2:
		var spread := 0.0
		for q: Vector3 in arrivals:
			spread = maxf(spread, q.distance_to(arrivals[0]))
		_ck("reenter.consistent", spread < 0.5, "%d 次回到獸道的抵達點最大差 %.3f m" % [arrivals.size(), spread])
	# ---- 4) BOSS 標記（S04 未改；遊戲腳本目前不讀 BossTrigger）
	var mr: Node = main.get("map_root")
	var names := ["BossTrigger", "BossSpawn", "PlayerSpawn_Arena"]
	var found := {}
	for nm in names:
		var nd := mr.find_child(nm, true, false) as Node3D
		found[nm] = str(nd.global_position.snapped(Vector3.ONE * 0.01)) if nd != null else "（沒有）"
	_ck("boss.markers_present", not found.values().has("（沒有）"), "S04 標記：%s" % str(found))
	_finish(out)


func _finish(out: String) -> void:
	var fails := 0
	for c: Dictionary in res["checks"]:
		if not bool(c["ok"]):
			fails += 1
	res["fails"] = fails
	print("[RT] ══ %d 項、%d 失敗 ══" % [(res["checks"] as Array).size(), fails])
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(res, "\t") + "\n")
		f.close()
	quit(0 if fails == 0 else 1)
