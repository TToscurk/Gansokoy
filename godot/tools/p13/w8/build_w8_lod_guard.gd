extends SceneTree
## P13 Wave 8 LodGuardP13 builder：gen/lod_guard_p13.scn を書く。
##   godot --headless --path . --script res://tools/p13/w8/build_w8_lod_guard.gd
const SCRIPT := "res://maps/village_v2/scripts_p13/lod_guard.gd"
const OUT_SCENE := "res://maps/village_v2/gen/lod_guard_p13.scn"
const JUMP_THRESHOLD := 6.0
const TURN_THRESHOLD_DEG := 35.0
const ACCUM_TURN_DEG := 45.0
const MINIMUM_INTERVAL := 1.0


func _init() -> void:
	var node := Node3D.new()
	node.name = "LodGuardP13"
	node.set_script(load(SCRIPT))
	node.set("jump_threshold", JUMP_THRESHOLD)
	node.set("turn_threshold_deg", TURN_THRESHOLD_DEG)
	node.set("accum_turn_deg", ACCUM_TURN_DEG)
	node.set("minimum_interval", MINIMUM_INTERVAL)
	var ps := PackedScene.new()
	ps.pack(node)
	var err := ResourceSaver.save(ps, OUT_SCENE)
	print("[W8A] saved ", OUT_SCENE, " err=", err, " jump_threshold=", JUMP_THRESHOLD, " turn=", TURN_THRESHOLD_DEG, " accum=", ACCUM_TURN_DEG, " interval=", MINIMUM_INTERVAL)
	quit(0)
