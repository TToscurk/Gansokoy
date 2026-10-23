extends "res://characters/yoriichi/v24_isshin/isshin_dojo_demo.gd"
## 緣一 R9 綜合試玩場景（候選 ART_REVIEW；不改正式 Player／跑酷／正式場景；19 招動作庫與 Dojo 不動）。
## A. 普通劍術派生（資料：r9/r9_moveset.json）：攻擊鍵依「狀態＋方向＋前一招」由派生表選招——
##    站立／走動＝選中的起手招（預設一心三刀，連按接連段）；衝刺中＝突進逆袈裟；閃避中／閃避後 0.35 s 內＝反擊；
##    跳躍中＝空中下劈（跳躍招自帶 next，無縫接 q_jumpcut）；後退＋攻擊＝退步縱斬；居合構＝居合斬（衝刺中＝拔刀上撩）。
## B. 日之呼吸（資料：r9/sun_breathing.json，獨立技能鍵與技能資料、獨立傷害／冷卻／銜接條件、專用動作與 VFX 模組 r9/sun_vfx.gd）。
## 操作：WASD 移動；Shift＋W 衝刺；Space 閃避；F 跳躍；J／K／滑鼠左鍵 攻擊；L／滑鼠右鍵 日之呼吸・圓舞；G 拔刀／收刀；
##       1–9、0 選一般攻擊的起手招（Tab 換頁）；V 特效開／關；Q/E 轉鏡頭；H 說明。
## 輸入緩衝：攻擊 0.20 s、閃避 0.15 s、技能 0.25 s、跳躍 0.12 s（按早了會在可出招的那一幀出，出招後才清掉）。
## 自動導覽：-- --tour --tourfile=PATH.json [--cam=third|side] [--novfx] [--perf=PATH.json]；每段可加 ev:[[秒, "attack"|"skill"|"jump"|"dodge"], ...]、vfx:true/false。
const R9_DIR := "res://characters/yoriichi/v24_isshin/r9/"
const SunVFX = preload("res://characters/yoriichi/v24_isshin/r9/sun_vfx.gd")
const SkillAudio = preload("res://characters/yoriichi/v24_isshin/r9/skill_audio.gd")
const MeshVFX = preload("res://characters/yoriichi/v24_isshin/r9c/sun_vfx_mesh.gd")
## R9-C：圓舞特效版本（"r9"＝原本程式刀光、"A"／"B"＝Blender 候選）；C 鍵切換、--vfx=
var vfx_variant := "r9"
## R10：目前選中的呼吸型（R9 只有圓舞）
var cur_skill := "sun_enbu"
var mvfx
var _skill_variant := "r9"
var _prewarm_n := 0

var r9: Dictionary = {}
var sun: Dictionary = {}
var skills: Dictionary = {}
var vfx
var saudio
var vfx_on := true
var buf := {"attack": -9.0, "dodge": -9.0, "skill": -9.0, "jump": -9.0}
var now := 0.0
var sprint_t := 0.0
var last_end_key := ""
var last_end_t := -9.0
var route_log: Array = []
var dmg_log: Array = []
var skill_key := ""
var skill_cd := {}
var perf_path := ""
var perf_log: Array = []
var _snap := {}
var _held := {}
var _ev_q: Array = []
var _my_pending := ""
var _last_route := ""
var _trail_lag := -1.0
var _dump_path := ""
var _dump: Array = []
var sync_log: Array = []
## R9-C3：環境（day＝原本的白天；dusk＝黃昏森林，看動態火光有沒有真的照到環境）；--env=dusk、N 鍵切換
var env_mode := "day"
var _env_day := {}
var _env_res: Environment
var _env_sun: DirectionalLight3D
var _trees: Node3D
var light_log: Array = []

func _pre_setup() -> void:
	r9 = JSON.parse_string(FileAccess.get_file_as_string(R9_DIR + "r9_moveset.json"))
	sun = JSON.parse_string(FileAccess.get_file_as_string(R9_DIR + "sun_breathing.json"))
	skills = sun["skills"]
	combat.sprint_anim = str(r9["sprint"]["anim"])
	combat.sprint_speed = float(r9["sprint"]["speed"])
	for k in r9["shots"]:
		combat.extra_shots[k] = _clean(r9["shots"][k])
	for k in skills:
		combat.extra_shots[k] = _clean(skills[k]["shot"])

