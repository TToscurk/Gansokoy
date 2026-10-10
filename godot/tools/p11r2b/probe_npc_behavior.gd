extends SceneTree
## P11 R2B TASK03／04 局部テスト（headless、只讀）：村を 1 回載せ、ゲーム内 90 秒（time_scale 3）を観察。
##  - Drink 住人（W3／C17／O8）：drink 再生時間の割合・回数・杯の表示が drink 中だけか
##  - patrol 住人：折返し 1 回あたりの回転量（最短弧なら ≤ π＋余裕）、idle のまま回った秒数
##   godot --headless --path . --script res://tools/p11r2b/probe_npc_behavior.gd
const SCENE := "res://maps/village_v2/village_v2.tscn"

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 6:
		await process_frame
	var overlays := []
	for n in ["Population/ActivityP10", "Population/ActivityCoreP10", "Population/ActivityOuterP10"]:
		var o := v.get_node_or_null(n)
		if o != null:
			overlays.append(o)
	var drinks := []
	for o in overlays:
		for e in o.entries:
			if e.type == "Drink":
				drinks.append(e)
	var walkers := []
	for b in v.get_node("Population").find_children("*", "AnimatableBody3D", true, false):
		if String(b.get("mode")) == "patrol":
			walkers.append(b)
	var st := {}
	for e in drinks:
		st[e.path] = {"drink_t": 0.0, "starts": 0, "cup_bad": 0, "was": false}
	var ws := {}
	for b in walkers:
		ws[b] = {"prev": b.rotation.y, "turn_acc": 0.0, "turns": [], "idle_spin": 0.0, "was_walk": bool(b.get("_walking"))}
	Engine.time_scale = 3.0
	var T := 0.0
	var DUR := 90.0
	while T < DUR:
		await physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second * Engine.time_scale
		T += dt
		for e in drinks:
			var s: Dictionary = st[e.path]
			var dr: bool = e.ap.current_animation == &"drink"
			if dr:
				s.drink_t += dt
				if not s.was:
					s.starts += 1
			if e.prop.visible != dr:
				s.cup_bad += 1
			s.was = dr
		for b in walkers:
			var w: Dictionary = ws[b]
			var d := absf(angle_difference(w.prev, b.rotation.y))
			w.prev = b.rotation.y
			var walking := bool(b.get("_walking"))
			if not walking:
				w.turn_acc += d
				var npc = b.get_node("NPC")
				if d > 0.0005 and npc.get("animation") == &"idle":
					w.idle_spin += dt
			elif not w.was_walk:
				w.turns.append(w.turn_acc)
				w.turn_acc = 0.0
			w.was_walk = walking
	Engine.time_scale = 1.0
	var bad := 0
	print("[NPCB] 観察 %.0f 秒（ゲーム内）" % DUR)
	for k in st:
		var s: Dictionary = st[k]
		var frac := float(s.drink_t) / DUR
		var ok := frac < 0.35 and int(s.starts) >= 1 and int(s.cup_bad) <= 2
		bad += int(not ok)
		print("[NPCB] Drink %-28s drink %.0f%%  回数 %d  杯の表示不一致 %d フレーム  %s" % [k, frac * 100.0, s.starts, s.cup_bad, "OK" if ok else "NG"])
	for b in walkers:
		var w: Dictionary = ws[b]
		var mx := 0.0
		for t in w.turns:
			mx = maxf(mx, t)
		var ok := mx <= PI + 0.25 and float(w.idle_spin) < 0.2
		bad += int(not ok)
		print("[NPCB] Patrol %-24s 折返 %d 回  最大回転 %.0f°  Idle のまま回転 %.2f 秒  %s" % [b.name, w.turns.size(), rad_to_deg(mx), w.idle_spin, "OK" if ok else "NG"])
	print("[NPCB] NG %d" % bad)
	quit(bad)
