extends Resource
class_name QuestData
## 任務定義（純資料）。共享 Resource，**不得**在裡面寫進度。

@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export var objectives: Array[QuestObjective] = []
@export var next_quest_id: String = ""
## 完成時設的劇情旗標（可空）
@export var complete_flags: PackedStringArray = []