func _clean(d: Dictionary) -> Dictionary:
	var o := {}
	for k in d:
		if not str(k).begins_with("_"):
			o[k] = d[k]
	return o

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--novfx":
			vfx_on = false
		elif a.begins_with("--perf="):
			perf_path = a.substr(7)
		elif a.begins_with("--vfx="):
			vfx_variant = a.substr(6)
		elif a.begins_with("--dumpblade="):
			_dump_path = a.substr(12)
		elif a.begins_with("--env="):
			env_mode = a.substr(6)
	super._ready()
	var want_env := env_mode
	_apply_env("dusk")                 # 開場先把黃昏森林的樹載好（藏起來），之後 N 鍵切換不卡（實測第一次切換時載樹卡 145 ms）
	_apply_env(want_env)
	# 19 招全部保留；停用的不進試玩清單（動畫與設定不刪）
	var keep: Array = []
	for m in moves:
		var info: Dictionary = (r9["moves"] as Dictionary).get(m["key"], {})
		if bool(info.get("enabled", true)):
			keep.append(m)
	moves = keep
	move_ix = {}
	for i in moves.size():
		move_ix[moves[i]["key"]] = i
	for k in r9["overrides"]:
		combat.shot_override[k] = (combat.shot_override.get(k, {}) as Dictionary).merged(r9["overrides"][k], true)
	combat.attack_router = _router
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--r9branch="):        # 調參用：--r9branch=<branch id>:<move key>
			var kv := a.substr(11).split(":")
			for br in r9["branches"]:
				if str(br["id"]) == kv[0]:
					br["move"] = kv[1]
	dummy_hp = 99
	vfx = SunVFX.new()
	vfx.name = "SunVFX"
	add_child(vfx)
	vfx.setup(sword, cam)
	vfx.enabled = vfx_on
	saudio = SkillAudio.new()
	saudio.name = "SkillAudio"
	add_child(saudio)
	saudio.muted = not use_audio
	for k in skills:
		saudio.preload_events(skills[k]["audio"])
	mvfx = MeshVFX.new()
	mvfx.name = "SunVFXMesh"
	add_child(mvfx)
	var all_variants := {}
	for k in skills:                                  # R10：各呼吸型的 mesh 特效版本合在一起登記（R9 只有圓舞）
		all_variants.merge(skills[k].get("vfx_variants", {}), true)
	mvfx.setup(actor, sword, cam, all_variants)
	mvfx.prewarm()
	_prewarm_n = 2
	if not ("--vfx=" in " ".join(OS.get_cmdline_user_args())):
		vfx_variant = str(skills["sun_enbu"].get("vfx_variant", "r9"))
	sk.skeleton_updated.connect(_vfx_frame)
	_mk_spark_pool()
	if perf_path != "":
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

func _build_world() -> void:
	super._build_world()
	for c in get_children():
		if c is WorldEnvironment:
			var env: Environment = (c as WorldEnvironment).environment
			env.glow_enabled = true            # 只讓火焰核心（EMISSION > 1.1）進泛光；強度壓低，避免刀路被糊掉
			env.glow_hdr_threshold = 1.1
			env.glow_intensity = 0.45
			env.glow_strength = 0.9
			env.glow_bloom = 0.0
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
			_env_res = env
		elif c is DirectionalLight3D and _env_sun == null:
			_env_sun = c as DirectionalLight3D
	if _env_res != null:
		var psm := _env_res.sky.sky_material as ProceduralSkyMaterial
		_env_day = {"top": psm.sky_top_color, "hor": psm.sky_horizon_color, "ghor": psm.ground_horizon_color, "gbot": psm.ground_bottom_color,
			"amb": _env_res.ambient_light_energy, "sun_e": _env_sun.light_energy if _env_sun else 1.0, "sun_c": _env_sun.light_color if _env_sun else Color.WHITE,
			"sun_r": _env_sun.rotation_degrees if _env_sun else Vector3.ZERO}

