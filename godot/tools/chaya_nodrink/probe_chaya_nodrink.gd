extends SceneTree
## 茶屋少女 Drink 削除の実機確認：village_v2 を載せて 25 秒動かし、3 人（W3／C17／O8）が基線 Idle のまま・
## 茶碗 prop 0・どの Activity overlay にも Drink 指派 0 であることを確かめる。
## godot --headless --path . --script res://tools/chaya_nodrink/probe_chaya_nodrink.gd
const ACTORS := ["Population/PopulationP10/MarketWest/W3_chaya_f01", "Population/CoreP10/Izakaya/C17_chaya_f01", "Population/OuterP10/Canal/O8_chaya_f01"]
const OVERLAYS := ["Population/ActivityP10", "Population/ActivityCoreP10", "Population/ActivityOuterP10"]
const DRINK := "drinking_im1_a030"


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	var fails := 0
	var seen := {}
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 25000:
		await process_frame
		for p: String in ACTORS:
			var a := v.get_node_or_null(p)
			if a == null:
				continue
			var ap: AnimationPlayer = a.get_node("NPC").player
			var cur := String(ap.current_animation)
			var anim := ap.get_animation(ap.current_animation) if ap.has_animation(ap.current_animation) else null
			var src := String(anim.resource_path) if anim else ""
			seen[p + " | " + cur + " | " + src.get_file()] = true
	for p: String in ACTORS:
		var ok := v.get_node_or_null(p) != null
		print("[CHAYA] %s actor %s" % ["PASS" if ok else "FAIL", p])
		fails += 0 if ok else 1
	for k: String in seen:
		var bad := k.contains(DRINK) or k.contains("| drink |")
		print("[CHAYA] %s seen %s" % ["FAIL" if bad else "PASS", k])
		fails += 1 if bad else 0
	var drinks := 0
	var cups := 0
	for o: String in OVERLAYS:
		var ov := v.get_node_or_null(o)
		if ov == null:
			print("[CHAYA] FAIL overlay missing ", o)
			fails += 1
			continue
		var n := 0
		for e: Dictionary in ov.get("entries"):
			if String(e.type) == "Drink" or String(e.path).contains("chaya_f01"):
				drinks += 1
			n += 1
		for c in ov.find_children("*", "MeshInstance3D", true, false):
			if c.has_meta("new_small_prop_reason"):
				cups += 1
		print("[CHAYA] INFO %s entries %d" % [o, n])
	print("[CHAYA] %s Drink／chaya 指派 %d・茶碗 prop %d" % ["PASS" if drinks == 0 and cups == 0 else "FAIL", drinks, cups])
	fails += 0 if drinks == 0 and cups == 0 else 1
	print("[CHAYA] 結果：%d 項失敗" % fails)
	quit(1 if fails else 0)
