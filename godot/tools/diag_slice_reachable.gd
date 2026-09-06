extends SceneTree
## Is maps/slice reachable by walking? Check the actual portal graph.

var main: Node = null

func _init() -> void:
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _meta(id: String) -> Dictionary:
	var f := FileAccess.open("res://data/%s.meta.json" % id, FileAccess.READ)
	if f == null:
		return {}
	var j: Variant = JSON.parse_string(f.get_as_text())
	return j if j is Dictionary else {}

func _run() -> void:
	print("[SLICE] === 傳送圖連通性（來自 data/*.meta.json）===")
	var maps := ["shrine", "trail", "village", "slice", "kourindou"]
	var inbound_to_slice: Array = []
	for id in maps:
		var m := _meta(id)
		if m.is_empty():
			print("[SLICE] %-10s 沒有 meta.json" % id)
			continue
		var outs: Array = []
		for p in m.get("portals", []):
			var t: Variant = p.get("target")
			var ts: String = "" if t == null else str(t)
			outs.append("(保留)" if ts.is_empty() else ts)
			if ts == "slice":
				inbound_to_slice.append(id)
		print("[SLICE] %-10s → %s" % [id, ", ".join(PackedStringArray(outs))])
	print("[SLICE] 指向 slice 的傳送區：%s" % ("無" if inbound_to_slice.is_empty() else str(inbound_to_slice)))

	# slice 在地圖登錄檔裡嗎？
	var reg: Variant = JSON.parse_string(FileAccess.open("res://data/mapRegistry.json", FileAccess.READ).get_as_text())
	print("[SLICE] slice 在 mapRegistry 裡：%s" % str(reg.has("slice")))

	# 場景檔存在嗎？
	print("[SLICE] maps/slice/slice.tscn 存在：%s" % str(ResourceLoader.exists("res://maps/slice/slice.tscn")))
	print("[SLICE] maps/village/village.tscn 存在：%s" % str(ResourceLoader.exists("res://maps/village/village.tscn")))

	# 實走：獸道的南端傳送區到底把人送到哪個場景？
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("trail", "shrine")
	await _wait(40)
	var player = main.get_node_or_null("Player")

	var portal: Area3D = null
	for c in main.get_children():
		for g in c.get_children():
			if String(g.name).begins_with("Portal_") and not String(g.name).ends_with("shrine"):
				portal = g
	print("[SLICE] 獸道南端傳送區名稱：%s" % (portal.name if portal else "找不到"))

	if portal != null:
		while main.portal_cooldown > 0.0:
			await physics_frame
			await process_frame
		player.global_position = portal.global_position
		player.velocity = Vector3.ZERO
		await _wait(40)
		print("[SLICE] 走進去之後實際載入的圖：%s" % main.current_id)
		var root_name := ""
		if main.map_root != null:
			root_name = String(main.map_root.name)
		print("[SLICE] 場景根節點：%s" % root_name)
		print("[SLICE] 判定：%s"
			% ("到的是 slice" if main.current_id == "slice" else "到的是 %s，不是 slice" % main.current_id))

	# slice 能不能直接載入（就算走不到）？
	main.load_map("slice", "")
	await _wait(60)
	print("[SLICE] 直接 load_map('slice')：current_id=%s 玩家=%s on_floor=%s"
		% [main.current_id, str(main.get_node("Player").global_position), str(main.get_node("Player").is_on_floor())])

	quit(0)
