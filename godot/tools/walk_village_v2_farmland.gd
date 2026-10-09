extends SceneTree
## P8 pilot player's actual movement along a bund in the loaded village.
## --zone：全區新構件（r6 生成器）玩家 1.7 m 實走＋TPS 相機淨空＋10:00 玩家視角代表畫面（可見網格當探針，不加碰撞）。
## --cost：同一鏡位 P8 開／關 A/B 幀成本（frame time、render CPU／GPU、primitives、draw calls、objects）。
## --no-shots：只驗不拍（回歸用，不覆寫已封存的 ART_REVIEW 截圖）。
## P8 runtime production budget（使用者 2026-10-01 核准）：--cost 每鏡位 P8 增量 GPU ≤ 4 ms（一般）、T1_eye ≤ 6 ms（最差代表鏡位硬上限）、
##   render CPU ≤ 4 ms；任一超出 → exit 1。
## --feeder：取水水路（r5：短落とし樋＋土渠＋FarmPath_1 路下伏越し＋地面木槽）對 FarmPath_1／稗田邸入口前空地的
##   玩家與 TPS 相機淨空（實際 main.tscn＋玩家＋SpringArm）。路權內不得有任何取水構件（地上或架空）。
const TARGET := Vector2(380.0, 52.0)
const FARM := "Districts/FarmlandEast/FarmlandP8"
const FL := preload("res://tools/village_v2_farmland_lib.gd")
const PROBE_LAYER := 1 << 31      # 可見網格探針（玩家、SpringArm、地面射線都不碰此層）
const SHOT_DIR := "../docs/art_review/village_v2_p8_farmland/"
const BUDGET_GPU_MS := 4.0         # 一般玩家鏡位 P8 GPU 增量上限
const BUDGET_GPU_WORST_MS := 6.0   # 最差代表鏡位（WORST_VIEW）硬上限
const BUDGET_CPU_MS := 4.0         # P8 render CPU 增量上限
const WORST_VIEW := "T1_eye"
const HEAD := 1.7                 # 玩家膠囊頂（CapsuleShape3D height 1.7，底在腳下）
const HEADROOM_MIN := 2.0         # 步行淨高門檻＝膠囊 1.7＋0.3
# 相機淨空＝近裁面四角半徑＋1 cm（近裁面碰到可見網格才會切面穿模）；由實際 Camera3D near／fov／畫面比算出。
# SpringArm3D 預設以相機 pyramid shape 做 cast_motion，實測斜角會越過碰撞盒面約 0.3 m（引擎行為，
# 所有牆面皆同），故不能拿「相機離碰撞 ≥ margin」當判準。
# 路權（layout_v2.json）：FarmPath_1 x=372 half_w 1.2；FarmPath_4 z=0 half_w 1.2（x 340–556，這裡量到 412）；
# 稗田邸大宅門 LANDMARK_HIEDA_GATE (398,−10) 寬 7 m → 門前到 FarmPath_4 的門前通道；PORTAL_HIEDA1F (398,2) 傳送圓盤 r 1.6＋0.6
const CORRIDORS := {"FarmPath_1": Rect2(370.8, -12.0, 2.4, 24.0), "FarmPath_4": Rect2(340.0, -1.2, 72.0, 2.4),
	"HiedaGateApron": Rect2(394.5, -9.0, 7.0, 7.8)}
const PORTAL := Vector3(398.0, 2.0, 2.2)      # x, z, 淨空半徑
const POST_GAP_MIN := 1.2                     # 支柱列可穿越：相鄰柱對淨距 ≥ 膠囊直徑 0.6 × 2
var main: Node
var player: CharacterBody3D
var fails := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var flags := root.get_node("/root/StoryFlags")
	flags.set_flag("woke_in_trail", true)
	flags.set_flag("met_reimu", true)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 60:
		await process_frame
	main.load_map("village_v2", "trail")
	for i in 90:
		await process_frame
	player = main.player
	if player == null or main.map_root.get_node_or_null("Districts/FarmlandEast/FarmlandP8") == null:
		push_error("[FARM_WALK] map/player/overlay missing")
		quit(2)
		return
	var debug: Node = main.map_root.get_node_or_null("Debug")
	if debug:
		debug.visible = false
	# 診斷（P9 R2 起）：--hide-forest 先隱藏 P9 林帶 overlay，用來分離「林帶本身」與「P8 A/B 增量」的成本
	if "--hide-forest" in OS.get_cmdline_user_args():
		var fo: Node = main.map_root.get_node_or_null("Vegetation/ForestP9")
		if fo:
			(fo as Node3D).visible = false
	if "--zone" in OS.get_cmdline_user_args():
		await _zone()
		print("[ZONE] result: %d failed" % fails)
		quit(1 if fails > 0 else 0)
		return
	if "--cost" in OS.get_cmdline_user_args():
		await _cost()
		print("[COST] 結果：%d 項失敗（P8 runtime budget）" % fails)
		quit(1 if fails > 0 else 0)
		return
	if "--feeder-negative" in OS.get_cmdline_user_args():
		quit(await _feeder_negative())
		return
	if "--feeder" in OS.get_cmdline_user_args():
		await _feeder()
		print("[FEEDER] result: %d failed" % fails)
		quit(1 if fails > 0 else 0)
		return
	player.global_position = Vector3(380.0, 1.5, 13.0)
	player.velocity = Vector3.ZERO
	for i in 30:
		await physics_frame
	print("[FARM_WALK] start=%s" % player.global_position)
	await _capture("arrival")
	Input.action_press("move_forward")
	var max_deviation := 0.0
	var arrived := false
	for f in 60 * 30:
		var p := Vector2(player.global_position.x, player.global_position.z)
		var d := TARGET - p
		if d.length() < 2.0:
			arrived = true
			break
		if f % 6 == 0:
			player.snap_yaw(atan2(-d.x, -d.y))
		await physics_frame
		max_deviation = maxf(max_deviation, absf(player.global_position.x - 380.0))
	Input.action_release("move_forward")
	await _capture("bund_end")
	var overview := Camera3D.new()
	root.add_child(overview)
	overview.global_position = Vector3(404.0, 52.0, 29.0)
	overview.look_at(Vector3(404.0, 0.1, 29.0), Vector3.FORWARD)
	overview.current = true
	await _capture("overview")
	overview.queue_free()
	print("[FARM_WALK] arrived=%s pos=%s lateral=%.2fm" % [arrived, player.global_position, max_deviation])
	quit(0 if arrived and max_deviation < 2.0 else 1)

func _capture(tag: String) -> void:
	if "--no-shots" in OS.get_cmdline_user_args():
		return
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := (ProjectSettings.globalize_path("res://") + "../docs/art_review/village_v2_p8_farmland/pilot_%s.png" % tag).simplify_path()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := root.get_texture().get_image().save_png(path)
	print("[FARM_WALK] capture %s: %s" % [tag, error_string(err)])


# ───────────────────────── --feeder：掛樋淨空 ─────────────────────────

