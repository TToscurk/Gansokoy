extends "res://characters/yoriichi/v24_isshin/fire_research_v2/sun_fire_hekira_demo.gd"
## 緣一 R15 日之呼吸候選統一試玩（ART_REVIEW）：同一場景選所有日之呼吸型，木樁實打、自由第三人稱鏡頭、可重設位置。
## - R15 新候選（r15/skills/*.json，notes/r15/build_*_r15.py 產生）：飛輪陽炎、幻日紅、圓舞（新）、圓舞一閃、碧羅天（新）、灼骨炎陽、斜陽轉身、輝輝恩光、日暈之龍・頭舞。
##   還沒有 json 的型在清單上標「未完成」，按 L 不會出招。
## - 已有成果原樣接入（只讀它們的 json，不改檔）：R13 炎舞（ART_APPROVED）、R12 火車（已驗收；預設 Blender 火焰 KS12，B 切統一系統）、
##   R14 陽華突（ART_REVIEW 第 2 版；T 換地面／空中目標）、R9 圓舞與 R11 碧羅天（原版，供比較）、烈日紅鏡。
## - 火焰全部走統一系統 sun_fire.gd＋sun_fire_profiles.json（R15 每型一筆 profile）；幻日紅殘影＝角色姿勢快照（本場景）；
##   日暈之龍的龍＝既有 characters/yoriichi/vfx/sun_dragon.gd（正式特效，只實例化、不改檔）。
## 操作：WASD 移動  L／右鍵 出招（圓舞（新）時 Shift+L＝圓舞一閃）  Z／X 換型（自動回到該型的木樁前）  T 換目標  R 重設位置
##       Space 閃避（蓄勢段可取消）  V 特效開關  B 火車火焰版本  Q／E、←／→ 轉鏡頭  H 說明。技能不接管鏡頭。
## 功能檢查：-- --r15-check=OUT_DIR [--only=id1,id2] [--shots]（每型：設計距離出招、命中次數、牆、蓄勢取消、收招取消；--shots 每型存 2 張圖）
const R15_DIR := "res://characters/yoriichi/v24_isshin/r15/"
const ThirdCam = preload("res://characters/yoriichi/v24_isshin/r12/third_person_cam.gd")
const AIR_R := 0.3
## R15 的型（清單順序＝批次順序）；沒有 json＝未完成
const R15_ORDER := ["sun_hirin_kagerou", "sun_genjitsu", "sun_enbu_r15", "sun_enbu_issen", "sun_hekiraten_r15",
	"sun_shakkotsu", "sun_shayou_tenshin", "sun_kiki_onkou", "sun_nichirin_dragon"]
const R15_NAMES := {"sun_hirin_kagerou": "飛輪陽炎", "sun_genjitsu": "幻日紅", "sun_enbu_r15": "圓舞（R15 新）", "sun_enbu_issen": "圓舞一閃",
	"sun_hekiraten_r15": "碧羅天（R15 新）", "sun_shakkotsu": "灼骨炎陽", "sun_shayou_tenshin": "斜陽轉身", "sun_kiki_onkou": "輝輝恩光",
	"sun_nichirin_dragon": "日暈之龍・頭舞"}
