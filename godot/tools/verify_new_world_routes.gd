extends SceneTree
## 新版地圖接管（2026-10-23）路線驗證：真的 main.tscn、真的傳送區與 _try_portal_interaction。
##   godot --headless --path godot --script res://tools/verify_new_world_routes.gd [-- --routes=v2]
##
## [ROUTE] 新版三圖＋共用室內圖往返：
##   village_v2 → beast_path → shrine_v3 → beast_path → village_v2 → hieda1f → hieda2f → hieda1f → village_v2
##   → kourindou → village_v2
##   每段：current_id 換成預期、落點在回程傳送點附近（≤ 6 m）但不在觸發區內、站在地面上（射線用玩家碰撞遮罩）、
##   膠囊不卡進碰撞體、60 幀後仍在地面（沒穿地往下掉）。
## [LEGACY] 正式流程不變：slice → hieda1f → slice、trail → shrine（舊）、shrine → trail。
## [SEAL] 獸道出口封印在 main 載入後停用碰撞，exit_shrine 支線全段膠囊淨空。
## [STORY] 新版三圖沒有已決定重製的舊劇情觸發器（MQ00/02/03、MQ07–MQ12 的 target）；走完一輪任務與旗標不變。
## [REIMU] 神社 v3 靈夢：模型可見、待機動畫在播、腳底貼地、膠囊不穿物件、互動區涵蓋站位、參道中軸淨空。
## [ALIAS]（--routes=v2 才跑）舊 id 讀檔：trail／slice／shrine 存檔 → 新圖出生點，不沿用舊座標。

var main: Node
var player: CharacterBody3D
var fails := 0
var mode := "legacy"

const OLD_TARGETS := ["trail_leave_clearing", "trail_wolf", "trail_wounded_yokai", "trail_predator_sign",
	"human_village_gate", "gatekeeper_gate", "village_temple_school", "keine_first", "keine_verdict",
	"kosuzu_lending", "akyuu_record", "inn_room"]


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--routes="):
			mode = a.substr(9)
	_run.call_deferred()


func check(tag: String, label: String, ok: bool) -> void:
	print("[%s] %s %s" % [tag, "PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func frames(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame


func ground_at(x: float, z: float, from_y := 400.0, extra: Array[RID] = []) -> float:
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, -200.0, z), player.collision_mask)
	var ex: Array[RID] = [player.get_rid()]
	ex.append_array(extra)
	q.exclude = ex
	var h: Dictionary = space.intersect_ray(q)
	return float(h.position.y) if h.has("position") else -INF


func capsule_hits(pos: Vector3, exclude: Array[RID]) -> Array:
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.2
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis(), pos)
	q.collision_mask = player.collision_mask
	q.exclude = exclude
	var out := []
	for r in space.intersect_shape(q, 8):
		var c: Object = r.get("collider")
		out.append(String((c as Node).get_path()) if c is Node else "?")
	return out


func portal_entry(target: String) -> Dictionary:
	for e in main.get("_live_portals"):
		if String(e.target) == target:
			return e
	return {}


## 把玩家放進指向 target 的傳送區、按傳送，等到 current_id == expect。
func travel(target: String, expect: String, back_target: String) -> bool:
	var from: String = main.get("current_id")
	var e := portal_entry(target)
	if e.is_empty():
		check("ROUTE", "%s 有通往 %s 的傳送區" % [from, target], false)
		return false
	var area: Area3D = e.area
	main.set("portal_cooldown", 0.0)
	player.velocity = Vector3.ZERO
	player.global_position = area.global_position + Vector3(0, -0.6, 0)
	await frames(6)
	var ok: bool = main.call("_try_portal_interaction")
	var n := 0
	while String(main.get("current_id")) != expect and n < 600:
		await frames(1)
		n += 1
	var cur: String = main.get("current_id")
	check("ROUTE", "%s → %s：到達 %s（實際 %s）" % [from, target, expect, cur], ok and cur == expect)
	if cur != expect:
		return false
	await frames(10)
	var p0 := player.global_position
	var back := portal_entry(back_target)
	var d := INF
	if not back.is_empty():
		var bp: Vector3 = (back.area as Area3D).global_position
		d = Vector2(p0.x - bp.x, p0.z - bp.z).length()
	check("ROUTE", "%s 落點在回程傳送點（→%s）旁 1.6–6 m（實 %.2f m）" % [expect, back_target, d], d > 1.6 and d <= 6.0)
	await frames(60)
	var p1 := player.global_position
	var gy := ground_at(p1.x, p1.z, p1.y + 2.0)
	var stand := p1.y - gy
	check("ROUTE", "%s 站在地面（離地 %+.2f m、60 幀下沉 %.2f m、on_floor=%s）" % [expect, stand, p0.y - p1.y, player.is_on_floor()],
		gy != -INF and stand > -0.15 and stand < 0.6 and p1.y > p0.y - 3.0)
	var hits := capsule_hits(p1 + Vector3(0, 1.1, 0), [player.get_rid()])
	check("ROUTE", "%s 落點膠囊不卡碰撞體 %s" % [expect, str(hits)], hits.is_empty())
	return true


