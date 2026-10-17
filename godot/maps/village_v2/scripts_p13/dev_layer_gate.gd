@tool
extends Node
## 開發用疊層的開關（P13 W9 收尾）。
## 規劃名牌（Debug/Labels）、區域輪廓（Debug/DistrictOutlines）、任務錨點標桿（QuestAnchors）、地塊線（Districts 下全部 *ParcelLines*）、傳送規劃標記
## 只給工具看；正式遊玩（--map=village_v2、獸道 portal 進村、F5 --no-review）時在 _ready 隱藏。
## - 不刪節點、不改節點內容：工具照舊讀得到位置與 meta。
## - 要在遊戲中看：命令列 `-- --dev-layers`。
## - 編輯器（@tool，2026-10-17）：同樣隱藏上述疊層，另外把地形碰撞（Collision/TerrainCollision/Shape，2 m 三角網格
##   ConcavePolygonShape3D）在編輯器裡隱藏——它的 gizmo 線框會把整片地面畫成青色格線。碰撞本身不受影響（遊戲中不碰）。
##   存檔前（NOTIFICATION_EDITOR_PRE_SAVE）全部還原、存完（POST_SAVE）再隱藏 → village_v2.tscn 不會被寫進 visible=false。
##   要在編輯器裡看回來：把本節點的 editor_hide 設成 false。
## 掛載：tools/p13/w9/attach_dev_layer_gate.gd（village_v2.tscn root 最後一個子節點，晚於所有兄弟節點 _ready）。
const PATHS := ["Debug", "QuestAnchors", "Districts/LandmarkParcelLines", "Districts/AuxParcelLines", "Portals"]
const EDITOR_ONLY_PATHS := ["Collision/TerrainCollision/Shape"]

@export var editor_hide := true:
	set(v):
		editor_hide = v
		if Engine.is_editor_hint() and is_inside_tree():
			_restore()
			if v:
				_hide_all(true)

var _hidden: Array = []      # [Node3D, 元の visible]（編輯器用；存檔前還原）


## 要隱藏的節點：PATHS ＋ Districts 下所有 *ParcelLines*（各町的 ParcelLines 與 Landmark／Aux）
static func dev_nodes(root: Node) -> Array:
	var out: Array = []
	for p: String in PATHS:
		var n := root.get_node_or_null(p) as Node3D
		if n != null and not out.has(n):
			out.append(n)
	var d := root.get_node_or_null("Districts")
	if d != null:
		for n in d.find_children("*ParcelLines*", "", true, false):
			if n is Node3D and not out.has(n):
				out.append(n)
	return out


func _ready() -> void:
	if Engine.is_editor_hint():
		if editor_hide:
			_hide_all.call_deferred(true)
		return
	if "--dev-layers" in OS.get_cmdline_user_args():
		return
	for n: Node3D in dev_nodes(get_parent()):
		n.visible = false


func _hide_all(editor: bool) -> void:
	var root := get_parent()
	if root == null:
		return
	_restore()
	var targets := dev_nodes(root)
	if editor:
		for p: String in EDITOR_ONLY_PATHS:
			var n := root.get_node_or_null(p) as Node3D
			if n != null:
				targets.append(n)
	for n: Node3D in targets:
		_hidden.append([n, n.visible])
		n.visible = false


func _restore() -> void:
	for h in _hidden:
		if is_instance_valid(h[0]):
			(h[0] as Node3D).visible = h[1]
	_hidden.clear()


func _notification(what: int) -> void:
	# 編輯器存檔：存原狀態（只在編輯器發生；遊戲中不會收到）
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_restore()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		if Engine.is_editor_hint() and editor_hide:
			_hide_all(true)
