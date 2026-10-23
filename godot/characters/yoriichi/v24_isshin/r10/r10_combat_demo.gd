extends "res://characters/yoriichi/v24_isshin/r9/r9_combat_demo.gd"
## 緣一 R10 綜合戰鬥試玩（候選 ART_REVIEW；不改正式 Player／跑酷／正式場景；R9／R9-C3 場景與資料原樣保留）。
## 一、居合：居合架勢與居合攻擊分開。刀在鞘中可以走、跑、衝刺、轉身、閃避（c1400 居合型 a100 的居合構步行組，
##     右手扶柄、左手握鞘口；notes/r10/build_sheathed_loco.py），停下回到居合構；按移動不再自動拔刀。
##     G＝主動拔刀／納刀；居合構＋攻擊＝目前選定的居合招（二連斬／居合上撩）；居合斬 a100_003021 已從預設路由移除（資料保留）。
## 二、日之呼吸：資料驅動（r10/sun_breathing_r10.json：名稱、動畫、起手條件、攻擊段、傷害、取消、冷卻、VFX、音效、可銜接）。
##     Z／X 切換型，L／滑鼠右鍵施放；壹 圓舞、貳 碧羅天、參 烈日紅鏡。
## 三、隻狼刀法庫：notes/r10/survey_all.py 盤點的全部持刀者（不含猴）可用刀法，批次重定向後在這裡試用；M 開關刀法庫、[ / ] 上一招／下一招、
##     , / . 換角色、J 出招。每招保留原動作的收勢段，結尾依「收勢姿勢與待機的差」決定淡回時間（過渡）。
## 武器邏輯狀態（HUD 顯示）：刀在鞘中／居合構／拔刀過渡／刀已出鞘／普通劍術攻擊中／居合攻擊中／納刀過渡（＋日之呼吸中）。
const R10_DIR := "res://characters/yoriichi/v24_isshin/r10/"
var skill_order: Array = []
var iai_sel_key := "twocut"
var normal_sel_key := "slash_v"
var library: Array = []
var lib_ix := 0
var lib_mode := false
var _shift_ms := -1
var hud_mode := 0          # 0＝精簡（狀態／型／刀法庫）、1＝完整說明、2＝隱藏；H 切換

func _pre_setup() -> void:
	r9 = JSON.parse_string(FileAccess.get_file_as_string(R10_DIR + "r10_moveset.json"))
	sun = JSON.parse_string(FileAccess.get_file_as_string(R10_DIR + "sun_breathing_r10.json"))
	skills = sun["skills"]
	skill_order = sun.get("order", skills.keys())
	cur_skill = str(skill_order[0])
	combat.sprint_anim = str(r9["sprint"]["anim"])
	combat.sprint_speed = float(r9["sprint"]["speed"])
	for k in r9["shots"]:
		combat.extra_shots[k] = _clean(r9["shots"][k])
	for k in skills:
		combat.extra_shots[k] = _clean(skills[k]["shot"])
	# 鞘中移動組（居合構步行／後退／橫移／突進跑；轉身）
	combat.sheathed = JSON.parse_string(FileAccess.get_file_as_string(R10_DIR + "r10_sheathed.json"))
	combat.extra_shots["sturn_l90"] = {"anim": "isshin_sh_turn_l90", "angle": 90.0, "fade_in": 0.05, "fade_out": 0.14, "yaw_scale_max": 2.0}
	combat.extra_shots["sturn_r90"] = {"anim": "isshin_sh_turn_r90", "angle": -90.0, "fade_in": 0.05, "fade_out": 0.14, "yaw_scale_max": 2.0}
	# 隻狼刀法庫
	if FileAccess.file_exists(R10_DIR + "r10_library.json"):
		var L: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(R10_DIR + "r10_library.json"))
		for e in L.get("moves", []):
			if FileAccess.file_exists("res://characters/yoriichi/v24_isshin/anims/" + str(e["shot"]["anim"]) + ".res"):
				library.append(e)
				combat.extra_shots[str(e["key"])] = e["shot"]
	auto_draw_on_move = false
	auto_pending_after_switch = false

func _ready() -> void:
	super._ready()
	if not ("--vfx=" in " ".join(OS.get_cmdline_user_args())):
		vfx_variant = str(sun.get("vfx_variant", "R10"))
	if hud:
		hud.add_theme_font_size_override("font_size", 16)

func _build_world() -> void:
	super._build_world()
	if _env_res != null:                     # R10：火焰核心更像高溫自發光——泛光門檻略降、強度略升（不靠整體曝光）
		_env_res.glow_hdr_threshold = 0.95
		_env_res.glow_intensity = 0.75
		_env_res.glow_strength = 1.0
		_env_res.glow_bloom = 0.02

# ------------------------------------------------------------------ 輸入
func _move_input() -> Vector2:
	if tour:
		return tour_input
	var x := float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	var y := float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S))
	if y > 0.0 and x == 0.0 and Input.is_key_pressed(KEY_SHIFT):
		if _shift_ms < 0:
			_shift_ms = Time.get_ticks_msec()
		y = 2.0 if Time.get_ticks_msec() - _shift_ms < 450 else 3.0      # Shift+W：先跑，按住 0.45 s 後衝刺
	else:
		_shift_ms = -1
	return Vector2(x, y)

