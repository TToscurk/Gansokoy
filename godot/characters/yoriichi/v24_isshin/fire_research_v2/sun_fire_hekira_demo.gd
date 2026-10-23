extends "res://characters/yoriichi/v24_isshin/r11/r11_combat_demo.gd"
## 日之呼吸火焰系統（統一版）— 碧羅天試玩（ART_REVIEW）。
## 動作、判定、Hit Stop、派生全部沿用 R11 碧羅天試玩（不改 R11 檔案）；碧羅天的 VFX 改由同一個 sun_fire.gd 播放，
## 主視覺＝沿刀尖實際路徑逐段點燃的風格化火環（sun_fire_profiles.json 的 sun_hekiraten）。其他型照 R11 原本的特效。
## 操作（其餘同 R11）：L／滑鼠右鍵 日之呼吸（開場選碧羅天）；B 統一版 ↔ R11 原特效；R 回到木樁前；V 特效開關；N 白天／黃昏。
## 功能檢查：-- --fire-check=OUT_DIR（施放一次碧羅天，記錄命中、停格、火環與刀尖同步，存 4 張第三人稱圖後結束）
const SunFire = preload("res://characters/yoriichi/v24_isshin/fire_research_v2/sun_fire.gd")
const UNIFIED := "SUN"
var fire
var _old_variant := "R10"
var _check_dir := ""
var _chk := {"phase": 0, "t": 0.0, "log": [], "shots": [], "casts": [], "want": [], "dup": []}
var _was_hs := false

func _ready() -> void:
	var forced := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--vfx="):
			forced = true
		elif a.begins_with("--fire-check="):
			_check_dir = a.substr(13)
	super._ready()
	fire = SunFire.new()
	fire.name = "SunFire"
	add_child(fire)
	fire.setup(actor, sword, cam)
	fire.enabled = vfx_on
	_old_variant = vfx_variant
	if not forced:
		vfx_variant = UNIFIED
	cur_skill = "sun_hekiraten"
	if _check_dir != "":
		Engine.max_fps = 60
		hud_on = false
	_reset_to_dummy()

func _reset_to_dummy() -> void:
	actor.position = Vector3.ZERO
	actor.rotation = Vector3.ZERO
	enemy_pos = Vector3(0, 0, 1.6)
	orbit_speed = 0.0

func _begin_skill(key: String) -> void:
	if vfx_variant != UNIFIED or not fire.has_skill(key):
		var v := vfx_variant
		if v == UNIFIED:
			vfx_variant = _old_variant            # 統一版還沒有的型：照 R11 原特效
		super._begin_skill(key)
		vfx_variant = v
		return
	skill_key = key
	_skill_variant = UNIFIED
	fire.enabled = vfx_on
	fire.begin(key)
	saudio.begin(skills[key]["audio"])
	if _check_dir != "":
		_chk["casts"].append({"key": key, "now": snappedf(now, 0.001)})

func _vfx_frame() -> void:
	if fire == null or sword == null:
		super._vfx_frame()
		return
	var mine: bool = _skill_variant == UNIFIED and skill_key != ""
	var active: bool = mine and combat.state == combat.S.SHOT and combat.shot_key == skill_key
	if mine and not active:
		fire.end()
	super._vfx_frame()
	var dt := get_process_delta_time()
	var t: float = combat.shot_t if active else fire.skill_t + dt
	fire.frame(sword.global_transform, t, dt, combat.hitstop_left > 0, tip_speed)
	if _check_dir != "":
		_check_frame(active)