## R9-C3：黃昏森林（只改這個試玩場景自己的環境；樹用 assets/landscape 現成的杉樹／針葉樹，只讀、不改資產）
func _apply_env(mode: String) -> void:
	env_mode = mode
	if _env_res == null:
		return
	var psm := _env_res.sky.sky_material as ProceduralSkyMaterial
	var dusk := mode == "dusk"
	psm.sky_top_color = Color(0.035, 0.045, 0.09) if dusk else _env_day["top"]
	psm.sky_horizon_color = Color(0.26, 0.12, 0.07) if dusk else _env_day["hor"]
	psm.ground_horizon_color = Color(0.08, 0.06, 0.05) if dusk else _env_day["ghor"]
	psm.ground_bottom_color = Color(0.02, 0.02, 0.02) if dusk else _env_day["gbot"]
	_env_res.ambient_light_energy = 0.55 if dusk else float(_env_day["amb"])
	_env_res.fog_enabled = dusk
	_env_res.fog_light_color = Color(0.07, 0.07, 0.11)
	_env_res.fog_density = 0.025
	_env_res.fog_sky_affect = 0.3
	if _env_sun:
		_env_sun.light_energy = 0.22 if dusk else float(_env_day["sun_e"])
		_env_sun.light_color = Color(1.0, 0.55, 0.35) if dusk else _env_day["sun_c"]
		_env_sun.rotation_degrees = Vector3(-9, 70, 0) if dusk else _env_day["sun_r"]
	if dusk and _trees == null:
		_trees = Node3D.new()
		_trees.name = "DuskForest"
		add_child(_trees)
		var srcs := ["res://assets/landscape/大衫.glb", "res://assets/landscape/2大衫.glb", "res://assets/landscape/針葉林樹3.glb"]
		var rng := RandomNumberGenerator.new()
		rng.seed = 9031
		for i in 14:
			var ps: PackedScene = load(srcs[i % srcs.size()])
			var tr := ps.instantiate() as Node3D
			var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / 14.0
			var r := rng.randf_range(8.5, 13.0)
			tr.position = Vector3(sin(a) * r, 0.0, 1.4 + cos(a) * r)
			tr.rotation.y = rng.randf() * TAU
			_trees.add_child(tr)
			var h := 0.0
			for mi in tr.find_children("*", "MeshInstance3D", true, false):
				var bb := (tr.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform) * (mi as MeshInstance3D).get_aabb()
				h = maxf(h, bb.end.y)
			tr.scale = Vector3.ONE * (rng.randf_range(11.0, 15.0) / maxf(h, 0.1))
	if _trees:
		_trees.visible = dusk

## 選招不再直接決定攻擊鍵（改由派生表），所以覆寫成空
func _route() -> void:
	pass

func _move_input() -> Vector2:
	if tour:
		return tour_input
	var x := float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	var y := float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S))
	if y > 0.0 and x == 0.0 and Input.is_key_pressed(KEY_SHIFT):
		y = 3.0                            # 衝刺
	return Vector2(x, y)

func _edge(name_: String, down: bool) -> bool:
	var was := bool(_held.get(name_, false))
	_held[name_] = down
	return down and not was

func _aim_err() -> float:
	var to := enemy_pos - actor.global_position
	return wrapf(atan2(to.x, to.z) - actor.rotation.y, -PI, PI)

