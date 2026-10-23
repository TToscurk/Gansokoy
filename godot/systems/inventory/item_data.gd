class_name ItemData
extends Resource
## 背包中的靜態道具定義。執行期數量由 InventoryManager 持有。

enum Category { QUEST, KEY, MATERIAL, CONSUMABLE }

@export var item_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.QUEST
@export_range(1, 999, 1) var max_stack: int = 1
@export var icon: Texture2D


func is_valid() -> bool:
	return not item_id.strip_edges().is_empty() \
		and not display_name.strip_edges().is_empty() \
		and max_stack > 0
