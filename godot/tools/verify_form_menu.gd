extends SceneTree
## 型選單 ＋ 呼吸槽 ＋ 型資源系統的無頭驗證。
##
## 執行：
##   godot --headless --path godot -s tools/verify_form_menu.gd
##
## 驗的是「線有沒有接上」，不是手感：
##   1. 呼吸槽真的會因命中／彈刀而漲（以前 add_breath 零呼叫者）
##   2. execute_form 會扣呼吸、起算冷卻，被擋下時不扣
##   3. form_block_reason 對每個型回報正確的原因
##   4. 選單列得出十二型，未修得的標得出來
##   5. 玩家軀幹爆掉會硬直、死亡會鎖輸入（以前完全沒接）

const SunBreathing = preload("res://characters/yoriichi/sun_breathing.gd")
const PostureComponent = preload("res://characters/combat/posture.gd")
const FormMenuScript = preload("res://ui/form_menu.gd")

var _pass := 0
var _fail := 0


func check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  [OK] ", label, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", label, ("  " + detail) if detail != "" else "")


func _initialize() -> void:
	print("=== 型選單 / 呼吸 / 型資源 驗證 ===")
	_test_form_table()
	_test_posture_wiring()
	_test_menu_rows()
	await process_frame
	await _test_player_runtime()
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


## 表本身：有幾型真的有動畫、mastery 0 開局能用幾型。
func _test_form_table() -> void:
	print("-- FORMS 表 --")
	var with_anim: Array[int] = []
	var no_anim: Array[int] = []
	for id in SunBreathing.FORMS:
		if String(SunBreathing.FORMS[id].anim) == "":
			no_anim.append(id)
		else:
			with_anim.append(id)
	with_anim.sort()
	no_anim.sort()
	check("十二型全在表裡", SunBreathing.FORMS.size() == 12,
		"實際 %d 型" % SunBreathing.FORMS.size())
	# ⚠ 捌ノ型 陽華突完成後：有動畫 8 型、缺 4 型（伍／陸／拾壹／拾貳）。
	#   這個數字會隨動畫補齊而變 —— 改的時候連同這裡一起更新。
	check("有動畫的型 = 8", with_anim.size() == 8, str(with_anim))
	check("缺動畫的型 = 4", no_anim.size() == 4, str(no_anim))

	# 開局（mastery 0）能用的型 —— 序章第一場戰鬥玩家看到的選項數
	var mastery0: Array[int] = []
	for id in with_anim:
		if int(SunBreathing.FORMS[id].required_mastery) == 0:
			mastery0.append(id)
	mastery0.sort()
	var names := ""
	for id in mastery0:
		names += String(SunBreathing.FORMS[id].name) + " "
	check("mastery 0 開局可用 3 型", mastery0.size() == 3, names.strip_edges())


## posture.gd 的雙軌語意沒被我改壞。
func _test_posture_wiring() -> void:
	print("-- Posture --")
	var p: Node = PostureComponent.new()
	p.max_health = 100.0
	p.max_posture = 100.0
	p.break_time = 2.0
	get_root().add_child(p)
	p._ready()

	p.apply_damage(0.0, 100.0)
	check("軀幹滿即破綻", p.is_broken())
	check("破綻中沒死", not p.is_dead())
	check("破綻中可忍殺", p.deathblow())
	check("忍殺後死亡", p.is_dead())

	var q: Node = PostureComponent.new()
	q.max_health = 100.0
	get_root().add_child(q)
	q._ready()
	# 殘血懲罰：血越少軀幹回復越慢，這是系統的手感支柱
	var full: float = q.regen_scale()
	q.apply_damage(90.0, 0.0)
	var hurt: float = q.regen_scale()
	check("殘血時軀幹回復更慢", hurt < full,
		"滿血 %.2f → 殘血 %.2f" % [full, hurt])
	p.queue_free()
	q.queue_free()


## 選單能不能把十二型排出來，狀態字對不對。
func _test_menu_rows() -> void:
	print("-- 選單列 --")
	var order: Array = FormMenuScript.FORM_ORDER
	check("選單順序含十二型", order.size() == 12, str(order))
	var ordered := true
	for i in order.size():
		if int(order[i]) != i + 1:
			ordered = false
	check("順序是壹→拾貳", ordered)


