extends "res://characters/yoriichi/yoriichi_character_r7.gd"
## R8 候選角色控制器（2026-10-20 使用者裁定 A）：R8 戰鬥動畫全面重製期間，候選角色只保留
##   拔刀／收刀（R7K draw／sheathe）、待機、移動、跳躍、閃避、格擋、鎖定。
## 所有攻擊入口在這裡擋掉：普攻、重斬／蓄力、型（含空中型）、十三型、特殊攻擊、忍殺。
## 不改 R7 控制器、不刪任何舊動畫檔；舊資源仍被 R7／正式場景引用，原地保留。
## 新的 R8 攻擊動畫做好並經使用者核准後，再逐一在此接回。

func request_primary_attack() -> void:
	pass

func request_heavy_cut() -> void:
	pass

func begin_heavy_charge() -> bool:
	return true          # 回 true＝「已處理」，父類輸入就不會改走 request_heavy_cut

func request_continuous_spin() -> void:
	pass

func request_special_attack(_animation_name: String) -> void:
	pass

func execute_form(_id: int, _free := false) -> bool:
	return false

func start_form13() -> bool:
	return false

func try_deathblow() -> bool:
	return false

func _unhandled_input(event):
	# R7 的空中出招攔截在這裡就不會觸發（execute_form 已回 false），其餘交給父類（拔刀、跳、閃避、格擋、鎖定）。
	if event.is_action_pressed("attack_light") or event.is_action_pressed("attack_heavy") \
			or event.is_action_released("attack_heavy") or event.is_action_pressed("attack_special") \
			or event.is_action_pressed("form13") or event.is_action_pressed("deathblow"):
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)
