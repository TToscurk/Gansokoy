extends SceneTree
## NPC Living World 實機錄影／截圖（視窗模式，搭配 Movie Maker）：
## godot --path godot --write-movie <out.avi> --fixed-fps 30 -s res://tools/npc_life/capture_npc_life.gd -- --map=village_v2 --scene=<名> [--secs=40] [--lifeshots=<資料夾>] [--hour=10]
## 場景：mushroom（魔理沙採蘑菇）、social（魔理沙找慧音聊天）、chain（毛玉→慧音通報→魔理沙改道調查）、
##       player（玩家攔下走路中的靈夢）、overview（載入後主街俯瞰：多名 HERO 各自活動）、garden（阿求庭院觀察）、kosuzu（小鈴整理書）
## 畫面左上角顯示 director 的事件紀錄（中文狀態），方便對照行為。

var main: Node
var dir: Node
var player: Node3D
var cam: Camera3D
var scene_name := "mushroom"
var secs := 40.0
var shots_dir := ""
var hour := 10.0
var hud: Label
var lines: Array = []
var t := 0.0
var started := false
var follow: Callable
var shot_times: Array = []
var shot_on := {}      # 事件狀態 → 延遲幾秒拍（每種最多 max_per 張）
var shot_count := {}
var max_per := 2
var shot_heroes: Array = []
var _cam_pos := Vector3.INF

const FAR := Vector3(330, 0.5, 150)   # 把玩家停在遠處（隱藏），HERO 的距離降頻在 _setup 已關掉
const ZH := {"Reserved": "預約", "Traveling": "移動中", "Interacting": "互動中", "Completed": "完成", "Failed": "失敗", "Interrupted": "中斷", "Cooldown": "冷卻",
	"SESSION_OPEN": "發起交談", "SESSION_TALK": "開始交談", "SESSION_COMPLETED": "交談結束", "SESSION_INTERRUPTED": "交談中斷", "SAY": "說", "LEARN": "得知",
	"FACT_SET": "世界事件", "FACT_CLEAR": "事件解除", "PAUSED": "暫停（玩家搭話）", "RESUMED": "續做", "OBJECT_USED": "使用物件", "STAND_UP": "起身", "TRIGGER": "觸發", "PLAYER_CHAT": "與玩家聊天"}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="): scene_name = a.substr(8)
		if a.begins_with("--secs="): secs = float(a.substr(7))
		if a.begins_with("--lifeshots="): shots_dir = a.substr(12)
		if a.begins_with("--hour="): hour = float(a.substr(7))
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)


func _process(dt: float) -> bool:
	if not started:
		dir = root.get_tree().get_first_node_in_group("npc_life_director")
		if dir == null or not bool(dir.get("_ready_done")):
			return false
		started = true
		_setup()
		return false
	t += dt
	if follow.is_valid():
		follow.call(dt)
	if shots_dir != "" and not shot_times.is_empty() and t >= float(shot_times[0]):
		shot_times.pop_front()
		_shot()
	if t >= secs:
		quit(0)
		return true
	return false


func _setup() -> void:
	player = root.get_tree().get_first_node_in_group("player") as Node3D
	var wt := root.get_node_or_null("/root/WorldTimeManager")
	if wt != null and hour >= 0.0:
		wt.set("hour", hour)
	for h in dir.get("heroes"):
		dir.get("heroes")[h].set("lod_near", 9999.0)
	dir.connect("event_state", _on_ev)
	cam = Camera3D.new()
	cam.fov = 50.0
	main.add_child(cam)
	cam.current = true
	var cl := CanvasLayer.new()
	main.add_child(cl)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_override("font", load("res://assets/fonts/NotoSerifTC-VF.ttf"))
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hud.add_theme_constant_override("outline_size", 6)
	cl.add_child(hud)
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
	match scene_name:
		"mushroom": _sc_mushroom()
		"social": _sc_social()
		"chain": _sc_chain()
		"player": _sc_player()
		"overview": _sc_overview()
		"garden": _sc_garden()
		"kosuzu": _sc_kosuzu()
		"voice": _sc_voice()


