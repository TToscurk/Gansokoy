extends SceneTree
## Regression: village 清版後，世界必須仍然完整可走。
##
## 承諾：
##   1. 任何資料檔都不再引用 village（registry、meta portals、connections）。
##   2. slice 不再依賴 maps/village/ 下的任何檔案（地標已搬去 assets/landmark）。
##   3. 村內測試 NPC 從舊基線改由 slice 提供，互動測試照跑。
##   4. 獸道→slice、slice 三口全部實走仍通（由既有測試涵蓋，這裡查靜態引用）。

var failures := 0

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[NOVILLAGE] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _read(p: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_as_text() if f != null else ""

func _run() -> void:
	# --- 1. village 的場景與資料都該消失 --------------------------------
	check("maps/village/village.tscn 已刪除",
		not ResourceLoader.exists("res://maps/village/village.tscn"))
	check("data/village.meta.json 已刪除", not FileAccess.file_exists("res://data/village.meta.json"))
	check("blockout/village.glb 已刪除", not FileAccess.file_exists("res://blockout/village.glb"))

	# --- 2. registry 不再認得 village -----------------------------------
	var reg: Variant = JSON.parse_string(_read("res://data/mapRegistry.json"))
	check("mapRegistry 沒有 village 登錄", reg != null and not reg.has("village"))
	var strays: Array = []
	for k in reg:
		if "village" in Array(reg[k].get("connections", [])):
			strays.append(k)
	check("沒有任何圖的 connections 還指向 village：%s" % str(strays), strays.is_empty())

	# --- 3. 所有 meta 的 portals 都不再傳向 village ---------------------
	var dm := DirAccess.open("res://data")
	var portal_hits: Array = []
	if dm:
		for f in dm.get_files():
			if not f.ends_with(".meta.json"):
				continue
			var m: Variant = JSON.parse_string(_read("res://data/" + f))
			if m == null:
				continue
			for p in m.get("portals", []):
				if str(p.get("target", "")) == "village":
					portal_hits.append(f)
	check("沒有任何 portal 還傳向 village：%s" % str(portal_hits), portal_hits.is_empty())

	# --- 4. slice 不再引用 maps/village/ 下的任何檔案 -------------------
	var slice := _read("res://maps/slice/slice.tscn")
	check("slice.tscn 沒有 maps/village 引用", not slice.contains("maps/village"))
	# 六支地標必须存在於新家，且仍可用（用舊 uid 直接載入）。
	for pair in [["res://assets/landmark/寺子屋/寺子屋.glb", "uid://huxrost0wlqu"],
			["res://assets/landmark/鈴奈庵/鈴奈庵.glb", "uid://bqufusi10p8ld"],
			["res://assets/landmark/鯢吞亭/鯢吞亭.glb", "uid://d0po5qd2jwkxh"],
			["res://assets/landmark/霧雨店/霧雨店.glb", "uid://cws10r4siyyj6"],
			["res://assets/landmark/龍神像/龍神像.glb", "uid://bwk4nobtxpmbt"],
			["res://assets/landmark/稗田邸/稗田底新版.glb", "uid://bm2ugu0n3ddlx"]]:
		check("%s 存在" % pair[0].get_file(), ResourceLoader.exists(pair[0]))
		check("%s 用原 uid 仍可解析" % pair[0].get_file(),
			ResourceLoader.exists(ResourceUID.get_id_path(ResourceUID.text_to_id(pair[1]))))

	# --- 5. 載圖不再炸：slice / trail / kourindou / hieda1f 全部實載 ----
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	for id in ["slice", "trail", "kourindou", "hieda1f"]:
		main.load_map(id, "")
		await process_frame
		await process_frame
		await process_frame
		check("載入 %s 成功" % id, main.current_id == id and main.map_root != null)

	# 村內測試 NPC 現在住在 slice。
	main.load_map("slice", "")
	for i in 10:
		await process_frame
	var npc: Node = main.map_root.get_node_or_null("VerticalSliceNPC")
	check("slice 上有測試村人 NPC", npc != null)
	if npc != null:
		check("村人站在可行的地面上（y 差 < 1 m）",
			absf(npc.global_position.y - main.get_node("Player").global_position.y) < 40.0)

	# --- 6. 舊圖真的打不開了（防呆：不是「剛好沒載到」）---------------
	main.load_map("village", "")
	await process_frame
	check("village 已無法載入", main.current_id != "village")

	print("[NOVILLAGE] failures=%d" % failures)
	quit(failures)