func _on_hit(info: Dictionary) -> void:
	if _skill_variant != UNIFIED:
		super._on_hit(info)
		return
	_skill_variant = "r9"                       # 基底照常扣血／停格，舊特效模組沒在出招，命中特效直接略過
	super._on_hit(info)
	_skill_variant = UNIFIED
	var key := str(info.get("key", ""))
	if skills.has(key) and vfx_on:
		var p: Vector3 = info.get("entry", info["pos"])
		var nrm := p - enemy_pos
		nrm.y = 0.0
		fire.hit(p, info.get("dir", Vector3.DOWN), nrm, int(info.get("strike", 0)))
		if _check_dir != "":
			fire.hit(p, info.get("dir", Vector3.DOWN), nrm, int(info.get("strike", 0)))
			_chk["dup"].append(fire.stats()["hits_ignored"])
	if _check_dir != "":
		_chk["log"].append({"ev": "hit", "key": key, "shot_t": snappedf(combat.shot_t, 0.001), "hp": dummy_hp})

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo:
		var ke := e as InputEventKey
		match ke.keycode:
			KEY_B:
				vfx_variant = _old_variant if vfx_variant == UNIFIED else UNIFIED
				if vfx_variant != UNIFIED:
					fire.clear()
				return
			KEY_C:
				return
			KEY_R:
				_reset_to_dummy()
				return
			KEY_V:
				super._unhandled_input(e)
				fire.enabled = vfx_on
				return
	super._unhandled_input(e)

func _hud_text() -> String:
	var name_ := "統一版（風格化火環）" if vfx_variant == UNIFIED else "R11 原特效"
	return "【碧羅天特效】%s   B＝統一版 ↔ R11 原特效   R＝回木樁前\n" % name_ + super._hud_text()

# ------------------------------------------------------------------ 功能檢查（一次性）
func _process(delta: float) -> void:
	super._process(delta)
	if _check_dir == "":
		return
	_chk["t"] = float(_chk["t"]) + delta
	var ph := int(_chk["phase"])
	var idle: bool = combat.state != combat.S.SHOT and combat.cooldown <= 0.0
	if ph == 0 and float(_chk["t"]) > 1.5 and idle:
		_reset_to_dummy()
		_chk["want"] = [0.63, -1.0, 1.0, 1.32]
		buf["skill"] = now
		_chk["phase"] = 1
	elif ph == 1 and float(_chk["t"]) > 5.0 and idle:
		_finish_check()
	elif float(_chk["t"]) > 15.0:
		_finish_check()

func _check_frame(active: bool) -> void:
	var st: Dictionary = fire.stats()
	_chk["log"].append({"f": Engine.get_frames_drawn(), "active": active, "key": combat.shot_key, "shot_t": snappedf(combat.shot_t, 0.0001), "hs": combat.hitstop_left,
		"skill_t": snappedf(float(st["skill_t"]), 0.0001), "fx_time": snappedf(float(st["fx_time"]), 0.0001), "stroke_pts": st["stroke_pts"],
		"sync": snappedf(float(st["stroke_sync_err"]), 0.001), "fps": Engine.get_frames_per_second(), "weapon": wstate(),
		"tip": _v3(actor.global_transform.affine_inverse() * (sword.global_transform * Vector3(0, 1.085, 0))), "act": _v3(actor.global_position)})
	if not active:
		return
	var want: Array = _chk["want"]
	var hs: bool = combat.hitstop_left > 0
	for i in want.size():
		var w := float(want[i])
		var take := (hs and not _was_hs) if w < 0.0 else combat.shot_t >= w
		if take:
			var tag: String = ["forming", "hit", "complete", "tearing"][i]
			want[i] = 99.0
			await RenderingServer.frame_post_draw
			_chk["shots"].append({"tag": tag, "shot_t": snappedf(combat.shot_t, 0.001), "img": get_viewport().get_texture().get_image()})
	_was_hs = hs

func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]

func _finish_check() -> void:
	if int(_chk["phase"]) == 9:
		return
	_chk["phase"] = 9
	for s: Dictionary in _chk["shots"]:
		var p := _check_dir.path_join("hekira_%s.png" % s["tag"])
		(s["img"] as Image).save_png(p)
		s.erase("img")
		s["path"] = p
	var f := FileAccess.open(_check_dir.path_join("hekira_check.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"casts": _chk["casts"], "dmg": dmg_log, "shots": _chk["shots"], "dup_ignored": _chk["dup"], "stats": fire.stats(), "log": _chk["log"]}))
	f.close()
	get_tree().quit()