# ------------------------------------------------------------------ 輸入：緩衝、跳躍、技能
func _filter_input(delta: float, dodge: bool, attack: bool) -> Array:
	now += delta
	_snap = {"state": combat.state, "key": combat.shot_key, "queued": combat.combo_queued, "t": combat.shot_t}
	var jump := false
	var skill := false
	if tour:
		while not _ev_q.is_empty() and tour_t >= float(_ev_q[0][0]):
			var ev: String = _ev_q.pop_front()[1]
			match ev:
				"attack": attack = true
				"dodge": dodge = true
				"jump": jump = true
				"skill": skill = true
	else:
		jump = _edge("jump", Input.is_key_pressed(KEY_F))
		skill = _edge("skill", Input.is_key_pressed(KEY_L) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	if attack:
		buf["attack"] = now
	if dodge:
		buf["dodge"] = now
	if jump:
		buf["jump"] = now
	if skill:
		buf["skill"] = now
	var B: Dictionary = r9["buffer"]
	# 衝刺計時（只在步行狀態量；出招那一幀保留，讓派生表看得到）
	if combat.state != combat.S.SHOT:
		sprint_t = sprint_t + delta if (combat.bp.y > 2.5 and combat.g > 0.7) else 0.0
	if now - float(buf["jump"]) <= float(B["jump"]) and _try_jump():
		buf["jump"] = -9.0
	if now - float(buf["skill"]) <= float(B["skill"]) and _try_skill(cur_skill):
		buf["skill"] = -9.0
	return [now - float(buf["dodge"]) <= float(B["dodge"]), now - float(buf["attack"]) <= float(B["attack"])]

func _after_step(_delta: float) -> void:
	var started: bool = combat.state == combat.S.SHOT and (combat.shot_key != str(_snap.get("key", "")) or int(_snap.get("state", -1)) != combat.S.SHOT)
	if started:
		var k: String = combat.shot_key
		if k.begins_with("dodge"):
			buf["dodge"] = -9.0
		elif k == "r9_jump":
			buf["jump"] = -9.0
		elif skills.has(k):
			buf["skill"] = -9.0
			_begin_skill(k)
		elif combat._cfg(k).get("attack", false) and k != "draw" and k != "noto":
			buf["attack"] = -9.0
		if k == "draw" or k == "noto":
			pass
	elif combat.combo_queued != bool(_snap.get("queued", false)):
		buf["attack"] = -9.0

func _try_jump() -> bool:
	if weapon != "drawn":
		return false
	var ok: bool = combat.state != combat.S.SHOT and combat.cooldown <= 0.0
	if combat.state == combat.S.SHOT:
		var cfg: Dictionary = combat._cfg(combat.shot_key)
		ok = cfg.has("move_cancel") and combat.shot_t >= float(cfg["move_cancel"]) and combat.hitstop_left == 0
		if ok:
			combat.cancel_log.append({"key": combat.shot_key, "kind": "jump", "shot_t": combat.shot_t})
			combat._end_shot(true)
	if ok:
		combat._fire("r9_jump", _aim_err())
		route_log.append({"t": snappedf(now, 0.001), "ctx": "jump", "branch": "jump", "move": "r9_jump"})
	return ok

func _try_skill(key: String) -> bool:
	var s: Dictionary = skills[key]
	if now < float(skill_cd.get(key, -1.0)):
		return false
	if weapon != str(s.get("requires", "drawn")):
		if combat.state != combat.S.SHOT and combat.cooldown <= 0.0:
			pending_key = key
			_my_pending = key
			combat._fire("draw", 0.0)
			route_log.append({"t": snappedf(now, 0.001), "ctx": "skill", "branch": "skill_draw_first", "move": "draw", "pending": key})
			return true
		return false
	if combat.state != combat.S.SHOT:
		if combat.cooldown > 0.0:
			return false
		combat._fire(key, _aim_err())
		route_log.append({"t": snappedf(now, 0.001), "ctx": "skill", "branch": "skill", "move": key})
		return true
	var lf: Dictionary = s.get("link_from", {})
	if lf.has(combat.shot_key) and combat.shot_t >= float(lf[combat.shot_key]):
		route_log.append({"t": snappedf(now, 0.001), "ctx": "skill", "branch": "skill_link", "move": key, "from": combat.shot_key, "from_t": snappedf(combat.shot_t, 0.001)})
		combat.fire_now(key, _aim_err())
		return true
	return false

func _fire_pending() -> void:
	_my_pending = ""
	super._fire_pending()

# ------------------------------------------------------------------ 普通劍術派生表
func _match(w: Dictionary, ctx: String, cur: String, wpn: String) -> bool:
	if w.has("ctx") and str(w["ctx"]) != ctx:
		return false
	if w.has("weapon") and str(w["weapon"]) != wpn:
		return false
	if w.has("after"):
		var al: Array = w["after"]
		if ctx == "cancel":
			if not al.has(cur):
				return false
		elif not (al.has(last_end_key) and now - last_end_t <= float(w.get("within", 0.0))):
			return false
	if w.has("loco"):
		match str(w["loco"]):
			"sprint":
				if sprint_t < float(r9["sprint"]["min_sprint"]):
					return false
			"back":
				if _move_input().y > -0.5:
					return false
	return true

func _router(ctx: String) -> String:
	var cur: String = combat.shot_key if ctx == "cancel" else ""
	var wpn := weapon
	if ctx == "cancel" and move_ix.has(cur) and _req(cur) == "sheathed":
		var m: Dictionary = moves[move_ix[cur]]
		if bool(m.get("ends_drawn", false)) or combat.shot_t < float(m.get("noto_t", 99.0)):
			wpn = "drawn"            # 居合系收刀前被取消＝刀留手上
	for b in r9["branches"]:
		var br: Dictionary = b
		if not _match(br["when"], ctx, cur, wpn):
			continue
		var mv := str(br["move"])
		if mv == "$selected":
			mv = _sel_key()
		elif mv.begins_with("$selected|"):         # 選中的招符合目前武器狀態就用它，否則用 | 後面的招
			mv = _sel_key() if _req(_sel_key()) == wpn else mv.substr(10)
		if not combat.shots.has(mv):
			continue
		var need := _req(mv)
		var entry := {"t": snappedf(now, 0.001), "ctx": ctx, "branch": br["id"], "move": mv, "prev": cur if cur != "" else last_end_key, "weapon": wpn}
		if need != wpn:
			pending_key = mv
			_my_pending = mv
			mv = "draw" if need == "drawn" else "noto"
			entry["pending"] = pending_key
			entry["move"] = mv
		else:
			combat.fire_opts = (br.get("fire", {}) as Dictionary).duplicate()
		route_log.append(entry)
		_last_route = "%s → %s" % [br.get("label", br["id"]), entry["move"]]
		return mv
	return ""

func _on_shot_finished(key: String, t: float, cancelled: bool) -> void:
	super._on_shot_finished(key, t, cancelled)
	last_end_key = key
	last_end_t = now
	if skills.has(key):
		skill_cd[key] = now + float(skills[key].get("cooldown", 0.0))

var _prof := {}
func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	super._process(delta)
	_prof["proc_us"] = Time.get_ticks_usec() - t0
	if _r9_spark != null:                  # 下一幀（停格中、刀已凍結）依畫面上的刀重算刀刃入口，同候選基底
		var m := sword.global_transform
		var e := _blade_entry(m * GUARD_LOCAL, m * TIP_LOCAL)
		_pooled_spark(e["p"] if not e.is_empty() else _r9_spark)
		_r9_spark = null
	if _my_pending != "" and pending_key != _my_pending:
		pending_key = _my_pending           # 基底的「依選中招式補出招」不得蓋掉派生表／技能排的待出招
	saudio.global_position = actor.global_position + Vector3(0, 1.2, 0)
	if perf_path != "" and tour and tour_t >= TOUR_START_DELAY:
		var vp := get_viewport().get_viewport_rid()
		var st: Dictionary = vfx.stats() if _skill_variant == "r9" else mvfx.stats()
		perf_log.append({"t": snappedf(tour_t - TOUR_START_DELAY, 0.001), "dt_ms": snappedf(delta * 1000.0, 0.01), "fps": Engine.get_frames_per_second(),
			"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.001),
			"cpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(), 0.001),
			"gpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_gpu(vp), 0.001),
			"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "prims": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"skill": skill_key, "vfx": vfx_on, "variant": _skill_variant, "env": env_mode, "lights_on": int(mvfx.light_state().get("vis", 0)),
			"tex_mem": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED), "buf_mem": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED), "proc_us": _prof.get("proc_us", 0), "hit_us": _prof.get("hit_us", 0), "vfx_us": _prof.get("vfx_us", 0), "sparks": st["sparks_est"], "hit_p": st["hit_particles"], "trail_n": st["trail_samples"], "shot_t": snappedf(mvfx.skill_t, 0.001), "frame": Engine.get_frames_drawn()})
	if hud and not tour:
		hud.text = _hud_text()

