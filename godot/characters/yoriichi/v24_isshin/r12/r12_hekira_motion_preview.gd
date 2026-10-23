extends "res://characters/yoriichi/v24_isshin/r10/r10_combat_demo.gd"
## R12 碧羅天動作重選 — 候選動作預覽（第二輪：依參考影片＝空中前空翻；只比較動作，不含火焰；ART_REVIEW）。
## 動作都是 R10 刀法庫裡已重定向到緣一骨架的隻狼原動作，沒有改造；最後一個是目前 R11 碧羅天（對照）。
## 1–5 播放候選；T 慢動作（0.3×）切換；R 回原點；Q／E 轉鏡頭（看側面）；O 自動繞轉。白線＝刀尖軌跡（看刀路平面）。
const CANDS := [
	{"key": "lib_c5060_a000_003003", "label": "① 梟・躍起前空翻＋落地劈（單手）", "note": "沉身 0.1–0.27 s → 起跳（雙腳離地最高 2.9 m）→ 空中前翻 350° → 1.0 s 落地縱劈 54 m/s；刀尖繞身 453°、刀路最平（偏離平面 0.14 m）"},
	{"key": "lib_c0000_a050_309000", "label": "② 狼・空中前翻斬（雙手 57%）", "note": "只有空中段（沒起跳／落地，開場就浮在半空）：0.27–0.67 s 前翻 367°，刀繞身 600°、兩刀 47／56 m/s"},
	{"key": "lib_c0000_a101_316200", "label": "③ 狼・流派技 前手翻縱劈（單手）", "note": "站立 → 前手翻（頭最低 0.59 m、腳離地 0.96 m）→ 0.67 s 縱劈 59 m/s；刀繞身 494°；原地 1.0 s"},
	{"key": "lib_c1400_a000_003001", "label": "④ 葦名劍客・大上段縱劈（上一輪蓄勢最佳，對照）", "note": "0.6–1.33 s 大上段靜止 → 0.1 s 內 45 m/s、下沉 35 cm；地面縱圓約 220°，不翻身"},
	{"key": "r11_hekira", "label": "⑤ 現行 R11 碧羅天（對照）", "note": "刀尖畫 345° 圓，但圓面與地面只夾 31°（斜環）"},
]
const TIP := 1.085
var _trail := ImmediateMesh.new()
var _trail_mi: MeshInstance3D
var _pts: Array = []          # [位置, 實際時間]
var _slow := false
var _last_play := -1
## 檢查模式 -- --preview-check=DIR：依序播 1–5，每支在斬擊結束後 0.25 s 存一張（白線＝整段刀尖軌跡），記錄實際播放的招式後結束
var _check_dir := ""
var _ck := {"i": -1, "t": 0.0, "started": [], "shots": [], "armed": false}

func _pre_setup() -> void:
	super._pre_setup()
	var by := {}
	for e in library:
		by[str(e["key"])] = e
	var r11: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://characters/yoriichi/v24_isshin/r11/sun_breathing_r11.json"))
	var r11_shot: Dictionary = _clean(r11["skills"]["sun_hekiraten"]["shot"])
	combat.extra_shots["r11_hekira"] = r11_shot
	by["r11_hekira"] = {"key": "r11_hekira", "chr": "c5400", "who": "R11 碧羅天", "hkx": "a000_003031（R11 重配時）", "desc": "", "shot": r11_shot}
	var lib2: Array = []
	for c in CANDS:
		if by.has(c["key"]):
			lib2.append(by[c["key"]])
		else:
			push_warning("R12 預覽：找不到 " + str(c["key"]))
	library = lib2
	lib_ix = 0
	lib_mode = true

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--preview-check="):
			_check_dir = a.substr(16)
	super._ready()
	if _check_dir != "":
		hud_on = false
		cam_yaw_extra = deg_to_rad(60.0)        # 斜後方 60°：同時看得到側面與背面的刀路
	_trail_mi = MeshInstance3D.new()
	_trail_mi.name = "TipTrail"
	_trail_mi.mesh = _trail
	_trail_mi.top_level = true
	_trail_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = false
	_trail_mi.material_override = m
	add_child(_trail_mi)
	_reset()

