extends SceneTree
## 白石磚候選貼圖體檢：平均色、是否夠白、單塊石在貼圖裡佔多大。
## 概念圖要「白色～淡灰、略帶青苔污漬」，單塊 0.6-1.2 × 0.4-0.8 m。
##
##   Godot --headless --path godot --script tools/probe_paving_texture.gd

const CANDS := ["stone_flag", "ishizumi", "stone_wall"]


func _init() -> void:
	for c in CANDS:
		_one(c)
	for c in ["res://assets/shrine/袖石垣_Baked_BaseColor.png",
			"res://assets/shrine/踏石_Baked_BaseColor.png",
			"res://assets/shrine/收頭石_Baked_BaseColor.png"]:
		_one(c)
	quit(0)


func _one(name: String) -> void:
	var path := "res://assets/textures/%s_diff.jpg" % name
	if name.begins_with("res://"):
		path = name
	if not ResourceLoader.exists(path):
		print("[TEX] %-12s 不存在" % name)
		return
	var tex := load(path) as Texture2D
	var img := tex.get_image()
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var step := maxi(1, int(maxf(w, h) / 128.0))
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	var lo := 1.0
	var hi := 0.0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			r += c.r; g += c.g; b += c.b
			n += 1
			var l := c.get_luminance()
			lo = minf(lo, l)
			hi = maxf(hi, l)
	var avg := Color(r / n, g / n, b / n)
	# 要多亮才算「白色～淡灰」：亮度 > 0.55 且飽和 < 0.15
	var white_ok := avg.get_luminance() > 0.5 and avg.s < 0.18
	print("[TEX] %-42s %dx%d  平均 %.2f %.2f %.2f  亮度 %.2f  飽和 %.2f  範圍 %.2f-%.2f  %s"
		% [name.get_file(), w, h, avg.r, avg.g, avg.b, avg.get_luminance(), avg.s, lo, hi,
			"✓ 白/淡灰" if white_ok else "✗ 偏暗或偏色（需 tint 提亮）"])