# ------------------------------------------------------------------ 技能演出（VFX、音效）
func _begin_skill(key: String) -> void:
	skill_key = key
	_skill_variant = vfx_variant
	vfx.enabled = vfx_on
	mvfx.enabled = vfx_on
	if _skill_variant == "r9":
		vfx.begin(skills[key]["vfx"])
	else:
		mvfx.begin(_skill_variant)
	saudio.begin(skills[key]["audio"])

## 骨架更新後（這一幀畫面上的刀）：餵 VFX 與技能音效
func _vfx_frame() -> void:
	if vfx == null or sword == null:
		return
	var tv := Time.get_ticks_usec()
	var dt := get_process_delta_time()
	var active: bool = skill_key != "" and combat.state == combat.S.SHOT and combat.shot_key == skill_key
	if _prewarm_n > 0:
		_prewarm_n -= 1
		if _prewarm_n == 0:
			mvfx.end_prewarm()
	if skill_key != "" and not active:
		vfx.end()
		mvfx.end()
		saudio.end()
		skill_key = ""
	var clock := 0.0 if combat.hitstop_left > 0 else 1.0
	var t: float = combat.shot_t if active else vfx.skill_t + dt
	vfx.frame(sword.global_transform, t, dt, clock, tip_speed)
	mvfx.hitstop = combat.hitstop_left > 0          # R9-C3：命中白光、火焰脈衝與停格同步
	mvfx.frame(combat.shot_t if active else mvfx.skill_t + dt, dt, tip_speed)
	if tour and slashlog_path != "":
		_log_light(active)
	saudio.frame(t, dt, active)
	_trail_lag = vfx.trail_head_lag(sword.global_transform)
	if _dump_path != "" and active:            # R9-C：記錄刀在「角色本地座標」的實際變換（給 Blender 依真實刀路做特效）
		var L := actor.global_transform.affine_inverse() * sword.global_transform
		_dump.append({"t": combat.shot_t, "hs": combat.hitstop_left, "b": [L.basis.x.x, L.basis.x.y, L.basis.x.z, L.basis.y.x, L.basis.y.y, L.basis.y.z, L.basis.z.x, L.basis.z.y, L.basis.z.z], "o": [L.origin.x, L.origin.y, L.origin.z],
			"actor": [actor.global_position.x, actor.global_position.y, actor.global_position.z, actor.rotation.y]})
	_prof["vfx_us"] = Time.get_ticks_usec() - tv
	if tour and slashlog_path != "" and active:
		sync_log.append({"t": snappedf(tour_t - TOUR_START_DELAY, 0.0001), "shot_t": snappedf(combat.shot_t, 0.0001), "hs": combat.hitstop_left,
			"lag": snappedf(_trail_lag, 0.0001), "n": vfx.trail.sample_count(), "blade": snappedf(vfx.blade_level, 0.001), "tip_v": snappedf(tip_speed, 0.01),
			"sparks": vfx.stats()["sparks_est"]})

