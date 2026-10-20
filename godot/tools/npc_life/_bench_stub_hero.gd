extends Node3D
## jev_decision_bench 用的 HERO 替身：只提供 director 需要的介面（位置、可否社交、目前事件），不走路、不播動作。
@export var hero_id := ""
var _plan := {}
var _step := {}
var _session := {}
var _paused_for := ""
var busy := false
var cur_event := ""


func _ready() -> void:
	add_to_group("npc_life_hero")


func life_setup(_d: Node, _def: Dictionary, _sh: Dictionary, _delay: float) -> void:
	pass


func can_accept_social(_from: String) -> bool:
	return visible and not busy


func current_event() -> String:
	return cur_event


func life_state() -> String:
	return "bench"


func on_learn(_f: String) -> void:
	pass