## 真的生一個玩家，跑完整條線。
func _test_player_runtime() -> void:
	print("-- 玩家執行期 --")
	var scene: PackedScene = load("res://characters/yoriichi/player_yoriichi.tscn")
	if scene == null:
		check("載入 player_yoriichi.tscn", false)
		return
	var player: Node = scene.instantiate()
	get_root().add_child(player)
	await process_frame
	await process_frame

	check("玩家有 posture", player.posture != null)
	check("開局呼吸槽為 0", is_equal_approx(player.sun_breath_gauge, 0.0),
		"實際 %.1f" % player.sun_breath_gauge)

	# --- 呼吸累積 ---
	player.add_breath(player.breath_gain_on_hit)
	check("命中累積呼吸", player.sun_breath_gauge > 0.0,
		"%.1f" % player.sun_breath_gauge)
	var before_deflect: float = player.sun_breath_gauge
	player.add_breath(player.breath_gain_on_deflect)
	check("彈刀給的呼吸比命中多",
		player.breath_gain_on_deflect > player.breath_gain_on_hit,
		"彈刀 %.0f vs 命中 %.0f" % [player.breath_gain_on_deflect, player.breath_gain_on_hit])
	check("呼吸有上限", player.sun_breath_gauge >= before_deflect)
	player.add_breath(9999.0)
	check("呼吸不超過上限",
		is_equal_approx(player.sun_breath_gauge, player.sun_breath_max),
		"%.1f / %.1f" % [player.sun_breath_gauge, player.sun_breath_max])

	# --- 阻擋原因 ---
	player.sun_mastery = 0
	player.sun_breath_gauge = player.sun_breath_max
	check("壹ノ型 mastery 0 可用（收刀狀態除外）",
		player.form_block_reason(1) == "", player.form_block_reason(1))
	check("貳ノ型 mastery 0 = 未修得",
		player.form_block_reason(2) == "mastery", player.form_block_reason(2))
	player.sun_mastery = 4   # 拉滿熟練度才驗得到「缺動畫」——否則先被 mastery 擋掉
	check("伍ノ型 = 缺動畫",
		player.form_block_reason(5) == "no_anim", player.form_block_reason(5))
	player.sun_mastery = 0
	player.sun_breath_gauge = 0.0
	check("呼吸歸零 → 壹ノ型 breath 不足",
		player.form_block_reason(1) == "breath", player.form_block_reason(1))

	# --- 發型扣呼吸 + 冷卻 ---
	player.sun_mastery = 4
	player.sun_breath_gauge = player.sun_breath_max
	player.sword_state = 2   # SwordState.DRAWN
	player.action_state = 0  # ActionState.FREE
	# ⚠ 無頭測試沒有地板，is_on_floor() 永遠 false。柒ノ型 allowed_airborne =
	#   false，所以這裡被「需著地」正當擋下 —— 先驗這條規則真的有效。
	check("空中發不出著地限定的型",
		player.form_block_reason(7) == "airborne", player.form_block_reason(7))
	# 改用 allowed_airborne = true 的型（壹ノ型，cost 10）驗扣費與冷卻。
	var gauge_before: float = player.sun_breath_gauge
	var fired: bool = player.execute_form(1)
	check("壹ノ型 發動成功", fired)
	if fired:
		var cost: float = float(SunBreathing.FORMS[1].breath_cost)
		check("發型扣掉呼吸",
			is_equal_approx(player.sun_breath_gauge, gauge_before - cost),
			"%.1f → %.1f（應扣 %.0f）" % [gauge_before, player.sun_breath_gauge, cost])
		# 壹ノ型 cooldown = 0（輕型不設冷卻），冷卻機制改用貳ノ型驗。
		check("無冷卻的型不留冷卻", is_equal_approx(player.form_cooldown_left(1), 0.0),
			"%.2f s" % player.form_cooldown_left(1))
		player.action_state = 0
		player.sun_breath_gauge = player.sun_breath_max
		player._form_cooldowns[2] = float(SunBreathing.FORMS[2].cooldown)
		check("冷卻中該型不可用",
			player.form_block_reason(2) == "cooldown", player.form_block_reason(2))

	# 被擋下的輸入不得扣呼吸
	player.action_state = 1   # ATTACKING（已在出招中）
	var g2: float = player.sun_breath_gauge
	var refused: bool = player.execute_form(2)
	check("出招中發型被擋下", not refused)
	check("被擋下不扣呼吸", is_equal_approx(player.sun_breath_gauge, g2),
		"%.1f → %.1f" % [g2, player.sun_breath_gauge])

	# --- 玩家軀幹爆掉 / 死亡（以前完全沒接） ---
	player.action_state = 0
	player.input_locked = false
	# ⚠ GDScript 的 lambda 捕捉區域變數是 **傳值**：寫 `var hit := false` 再在
	#   lambda 裡 `hit = true`，外面永遠看不到。用 Array（傳參考）才收得到。
	var seen := []
	player.player_posture_broken.connect(func() -> void: seen.append("broken"))
	player.player_died.connect(func() -> void: seen.append("died"))
	player.posture.apply_damage(0.0, player.posture.max_posture)
	check("玩家軀幹爆掉會發訊號", "broken" in seen, str(seen))
	player.posture.apply_damage(9999.0, 0.0)
	check("玩家死亡會發訊號", "died" in seen, str(seen))
	check("死亡後鎖住輸入", player.input_locked)

	player.queue_free()
