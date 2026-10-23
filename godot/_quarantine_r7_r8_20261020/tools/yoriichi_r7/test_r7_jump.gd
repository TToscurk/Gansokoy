extends SceneTree
## R7 P5 普通跳躍（空白鍵）focused 測試：只用程式輸入（InputMap 實體事件全清）、headless 物理、不寫資源／場景。
##   godot --headless --fixed-fps 60 --path godot -s res://tools/yoriichi_r7/test_r7_jump.gd -- [scenario|all] [mx|r61|both]
## 每格記錄 is_on_floor／y／loco 狀態／該狀態對應的 clip 名；回報離地格、最高點、接地格、播放序列、地面段腳趾滑移。
const PLAYER := "res://characters/yoriichi/player_yoriichi_r7k.tscn"
const SCENARIOS := ["idle", "move", "drawn", "ceiling", "low_platform", "high_drop", "long_fall", "air_attack", "land_move", "land_attack", "ledge_walkoff"]
var _p: CharacterBody3D
var _world: Node3D
var _case: Dictionary
var _failures: Array = []
var _results: Array = []
var _frame := 0
var _rows: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	_case.checks.append([ok, label])
	if not ok:
		_failures.append("%s/%s: %s" % [_case.scenario, _case.variant, label])
		push_error("FAIL %s/%s: %s" % [_case.scenario, _case.variant, label])

func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	_world.add_child(body)
	return body

func _clip_of(state: String) -> String:
	match state:
		"JumpStart": return str(_p.get("jump_anim"))
		"Fall": return str(_p.get("fall_anim"))
		"Land": return str(_p.get("land_anim"))
	return state

func _toes() -> Array:
	var sk: Skeleton3D = _p.get("_visual").find_children("*", "Skeleton3D", true, false)[0]
	var out := []
	for bn in ["mixamorig_LeftToeBase", "mixamorig_RightToeBase"]:
		out.append(sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bn)).origin)
	return out

func _tick(n: int) -> void:
	for i in n:
		await physics_frame
		_frame += 1
		var pb: AnimationNodeStateMachinePlayback = _p.get("_tree").get("parameters/loco/playback")
		var st := str(pb.get_current_node())
		_rows.append({"f": _frame, "floor": _p.is_on_floor(), "y": _p.global_position.y, "vy": _p.velocity.y,
			"x": _p.global_position.x, "z": _p.global_position.z, "st": st, "clip": _clip_of(st),
			"pos": pb.get_current_play_position(), "toes": _toes(), "ceil": _p.is_on_ceiling(),
			"action": int(_p.get("action_state")), "form": int(_p.get("active_form"))})

func _setup(variant: String, start: Vector3) -> void:
	_world = Node3D.new()
	root.add_child(_world)
	_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200))
	_p = (load(PLAYER) as PackedScene).instantiate()
	_p.set("r7_vfx_enabled", false)
	_p.set("r7_jump_variant", variant)
	_p.set("sun_mastery", 100)
	_p.set("sun_breath_gauge", 100.0)
	_p.position = start
	_world.add_child(_p)
	await process_frame
	_p.set_process_unhandled_input(false)
	_frame = 0
	_rows = []
	await _tick(30)

## 本段（從 i0 起）摘要：離地格、最高點、接地格、序列、clip 名
func _summary(i0: int) -> Dictionary:
	var off := -1
	var land := -1
	var peak := -INF
	var peak_f := -1
	var seq: Array = []
	var clips: Array = []
	for i in range(i0, _rows.size()):
		var r: Dictionary = _rows[i]
		if off < 0 and not r.floor:
			off = r.f
		if off >= 0 and land < 0 and r.floor:
			land = r.f
		if off >= 0 and land < 0 and r.y > peak:
			peak = r.y
			peak_f = r.f
		if seq.is_empty() or seq[-1] != r.st:
			seq.append(r.st)
			clips.append(r.clip)
	return {"takeoff_f": off, "apex_f": peak_f, "apex_y": snappedf(peak, 0.001), "contact_f": land, "seq": seq, "clips": clips}