## 既有成果：json、狀態、目標、蓄勢取消
const OLD := {
	"sun_enbu_double": {"json": "res://characters/yoriichi/v24_isshin/r13/enbu_r13.json", "status": "ART_APPROVED（R13，使用者已驗收，凍結）",
		"source": "#80→#81 梟 c5060 a000_003000→003001", "targets": [{"name": "木樁 2.75 m", "pos": [0.0, 0.0, 2.75]}, {"name": "木樁 2.0 m（近）", "pos": [0.0, 0.0, 2.0]}]},
	"sun_kasha": {"json": "res://characters/yoriichi/v24_isshin/r12/kasha_r12.json", "status": "ART_APPROVED（R12 火車，使用者已驗收）",
		"source": "#83 梟 c5060 a000_003003", "targets": [{"name": "木樁 3.2 m", "pos": [0.0, 0.0, 3.2]}], "cancel_fade_in": 0.16},
	"sun_youkatotsu": {"json": "res://characters/yoriichi/v24_isshin/r14/youka_r14.json", "status": "ART_REVIEW 第 2 版（R14，待驗收）",
		"source": "#221 葦名弦一郎 c7100 a000_003062", "targets": [{"name": "地面木樁 1.3 m", "pos": [0.0, 0.0, 1.3]},
			{"name": "空中目標（球心高 2.6 m、前方 2.3 m）", "pos": [0.0, 2.6, 2.3], "air": true},
			{"name": "遠處空中目標（只在火焰延伸範圍）", "pos": [0.0, 2.95, 2.75], "air": true}]},
}
const ORIG := {"sun_enbu": "R9 圓舞（原版，保留供比較）", "sun_hekiraten": "R11 碧羅天（原版，保留供比較）", "sun_retsujitsu": "烈日紅鏡（R10 原版）"}
var meta := {}                 # key -> {status, source, timeline, targets, charge_cancel, cancel_fade_in, afterimage, dragon, label}
var missing: Array = []        # R15 未完成的型
var target_ix := 0
var kasha_unified := false     # 火車：false＝Blender KS12（R12 驗收時的預設），true＝統一系統火環
var _air := false
var _air_y := 0.0
var _air_mi: MeshInstance3D
var _ghosts: Array = []
var _fx_done := {}             # 這一招已觸發的殘影／龍（時間索引）
var _fx_key := ""
var _msg := ""
var _msg_t := 0.0
var _skl: Skeleton3D
var _r15_dir := ""
var _only: Array = []
var _shots_on := false
var _ck := {"phase": 0, "t": 0.0, "t0": 0.0, "queue": [], "cur": {}, "results": [], "shots": [], "frames": []}
var _arc := {}                 # 幻日紅：這一招的繞行弧（出招當下的角色位置與目標）

func _pre_setup() -> void:
	super._pre_setup()
	var base: Dictionary = (skills["sun_hekiraten"] as Dictionary).duplicate(true)   # 輸入／派生沿用；碧羅天本身不動
	for k in ["vfx_variants", "vfx_map", "vfx", "_anim"]:
		base.erase(k)
	# 既有成果（只讀）
	for key in OLD:
		var o: Dictionary = OLD[key]
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(o["json"])))
		var s: Dictionary = base.duplicate(true)
		s["name"] = str(d.get("name", key))
		s["shot"] = d["shot"]
		s["audio"] = d["audio"]
		s["_anim"] = d.get("_doc", "")
		if d.has("damage"):
			s["damage"] = int(d["damage"])
		if d.has("cooldown"):
			s["cooldown"] = float(d["cooldown"])
		for k in ["vfx_variants", "vfx_map", "vfx"]:
			if d.has(k):
				s[k] = d[k]
		_register(key, s)
		meta[key] = {"status": o["status"], "source": o["source"], "targets": o["targets"], "charge_cancel": float(d.get("charge_cancel", 0.0)),
			"cancel_fade_in": float(o.get("cancel_fade_in", 0.0)), "timeline": "", "label": s["name"]}
	# R15 候選
	for key in R15_ORDER:
		var p: String = R15_DIR + "skills/" + key + ".json"
		if not FileAccess.file_exists(p):
			missing.append(key)
			continue
		var d2: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(p))
		var s2: Dictionary = base.duplicate(true)
		s2["name"] = str(d2.get("name", key))
		s2["shot"] = d2["shot"]
		s2["audio"] = d2.get("audio", {})
		s2["damage"] = int(d2.get("damage", 3))
		s2["cooldown"] = float(d2.get("cooldown", 1.2))
		s2["_anim"] = d2.get("_doc", "")
		_register(key, s2)
		meta[key] = {"status": str(d2.get("status", "ART_REVIEW")), "source": str(d2.get("source", "")), "timeline": str(d2.get("timeline", "")),
			"targets": d2.get("targets", [{"name": "木樁 2.5 m", "pos": [0.0, 0.0, 2.5]}]), "charge_cancel": float(d2.get("charge_cancel", 0.0)),
			"cancel_fade_in": float(d2.get("cancel_fade_in", 0.0)), "afterimage": d2.get("afterimage", {}), "dragon": d2.get("dragon", {}), "arc": d2.get("arc", {}),
			"knock": d2.get("knock", []),
			"issues": d2.get("issues", []), "label": s2["name"]}
	for key in ORIG:
		if skills.has(key):
			meta[key] = {"status": ORIG[key], "source": "", "timeline": "", "targets": [{"name": "木樁 1.6 m", "pos": [0.0, 0.0, 1.6]}],
				"charge_cancel": 0.0, "cancel_fade_in": 0.16 if key == "sun_hekiraten" else 0.0, "label": skills[key]["name"]}
	var order: Array = []
	for key in R15_ORDER:
		if skills.has(key):
			order.append(key)
	for key in ["sun_enbu_double", "sun_kasha", "sun_youkatotsu", "sun_enbu", "sun_hekiraten", "sun_retsujitsu"]:
		if skills.has(key):
			order.append(key)
	skill_order = order
	cur_skill = str(order[0])

