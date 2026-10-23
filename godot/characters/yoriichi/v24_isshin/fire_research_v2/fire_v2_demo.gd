extends "res://characters/yoriichi/v24_isshin/r9/r9_combat_demo.gd"
## 日之呼吸火焰系統（統一版）試玩場景（候選 ART_REVIEW）。沿用 R9 綜合試玩的全部動作、派生、判定、Hit Stop；
## 圓舞的 VFX 改由單一入口 sun_fire.gd 播放（R9 程式刀光＋Blender 火焰造型＋FIRE_RESEARCH_V2 動態燃燒整合成一套）。戰鬥控制器不改。
## （本場景原為 FIRE_RESEARCH_V2 試玩；V2 研究模組 fire_v2.gd 保留在同資料夾作為來源，不再掛載。）
## 操作（其餘同 R9）：L／滑鼠右鍵 圓舞；B 統一版 ↔ 原始 R9 程式刀光；R 回到木樁前 1.4 m；V 特效開關；N 白天／黃昏。
## 功能檢查：-- --fire-check=OUT_DIR（統一版施放一次＋原始 R9 一次；記錄命中、停格、重複命中防護，存 4 張第三人稱圖後結束）
const SunFire = preload("res://characters/yoriichi/v24_isshin/fire_research_v2/sun_fire.gd")
const UNIFIED := "SUN"
var fire
var _check_dir := ""
var _chk := {"phase": 0, "t": 0.0, "log": [], "shots": [], "casts": [], "want": [], "dup": []}

func _ready() -> void:
	var forced := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--vfx="):
			forced = true
		elif a.begins_with("--fire-check="):
			_check_dir = a.substr(13)
	super._ready()
	Engine.max_fps = 60                     # 與 R9 判定驗證相同的情境（渲染驅動的刀身掃掠）
	fire = SunFire.new()
	fire.name = "SunFire"
	add_child(fire)
	fire.setup(actor, sword, cam)
	fire.enabled = vfx_on
	if not forced:
		vfx_variant = UNIFIED
	if _check_dir != "":
		hud_on = false                   # 檢查圖不要被說明文字擋住
	_reset_to_dummy()

func _reset_to_dummy() -> void:
	actor.position = Vector3.ZERO
	actor.rotation = Vector3.ZERO
	enemy_pos = Vector3(0, 0, 1.4)
	orbit_speed = 0.0

func _begin_skill(key: String) -> void:
	if vfx_variant != UNIFIED or not fire.has_skill(key):
		super._begin_skill(key)
		return
	skill_key = key
	_skill_variant = UNIFIED
	fire.enabled = vfx_on
	fire.begin(key)
	saudio.begin(skills[key]["audio"])
	if _check_dir != "":
		_chk["casts"].append({"variant": UNIFIED, "now": snappedf(now, 0.001)})

func _vfx_frame() -> void:
	if fire == null or sword == null:
		super._vfx_frame()
		return
	var mine: bool = _skill_variant == UNIFIED and skill_key != ""
	var active: bool = mine and combat.state == combat.S.SHOT and combat.shot_key == skill_key
	if mine and not active:
		fire.end()
	super._vfx_frame()                      # 原始 R9 模組照常推進（統一版時它們沒有 begin，不會畫東西）
	var dt := get_process_delta_time()
	var t: float = combat.shot_t if active else fire.skill_t + dt
	fire.frame(sword.global_transform, t, dt, combat.hitstop_left > 0, tip_speed)
	if _check_dir != "":
		_check_frame(active)

func _on_hit(info: Dictionary) -> void:
	if _skill_variant != UNIFIED:
		super._on_hit(info)
		if _check_dir != "" and skills.has(str(info.get("key", ""))):
			_chk["log"].append({"ev": "hit", "variant": _skill_variant, "shot_t": snappedf(combat.shot_t, 0.001), "hp": dummy_hp})
		return
	# 基底照常扣血／記錄／停格，但不呼叫舊特效的命中（暫時當成 r9：原始 R9 模組沒在出招，hit 直接略過）
	_skill_variant = "r9"
	super._on_hit(info)
	_skill_variant = UNIFIED
	var key := str(info.get("key", ""))
	if skills.has(key) and vfx_on:
		var p: Vector3 = info.get("entry", info["pos"])
		var nrm := p - enemy_pos
		nrm.y = 0.0
		fire.hit(p, info.get("dir", Vector3.DOWN), nrm, int(info.get("strike", 0)))
		if _check_dir != "":                # 檢查：同一段判定再送一次，必須被忽略
			fire.hit(p, info.get("dir", Vector3.DOWN), nrm, int(info.get("strike", 0)))
			_chk["dup"].append(fire.stats()["hits_ignored"])
	if _check_dir != "" and skills.has(key):
		_chk["log"].append({"ev": "hit", "variant": UNIFIED, "shot_t": snappedf(combat.shot_t, 0.001), "hp": dummy_hp, "dmg": int(skills[key].get("damage", 1))})

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo:
		var ke := e as InputEventKey
		match ke.keycode:
			KEY_B:
				_switch("r9" if vfx_variant == UNIFIED else UNIFIED)
				return
			KEY_C:
				return                          # 不再輪切舊候選
			KEY_R:
				_reset_to_dummy()
				return
			KEY_V:
				super._unhandled_input(e)
				fire.enabled = vfx_on
				return
	super._unhandled_input(e)

