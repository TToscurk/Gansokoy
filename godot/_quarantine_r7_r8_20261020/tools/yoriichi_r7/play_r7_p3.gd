extends SceneTree
## Isolated playable R7 P3 arena: reuses the existing arena and its HUD, swaps ONLY the runtime Player instance.
## godot --path godot -s res://tools/yoriichi_r7/play_r7_p3.gd
const ARENA := preload("res://scenes/combat_arena.tscn")
const CANDIDATE := preload("res://characters/yoriichi/player_yoriichi_r7k.tscn")

class ReviewKeys extends Node:
	var player: CharacterBody3D
	var label: Label

	func _unhandled_input(event: InputEvent) -> void:
		if not event is InputEventKey or not event.pressed or event.echo:
			return
		var forms := {KEY_F5: 10, KEY_F6: 4, KEY_F7: 5, KEY_F8: 7}
		if forms.has(event.keycode):
			var id: int = forms[event.keycode]
			var accepted: bool = player.execute_form(id, false)
			print("P3_PLAY_INPUT id=", id, " accepted=", accepted, " floor=", player.is_on_floor())
			get_viewport().set_input_as_handled()

	func _process(_delta: float) -> void:
		label.text = "R7 P3｜ART_REVIEW｜候選試玩，不影響正式主遊戲\nF5 火車／F6 灼骨炎陽／F7 斜陽轉身／F8 輝輝恩光（地面或空中）\nSpace 起跳；空中滑鼠左鍵＝火車、右鍵＝灼骨炎陽；原有移動／格擋／閃避沿用\n著地：%s｜型：%s｜階段：%s" % [str(player.is_on_floor()), str(player.active_form), str(player.get("r7_air_phase"))]

func _initialize() -> void:
	_boot.call_deferred()

func _boot() -> void:
	var arena := ARENA.instantiate()
	var original := arena.get_node("Player") as Node3D
	var spawn := original.transform
	arena.remove_child(original)
	original.free()
	var player := CANDIDATE.instantiate() as CharacterBody3D
	player.name = "Player"
	player.transform = spawn
	player.set("sun_mastery", 3)  # Candidate test instance only; no save-data or production defaults are changed.
	player.set("form13_key_enabled", false)  # Twelve-form sequencing is outside this batch.
	player.set("r7_vfx_enabled", false)
	arena.add_child(player)
	root.add_child(arena)
	var layer := CanvasLayer.new()
	layer.layer = 100
	var label := Label.new()
	label.position = Vector2(18, 16)
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(label)
	root.add_child(layer)
	var keys := ReviewKeys.new()
	keys.player = player
	keys.label = label
	root.add_child(keys)
	await process_frame
	player.request_draw()
	print("P3_PLAY_READY candidate=player_yoriichi_r7k production_scene_unchanged=true")