func _register(key: String, s: Dictionary) -> void:
	skills[key] = s
	var atk_cancel := float((s["shot"] as Dictionary).get("attack_cancel", 1.1))
	for k2 in skills:                                   # 其他型「接在這一型之後」的時間＝這一型自己的攻擊取消時間
		var lf: Dictionary = (skills[k2] as Dictionary).get("link_from", {})
		if k2 != key and lf.has("sun_hekiraten"):
			lf[key] = atk_cancel
	combat.extra_shots[key] = _clean(s["shot"])

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--r15-check="):
			_r15_dir = a.substr(12)
		elif a.begins_with("--only="):
			_only = Array(a.substr(7).split(","))
		elif a == "--shots":
			_shots_on = true
	super._ready()
	_skl = actor.get_node("BodyVisual/緣一_fbx/Armature/Skeleton3D") as Skeleton3D
	_air_mi = MeshInstance3D.new()
	_air_mi.name = "AirTarget"
	var sm := SphereMesh.new()
	sm.radius = AIR_R
	sm.height = AIR_R * 2.0
	_air_mi.mesh = sm
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(0.62, 0.16, 0.12)
	_air_mi.material_override = mt
	enemy.add_child(_air_mi)
	cur_skill = str(skill_order[0])
	if _r15_dir != "":
		Engine.max_fps = 60
		hud_on = false
		_ck_build_queue()
	_reset_to_dummy()

## 回到這一型的目標前（目標＝這一型 json 的 targets[target_ix]）
func _reset_to_dummy() -> void:
	actor.position = Vector3.ZERO
	actor.rotation = Vector3.ZERO
	orbit_speed = 0.0
	_last_pos = Vector3.INF                 # 位移碰撞代理：瞬移後重新起算
	if meta.is_empty() or not meta.has(cur_skill):
		enemy_pos = Vector3(0, 0, 1.6)
		return
	var tl: Array = meta[cur_skill]["targets"]
	target_ix = clampi(target_ix, 0, tl.size() - 1)
	var tg: Dictionary = tl[target_ix]
	var p: Array = tg["pos"]
	enemy_pos = Vector3(float(p[0]), 0.0, float(p[2]))
	_air = bool(tg.get("air", false))
	_air_y = float(p[1])
	if _air_mi:
		_air_mi.visible = _air
		_air_mi.position = Vector3(0, _air_y, 0)
	for kid in enemy_kids:
		(kid[0] as Node3D).visible = not _air
	judge.radius_fn = _air_r if _air else BladeJudge.dummy_r

func _air_r(y: float) -> float:
	return sqrt(maxf(0.0, AIR_R * AIR_R - pow(y - AIR_R, 2.0)))

func _shared_hit_test() -> Dictionary:
	if not _air:
		return super._shared_hit_test()
	if sword == null:
		return {}
	var cfg: Dictionary = combat._cfg(combat.shot_key)
	return judge.test(sword.global_transform, Vector3(enemy_pos.x, _air_y - AIR_R, enemy_pos.z), combat.shot_t, get_process_delta_time(),
		cfg.get("strikes", []), tip_v, tip_speed)

## 圓舞（新）選中時 Shift＋L＝圓舞一閃（兩型也都能用 Z／X 直接選）
func _try_skill(key: String) -> bool:
	if key == "sun_enbu_r15" and skills.has("sun_enbu_issen") and Input.is_key_pressed(KEY_SHIFT):
		key = "sun_enbu_issen"
	if missing.has(key):
		return false
	return super._try_skill(key)

## 火車：預設 Blender 火焰 KS12（R12 驗收時的預設），B 切統一系統火環；其他型一律統一系統
func _begin_skill(key: String) -> void:
	_fx_key = key
	_fx_done.clear()
	if key == "sun_kasha" and not kasha_unified:
		var v := vfx_variant
		vfx_variant = _old_variant
		fire.clear()
		super._begin_skill(key)
		vfx_variant = v
		return
	super._begin_skill(key)

