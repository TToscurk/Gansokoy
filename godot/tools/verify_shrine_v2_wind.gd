extends SceneTree
## 博麗神社 v2 候選 × 風力：真實視窗（非 headless）逐像素量樹冠在「開風／關風」的畫面變化。
##   godot --path godot --resolution 1280x720 --script res://tools/verify_shrine_v2_wind.gd
## A) 接線：載圖後 Wind.veg_stats() 的物種計數、wind_sp 已寫入的樹 mesh 數、未對到物種表（→ rigid）的名稱。
## B) GPU 真值：同一鏡位連拍兩張（間隔 0.8 s 實時間）；風開（Strong Gust）→ 樹冠區平均絕對差；風關 → 同區差。
##    開風差必須明顯大於關風差（>3 倍且 >0.4 灰階），否則判定樹沒有被風推動。

const SHOT := {"cam": [-8.0, 0.0, -14.0], "look": [-30.0, 0.0, -34.0]}
var fails := 0


func _init() -> void:
	_run.call_deferred()


func check(label: String, ok: bool) -> void:
	print("[WIND2] %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _grab() -> Image:
	return root.get_texture().get_image()


func _diff(a: Image, b: Image, r: Rect2i) -> float:
	var s := 0.0
	var n := 0
	for y in range(r.position.y, r.end.y, 2):
		for x in range(r.position.x, r.end.x, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			s += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
			n += 1
	return s / float(maxi(n, 1)) * 255.0


func _run() -> void:
	var wind: Node = root.get_node("/root/Wind")
	var world := Node3D.new()
	root.add_child(world)
	var scene := (load("res://maps/shrine_v2/shrine_v2.tscn") as PackedScene).instantiate()
	world.add_child(scene)
	await _frames(10)
	# 地面高度：先放一次相機，用 S2 資料不方便 → 以場景裡的物理射線（沒有碰撞體時退回 y_c）
	var g := 8.32
	var cam := Camera3D.new()
	cam.far = 3000.0
	world.add_child(cam)
	cam.current = true
	var c: Array = SHOT["cam"]
	var l: Array = SHOT["look"]
	cam.global_position = Vector3(c[0], g + 1.7, c[2])
	cam.look_at(Vector3(l[0], g + 11.0, l[2]), Vector3.UP)

	# ── A) 接線 ──
	var st: Dictionary = wind.veg_stats()
	var sp: Dictionary = st["species"]
	var wired := 0
	for k in sp.keys():
		wired += int(sp[k])
	print("[WIND2]   物種計數 %s；未對到物種表（→ rigid）：%s" % [str(sp), str(st["unknown"])])
	var tree_meshes := 0
	var tree_wired := 0
	for n in scene.get_node("樹木").find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		tree_meshes += 1
		var v: Variant = mi.get_instance_shader_parameter("wind_sp")
		if v is Vector4 and (v as Vector4).x >= 0.0:
			tree_wired += 1
	check("A 樹 mesh 全部接線（wind_sp 已寫入）：%d/%d" % [tree_wired, tree_meshes], tree_meshes > 0 and tree_wired == tree_meshes)
	check("A 物種表有計數（共 %d 個 mesh 接線）" % wired, wired >= tree_meshes)

	# ── B) GPU 真值 ──
	var rect := Rect2i(0, 40, 1280, 360)      # 畫面上半部：樹冠與天空
	wind.set_enabled(true)
	wind.set_preset(3)                         # Strong Gust
	await _frames(240)                         # 讓風場長起來
	var a1 := _grab()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 800:
		await process_frame
	var a2 := _grab()
	var d_on := _diff(a1, a2, rect)
	wind.set_enabled(false)
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 3500:   # 關風是 0.45 s 淡出 + 閘門清空，給足時間
		await process_frame
	var b1 := _grab()
	var t2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < 800:
		await process_frame
	var b2 := _grab()
	var d_off := _diff(b1, b2, rect)
	print("[WIND2]   樹冠區平均絕對差：風開 %.3f／關 %.3f（0–255 灰階）" % [d_on, d_off])
	check("B 風開時樹冠隨風變化（差 %.3f 大於關風差 %.3f 的 3 倍且 >0.4）" % [d_on, d_off], d_on > d_off * 3.0 and d_on > 0.4)
	b1.save_png("D:/神社/shrine/_review/shrine_v2/wind_off.png")
	a2.save_png("D:/神社/shrine/_review/shrine_v2/wind_on.png")
	print("[WIND2] failures=%d" % fails)
	quit(fails)
