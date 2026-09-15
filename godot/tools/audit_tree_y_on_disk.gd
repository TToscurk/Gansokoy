extends SceneTree
## 直接讀磁碟上的 treemm_*.res，列出每棵樹的絕對 y。
## 不載入場景、不打射線——純粹回答「存到檔案裡的座標是多少」。

const NAMES := ["櫻花樹", "普通樹", "大衫", "2大衫", "針葉樹1",
	"針葉林樹3", "針葉林樹4", "盆樹"]

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var all: Array = []
	for n in NAMES:
		var p := "res://maps/slice/gen/treemm_%s.res" % n
		var mm := ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_IGNORE) as MultiMesh
		if mm == null:
			print("缺 %s" % n)
			continue
		var ys: Array = []
		# ⚠ headless 是 dummy renderer，get_instance_transform() 全回 0。
		# 產生器當初就是直接組 buffer 寫進去的，這裡也直接讀 buffer。
		# stride 12 = 3x4 矩陣列優先，origin 在 index 3 / 7 / 11。
		var buf: PackedFloat32Array = mm.buffer
		for i in mm.instance_count:
			var o: int = i * 12
			var pos := Vector3(buf[o + 3], buf[o + 7], buf[o + 11])
			ys.append(pos.y)
			all.append([pos.y, n, i, pos])
		ys.sort()
		print("%-10s n=%3d  y 最低 %8.2f  中位 %8.2f  最高 %8.2f"
			% [n, ys.size(), ys[0], ys[ys.size() / 2], ys[ys.size() - 1]])

	all.sort_custom(func(a, b): return a[0] > b[0])
	print("\n=== y 最高的 15 棵（疑似浮空） ===")
	for i in mini(15, all.size()):
		var w: Array = all[i]
		var o: Vector3 = w[3]
		print("  %-10s #%-3d y=%8.2f  @ (%.1f, %.1f)" % [w[1], w[2], w[0], o.x, o.z])
	print("\n=== y 最低的 5 棵 ===")
	for i in range(maxi(0, all.size() - 5), all.size()):
		var w: Array = all[i]
		var o: Vector3 = w[3]
		print("  %-10s #%-3d y=%8.2f  @ (%.1f, %.1f)" % [w[1], w[2], w[0], o.x, o.z])
	quit(0)
