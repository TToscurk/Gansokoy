extends SceneTree
## 邊界勘查：玩家實際能跑多遠？現有的天然邊界在哪？風景往哪個方向看？
##
##   Godot --headless --path godot --script tools/probe_play_bounds.gd
##
## 為什麼不是直接放牆：使用者要的是「限制移動」，但牆會擋掉風景。這兩件事
## 只有在「牆是唯一的邊界手段」時才衝突。先量出地形自己在哪裡已經擋住人
## （陡坡、河、落差），就知道哪幾段其實不需要牆。

const RUN_OUT := 420.0   # 從村心往外掃多遠
const STEP := 3.0
## Yoriichi: r=0.3、可走坡度 52 度。超過這個角度的地面本身就是牆。
const WALK_LIMIT_DEG := 52.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := ResourceLoader.load("res://scenes/main.tscn", "PackedScene") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	main.load_map("slice", "")
	for i in 8:
		await physics_frame
	var space: PhysicsDirectSpaceState3D = main.map_root.get_world_3d().direct_space_state
	# 地形層：gen_ground_collision.gd 給地面/丘陵/護岸/水路加了 bit32（筆刷層），
	# 建物碰撞只有 layer 1。只查 bit32 就能把房子排除在外，量到純地形。
	var mask := 1 << 31

	# 村心：主街中段。但射線會打到建築屋頂，被誤判成「落差」。改用
	# 玩家實際站得到的高度來判斷：只有當地面本身陡到走不上去、或消失，
	# 才算天然邊界。建築另外用碰撞掃掠測，不混在一起。
	var heart := Vector3(235.0, 0.0, 10.0)
	print("[BOUND] 從村心 (235, 10) 向 16 個方位掃，找第一個「走不過去」的點")
	print("[BOUND] 判準：坡度 > %.0f 度、或沒有地面。" % WALK_LIMIT_DEG)
	print("[BOUND] ⚠ 只看 UnifiedGround/BasinHills 這類地形面，忽略建物屋頂——")
	print("[BOUND]   否則射線一打到屋頂就報「落差 5 m」，量到的是房子不是邊界。")
	print("[BOUND] %6s %10s %26s %s" % ["方位", "可走到", "阻擋點", "阻擋原因"])

	for i in 16:
		var ang := TAU * float(i) / 16.0
		var dir := Vector3(sin(ang), 0.0, cos(ang))
		var label := _compass(i)
		var prev_y := _ground(space, mask, heart)
		var blocked_at := -1.0
		var reason := ""
		var d := STEP
		while d <= RUN_OUT:
			var p := heart + dir * d
			var y := _ground(space, mask, p)
			if is_nan(y):
				blocked_at = d
				reason = "無地面（世界邊緣）"
				break
			var rise := absf(y - prev_y)
			var slope := rad_to_deg(atan2(rise, STEP))
			if slope > WALK_LIMIT_DEG:
				blocked_at = d
				reason = "地形坡度 %.0f 度（爬不上去）" % slope
				break
			prev_y = y
			d += STEP
		if blocked_at < 0.0:
			print("[BOUND] %6s %10s %26s %s" % [
				label, "%.0f m+" % RUN_OUT, "—", "★ 一路暢通，需要人工邊界"])
		else:
			var p := heart + dir * blocked_at
			print("[BOUND] %6s %10.0f m %26s %s" % [
				label, blocked_at, "(%.0f, %.0f)" % [p.x, p.z], reason])

	print("[BOUND] done")
	quit(0)


func _ground(space: PhysicsDirectSpaceState3D, mask: int, p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(p.x, 80.0, p.z), Vector3(p.x, -60.0, p.z), mask)
	var hit := space.intersect_ray(q)
	return NAN if hit.is_empty() else hit["position"].y


func _compass(i: int) -> String:
	return ["北", "北北東", "東北", "東北東", "東", "東南東", "東南", "南南東",
		"南", "南南西", "西南", "西南西", "西", "西北西", "西北", "北北西"][i]