func _chk(label: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("[FEEDER] %s %s：%s" % ["PASS" if ok else "FAIL", label, detail])

## 可見掛樋方塊（BoxMesh）：[world→local, local AABB, 名稱]
func _flume_boxes() -> Array:
	var out: Array = []
	for n in main.map_root.get_node(FARM + "/FieldDetails/WaterSupply").find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		out.append([mi.global_transform.affine_inverse(), mi.mesh.get_aabb(), mi.global_transform, String(mi.get_parent().name) + "/" + String(mi.name)])
	return out

## 點到 OBB 的距離（0＝在內）
func _obb_dist(b: Array, p: Vector3) -> float:
	var lp: Vector3 = (b[0] as Transform3D) * p
	var ab: AABB = b[1]
	var c := Vector3(clampf(lp.x, ab.position.x, ab.end.x), clampf(lp.y, ab.position.y, ab.end.y), clampf(lp.z, ab.position.z, ab.end.z))
	return ((b[2] as Transform3D) * c).distance_to(p)

## 線段 p→q 與 OBB 相交（slab）
func _seg_hits(b: Array, p: Vector3, q: Vector3) -> bool:
	var inv: Transform3D = b[0]
	var o := inv * p
	var d := inv * q - o
	var ab: AABB = b[1]
	var t0 := 0.0
	var t1 := 1.0
	for i in 3:
		if absf(d[i]) < 1e-9:
			if o[i] < ab.position[i] or o[i] > ab.end[i]:
				return false
		else:
			var ta := (ab.position[i] - o[i]) / d[i]
			var tb := (ab.end[i] - o[i]) / d[i]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				return false
	return true

## 垂直線 (x,z) 上可見掛樋最低下緣（無則 INF）
func _underside(boxes: Array, x: float, z: float, y0: float) -> float:
	var lo := INF
	for b: Array in boxes:
		var inv: Transform3D = b[0]
		var o := inv * Vector3(x, y0, z)
		var d := inv.basis * Vector3.UP
		var ab: AABB = b[1]
		var t0 := 0.0
		var t1 := 50.0
		var hit := true
		for i in 3:
			if absf(d[i]) < 1e-9:
				if o[i] < ab.position[i] or o[i] > ab.end[i]:
					hit = false
					break
			else:
				var ta := (ab.position[i] - o[i]) / d[i]
				var tb := (ab.end[i] - o[i]) / d[i]
				t0 = maxf(t0, minf(ta, tb))
				t1 = minf(t1, maxf(ta, tb))
				if t0 > t1:
					hit = false
					break
		if hit:
			lo = minf(lo, y0 + t0)
	return lo

func _ground(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 30.0, z), Vector3(x, -30.0, z))
	q.collision_mask = 0x7FFFFFFF & ~PROBE_LAYER
	q.exclude = [player.get_rid()]
	var ss := player.get_world_3d().direct_space_state
	for i in 8:
		var r := ss.intersect_ray(q)
		if r.is_empty():
			return NAN
		var col := r["collider"] as Node
		if col != null and String(col.name) != "WaterSupply":
			return (r["position"] as Vector3).y
		q.exclude = q.exclude + [r["rid"]]
	return NAN

func _feeder() -> void:
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var boxes := _flume_boxes()
	var body := main.map_root.get_node(FARM + "/Irrigation/WaterSupply") as StaticBody3D
	print("[FEEDER] 可見方塊 %d、碰撞形狀 %d" % [boxes.size(), body.get_child_count()])
	# 1) 可見支柱都有碰撞（柱身中段點查詢打得到 FeederFlume）
	var ss := player.get_world_3d().direct_space_state
	var posts := 0
	var uncovered: Array = []
	for b: Array in boxes:
		if not String(b[3]).contains("/Post_"):
			continue
		posts += 1
		var c: Vector3 = (b[2] as Transform3D) * (b[1] as AABB).get_center()
		var pq := PhysicsPointQueryParameters3D.new()
		pq.position = c
		var hit := false
		for r: Dictionary in ss.intersect_point(pq, 8):
			if r["collider"] == body:
				hit = true
		if not hit:
			uncovered.append("%s@(%.2f,%.2f)" % [b[3], c.x, c.z])
	_chk("post_collision", uncovered.is_empty(), "可見支柱 %d 根，無碰撞 %d：%s" % [posts, uncovered.size(), "；".join(uncovered.slice(0, 6))])
	# 1b) R5b.1 系統狀態（使用者 2026-10-10「P8 FEEDER 驗證不能僅因節點不可見就放行」）：
	#   取水構件全部可見、碰撞形全部有效、碰撞體有層；撤去済みの r5 高架落とし樋（Chute／ChuteJoint／HeadBearer／Support）の残骸 0。
	#   runtime overlay が P8 の部材を隠す／碰撞を止めると、ここで FAIL。
	await _supply_state(body)
	# 1c) 水源連通（竜骨車）：取水口が水渠水面下かつ渠底より上、樋底は岸坡の地面より上、吐き口 → 送り樋 → 落とし桝 → 上段土渠 → 伏越し → 木槽 → 內渠 の水位が単調に下がる
	_source_chain()
	# 1d) 竜骨車と他層の干渉：可見網格の頂点（P7 河岸・P9 植生・水車・P10 overlay・NPC）と MultiMesh 実例（草）が竜骨車の部材 OBB に入らない
	_ryukotsu_clear(boxes)
	# 2) 走廊內：支柱不落在路權內、樋下淨高（10 cm 格）
	for cn: String in CORRIDORS:
		var R: Rect2 = CORRIDORS[cn]
		var min_room := INF
		var at := Vector2.ZERO
		var cells := 0
		var blocked: Array = []
		var x := R.position.x
		while x <= R.end.x + 1e-6:
			var z := R.position.y
			while z <= R.end.y + 1e-6:
				var g := _ground(x, z)
				var u := _underside(boxes, x, z, g - 0.5)
				if u < INF:
					cells += 1
					var room := u - g
					if room < min_room:
						min_room = room
						at = Vector2(x, z)
					if room < 0.05 and blocked.size() < 4:
						blocked.append("(%.1f,%.1f)" % [x, z])
				z += 0.1
			x += 0.1
		_chk("route_clear_" + cn, cells == 0,
			"路權內取水構件覆蓋 %d 格（地上＋架空，門檻 0）%s" % [cells, "" if cells == 0 else "；最低淨高 %.2f m @(%.1f,%.1f)" % [min_room, at.x, at.y]])
	# 2b) 傳送圓盤淨空：圓盤＋0.6 m 內不得有支柱／樋體落地；支柱列（入口前 FarmPath_4 以北的非路權空地）可穿越
	var near_portal := INF
	var post_x: Array = []
	for bx: Array in boxes:
		var c: Vector3 = (bx[2] as Transform3D) * (bx[1] as AABB).get_center()
		if String(bx[3]).contains("/Post_1"):
			post_x.append(c.x)
		if String(bx[3]).contains("/Post_"):
			near_portal = minf(near_portal, Vector2(c.x, c.z).distance_to(Vector2(PORTAL.x, PORTAL.y)) - 0.045)
	var room_portal := INF
	for k in 72:
		for r: float in [0.0, 0.8, 1.6, PORTAL.z]:
			var q := Vector2(PORTAL.x, PORTAL.y) + Vector2.from_angle(TAU * k / 72.0) * r
			var g := _ground(q.x, q.y)
			room_portal = minf(room_portal, _underside(boxes, q.x, q.y, g - 0.5) - g)
	_chk("portal_clear", near_portal >= PORTAL.z and room_portal >= HEADROOM_MIN,
		"PORTAL_HIEDA1F 最近支柱 %.2f m（門檻 %.1f）；圓盤＋0.6 m 內樋下淨高 %s" % [near_portal, PORTAL.z, "無樋覆蓋" if room_portal == INF else "%.2f m" % room_portal])
	# 取水構件最高點（稗田邸前視覺：不得有架空水槽；架空只留水渠岸坡的落とし樋）
	var top_east := -INF
	for bx: Array in boxes:
		var c: Vector3 = (bx[2] as Transform3D) * (bx[1] as AABB).get_center()
		if c.x > 345.0:
			top_east = maxf(top_east, ((bx[2] as Transform3D) * (bx[1] as AABB)).end.y - _ground(c.x, c.z))
	_chk("low_profile_east_of_345", top_east <= 0.45, "x > 345（上段土渠起點以東、含 FarmPath_1／稗田邸前）取水構件離地最高 %.2f m（門檻 0.45：與田埂同級、無架空）" % top_east)
	# 3) 實走：FarmPath_1 由南往北走過伏越し（路面下）；大宅門前往北經木槽跨渠板進 W1；沿木槽外側東西向
	await _walk_leg("walk_FarmPath_1", Vector2(372.0, -8.0), Vector2(372.0, 14.0), boxes)
	await _walk_leg("walk_HiedaFront", Vector2(398.0, -7.0), Vector2(397.8, 12.0), boxes)
	await _walk_leg("walk_TroughSide", Vector2(376.0, 5.1), Vector2(402.0, 5.1), boxes)
	# 4) 起跳：路權／木槽旁不得有看不見的天花板（撞頂＝false）
	for jp: Vector2 in [Vector2(372.0, 6.25), Vector2(386.6, 4.85), Vector2(397.8, 6.2)]:
		await _jump_test(jp, boxes)
	# 5) TPS 相機：12 方位 × 5 俯仰 × 3 臂長
	await _camera_sweep(boxes)

