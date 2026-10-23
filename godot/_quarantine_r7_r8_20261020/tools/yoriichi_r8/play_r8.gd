extends SceneTree
## R8 候選試玩：沿用既有 combat_arena，只在執行期換上 R8 候選角色（只有拔刀／收刀與移動）。不寫任何場景／資源／存檔。
##   godot --path godot -s res://tools/yoriichi_r8/play_r8.gd
const ARENA := preload("res://scenes/combat_arena.tscn")
const CANDIDATE := preload("res://characters/yoriichi/player_yoriichi_r8.tscn")

class Hud extends Node:
	var player: CharacterBody3D
	var label: Label
	func _process(_d: float) -> void:
		var st := ["收刀", "拔刀中", "持刀", "收刀中"]
		label.text = ("R8 候選試玩｜ART_REVIEW｜不影響正式主遊戲\n"
			+ "目前只有：Q 拔刀／收刀、WASD 移動、Shift 長按衝刺／短按閃避、Space 跳、F 防禦\n"
			+ "所有攻擊已停用（等 R8 新動畫核准後再接回）\n刀：%s｜著地：%s") % [
			st[clampi(int(player.get("sword_state")), 0, 3)], "是" if player.is_on_floor() else "否"]

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
	player.set("r7_vfx_enabled", false)
	arena.add_child(player)
	root.add_child(arena)
	var layer := CanvasLayer.new()
	layer.layer = 100
	var label := Label.new()
	label.position = Vector2(18, 16)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(label)
	root.add_child(layer)
	var hud := Hud.new()
	hud.player = player
	hud.label = label
	root.add_child(hud)
	print("R8_PLAY_READY")
