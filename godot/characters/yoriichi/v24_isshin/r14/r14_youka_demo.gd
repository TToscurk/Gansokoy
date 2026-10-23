extends "res://characters/yoriichi/v24_isshin/fire_research_v2/sun_fire_hekira_demo.gd"
## 緣一 R14 試玩：日之呼吸・陽華突——後跳收刀蓄勢、蹲身、向前上方突刺並跳起、命中爆燃、落地收勢（候選 ART_REVIEW，第 2 版：跳躍加強）。
## 動作：anims/isshin_sun_youka_r14.res（notes/r14/build_youka_r14.py：#221 葦名弦一郎 c7100 a000_003062 雙手突刺改造；腿、髖、軀幹、腳步沿用，
##       雙臂兩骨 IK 讓刀身全程對準突刺方向（仰角 43°），刀尖沿一直線由 1.27 m 刺到 2.18 m）。
## 技能：sun_youkatotsu（r14/youka_r14.json）＝一個判定窗，最多命中一次；冷卻／派生沿用 R11 碧羅天的值另建一份（碧羅天本身不動）。
## 判定：沿用共用刀身判定 blade_hit_judge.gd（立體刀身取樣），只換目標形狀：T 鍵切換 地面木樁／空中目標（球心 2.3 m）／遠處空中目標（只在火焰延伸範圍）。
## 火焰：統一火焰系統 sun_fire.gd profile sun_youkatotsu（刀身火＋沿突刺線的窄火槍＋命中爆燃）。鏡頭完全由玩家控制，技能不接管。
## 操作：L／右鍵 陽華突；Space 閃避（突刺前可取消）；T 換目標；R 回到目標前；Z／X 換型；Q／E、←／→ 轉鏡頭；O 繞轉；V 特效開關。
## 功能檢查：-- --youka-check=OUT_DIR（地面木樁、空中目標、遠處空中目標、牆、蓄勢取消；4 張圖後結束）
const R14_DIR := "res://characters/yoriichi/v24_isshin/r14/"
const ThirdCam = preload("res://characters/yoriichi/v24_isshin/r12/third_person_cam.gd")
const KEY := "sun_youkatotsu"
const AIR_R := 0.3
## 目標（相對起手位置）：地面木樁 1.3 m（刀由下往上刺進頭頸）；空中目標球心 (0, 2.6, 2.3)（跳起上升時刺中）；遠處空中目標＝球心 (0, 2.95, 2.75)，
## 在火焰槍尖方向上、刀尖最高點外 0.12 m（火焰會到，刀碰不到）。依 notes/r14/reach_r14.py 的離線量測擺放。
const TARGETS := [
	{"name": "地面木樁 1.3 m", "air": false, "pos": Vector3(0.0, 0.0, 1.3)},
	{"name": "空中目標（球心高 2.6 m、前方 2.3 m）", "air": true, "pos": Vector3(0.0, 2.60, 2.30)},
	{"name": "遠處空中目標（只在火焰延伸範圍）", "air": true, "pos": Vector3(0.0, 2.95, 2.75)},
]
var r14: Dictionary = {}
var charge_cancel := 0.55
var target_mode := 0
var _air_y := 0.0
var _air_mi: MeshInstance3D
var _r14_dir := ""
var _ck := {"phase": 0, "t": 0.0, "t0": 0.0, "frames": [], "shots": [], "runs": [], "dodge_sent": false, "wall": null, "hs_edges": 0, "was_hs": false, "want": []}
var _skl: Skeleton3D

func _pre_setup() -> void:
	super._pre_setup()
	r14 = JSON.parse_string(FileAccess.get_file_as_string(R14_DIR + "youka_r14.json"))
	var s: Dictionary = (skills["sun_hekiraten"] as Dictionary).duplicate(true)   # 輸入／派生沿用；碧羅天本身不動
	for k in ["vfx_variants", "vfx_map", "vfx", "_anim"]:
		s.erase(k)
	s["name"] = str(r14.get("name", "日之呼吸・陽華突"))
	s["shot"] = r14["shot"]
	s["audio"] = r14["audio"]
	s["damage"] = int(r14.get("damage", 3))
	s["cooldown"] = float(r14.get("cooldown", 1.2))
	s["_anim"] = r14["_doc"]
	skills[KEY] = s
	if not skill_order.has(KEY):
		skill_order.append(KEY)
	var atk_cancel := float((r14["shot"] as Dictionary).get("attack_cancel", 1.1))
	for k2 in skills:                                   # 其他型「接在陽華突之後」的時間＝陽華突自己的攻擊取消時間
		var lf: Dictionary = (skills[k2] as Dictionary).get("link_from", {})
		if k2 != KEY and lf.has("sun_hekiraten"):
			lf[KEY] = atk_cancel
	charge_cancel = float(r14.get("charge_cancel", 0.55))
	combat.extra_shots[KEY] = _clean(s["shot"])
	cur_skill = KEY

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--youka-check="):
			_r14_dir = a.substr(14)
	super._ready()
	cur_skill = KEY
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
	if _r14_dir != "":
		Engine.max_fps = 60
		hud_on = false
	_reset_to_dummy()

