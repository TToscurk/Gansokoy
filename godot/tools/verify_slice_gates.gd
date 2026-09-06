extends SceneTree
## Regression: slice 的三個出入口，依使用者指定的地標配置。
##
##   * 獸道入口 = **南側大鳥居**（x≈236, z≈+102），外側是草地與排列的石頭。
##   * 北側大鳥居（z≈-80）盡頭是**稗田邸**（z≈-138）→ hieda1f 的入口。
##   * **香霖堂**入口在**龍石像橋**旁（橋跨 x 398~452, z≈-144，龍神像在 x≈362）。

var failures := 0
var main: Node = null
var player: Node = null

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[GATES] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

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

func _portal(meta: Dictionary, target: String) -> Dictionary:
	for p in meta.get("portals", []):
		if str(p.get("target", "")) == target:
			return p
	return {}

## 站上傳送區並等它觸發，回傳最後的圖 id。
func _enter(area_pos: Vector3) -> String:
	while main.portal_cooldown > 0.0:
		await physics_frame
		await process_frame
	player.global_position = area_pos + Vector3(0, 0.5, 0)
	player.velocity = Vector3.ZERO
	await _wait(40)
	return main.current_id

func _run() -> void:
	var slice_meta := _meta("slice")

	# --- 靜態：三顆 portal 都在，且位置對得上地標 ---------------------
	var to_trail := _portal(slice_meta, "trail")
	var to_hieda := _portal(slice_meta, "hieda1f")
	var to_kourin := _portal(slice_meta, "kourindou")

	check("slice 有通往獸道的傳送區", not to_trail.is_empty())
	check("slice 有通往稗田邸的傳送區", not to_hieda.is_empty())
	check("slice 有通往香霖堂的傳送區", not to_kourin.is_empty())

	if not to_trail.is_empty():
		# 南側大鳥居在 (236, 102)；獸道口必須在它附近，而不是北口。
		var d := Vector2(float(to_trail.x) - 236.0, float(to_trail.z) - 102.0).length()
		print("[GATES] 獸道口 (%.1f, %.1f)，距南側大鳥居 %.1f m" % [to_trail.x, to_trail.z, d])
		check("獸道口設在南側大鳥居旁（草地石列那側）", d < 25.0)
		check("獸道口在村子南側（z 為正）", float(to_trail.z) > 0.0)

	if not to_hieda.is_empty():
		# 稗田邸在 (233, -138)，北側大鳥居在 (235, -80)。
		var dh := Vector2(float(to_hieda.x) - 233.2, float(to_hieda.z) + 138.6).length()
		print("[GATES] 稗田口 (%.1f, %.1f)，距稗田邸 %.1f m" % [to_hieda.x, to_hieda.z, dh])
		check("稗田口就在稗田邸前", dh < 25.0)
		check("稗田口在北側大鳥居之外（z 更負）", float(to_hieda.z) < -80.0)

	if not to_kourin.is_empty():
		# 龍石像橋中心 (423, -144)。
		var dk := Vector2(float(to_kourin.x) - 423.0, float(to_kourin.z) + 144.0).length()
		print("[GATES] 香霖口 (%.1f, %.1f)，距龍石像橋 %.1f m" % [to_kourin.x, to_kourin.z, dk])
		check("香霖口設在龍石像橋旁", dk < 40.0)

	# 三個口必須彼此分得夠開，不然會互相誤觸。
	if not to_trail.is_empty() and not to_hieda.is_empty() and not to_kourin.is_empty():
		var a := Vector2(float(to_trail.x), float(to_trail.z))
		var b := Vector2(float(to_hieda.x), float(to_hieda.z))
		var c := Vector2(float(to_kourin.x), float(to_kourin.z))
		check("三個出入口彼此相距夠遠（不會誤觸）",
			a.distance_to(b) > 20.0 and b.distance_to(c) > 20.0 and a.distance_to(c) > 20.0)

	# --- 實走：每個口都要能用 -----------------------------------------
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("slice", "")
	await _wait(80)
	player = main.get_node_or_null("Player")

	# 每個傳送區都必須真的在場上生出來。
	var names: Array = []
	for c in main.get_children():
		for g in c.get_children():
			if String(g.name).begins_with("Portal_"):
				names.append(String(g.name))
	print("[GATES] slice 場上的傳送區：%s" % str(names))
	check("場上生出了往獸道的傳送區", names.has("Portal_trail"))
	check("場上生出了往稗田邸的傳送區", names.has("Portal_hieda1f"))
	check("場上生出了往香霖堂的傳送區", names.has("Portal_kourindou"))

	# 站上去要能觸發，而且到的是對的地方。
	if not to_trail.is_empty():
		var got: String = await _enter(Vector3(float(to_trail.x), float(to_trail.y), float(to_trail.z)))
		check("走進獸道口 → 獸道（實得 %s）" % got, got == "trail")
		main.load_map("slice", "")
		await _wait(60)

	if not to_kourin.is_empty():
		var got2: String = await _enter(Vector3(float(to_kourin.x), float(to_kourin.y), float(to_kourin.z)))
		check("走進香霖口 → 香霖堂（實得 %s）" % got2, got2 == "kourindou")
		main.load_map("slice", "")
		await _wait(60)

	if not to_hieda.is_empty():
		var got3: String = await _enter(Vector3(float(to_hieda.x), float(to_hieda.y), float(to_hieda.z)))
		check("走進稗田口 → 稗田邸（實得 %s）" % got3, got3 == "hieda1f")

	# --- 從稗田邸／香霖堂要回得來 -------------------------------------
	var hieda_back := _portal(_meta("hieda1f"), "slice")
	check("稗田邸有回 slice 的傳送區（不是回舊 village）", not hieda_back.is_empty())
	var kourin_back := _portal(_meta("kourindou"), "slice")
	check("香霖堂有回 slice 的傳送區（不是回舊 village）", not kourin_back.is_empty())

	print("[GATES] failures=%d" % failures)
	quit(failures)
