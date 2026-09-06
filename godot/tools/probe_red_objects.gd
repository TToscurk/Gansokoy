extends SceneTree
## 場景裡的紅色物件盤點：地藏頭巾、紅布條、紅葉樹各有多少、在哪。
##   Godot --headless --path godot --script tools/probe_red_objects.gd
##
## v16 實拍畫面上散落多個紅團，要確認是哪一類、密度是否過高。

func _init() -> void:
	var ps := load("res://maps/trail/trail.tscn") as PackedScene
	var root := ps.instantiate() as Node3D
	var counts := {}
	var samples := {}
	for n in _all(root):
		var nm := String(n.name)
		var key := ""
		if nm.begins_with("紅頭巾") or nm.begins_with("圍兜"):
			key = "地藏布(頭巾/圍兜)"
		elif nm.begins_with("紅布"):
			key = "紅布條"
		elif nm.begins_with("舊紅布"):
			key = "空地舊紅布"
		if key == "":
			continue
		counts[key] = counts.get(key, 0) + 1
		if not samples.has(key):
			samples[key] = []
		if samples[key].size() < 3 and n is Node3D:
			samples[key].append((n as Node3D).global_position if n.is_inside_tree() else (n as Node3D).position)
	for k in counts:
		print("[RED] %-18s %4d  例：%s" % [k, counts[k], samples[k]])
	# 倒木
	var logs := 0
	for n in _all(root):
		if String(n.name).begins_with("暫代倒木"):
			logs += 1
	print("[RED] 暫代倒木 %d 根" % logs)
	root.free()
	quit(0)

func _all(n: Node) -> Array:
	var o := [n]
	for c in n.get_children():
		o.append_array(_all(c))
	return o
