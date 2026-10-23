extends "res://characters/yoriichi/v24_isshin/fire_research_v2/sun_fire_hekira_demo.gd"
## 緣一 R13 試玩：日之呼吸・炎舞——蓄勢、第一刀袈裟、第二刀水平橫斬、每刀命中爆燃、收勢（ART_APPROVED 2026-10-23，使用者試玩通過；凍結）。
## 動作：anims/isshin_sun_enbu_double_r13.res（notes/r13/build_enbu_r13.py：梟 c5060 a000_003000 #80 → a000_003001 #81 原生連段、原速；
##       接點＝003000 的 0.90 s 與 003001 第 0 格同一姿勢，不加過渡、沒有 Blender 改造；只改：腳貼地／站定的腳釘地、整段降 2.1 cm、
##       收勢＝左腳不動、右腳上步淡回待機）。
## 技能：sun_enbu_double（r13/enbu_r13.json）＝一招兩個判定窗，每窗最多命中一次；輸入／冷卻／派生沿用 R11 碧羅天的值另建一份（碧羅天本身不動）。
## 火焰：統一火焰系統 sun_fire.gd profile sun_enbu_double（刀身火＋每刀一道沿該刀實際刀路點燃的火帶＋每次命中爆燃）。鏡頭完全由玩家控制，技能不接管。
## 操作：L／右鍵 炎舞；Space 閃避（蓄勢段可取消）；R 回到木樁前；Z／X 換型；Q／E、←／→ 轉鏡頭；O 繞轉；V 特效開關。
## 功能檢查：-- --enbu-check=OUT_DIR（標準距離、近距離、牆、蓄勢取消；4 張圖後結束）
const R13_DIR := "res://characters/yoriichi/v24_isshin/r13/"
const ThirdCam = preload("res://characters/yoriichi/v24_isshin/r12/third_person_cam.gd")
const KEY := "sun_enbu_double"
const DUMMY_Z := 2.75                       # 設計距離：第一刀時根前進約 1.48 m，木樁在根前方約 1.27 m（刀身前段切入）；第二刀由 lunges 自動收距
const CLOSE_Z := 2.0                        # 功能檢查：近距離起手
var r13: Dictionary = {}
var charge_cancel := 0.5
var _r13_dir := ""
var _ck := {"phase": 0, "t": 0.0, "t0": 0.0, "frames": [], "shots": [], "runs": [], "dodge_sent": false, "wall": null, "hs_edges": 0, "was_hs": false}
var _skl: Skeleton3D

func _pre_setup() -> void:
	super._pre_setup()
	r13 = JSON.parse_string(FileAccess.get_file_as_string(R13_DIR + "enbu_r13.json"))
	var s: Dictionary = (skills["sun_hekiraten"] as Dictionary).duplicate(true)   # 輸入／冷卻／派生沿用；碧羅天本身不動
	for k in ["vfx_variants", "vfx_map", "vfx", "_anim"]:
		s.erase(k)
	s["name"] = str(r13.get("name", "日之呼吸・炎舞"))
	s["shot"] = r13["shot"]
	s["audio"] = r13["audio"]
	s["damage"] = int(r13.get("damage", 2))
	s["cooldown"] = float(r13.get("cooldown", 1.2))
	s["_anim"] = r13["_doc"]
	skills[KEY] = s
	if not skill_order.has(KEY):
		skill_order.append(KEY)
	var atk_cancel := float((r13["shot"] as Dictionary).get("attack_cancel", 1.95))
	for k2 in skills:                                   # 其他型「接在炎舞之後」的時間＝炎舞自己的攻擊取消時間
		var lf: Dictionary = (skills[k2] as Dictionary).get("link_from", {})
		if k2 != KEY and lf.has("sun_hekiraten"):
			lf[KEY] = atk_cancel
	charge_cancel = float(r13.get("charge_cancel", 0.5))
	combat.extra_shots[KEY] = _clean(s["shot"])
	cur_skill = KEY

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--enbu-check="):
			_r13_dir = a.substr(13)
	super._ready()
	cur_skill = KEY
	_skl = actor.get_node("BodyVisual/緣一_fbx/Armature/Skeleton3D") as Skeleton3D
	if _r13_dir != "":
		Engine.max_fps = 60
		hud_on = false
	_reset_to_dummy()