## R5b.1 永久反向：取水構件を runtime で隠す／碰撞を止める／撤去済みの高架樋が残る → supply_system_state は各案で必ず FAIL
func _feeder_negative() -> int:
	var body := main.map_root.get_node(FARM + "/Irrigation/WaterSupply") as StaticBody3D
	var ws: Node = main.map_root.get_node(FARM + "/FieldDetails/WaterSupply")
	var names := ["N1 竜骨車の樋を runtime 非表示（ROUND 3 の WaterLifeP10 と同じ手口）", "N2 竜骨車の柱の碰撞形を停止", "N3 撤去済みの高架落とし樋 Chute_0 が残る"]
	var miss := 0
	for i in names.size():
		_neg_case(i, true, ws, body)
		var f0 := fails
		await _supply_state(body)
		var tripped := fails > f0
		fails = f0
		_neg_case(i, false, ws, body)
		print("[FEEDER-NEG] %s：%s" % [names[i], "PASS（gate 正確失敗）" if tripped else "FAIL（gate 沒抓到）"])
		if not tripped:
			miss += 1
	var f1 := fails
	await _supply_state(body)
	var clean := fails == f1
	print("[FEEDER-NEG] 復元後の正常状態：%s" % ("PASS" if clean else "FAIL"))
	print("[FEEDER-NEG] result: 反向 %d/%d" % [names.size() - miss, names.size()])
	return 0 if miss == 0 and clean else 1

func _neg_case(i: int, on: bool, ws: Node, body: StaticBody3D) -> void:
	match i:
		0:
			(ws.get_node("Ryukotsu/Trough") as Node3D).visible = not on
		1:
			(body.get_node("Post_00") as CollisionShape3D).disabled = on
		2:
			if on:
				var n := Node3D.new()
				n.name = "Chute_0"
				ws.add_child(n)
			else:
				ws.get_node("Chute_0").free()

## R5b.1：取水構件の可視／碰撞の実状態
func _supply_state(body: StaticBody3D) -> void:
	var ws: Node = main.map_root.get_node(FARM + "/FieldDetails/WaterSupply")
	var hidden: Array = []
	var dead: Array = []
	for n in ws.find_children("*", "", true, false):
		var nm := String(n.name)
		if nm.begins_with("Chute") or nm.begins_with("Support_") or nm == "HeadBearer":
			dead.append(String(ws.get_path_to(n)))
		if n is VisualInstance3D and not (n as VisualInstance3D).is_visible_in_tree():
			hidden.append(String(ws.get_path_to(n)))
	var disabled: Array = []
	for s in body.get_children():
		var nm := String(s.name)
		if nm.begins_with("Chute"):
			dead.append("Irrigation/WaterSupply/" + nm)
		if s is CollisionShape3D and ((s as CollisionShape3D).disabled or (s as CollisionShape3D).shape == null):
			disabled.append(nm)
	var ok := hidden.is_empty() and disabled.is_empty() and dead.is_empty() and body.collision_layer != 0 and body.is_visible_in_tree() and body.process_mode != Node.PROCESS_MODE_DISABLED
	_chk("supply_system_state", ok, "非表示の取水構件 %d%s；無効な碰撞形 %d%s；撤去済み高架樋の残骸 %d%s；碰撞層 %d" % [hidden.size(), "" if hidden.is_empty() else "（" + "、".join(hidden.slice(0, 4)) + "）",
		disabled.size(), "" if disabled.is_empty() else "（" + "、".join(disabled.slice(0, 4)) + "）", dead.size(), "" if dead.is_empty() else "（" + "、".join(dead.slice(0, 4)) + "）", body.collision_layer])

## P2 水渠水面（Water/*Canal* 網格）の (x, z) 最寄り頂点の y
func _canal_water(x: float, z: float) -> float:
	var best := INF
	var wy := NAN
	for mi in main.map_root.get_node("Water").find_children("*", "MeshInstance3D", true, false):
		if not String(mi.name).to_lower().contains("canal"):
			continue
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			for v: Vector3 in m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p := m.global_transform * v
				var d := Vector2(p.x - x, p.z - z).length()
				if d < best:
					best = d
					wy = p.y
	return wy

