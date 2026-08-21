## 日之呼吸十二型＋十三型的 data-driven 定義。純資料，不含播放邏輯；
## 使用端以 preload 引入（const SunBreathing = preload("res://sun_breathing.gd")）。
## 執行由 yoriichi_character.gd 的 execute_form() 讀表驅動。
##
## 欄位：
##   anim            AnimationPlayer 內的動畫名；"" = 尚無專用動畫（slot 保留）
##   section         Vector2(起,迄) 佔 clip 長度比例；ZERO~ONE = 整段
##   layer           "upper"（可邊跑邊斬）或 "full"（全身接管）
##   speed           播放倍率
##   damage          傷害倍率（傷害系統接上前先保留）
##   breath_cost     呼吸量消耗
##   cooldown        秒
##   impulse         起手時沿面朝方向的 CharacterBody3D 前衝（m/s，程式位移，非 root motion）
##   allowed_airborne 可否空中發動
##   required_mastery 解鎖所需熟練度
##   vfx             VFX id（VFX 系統接上前先保留）
##   cancel          可取消窗口（段落進度比例）
##   next            十三型循環中的下一型

const FORMS := {
	1: {status = "READY", name = "壹ノ型 圓舞", anim = "Attack_Combo", section = Vector2(0.0, 0.34), layer = "upper",
		speed = 2.0, damage = 1.0, breath_cost = 10.0, cooldown = 0.0, impulse = 1.5,
		allowed_airborne = true, required_mastery = 0, vfx = "", cancel = Vector2(0.35, 0.65), next = 2},
	2: {status = "READY", name = "貳ノ型 碧羅天", anim = "Attack_Spin", section = Vector2(0.0, 1.0), layer = "full",
		speed = 2.0, damage = 1.3, breath_cost = 18.0, cooldown = 1.0, impulse = 0.0,
		allowed_airborne = false, required_mastery = 1, vfx = "", cancel = Vector2(0.6, 0.9), next = 3},
	3: {status = "READY", name = "參ノ型 烈日紅鏡", anim = "Attack_Combo", section = Vector2(0.30, 0.67), layer = "upper",
		speed = 2.0, damage = 1.1, breath_cost = 12.0, cooldown = 0.0, impulse = 0.5,
		allowed_airborne = true, required_mastery = 0, vfx = "", cancel = Vector2(0.35, 0.65), next = 4},
	4: {status = "READY", name = "肆ノ型 灼骨炎陽", anim = "Attack_Combo_1", section = Vector2(0.0, 1.0), layer = "full",
		speed = 2.0, damage = 1.2, breath_cost = 15.0, cooldown = 0.5, impulse = 1.0,
		allowed_airborne = false, required_mastery = 1, vfx = "", cancel = Vector2(0.5, 0.8), next = 5},
	5: {status = "PARTIAL", name = "伍ノ型 斜陽轉身", anim = "", section = Vector2.ZERO, layer = "full",
		speed = 2.0, damage = 1.2, breath_cost = 14.0, cooldown = 1.0, impulse = 0.0,
		allowed_airborne = false, required_mastery = 2, vfx = "", cancel = Vector2.ZERO, next = 6,
		note = "dodge counter 已實裝：DRAWN 翻滾中按 LMB → roll 結束沿翻滾方向前衝 2 m/s 接 Combo 第一段；專用 counter 動畫仍可之後補"},
	6: {status = "PARTIAL", name = "陸ノ型 飛輪陽炎", anim = "", section = Vector2.ZERO, layer = "full",
		speed = 2.0, damage = 1.4, breath_cost = 16.0, cooldown = 2.0, impulse = 5.0,
		allowed_airborne = false, required_mastery = 2, vfx = "", cancel = Vector2.ZERO, next = 7,
		note = "quick-draw 已實裝：SHEATHED+LMB 拔刀，刀離鞘（0.65）瞬間取消剩餘 draw 接第一段；大位移 dash 版仍缺專用動畫"},
	7: {status = "READY", name = "柒ノ型 輝輝恩光", anim = "Attack_Judgment", section = Vector2(0.0, 1.0), layer = "full",
		speed = 2.0, damage = 1.8, breath_cost = 25.0, cooldown = 3.0, impulse = 0.5,
		allowed_airborne = false, required_mastery = 2, vfx = "", cancel = Vector2(0.7, 0.95), next = 8},
	8: {status = "MISSING", name = "捌ノ型 陽華突", anim = "", section = Vector2.ZERO, layer = "full",
		speed = 2.0, damage = 1.5, breath_cost = 18.0, cooldown = 2.0, impulse = 6.0,
		allowed_airborne = false, required_mastery = 3, vfx = "", cancel = Vector2.ZERO, next = 9,
		note = "直線突刺：現有 clip 無合適突刺段，slot 保留"},
	9: {status = "MISSING", name = "玖ノ型 日暈龍・頭舞", anim = "", section = Vector2.ZERO, layer = "full",
		speed = 2.0, damage = 1.6, breath_cost = 22.0, cooldown = 3.0, impulse = 3.0,
		allowed_airborne = false, required_mastery = 3, vfx = "", cancel = Vector2.ZERO, next = 10,
		note = "Combo + directional chained dash；需 dash-chain 系統，slot 保留"},
	10: {status = "READY", name = "拾ノ型 火車", anim = "Attack_Spin_Jump", section = Vector2(0.0, 1.0), layer = "full",
		speed = 2.0, damage = 1.6, breath_cost = 24.0, cooldown = 3.0, impulse = 2.0,
		allowed_airborne = true, required_mastery = 3, vfx = "", cancel = Vector2(0.7, 0.95), next = 11},
	11: {status = "MISSING", name = "拾壹ノ型 幻日虹", anim = "", section = Vector2.ZERO, layer = "full",
		speed = 2.0, damage = 0.0, breath_cost = 20.0, cooldown = 4.0, impulse = 0.0,
		allowed_airborne = false, required_mastery = 4, vfx = "", cancel = Vector2.ZERO, next = 12,
		note = "閃身／殘影反擊：需 afterimage VFX 與 counter 判定，slot 保留"},
	12: {status = "PARTIAL", name = "拾貳ノ型 炎舞", anim = "", section = Vector2.ZERO, layer = "full",
		speed = 2.0, damage = 1.5, breath_cost = 20.0, cooldown = 2.5, impulse = 2.0,
		allowed_airborne = false, required_mastery = 4, vfx = "", cancel = Vector2.ZERO, next = 1,
		note = "quick-draw → 段1 → buffer 段2 已可操作（炎舞雛形）；專用二段斬動畫仍缺"},
}

## 拾參ノ型：不是獨立單招，而是把可用的前十二型按此順序高速循環。
## 缺動畫的型（anim == ""）在 sequencer 中誠實跳過，不播假內容。
const FORM13_SEQUENCE: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]

static func available_forms() -> Array[int]:
	var out: Array[int] = []
	for id in FORMS:
		if FORMS[id].anim != "":
			out.append(id)
	return out

static func missing_forms() -> Array[int]:
	var out: Array[int] = []
	for id in FORMS:
		if FORMS[id].anim == "":
			out.append(id)
	return out