func _reset_to_dummy() -> void:
	actor.position = Vector3.ZERO
	actor.rotation = Vector3.ZERO
	enemy_pos = Vector3(0, 0, DUMMY_Z)
	orbit_speed = 0.0
	_last_pos = Vector3.INF                 # 位移碰撞代理：瞬移後重新起算（不要把瞬移當成一次掃掠）

## 蓄勢段（第一刀出手前）按閃避＝取消技能、直接閃避；出手後要到第二刀收刀（dodge_cancel）才能取消
func _filter_input(delta: float, dodge: bool, attack: bool) -> Array:
	var io: Array = super._filter_input(delta, dodge, attack)
	if io[0] and combat.state == combat.S.SHOT and combat.shot_key == KEY and combat.shot_t < charge_cancel and combat.hitstop_left == 0:
		var mx := _move_input().x
		combat._end_shot(true)
		combat.cancel_log.append({"key": KEY, "kind": "charge_dodge", "shot_t": combat.shot_t})
		buf["dodge"] = -9.0
		combat._fire("dodge_l" if mx < 0.0 else "dodge_r", _aim_err())
		return [false, false]
	return io

## 鏡頭：第三人稱自由鏡頭（R12 同一支 third_person_cam.gd，身後偏右肩、Q／E 轉動）；技能不接管。--cam=side／front／third 時照上游舊行為
func _update_cam(snap: bool) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam="):
			super._update_cam(snap)
			return
	ThirdCam.update(self, snap)

## 炎舞只有統一火焰系統一個版本：B 不切換（其他型照 R11 原本的特效）
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed and (e as InputEventKey).keycode == KEY_B:
		return
	super._unhandled_input(e)

func _hud_text() -> String:
	var base := super._hud_text()
	var nl := base.find("\n")                           # 第一行是碧羅天特效試玩的標題，換成炎舞的
	if nl >= 0:
		base = base.substr(nl + 1)
	return ("【R13 日之呼吸・炎舞】蓄勢 0–0.55 s（Space 可取消）→ 第一刀袈裟 0.6 s → 第二刀水平橫斬 1.3 s → 收勢   R＝回木樁前（%.1f m）\n" % DUMMY_Z
		+ base.replace("緣一 R11 碧羅天試玩", "緣一 R13 炎舞試玩"))

# ------------------------------------------------------------------ 功能檢查（一次性）
func _vfx_frame() -> void:
	super._vfx_frame()
	if _r13_dir != "" and int(_ck["phase"]) in [1, 2, 3, 4]:
		_r13_log()

func _bone_w(n: String) -> Vector3:
	return _skl.global_transform * _skl.get_bone_global_pose(_skl.find_bone(n)).origin

func _r13_log() -> void:
	var on := combat.state == combat.S.SHOT
	var tip := sword.global_transform * Vector3(0, 1.085, 0)
	var st: Dictionary = fire.stats()
	var hs: bool = combat.hitstop_left > 0
	if hs and not bool(_ck["was_hs"]):
		_ck["hs_edges"] = int(_ck["hs_edges"]) + 1
	(_ck["frames"] as Array).append({"ph": _ck["phase"], "key": combat.shot_key if on else "", "st": snappedf(combat.shot_t, 0.0001), "hs": combat.hitstop_left,
		"pos": _v3(actor.global_position), "yaw": snappedf(actor.rotation.y, 0.001), "hips": _v3(_bone_w("mixamorig_Hips")), "head": _v3(_bone_w("mixamorig_Head")),
		"lf": _v3(_bone_w("mixamorig_LeftFoot")), "rf": _v3(_bone_w("mixamorig_RightFoot")), "lt": _v3(_bone_w("mixamorig_LeftToeBase")), "rt": _v3(_bone_w("mixamorig_RightToeBase")),
		"tip": _v3(tip), "lh": _v3(_bone_w("mixamorig_LeftHand")), "rh": _v3(_bone_w("mixamorig_RightHand")),
		"stroke": st["stroke_pts"], "sync": snappedf(float(st["stroke_sync_err"]), 0.001), "fhits": st["hits"], "fign": st["hits_ignored"],
		"fade": snappedf(float(fire._fade), 0.01), "hp": dummy_hp, "enemy": _v3(enemy_pos), "fps": Engine.get_frames_per_second()})
	if int(_ck["phase"]) == 1 and on and combat.shot_key == KEY:
		var want: Array = _ck.get("want", [])
		for i in want.size():
			var w := float(want[i])
			if w > 50.0:
				continue
			var take := (hs and not bool(_ck["was_hs"]) and int(_ck["hs_edges"]) == int(-w)) if w < 0.0 else combat.shot_t >= w
			if take:
				want[i] = 99.0
				var tag: String = ["windup", "cut1", "cut2", "burn"][i]
				_ck["was_hs"] = hs
				await RenderingServer.frame_post_draw
				(_ck["shots"] as Array).append({"tag": tag, "st": snappedf(combat.shot_t, 0.001), "img": get_viewport().get_texture().get_image()})
	_ck["was_hs"] = hs

