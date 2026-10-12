extends SceneTree
## P13 W2（只讀）：village_v2.tscn を GEN_EDIT_STATE_MAIN で instantiate → pack → 一時ファイルへ保存（無変更）。
## 元ファイルとのテキスト差分量で、Godot 再保存の忠実度を確認する。
##   godot --headless --path . --script res://tools/p13/resave_probe.gd -- <out.tscn>
func _init() -> void:
	var ps := load("res://maps/village_v2/village_v2.tscn") as PackedScene
	var root := ps.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	var p2 := PackedScene.new()
	var e := p2.pack(root)
	var e2 := ResourceSaver.save(p2, OS.get_cmdline_user_args()[0])
	print("[RESAVE] pack %d save %d" % [e, e2])
	root.free()
	quit(0)