func _source_chain() -> void:
	var lo: Vector3 = FL.RYU_LOW
	var hi: Vector3 = FL.RYU_HIGH
	var cw := _canal_water(lo.x, lo.z)
	var bed := _ground(lo.x, lo.z)
	var lax := lo + FL.ryu_basis() * Vector3(0, FL.RYU_DRUM_UP, 0)
	var g_box := _ground(FL.DROP_BOX.x + 0.6, FL.DROP_BOX.y)       # 桝の東（土渠側）の 0.20 階面
	var box_w := g_box + FL.UPPER_LIFT + 0.01
	var box_top := g_box + 0.24
	# 樋底と地面（岸坡）：水面より上に出ている区間で樋底板の下面 ≥ 地面＋0.10
	var min_c := INF
	var at := 0.0
	for k in range(0, 41):
		var t := k / 40.0
		var q := lo.lerp(hi, t)
		var g := _ground(q.x, q.z)
		if q.y - 0.04 > cw and not is_nan(g):
			var c := q.y - 0.04 - g
			if c < min_c:
				min_c = c
				at = q.x
	# 送り樋：樋底板の下面 ≥ 地面＋0.15、上端の樋は送り樋の底に入り込まない、張り出しは桝の壁頂より上・桝の内側
	var fa: Vector3 = FL.FEED[0]
	var fb: Vector3 = FL.FEED[1]
	var min_f := INF
	for k in range(0, 21):
		var q := fa.lerp(fb, k / 20.0)
		min_f = minf(min_f, q.y - 0.04 - _ground(q.x, q.z))
	var t_nest := (fa.x - lo.x) / (hi.x - lo.x)
	var nest_gap := lerpf(lo.y, hi.y, t_nest) - 0.04 - fa.y
	var chain := [["竜骨車 吐き口（樋底上端）", hi.y], ["送り樋 水面 始", fa.y + 0.06], ["送り樋 水面 末", fb.y + 0.06], ["落とし桝 水面", box_w],
		["上段土渠 水面", g_box + FL.UPPER_LIFT], ["伏越し入口桝", FL.SIPHON_WATER[0]], ["伏越し出口桝", FL.SIPHON_WATER[1]],
		["木槽 水面 始", FL.TROUGH_BOT[0] + FL.TROUGH_DEPTH], ["木槽 水面 末", FL.TROUGH_BOT[1] + FL.TROUGH_DEPTH], ["內渠 水面", FL.CH_WATER_S]]
	var mono := true
	var txt: Array = ["水渠水面 %.2f" % cw]
	for i in chain.size():
		txt.append("%s %.3f" % [chain[i][0], float(chain[i][1])])
		if i > 0 and float(chain[i][1]) > float(chain[i - 1][1]) + 1e-4:
			mono = false
	var intake_ok := lo.y <= cw - 0.15 and lax.y - 0.13 >= bed + 0.10 and lo.y - 0.04 >= bed + 0.20
	var lift_ok := hi.y >= box_w + 0.15
	var spout_ok := fb.y - 0.04 > box_top + 0.005 and absf(fb.x - FL.DROP_BOX.x) < 0.25 and absf(fb.z - FL.DROP_BOX.y) < 0.25
	_chk("source_ryukotsu", intake_ok and lift_ok and spout_ok and min_c >= 0.10 and min_f >= 0.15 and nest_gap >= 0.0 and mono and not is_nan(cw),
		"取水口 樋底 %.2f（水渠水面 %.2f の %.2f m 下、渠底 %.2f の %.2f m 上、下車の下端 %.2f）；必要揚程 %.2f m（水面→落とし桝水面）、吐き口まで %.2f m；"
		% [lo.y, cw, cw - lo.y, bed, lo.y - 0.04 - bed, lax.y - 0.13, box_w - cw, hi.y - cw]
		+ "傾斜 %.1f°・樋長 %.2f m；岸坡上の樋底板下面－地面 最小 %.2f m（x %.1f）；送り樋下面－地面 最小 %.2f m；上端の入り込み隙間 %.3f m；張り出し下面 %.2f > 桝壁頂 %.2f；水位鎖 %s：%s"
		% [rad_to_deg(atan2(hi.y - lo.y, Vector2(hi.x - lo.x, hi.z - lo.z).length())), (hi - lo).length(), min_c, at, min_f, nest_gap, fb.y - 0.04, box_top, "単調減少" if mono else "逆流あり", " → ".join(txt)])

func _ryukotsu_clear(boxes: Array) -> void:
	var ryu: Array = boxes.filter(func(b: Array) -> bool: return String(b[3]).begins_with("Ryukotsu") or String(b[3]).begins_with("Trough/") or String(b[3]).begins_with("Feed/"))
	var region := AABB(Vector3(329.5, -3.0, 2.5), Vector3(10.5, 6.0, 5.0))
	var skip := ["Terrain", "Water", "Debug", "Collision"]
	var hits := {}
	var nverts := 0
	for mi in main.map_root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var path := String(main.map_root.get_path_to(m))
		if path.get_slice("/", 0) in skip or path.contains("/WaterSupply/") or path.contains("/Ground/") or path.contains("LOD1") or path.contains("LOD2") or path.contains("LOD3"):
			continue
		var ab: AABB = m.global_transform * m.get_aabb()
		if not ab.intersects(region):
			continue
		for s in m.mesh.get_surface_count():
			for v: Vector3 in m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p := m.global_transform * v
				if not region.has_point(p):
					continue
				nverts += 1
				for bx: Array in ryu:
					if _obb_dist(bx, p) < 0.03:
						hits[path] = int(hits.get(path, 0)) + 1
						break
	var mm_hits := {}
	var nmm := 0
	for mi in main.map_root.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := mi as MultiMeshInstance3D
		if mmi.multimesh == null or not mmi.is_visible_in_tree():
			continue
		var ab: AABB = mmi.global_transform * mmi.get_aabb()
		if not ab.intersects(region):
			continue
		var mm := mmi.multimesh
		var top := mm.mesh.get_aabb().end.y if mm.mesh else 0.3
		for i in mm.instance_count:
			var xf := mmi.global_transform * mm.get_instance_transform(i)
			if not region.has_point(xf.origin):
				continue
			nmm += 1
			var tip := xf * Vector3(0, top, 0)
			for bx: Array in ryu:
				if _seg_hits(bx, xf.origin, tip):
					var key := String(main.map_root.get_path_to(mmi))
					mm_hits[key] = int(mm_hits.get(key, 0)) + 1
					break
	_chk("ryukotsu_overlay_clear", hits.is_empty() and mm_hits.is_empty() and ryu.size() > 0,
		"竜骨車の部材 OBB %d 個；周辺の可見網格頂点 %d のうち部材内 %s；MultiMesh 実例 %d のうち部材を貫く %s" % [ryu.size(), nverts, str(hits) if not hits.is_empty() else "0", nmm, str(mm_hits) if not mm_hits.is_empty() else "0"])

func _place(p: Vector2, yaw: float) -> void:
	player.global_position = Vector3(p.x, _ground(p.x, p.y) + 0.05, p.y)
	player.velocity = Vector3.ZERO
	player.snap_yaw(yaw)
	for i in 20:
		await physics_frame

func _walk_leg(label: String, a: Vector2, b: Vector2, boxes: Array) -> void:
	var d0 := b - a
	await _place(a, atan2(-d0.x, -d0.y))
	Input.action_press("move_forward")
	var dev := 0.0
	var arrived := false
	var head_in := 0
	var dir := d0.normalized()
	for f in 60 * 25:
		var p := Vector2(player.global_position.x, player.global_position.z)
		var d := b - p
		if d.length() < 1.0:
			arrived = true
			break
		if f % 6 == 0:
			player.snap_yaw(atan2(-d.x, -d.y))
		await physics_frame
		var rel := p - a
		dev = maxf(dev, absf(rel.x * dir.y - rel.y * dir.x))
		for bx: Array in boxes:
			if _obb_dist(bx, player.global_position + Vector3(0, HEAD - 0.05, 0)) < 0.001:
				head_in += 1
				break
	Input.action_release("move_forward")
	for i in 10:
		await physics_frame
	_chk(label, arrived and dev < 0.6 and head_in == 0, "抵達=%s、橫偏 %.2f m、頭部穿入樋體 %d 幀、終點 %s" % [arrived, dev, head_in, player.global_position])

func _jump_test(p: Vector2, boxes: Array) -> void:
	await _place(p, 0.0)
	var g := player.global_position.y
	var room := _underside(boxes, p.x, p.y, g) - g
	player.request_jump()
	var top := g
	var head_in := 0
	var ceiling := false
	for f in 120:
		await physics_frame
		top = maxf(top, player.global_position.y)
		ceiling = ceiling or player.is_on_ceiling()
		for bx: Array in boxes:
			if _obb_dist(bx, player.global_position + Vector3(0, HEAD - 0.02, 0)) < 0.001:
				head_in += 1
				break
	_chk("jump_(%.1f,%.1f)" % [p.x, p.y], head_in == 0 and not ceiling, "樋下淨高 %.2f m、起跳頂高 %.2f m（頭頂 %.2f m）、撞頂=%s、頭部穿入樋體 %d 幀" % [room, top - g, top - g + HEAD, ceiling, head_in])

