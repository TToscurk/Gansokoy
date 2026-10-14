extends SceneTree
## P13 Wave 7 EarthBankToneP13 builder：gen/earth_bank_tone_p13.scn を書く。
##   godot --headless --path . --script res://tools/p13/w7/build_w7_earthbank.gd
## 値はここが唯一の正（Gate は独立に抄写して比較する）。
const SCRIPT := "res://maps/village_v2/scripts_p13/earth_bank_tone.gd"
const OUT_SCENE := "res://maps/village_v2/gen/earth_bank_tone_p13.scn"
const GROUND_K := 0.21


func _init() -> void:
	var node := Node3D.new()
	node.name = "EarthBankToneP13"
	node.set_script(load(SCRIPT))
	node.set("bank_path", "Districts/FarmlandEast/FarmlandP8/EarthBanks")
	node.set("ground_k", GROUND_K)
	var ps := PackedScene.new()
	ps.pack(node)
	var err := ResourceSaver.save(ps, OUT_SCENE)
	print("[W7B] saved ", OUT_SCENE, " err=", err, " ground_k=", GROUND_K)
	quit(0)
