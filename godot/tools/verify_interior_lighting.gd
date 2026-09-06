extends SceneTree
## Regression: 室內補光不得被日夜循環蓋掉。
##
## 症狀：`interior_lighting.gd` 把 ambient_energy 拉到 2.10、sky_contribution
## 降到 0.08，但實測室內環境光是 0.73 / 0.43 —— 正好是 daynight.gd 的
## `lerpf(0.58, 0.82, k)` 與 `lerpf(0.22, 0.55, k)`。
##
## 根因：daynight.gd 的 `_apply_ambient()` 每秒覆寫**目前生效的 Environment**，
## 它只跳過「有天象系統」的室外圖，不認得室內。室內看不到天空，
## sky_contribution 被拉回 0.43 等於把近半亮度交給一片看不見的天空。

var failures := 0

func _init() -> void:
	_run.call_deferred()

func check(label: String, ok: bool) -> void:
	print("[ILIGHT] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _wait(n: int) -> void:
	for i in n:
		await physics_frame
		await process_frame

func _env(main: Node) -> Environment:
	for n in main.map_root.find_children("*", "WorldEnvironment", true, false):
		var we := n as WorldEnvironment
		if we.environment != null:
			return we.environment
	return null

func _run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(3)

	for id in ["hieda1f", "hieda2f", "hieda3f"]:
		main.load_map(id, "slice" if id == "hieda1f" else "hieda1f")
		await _wait(60)
		var env := _env(main)
		check("%s 有 Environment" % id, env != null)
		if env == null:
			continue

		# 讓日夜循環有機會覆寫：等足夠多幀。
		await _wait(120)
		print("[ILIGHT] %s ambient_energy=%.3f sky_contribution=%.3f source=%d"
			% [id, env.ambient_light_energy, env.ambient_light_sky_contribution,
				env.ambient_light_source])

		# 室內看不到天空：對天空的依賴必須壓低，否則等於白給亮度。
		check("%s 室內不依賴天空（sky_contribution %.2f ≤ 0.20）"
			% [id, env.ambient_light_sky_contribution],
			env.ambient_light_sky_contribution <= 0.20)
		# 環境光要自己給足。
		check("%s 環境光足夠（energy %.2f ≥ 1.50）" % [id, env.ambient_light_energy],
			env.ambient_light_energy >= 1.50)
		check("%s 環境光來源是顏色而非天空" % id,
			env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR)

		# 時間推進也不能把它打回去 —— 室內沒有日夜。
		var dn: Node = root.get_node_or_null("DayNight")
		if dn != null:
			dn.hour = 2.0
		await _wait(90)
		print("[ILIGHT] %s 半夜 2 點：energy=%.3f sky=%.3f"
			% [id, env.ambient_light_energy, env.ambient_light_sky_contribution])
		check("%s 深夜仍維持室內補光（energy %.2f ≥ 1.50）"
			% [id, env.ambient_light_energy], env.ambient_light_energy >= 1.50)
		if dn != null:
			dn.hour = 12.0
		await _wait(30)

	print("[ILIGHT] failures=%d" % failures)
	quit(failures)
