extends "res://characters/yoriichi/v24_isshin/r15/r15_sun_all_demo.gd"
## 緣一 R16 日之呼吸道場（ART_REVIEW）。R16b（2026-10-23 晚，使用者《特效更新》）：
## - 所有日之呼吸預設播「新版特效」＝統一系統 sun_fire.gd＋aoe 子模組的 'fx2/<技能>' profile（r16/fx2_profiles.json，notes/r16/build_fx_r16b.py 產生）：
##   白金核心＋金黃主體＋橘紅外焰＋少量淡粉紅火舌末端；每一型自己的主特效形狀、方向、時間、消散。舊的完整特效（風格化火帶、Blender 火焰網格、
##   R11／R12 原特效）不會和新版同時播放；唯一例外是日暈之龍保留上一版（R15）的龍身火帶與 sun_dragon 龍頭（使用者指定）。
## - B＝新版特效 ↔ 舊版特效（回退：每一型原本的特效，含 R12 火車 Blender KS12、R13 炎舞風格化火帶、R9／R11／R10 原特效）。舊 profile 一筆都沒改。
## - 清單：先是每一型目前的候選（R16b 圓舞 #83、碧羅天、烈日紅鏡、灼骨炎陽、陽華突、日暈之龍（恢復上一版）、斜陽轉身、飛輪陽炎、輝輝恩光、
##   火車、幻日紅、炎舞 R13／R16、圓舞一閃），後面是比較用的舊版本（R16 第一批圓舞／日暈、R15 各版、R9 圓舞、R11 碧羅天、R12 火車）。
## - 判定、傷害、命中次數、擊退、碰撞：照各技能原本的規則（特效只是視覺）。
## 操作：WASD 移動  L／右鍵 出招  Z／X 換型  T 換目標  R 重設位置  Space 閃避（蓄勢段可取消）  V 特效開關  B 新版／舊版特效
##       Q／E、←／→ 轉鏡頭  H 說明。技能不接管鏡頭。
## 功能檢查：-- --r15-check=OUT_DIR [--only=id1,id2] [--full=id1,id2（其他只跑主測試）] [--shots] [--old-fx]
## 2026-10-24 十二式整合：Z／X 只在「日之呼吸」唯一清單裡循環（characters/yoriichi/sun_breathing_registry.json，
##   漫畫第 192 話順序 01 圓舞 → … → 12 炎舞 → 13 圓舞一閃（衍生技）→ 01；X＝下一個、Z＝上一個），預設選中 01 圓舞。招式本身（動作、判定、傷害、特效）照各技能原檔。
##   13 圓舞一閃是額外可選的衍生技（r15/skills/sun_enbu_issen.json 原檔），不屬於十二式、不進第十三型的循環。
##   舊的比較清單（各型舊版本）：啟動參數 -- --legacy-list。
const R16_DIR := "res://characters/yoriichi/v24_isshin/r16/"
const SunRegistry = preload("res://characters/yoriichi/sun_breathing_registry.gd")
const R16_ORDER := ["sun_enbu_r16b", "sun_nichirin_r16b", "sun_kasha_r16b", "sun_youkatotsu_r16b", "sun_enbu_double_r16c", "sun_enbu_r16", "sun_enbu_double_r16", "sun_kasha_r16", "sun_genjitsu_r16", "sun_shakkotsu_r16", "sun_shakkotsu_r16d", "sun_shakkotsu_r16f", "sun_nichirin_r16"]
## 每一型目前的候選（清單最前面，依型的順序）；其他＝比較用的舊版本
## R16c：炎舞 2 倍速 sun_enbu_double_r16c（R13 已驗收動作 ×2）排在 R13 炎舞前面。
## R16b 第二輪：火車＝sun_kasha_r16b（瞬步＋高速縱向迴旋斬）、陽華突＝sun_youkatotsu_r16b（更高跳）放在各型的位置；R12 火車、R16 火車、R14 陽華突照舊留在清單後段比較
const MAIN_ORDER := ["sun_enbu_r16b", "sun_hekiraten_r15", "sun_retsujitsu", "sun_shakkotsu_r16f", "sun_youkatotsu_r16b", "sun_nichirin_r16b",
	"sun_shayou_tenshin", "sun_hirin_kagerou", "sun_kiki_onkou", "sun_kasha_r16b", "sun_genjitsu_r16", "sun_enbu_double_r16c", "sun_enbu_double", "sun_enbu_double_r16", "sun_enbu_issen"]
