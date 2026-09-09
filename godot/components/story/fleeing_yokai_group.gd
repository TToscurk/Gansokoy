extends Node3D
class_name FleeingYokaiGroup
## MQ03 不要追 —— 2～3 隻毛玉躲在路邊，玩家一靠近就逃進樹叢。
## 全部逃光後在原地留下一顆果實（不是武器），觸發獨白。
##
## 不認識任務；果實本身是 WorldInteraction，由它回報。

@export var kedama_scene: PackedScene
@export var count := 3
## 毛玉散佈半徑
@export var spread := 2.5
## 全部逃離的方向（往路旁樹叢）
@export var flee_dir := Vector3(1.0, 0.0, -0.3)
## 逃光後生出的果實場景（留空就不生）
@export var drop_scene: PackedScene
## 逃光後才啟用的互動區（果實的獨白）。指向同層的 WorldInteraction 節點名
@export var reveal_interaction := ""

var _alive := 0
var _done := false


func _ready() -> void:
	if kedama_scene == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260908
	for i in count:
		var k: Node3D = kedama_scene.instantiate()
		add_child(k)
		var a := TAU * float(i) / float(count) + rng.randf_range(-0.4, 0.4)
		k.position = Vector3(cos(a) * spread, 0.0, sin(a) * spread)
		k.set("mode", 1)   # FLEE
		k.set("flee_dir", (flee_dir + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))).normalized())
		k.set("notice_range", 7.0 + float(i) * 0.8)   # 一隻先跑、其他跟著跑
		if k.has_signal("fled"):
			k.fled.connect(_on_one_fled)
		_alive += 1
	# 果實與獨白區先關著
	var wi := get_node_or_null(reveal_interaction)
	if wi != null:
		wi.set("enabled", false)


func _on_one_fled() -> void:
	_alive -= 1
	if _alive > 0 or _done:
		return
	_done = true
	if drop_scene != null:
		var d: Node3D = drop_scene.instantiate()
		add_child(d)
		d.position = Vector3(0, 0.05, 0)
	var wi := get_node_or_null(reveal_interaction)
	if wi != null:
		wi.set("enabled", true)