## 一般攻擊的起手招：選中的是居合系就用上一個一般招（不因選招而換武器狀態或自動出招）
func _sel_key() -> String:
	var k: String = moves[sel]["key"]
	return k if _req(k) != "sheathed" else normal_sel_key

func _router(ctx: String) -> String:
	if weapon == "sheathed" and ctx == "loco":
		if combat.shots.has(iai_sel_key):
			route_log.append({"t": snappedf(now, 0.001), "ctx": ctx, "branch": "sheathed", "move": iai_sel_key, "weapon": weapon})
			_last_route = "居合構＋攻擊 → %s" % iai_sel_key
			return iai_sel_key
		return ""
	if lib_mode and ctx == "loco" and weapon == "drawn" and not library.is_empty():
		var k := str(library[lib_ix]["key"])
		route_log.append({"t": snappedf(now, 0.001), "ctx": ctx, "branch": "library", "move": k, "weapon": weapon})
		_last_route = "刀法庫 → %s" % k
		return k
	return super._router(ctx)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo:
		var ke := e as InputEventKey
		match ke.keycode:
			KEY_Z, KEY_X:
				var i := skill_order.find(cur_skill)
				cur_skill = str(skill_order[posmod(i + (1 if ke.keycode == KEY_X else -1), skill_order.size())])
				return
			KEY_M:
				lib_mode = not lib_mode and not library.is_empty()
				return
			KEY_H:
				hud_mode = (hud_mode + 1) % 3
				hud_on = hud_mode != 2
				return
			KEY_C:                                      # 特效版本：R9 原始程式刀光 → A → B → C1–C3 → L1 → L2 → R10（新型沒有的版本用 R10）
				var order := ["r9", "A", "B", "C1", "C2", "C3", "L1", "L2", "R10"]
				vfx_variant = order[(order.find(vfx_variant) + 1) % order.size()]
				return
			KEY_BRACKETRIGHT, KEY_BRACKETLEFT:
				if not library.is_empty():
					lib_ix = posmod(lib_ix + (1 if ke.keycode == KEY_BRACKETRIGHT else -1), library.size())
					lib_mode = true
				return
			KEY_PERIOD, KEY_COMMA:
				if not library.is_empty():
					var who := str(library[lib_ix]["chr"])
					var step := 1 if ke.keycode == KEY_PERIOD else -1
					var j := lib_ix
					for _n in library.size():
						j = posmod(j + step, library.size())
						if str(library[j]["chr"]) != who:
							break
					if step < 0:                     # 跳到該角色的第一招
						var c2 := str(library[j]["chr"])
						while j > 0 and str(library[j - 1]["chr"]) == c2:
							j -= 1
					lib_ix = j
					lib_mode = true
				return
	super._unhandled_input(e)
	var k: String = moves[sel]["key"]
	if _req(k) == "sheathed":
		iai_sel_key = k
	else:
		normal_sel_key = k

# ------------------------------------------------------------------ 日之呼吸：每一型對應自己的 mesh 特效版本
func _mesh_variant(key: String, v: String) -> String:
	var mp: Dictionary = skills[key].get("vfx_map", {})
	if mp.is_empty():
		return v
	return str(mp.get(v, mp.get("*", v)))

func _begin_skill(key: String) -> void:
	skill_key = key
	_skill_variant = vfx_variant
	vfx.enabled = vfx_on
	mvfx.enabled = vfx_on
	if _skill_variant == "r9":
		vfx.begin(skills[key]["vfx"])
	else:
		mvfx.begin(_mesh_variant(key, _skill_variant))
	saudio.begin(skills[key]["audio"])

# ------------------------------------------------------------------ 武器邏輯狀態
func wstate() -> String:
	if combat.state == combat.S.SHOT:
		var k: String = combat.shot_key
		if k == "draw":
			return "drawing"
		if k == "noto":
			return "sheathing"
		if skills.has(k):
			return "breathing"
		if bool(combat._cfg(k).get("attack", false)):
			return "iai_attack" if _req(k) == "sheathed" else "attack"
	if weapon == "sheathed":
		return "iai_stance" if combat.g < 0.05 else "sheathed"
	return "drawn"

const WS_LABEL := {"sheathed": "刀在鞘中（移動）", "iai_stance": "居合構", "drawing": "拔刀過渡", "drawn": "刀已出鞘", "attack": "普通劍術攻擊中",
	"iai_attack": "居合攻擊中", "sheathing": "納刀過渡", "breathing": "日之呼吸"}
const WS_ALLOW := {"sheathed": "可：走／跑／衝刺／轉身／閃避／居合攻擊／拔刀／呼吸（先拔刀）", "iai_stance": "可：移動／閃避／居合攻擊／拔刀／呼吸（先拔刀）",
	"drawing": "拔刀中：不可移動（0.13 s）", "drawn": "可：移動／衝刺／閃避／跳躍／普通劍術／日之呼吸／納刀", "attack": "取消窗內可：閃避／移動／接招／呼吸",
	"iai_attack": "納刀前取消＝刀留手上；不取消＝完整納刀回居合構", "sheathing": "納刀中：完成後回居合構", "breathing": "取消窗內可：閃避／移動／接招"}