## 一次整體視覺檢查用的截圖時間（技能秒數；--shots 才用）
const R16_SHOTS := {"sun_kasha_r16b": [0.5, 0.68, 0.9], "sun_youkatotsu_r16b": [0.6, 0.92], "sun_enbu_double_r16c": [0.33, 0.69],
	"sun_enbu_r16b": [0.45, 0.86, 1.15], "sun_shakkotsu_r16": [0.95, 1.2, 1.5], "sun_shakkotsu_r16d": [0.99, 1.12, 1.35, 1.65], "sun_shakkotsu_r16f": [0.884, 0.994, 1.188, 1.442], "sun_nichirin_r16b": [1.22, 2.1, 3.25],
	"sun_kasha_r16": [0.8, 1.12, 1.45], "sun_retsujitsu": [0.66, 1.02], "sun_hekiraten_r15": [0.95], "sun_youkatotsu": [0.78], "sun_shayou_tenshin": [0.6],
	"sun_hirin_kagerou": [1.3], "sun_kiki_onkou": [0.86, 1.0], "sun_enbu_issen": [0.5, 0.82], "sun_genjitsu_r16": [0.42, 0.9], "sun_enbu_double": [1.4],
	"sun_enbu_double_r16": [0.75]}
var fx_new := true
var _full: Array = []
var _projectile_safety := false
var _legacy_list := false      # true＝舊的比較清單（各型候選＋舊版本）；預設＝十二式唯一清單

func _pre_setup() -> void:
	super._pre_setup()
	var base: Dictionary = (skills["sun_hekiraten"] as Dictionary).duplicate(true)   # 輸入／派生沿用（同 R15）
	for k in ["vfx_variants", "vfx_map", "vfx", "_anim"]:
		base.erase(k)
	for key in R16_ORDER:
		var p: String = R16_DIR + "skills/" + key + ".json"
		if not FileAccess.file_exists(p):
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
			"knock": d2.get("knock", []), "issues": d2.get("issues", []), "label": s2["name"]}
	for key in R16_SHOTS:
		if meta.has(key):
			meta[key]["shots"] = R16_SHOTS[key]
	var order: Array = []
	for key in MAIN_ORDER:
		if skills.has(key):
			order.append(key)
	for key in R16_ORDER + skill_order:
		if skills.has(key) and not order.has(key):
			order.append(key)
	skill_order = order
	cur_skill = str(order[0])
	if not _legacy_list:
		_use_sun12()

## 十二式唯一清單：選單順序、顯示名稱、狀態都從清單來；技能資料（動作、判定、傷害、特效）仍是各技能原本載入的那份，不改
func _use_sun12() -> void:
	var order: Array = []
	for e: Dictionary in SunRegistry.entries():
		var key := str(e["skill_key"])
		if not skills.has(key):
			push_error("SUN12 清單的技能沒有載入：%s %s" % [SunRegistry.label(e), key])
			continue
		order.append(key)
		skills[key]["name"] = SunRegistry.label(e)
		if str(e["anim"]) != str(skills[key]["shot"]["anim"]):   # 收勢挺直版動畫（清單決定）；技能 JSON 不改，--legacy-list＝原動畫
			skills[key]["shot"]["anim"] = str(e["anim"])
			combat.extra_shots[key]["anim"] = str(e["anim"])
		if meta.has(key):
			meta[key]["label"] = SunRegistry.label(e)
			meta[key]["status"] = "%s　版本：%s" % [str(e["status"]), str(e["version"])]
	skill_order = order
	cur_skill = str(order[0])