func old_story_triggers() -> Array:
	var found := []
	var mr: Node = main.get("map_root")
	for n in mr.find_children("*", "Area3D", true, false):
		var t := String(n.get("quest_target_id")) if "quest_target_id" in n else ""
		if OLD_TARGETS.has(t):
			found.append(t)
	return found


func _run() -> void:
	var ps := load("res://scenes/main.tscn") as PackedScene
	main = ps.instantiate()
	root.add_child(main)
	await frames(3)
	player = main.get("player")
	var qm: Node = root.get_node("/root/QuestManager")
	var sf: Node = root.get_node("/root/StoryFlags")
	var quest0 := str(qm.call("get_active_quest"))
	var flags0 := str(sf.call("serialize")) if sf.has_method("serialize") else ""
	print("[ROUTE] mode=%s" % main.get("router").get("mode"))

	# ───── 新版三圖＋共用室內圖 ─────
	main.call("load_map", "village_v2", "")
	await frames(30)
	var sp := player.global_position
	var sg := ground_at(sp.x, sp.z, sp.y + 2.0)
	check("ROUTE", "village_v2 出生點 (%.1f, %.2f, %.1f) 離地 %+.2f m" % [sp.x, sp.y, sp.z, sp.y - sg], sg != -INF and absf(sp.y - sg) < 0.6)
	check("STORY", "village_v2 無舊劇情觸發器 %s" % str(old_story_triggers()), old_story_triggers().is_empty())
	if await travel("beast_path", "beast_path", "village_v2"):
		check("STORY", "beast_path 無舊劇情觸發器 %s" % str(old_story_triggers()), old_story_triggers().is_empty())
		await seal_checks()
	if await travel("shrine_v3", "shrine_v3", "beast_path"):
		check("STORY", "shrine_v3 無舊劇情觸發器 %s" % str(old_story_triggers()), old_story_triggers().is_empty())
		await reimu_checks()
	await travel("beast_path", "beast_path", "shrine_v3")
	await travel("village_v2", "village_v2", "beast_path")
	await travel("hieda1f", "hieda1f", "slice")
	await travel("hieda2f", "hieda2f", "hieda1f")
	await travel("hieda1f", "hieda1f", "hieda2f")
	await travel("slice", "village_v2", "hieda1f")      # 回程 target 寫 slice → 群組記憶回 village_v2
	await travel("kourindou", "kourindou", "slice")
	await travel("slice", "village_v2", "kourindou")
	check("STORY", "整輪往返後任務不變（%s）" % quest0, str(qm.call("get_active_quest")) == quest0)
	if flags0 != "":
		check("STORY", "整輪往返後 StoryFlags 不變", str(sf.call("serialize")) == flags0)

	# ───── 正式（舊）流程不變 ─────
	if mode == "legacy":
		main.call("load_map", "slice", "")
		await frames(30)
		await travel("hieda1f", "hieda1f", "slice")
		await travel("slice", "slice", "hieda1f")
		main.call("load_map", "trail", "")
		await frames(30)
		await travel("shrine", "shrine", "trail")
		await travel("trail", "trail", "shrine")
	else:
		await alias_checks()

	print("[ROUTE] ═══ 結果：%d 項失敗 ═══" % fails)
	quit(fails)


func seal_checks() -> void:
	var mr: Node = main.get("map_root")
	var seals := []
	for b in mr.find_children("*", "CollisionObject3D", true, false):
		if String(b.get_meta("bp_role", "")) == "exit_seal":
			seals.append(b)
	await frames(2)
	var disabled := 0
	for b in seals:
		for cs in b.find_children("*", "CollisionShape3D", true, false):
			if (cs as CollisionShape3D).disabled:
				disabled += 1
	check("SEAL", "出口封印 %d 處、碰撞已停用 %d 個（open_seals 暫行）" % [seals.size(), disabled], seals.size() > 0 and disabled >= seals.size())
	# exit_shrine 支線（layout）每 0.5 m 膠囊淨空：從 BOSS 場出口到神社傳送點
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/beast_path/layout_beast_path.json"))
	var pts: Array = []
	for b in L["branches"]:
		if String(b["id"]) == "exit_shrine":
			for q in b["points"]:
				pts.append(Vector2(float(q["x"]), float(q["z"])))
	var blocked := []
	var samples := 0
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var c: Vector2 = pts[i + 1]
		var steps := int(ceil(a.distance_to(c) / 0.5))
		for s in steps:
			var p: Vector2 = a.lerp(c, float(s) / steps)
			var g := ground_at(p.x, p.y)
			samples += 1
			var h := capsule_hits(Vector3(p.x, g + 0.45 + 0.9, p.y), [player.get_rid()])
			if not h.is_empty():
				blocked.append("(%.1f,%.1f) %s" % [p.x, p.y, h[0]])
	check("SEAL", "exit_shrine 支線 %d 個取樣、膠囊被擋 %d 處 %s" % [samples, blocked.size(), str(blocked.slice(0, 3))], blocked.is_empty())