func _process(delta: float) -> void:
	super._process(delta)
	if _r13_dir == "":
		return
	_ck["t"] = float(_ck["t"]) + delta
	var t := float(_ck["t"])
	var ph := int(_ck["phase"])
	var idle: bool = combat.state != combat.S.SHOT and combat.cooldown <= 0.0 and now >= float(skill_cd.get(KEY, -1.0))
	var since := t - float(_ck["t0"])
	if ph == 0 and t > 1.5 and idle:
		_r13_cast(1, DUMMY_Z)
		_ck["want"] = [0.45, -1.0, -2.0, 1.52]
		cam_yaw_extra = deg_to_rad(65.0)        # 檢查圖用斜側面（玩家鏡頭本身不受技能控制）
	elif ph == 1 and since > 1.0 and idle and weapon == "drawn":
		cam_yaw_extra = 0.0
		_r13_cast(2, CLOSE_Z)
	elif ph == 2 and since > 1.0 and idle:
		_add_wall(Vector3(0.0, 0.0, 1.3 + 0.125), 0.0, Vector3(6.0, 2.2, 0.25))
		_ck["wall"] = get_child(get_child_count() - 1)
		_r13_cast(3, DUMMY_Z)
	elif ph == 3 and since > 1.0 and idle:
		(_ck["wall"] as Node).queue_free()
		_r13_cast(4, DUMMY_Z)
		_ck["dodge_sent"] = false
	elif ph == 4 and not bool(_ck["dodge_sent"]) and combat.state == combat.S.SHOT and combat.shot_key == KEY and combat.shot_t >= 0.30:
		buf["dodge"] = now
		_ck["dodge_sent"] = true
	elif ph == 4 and since > 2.5 and idle:
		_r13_finish()
	elif t > 45.0:
		_r13_finish()

func _r13_cast(ph: int, dz: float) -> void:
	_reset_to_dummy()
	enemy_pos = Vector3(0, 0, dz)
	_ck["phase"] = ph
	_ck["t0"] = _ck["t"]
	(_ck["runs"] as Array).append({"phase": ph, "now": snappedf(now, 0.001), "weapon": weapon, "skill": cur_skill, "dummy_z": dz, "hp0": dummy_hp})
	buf["skill"] = now

func _r13_finish() -> void:
	if int(_ck["phase"]) == 9:
		return
	_ck["phase"] = 9
	DirAccess.make_dir_recursive_absolute(_r13_dir)
	for s: Dictionary in _ck["shots"]:
		var p := _r13_dir.path_join("enbu_%s.png" % s["tag"])
		(s["img"] as Image).save_png(p)
		s.erase("img")
		s["path"] = p
	var f := FileAccess.open(_r13_dir.path_join("r13_check.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"runs": _ck["runs"], "dmg": dmg_log, "cancels": combat.cancel_log, "fit": combat.fit_log, "audio": saudio.ev_log,
		"shots": _ck["shots"], "stats": fire.stats(), "frames": _ck["frames"]}))
	f.close()
	get_tree().quit()