func _router(ctx: String) -> String:
	var from := combat.shot_key if combat.state == combat.S.SHOT else ""
	var k := super._router(ctx)
	if ctx == "cancel" and k != "" and meta.has(from) and float(meta[from].get("cancel_fade_in", 0.0)) > 0.0:
		combat.fire_opts["fade_in"] = float(meta[from]["cancel_fade_in"])
	return k

## 蓄勢段（出手前）按閃避＝取消技能、直接閃避；之後照各型 dodge_cancel
func _filter_input(delta: float, dodge: bool, attack: bool) -> Array:
	var io: Array = super._filter_input(delta, dodge, attack)
	if io[0] and combat.state == combat.S.SHOT and meta.has(combat.shot_key) and combat.hitstop_left == 0 \
			and combat.shot_t < float(meta[combat.shot_key].get("charge_cancel", 0.0)):
		var key := combat.shot_key
		var mx := _move_input().x
		combat._end_shot(true)
		combat.cancel_log.append({"key": key, "kind": "charge_dodge", "shot_t": combat.shot_t})
		buf["dodge"] = -9.0
		combat._fire("dodge_l" if mx < 0.0 else "dodge_r", _aim_err())
		return [false, false]
	return io

## 繞行弧（幻日紅，skill json 的 arc）：出招當下記下角色位置與「實際」目標，依技能時間沿弧移動（動畫根位移不用：travel_scale 0；
## 角色朝向照動畫的 root_yaw 轉 phi）；位置在 R11 的移動代理掃掠之前設定，所以牆一樣擋得住；半徑不小於 r_min（不穿過木樁）
func _after_step(delta: float) -> void:
	_arc_drive()
	super._after_step(delta)

## 受擊擊退（候選專用）：skill json 有 knock（每刀擊退 m）就照它；日暈之龍五刀繞著木樁砍，前四刀不擊退、只有收尾推開，
## 否則基底每刀推 0.45–0.6 m 會把木樁推離設計的繞行路線。沒有 knock 的招式＝基底行為不變。
func _on_hit(info: Dictionary) -> void:
	super._on_hit(info)
	var key := str(info.get("key", ""))
	if not meta.has(key):
		return
	var kl: Array = meta[key].get("knock", [])
	if kl.is_empty():
		return
	var km := float(kl[mini(int(info.get("strike", 0)), kl.size() - 1)])
	if km <= 0.0:
		knock_t = -1.0
	else:
		var kd := knock_from - actor.global_position
		kd.y = 0.0
		if kd.length() > 0.01:
			knock_to = knock_from + kd.normalized() * km

func _arc_drive() -> void:
	var key := combat.shot_key if combat.state == combat.S.SHOT else ""
	if key == "" or not meta.has(key) or (meta[key].get("arc", {}) as Dictionary).is_empty():
		_arc = {}
		return
	var a: Dictionary = meta[key]["arc"]
	if _arc.is_empty() or str(_arc["key"]) != key or combat.shot_t + 1e-4 < float(_arc["last_t"]):
		var to := enemy_pos - actor.global_position
		to.y = 0.0
		var v0 := -to.normalized() if to.length() > 0.05 else actor.global_basis.z * -1.0
		_arc = {"key": key, "tg": Vector3(enemy_pos.x, 0.0, enemy_pos.z), "d": maxf(to.length(), 0.05), "v0": v0, "last_t": combat.shot_t}
	var u := clampf((combat.shot_t - float(a["t0"])) / maxf(float(a["t1"]) - float(a["t0"]), 1e-3), 0.0, 1.0)
	var eo := float(a.get("ease_out", 0.55))
	var e := eo * (1.0 - pow(1.0 - u, 2.0)) + (1.0 - eo) * u * u * (3.0 - 2.0 * u)
	var r := maxf(lerpf(float(_arc["d"]), float(a["r_end"]), e), float(a.get("r_min", 1.0)))
	var p: Vector3 = (_arc["tg"] as Vector3) + (_arc["v0"] as Vector3).rotated(Vector3.UP, deg_to_rad(float(a["phi_deg"])) * e) * r
	actor.global_position = Vector3(p.x, actor.global_position.y, p.z)
	_arc["last_t"] = combat.shot_t