func _on_ev(h: String, e: String, s: String, info: Dictionary) -> void:
	if shot_on.has(s) and (shot_heroes.is_empty() or shot_heroes.has(h)) and int(shot_count.get(s, 0)) < max_per:
		shot_count[s] = int(shot_count.get(s, 0)) + 1
		shot_times.append(t + float(shot_on[s]))
		shot_times.sort()
	if s in ["Cooldown", "SESSION_OPEN"]:
		return
	var defs: Dictionary = dir.get("defs")
	var nm := String(defs.get(h, {}).get("name", h)) if defs.has(h) else "世界"
	var label := e
	if defs.has(h):
		for ev in defs[h].get("events", []):
			if ev.id == e: label = String(ev.get("label", e))
	var txt := "%s｜%s｜%s" % [nm, label, ZH.get(s, s)]
	if s == "SAY":
		txt = "%s：%s" % [nm, info.get("text", "")]
	lines.append(txt)
	if lines.size() > 7:
		lines.pop_front()
	hud.text = "\n".join(lines)


func _hero(id: String) -> Node3D:
	return dir.get("heroes")[id]


func _park_player(p: Vector3, hide := true) -> void:
	player.global_position = Vector3(p.x, dir.call("ground_y", Vector2(p.x, p.z), p.y) + 0.05, p.z)
	player.set("velocity", Vector3.ZERO)
	if hide:
		for c in player.get_children():
			if c is Node3D: (c as Node3D).visible = false


## 跟拍：相機在角色「正面方向＋yaw_off」dist 公尺、高 h（隨角色朝向，拍得到臉與動作）；平滑
func _follow_hero(id: String, yaw_off: float, dist: float, h: float, look_h := 1.0) -> Callable:
	return func(dt: float) -> void:
		var a := _hero(id)
		var p := a.global_position
		var yaw := a.rotation.y + yaw_off
		var want := p + Vector3(sin(yaw), 0, cos(yaw)) * dist + Vector3(0, h, 0)
		want = _clear_view(p + Vector3(0, look_h, 0), want)
		_cam_pos = want if _cam_pos == Vector3.INF else _cam_pos.lerp(want, clampf(2.5 * dt, 0, 1))
		cam.global_position = _cam_pos
		cam.look_at(p + Vector3(0, look_h, 0))


func _follow_pair(a_id: String, b_id: String, dist: float, h: float) -> Callable:
	return func(dt: float) -> void:
		var a := _hero(a_id).global_position
		var b := _hero(b_id).global_position
		var mid := (a + b) * 0.5
		var ab := (b - a)
		ab.y = 0
		var side := Vector3(-ab.z, 0, ab.x).normalized() if ab.length() > 0.3 else Vector3(1, 0, 0)
		var d := maxf(dist, ab.length() * 1.2 + 2.0)
		var want := mid + side * d + Vector3(0, h, 0)
		var tgt := mid + Vector3(0, 1.1, 0)
		var w2 := mid - side * d + Vector3(0, h, 0)
		if _blocked(tgt, want) and not _blocked(tgt, w2):
			want = w2
		elif _cam_pos != Vector3.INF and _xz(_cam_pos - mid).dot(_xz(w2 - mid)) > 0.0 and not _blocked(tgt, w2):
			want = w2   # 已在另一側就留著，不要來回翻
		want = _clear_view(tgt, want)
		_cam_pos = want if _cam_pos == Vector3.INF else _cam_pos.lerp(want, clampf(1.8 * dt, 0, 1))
		cam.global_position = _cam_pos
		cam.look_at(mid + Vector3(0, 1.1, 0))


func _blocked(from: Vector3, to: Vector3) -> bool:
	var ss := main.get_viewport().world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var ex: Array[RID] = []
	for h in dir.get("heroes"):
		ex.append((dir.get("heroes")[h] as CollisionObject3D).get_rid())
	q.exclude = ex
	return not ss.intersect_ray(q).is_empty()