## 新版特效（預設）：fx2/<技能> profile；舊版（B）：照 R15 道場原本的路徑（R12 火車 KS12、R9／R11／R10 原特效、各自原本的 profile）
func _begin_skill(key: String) -> void:
	var pk := "fx2/" + key
	if fx_new and fire.has_skill(pk):
		_fx_key = key
		_fx_done.clear()
		skill_key = key
		_skill_variant = UNIFIED
		fire.enabled = vfx_on
		fire.begin(pk)
		saudio.begin(skills[key]["audio"])
		return
	super._begin_skill(key)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo and (e as InputEventKey).keycode == KEY_B:
		if combat.state == combat.S.SHOT:
			return
		fx_new = not fx_new
		fire.clear()
		_flash_msg("特效：%s" % ("新版（統一火焰＋淡粉紅末端）" if fx_new else "舊版（回退；各型原本的特效）"))
		return
	super._unhandled_input(e)

## 繞行弧＋上步（R16 幻日紅：arc.approach＝繞到側後方之後，半徑在 approach.t0–t1 由 r_end 收到 approach.r，讓雙手下劈真的砍到木樁）；
## 沒有 approach 的型（R15 幻日紅）照 R15 原本的弧
func _add_wall(pos: Vector3, yaw: float, size: Vector3) -> void:
	# Opt-in local safety test: a tall wall guarantees an airborne bolt cannot fly over it.
	if _projectile_safety:
		size.y = 5.0
	super._add_wall(pos, yaw, size)

func _arc_drive() -> void:
	var key := combat.shot_key if combat.state == combat.S.SHOT else ""
	if key == "" or not meta.has(key) or not (meta[key].get("arc", {}) as Dictionary).has("approach"):
		super._arc_drive()
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
	var r := lerpf(float(_arc["d"]), float(a["r_end"]), e)
	var ap: Dictionary = a["approach"]
	var w := clampf((combat.shot_t - float(ap["t0"])) / maxf(float(ap["t1"]) - float(ap["t0"]), 1e-3), 0.0, 1.0)
	r = lerpf(r, float(ap["r"]), w * w * (3.0 - 2.0 * w))
	r = maxf(r, float(a.get("r_min", 1.0)))
	var p: Vector3 = (_arc["tg"] as Vector3) + (_arc["v0"] as Vector3).rotated(Vector3.UP, deg_to_rad(float(a["phi_deg"])) * e) * r
	actor.global_position = Vector3(p.x, actor.global_position.y, p.z)
	_arc["last_t"] = combat.shot_t

## 殘影材質預熱：第一次殘影會即時編譯 StandardMaterial3D（實測日暈之龍第一次瞬步時卡約 180 ms，剛好蓋掉第一刀）
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--projectile-safety":
			_projectile_safety = true
		elif a == "--old-fx":
			fx_new = false
		elif a == "--legacy-list":
			_legacy_list = true
		elif a.begins_with("--full="):
			_full = Array(a.substr(7).split(","))
	super._ready()
	fire.aoe.visual_target = func() -> Vector3: return enemy_pos + Vector3(0, 1.1, 0)
	_spawn_ghost(0.05, 0.01, [1.0, 0.5, 0.2])
	if not _legacy_list:
		_sun12_selftest(_r15_dir != "")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--start-skill=") and skills.has(arg.substr(14)):
			cur_skill = arg.substr(14)
			_reset_to_dummy()

