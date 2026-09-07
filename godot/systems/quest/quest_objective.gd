extends Resource
class_name QuestObjective
## 任務目標定義（純資料，不含進度）。進度由 QuestManager 保存。

enum Type { REACH, INTERACT, TALK, DEFEAT }

@export var type: Type = Type.REACH
@export var target_id: String = ""
@export var description: String = ""
@export var required_amount: int = 1
