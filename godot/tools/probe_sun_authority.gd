extends SceneTree
## 誰在控制太陽？DayNight autoload 與天象系統的權責重疊查證。
##
##   Godot --headless --path godot --script tools/probe_sun_authority.gd -- --hour=11
##
## 症狀：--hour=11 讓 HUD 時鐘顯示 11:00，但太陽角度沒動，右側整排町家仍全暗。
## 兩個嫌疑：
##  (1) DayNight 轉的是 main.tscn 的 $Sun，但那盞已經被 main.gd 讓位隱藏了，
##      實際照明的是天象系統的「太陽」，而天象系統讀自己的「時刻」不讀 DayNight。
##  (2) 天象系統的時刻停在場景存檔時的值。
## 這支把兩邊的數字並排印出來，看是哪一個。

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

	var dn: Node = root.get_node_or_null("/root/DayNight")
	print("[SUN] DayNight.hour    = %s" % (dn.get("hour") if dn else "（無 autoload）"))
	print("[SUN] DayNight.flowing = %s" % (dn.get("flowing") if dn else "-"))

	var sky: Node = main.map_root.get_node_or_null("天象系統")
	if sky != null:
		print("[SUN] 天象系統.時刻      = %s" % sky.get("時刻"))
		print("[SUN] 天象系統.一日長度分鐘 = %s" % sky.get("一日長度分鐘"))

	print("[SUN] === 場上所有 DirectionalLight3D ===")
	for l in _lights(main):
		var d := l as DirectionalLight3D
		# ⚠ 仰角＝「太陽在天上多高」，不是光線向量的 y。
		# DirectionalLight3D 的 -basis.z 是**光行進的方向**：正午太陽在頭頂，
		# 光往下打，所以那個 y 是大的負值。太陽自身的高度角要取反號。
		# 第一版直接印光線 y，正午量到 −58.5° 看起來像太陽在地底下。
		var light_dir := -d.global_transform.basis.z
		var elev := rad_to_deg(asin(clampf(-light_dir.y, -1.0, 1.0)))
		print("[SUN] %-28s 可見=%-5s 能量=%.2f 太陽高度=%+.1f° 投影=%s" % [
			_path(d, main), d.visible, d.light_energy, elev, d.shadow_enabled])

	print("[SUN] （太陽高度：正午應 +50° 以上；0° = 地平線；負 = 已落下）")
	print("[SUN] done")
	quit(0)


func _lights(n: Node) -> Array:
	var out: Array = []
	if n is DirectionalLight3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_lights(c))
	return out


func _path(n: Node, root_node: Node) -> String:
	var parts := PackedStringArray()
	var cur: Node = n
	while cur != null and cur != root_node:
		parts.append(String(cur.name))
		cur = cur.get_parent()
	parts.reverse()
	return "/".join(parts)