func _update_cam(snap: bool) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam="):
			super._update_cam(snap)
			return
	ThirdCam.update(self, snap)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo:
		match (e as InputEventKey).keycode:
			KEY_B:
				kasha_unified = not kasha_unified
				_flash_msg("火車火焰：%s" % ("統一系統火環" if kasha_unified else "Blender 火焰 KS12（R12 預設）"))
				return
			KEY_T:
				if meta.has(cur_skill):
					target_ix = (target_ix + 1) % (meta[cur_skill]["targets"] as Array).size()
				_reset_to_dummy()
				return
			KEY_Z, KEY_X:
				if combat.state != combat.S.SHOT:
					super._unhandled_input(e)
					target_ix = 0
					_reset_to_dummy()
				return
	super._unhandled_input(e)

func _flash_msg(s: String) -> void:
	_msg = s
	_msg_t = 2.0

func _hud_text() -> String:
	var base := super._hud_text()
	var nl := base.find("\n")                           # 第一行是碧羅天特效試玩的標題，換掉
	if nl >= 0:
		base = base.substr(nl + 1)
	var m: Dictionary = meta.get(cur_skill, {})
	var tl: Array = m.get("targets", [])
	var tname: String = str((tl[target_ix] as Dictionary)["name"]) if target_ix < tl.size() else "—"
	var lines := ["【R15 日之呼吸候選試玩】%s（%s）　狀態：%s　來源：%s" % [str(skills[cur_skill]["name"]), cur_skill, str(m.get("status", "")), str(m.get("source", ""))]]
	if str(m.get("timeline", "")) != "":
		lines.append("節奏：" + str(m["timeline"]))
	lines.append("目標：%s（T 切換）　R 重設　Z／X 換型　特效 %s（V）%s%s" % [tname, "開" if vfx_on else "關",
		"　火車火焰：%s（B）" % ("統一火環" if kasha_unified else "Blender KS12") if cur_skill == "sun_kasha" else "",
		"　Shift+L＝圓舞一閃" if cur_skill == "sun_enbu_r15" else ""])
	var miss_names: Array = []
	for k in missing:
		miss_names.append(R15_NAMES.get(k, k))
	if not miss_names.is_empty():
		lines.append("未完成（不能出招）：" + "、".join(miss_names))
	if _msg_t > 0.0:
		lines.append(_msg)
	return "\n".join(lines) + "\n" + base

# ------------------------------------------------------------------ 殘影（幻日紅）與龍（日暈之龍）：照技能時間觸發
func _vfx_frame() -> void:
	super._vfx_frame()
	var on: bool = combat.state == combat.S.SHOT and combat.shot_key == _fx_key and meta.has(_fx_key)
	if on and vfx_on and combat.hitstop_left == 0:
		var ai: Dictionary = meta[_fx_key].get("afterimage", {})
		var times: Array = ai.get("times", [])
		for i in times.size():
			if not _fx_done.has("g%d" % i) and combat.shot_t >= float(times[i]):
				_fx_done["g%d" % i] = true
				_spawn_ghost(float(ai.get("life", 0.14)), float(ai.get("alpha", 0.5)), ai.get("color", [1.0, 0.45, 0.12]))
		var dg: Dictionary = meta[_fx_key].get("dragon", {})
		if not dg.is_empty() and not _fx_done.has("dragon") and combat.shot_t >= float(dg.get("at", 0.0)):
			_fx_done["dragon"] = true
			_spawn_dragon(dg)
	if _r15_dir != "" and int(_ck["phase"]) > 0 and int(_ck["phase"]) < 9:
		_ck_log()

func _spawn_ghost(life: float, alpha: float, col: Array) -> void:
	for mi: MeshInstance3D in actor.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null or mi.name == "AirTarget":
			continue
		var m: Mesh = mi.mesh
		if not mi.skeleton.is_empty() and mi.skin != null:
			m = mi.bake_mesh_from_current_skeleton_pose()
		if m == null:
			continue
		var g := MeshInstance3D.new()
		g.mesh = m
		g.top_level = true
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)
		g.global_transform = mi.global_transform
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(float(col[0]), float(col[1]), float(col[2]), alpha)
		g.material_override = mat
		_ghosts.append({"node": g, "mat": mat, "t": 0.0, "life": life, "a": alpha})