func _camera_sweep(boxes: Array) -> void:
	var adapter := player.get_node("CameraAdapter")
	var arm := player.get_node("Pivot/SpringArm3D") as SpringArm3D
	var pivot := player.get_node("Pivot") as Node3D
	var pts := {"FP1_siphon": Vector2(372.0, 6.25), "FP1_south": Vector2(372.0, 1.5), "FP1_north": Vector2(372.0, 9.0),
		"portal": Vector2(398.0, 2.0), "gate_front": Vector2(398.0, -6.0), "trough_cross": Vector2(397.8, 5.2),
		"trough_mid": Vector2(386.6, 5.3), "chute_side": Vector2(339.0, 3.2), "ryu_head_n": Vector2(337.0, 6.9)}
	var cam0 := root.get_viewport().get_camera_3d()
	var vs := Vector2(root.get_viewport().get_visible_rect().size)
	var hh := cam0.near * tan(deg_to_rad(cam0.fov) * 0.5)
	var CAM_CLEAR := Vector3(cam0.near, hh, hh * vs.x / vs.y).length() + 0.01
	var worst := INF
	var worst_at := ""
	var bad := 0
	var occl := 0
	var n := 0
	var bad_by := {}
	var shots := {"FP1_siphon": [0.0, -0.18, 8.5], "portal": [PI, -0.18, 8.5], "trough_mid": [-PI * 0.5, -0.25, 6.0], "chute_side": [-PI * 0.75, -0.2, 6.0]}
	for pn: String in pts:
		var p: Vector2 = pts[pn]
		await _place(p, 0.0)
		for yi in 12:
			var yaw := TAU * yi / 12.0
			for pitch: float in [-1.1, -0.6, -0.18, 0.3, 0.55]:
				for dist: float in [3.0, 8.5, 16.0]:
					adapter._target_yaw = yaw
					adapter._current_yaw = yaw
					adapter._target_pitch = pitch
					adapter._current_pitch = pitch
					adapter._target_distance = dist
					adapter._current_distance = dist
					pivot.global_position = player.global_position + Vector3(0, adapter.pivot_height, 0)
					pivot.rotation = Vector3(pitch, yaw, 0)
					arm.spring_length = dist
					await physics_frame
					await physics_frame
					var cam := root.get_viewport().get_camera_3d()
					var cp := cam.global_position
					n += 1
					var near := INF
					var nm := ""
					for bx: Array in boxes:
						var dd := _obb_dist(bx, cp)
						if dd < near:
							near = dd
							nm = bx[3]
					if near < worst:
						worst = near
						worst_at = "%s yaw %d° pitch %.2f arm %.1f → %s" % [pn, int(rad_to_deg(yaw)), pitch, dist, nm]
					if near < CAM_CLEAR:
						bad += 1
						var part := String(nm).get_slice("/", 1).get_slice("_", 0)
						var key := "%s:%s" % [pn, part]
						bad_by[key] = int(bad_by.get(key, 0)) + 1
						var hit_arm := arm.get_hit_length() < dist - 0.01
						bad_by["arm_hit=" + str(hit_arm)] = int(bad_by.get("arm_hit=" + str(hit_arm), 0)) + 1
					var eye := player.global_position + Vector3(0, 1.2, 0)
					for bx: Array in boxes:
						if _seg_hits(bx, cp, eye):
							occl += 1
							break
	_chk("tps_camera", bad == 0, "近裁面四角半徑＋1 cm＝%.3f m；%d 個相機姿勢（%d 點 × 12 方位 × 5 俯仰 × 臂長 3／8.5／16 m）；距取水構件 < %.3f m 的姿勢 %d；最近 %.2f m（%s）；掛樋擋在相機與玩家胸口之間 %d 姿勢（%.1f %%，資訊）" % [CAM_CLEAR, n, pts.size(), CAM_CLEAR, bad, worst, worst_at, occl, 100.0 * occl / maxf(1, n)])
	print("[FEEDER] camera near-miss breakdown: %s" % str(bad_by))
	# 代表畫面（遊戲實際 TPS 相機）
	for sn: String in shots:
		var v: Array = shots[sn]
		await _place(pts[sn], v[0])
		adapter._target_pitch = v[1]
		adapter._current_pitch = v[1]
		adapter._target_distance = v[2]
		adapter._current_distance = v[2]
		for i in 40:
			await process_frame
		await _capture("supply_tps_" + sn)


# ───────────────────────── --zone：全區新構件 ─────────────────────────
# 可見網格探針：ZoneIrrigation（跨路桝／伏越し／落差工／取水／排水口／支渠堰與跨渠板）與 ZoneDetails 的水口、落水口、農具，
# 每個 MeshInstance3D 以 ConcavePolygonShape3D 掛在 PROBE_LAYER（玩家、SpringArm、地面射線都不碰）→
# 玩家身體穿入可見構件、相機近裁面碰到可見構件都用實際形狀查詢判定（不是 AABB）。
# 支渠水面／渠床帶（LateralBed／LateralWater、Ditch*）是貼地水面，只算相機、不算身體。

var probe_root: Node3D
var _probe_names := {}

func _probe_meshes(base: Node) -> int:
	var n := 0
	for m in base.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var faces := mi.mesh.get_faces()
		if faces.size() < 3:
			continue
		var sb := StaticBody3D.new()
		sb.collision_layer = PROBE_LAYER
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var sh := ConcavePolygonShape3D.new()
		sh.backface_collision = true
		sh.set_faces(faces)
		cs.shape = sh
		sb.add_child(cs)
		probe_root.add_child(sb)
		sb.global_transform = mi.global_transform
		var rel := String(base.get_path_to(mi))
		# 貼地面片（水面、渠床帶、溝床；合併後名字是 Merged_N，故以幾何判定）：≥ 95 % 三角面近水平
		var horiz := 0
		for t in range(0, faces.size(), 3):
			var nrm := (faces[t + 1] - faces[t]).cross(faces[t + 2] - faces[t])
			if nrm.length() < 1e-9 or absf(nrm.normalized().y) > 0.85:
				horiz += 1
		var flat := horiz >= int(0.95 * faces.size() / 3.0)
		var mat := mi.get_active_material(0)
		var tag := ""
		if mat:
			tag = mat.resource_name if mat.resource_name != "" else (mat.resource_path.get_file() if mat.resource_path != "" else (String((mat as ShaderMaterial).shader.resource_path.get_file()) if mat is ShaderMaterial and (mat as ShaderMaterial).shader else mat.get_class()))
		var wab := mi.global_transform * mi.mesh.get_aabb()
		_probe_names[sb.get_rid()] = [String(base.name) + "/" + rel + "{%s h%.2f}" % [tag, wab.size.y], flat]
		n += 1
	return n

func _probe_hits(shape: Shape3D, xf: Transform3D, bodies_only: bool) -> Array:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = xf
	q.collision_mask = PROBE_LAYER
	var out: Array = []
	for r: Dictionary in player.get_world_3d().direct_space_state.intersect_shape(q, 16):
		var info: Array = _probe_names.get(r["rid"], ["?", false])
		if bodies_only and info[1]:
			continue
		out.append(info[0])
	return out