## R9-C3：光照記錄（每幀）＋地面／木樁／背的螢幕座標（錄影抽格量亮度用）
func _log_light(active: bool) -> void:
	var to := enemy_pos - actor.global_position
	to.y = 0.0
	var fwd := to.normalized() if to.length() > 0.1 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP)
	var probes := {"floor_r": actor.global_position + right * 0.7 + Vector3(0, 0.01, 0), "floor_l": actor.global_position - right * 0.7 + Vector3(0, 0.01, 0),
		"floor_mid": actor.global_position + to * 0.5 + right * 0.45 + Vector3(0, 0.01, 0), "dummy": enemy_pos - fwd * 0.27 + Vector3(0, 0.45, 0),
		"back": actor.global_position - fwd * 0.16 + Vector3(0, 1.05, 0)}
	var sp := {}
	for k in probes:
		var w: Vector3 = probes[k]
		if not cam.is_position_behind(w):
			var u := cam.unproject_position(w)
			sp[k] = [int(u.x), int(u.y)]
	light_log.append({"t": snappedf(tour_t - TOUR_START_DELAY, 0.0001), "f": Engine.get_frames_drawn(), "label": cur_label, "variant": _skill_variant, "vfx": vfx_on,
		"active": active, "shot_t": snappedf(mvfx.skill_t, 0.001), "hs": combat.hitstop_left, "L": mvfx.light_state().duplicate(), "lights": mvfx.light_count(),
		"sword_a": [snappedf((sword.global_transform * Vector3.ZERO).x, 0.001), snappedf((sword.global_transform * Vector3.ZERO).y, 0.001), snappedf((sword.global_transform * Vector3.ZERO).z, 0.001)],
		"sword_b": [snappedf((sword.global_transform * Vector3(0, 1.085, 0)).x, 0.001), snappedf((sword.global_transform * Vector3(0, 1.085, 0)).y, 0.001), snappedf((sword.global_transform * Vector3(0, 1.085, 0)).z, 0.001)],
		"probes": sp, "vp": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]})

