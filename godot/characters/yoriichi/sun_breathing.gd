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
##   impulse         起手時沿面朝方向的 CharacterBody3D 前衝（m/s，程式位移，非 root motion；負值 = 後撤）
##   allowed_airborne 可否空中發動
##   required_mastery 解鎖所需熟練度
##   vfx             VFX id："ignite" = 起手日之呼吸火光（CombatVFX.spawn_form_ignite）；"" = 無
##   cancel          可取消窗口（段落進度比例）
##   next            十三型循環中的下一型

const FORMS := {
	1: {status = "READY", name = "壹ノ型 圓舞", anim = "Attack_Combo", section = Vector2(0.0, 0.34), layer = "upper",
		speed = 2.0, damage = 1.0, breath_cost = 10.0, cooldown = 0.0, impulse = 1.5,
		allowed_airborne = true, required_mastery = 0, vfx = "", cancel = Vector2(0.35, 0.65), next = 2},
	2: {status = "READY", name = "貳ノ型 碧羅天", anim = "Attack_Spin", section = Vector2(0.0, 1.0), layer = "full",
		speed = 1.7, damage = 1.3, breath_cost = 18.0, cooldown = 1.0, impulse = 0.0,
		allowed_airborne = false, required_mastery = 1, vfx = "", cancel = Vector2(0.6, 0.9), next = 3},
	3: {status = "READY", name = "參ノ型 烈日紅鏡", anim = "Attack_Combo", section = Vector2(0.30, 0.67), layer = "upper",
		speed = 2.0, damage = 1.1, breath_cost = 12.0, cooldown = 0.0, impulse = 0.5,
		allowed_airborne = true, required_mastery = 0, vfx = "", cancel = Vector2(0.35, 0.65), next = 4},
	4: {status = "READY", name = "肆ノ型 灼骨炎陽", anim = "Attack_Combo_1", section = Vector2(0.0, 1.0), layer = "full",
		speed = 2.2, damage = 1.2, breath_cost = 15.0, cooldown = 0.5, impulse = 1.0,
		allowed_airborne = false, required_mastery = 1, vfx = "", cancel = Vector2(0.5, 0.8), next = 5,
		note = "第二輪風格減法：已下線連段自動收尾；保留 execute_form 通道"},
	5: {status = "READY", name = "伍ノ型 斜陽轉身", anim = "Attack_Form05_Turn", section = Vector2(0.0, 1.0), layer = "full",
		speed = 1.7, damage = 1.2, breath_cost = 14.0, cooldown = 1.0, impulse = 1.0,
		allowed_airborne = false, required_mastery = 2, vfx = "ignite", cancel = Vector2(0.62, 0.95), next = 6,
		note = "自製動畫（tools/blender/make_form_clips.py，14 幀）：腰擰→由右下往左上撩斬。連段分支：LMB 二段中按 RMB；dodge counter（翻滾中 LMB）仍走 Combo 段1"},
	6: {status = "READY", name = "陸ノ型 飛輪陽炎", anim = "Attack_Form06_Wheel", section = Vector2(0.0, 1.0), layer = "full",
		speed = 1.8, damage = 1.4, breath_cost = 16.0, cooldown = 2.0, impulse = 5.0,
		allowed_airborne = false, required_mastery = 2, vfx = "ignite", cancel = Vector2(0.60, 0.95), next = 7,
		note = "自製動畫（16 幀）：前弓步水平橫斬，起手前衝 5 m/s。連段分支：LMB 一段中按 RMB。quick-draw（SHEATHED+LMB）仍走 Combo 段1"},
	7: {status = "READY", name = "柒ノ型 輝輝恩光", anim = "Attack_Judgment", section = Vector2(0.0, 1.0), layer = "full",
		speed = 2.4, damage = 1.8, breath_cost = 25.0, cooldown = 3.0, impulse = 0.5,
		allowed_airborne = false, required_mastery = 2, vfx = "", cancel = Vector2(0.7, 0.95), next = 8,
		note = "第二輪風格減法：已從預設 RMB 下線（過大幅度的縱劈）；保留 execute_form 通道"},
	8: {status = "READY", name = "捌ノ型 陽華突", anim = "Attack_Thrust", section = Vector2(0.0, 1.0), layer = "full",
		speed = 1.6, damage = 1.5, breath_cost = 18.0, cooldown = 2.0, impulse = 6.0,
		allowed_airborne = false, required_mastery = 3, vfx = "", cancel = Vector2(0.55, 0.85), next = 9,
		note = "直線突刺：自製動畫（tools/blender/make_form08_thrust.py，30 幀 @24fps）。蓄 f0-7 / 突 f8-12 / 留 f13-17 / 收 f18-30；突刺段爆發 4.6x 於收招段"},
	9: {status = "READY", name = "玖ノ型 日暈龍・頭舞", anim = "Attack_Continuous_Spin", section = Vector2(0.0, 1.0), layer = "full",
		speed = 1.8, damage = 1.6, breath_cost = 22.0, cooldown = 3.0, impulse = 2.0,
		allowed_airborne = false, required_mastery = 0, vfx = "", cancel = Vector2(0.7, 0.95), next = 10,
		note = "連續旋轉砍擊（Meshy AI 衍生）：高速迴旋連段"},
	10: {status = "READY", name = "拾ノ型 火車", anim = "Attack_Spin_Jump", section = Vector2(0.0, 1.0), layer = "full",
		speed = 2.0, damage = 1.6, breath_cost = 24.0, cooldown = 3.0, impulse = 2.0,
		allowed_airborne = true, required_mastery = 3, vfx = "", cancel = Vector2(0.7, 0.95), next = 11,
		note = "第二輪風格減法：已從預設空中 RMB 下線（旋轉幅度過大）；保留 execute_form 通道"},
	11: {status = "READY", name = "拾壹ノ型 幻日虹", anim = "Attack_Form11_Halo", section = Vector2(0.0, 1.0), layer = "full",
		speed = 1.8, damage = 1.3, breath_cost = 20.0, cooldown = 4.0, impulse = -1.5,
		allowed_airborne = false, required_mastery = 4, vfx = "ignite", cancel = Vector2(0.65, 0.95), next = 12,
		note = "自製動畫（16 幀）：上身後仰閃身（起手後撤 1.5 m/s）→ 斜下反斬。連段分支：RMB 聚力單斬中按 LMB。殘影 VFX 尚未做"},
	12: {status = "READY", name = "拾貳ノ型 炎舞", anim = "Attack_Form12_Dance", section = Vector2(0.0, 1.0), layer = "full",
		speed = 1.9, damage = 1.5, breath_cost = 20.0, cooldown = 2.5, impulse = 2.0,
		allowed_airborne = false, required_mastery = 4, vfx = "ignite", cancel = Vector2(0.72, 0.95), next = 1, rehit = 0.55,
		note = "自製動畫（22 幀）：高舉直劈 → 低位撩起兩段一氣（rehit 0.55 = 第二刀重新判定命中）。連段分支：LMB 三段中按 RMB（連段終結）"},
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