var _skip_walk := false
func _zone_walk(label: String, a: Vector2, b: Vector2) -> void:
	if _skip_walk:
		return
	var d0 := b - a
	await _place(a, atan2(-d0.x, -d0.y))
	var body := CapsuleShape3D.new()
	body.radius = 0.28
	body.height = 1.45                 # 腳上 0.2 m 起算（腳底踩構件頂不算穿入；小腿以上穿過可見構件才算）
	Input.action_press("move_forward")
	var dev := 0.0
	var arrived := false
	var clip := 0
	var clip_by := {}
	var dir := d0.normalized()
	var ymax := -INF
	var ymin := INF
	for f in 60 * 25:
		var p := Vector2(player.global_position.x, player.global_position.z)
		var d := b - p
		if d.length() < 0.8:
			arrived = true
			break
		if f % 6 == 0:
			player.snap_yaw(atan2(-d.x, -d.y))
		await physics_frame
		var rel := p - a
		dev = maxf(dev, absf(rel.x * dir.y - rel.y * dir.x))
		ymax = maxf(ymax, player.global_position.y)
		ymin = minf(ymin, player.global_position.y)
		var hits := _probe_hits(body, Transform3D(Basis.IDENTITY, player.global_position + Vector3(0, 0.2 + 1.45 * 0.5, 0)), true)
		if not hits.is_empty():
			clip += 1
			for h: String in hits:
				clip_by[h] = int(clip_by.get(h, 0)) + 1
	Input.action_release("move_forward")
	for i in 10:
		await physics_frame
	_zchk(label, arrived and dev < 0.6 and clip == 0, "抵達=%s、橫偏 %.2f m、身體穿入可見構件 %d 幀%s、高程 %.2f–%.2f m、終點 (%.1f, %.1f)" % [
		arrived, dev, clip, "" if clip_by.is_empty() else str(clip_by.keys().slice(0, 3)), ymin, ymax, player.global_position.x, player.global_position.z])

