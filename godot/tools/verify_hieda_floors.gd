extends SceneTree
## Regression: 稗田邸內部 1F → 2F → 3F 的上下樓動線必須真的通。
## slice ──稗田口──> hieda1f ⇄ hieda2f ⇄ hieda3f

var failures := 0
var main: Node = null
var player: Node = null

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[HIEDA] %s %s" % ["PASS" if ok else "FAIL", label])
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

func _portal(id: String, target: String) -> Dictionary:
	for p in _meta(id).get("portals", []):
		if str(p.get("target", "")) == target:
			return p
	return {}

## 站上該圖通往 target 的傳送區，回傳實際抵達的圖 id。
func _go(target: String) -> String:
	var p := _portal(main.current_id, target)
	if p.is_empty():
		return "(%s 沒有往 %s 的傳送區)" % [main.current_id, target]
	while main.portal_cooldown > 0.0:
		await physics_frame
		await process_frame
	player.global_position = Vector3(float(p.x), float(p.y) + 0.5, float(p.z))
	player.velocity = Vector3.ZERO
	await _wait(45)
	return main.current_id

func _run() -> void:
	# --- 靜態：三層都要有場景與 meta ---------------------------------
	for f in ["hieda1f", "hieda2f", "hieda3f"]:
		check("%s 場景檔存在" % f, ResourceLoader.exists("res://maps/%s/%s.tscn" % [f, f]))
		check("%s 有 meta.json" % f, not _meta(f).is_empty())

	check("1F 有往 2F 的傳送區", not _portal("hieda1f", "hieda2f").is_empty())
	check("2F 有往 3F 的傳送區", not _portal("hieda2f", "hieda3f").is_empty())
	check("2F 有回 1F 的傳送區", not _portal("hieda2f", "hieda1f").is_empty())
	check("3F 有回 2F 的傳送區", not _portal("hieda3f", "hieda2f").is_empty())
	check("1F 出口回的是 slice（不是凍結的 village）",
		not _portal("hieda1f", "slice").is_empty())

	# --- 實走：從人里進屋，一路爬到三樓，再走回人里 -------------------
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)
	main.load_map("slice", "")
	await _wait(80)
	player = main.get_node_or_null("Player")

	var a: String = await _go("hieda1f")
	check("從人里進得了稗田邸一樓（實得 %s）" % a, a == "hieda1f")
	if a == "hieda1f":
		await _wait(40)
		check("在一樓踩得到地面", player.is_on_floor())
		print("[HIEDA] 1F 落點 %s on_floor=%s" % [str(player.global_position), str(player.is_on_floor())])

		var b: String = await _go("hieda2f")
		check("一樓上得了二樓（實得 %s）" % b, b == "hieda2f")
		if b == "hieda2f":
			await _wait(40)
			check("在二樓踩得到地面", player.is_on_floor())
			print("[HIEDA] 2F 落點 %s on_floor=%s" % [str(player.global_position), str(player.is_on_floor())])

			var c: String = await _go("hieda3f")
			check("二樓上得了三樓（實得 %s）" % c, c == "hieda3f")
			if c == "hieda3f":
				await _wait(40)
				check("在三樓踩得到地面", player.is_on_floor())
				print("[HIEDA] 3F 落點 %s on_floor=%s" % [str(player.global_position), str(player.is_on_floor())])

				# --- 下樓：一路走回人里 -------------------------------
				var d: String = await _go("hieda2f")
				check("三樓下得回二樓（實得 %s）" % d, d == "hieda2f")
				var e: String = await _go("hieda1f")
				check("二樓下得回一樓（實得 %s）" % e, e == "hieda1f")
				var f2: String = await _go("slice")
				check("一樓走得回人間之里（實得 %s）" % f2, f2 == "slice")
				if f2 == "slice":
					await _wait(60)
					check("回到人里站得住", player.is_on_floor())
					print("[HIEDA] 回人里落點 %s" % str(player.global_position))

	print("[HIEDA] failures=%d" % failures)
	quit(failures)