## 地面段腳趾滑移：toe 骨高度 < 地面+0.13 m（站姿 toe 骨≈0.08–0.09）且連續兩格都在地面時，腳趾 xz 位移扣掉膠囊水平位移後的最大值（每腳，m/物理格）
func _slide(i0: int, i1: int, phase: String, ground_y: float) -> float:
	var worst := 0.0
	for k in range(maxi(i0 + 1, 1), mini(i1, _rows.size())):
		var a: Dictionary = _rows[k - 1]
		var b: Dictionary = _rows[k]
		if phase == "pre" and not (a.floor and b.floor and a.st == "JumpStart" and b.st == "JumpStart"):
			continue
		if phase == "land" and not (a.floor and b.floor and b.st == "Land" and a.st == "Land"):
			continue
		for t in 2:
			var ta: Vector3 = a.toes[t]
			var tb: Vector3 = b.toes[t]
			if ta.y - ground_y < 0.13 and tb.y - ground_y < 0.13:
				var d := Vector2((tb.x - ta.x) - (b.x - a.x), (tb.z - ta.z) - (b.z - a.z)).length()
				worst = maxf(worst, d)
	return snappedf(worst, 0.0001)

func _run_case(scenario: String, variant: String) -> void:
	_case = {"scenario": scenario, "variant": variant, "checks": []}
	var start := Vector3.ZERO
	if scenario == "high_drop":
		start = Vector3(0, 3.0, 0)
	elif scenario == "long_fall":
		start = Vector3(0, 30.0, 0)
	elif scenario == "ledge_walkoff":
		start = Vector3(0, 3.2, 0)
	await _setup(variant, start)
	var ground_y := 0.0
	if scenario == "high_drop":
		_box(Vector3(0, 1.5, 0), Vector3(1.6, 3.0, 1.6))     # 3 m 台，跳起後往前飄出邊緣
		ground_y = 3.0
	elif scenario == "long_fall":
		_box(Vector3(0, 15.0, 0), Vector3(1.6, 30.0, 1.6))
		ground_y = 30.0
	elif scenario == "ledge_walkoff":
		_box(Vector3(0, 1.6, 0), Vector3(1.6, 3.2, 1.6))
		ground_y = 3.2
	elif scenario == "ceiling":
		_box(Vector3(0, 2.6, 0), Vector3(20, 0.2, 20))      # 頭頂 2.5 m：跳高 1.68 m 會撞頂
	if scenario in ["high_drop", "long_fall", "ledge_walkoff"]:
		_p.global_position = start
		await _tick(30)
		ground_y = _p.global_position.y
	_case.ground_y = ground_y
	_check(_p.is_on_floor(), "starts grounded")
	if scenario in ["drawn", "air_attack"]:
		_p.call("request_draw")
		await _tick(100)
		_check(int(_p.get("sword_state")) == 2, "drawn")
	var i0 := _rows.size()
	var moving := scenario in ["move", "low_platform", "high_drop", "long_fall"]
	if moving:
		Input.action_press("move_forward")
		await _tick(30 if scenario == "move" else 6)
		i0 = _rows.size()
	if scenario == "low_platform":
		# 1.2 m 台：起跳點前方 2.6 m 起、深 4 m → 下降段（頂點後）提前接地，早於平地 0.82 s
		var hv := Vector3(_p.velocity.x, 0, _p.velocity.z)
		var dir := hv.normalized()
		var c := _p.global_position + dir * (2.6 + 2.0) + Vector3.UP * 0.6
		var b := _box(c, Vector3(4, 1.2, 4))
		b.rotation.y = atan2(dir.x, dir.z)
		_case.platform_dir = [snappedf(dir.x, 0.01), snappedf(dir.z, 0.01)]
	if scenario == "ledge_walkoff":
		Input.action_press("move_forward")
	else:
		_p.call("request_jump")
	if scenario == "air_attack":
		await _tick(18)
		_p.call("request_draw")
		await _tick(1)
		_case.air_form_started = _p.call("execute_form", 10, true)
	if scenario in ["low_platform", "move"]:
		await _tick(90)
	elif scenario == "long_fall":
		await _tick(30)
		Input.action_release("move_forward")
		await _tick(160)
	elif scenario == "high_drop":
		await _tick(20)
		Input.action_release("move_forward")
		await _tick(90)
	elif scenario == "ledge_walkoff":
		await _tick(25)
		Input.action_release("move_forward")
		await _tick(80)
	elif scenario in ["land_move", "land_attack"]:
		var was_air := false
		for i in 120:
			await _tick(1)
			was_air = was_air or not _p.is_on_floor()
			if was_air and _p.is_on_floor():
				break
	else:
		await _tick(160 if scenario == "air_attack" else 70)
	if scenario == "land_move":
		pass
	# 落地後立刻移動／攻擊
	var post := {}
	if scenario in ["land_move", "land_attack"]:
		var contact_f := _frame
		if scenario == "land_move":
			Input.action_press("move_forward")
			var from := _p.global_position
			await _tick(20)
			Input.action_release("move_forward")
			post.move_m = snappedf(Vector2(_p.global_position.x - from.x, _p.global_position.z - from.z).length(), 0.01)
			_check(post.move_m > 1.0, "move right after land > 1.0 m in 20 frames")
		else:
			_p.call("request_primary_attack")
			await _tick(2)
			post.combo_stage = int(_p.get("combo_stage"))
			post.action_state = int(_p.get("action_state"))
			_check(int(_p.get("action_state")) == 1, "attack right after land starts (ATTACKING)")
			await _tick(60)
		post.contact_f = contact_f
		i0 = 0
	if moving:
		Input.action_release("move_forward")
	var s := _summary(i0)
	_case.merge(s)
	_case.post = post
	_case.slide_pre = _slide(i0, _rows.size(), "pre", ground_y)
	_case.slide_land = _slide(i0, _rows.size(), "land", ground_y)
	var air_frames: int = s.contact_f - s.takeoff_f if s.contact_f > 0 and s.takeoff_f > 0 else -1
	_case.air_frames = air_frames
	var want_jump := str(_p.get("jump_anim"))
	var want_fall := str(_p.get("fall_anim"))
	var want_land := str(_p.get("land_anim"))
	if variant == "mx":
		_check(want_jump == "R7_Jump_MX" and want_fall == "R7_Fall_MX" and want_land == "R7_Land_MX", "mx clip names installed")
		_check(_p.get("_anim").get_animation(want_fall).loop_mode == Animation.LOOP_NONE, "mx fall not looping")
	else:
		_check(want_jump == "Jump" and want_fall == "Fall" and want_land == "Land", "r61 clip names")
		_check((_p.get("_anim").get_animation("Jump") as Animation).resource_path.ends_with("r61_jump_up.res"), "r61 jump resource")
	_check(s.takeoff_f > 0, "left the floor")
	_check(s.contact_f > s.takeoff_f, "landed")
	# 物理不變：起跳延遲＝(0.567−0.33)/1.6≈0.148 s ≈ 9 格；平地跳高 v²/2g = 1.68 m
	if scenario in ["idle", "move", "drawn", "land_move", "land_attack"]:
		_check(abs(s.apex_y - _rows[i0].y - 1.68) < 0.08, "flat apex ~1.68 m (got %s)" % s.apex_y)
		_check(air_frames >= 46 and air_frames <= 52, "flat airtime ~0.82 s (got %d frames)" % air_frames)
	if scenario == "ceiling":
		_check(s.apex_y - _rows[i0].y < 1.0, "ceiling caps the rise")
		var ceil_hit := false
		for r in _rows:
			ceil_hit = ceil_hit or r.ceil
		_case.ceiling_hit = ceil_hit
		_check(ceil_hit, "actually touched ceiling")
	if scenario == "low_platform":
		_check(s.contact_f - s.takeoff_f < 46, "early contact on platform (air %d < flat 49)" % (s.contact_f - s.takeoff_f))
		_check(_p.global_position.y > 1.15, "ended on the 1.2 m platform")
	# 落地後必須離開 JumpStart（碰頂／提前接地不強制播完起跳）
	var after_land := []
	for r in _rows.slice(i0):
		if r.f >= s.contact_f and s.contact_f > 0 and r.f <= s.contact_f + 3:
			after_land.append(r.st)
	_case.after_land = after_land
	if scenario != "air_attack":   # 空中出招期間 full 層蓋住 loco（loco 停在 JumpStart 不可見），改由下方 replay 檢查
		_check(not ("JumpStart" in after_land.slice(1)), "JumpStart not kept after real contact")
	# 地面蹬地段只能在起跳前；空中不得回到 JumpStart
	var air_js := false
	var air_states := {}
	for r in _rows.slice(i0):
		if not r.floor and r.f > s.takeoff_f + 2 and r.f < s.contact_f:
			air_states[r.st] = true
			if r.st == "JumpStart" and r.vy <= -0.5 and r.form == 0:
				air_js = true
	_case.air_states = air_states.keys()
	_check(not air_js, "no JumpStart replay while falling")
	if scenario == "air_attack":
		_check(bool(_case.get("air_form_started", false)), "air form started (REF05 id 10)")
		var replay := false
		var seen_air := false
		for r in _rows.slice(i0):
			if r.form != 0:
				seen_air = true
			if seen_air and r.form == 0 and r.st == "JumpStart":
				replay = true
		_check(not replay, "air attack does not restart ground push-off")
	if scenario in ["high_drop", "long_fall", "ledge_walkoff"]:
		_check(s.contact_f - s.takeoff_f > (30 if scenario == "ledge_walkoff" else 50), "long airtime")
		var fall_pos := 0.0
		for r in _rows.slice(i0):
			if r.st == "Fall":
				fall_pos = maxf(fall_pos, r.pos)
		_case.fall_play_pos_max = snappedf(fall_pos, 0.01)
	# 腳趾滑移以同一量法的 r61 基準比較（r61 實測 idle/drawn 0.0317、high_drop 0.040、ledge 0.0718 m/格）
	if variant == "mx" and scenario in ["idle", "drawn", "high_drop", "ledge_walkoff"]:
		_check(_case.slide_land <= 0.035, "Land toe slide not worse than r61 (max %.4f m/frame)" % _case.slide_land)
	_case.trace = []
	for r in _rows.slice(i0):
		if (r.f - s.takeoff_f) % 3 == 0 or r.f == s.contact_f or r.f == s.takeoff_f:
			_case.trace.append([r.f, r.floor, snappedf(r.y, 0.001), snappedf(r.vy, 0.01), r.st, snappedf(r.pos, 0.003)])
	_case.toes_near_contact = []
	for r in _rows.slice(i0):
		if s.contact_f > 0 and r.f >= s.contact_f - 2 and r.f <= s.contact_f + 30:
			var tt: Array = r.toes
			_case.toes_near_contact.append([r.f, r.st, snappedf(r.pos, 0.003), [snappedf(tt[0].x, 0.001), snappedf(tt[0].y, 0.001), snappedf(tt[0].z, 0.001)], [snappedf(tt[1].x, 0.001), snappedf(tt[1].y, 0.001), snappedf(tt[1].z, 0.001)]])
	_results.append(_case)
	print("JCASE %s/%s takeoff=%d apex=%s@%d contact=%d air=%d seq=%s clips=%s slide_pre=%s slide_land=%s %s" % [
		scenario, variant, s.takeoff_f, s.apex_y, s.apex_f, s.contact_f, air_frames, s.seq, s.clips,
		_case.slide_pre, _case.slide_land, ("post=" + JSON.stringify(post)) if not post.is_empty() else ""])
	_world.queue_free()
	await process_frame
	await physics_frame

func _run() -> void:
	for act in InputMap.get_actions():
		InputMap.action_erase_events(act)
	var args := OS.get_cmdline_user_args()
	var which: String = args[0] if args.size() > 0 else "all"
	var vs: Array = ["mx", "r61"] if args.size() < 2 or args[1] == "both" else [args[1]]
	var expected := 0
	for v in vs:
		for sc in SCENARIOS:
			if which != "all" and which != sc:
				continue
			expected += 1
			await _run_case(sc, v)
	if _results.size() != expected or expected == 0:
		_failures.append("incomplete case set")
	var path := "user://r7_jump_tests.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"scene": PLAYER, "cases": _results, "failures": _failures}, "\t"))
	f.close()
	for x in _failures:
		print("JFAIL ", x)
	print("R7_JUMP_RESULT cases=", _results.size(), " failures=", _failures.size(), " json=", ProjectSettings.globalize_path(path))
	quit(0 if _failures.is_empty() else 1)
