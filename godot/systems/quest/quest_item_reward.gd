class_name QuestItemReward
extends Resource
## 任務完成時交給玩家的道具。

@export var item_id: String = ""
@export_range(1, 999, 1) var amount: int = 1


func is_valid() -> bool:
	return not item_id.strip_edges().is_empty() and amount > 0