## 十二式清單自我檢查（每次啟動）：清單內容與各技能 JSON 一致；功能檢查模式另外真的送 X／Z 按鍵各 12 次，
## 記下每一步選到的名稱、動畫、特效 profile（走的是實際換型的輸入路徑）
func _sun12_selftest(cycle: bool) -> void:
	var bad := SunRegistry.validate()
	if not bad.is_empty():
		push_error("SUN12 清單有問題：%s" % JSON.stringify(bad))
	print("SUN12_REGISTRY count=%d forms=%d derived=%d problems=%d %s" % [skill_order.size(), SunRegistry.forms().size(),
		SunRegistry.derived().size(), bad.size(), JSON.stringify(bad)])
	if not cycle:
		return
	var keep := cur_skill
	for dir in [1, -1]:
		cur_skill = str(skill_order[0])
		var seq: Array = [cur_skill]
		for i in SunRegistry.COUNT:
			var ev := InputEventKey.new()
			ev.pressed = true
			ev.keycode = KEY_X if dir > 0 else KEY_Z
			_unhandled_input(ev)
			seq.append(cur_skill)
		var rows: Array = []
		for k: String in seq:
			var e := SunRegistry.entry_by_skill(k)
			var anim := str((combat.extra_shots.get(k, {}) as Dictionary).get("anim", ""))
			var pk := "fx2/" + k
			var ok: bool = anim == str(e.get("anim", "?")) and pk == str(e.get("vfx_profile", "?")) and fire.has_skill(pk) \
				and ResourceLoader.exists(str(e.get("anim_res", ""))) and str(skills[k]["name"]) == SunRegistry.label(e)
			rows.append("%s|%s|%s|%s|%s" % [str(e.get("menu", "??")), str(skills[k]["name"]), anim, pk if fire.has_skill(pk) else "NO_FX", "ok" if ok else "MISMATCH"])
		print("SUN12_CYCLE %s %s" % ["X" if dir > 0 else "Z", " > ".join(rows)])
	cur_skill = keep
	_reset_to_dummy()

## 殘影（R16b）：R15 的做法每個殘影都在 CPU 上烘焙 10 個蒙皮網格（共 15.8 萬頂點），實測每次卡 70–106 ms——日暈之龍第一刀因此漏判、
## 有殘影的招式出招時明顯頓一下。改成「凍結骨架」：新建 Skeleton3D 複製同名骨頭與此刻的姿勢（由全域姿勢換算，含 IK 修正），原本的網格＋skin
## 掛上去由 GPU 蒙皮：幾何相同、材質與淡出相同（同一個 _ghosts 清單），只是不再 CPU 烘焙。沒有骨架時退回 R15 原本的做法。
func _spawn_ghost(life: float, alpha: float, col: Array) -> void:
	var sks := actor.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		super._spawn_ghost(life, alpha, col)
		return
	var src: Skeleton3D = sks[0]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(float(col[0]), float(col[1]), float(col[2]), alpha)
	var gs := Skeleton3D.new()
	var nb := src.get_bone_count()
	for b in nb:
		gs.add_bone(src.get_bone_name(b))
	for b in nb:
		gs.set_bone_parent(b, src.get_bone_parent(b))
		gs.set_bone_rest(b, src.get_bone_rest(b))
	for b in nb:
		var pb := src.get_bone_parent(b)
		var gp := src.get_bone_global_pose(b)
		gs.set_bone_pose(b, gp if pb < 0 else src.get_bone_global_pose(pb).affine_inverse() * gp)
	gs.top_level = true
	add_child(gs)
	gs.global_transform = src.global_transform
	var inv := src.global_transform.affine_inverse()
	for mi: MeshInstance3D in actor.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null or mi.name == "AirTarget":
			continue
		var skinned := not mi.skeleton.is_empty() and mi.skin != null
		var m: Mesh = mi.mesh
		if skinned and mi.get_node_or_null(mi.skeleton) != src:
			m = mi.bake_mesh_from_current_skeleton_pose()   # 掛在別的骨架上的（目前沒有）：照舊烘焙
			skinned = false
		if m == null:
			continue
		var g := MeshInstance3D.new()
		g.mesh = m
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.material_override = mat
		gs.add_child(g)
		g.transform = inv * mi.global_transform
		if skinned:
			g.skin = mi.skin
			g.skeleton = NodePath("..")
	_ghosts.append({"node": gs, "mat": mat, "t": 0.0, "life": life, "a": alpha})
	if _r15_dir != "":   # 功能檢查：殘影骨架的每根骨頭（全域）與角色此刻的骨頭差多少（0＝殘影姿勢與角色完全相同）
		gs.force_update_all_bone_transforms()
		var e := 0.0
		for b in nb:
			e = maxf(e, (gs.get_bone_global_pose(b).origin - src.get_bone_global_pose(b).origin).length())
		print("GHOST_CHECK key=%s t=%.3f bones=%d meshes=%d max_err_m=%.6f" % [combat.shot_key, combat.shot_t, nb, gs.get_child_count(), e])

