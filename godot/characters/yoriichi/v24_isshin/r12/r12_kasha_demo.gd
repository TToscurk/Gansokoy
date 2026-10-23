extends "res://characters/yoriichi/v24_isshin/fire_research_v2/sun_fire_hekira_demo.gd"
## 緣一 R12 試玩：日之呼吸・火車——蓄勢、刀身點燃、起跳空中縮身前空翻、向下斬擊、落地（候選 ART_REVIEW）。
## 2026-10-22：R12 的空翻招由原本暫定的碧羅天改歸「火車」，動作與時序不變。火車是獨立技能 ID sun_kasha；R11 的碧羅天 sun_hekiraten
## 原樣保留（Z／X 仍可選到，R11 動作與特效，不改）。
## 動作：anims/isshin_sun_kasha_r12.res（notes/r12/build_kasha_r12.py：梟 c5060 a000_003003 改造，雙手持刀、降低跳躍、縮短位移、加蓄勢）。
## 技能資料：r12/kasha_r12.json（shot／audio／Blender 火焰設定）；輸入、傷害、冷卻、派生沿用 R11 碧羅天的值另建一份（碧羅天本身不動）。
## 火焰：預設＝Blender 火焰 KS12（R11 原版同一套建造腳本／材質／光照，r9c/sun_vfx_mesh.gd 播放）；B＝統一火焰系統 sun_fire.gd
##       profile sun_kasha（刀身火＋依技能時間沿翻轉展開的風格化火環）。命中爆燃照實際命中。鏡頭完全由玩家控制，技能不接管。
## 操作：L／右鍵 火車；Space 閃避（蓄勢段可取消）；R 回到木樁前；B 切火焰版本；Z／X 換型；Q／E、←／→ 轉鏡頭；O 繞轉。
## 功能檢查：-- --kasha-check=OUT_DIR（命中、位移、落地、牆、蓄勢取消；4 張圖後結束）
const R12_DIR := "res://characters/yoriichi/v24_isshin/r12/"
const ThirdCam = preload("res://characters/yoriichi/v24_isshin/r12/third_person_cam.gd")
const KEY := "sun_kasha"
const DUMMY_Z := 3.2                       # 設計距離：起跳 0.30＋空中 1.68 m 後，木樁在根前方 1.2 m（lunge_min_dist）
var r12: Dictionary = {}
var charge_cancel := 0.44
var _r12_dir := ""
var _ck := {"phase": 0, "t": 0.0, "t0": 0.0, "frames": [], "shots": [], "runs": [], "dodge_sent": false, "wall": null}
var _skl: Skeleton3D

func _pre_setup() -> void:
	super._pre_setup()
	r12 = JSON.parse_string(FileAccess.get_file_as_string(R12_DIR + "kasha_r12.json"))
	var s: Dictionary = (skills["sun_hekiraten"] as Dictionary).duplicate(true)   # 輸入／傷害／冷卻／派生沿用；碧羅天本身不動
	for k in ["vfx_variants", "vfx_map", "vfx", "_anim"]:
		s.erase(k)
	s["name"] = str(r12.get("name", "日之呼吸・火車"))
	s["shot"] = r12["shot"]
	s["audio"] = r12["audio"]
	s["_anim"] = r12["_doc"]
	for k in ["vfx_variants", "vfx_map", "vfx"]:
		if r12.has(k):
			s[k] = r12[k]
	skills[KEY] = s
	if not skill_order.has(KEY):
		skill_order.append(KEY)
	var atk_cancel := float((r12["shot"] as Dictionary).get("attack_cancel", 1.85))
	for k2 in skills:                                   # 其他型「接在火車之後」的時間＝火車自己的攻擊取消時間
		var lf: Dictionary = (skills[k2] as Dictionary).get("link_from", {})
		if k2 != KEY and lf.has("sun_hekiraten"):
			lf[KEY] = atk_cancel
	charge_cancel = float(r12.get("charge_cancel", 0.44))
	combat.extra_shots[KEY] = _clean(s["shot"])
	cur_skill = KEY

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kasha-check="):
			_r12_dir = a.substr(14)
		elif a.begins_with("--r12-check="):
			_r12_dir = a.substr(12)
	super._ready()
	cur_skill = KEY
	var forced := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--vfx=") or a == "--vfx12=unified":
			forced = true
	if not forced:
		vfx_variant = _old_variant            # 預設＝Blender 火焰 KS12（R11 原版同一套）；B 切到統一系統的風格化火環
		fire.clear()
	_skl = actor.get_node("BodyVisual/緣一_fbx/Armature/Skeleton3D") as Skeleton3D
	if _r12_dir != "":
		Engine.max_fps = 60
		hud_on = false
	_reset_to_dummy()

func _reset_to_dummy() -> void:
	actor.position = Vector3.ZERO
	actor.rotation = Vector3.ZERO
	enemy_pos = Vector3(0, 0, DUMMY_Z)
	orbit_speed = 0.0
	_last_pos = Vector3.INF                 # 位移碰撞代理：瞬移後重新起算（不要把瞬移當成一次掃掠）

## 火車收勢低身，取消接普通劍術時交叉淡入加長到 0.16 s（同 R11 碧羅天的處理）
func _router(ctx: String) -> String:
	var from := combat.shot_key if combat.state == combat.S.SHOT else ""
	var k := super._router(ctx)
	if ctx == "cancel" and from == KEY and k != "":
		combat.fire_opts["fade_in"] = 0.16
	return k

## 蓄勢段（起跳前）按閃避＝取消技能、直接閃避；起跳後要到落地吸收結束（dodge_cancel）才能取消
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

## 鏡頭：第三人稱自由鏡頭（身後偏右肩、Q／E 轉動）；技能不接管。--cam=side／front／third 時照上游舊行為
func _update_cam(snap: bool) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam="):
			super._update_cam(snap)
			return
	ThirdCam.update(self, snap)

