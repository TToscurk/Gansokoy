extends SceneTree
## 量新 Tripo 樹的貼圖平均色（HSV），與舊 Meshy 版比較。
## probe_flora_color.gd 的同型檢查——判斷「樹看起來發黑」是貼圖本身暗，
## 還是場景光照造成。

const LS := "res://assets/landscape/"
const FILES := ["普通樹.glb", "大衫.glb", "2大衫.glb", "針葉樹1.glb",
	"針葉林樹3.glb", "針葉林樹4.glb", "盆樹.glb", "櫻花樹.glb", "楓樹.glb",
	"竹垣.glb", "鎮守之杜.glb"]

func _init() -> void:
	_run.call_deferred()

func _find_mat(node: Node) -> BaseMaterial3D:
	if node is MeshInstance3D and node.mesh != null:
		var m: Material = node.mesh.surface_get_material(0)
		if m == null:
			m = (node as MeshInstance3D).get_active_material(0)
		if m is BaseMaterial3D:
			return m
	for c in node.get_children():
		var r := _find_mat(c)
		if r != null:
			return r
	return null

func _run() -> void:
	print("%-14s %-7s %-7s %-7s  %s" % ["檔名", "H(度)", "S", "V", "備註"])
	for f in FILES:
		var path: String = LS + f
		if not ResourceLoader.exists(path):
			print("%-14s 缺檔" % f)
			continue
		var inst: Node = (load(path) as PackedScene).instantiate()
		var mat := _find_mat(inst)
		if mat == null:
			print("%-14s 取不到材質" % f)
			inst.free()
			continue
		var tex := mat.albedo_texture
		if tex == null:
			print("%-14s 無 albedo 貼圖，albedo_color=%s" % [f, str(mat.albedo_color)])
			inst.free()
			continue
		var img := tex.get_image()
		img.decompress()
		# 取樣：跳格掃描算平均，避開全透明像素
		var w := img.get_width()
		var h := img.get_height()
		var step: int = maxi(1, w / 96)
		var acc := Vector3.ZERO
		var n := 0
		for y in range(0, h, step):
			for x in range(0, w, step):
				var c := img.get_pixel(x, y)
				if c.a < 0.5:
					continue
				acc += Vector3(c.r, c.g, c.b)
				n += 1
		if n == 0:
			print("%-14s 全透明" % f)
			inst.free()
			continue
		var avg := acc / float(n)
		var col := Color(avg.x, avg.y, avg.z)
		print("%-14s %6.1f  %6.3f  %6.3f  %dx%d 取樣%d  albedo_color=%s"
			% [f, col.h * 360.0, col.s, col.v, w, h, n, str(mat.albedo_color)])
		inst.free()
	quit(0)