func _reset() -> void:
	actor.position = Vector3.ZERO
	actor.rotation = Vector3.ZERO
	enemy_pos = Vector3(0, 0, 2.2)
	orbit_speed = 0.0

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo:
		var ke := e as InputEventKey
		var n := ke.keycode - KEY_1
		if n >= 0 and n < library.size():
			lib_ix = n
			lib_mode = true
			_last_play = n
			buf["attack"] = now
			return
		match ke.keycode:
			KEY_T:
				_slow = not _slow
				Engine.time_scale = 0.3 if _slow else 1.0
				return
			KEY_R:
				_reset()
				return
			KEY_M, KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_COMMA, KEY_PERIOD:
				return
	super._unhandled_input(e)

func _process(delta: float) -> void:
	super._process(delta)
	if sword == null:
		return
	var tnow := Time.get_ticks_msec() / 1000.0
	var in_shot: bool = combat.state == combat.S.SHOT
	if in_shot:
		_pts.append([sword.global_transform * Vector3(0, TIP, 0), tnow])
	var keep := 1.4 / maxf(Engine.time_scale, 0.05)
	while not _pts.is_empty() and tnow - float(_pts[0][1]) > keep:
		_pts.pop_front()
	_trail.clear_surfaces()
	if _pts.size() >= 2 and cam != null:
		_trail.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)          # 朝相機的 3 cm 細帶（1 px 線在 1600×900 看不清）
		for j in _pts.size():
			var p: Vector3 = _pts[j][0]
			var q: Vector3 = _pts[mini(j + 1, _pts.size() - 1)][0] - _pts[maxi(j - 1, 0)][0]
			var side := q.cross(cam.global_position - p)
			side = side.normalized() * 0.015 if side.length_squared() > 1e-10 else Vector3.UP * 0.015
			var a := clampf(1.0 - (tnow - float(_pts[j][1])) / keep, 0.0, 1.0)
			_trail.surface_set_color(Color(1.0, 0.92, 0.7, a))
			_trail.surface_add_vertex(p - side)
			_trail.surface_set_color(Color(1.0, 0.92, 0.7, a))
			_trail.surface_add_vertex(p + side)
		_trail.surface_end()
	if _check_dir != "":
		_check_step(delta, in_shot)

func _check_step(delta: float, in_shot: bool) -> void:
	_ck["t"] = float(_ck["t"]) + delta
	var i := int(_ck["i"])
	if in_shot and not bool(_ck["armed"]) and i >= 0:
		_ck["armed"] = true
		_ck["started"].append({"want": str(library[i]["key"]), "got": combat.shot_key})
	if bool(_ck["armed"]) and not in_shot:
		_ck["armed"] = false
	var sh: Dictionary = library[maxi(i, 0)]["shot"]
	var end_t: float = minf(float(sh.get("strikes", [[0, 1.0]])[-1][1]) + 0.25, float(sh.get("end_t", 99.0)) - 0.05)
	if sh.has("end_t") and float(sh["end_t"]) <= float(sh.get("strikes", [[0, 1.0]])[-1][1]):
		end_t = float(sh["end_t"]) - 0.1
	if i >= 0 and in_shot and combat.shot_key == str(library[i]["key"]) and combat.shot_t >= end_t and _ck["shots"].size() == i:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_check_dir.path_join("cand_%d.png" % (i + 1)))
		_ck["shots"].append(i)
	if float(_ck["t"]) > 1.5 and not in_shot and combat.cooldown <= 0.0 and _ck["shots"].size() == i + 1:
		if i + 1 >= library.size():
			var f := FileAccess.open(_check_dir.path_join("preview_check.json"), FileAccess.WRITE)
			f.store_string(JSON.stringify({"started": _ck["started"], "shots": _ck["shots"]}))
			f.close()
			get_tree().quit()
			return
		_reset()
		_pts.clear()
		_ck["i"] = i + 1
		_ck["t"] = 0.0
		lib_ix = i + 1
		buf["attack"] = now
	elif i < 0 and float(_ck["t"]) > 1.5:
		_ck["shots"] = []
		_ck["i"] = 0
		_ck["t"] = 0.0
		lib_ix = 0
		buf["attack"] = now

func _hud_text() -> String:
	var lines: Array = ["【R12 碧羅天動作候選預覽】1–5 播放　T 慢動作（%s）　R 回原點　Q／E 轉鏡頭　O 繞轉　白線＝刀尖軌跡" % ("0.3×" if _slow else "1×")]
	for i in CANDS.size():
		var c: Dictionary = CANDS[i]
		lines.append("%s %d %s — %s" % ["▶" if i == lib_ix else "　", i + 1, c["label"], c["note"]])
	lines.append("出招中：%s  t=%.2f" % [combat.shot_key if combat.state == combat.S.SHOT else "—", combat.shot_t])
	return "\n".join(lines)
