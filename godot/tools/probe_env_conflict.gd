extends SceneTree
## F5 之後場上到底有幾個 WorldEnvironment / DirectionalLight，哪一個在管天空。
##
##   Godot --headless --path godot --script tools/probe_env_conflict.gd
##
## 懷疑點：main.gd 用 find_child("WorldEnvironment") 找圖自帶的環境，那是
## **名稱**比對；slice 的節點叫「天空環境」，名字對不上。若真如此，main 自己
## 的 WorldEnvironment 與 Sun 不會讓位，會和天象系統打架。

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	main.load_map("slice", "")
	for i in 8:
		await process_frame

	print("[ENV] === WorldEnvironment ===")
	for n in _find(main, "WorldEnvironment"):
		var e: Environment = (n as WorldEnvironment).environment
		var desc := "environment=null（未啟用）"
		if e != null:
			desc = "bg=%d sky=%s 霧=%s volfog=%s ssao=%s" % [
				e.background_mode, "有" if e.sky != null else "無",
				e.fog_enabled, e.volumetric_fog_enabled, e.ssao_enabled]
		print("[ENV] %-40s %s" % [_path(n, main), desc])

	print("[ENV] === DirectionalLight3D ===")
	for n in _find(main, "DirectionalLight3D"):
		var l := n as DirectionalLight3D
		print("[ENV] %-40s 可見=%s 能量=%.2f 投影=%s 色=%s" % [
			_path(n, main), l.visible, l.light_energy, l.shadow_enabled,
			l.light_color])

	# main.gd 那一行實際找到什麼
	var found: Node = main.map_root.find_child("WorldEnvironment", true, false)
	print("[ENV] main.gd 的 find_child(\"WorldEnvironment\") → %s" % [
		"null（找不到！）" if found == null else _path(found, main)])
	var by_type := _find(main.map_root, "WorldEnvironment")
	print("[ENV] 但圖裡實際有 %d 個 WorldEnvironment：%s" % [
		by_type.size(), ", ".join(by_type.map(func(x): return String(x.name)))])

	print("[ENV] done")
	quit(0)


func _find(n: Node, cls: String) -> Array:
	var out := []
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		out.append_array(_find(c, cls))
	return out


func _path(n: Node, root_node: Node) -> String:
	var parts := PackedStringArray()
	var cur: Node = n
	while cur != null and cur != root_node:
		parts.append(String(cur.name))
		cur = cur.get_parent()
	parts.reverse()
	return "/".join(parts)