func _reset_to_dummy() -> void:
	actor.position = Vector3.ZERO
	actor.rotation = Vector3.ZERO
	var tg: Dictionary = TARGETS[target_mode]
	var p: Vector3 = tg["pos"]
	enemy_pos = Vector3(p.x, 0.0, p.z)
	_air_y = p.y
	var air: bool = tg["air"]
	if _air_mi:
		_air_mi.visible = air
		_air_mi.position = Vector3(0, p.y, 0)
	for kid in enemy_kids:
		(kid[0] as Node3D).visible = not air
	judge.radius_fn = _air_r if air else BladeJudge.dummy_r
	orbit_speed = 0.0
	_last_pos = Vector3.INF                 # 位移碰撞代理：瞬移後重新起算（不要把瞬移當成一次掃掠）

## 空中目標：球（共用刀身判定的 radius_fn 換成球的截面半徑；目標底部當成判定的基準高度）
func _air_r(y: float) -> float:
	return sqrt(maxf(0.0, AIR_R * AIR_R - pow(y - AIR_R, 2.0)))

func _shared_hit_test() -> Dictionary:
	if not bool(TARGETS[target_mode]["air"]):
		return super._shared_hit_test()
	if sword == null:
		return {}
	var cfg: Dictionary = combat._cfg(combat.shot_key)
	return judge.test(sword.global_transform, Vector3(enemy_pos.x, _air_y - AIR_R, enemy_pos.z), combat.shot_t, get_process_delta_time(),
		cfg.get("strikes", []), tip_v, tip_speed)

## 突刺出手前（後跳＋蹲身蓄勢）按閃避＝取消技能、直接閃避；出手後要到伸直停留結束（dodge_cancel）才能取消
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

## 陽華突只有統一火焰系統一個版本：B 不切換；T 換目標
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo:
		match (e as InputEventKey).keycode:
			KEY_B:
				return
			KEY_T:
				target_mode = (target_mode + 1) % TARGETS.size()
				_reset_to_dummy()
				return
	super._unhandled_input(e)

func _hud_text() -> String:
	var base := super._hud_text()
	var nl := base.find("\n")                           # 第一行是碧羅天特效試玩的標題，換成陽華突的
	if nl >= 0:
		base = base.substr(nl + 1)
	return ("【R14 日之呼吸・陽華突】後跳收刀＋蹲身 0–0.58 s（Space 可取消）→ 突刺起跳 0.58–0.71 s → 滯空 → 1.15 s 落地 → 收勢   目標：%s（T 切換）   R＝回到目標前\n" % str(TARGETS[target_mode]["name"])
		+ base.replace("緣一 R11 碧羅天試玩", "緣一 R14 陽華突試玩"))

# ------------------------------------------------------------------ 功能檢查（一次性）
func _vfx_frame() -> void:
	super._vfx_frame()
	if _r14_dir != "" and int(_ck["phase"]) in [1, 2, 3, 4, 5]:
		_r14_log()

func _bone_w(n: String) -> Vector3:
	return _skl.global_transform * _skl.get_bone_global_pose(_skl.find_bone(n)).origin