func _hud_text() -> String:
	var ws := wstate()
	var cd := maxf(0.0, float(skill_cd.get(cur_skill, 0.0)) - now)
	if hud_mode == 0:
		var c := ["%s　｜　%s%s　｜　H 說明" % [WS_LABEL.get(ws, ws), str(skills[cur_skill]["name"]).replace("日之呼吸・", ""), "（冷卻 %.1f s）" % cd if cd > 0.0 else ""]]
		if lib_mode and not library.is_empty():
			var e0: Dictionary = library[lib_ix]
			c.append("刀法庫 %d/%d：%s %s　%s" % [lib_ix + 1, library.size(), e0["who"], e0["hkx"], e0.get("desc", "")])
		return "\n".join(c)
	var lines := ["緣一 R10 綜合戰鬥試玩（候選 ART_REVIEW）   FPS %d   特效：%s（V）  版本：%s（C）  環境：%s（N）" % [Engine.get_frames_per_second(),
		"開" if vfx_on else "關", vfx_variant, "黃昏森林" if env_mode == "dusk" else "白天"],
		"武器狀態：%s　%s" % [WS_LABEL.get(ws, ws), WS_ALLOW.get(ws, "")],
		"WASD 移動　Shift+W 跑（按住＝衝刺）　Space 閃避　F 跳躍（刀在手）　G 拔刀／納刀　J／左鍵 攻擊　L／右鍵 日之呼吸　Z／X 換型",
		"日之呼吸：" + "　".join(skill_order.map(func(k): return ("▶" if k == cur_skill else "") + str(skills[k]["name"]).replace("日之呼吸・", ""))) + ("（冷卻 %.1f s）" % cd if cd > 0.0 else ""),
		"居合構攻擊＝%s　一般攻擊起手＝%s　（1–0 選招、Tab 換頁；選到居合系＝設成居合構的攻擊）" % [_label_of(iai_sel_key), _label_of(normal_sel_key)]]
	if not library.is_empty():
		var e: Dictionary = library[lib_ix]
		lines.append("刀法庫 %s（M）%d/%d：%s %s　%s　（[ ] 換招　, . 換角色）" % ["開" if lib_mode else "關", lib_ix + 1, library.size(), e["who"], e["hkx"], e.get("desc", "")])
	var page := sel / 10
	var row := []
	for i in range(page * 10, mini(moves.size(), page * 10 + 10)):
		var m: Dictionary = moves[i]
		row.append("%s%d %s%s" % ["▶" if i == sel else "", (i % 10 + 1) % 10, m["label"], "（鞘）" if str(m.get("req", "drawn")) == "sheathed" else ""])
	lines.append("　".join(row))
	lines.append("出招中：%s  t=%.2f   上一次：%s" % [combat.shot_key if combat.state == combat.S.SHOT else "—", combat.shot_t, _last_route])
	return "\n".join(lines)

## 導覽段額外參數：form＝日之呼吸型 key、iai＝居合構攻擊的招、lib＝刀法庫 key（開刀法庫模式）
func _tour_step(delta: float) -> void:
	var prev := tour_ix
	super._tour_step(delta)
	if tour_ix != prev and tour_ix >= 0 and tour_ix < tour_steps.size():
		var st: Dictionary = tour_steps[tour_ix]
		if st.has("form"):
			cur_skill = str(st["form"])
		if st.has("iai"):
			iai_sel_key = str(st["iai"])
		if st.has("lib"):
			lib_mode = true
			for i in library.size():
				if str(library[i]["key"]) == str(st["lib"]):
					lib_ix = i
		elif st.has("select"):
			lib_mode = false
	if tour and slashlog_path != "":
		wlog.append({"t": snappedf(tour_t - TOUR_START_DELAY, 0.001), "ws": wstate(), "weapon": weapon, "shot": combat.shot_key if combat.state == combat.S.SHOT else "",
			"g": snappedf(combat.g, 0.01), "bp": [snappedf(combat.bp.x, 0.01), snappedf(combat.bp.y, 0.01)], "pos": [snappedf(actor.global_position.x, 0.001), snappedf(actor.global_position.z, 0.001)], "yaw": snappedf(actor.rotation.y, 0.0001), "st": combat.state, "shot_t": snappedf(combat.shot_t, 0.001),
			"sword": sword.visible, "sheath_sword": sword_sheathed.visible, "label": cur_label})

var wlog: Array = []

func _finish_tour() -> void:
	if slashlog_path != "":
		var f := FileAccess.open(slashlog_path.get_basename() + "_r10.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"w": wlog}))
		f.close()
	super._finish_tour()

func _label_of(k: String) -> String:
	if move_ix.has(k):
		return str(moves[move_ix[k]]["label"])
	return k
