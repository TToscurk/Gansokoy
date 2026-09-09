extends CharacterBody3D
## 測試用假玩家：只提供狼的 AI 需要的介面（group player、action_state、take_hit）。
## ⚠ 裸 CharacterBody3D 用 set("action_state", 1) 不會建立屬性，
##   狼的閃避判定永遠讀到 null。要有腳本宣告過的變數才行。

## 對應 yoriichi_character.gd 的 ActionState { FREE, ATTACKING, DODGING }
var action_state: int = 0
var hits_taken: int = 0


func _ready() -> void:
	add_to_group("player")


func take_hit(_hit_data: Dictionary) -> Dictionary:
	hits_taken += 1
	return {"result": "hit"}


## 模擬揮刀：進入 ATTACKING 一小段時間再回 FREE
func swing() -> void:
	action_state = 0
	await get_tree().physics_frame
	action_state = 1