func _on_hit(info: Dictionary) -> void:
	var th := Time.get_ticks_usec()
	super._on_hit(info)
	_prof["hit_us"] = Time.get_ticks_usec() - th
	# 普通命中的白色火花改用預先建好的 4 顆輪流用：候選基底每次命中都新建 SphereMesh＋材質，實測命中後那一幀 process 卡 35–45 ms（R9 量測）
	_r9_spark = _pending_spark
	_pending_spark = null
	if skills.has(str(info.get("key", ""))) and vfx_on:
		_r9_spark = null                    # 技能命中且特效開著：由日之呼吸命中火焰取代
	var key := str(info.get("key", ""))
	var dmg := 1
	if skills.has(key):
		dmg = int(skills[key].get("damage", 1))
		dummy_hp -= dmg - 1
		var p: Vector3 = info.get("entry", info["pos"])
		var nrm := p - enemy_pos
		nrm.y = 0.0
		if _skill_variant == "r9":
			vfx.hit(p, info.get("dir", Vector3.DOWN), nrm)
		else:
			mvfx.hit(p, info.get("dir", Vector3.DOWN), nrm)
		saudio.hit(combat.shot_t)
	dmg_log.append({"t": snappedf(tour_t - TOUR_START_DELAY, 0.001), "key": key, "strike": info.get("strike", 0), "shot_t": snappedf(float(info.get("shot_t", 0.0)), 0.001),
		"dmg": dmg, "hp": dummy_hp, "depth": snappedf(float(info.get("depth", 0.0)), 0.001), "blade_u": info.get("blade_u", -1.0), "skill": skills.has(key), "label": cur_label})

var _r9_spark: Variant = null
var _spark_pool: Array = []
var _spark_ix := 0

func _mk_spark_pool() -> void:
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 16
	sm.rings = 8
	for i in 4:
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		var mt := StandardMaterial3D.new()
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mt.albedo_color = Color(1.0, 0.85, 0.5, 0.0)
		mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = mt
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = Vector3(0, -50, 0)
		_spark_pool.append(mi)

## 與候選基底同樣的火花（刀刃入口、0.15 s 由 1× 放大到 2.8× 並淡出），只是重用節點
func _pooled_spark(p: Vector3) -> void:
	var mi: MeshInstance3D = _spark_pool[_spark_ix % _spark_pool.size()]
	_spark_ix += 1
	var mt := mi.material_override as StandardMaterial3D
	mi.global_position = p
	mi.scale = Vector3.ONE
	mt.albedo_color = Color(1.0, 0.85, 0.5, 1.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(2.8, 2.8, 2.8), 0.15)
	tw.tween_property(mt, "albedo_color:a", 0.0, 0.15)

# ------------------------------------------------------------------ 錄影相機
## --cam=side：垂直於「角色→木樁」連線、站右手側再往正面轉 20°，持續跟拍（出招中鎖住不晃）；
## --cam=front：角色右前方 45°、3.8 m（看圓舞的整個圓弧）；其他＝基底第三人稱（身後偏右肩）
var _r9cam_init := false
func _update_cam(snap: bool) -> void:
	var args := OS.get_cmdline_user_args()
	var mode := "side" if args.has("--cam=side") else ("front" if args.has("--cam=front") else "")
	if mode == "":
		super._update_cam(snap)
		return
	var firing: bool = combat.state == combat.S.SHOT and bool(combat._cfg(combat.shot_key).get("attack", false))
	var want := Vector3.ZERO
	var look := Vector3.ZERO
	if mode == "side":
		var to := enemy_pos - actor.global_position
		to.y = 0.0
		var d := clampf(to.length(), 1.0, 6.0)
		var yaw := atan2(to.x, to.z)
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		var right := Vector3(-cos(yaw), 0, sin(yaw))
		look = actor.global_position + dir * (d * 0.5) + Vector3(0, 1.0, 0)
		want = look + right.rotated(Vector3.UP, -deg_to_rad(20.0)) * maxf(5.0, d * 1.4) + Vector3(0, 0.6, 0)
	else:
		var fwd := Vector3(sin(actor.rotation.y), 0, cos(actor.rotation.y))
		look = actor.global_position + fwd * 0.7 + Vector3(0, 1.0, 0)
		want = actor.global_position + fwd.rotated(Vector3.UP, -deg_to_rad(45.0)) * 3.8 + Vector3(0, 1.35, 0)
	if snap or not _r9cam_init:
		_r9cam_init = true
		cam.global_position = want
		cam.look_at(look, Vector3.UP)
		return
	if firing and mode == "side":
		return                              # 出招中鎖住（不跟著位移晃）
	var k := 1.0 - exp(-5.0 * get_process_delta_time())
	cam.global_position = cam.global_position.lerp(want, k)
	var cur_look := cam.global_position + (-cam.global_basis.z) * 3.0
	cam.look_at(cur_look.lerp(look, k * 1.5), Vector3.UP)