func _hud_text() -> String:
	var fx := "Blender 火焰 KS12" if vfx_variant != UNIFIED else "統一系統風格化火環"
	var base := super._hud_text()
	var nl := base.find("\n")                           # 第一行是碧羅天特效試玩的標題，換成火車的
	if nl >= 0:
		base = base.substr(nl + 1)
	return ("【R12 日之呼吸・火車】火焰：%s（B 切換）   蓄勢 0–0.46 s（Space 可取消）→ 起跳空翻 → 下斬 → 落地   R＝回木樁前（%.1f m）\n" % [fx, DUMMY_Z]
		+ base.replace("緣一 R11 碧羅天試玩", "緣一 R12 火車試玩"))

# ------------------------------------------------------------------ 功能檢查（一次性）
func _vfx_frame() -> void:
	super._vfx_frame()
	if _r12_dir != "" and int(_ck["phase"]) in [1, 2, 3]:
		_r12_log()

func _bone_w(n: String) -> Vector3:
	return _skl.global_transform * _skl.get_bone_global_pose(_skl.find_bone(n)).origin

func _r12_log() -> void:
	var on := combat.state == combat.S.SHOT
	var tip := sword.global_transform * Vector3(0, 1.085, 0)
	var st: Dictionary = fire.stats()
	(_ck["frames"] as Array).append({"ph": _ck["phase"], "key": combat.shot_key if on else "", "st": snappedf(combat.shot_t, 0.0001), "hs": combat.hitstop_left,
		"pos": _v3(actor.global_position), "yaw": snappedf(actor.rotation.y, 0.001), "hips": _v3(_bone_w("mixamorig_Hips")), "head": _v3(_bone_w("mixamorig_Head")),
		"lf": _v3(_bone_w("mixamorig_LeftFoot")), "rf": _v3(_bone_w("mixamorig_RightFoot")), "tip": _v3(tip),
		"lh": _v3(_bone_w("mixamorig_LeftHand")), "rh": _v3(_bone_w("mixamorig_RightHand")),
		"ring": st["stroke_pts"], "mesh_t": snappedf(float(mvfx.skill_t), 0.001), "fade": snappedf(float(fire._fade), 0.01), "hp": dummy_hp, "fps": Engine.get_frames_per_second()})
	if int(_ck["phase"]) == 1 and on and combat.shot_key == KEY:
		var want: Array = _ck.get("want", [])
		for i in want.size():
			var w := float(want[i])
			if w > 50.0:
				continue
			var take := (combat.hitstop_left > 0) if w < 0.0 else combat.shot_t >= w
			if take:
				want[i] = 99.0
				var tag: String = ["charge", "flip", "hit", "ring"][i]
				await RenderingServer.frame_post_draw
				(_ck["shots"] as Array).append({"tag": tag, "st": snappedf(combat.shot_t, 0.001), "img": get_viewport().get_texture().get_image()})

func _process(delta: float) -> void:
	super._process(delta)
	if _r12_dir == "":
		return
	_ck["t"] = float(_ck["t"]) + delta
	var t := float(_ck["t"])
	var ph := int(_ck["phase"])
	var idle: bool = combat.state != combat.S.SHOT and combat.cooldown <= 0.0 and now >= float(skill_cd.get(KEY, -1.0))
	var since := t - float(_ck["t0"])
	if ph == 0 and t > 1.5 and idle:
		_r12_cast(1)
		_ck["want"] = [0.40, 0.72, -1.0, 1.36]
		cam_yaw_extra = deg_to_rad(65.0)        # 檢查圖用斜側面（玩家鏡頭本身不受技能控制）
	elif ph == 1 and since > 1.0 and idle and weapon == "drawn":
		cam_yaw_extra = 0.0
		_add_wall(Vector3(0.0, 0.0, 1.3 + 0.125), 0.0, Vector3(6.0, 2.2, 0.25))
		_ck["wall"] = get_child(get_child_count() - 1)
		_r12_cast(2)
	elif ph == 2 and since > 1.0 and idle:
		(_ck["wall"] as Node).queue_free()
		_r12_cast(3)
		_ck["dodge_sent"] = false
	elif ph == 3 and not bool(_ck["dodge_sent"]) and combat.state == combat.S.SHOT and combat.shot_key == KEY and combat.shot_t >= 0.30:
		buf["dodge"] = now
		_ck["dodge_sent"] = true
	elif ph == 3 and since > 2.5 and idle:
		_r12_finish()
	elif t > 40.0:
		_r12_finish()

func _r12_cast(ph: int) -> void:
	_reset_to_dummy()
	_ck["phase"] = ph
	_ck["t0"] = _ck["t"]
	(_ck["runs"] as Array).append({"phase": ph, "now": snappedf(now, 0.001), "weapon": weapon, "skill": cur_skill})
	buf["skill"] = now

func _r12_finish() -> void:
	if int(_ck["phase"]) == 9:
		return
	_ck["phase"] = 9
	DirAccess.make_dir_recursive_absolute(_r12_dir)
	for s: Dictionary in _ck["shots"]:
		var p := _r12_dir.path_join("kasha_%s.png" % s["tag"])
		(s["img"] as Image).save_png(p)
		s.erase("img")
		s["path"] = p
	var f := FileAccess.open(_r12_dir.path_join("r12_check.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"runs": _ck["runs"], "dmg": dmg_log, "cancels": combat.cancel_log, "fit": combat.fit_log, "audio": saudio.ev_log,
		"shots": _ck["shots"], "stats": fire.stats(), "mesh": mvfx.stats(), "frames": _ck["frames"]}))
	f.close()
	get_tree().quit()