func reimu_checks() -> void:
	var mr: Node = main.get("map_root")
	var body := mr.find_child("R1_reimu", true, false) as Node3D
	check("REIMU", "靈夢節點存在", body != null)
	if body == null:
		return
	var npc := body.get_node_or_null("NPC") as Node3D
	await frames(30)
	var ap: AnimationPlayer = npc.get("player") if npc != null else null
	check("REIMU", "模型可見（%s）" % (str(npc.is_visible_in_tree()) if npc else "null"), npc != null and npc.is_visible_in_tree())
	check("REIMU", "待機動畫播放中（%s）" % (ap.current_animation if ap else "無 AnimationPlayer"), ap != null and ap.is_playing() and String(ap.current_animation).begins_with("idle"))
	# 腳底：左右腳趾／腳骨的最低點 vs 地面
	var skel := npc.find_children("*", "Skeleton3D", true, false)
	var low := INF
	var names := []
	if not skel.is_empty():
		var sk := skel[0] as Skeleton3D
		for bi in sk.get_bone_count():
			var bn := sk.get_bone_name(bi)
			if bn.contains("Foot") or bn.contains("Toe"):
				var wp := sk.global_transform * sk.get_bone_global_pose(bi).origin
				if wp.y < low:
					low = wp.y
					names = [bn]
	var bp := body.global_position
	var g := ground_at(bp.x, bp.z, bp.y + 3.0, [(body as CollisionObject3D).get_rid()])   # 排除她自己的膠囊
	check("REIMU", "腳骨最低點 %s 離地 %+.3f m（地面 %.3f）" % [str(names), low - g, g], absf(low - g) < 0.12)
	check("REIMU", "站位原點貼地（%+.3f m）" % (bp.y - g), absf(bp.y - g) < 0.03)
	var hits := capsule_hits(bp + Vector3(0, 0.9, 0), [player.get_rid(), (body as CollisionObject3D).get_rid()])
	check("REIMU", "膠囊不穿物件 %s" % str(hits), hits.is_empty())
	check("REIMU", "參道中軸淨空（|x|=%.2f m ≥ 0.9）" % absf(bp.x), absf(bp.x) >= 0.9)
	# 玩家走到她面前 1.4 m：拜殿拜訪互動區要罩住玩家
	var area := mr.find_child("拜殿拜訪", true, false) as Area3D
	player.velocity = Vector3.ZERO
	player.global_position = bp + Vector3(0.3, 0.2, 1.4)
	await frames(8)
	check("REIMU", "玩家在她面前 1.4 m 時位於「拜訪」互動區內", area != null and area.overlaps_body(player))
	var gp := ground_at(player.global_position.x, player.global_position.z, player.global_position.y + 2.0)
	check("REIMU", "玩家可站到她面前（離地 %+.2f m）" % (player.global_position.y - gp), absf(player.global_position.y - gp) < 0.6)


func alias_checks() -> void:
	var sm: Node = root.get_node("/root/SaveManager")
	for pair in [["trail", "beast_path", Vector3(-13.8, 9.2, -26.8)], ["slice", "village_v2", Vector3(234, 3, 101)], ["shrine", "shrine_v3", Vector3(0, 0.5, 40)]]:
		sm.emit_signal("load_requested", pair[0], pair[2], 0.0)
		await frames(40)
		var cur: String = main.get("current_id")
		var p := player.global_position
		var g := ground_at(p.x, p.z, p.y + 2.0)
		var far := p.distance_to(pair[2]) > 1.0
		check("ALIAS", "讀檔 %s → %s（實 %s）、不沿用舊座標、站在地面（離地 %+.2f）" % [pair[0], pair[1], cur, p.y - g],
			cur == pair[1] and far and g != -INF and absf(p.y - g) < 0.6)
	# 無效／循環：所有新版 meta 的傳送目標都存在、不指向自己
	var router: Object = main.get("router")
	for id in ["village_v2", "beast_path", "shrine_v3", "hieda1f", "kourindou"]:
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.meta.json" % id))
		var ps: Array = meta.get("portals", [])
		for i in ps.size():
			var t: String = router.call("portal_target", id, i, ps[i].get("target"))
			if t == "":
				continue
			var r: String = router.call("resolve_travel", id, t)
			check("ALIAS", "%s 傳送點 %d → %s → %s（存在、非自己）" % [id, i, t, r], r != id and FileAccess.file_exists("res://data/%s.meta.json" % r))