## 視線被擋：先繞角（±0.35 rad 遞增）找通視方位；再試抬高 2.5 m；最後才拉近，但不近於 2.2 m（避免鏡頭穿進角色）
func _clear_view(tgt: Vector3, want: Vector3) -> Vector3:
	if not _blocked(tgt, want):
		return want
	var d := want - tgt
	for k in 12:
		var r := d.rotated(Vector3.UP, (k / 2 + 1) * 0.35 * (1 if k % 2 == 0 else -1))
		if not _blocked(tgt, tgt + r):
			return tgt + r
	var up := want + Vector3(0, 2.5, 0)
	if not _blocked(tgt, up):
		return up
	var ss := main.get_viewport().world_3d.direct_space_state
	var hit := ss.intersect_ray(PhysicsRayQueryParameters3D.create(tgt, want))
	if not hit.is_empty():
		var v: Vector3 = (hit.position - tgt) * 0.85
		if v.length() < 2.2:
			v = v.normalized() * 2.2
		return tgt + v
	return want


static func _xz(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


## 語音雙人對話：魔理沙去找慧音，到位後鏡頭切到正在說話的人臉部 3/4 特寫；畫面下方顯示繁中字幕
var sub: Label


func _sc_voice() -> void:
	_park_player(FAR)
	dir.set("time_scale", 1.0)
	var topic := ""
	var partner := "keine"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--topic="): topic = a.substr(8)
		if a.begins_with("--partner="): partner = a.substr(10)
	# 指定主題：暫時讓魔理沙的閒聊只用這個主題
	for ev in dir.get("defs")["marisa"].events:
		if ev.id == "marisa_chat" and topic != "":
			ev["topics"] = [topic]
	dir.call("force_event", "marisa", "marisa_chat", partner)
	var cl := CanvasLayer.new()
	main.add_child(cl)
	sub = Label.new()
	sub.add_theme_font_override("font", load("res://assets/fonts/NotoSerifTC-VF.ttf"))
	sub.add_theme_font_size_override("font_size", 30)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	sub.add_theme_constant_override("outline_size", 8)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.anchor_left = 0.0
	sub.anchor_right = 1.0
	sub.anchor_top = 1.0
	sub.anchor_bottom = 1.0
	sub.offset_top = -120
	sub.offset_bottom = -40
	cl.add_child(sub)
	dir.connect("event_state", func(h, e, st, info):
		if st == "SAY":
			var nm := String(dir.get("defs")[h].get("name", h))
			var emo := String(info.get("emo", "neutral"))
			sub.text = "%s：%s%s\n%s" % [nm, info.get("text", ""), ("　〔%s〕" % emo) if emo != "neutral" else "", info.get("sub", "")])
	var pair := _follow_pair("marisa", partner, 3.2, 1.5)
	follow = func(dt: float) -> void:
		var speaker := ""
		for h in ["marisa", partner]:
			if bool(_hero(h).call("is_speaking")):
				speaker = h
		if speaker == "":
			cam.fov = 50.0
			pair.call(dt)
			return
		cam.fov = 32.0
		var a := _hero(speaker)
		if OS.get_cmdline_user_args().has("--mouthdbg") and Engine.get_process_frames() % 10 == 0:
			var m: Node = a.get("_mouth")
			print("MOUTHDBG ", speaker, " " + ("no mouth node" if m == null else "drawing=%s open=%.2f vt=%.2f" % [m.call("is_drawing"), float(m.get("_open")), float(a.get("_vt"))]))
		var head := a.global_position + Vector3(0, 1.38, 0)
		var yaw := a.rotation.y + 0.55
		var want := head + Vector3(sin(yaw), 0, cos(yaw)) * 0.95 + Vector3(0, 0.03, 0)
		want = _clear_view(head, want)
		_cam_pos = want if _cam_pos == Vector3.INF else _cam_pos.lerp(want, clampf(3.0 * dt, 0, 1))
		cam.global_position = _cam_pos
		cam.look_at(head)
	shot_on = {"SAY": 1.6}
	max_per = 6
	shot_heroes = ["marisa", partner]


func _sc_mushroom() -> void:
	_park_player(FAR)
	dir.set("time_scale", 1.0)
	dir.call("force_event", "marisa", "marisa_mushroom", "", "mushroom_3")
	follow = _follow_hero("marisa", 0.75, 3.6, 1.5, 0.7)
	shot_on = {"Traveling": 6.0, "Interacting": 4.5, "OBJECT_USED": 2.5}
	max_per = 1
	shot_heroes = ["marisa"]


func _sc_social() -> void:
	var m := _hero("marisa")
	var k := _hero("keine")
	_park_player(FAR)
	dir.set("time_scale", 1.0)
	dir.call("force_event", "marisa", "marisa_chat", "keine")
	follow = _follow_pair("marisa", "keine", 4.2, 1.5)
	shot_on = {"SAY": 1.5, "Traveling": 5.0}
	max_per = 4
	shot_heroes = ["marisa", "keine"]


func _sc_chain() -> void:
	_park_player(FAR)
	dir.set("time_scale", 2.0)
	dir.call("_spawn_kedama", {"fact": "anomaly_south_forest", "ttl": 900})
	dir.call("learn", "keine", "anomaly_south_forest")
	# 由慧音去通報魔理沙（自然運作時對象依關係挑選；錄影指定魔理沙）
	(func() -> void:
		await create_timer(1.0).timeout
		dir.call("force_event", "keine", "keine_report_anomaly", "marisa")).call()
	var stage := [0]
	follow = func(dt: float) -> void:
		var m := _hero("marisa")
		var k := _hero("keine")
		if String(m.call("current_event")) == "marisa_investigate" or stage[0] == 1:
			stage[0] = 1
			_follow_hero("marisa", 0.8, 4.5, 1.8, 0.8).call(dt)
		else:
			_follow_pair("keine", "marisa", 4.5, 1.6).call(dt)
	shot_on = {"SAY": 1.2, "LEARN": 1.0, "Interacting": 3.0, "FACT_SET": 2.0}
	max_per = 3
	shot_heroes = ["marisa", "keine", "world"]


func _sc_player() -> void:
	var r := _hero("reimu")
	# 錄影：避免別的 HERO 先把靈夢找去聊天（把雙人冷卻設成剛聊過）
	for h in dir.get("memory"):
		dir.get("memory")[h].pair["reimu"] = float(dir.get("clock"))
	dir.set("time_scale", 1.0)
	dir.call("force_event", "reimu", "reimu_market")
	_park_player(r.global_position + Vector3(30, 0, 0), false)
	var st := [0]
	follow = func(dt: float) -> void:
		var rr := _hero("reimu")
		if st[0] == 0 and t > 6.0:
			st[0] = 1
			var fwd := Vector3(sin(rr.rotation.y), 0, cos(rr.rotation.y))
			_park_player(rr.global_position + fwd * 2.4, false)
			player.look_at(rr.global_position, Vector3.UP)
		if st[0] == 1 and t > secs - 12.0:
			st[0] = 2
			_park_player(rr.global_position + Vector3(30, 0, 0), false)
		_follow_hero("reimu", -0.9, 4.6, 1.6, 1.0).call(dt)
	shot_on = {"PAUSED": 2.5, "RESUMED": 3.0}
	max_per = 1


func _sc_overview() -> void:
	_park_player(FAR)
	dir.set("time_scale", 1.0)
	cam.global_position = Vector3(262, 22, 62)
	cam.look_at(Vector3(240, 0, 10))
	follow = Callable()
	shot_times = [6.0, secs * 0.5, secs - 2.0]


func _sc_garden() -> void:
	_park_player(FAR)
	dir.set("time_scale", 1.0)
	dir.call("force_event", "akyuu", "akyuu_garden", "", "hieda_tsukubai")
	follow = _follow_hero("akyuu", 0.7, 3.4, 1.4, 0.7)
	shot_on = {"STAND_UP": 2.0, "Interacting": 5.0}
	max_per = 1


func _sc_kosuzu() -> void:
	_park_player(FAR)
	dir.set("time_scale", 1.0)
	dir.call("force_event", "kosuzu", "kosuzu_arrange", "", "suzunaan_bookstand")
	follow = _follow_hero("kosuzu", 0.7, 3.4, 1.4, 0.8)
	shot_on = {"Interacting": 2.0, "Completed": 0.5}
	max_per = 1


func _shot() -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_jpg("%s/%s_%02d.jpg" % [shots_dir, scene_name, int(t)], 0.9)