func _zchk(label: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("[ZONE] %s %s：%s" % ["PASS" if ok else "FAIL", label, detail])

## 群組可見網格世界 AABB 中心
func _gcenter(n: Node) -> Vector3:
	var ab := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var w := mi.global_transform * mi.mesh.get_aabb()
		ab = w if first else ab.merge(w)
		first = false
	return ab.get_center()

func _road_dir(c: Vector2) -> Vector2:
	var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/village_v2/layout_v2.json"))
	var best := INF
	var dir := Vector2.RIGHT
	for r: Dictionary in L["roads"]:
		var pts: Array = r["pts"]
		for i in pts.size() - 1:
			var p0 := Vector2(pts[i][0], pts[i][1])
			var p1 := Vector2(pts[i + 1][0], pts[i + 1][1])
			var q := Geometry2D.get_closest_point_to_segment(c, p0, p1)
			if q.distance_to(c) < best:
				best = q.distance_to(c)
				dir = (p1 - p0).normalized()
	return dir

func _zone() -> void:
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var fp: Node = main.map_root.get_node(FARM)
	var zi: Node = fp.get_node("ZoneWorks/ZoneIrrigation")
	var zd: Node = fp.get_node("ZoneWorks/ZoneDetails")
	probe_root = Node3D.new()
	probe_root.name = "ZoneProbe"
	main.map_root.add_child(probe_root)
	var np := _probe_meshes(zi)
	for c in zd.get_children():
		var cn := String(c.name)
		if cn.begins_with("Inlet_") or cn.begins_with("Outlet_") or cn == "FarmTools":
			np += _probe_meshes(c)
	for i in 3:
		await physics_frame
	var P := FL.plan()
	var Z: Dictionary = P["zone"]
	print("[ZONE] 探針網格 %d；跨階連接 %d、取水 %d、排水口 %d" % [np, Z["links"].size(), Z["feeders"].size(), Z["outfalls"].size()])
	# 1) 玩家 1.7 m 實走（實際 CharacterBody3D＋輸入）
	var cam_pts := {}
	var only := ""
	for u in OS.get_cmdline_user_args():
		if u.begins_with("--only="):
			only = u.trim_prefix("--only=")
	_skip_walk = only != "" and only != "walk"
	for ln: Dictionary in Z["links"]:
		var nm := String(ln["name"])
		if ln["kind"] == "road":
			var A: Vector2 = ln["A"]
			var B: Vector2 = ln["B"]
			var mid := (A + B) * 0.5
			var rd := _road_dir(mid)
			await _zone_walk("walk_%s（沿 %s 走過路下管段）" % [nm, ln["road"]], mid - rd * 9.0, mid + rd * 9.0)
			var lk := (B - A).normalized()
			cam_pts[nm + "_road"] = mid
			cam_pts[nm + "_inlet"] = A - lk * 0.0 + rd * 1.35          # 伏越し入口桝旁（路肩）
			cam_pts[nm + "_outlet"] = B + rd * 1.35
		else:
			var O: Vector2 = ln["O"]
			var I: Vector2 = ln["I"]
			var path: PackedVector2Array = ln["path"]
			var pm := path[0].lerp(path[path.size() - 1], 0.5)
			var pd := (path[path.size() - 1] - path[0]).normalized()
			var mid := pm + pd * 1.6              # 板堰本體有碰撞（玩家繞過）；在堰旁 1.6 m 橫越落水溝
			var n := pd.orthogonal()
			await _zone_walk("walk_%s（堰旁橫越落差溝）" % nm, mid - n * 5.0, mid + n * 5.0)
	for f: Dictionary in Z["feeders"]:
		var tl: PackedVector2Array = f["trough"]
		var bx: Vector2 = f["box"]
		for i in tl.size() - 1:
			var t := (tl[i + 1] - tl[i]).normalized()
			var side := t.orthogonal() * 1.25
			# 走木槽外側（取遠離水車那側）
			if (tl[i] + side).distance_to(bx) < (tl[i] - side).distance_to(bx):
				side = -side
			await _zone_walk("walk_Feeder_%s_槽側%d" % [f["block"], i], tl[i] + side + t * 0.6, tl[i + 1] + side - t * 0.6)
		var t0 := (tl[1] - tl[0]).normalized()
		cam_pts["WW_%s_dropbox" % f["block"]] = bx + t0.orthogonal() * 1.3
		cam_pts["WW_%s_trough" % f["block"]] = tl[1] + t0.orthogonal() * 1.2
		cam_pts["WW_%s_bank" % f["block"]] = bx + (bx - Vector2(f["chute"][0].x, f["chute"][0].z)).normalized() * 1.6
	for of: Dictionary in Z["outfalls"]:
		var cv: Array = of["culvert"]
		var c0: Vector2 = cv[0]
		var c1: Vector2 = cv[1]
		var mid := (c0 + c1) * 0.5
		var rd := _road_dir(mid)
		await _zone_walk("walk_Outfall_%s（沿 %s 走過暗渠）" % [of["block"], of["road"]], mid - rd * 9.0, mid + rd * 9.0)
		var t := (c1 - c0).normalized()
		cam_pts["Outfall_%s_in" % of["block"]] = c0 + t.orthogonal() * 1.3
		cam_pts["Outfall_%s_out" % of["block"]] = c1 + t.orthogonal() * 1.3
	# 支渠跨渠板（每塊一處）：沿田界跨過支渠
	for bid: String in Z["blocks"]:
		var pl: Node = zi.get_node_or_null("Block_%s/PlankCrossing_Lateral" % bid)
		if pl == null:
			continue
		var c3 := _gcenter(pl)
		var c := Vector2(c3.x, c3.z)
		var lat: PackedVector2Array = Z["blocks"][bid]["lat_line"]
		var best := INF
		var tan := Vector2.RIGHT
		for i in lat.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(c, lat[i], lat[i + 1])
			if q.distance_to(c) < best:
				best = q.distance_to(c)
				tan = (lat[i + 1] - lat[i]).normalized()
		var n := tan.orthogonal()
		await _zone_walk("walk_Plank_%s（跨支渠板）" % bid, c - n * 3.2, c + n * 3.2)
	# 2) TPS 相機淨空（實際 SpringArm＋相機；近裁面四角半徑＋1 cm 球對可見網格）
	if only == "" or only == "cam":
		await _zone_camera(cam_pts)
	# 3) 10:00 玩家視角代表畫面
	if (only == "" or only == "shots") and not "--no-shots" in OS.get_cmdline_user_args():
		await _zone_shots(Z)

func _zone_camera(pts: Dictionary) -> void:
	var adapter := player.get_node("CameraAdapter")
	var arm := player.get_node("Pivot/SpringArm3D") as SpringArm3D
	var pivot := player.get_node("Pivot") as Node3D
	var cam0 := root.get_viewport().get_camera_3d()
	var vs := Vector2(root.get_viewport().get_visible_rect().size)
	var hh := cam0.near * tan(deg_to_rad(cam0.fov) * 0.5)
	var CAM_CLEAR := Vector3(cam0.near, hh, hh * vs.x / vs.y).length() + 0.01
	var ball := SphereShape3D.new()
	ball.radius = CAM_CLEAR
	var near_ball := SphereShape3D.new()
	near_ball.radius = 0.25
	var n := 0
	var bad := 0
	var close := 0
	var occl := 0
	var terrain_lim := 0
	var skim := 0
	var skim_at: Array = []
	var bad_by := {}
	var per_pt := {}
	for pn: String in pts:
		var p: Vector2 = pts[pn]
		await _place(p, 0.0)
		var pb := 0
		for yi in 12:
			var yaw := TAU * yi / 12.0
			for pitch: float in [-1.1, -0.6, -0.18, 0.3, 0.55]:
				for dist: float in [3.0, 8.5, 16.0]:
					adapter._target_yaw = yaw
					adapter._current_yaw = yaw
					adapter._target_pitch = pitch
					adapter._current_pitch = pitch
					adapter._target_distance = dist
					adapter._current_distance = dist
					pivot.global_position = player.global_position + Vector3(0, adapter.pivot_height, 0)
					pivot.rotation = Vector3(pitch, yaw, 0)
					arm.spring_length = dist
					await physics_frame
					await physics_frame
					var cp := root.get_viewport().get_camera_3d().global_position
					n += 1
					var hits := _probe_hits(ball, Transform3D(Basis.IDENTITY, cp), false)
					# 相機已壓到地形（離地 < 近裁面半徑）＝地形本身就在近裁面內，與 P8 構件無關（全村同一相機行為）→ 只計資訊
					if not hits.is_empty() and cp.y - _ground(cp.x, cp.z) < CAM_CLEAR:
						terrain_lim += 1
						hits = []
					# 只碰到貼地面片（水面／渠床）＝相機貼地掠過水面（與地形同類，SpringArm 不擋水面）→ 資訊
					if not hits.is_empty():
						var solid := _probe_hits(ball, Transform3D(Basis.IDENTITY, cp), true)
						if solid.is_empty():
							skim += 1
							skim_at.append("%s %.2fm" % [pn, cp.y - _ground(cp.x, cp.z)])
							hits = []
					if not hits.is_empty():
						bad += 1
						pb += 1
						var key := "%s→%s" % [pn, String(hits[0]).get_slice("/", 1)]
						bad_by[key] = int(bad_by.get(key, 0)) + 1
						if bad <= 40:
							print("[ZONE] cam-hit %s yaw%d pitch%.2f d%.1f cam=(%.2f,%.2f,%.2f) 地面上 %.2f m arm=%.2f → %s" % [pn, yi, pitch, dist, cp.x, cp.y, cp.z, cp.y - _ground(cp.x, cp.z), arm.get_hit_length(), str(hits)])
					elif not _probe_hits(near_ball, Transform3D(Basis.IDENTITY, cp), false).is_empty():
						close += 1
					var rq := PhysicsRayQueryParameters3D.create(cp, player.global_position + Vector3(0, 1.2, 0), PROBE_LAYER)
					var rr := player.get_world_3d().direct_space_state.intersect_ray(rq)
					if not rr.is_empty() and not _probe_names.get(rr["rid"], ["", true])[1]:
						occl += 1
		per_pt[pn] = pb
	_zchk("tps_camera_zone", bad == 0, "近裁面四角半徑＋1 cm＝%.3f m；%d 點 × 180 姿勢＝%d（12 方位 × 5 俯仰 × 臂長 3／8.5／16 m）；近裁面碰到可見構件 %d；相機已壓地形（離地 < %.3f m）時同時碰到貼地構件 %d（資訊，非 P8）；只碰到貼地水面／渠床面片 %d（資訊）；0.25 m 內 %d（資訊）；構件擋在相機與胸口間 %d（%.1f %%，資訊）" % [
		CAM_CLEAR, pts.size(), n, bad, CAM_CLEAR, terrain_lim, skim, close, occl, 100.0 * occl / maxf(1, n)])
	print("[ZONE] camera points: %s" % str(pts.keys()))
	print("[ZONE] camera skim（貼地水面）: %s" % str(skim_at))
	if bad > 0:
		print("[ZONE] camera near-clip breakdown: %s" % str(bad_by))

## 10:00 玩家視角（實際 TPS 相機，非鳥瞰）
func _zone_shots(Z: Dictionary) -> void:
	var dn := root.get_node_or_null("/root/DayNight")
	if dn:
		dn.flowing = false
		dn.set_hour(10.0)
	var sky: Node = main.map_root.get_node_or_null("Lighting/天象系統")
	if sky:
		sky.set("一日長度分鐘", 0.0)
		sky.set("時刻", 10.0)
	probe_root.queue_free()
	var adapter := player.get_node("CameraAdapter")
	# [名稱, 玩家 x, z, 朝向（看向點 x, z）, 俯仰, 臂長]
	var shots := [
		["T0_feeder_WW3", 326.0, 74.0, 318.0, 61.0, -0.12, 6.0],
		["T0_paddies", 340.0, 82.0, 352.0, 120.0, -0.12, 5.0],
		["T1_bund", 392.0, 100.0, 418.0, 120.0, -0.10, 5.0],
		["T1T2_siphon_FarmPath2", 440.0, 84.0, 440.0, 70.0, -0.15, 6.0],
		["T2_lateral", 470.0, 84.0, 470.0, 120.0, -0.10, 5.0],
		["T3_dropweir", 494.0, 128.0, 510.0, 140.0, -0.12, 5.0],
		["S2_from_road", 447.6, 66.0, 465.0, 40.0, -0.10, 5.0],
		["S3_paddies", 545.0, 50.0, 520.0, 25.0, -0.10, 5.0],
		["S0_dryfield", 352.0, 30.0, 340.0, 50.0, -0.12, 5.0],
		["N0_feeder_WW1", 350.0, -42.0, 342.0, -52.0, -0.12, 6.0],
		["N1_paddies", 390.0, -60.0, 410.0, -95.0, -0.10, 5.0],
		["N2_from_FarmPath4", 455.0, -3.0, 465.0, -40.0, -0.10, 5.0],
		["N2_outfall", 449.0, -105.0, 451.0, -124.0, -0.15, 6.0],
		["N3_outfall", 512.0, -84.0, 510.0, -104.0, -0.15, 6.0],
		["N3_fallow", 540.0, -20.0, 520.0, -60.0, -0.10, 5.0],
		["S3N3_siphon_FarmPath4", 556.0, 0.0, 545.0, 0.0, -0.15, 6.0],
	]
	for s: Array in shots:
		var at := Vector2(s[1], s[2])
		var look := Vector2(s[3], s[4])
		var d := look - at
		await _place(at, atan2(-d.x, -d.y))
		adapter._target_yaw = atan2(-d.x, -d.y)
		adapter._current_yaw = adapter._target_yaw
		adapter._target_pitch = s[5]
		adapter._current_pitch = s[5]
		adapter._target_distance = s[6]
		adapter._current_distance = s[6]
		for i in 45:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := (ProjectSettings.globalize_path("res://") + SHOT_DIR + "r6_tps_%s.png" % s[0]).simplify_path()
		var err := root.get_texture().get_image().save_png(path)
		print("[ZONE] shot %s @(%.0f,%.0f) %s" % [s[0], at.x, at.y, error_string(err)])

# ───────────────────────── --cost：P8 開／關 A/B ─────────────────────────
## 量測一態：暖機 warm 幀後量 n 幀；GPU／frame 取中位數（GPU 計時有 ±2 ms 尖峰），其餘取平均
func _measure(vp: RID, warm: int, n: int) -> Dictionary:
	for i in warm:
		await process_frame
	var ft: Array = []
	var gp: Array = []
	var cpu := 0.0
	var prim := 0.0
	var draws := 0.0
	for i in n:
		var t0 := Time.get_ticks_usec()
		await process_frame
		ft.append((Time.get_ticks_usec() - t0) / 1000.0)
		gp.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	ft.sort()
	gp.sort()
	return {"frame": ft[n / 2], "p95": ft[int(n * 0.95)], "gpu": gp[n / 2], "cpu": cpu / n, "prims": prim / n, "draws": draws / n}

func _cost_view(adapter: Node, v: Array) -> void:
	var at := Vector2(v[1], v[2])
	var d := Vector2(v[3], v[4]) - at
	await _place(at, atan2(-d.x, -d.y))
	adapter._target_yaw = atan2(-d.x, -d.y)
	adapter._current_yaw = adapter._target_yaw
	adapter._target_pitch = v[5]
	adapter._current_pitch = v[5]
	adapter._target_distance = v[6]
	adapter._current_distance = v[6]

func _cost() -> void:
	for cl in root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var dn := root.get_node_or_null("/root/DayNight")
	if dn:
		dn.flowing = false
		dn.set_hour(10.0)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var fp := main.map_root.get_node(FARM) as Node3D
	var adapter := player.get_node("CameraAdapter")
	var views := [
		["T1_eye", 392.0, 100.0, 418.0, 120.0, -0.10, 5.0],
		["N2_eye", 455.0, -3.0, 465.0, -40.0, -0.10, 5.0],
		["S2_road", 447.6, 66.0, 465.0, 40.0, -0.10, 5.0],
		["Hieda_front", 398.0, -6.0, 398.0, 20.0, -0.15, 8.5],
		["High_overlook", 420.0, 150.0, 450.0, 60.0, -0.55, 16.0],
	]
	print("[COST] 解析度 %s、vsync off、max_fps 0、10:00；ON／OFF 交替 3 輪，每態暖機 60 幀、量 150 幀；GPU／frame 取中位數，Δ 取 3 輪中位數" % str(root.get_visible_rect().size))
	for v: Array in views:
		await _cost_view(adapter, v)
		var on: Array = []
		var off: Array = []
		for r in 3:
			fp.visible = true
			on.append(await _measure(vp, 60, 150))
			fp.visible = false
			off.append(await _measure(vp, 60, 150))
		fp.visible = true
		var dg: Array = []
		var df: Array = []
		var dc: Array = []
		for r in 3:
			dg.append(on[r]["gpu"] - off[r]["gpu"])
			df.append(on[r]["frame"] - off[r]["frame"])
			dc.append(on[r]["cpu"] - off[r]["cpu"])
		dg.sort()
		df.sort()
		dc.sort()
		var a: Dictionary = on[1]
		var b: Dictionary = off[1]
		print("[COST] %-13s ON  frame %.2f ms (p95 %.2f)  renderCPU %.2f  GPU %.2f  prims %d  draws %d" % [v[0], a["frame"], a["p95"], a["cpu"], a["gpu"], int(a["prims"]), int(a["draws"])])
		print("[COST] %-13s OFF frame %.2f ms (p95 %.2f)  renderCPU %.2f  GPU %.2f  prims %d  draws %d" % [v[0], b["frame"], b["p95"], b["cpu"], b["gpu"], int(b["prims"]), int(b["draws"])])
		print("[COST] %-13s Δ(P8) frame %+.2f  renderCPU %+.2f  GPU %+.2f（3 輪 %+.2f／%+.2f／%+.2f）  prims %+d  draws %+d" % [v[0], df[1], dc[1], dg[1], dg[0], dg[1], dg[2], int(a["prims"] - b["prims"]), int(a["draws"] - b["draws"])])
		var lim := BUDGET_GPU_WORST_MS if v[0] == WORST_VIEW else BUDGET_GPU_MS
		var ok: bool = dg[1] <= lim and dc[1] <= BUDGET_CPU_MS
		if not ok:
			fails += 1
		print("[COST] %s budget %-13s GPU Δ %+.2f（上限 %.0f ms）  renderCPU Δ %+.2f（上限 %.0f ms）" % ["PASS" if ok else "FAIL", v[0], dg[1], lim, dc[1], BUDGET_CPU_MS])
	# 分項（--split）：五鏡位逐類單獨隱藏，與全開交替 3 輪；GPU 差＝該類單獨成本（類間 overdraw 互相遮擋，差值不可相加）
	if "--split" in OS.get_cmdline_user_args():
		var cats := [["grass", ["*Weeds_*", "Grass_*", "GrassChunks"]], ["bund_soil", ["EarthBanks"]], ["water", ["*Water*"]], ["seedlings", ["RiceSeedlings*"]]]
		for v: Array in views:
			await _cost_view(adapter, v)
			for cat: Array in cats:
				var hidden: Array = []
				for pat: String in cat[1]:
					for nd in ([fp.get_node(pat)] if fp.has_node(pat) else fp.find_children(pat, "", true, false)):
						if nd is Node3D and (nd as Node3D).visible:
							hidden.append(nd)
				var dg: Array = []
				var dp := 0.0
				var dd := 0.0
				for r in 3:
					var a: Dictionary = await _measure(vp, 45, 120)
					for nd in hidden:
						(nd as Node3D).visible = false
					var b: Dictionary = await _measure(vp, 45, 120)
					for nd in hidden:
						(nd as Node3D).visible = true
					dg.append(a["gpu"] - b["gpu"])
					dp = a["prims"] - b["prims"]
					dd = a["draws"] - b["draws"]
				dg.sort()
				print("[COST] split %-13s %-10s 節點 %5d  GPU %+.2f ms（3 輪 %+.2f／%+.2f／%+.2f）  prims %+d  draws %+d" % [v[0], cat[0], hidden.size(), dg[1], dg[0], dg[1], dg[2], int(dp), int(dd)])
