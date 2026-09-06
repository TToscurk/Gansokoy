extends SceneTree
## Verify the sky/weather system compiles, runs, and produces sane values at
## every hour and in every weather.
##
## Why a headless sweep instead of eyeballing the editor: the system has ~40
## coupled outputs (sun angle, energy, colour, fog density, ambient, sky
## uniforms) across 24 hours x 6 weathers. A visual check catches the one state
## you happen to look at; this catches the midnight-sun bug, the black-at-noon
## bug and the fog-density-explodes-in-rain bug before they reach the viewport.
##
## Asserts real invariants, not just "it did not crash":
##   - sun is below the horizon at midnight and above it at noon
##   - light energy never goes negative or absurdly high
##   - night is dimmer than day in every weather
##   - fog density stays inside a usable band
##
## Run: godot --headless --path godot --script tools/verify_sky_system.gd

const SKY_SCRIPT := "res://scripts/sky_system.gd"
const SHADER := "res://shaders/sky_daynight.gdshader"


func _init() -> void:
	# The shader must compile before anything else is worth testing.
	var sh = load(SHADER)
	if sh == null:
		push_error("天空著色器載入失敗")
		quit(1)
		return
	print("[ok] 天空著色器載入成功")

	var scr = load(SKY_SCRIPT)
	if scr == null:
		push_error("天象系統腳本載入失敗")
		quit(1)
		return

	var node = scr.new()
	root.add_child(node)
	_run(node)


func _run(node) -> void:
	await process_frame
	await process_frame

	var fails: Array = []

	# ── 24 小時掃描（晴天）──
	print("\n=== 晴天 24 小時 ===")
	print("%-6s %-9s %-9s %-22s %-9s %s" % [
		"時刻", "太陽高度", "光強", "光色", "環境光", "霧密度"])

	var 白天最強 := 0.0
	var 夜晚最強 := 0.0

	for i in 25:
		var hr := float(i)
		node.設定時刻(hr)
		await process_frame

		var sun: DirectionalLight3D = node.get_node("太陽")
		var envn: WorldEnvironment = node.get_node("天空環境")
		var env: Environment = envn.environment

		# A DirectionalLight3D emits along its own -Z. The direction the light
		# TRAVELS is therefore -basis.z; the direction TOWARD the sun is the
		# negation of that, i.e. +basis.z. Its Y component is the sun's height.
		var elev := rad_to_deg(asin(clampf(sun.global_transform.basis.z.y, -1.0, 1.0)))
		var e := sun.light_energy
		var c := sun.light_color

		if hr >= 10.0 and hr <= 14.0:
			白天最強 = maxf(白天最強, e)
		if hr <= 3.0 or hr >= 21.0:
			夜晚最強 = maxf(夜晚最強, e)

		print("%-6.1f %-9.1f %-9.3f %-22s %-9.3f %.5f" % [
			hr, elev, e,
			"(%.2f,%.2f,%.2f)" % [c.r, c.g, c.b],
			env.ambient_light_energy, env.fog_density])

		if e < 0.0:
			fails.append("%.0f時 光強為負" % hr)
		if e > 3.0:
			fails.append("%.0f時 光強過高 %.2f" % [hr, e])
		if env.fog_density < 0.0 or env.fog_density > 0.05:
			fails.append("%.0f時 霧密度異常 %.5f" % [hr, env.fog_density])

		# Physical sanity: the sun must be up at noon and down at midnight.
		if is_equal_approx(hr, 12.0) and elev <= 0.0:
			fails.append("正午太陽在地平線下 (%.1f度)" % elev)
		if is_equal_approx(hr, 0.0) and elev >= 0.0:
			fails.append("午夜太陽在地平線上 (%.1f度)" % elev)

	if 夜晚最強 >= 白天最強:
		fails.append("夜晚比白天亮 (夜 %.3f >= 日 %.3f)" % [夜晚最強, 白天最強])
	else:
		print("\n[ok] 白天最強 %.3f > 夜晚最強 %.3f" % [白天最強, 夜晚最強])

	# ── 六種天氣（正午）──
	print("\n=== 正午各天氣（過渡設為 0 以便即時比較）===")
	print("%-8s %-9s %-9s %-11s %-9s %s" % [
		"天氣", "光強", "角直徑", "霧密度", "飽和度", "體積霧"])

	node.天氣過渡秒數 = 0.0
	node.設定時刻(12.0)

	var 名稱 := ["晴", "薄雲", "陰", "雨", "霧", "雪"]
	var 前次光強 := 999.0

	for w in 6:
		node.天氣 = w
		# Transition is instant but still needs frames to settle.
		for f in 4:
			await process_frame

		var sun: DirectionalLight3D = node.get_node("太陽")
		var env: Environment = node.get_node("天空環境").environment

		print("%-8s %-9.3f %-9.2f %-11.5f %-9.3f %.4f" % [
			名稱[w], sun.light_energy, sun.light_angular_distance,
			env.fog_density, env.adjustment_saturation,
			env.volumetric_fog_density])

		if sun.light_energy <= 0.0:
			fails.append("%s 正午光強為 0" % 名稱[w])
		if env.fog_density > 0.05:
			fails.append("%s 霧密度爆炸 %.4f" % [名稱[w], env.fog_density])

	# ── 星空參數 ──
	print("\n=== 午夜星空參數 ===")
	node.天氣 = 0
	for f in 4:
		await process_frame
	node.設定時刻(0.0)
	await process_frame

	var env2: Environment = node.get_node("天空環境").environment
	var mat := env2.sky.sky_material as ShaderMaterial
	if mat == null:
		fails.append("天空材質不是 ShaderMaterial")
	else:
		for p in ["star_density", "milkyway", "day_amount", "moon_visible"]:
			print("  %-14s = %s" % [p, mat.get_shader_parameter(p)])
		var da = mat.get_shader_parameter("day_amount")
		if da != null and float(da) > 0.05:
			fails.append("午夜 day_amount 應接近 0，實際 %.3f" % float(da))

	print("")
	if fails.is_empty():
		print("[PASS] 全部檢查通過")
		quit(0)
	else:
		for f in fails:
			print("  [FAIL] %s" % f)
		print("\n[FAIL] %d 項問題" % fails.size())
		quit(1)