func _spawn_dragon(dg: Dictionary) -> void:
	var xf := actor.global_transform
	xf.origin += actor.global_basis * Vector3(0.0, float(dg.get("y", 0.0)), float(dg.get("fwd", 0.0)))
	var d := SunDragon.spawn(actor, xf)
	if d == null:
		return
	d.reveal_time = float(dg.get("reveal", 0.55))
	d.hold_time = float(dg.get("hold", 0.35))
	d.burn_time = float(dg.get("burn", 0.6))
	d.intensity = float(dg.get("intensity", 1.6))
	if dg.has("scale"):
		d.scale = Vector3.ONE * float(dg["scale"])

func _process(delta: float) -> void:
	super._process(delta)
	_msg_t = maxf(0.0, _msg_t - delta)
	for i in range(_ghosts.size() - 1, -1, -1):
		var g: Dictionary = _ghosts[i]
		if combat.hitstop_left == 0:
			g["t"] = float(g["t"]) + delta
		var k := clampf(float(g["t"]) / float(g["life"]), 0.0, 1.0)
		var mat: StandardMaterial3D = g["mat"]
		mat.albedo_color.a = float(g["a"]) * (1.0 - k)
		if k >= 1.0:
			(g["node"] as Node).queue_free()
			_ghosts.remove_at(i)
	if _r15_dir != "":
		_ck_step(delta)

# ------------------------------------------------------------------ 功能檢查（一次性；每型：設計距離、牆、蓄勢取消、收招取消）
func _ck_build_queue() -> void:
	var q: Array = []
	for key in skill_order:
		if not _only.is_empty() and not _only.has(key):
			continue
		if ORIG.has(key):
			continue
		var cfg: Dictionary = skills[key]["shot"]
		q.append({"key": key, "test": "main", "tix": 0})
		if not OLD.has(key):          # 牆測試：每一支新招都做（含沒有 lunges 的幻日紅繞行弧與日暈之龍的瞬步）
			q.append({"key": key, "test": "wall", "tix": 0})
		if float(meta[key].get("charge_cancel", 0.0)) > 0.0 and not OLD.has(key):
			q.append({"key": key, "test": "charge_cancel", "tix": 0})
		if cfg.has("dodge_cancel") and not OLD.has(key):
			q.append({"key": key, "test": "recover_cancel", "tix": 0})
	_ck["queue"] = q

func _ck_step(delta: float) -> void:
	_ck["t"] = float(_ck["t"]) + delta
	var t := float(_ck["t"])
	var idle: bool = combat.state != combat.S.SHOT and combat.cooldown <= 0.0
	var cur: Dictionary = _ck["cur"]
	if int(_ck["phase"]) == 0:
		if t > 1.5 and idle:
			_ck["phase"] = 1
		return
	if int(_ck["phase"]) == 9:
		return
	if cur.is_empty():
		if (_ck["queue"] as Array).is_empty():
			_ck_finish()
			return
		if not idle:
			return
		cur = (_ck["queue"] as Array).pop_front()
		_ck["cur"] = cur
		cur_skill = str(cur["key"])
		target_ix = int(cur["tix"])
		_reset_to_dummy()
		skill_cd.erase(cur_skill)
		cur["t0"] = t
		cur["hp0"] = dummy_hp
		cur["dmg0"] = dmg_log.size()
		cur["cancel0"] = combat.cancel_log.size()
		cur["fit0"] = combat.fit_log.size()
		cur["maxz"] = -99.0
		cur["minfoot"] = 99.0
		cur["sent"] = false
		cur["started"] = false
		cur["shots_taken"] = []
		if str(cur["test"]) == "wall":
			var wz := 1.2
			_add_wall(Vector3(0.0, 0.0, wz + 0.125), 0.0, Vector3(6.0, 2.2, 0.25))
			cur["wall"] = get_child(get_child_count() - 1)
			cur["wall_z"] = wz
		buf["skill"] = now
		return
	var key := str(cur["key"])
	var on: bool = combat.state == combat.S.SHOT and combat.shot_key == key
	if on:
		cur["started"] = true
		cur["maxz"] = maxf(float(cur["maxz"]), actor.global_position.z)
		var cfg: Dictionary = combat._cfg(key)
		if str(cur["test"]) == "charge_cancel" and not bool(cur["sent"]) and combat.shot_t >= float(meta[key]["charge_cancel"]) * 0.6:
			buf["dodge"] = now
			cur["sent"] = true
		elif str(cur["test"]) == "recover_cancel" and not bool(cur["sent"]) and combat.shot_t >= float(cfg.get("dodge_cancel", 99.0)) + 0.05:
			buf["dodge"] = now
			cur["sent"] = true
		if _shots_on and str(cur["test"]) == "main":
			var want: Array = (meta[key].get("shots", []) as Array) if meta[key].has("shots") else []
			if want.is_empty():
				var st: Array = cfg.get("strikes", [])
				if not st.is_empty():
					want = [float(st[0][0]) + 0.02, float(st[st.size() - 1][1]) + 0.12]
			for i in want.size():
				if not (cur["shots_taken"] as Array).has(i) and combat.shot_t >= float(want[i]) and combat.hitstop_left == 0:
					(cur["shots_taken"] as Array).append(i)
					await RenderingServer.frame_post_draw
					(_ck["shots"] as Array).append({"key": key, "i": i, "st": snappedf(combat.shot_t, 0.001), "img": get_viewport().get_texture().get_image()})
	elif bool(cur["started"]) and idle or t - float(cur["t0"]) > 12.0:
		_ck_close(cur)