func _switch(v: String) -> void:
	vfx_variant = v
	if v != UNIFIED:
		fire.clear()

func _hud_text() -> String:
	var name_ := "日之呼吸火焰（統一版）" if vfx_variant == UNIFIED else "原始 R9 程式刀光"
	return "【圓舞特效】%s   B＝統一版 ↔ 原始 R9   R＝回木樁前\n" % name_ + super._hud_text()

# ------------------------------------------------------------------ 功能檢查（一次性：統一版施放 → 原始 R9 施放 → 存檔結束）
func _process(delta: float) -> void:
	super._process(delta)
	if _check_dir == "":
		return
	_chk["t"] = float(_chk["t"]) + delta
	var ph := int(_chk["phase"])
	var idle: bool = combat.state != combat.S.SHOT and combat.cooldown <= 0.0
	if ph == 0 and float(_chk["t"]) > 1.5 and idle:
		_switch(UNIFIED)
		_reset_to_dummy()
		_chk["want"] = [0.36, -1.0, 0.66, 0.95]      # 擷圖會卡一幀：只在判定窗之外或命中之後拍
		buf["skill"] = now
		_chk["phase"] = 1
	elif ph == 1 and float(_chk["t"]) > 1.8 and idle and now > float(skill_cd.get("sun_enbu", 0.0)) + 0.9:
		_chk["phase"] = 2
		_chk["t2"] = _chk["t"]
	elif ph == 2 and float(_chk["t"]) - float(_chk["t2"]) > 0.4:
		_switch("r9")
		_reset_to_dummy()
		buf["skill"] = now
		_chk["want"] = []
		_chk["phase"] = 3
	elif ph == 3 and float(_chk["t"]) - float(_chk["t2"]) > 1.0 and idle and now > float(skill_cd.get("sun_enbu", 0.0)) + 0.3:
		_finish_check()

var _was_hs := false
func _check_frame(active: bool) -> void:
	var st: Dictionary = fire.stats()
	_chk["log"].append({"f": Engine.get_frames_drawn(), "variant": _skill_variant, "active": active, "shot_t": snappedf(combat.shot_t, 0.0001),
		"hs": combat.hitstop_left, "tip_v": snappedf(tip_speed, 0.01), "trail": st["trail_live"], "emit": st["emitted"], "flashes": st["flashes"],
		"fx_time": snappedf(float(st["fx_time"]), 0.0001), "skill_t": snappedf(float(st["skill_t"]), 0.0001), "frozen_arc": st["frozen_arc"], "fps": Engine.get_frames_per_second()})
	if _skill_variant != UNIFIED or not active:
		return
	var want: Array = _chk["want"]
	var hs: bool = combat.hitstop_left > 0
	for i in want.size():
		var w := float(want[i])
		var take := false
		if w < 0.0:
			take = hs and not _was_hs          # 命中停格的第一格
		else:
			take = combat.shot_t >= w
		if take:
			var tag: String = ["ignite", "hit", "slash", "residual"][i]
			want[i] = 99.0
			await RenderingServer.frame_post_draw
			_chk["shots"].append({"tag": tag, "shot_t": snappedf(combat.shot_t, 0.001), "img": get_viewport().get_texture().get_image()})
	_was_hs = hs

func _finish_check() -> void:
	for s: Dictionary in _chk["shots"]:
		var p := _check_dir.path_join("sun_%s.png" % s["tag"])
		(s["img"] as Image).save_png(p)
		s.erase("img")
		s["path"] = p
	var f := FileAccess.open(_check_dir.path_join("function_check.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"casts": _chk["casts"], "routes": route_log, "dmg": dmg_log, "shots": _chk["shots"], "dup_ignored": _chk["dup"],
		"stats": fire.stats(), "log": _chk["log"]}))
	f.close()
	get_tree().quit()
