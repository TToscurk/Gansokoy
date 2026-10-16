extends SceneTree
## 把 DevLayerGate（maps/village_v2/scripts_p13/dev_layer_gate.gd）掛到 village_v2.tscn root 的最後一個子節點（文字編輯・不重複・可拆）。
##   godot --headless --path godot --script res://tools/p13/w9/attach_dev_layer_gate.gd -- --check    唯讀：掛了沒、載入後開發疊層是否隱藏
##   godot --headless --path godot --script res://tools/p13/w9/attach_dev_layer_gate.gd -- --attach   寫 village_v2.tscn（+3 行）
##   godot --headless --path godot --script res://tools/p13/w9/attach_dev_layer_gate.gd -- --detach   拆掉（還原為掛載前的文字）
## --attach／--detach 只在共享編輯器沒有開著 village_v2.tscn（或確認無未存檔修改）時執行。
## village_v2.tscn 由 gen_village_v2.gd 產生；若重新產生，需重跑 --attach（與其他 overlay 的 --attach 相同）。
var SCENE := "res://maps/village_v2/village_v2.tscn"   # --scene=<path> で上書き（可逆性テスト用のコピー）
const SCRIPT := "res://maps/village_v2/scripts_p13/dev_layer_gate.gd"
const EXT_ID := "p13w9_devgate"
const NODE_LINE := "[node name=\"DevLayerGate\" parent=\".\" type=\"Node\"]"
const PROP_LINE := "script = ExtResource(\"p13w9_devgate\")"
const EXT_LINE := "[ext_resource type=\"Script\" path=\"res://maps/village_v2/scripts_p13/dev_layer_gate.gd\" id=\"p13w9_devgate\"]"
const DEV_PATHS := ["Debug", "QuestAnchors", "Districts/LandmarkParcelLines", "Districts/AuxParcelLines", "Portals"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for a: String in args:
		if a.begins_with("--scene="):
			SCENE = a.trim_prefix("--scene=")
	if "--attach" in args:
		quit(_attach())
	elif "--detach" in args:
		quit(_detach())
	else:
		_check.call_deferred()


func _nl(txt: String) -> String:
	return "\r\n" if txt.contains("\r\n") else "\n"


func _attach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if txt.contains(NODE_LINE):
		print("[DEVGATE] attach：已掛（不重複、不寫場景）")
		return 0
	if txt.contains(EXT_ID):
		printerr("[DEVGATE] 場景有半套的 %s（只有 ext_resource 或 script 行）→ 不寫，先人工確認" % EXT_ID)
		return 1
	var nl := _nl(txt)
	var lines := txt.split(nl)
	var out := PackedStringArray(Array(lines))
	var last_ext := -1
	for k in out.size():
		if out[k].begins_with("[ext_resource"):
			last_ext = k
	if last_ext < 0:
		printerr("[DEVGATE] 找不到 ext_resource 區")
		return 1
	out.insert(last_ext + 1, EXT_LINE)
	while out.size() > 0 and out[out.size() - 1] == "":
		out.remove_at(out.size() - 1)
	out.append("")
	out.append(NODE_LINE)
	out.append(PROP_LINE)
	out.append("")
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[DEVGATE] attach：加 root/DevLayerGate（最後一個子節點）→ %s（+%d 行）" % [SCENE, out.size() - lines.size()])
	return 0


func _detach() -> int:
	var txt := FileAccess.get_file_as_string(SCENE)
	if not txt.contains(NODE_LINE):
		print("[DEVGATE] detach：沒有掛（不寫場景）")
		return 0
	var nl := _nl(txt)
	var out := PackedStringArray()
	var lines := txt.split(nl)
	var k := 0
	while k < lines.size():
		var l := lines[k]
		if l == EXT_LINE:
			k += 1
			continue
		if l == NODE_LINE:
			if out.size() > 0 and out[out.size() - 1] == "":
				out.remove_at(out.size() - 1)
			k += 2   # node 行＋script 行
			continue
		out.append(l)
		k += 1
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(nl.join(out))
	f.close()
	print("[DEVGATE] detach：拆掉 root/DevLayerGate → %s（%d 行）" % [SCENE, out.size() - lines.size()])
	return 0


func _check() -> void:
	var txt := FileAccess.get_file_as_string(SCENE)
	var n_node := txt.count(NODE_LINE)
	var n_ext := txt.count(EXT_LINE)
	print("[DEVGATE] 場景文字：node %d・ext_resource %d（應為 1／1 或 0／0）" % [n_node, n_ext])
	var bad := (n_node != n_ext) or n_node > 1
	var v := (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	await process_frame
	var last := v.get_child(v.get_child_count() - 1)
	print("[DEVGATE] root 最後一個子節點：%s" % last.name)
	for p: String in DEV_PATHS:
		var n := v.get_node_or_null(p) as Node3D
		print("[DEVGATE]   %-30s %s" % [p, ("visible=%s" % n.visible) if n else "（無此節點）"])
		if n_node == 1 and n != null and n.visible:
			bad = true
	print("[DEVGATE] 結果：%s" % ("FAIL" if bad else "OK"))
	v.queue_free()
	await process_frame
	quit(1 if bad else 0)
