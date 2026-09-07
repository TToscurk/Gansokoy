extends SceneTree
## 立繪資產驗收：portraits.json 每個角色／表情都能載入、尺寸合理、彼此不同圖。
##   Godot --headless --path godot --script tools/verify_portraits.gd
var fails := 0


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[PORTRAIT] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _run() -> void:
	var raw := FileAccess.get_file_as_string("res://data/portraits.json")
	var data: Variant = JSON.parse_string(raw)
	check("portraits.json 可解析", data is Dictionary and not (data as Dictionary).is_empty())
	if not (data is Dictionary):
		quit(1)
		return
	var dm: Node = root.get_node("/root/DialogueManager")
	var digests: Dictionary = {}
	for character_id in (data as Dictionary).keys():
		var entry: Dictionary = data[character_id]
		var table: Dictionary = entry.get("portraits", {})
		check("%s 有名字" % character_id, not String(entry.get("name", "")).is_empty())
		check("%s 至少一種表情" % character_id, table.size() > 0)
		for state in table.keys():
			var path := String(table[state])
			var tex: Texture2D = dm.call("_portrait", String(character_id), String(state))
			var ok_tex := tex != null and tex.get_width() > 64 and tex.get_height() > 64
			check("%s/%s 載入 %s（%s）" % [character_id, state, path,
				"%dx%d" % [tex.get_width(), tex.get_height()] if tex != null else "null"], ok_tex)
			if tex == null:
				continue
			var img := tex.get_image()
			var key := "%s|%s" % [character_id, state]
			digests[key] = img.get_data().slice(0, 4096).hex_encode()
	# 同角色的各表情不得是同一張圖（切錯格會全部一樣）
	for character_id in (data as Dictionary).keys():
		var seen: Dictionary = {}
		var dup := ""
		for key in digests.keys():
			if not String(key).begins_with(String(character_id) + "|"):
				continue
			var d: String = digests[key]
			if seen.has(d):
				dup = "%s == %s" % [key, seen[d]]
			seen[d] = key
		check("%s 各表情圖不重複%s" % [character_id, "" if dup.is_empty() else "（%s）" % dup], dup.is_empty())
	print("[PORTRAIT] failures=%d" % fails)
	quit(1 if fails > 0 else 0)
