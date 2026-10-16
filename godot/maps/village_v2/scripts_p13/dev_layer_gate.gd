extends Node
## 開發用疊層的執行期開關（P13 W9 收尾）。
## 規劃名牌（Debug/Labels）、區域輪廓（Debug/DistrictOutlines）、任務錨點標桿（QuestAnchors）、地塊線、傳送規劃標記
## 只給編輯器與工具看；正式遊玩（--map=village_v2、獸道 portal 進村、F5 --no-review）時在 _ready 隱藏。
## - 不刪節點、不改節點內容：編輯器（此腳本不是 @tool，不在編輯器執行）照舊看得到，工具照舊讀得到位置與 meta。
## - 要在遊戲中看：命令列 `-- --dev-layers`。
## 掛載：tools/p13/w9/attach_dev_layer_gate.gd（village_v2.tscn root 最後一個子節點，晚於所有兄弟節點 _ready）。
const PATHS := ["Debug", "QuestAnchors", "Districts/LandmarkParcelLines", "Districts/AuxParcelLines", "Portals"]


func _ready() -> void:
	if Engine.is_editor_hint() or "--dev-layers" in OS.get_cmdline_user_args():
		return
	var root := get_parent()
	for p: String in PATHS:
		var n := root.get_node_or_null(p) as Node3D
		if n != null:
			n.visible = false