## 功能檢查：R15 的佇列（主測試＋牆＋蓄勢取消＋收招取消）；--full 有列的型才跑全部，其他只跑主測試；--only 點名的 R9／R10／R11 原版也跑主測試
func _ck_build_queue() -> void:
	super._ck_build_queue()
	var q: Array = _ck["queue"]
	if not _full.is_empty():
		q = q.filter(func(c: Dictionary) -> bool: return str(c["test"]) == "main" or _full.has(str(c["key"])))
	for key in skill_order:
		if ORIG.has(key) and (_only.has(key) or (not _legacy_list and _only.is_empty())):
			q.append({"key": key, "test": "main", "tix": 0})
			if not _legacy_list:   # 十二式：烈日紅鏡（R10 原版動作）也做牆與收招取消（父類對原版只做主測試）
				q.append({"key": key, "test": "wall", "tix": 0})
				if (skills[key]["shot"] as Dictionary).has("dodge_cancel"):
					q.append({"key": key, "test": "recover_cancel", "tix": 0})
	# R16b 第二輪：新火車／新陽華突也跑其他目標（火車：近 3.0 m＝前衝縮短、遠 9 m＝前方無障礙的全程位移；陽華突：空中目標）
	# 10-24：13 圓舞一閃（衍生技）也跑 4.5 m 木樁（瞬步自動縮短）
	for key in ["sun_kasha_r16b", "sun_youkatotsu_r16b", "sun_enbu_issen"]:
		if not skills.has(key) or not meta.has(key) or (not _only.is_empty() and not _only.has(key)):
			continue
		for ti in range(1, (meta[key]["targets"] as Array).size()):
			q.append({"key": key, "test": "main", "tix": ti})
	if _projectile_safety:
		meta["sun_kiki_onkou"]["targets"].append({"name":"飛射未命中測試", "pos":[0,0,20]})
		q.append({"key":"sun_kiki_onkou", "test":"main", "tix":2})
		q.append({"key":"sun_kiki_onkou", "test":"recover_cancel", "tix":2})
	_ck["queue"] = q

## R16c：技能設定 judge_substeps（只有炎舞 2 倍速 sun_enbu_double_r16c 有）＝這一招的刀身判定幀間插值段數；其他招式＝共用判定原樣（4 段）
func _shared_hit_test() -> Dictionary:
	judge.substeps = judge.SUBSTEPS
	if combat.state == combat.S.SHOT:
		judge.substeps = int(combat._cfg(combat.shot_key).get("judge_substeps", judge.SUBSTEPS))
	var r := super._shared_hit_test()
	judge.substeps = judge.SUBSTEPS
	return r

func _hud_text() -> String:
	var s := super._hud_text()
	s = s.replace("　火車火焰：%s（B）" % ("統一火環" if kasha_unified else "Blender KS12"), "")
	var e12 := {} if _legacy_list else SunRegistry.entry_by_skill(cur_skill)
	if not e12.is_empty():
		s = s.replace("【R15 日之呼吸候選試玩】" + str(skills[cur_skill]["name"]),
			"%s%s（%s）　%s" % ["【日之呼吸】" if SunRegistry.is_derived(e12) else "【日之呼吸十二式】", str(skills[cur_skill]["name"]),
			str(e12["name_ja"]), "X＝下一個　Z＝上一個"])
	s = s.replace("【R15 日之呼吸候選試玩】", "【R16 日之呼吸道場】" if MAIN_ORDER.has(cur_skill) else "【R16 日之呼吸道場｜舊版比較】")
	var nl := s.find("\n")
	var tag := "特效：%s（B 切換）" % ("新版" if fx_new else "舊版（回退）")
	return s.insert(nl, "　" + tag) if nl >= 0 else s + "\n" + tag