# ------------------------------------------------------------------ 導覽與記錄
func _tour_step(delta: float) -> void:
	var prev := tour_ix
	super._tour_step(delta)
	if tour_ix != prev and tour_ix >= 0 and tour_ix < tour_steps.size():
		var st: Dictionary = tour_steps[tour_ix]
		_ev_q = []
		for e in st.get("ev", []):
			_ev_q.append([tour_t + float(e[0]), str(e[1])])
		if st.has("vfx"):
			vfx_on = bool(st["vfx"])
			vfx.enabled = vfx_on
			mvfx.enabled = vfx_on
		if st.has("variant"):
			vfx_variant = str(st["variant"])
		if st.has("env") and str(st["env"]) != env_mode:
			_apply_env(str(st["env"]))

func _finish_tour() -> void:
	if slashlog_path != "":
		var f := FileAccess.open(slashlog_path.get_basename() + "_r9.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"routes": route_log, "dmg": dmg_log, "cancels": combat.cancel_log, "audio": saudio.ev_log, "hits_vfx": vfx.hits_spawned, "sync": sync_log, "lights": light_log, "env": env_mode}))
		f.close()
	if _dump_path != "":
		var df := FileAccess.open(_dump_path, FileAccess.WRITE)
		df.store_string(JSON.stringify(_dump))
		df.close()
	if perf_path != "":
		var pf := FileAccess.open(perf_path, FileAccess.WRITE)
		pf.store_string(JSON.stringify(perf_log))
		pf.close()
	super._finish_tour()

func _hud_text() -> String:
	var cd := maxf(0.0, float(skill_cd.get("sun_enbu", 0.0)) - now)
	var lines := ["緣一 R9 綜合試玩（候選 ART_REVIEW）  武器：%s   特效：%s（V）  圓舞特效版本：%s（C 切換）   FPS %d" % ["刀在手上" if weapon == "drawn" else "居合構（刀在鞘）", "開" if vfx_on else "關", {"r9": "R9 程式刀光", "A": "Blender A 銳利", "B": "Blender B 流動", "C1": "C1 爆發", "C2": "C2 流焰", "C3": "C3 神火", "L1": "L1 自然火光", "L2": "L2 動畫爆發"}.get(vfx_variant, vfx_variant), Engine.get_frames_per_second()],
		"環境：%s（N 切換白天／黃昏森林）" % ("黃昏森林" if env_mode == "dusk" else "白天"),
		"WASD 移動  Shift+W 衝刺  Space 閃避  F 跳躍  J/左鍵 攻擊  L/右鍵 日之呼吸・圓舞%s  G 拔刀/收刀" % ("（冷卻 %.1f s）" % cd if cd > 0.0 else ""),
		"派生：站立＝起手招／衝刺中＝突進逆袈裟／閃避中後＝反擊／跳躍中＝空中下劈／後退＋攻擊＝退步縱斬／居合構＝居合斬",
		"起手招（1–0 選，Tab 換頁）："]
	var page := sel / 10
	for i in range(page * 10, mini(moves.size(), page * 10 + 10)):
		var m: Dictionary = moves[i]
		lines.append("%s %d  %s" % ["▶" if i == sel else "  ", (i % 10 + 1) % 10, m["label"]])
	lines.append("出招中：%s  t=%.2f   上一次派生：%s" % [combat.shot_key if combat.state == combat.S.SHOT else "—", combat.shot_t, _last_route])
	return "\n".join(lines)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo:
		var ke := e as InputEventKey
		if ke.keycode == KEY_F or ke.keycode == KEY_L:
			return                         # F＝跳躍、L＝技能（在 _filter_input 讀）；不要讓基底拿 F 去切彈簧骨
		if ke.keycode == KEY_N:
			_apply_env("day" if env_mode == "dusk" else "dusk")
			return
		if ke.keycode == KEY_V:
			vfx_on = not vfx_on
			vfx.enabled = vfx_on
			mvfx.enabled = vfx_on
			return
		if ke.keycode == KEY_C:                    # 圓舞特效版本：程式刀光 → Blender A → B → C1 → C2 → C3
			var order := ["r9", "A", "B", "C1", "C2", "C3", "L1", "L2"]          # R9-C2：加 C1／C2／C3；R9-C3：加 L1／L2
			vfx_variant = order[(order.find(vfx_variant) + 1) % order.size()]
			return
	super._unhandled_input(e)
