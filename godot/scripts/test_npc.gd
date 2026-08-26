extends Node3D

@export var prompt := "E：交談"
@export var response := "村人：歡迎來到人間之里。"


func get_interaction_prompt() -> String:
	return prompt


func interact() -> String:
	return response
