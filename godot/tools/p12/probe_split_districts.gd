extends SceneTree
## P12 Wave 1 實驗（只寫 scratch，不寫專案場景）：Districts サブツリーを binary .scn に切り出し、
## 本体 .tscn はそれを instance する形にした場合の load 時間を測るための試作ファイルを作る。
##   godot --headless --path . --script res://tools/p12/probe_split_districts.gd -- --out=<abs dir>/ [--sub=Districts]
const SCENE := "res://maps/village_v2/village_v2.tscn"

func _init() -> void:
	_run.call_deferred()

func _own(n: Node, o: Node) -> void:
	for c in n.get_children():
		c.owner = o
		_own(c, o)

func _run() -> void:
	var out := ""
	var sub := "Districts"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--sub="):
			sub = a.trim_prefix("--sub=")
	var ps := load(SCENE) as PackedScene
	var v := ps.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var d := v.get_node(sub)
	var idx := d.get_index()
	v.remove_child(d)
	# 子シーン（Districts 以下の instance 子＝FarmlandP8 等）は instance のまま保持される（owner＝d に付け替え、instance root の中身は触らない）
	for c in d.get_children():
		_own_keep_instances(c, d)
	var sp := PackedScene.new()
	var e1 := sp.pack(d)
	var sub_path := out + "districts_probe.scn"
	var e2 := ResourceSaver.save(sp, sub_path, ResourceSaver.FLAG_COMPRESS)
	d.free()
	var inst := (load(sub_path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	v.add_child(inst)
	v.move_child(inst, idx)
	inst.owner = v
	var mp := PackedScene.new()
	var e3 := mp.pack(v)
	var main_path := out + "village_v2_split_probe.tscn"
	var e4 := ResourceSaver.save(mp, main_path)
	print("[P12SPLIT] pack %d save %d (%d bytes) / main pack %d save %d (%d bytes)" % [e1, e2, FileAccess.get_file_as_bytes(sub_path).size(), e3, e4, FileAccess.get_file_as_bytes(main_path).size()])
	v.free()
	quit(0)

func _own_keep_instances(n: Node, o: Node) -> void:
	n.owner = o
	if n.scene_file_path != "":
		return   # instance root：中身は instance 側の owner のまま
	for c in n.get_children():
		_own_keep_instances(c, o)