func _r14_log() -> void:
	var on := combat.state == combat.S.SHOT
	var tip := sword.global_transform * Vector3(0, 1.085, 0)
	var org := sword.global_transform * Vector3.ZERO
	var st: Dictionary = fire.stats()
	var hs: bool = combat.hitstop_left > 0
	if hs and not bool(_ck["was_hs"]):
		_ck["hs_edges"] = int(_ck["hs_edges"]) + 1
	(_ck["frames"] as Array).append({"ph": _ck["phase"], "key": combat.shot_key if on else "", "st": snappedf(combat.shot_t, 0.0001), "hs": combat.hitstop_left,
		"pos": _v3(actor.global_position), "yaw": snappedf(actor.rotation.y, 0.001), "hips": _v3(_bone_w("mixamorig_Hips")), "head": _v3(_bone_w("mixamorig_Head")),
		"lf": _v3(_bone_w("mixamorig_LeftFoot")), "rf": _v3(_bone_w("mixamorig_RightFoot")), "lt": _v3(_bone_w("mixamorig_LeftToeBase")), "rt": _v3(_bone_w("mixamorig_RightToeBase")),
		"tip": _v3(tip), "org": _v3(org), "lh": _v3(_bone_w("mixamorig_LeftHand")), "rh": _v3(_bone_w("mixamorig_RightHand")),
		"stroke": st["stroke_pts"], "sync": snappedf(float(st["stroke_sync_err"]), 0.001), "fhits": st["hits"], "fign": st["hits_ignored"],
		"fade": snappedf(float(fire._fade), 0.01), "hp": dummy_hp, "enemy": _v3(enemy_pos), "air_y": _air_y, "mode": target_mode, "fps": Engine.get_frames_per_second()})
	if on and combat.shot_key == KEY:
		var want: Array = _ck["want"]
		for i in want.size():
			var w := float(want[i][1])
			if w > 50.0:
				continue
			var take := (hs and not bool(_ck["was_hs"]) and int(_ck["hs_edges"]) == int(-w)) if w < 0.0 else combat.shot_t >= w
			if take:
				var tag := str(want[i][0])
				want[i][1] = 99.0
				_ck["was_hs"] = hs
				await RenderingServer.frame_post_draw
				(_ck["shots"] as Array).append({"tag": tag, "st": snappedf(combat.shot_t, 0.001), "img": get_viewport().get_texture().get_image()})
	_ck["was_hs"] = hs

func _process(delta: float) -> void:
	super._process(delta)
	if _r14_dir == "":
		return
	_ck["t"] = float(_ck["t"]) + delta
	var t := float(_ck["t"])
	var ph := int(_ck["phase"])
	var idle: bool = combat.state != combat.S.SHOT and combat.cooldown <= 0.0 and now >= float(skill_cd.get(KEY, -1.0))
	var since := t - float(_ck["t0"])
	if ph == 0 and t > 1.5 and idle:
		_r14_cast(1, 0, [["cocked", 0.50], ["ground_hit", -1.0]])
		cam_yaw_extra = deg_to_rad(65.0)        # 檢查圖：地面木樁用斜側面（玩家鏡頭本身不受技能控制）
	elif ph == 1 and since > 1.0 and idle and weapon == "drawn":
		cam_yaw_extra = 0.0                     # 空中目標：一般背後視角
		_r14_cast(2, 1, [["air_hit", -1.0], ["landing", 1.16]])
	elif ph == 2 and since > 1.0 and idle:
		_r14_cast(3, 2, [])
	elif ph == 3 and since > 1.0 and idle:
		_r14_cast(4, 0, [])
		enemy_pos = Vector3(0, 0, 2.5)          # 牆：木樁放遠，讓前衝只被牆擋
		_add_wall(Vector3(0.0, 0.0, 0.6 + 0.125), 0.0, Vector3(6.0, 2.2, 0.25))
		_ck["wall"] = get_child(get_child_count() - 1)
	elif ph == 4 and since > 1.0 and idle:
		(_ck["wall"] as Node).queue_free()
		_r14_cast(5, 1, [])
		_ck["dodge_sent"] = false
	elif ph == 5 and not bool(_ck["dodge_sent"]) and combat.state == combat.S.SHOT and combat.shot_key == KEY and combat.shot_t >= 0.30:
		buf["dodge"] = now
		_ck["dodge_sent"] = true
	elif ph == 5 and since > 2.5 and idle:
		_r14_finish()
	elif t > 50.0:
		_r14_finish()

func _r14_cast(ph: int, mode: int, want: Array) -> void:
	target_mode = mode
	_reset_to_dummy()
	_ck["phase"] = ph
	_ck["t0"] = _ck["t"]
	_ck["hs_edges"] = 0
	_ck["want"] = want
	(_ck["runs"] as Array).append({"phase": ph, "now": snappedf(now, 0.001), "weapon": weapon, "skill": cur_skill, "mode": mode, "target": _v3(TARGETS[mode]["pos"]), "hp0": dummy_hp})
	buf["skill"] = now

func _r14_finish() -> void:
	if int(_ck["phase"]) == 9:
		return
	_ck["phase"] = 9
	DirAccess.make_dir_recursive_absolute(_r14_dir)
	for s: Dictionary in _ck["shots"]:
		var p := _r14_dir.path_join("youka_%s.png" % s["tag"])
		(s["img"] as Image).save_png(p)
		s.erase("img")
		s["path"] = p
	var f := FileAccess.open(_r14_dir.path_join("r14_check.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"runs": _ck["runs"], "dmg": dmg_log, "cancels": combat.cancel_log, "fit": combat.fit_log, "audio": saudio.ev_log,
		"shots": _ck["shots"], "stats": fire.stats(), "frames": _ck["frames"]}))
	f.close()
	get_tree().quit()
