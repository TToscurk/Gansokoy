extends SceneTree
## 圍牆選線的地面剖面：沿兩座鳥居兩側的候選牆線取樣，回報每一段該放的
## 高度、以及該線的地面起伏是否可接受。
##
##   Godot --headless --path godot --script tools/probe_wall_line.gd
##
## 為什麼要逐段量：圍牆是剛體長條，一段 11.2 m。地面沿線起伏若超過牆高的
## 三分之一（約 0.8 m），那一段就會一頭埋進土裡、另一頭浮空。與其事後手調
## 每一段的 Y，不如先量出剖面，讓每段各自貼合自己的地面。

const SEG_LEN := 11.20      # scale 5.9 的單段長度
const WALL_H := 2.41        # 牆高
## 兩座鳥居的實測位置（來自 b1_street.tscn，yaw=0 表示牆沿 X 展開）
const TORII_N := Vector3(235.33, 7.12, 102.05)
const TORII_S := Vector3(234.50, 6.14, -80.77)
## 鳥居本身的通道寬度：不能被牆封住。20 倍縮放的鳥居柱距實測約 10 m，
## 兩側各留 1 m 餘裕。
const GATE_HALF := 6.0


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
	var mask := 1 << 31   # 只看地形層，忽略建物

	for gate in [{"n": "北鳥居", "p": TORII_N}, {"n": "南鳥居", "p": TORII_S}]:
		var c: Vector3 = gate["p"]
		print("[LINE] ===== %s (%.1f, %.1f) 兩側牆線 =====" % [gate["n"], c.x, c.z])
		for side in [{"s": -1.0, "n": "西翼"}, {"s": 1.0, "n": "東翼"}]:
			var sgn: float = side["s"]
			print("[LINE] --- %s ---" % side["n"])
			print("[LINE] %4s %20s %9s %9s %9s %s" % [
				"段", "中心 (x, z)", "地面低", "地面高", "起伏", "建議"])
			for seg in range(3):
				# 從閘口外緣開始，一段一段往外排
				var x0: float = c.x + sgn * (GATE_HALF + seg * SEG_LEN)
				var x1: float = x0 + sgn * SEG_LEN
				var lo := 1e9
				var hi := -1e9
				var n := 12
				for i in range(n + 1):
					var x: float = lerpf(x0, x1, float(i) / float(n))
					var y := _ground(space, mask, x, c.z)
					if is_nan(y):
						continue
					lo = minf(lo, y)
					hi = maxf(hi, y)
				if lo > hi:
					print("[LINE] %4d %20s %s" % [seg + 1, "—", "無地面"])
					continue
				var rise := hi - lo
				var verdict := "✓ 平坦，直接放"
				if rise > WALL_H * 0.5:
					verdict = "✗ 起伏 > 半牆高，這段會露底/埋頭"
				elif rise > WALL_H / 3.0:
					verdict = "△ 需individually 調 Y 或改短段"
				print("[LINE] %4d %20s %9.2f %9.2f %9.2f %s" % [
					seg + 1, "(%.1f, %.1f)" % [(x0 + x1) * 0.5, c.z],
					lo, hi, rise, verdict])
				# 建議的擺放 Y：原點在幾何中心，所以是「地面 + 半牆高」
				print("[LINE]      → 建議 position = (%.2f, %.2f, %.2f)" % [
					(x0 + x1) * 0.5, lo + WALL_H * 0.5, c.z])

	print("[LINE] done")
	quit(0)


func _ground(space: PhysicsDirectSpaceState3D, mask: int, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, 80.0, z), Vector3(x, -60.0, z), mask)
	var hit := space.intersect_ray(q)
	return NAN if hit.is_empty() else hit["position"].y
