extends SceneTree
## 天空 shader 的實際 runtime 參數，以及雲到底畫了多少。
##
##   Godot --headless --path godot --script tools/probe_sky_clouds.gd
##
## 不推論、直接讀：Sky 用的是哪個材質、painted_clouds 綁到哪張圖、
## painted_mix / cloud_cover 是多少，以及 procedural 那層有沒有被關掉。

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	main.load_map("slice", "")
	for i in 10:
		await process_frame

	var sky_node: Node = _find(main.map_root, "WorldEnvironment")
	if sky_node == null:
		print("[SKY] 圖裡找不到 WorldEnvironment")
		quit(1)
		return
	var env: Environment = (sky_node as WorldEnvironment).environment
	print("[SKY] 環境節點 = %s" % sky_node.name)
	print("[SKY] background_mode = %d（2 = Sky）" % env.background_mode)
	var sky: Sky = env.sky
	if sky == null:
		print("[SKY] environment.sky = null → 沒有天空！")
		quit(1)
		return
	var mat := sky.sky_material
	print("[SKY] sky_material = %s" % mat.get_class())
	if not (mat is ShaderMaterial):
		print("[SKY] ✗ 不是 ShaderMaterial，雲的 shader 根本沒在跑")
		quit(1)
		return
	var sm := mat as ShaderMaterial
	print("[SKY] shader = %s" % (sm.shader.resource_path if sm.shader else "null"))

	for p in ["painted_clouds", "painted_mix", "painted_yaw", "painted_drift",
			"cloud_cover", "overcast", "day_amount", "sun_dir"]:
		var v = sm.get_shader_parameter(p)
		var desc := str(v)
		if v is Texture2D:
			desc = "%s  (%dx%d)" % [(v as Texture2D).resource_path,
				(v as Texture2D).get_width(), (v as Texture2D).get_height()]
		elif v == null:
			desc = "null（未設定 → 用 shader 預設）"
		print("[SKY]   %-16s = %s" % [p, desc])

	var pm = sm.get_shader_parameter("painted_mix")
	var pmf: float = 1.0 if pm == null else float(pm)
	print("[SKY] → 程序化雲權重 proc_w = 1 - painted_mix = %.2f %s" % [
		1.0 - pmf,
		"（程序化雲完全關閉，雲全靠貼圖）" if pmf >= 0.999 else ""])

	var 天象: Node = main.map_root.get_node_or_null("天象系統")
	if 天象 != null:
		print("[SKY] 天象系統 天氣=%s 時刻=%.2f 概念圖雲層比例=%s" % [
			天象.get("天氣"), 天象.get("時刻"), 天象.get("概念圖雲層比例")])
	print("[SKY] done")
	quit(0)


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null