func _ck_close(cur: Dictionary) -> void:
	var key := str(cur["key"])
	var hits: Array = []
	for i in range(int(cur["dmg0"]), dmg_log.size()):
		if str(dmg_log[i]["key"]) == key:
			hits.append({"strike": dmg_log[i]["strike"], "shot_t": dmg_log[i]["shot_t"], "dmg": dmg_log[i]["dmg"]})
	var cancels: Array = combat.cancel_log.slice(int(cur["cancel0"]))
	var fits: Array = combat.fit_log.slice(int(cur["fit0"]))
	var res := {"key": key, "test": cur["test"], "hits": hits, "n_strikes": (combat._cfg(key).get("strikes", []) as Array).size(), "hp_loss": int(cur["hp0"]) - dummy_hp,
		"cancels": cancels, "fits": fits, "max_z": snappedf(float(cur["maxz"]), 0.001), "end_pos": _v3(actor.global_position), "end_yaw": snappedf(actor.rotation.y, 0.001),
		"stats": fire.stats(), "target": _v3(enemy_pos)}
	if cur.has("wall"):
		res["wall_z"] = cur["wall_z"]
		(cur["wall"] as Node).queue_free()
	(_ck["results"] as Array).append(res)
	_ck["cur"] = {}

func _ck_log() -> void:
	var on := combat.state == combat.S.SHOT
	if not on or (_ck["cur"] as Dictionary).is_empty() or str((_ck["cur"] as Dictionary)["test"]) != "main":
		return
	var b := func(n: String) -> Vector3: return _skl.global_transform * _skl.get_bone_global_pose(_skl.find_bone(n)).origin
	(_ck["frames"] as Array).append({"key": combat.shot_key, "st": snappedf(combat.shot_t, 0.0001), "hs": combat.hitstop_left, "pos": _v3(actor.global_position),
		"yaw": snappedf(actor.rotation.y, 0.001), "hips": _v3(b.call("mixamorig_Hips")), "lf": _v3(b.call("mixamorig_LeftFoot")), "rf": _v3(b.call("mixamorig_RightFoot")),
		"lt": _v3(b.call("mixamorig_LeftToeBase")), "rt": _v3(b.call("mixamorig_RightToeBase")), "lh": _v3(b.call("mixamorig_LeftHand")), "rh": _v3(b.call("mixamorig_RightHand")),
		"tip": _v3(sword.global_transform * Vector3(0, 1.085, 0)), "stroke": fire.stats()["stroke_pts"], "sync": snappedf(float(fire.stats()["stroke_sync_err"]), 0.001),
		"ghosts": _ghosts.size(), "fps": Engine.get_frames_per_second()})

func _ck_finish() -> void:
	if int(_ck["phase"]) == 9:
		return
	_ck["phase"] = 9
	DirAccess.make_dir_recursive_absolute(_r15_dir)
	for s: Dictionary in _ck["shots"]:
		var p := _r15_dir.path_join("%s_%d.png" % [s["key"], int(s["i"])])
		(s["img"] as Image).save_png(p)
		s.erase("img")
		s["path"] = p
	var f := FileAccess.open(_r15_dir.path_join("r15_check.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"results": _ck["results"], "missing": missing, "dmg": dmg_log, "audio": saudio.ev_log, "shots": _ck["shots"], "frames": _ck["frames"]}))
	f.close()
	get_tree().quit()
