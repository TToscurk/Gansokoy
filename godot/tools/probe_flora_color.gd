extends SceneTree
## 樹資產葉色實測：取每個 surface 的 albedo 貼圖平均色（略過近透明像素）。
## §0 禁止「過度櫻花化」、§5 要求中低飽和 —— 用數字挑掉紅／粉的變體，
## 不靠看截圖猜。
##
##   Godot --headless --path godot --script tools/probe_flora_color.gd

const LS := "res://assets/landscape/"
const NAT := "res://assets/nature/"

const CANDS := [
	LS + "大衫.glb", LS + "2大衫.glb", LS + "松樹.glb", LS + "普通樹.glb",
	LS + "針葉樹1.glb", LS + "針葉樹2glb.glb", LS + "針葉林樹3.glb", LS + "針葉林樹4.glb",
	NAT + "Pine_1.gltf", NAT + "Pine_2.gltf", NAT + "Pine_3.gltf",
	NAT + "Pine_4.gltf", NAT + "Pine_5.gltf",
	NAT + "CommonTree_1.gltf", NAT + "CommonTree_2.gltf", NAT + "CommonTree_3.gltf",
	NAT + "CommonTree_4.gltf", NAT + "CommonTree_5.gltf",
	NAT + "Bush_Common.gltf", NAT + "Bush_Common_Flowers.gltf",
	NAT + "Grass_Common_Short.gltf", NAT + "Grass_Common_Tall.gltf",
	NAT + "Grass_Wispy_Short.gltf", NAT + "Grass_Wispy_Tall.gltf",
	NAT + "Plant_1.gltf", NAT + "Plant_7.gltf",
	NAT + "Flower_3_Group.gltf", NAT + "Flower_4_Group.gltf",
	NAT + "Clover_1.gltf", NAT + "Fern_1.gltf",
]


func _init() -> void:
	print("[COL] %-22s %-22s %5s %5s %5s   H %5s  S %5s  V %5s  %s"
		% ["asset", "surface", "R", "G", "B", "色相", "飽和", "明度", "判定"])
	for p in CANDS:
		_one(p)
	quit(0)


func _one(path: String) -> void:
	if not ResourceLoader.exists(path):
		print("[COL] %-22s 不存在" % path.get_file())
		return
	var ps := load(path) as PackedScene
	var inst := ps.instantiate() as Node3D
	var label := path.get_file().get_basename()
	var seen := {}
	for m in _meshes(inst):
		var mi := m as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat == null:
				continue
			var key := "%s#%d" % [mi.name, s]
			if seen.has(key):
				continue
			seen[key] = true
			var tex := mat.albedo_texture
			var c := mat.albedo_color
			var src := "albedo_color"
			if tex != null:
				var img := tex.get_image()
				if img != null:
					c = _avg(img)
					src = tex.resource_path.get_file()
			var h := c.h * 360.0
			# 綠 = 色相 60-160；紅/粉 = <30 或 >330
			var verdict := "綠 OK"
			if c.s < 0.12:
				verdict = "低飽和/灰"
			elif h < 40.0 or h > 320.0:
				verdict = "★紅/粉 —— §0 禁過度櫻花化"
			elif h < 60.0:
				verdict = "黃橘（秋）"
			elif h > 180.0:
				verdict = "★偏藍青"
			print("[COL] %-22s %-22s %5.2f %5.2f %5.2f   %6.1f %6.2f %6.2f  %s"
				% [label, src.substr(0, 22), c.r, c.g, c.b, h, c.s, c.v, verdict])
	inst.free()


## 平均色：跳過 alpha < 0.5 的像素（葉片貼圖大半是透明的）
## ⚠ 匯入後的貼圖多半是 VRAM 壓縮格式，get_pixel() 會直接報錯，必須先 decompress()。
func _avg(src: Image) -> Color:
	var img := src
	if img.is_compressed():
		img = src.duplicate() as Image
		if img.decompress() != OK:
			return Color(0, 0, 0)
	var w := img.get_width()
	var hgt := img.get_height()
	var step := maxi(1, int(maxf(w, hgt) / 96.0))
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	for y in range(0, hgt, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			r += c.r; g += c.g; b += c.b
			n += 1
	if n == 0:
		return Color(0, 0, 0)
	return Color(r / n, g / n, b / n)


func _meshes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		o.append(n)
	for c in n.get_children():
		o.append_array(_meshes(c))
	return o
