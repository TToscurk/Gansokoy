extends SceneTree
## 量每棵樹「底部帶」在 albedo 貼圖上實際採到的顏色，與樹幹帶比對。
## 目的：找出底部被畫上泥土／苔痕色塊的樹種。
##   底帶 = 最低 6% 高度的頂點，依其 UV 採樣 base_color
##   幹帶 = 25%~40% 高度的頂點，同樣採樣
## 泥土色 = 色相 20~45 度且明度明顯低於樹幹；苔痕 = 色相 70~150 度且低彩度。

const LS := "res://assets/landscape/"
const FILES := ["普通樹.glb", "大衫.glb", "2大衫.glb", "針葉樹1.glb",
	"針葉樹2glb.glb", "針葉林樹3.glb", "針葉林樹4.glb", "盆樹.glb",
	"櫻花樹.glb", "楓樹.glb", "松樹.glb", "鎮守之杜.glb", "竹垣.glb"]

var _img_cache: Dictionary = {}

func _init() -> void:
	_run.call_deferred()

func _gather(node: Node, xf: Transform3D, out: Array) -> void:
	var t := xf
	if node is Node3D:
		t = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var mat: Material = mesh.surface_get_material(s)
			if mat == null:
				mat = mi.get_active_material(s)
			var arr := mesh.surface_get_arrays(s)
			out.append({"xf": t, "arr": arr, "mat": mat})
	for c in node.get_children():
		_gather(c, t, out)

func _img_for(mat: Material) -> Image:
	if not (mat is BaseMaterial3D):
		return null
	var bm := mat as BaseMaterial3D
	var tex := bm.albedo_texture
	if tex == null:
		return null
	var key := tex.get_rid()
	if _img_cache.has(key):
		return _img_cache[key]
	var img := tex.get_image()
	if img != null:
		img.decompress()
	_img_cache[key] = img
	return img

func _sample(img: Image, uv: Vector2) -> Color:
	var w := img.get_width()
	var h := img.get_height()
	var x := int(fposmod(uv.x, 1.0) * float(w))
	var y := int(fposmod(uv.y, 1.0) * float(h))
	return img.get_pixel(clampi(x, 0, w - 1), clampi(y, 0, h - 1))

func _band_stats(surfaces: Array, ymin: float, h: float, lo_f: float, hi_f: float) -> Dictionary:
	var lo := ymin + h * lo_f
	var hi := ymin + h * hi_f
	var acc := Vector3.ZERO
	var n := 0
	var dirt := 0
	var moss := 0
	for s in surfaces:
		var img: Image = _img_for(s["mat"])
		if img == null:
			continue
		var arr: Array = s["arr"]
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uvs = arr[Mesh.ARRAY_TEX_UV]
		if uvs == null:
			continue
		var xf: Transform3D = s["xf"]
		for i in verts.size():
			var wp: Vector3 = xf * verts[i]
			if wp.y < lo or wp.y > hi:
				continue
			var c := _sample(img, uvs[i])
			if c.a < 0.5:
				continue
			acc += Vector3(c.r, c.g, c.b)
			n += 1
			var hue := c.h * 360.0
			if hue >= 15.0 and hue <= 50.0 and c.s > 0.15 and c.v < 0.55:
				dirt += 1
			elif hue >= 65.0 and hue <= 160.0 and c.s < 0.45 and c.v < 0.5:
				moss += 1
	if n == 0:
		return {"n": 0}
	var avg := acc / float(n)
	var col := Color(avg.x, avg.y, avg.z)
	return {"n": n, "h": col.h * 360.0, "s": col.s, "v": col.v,
		"dirt": 100.0 * float(dirt) / float(n), "moss": 100.0 * float(moss) / float(n)}

func _run() -> void:
	print("%-12s | %-24s | %-24s | %s" % ["檔名", "底帶 H/S/V  泥% 苔%", "幹帶 H/S/V  泥% 苔%", "判定"])
	for f in FILES:
		var path: String = LS + f
		if not ResourceLoader.exists(path):
			print("%-12s 缺檔" % f)
			continue
		var inst: Node = (load(path) as PackedScene).instantiate()
		var surfaces: Array = []
		_gather(inst, Transform3D.IDENTITY, surfaces)
		var ymin := INF
		var ymax := -INF
		for s in surfaces:
			var xf: Transform3D = s["xf"]
			for v in (s["arr"][Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var wp: Vector3 = xf * v
				ymin = minf(ymin, wp.y)
				ymax = maxf(ymax, wp.y)
		var h: float = ymax - ymin
		var b := _band_stats(surfaces, ymin, h, 0.0, 0.06)
		var t := _band_stats(surfaces, ymin, h, 0.25, 0.40)
		inst.free()
		if b.get("n", 0) == 0 or t.get("n", 0) == 0:
			print("%-12s 取樣不足 (底%d 幹%d)" % [f, b.get("n", 0), t.get("n", 0)])
			continue
		var dv: float = t["v"] - b["v"]
		var flags: Array = []
		if b["dirt"] > 25.0:
			flags.append("泥土%.0f%%" % b["dirt"])
		if b["moss"] > 25.0:
			flags.append("苔痕%.0f%%" % b["moss"])
		if dv > 0.12:
			flags.append("底比幹暗%.2f" % dv)
		var verdict: String = "乾淨" if flags.is_empty() else " / ".join(flags)
		print("%-12s | %5.0f %4.2f %4.2f %4.0f %4.0f | %5.0f %4.2f %4.2f %4.0f %4.0f | %s" % [
			f, b["h"], b["s"], b["v"], b["dirt"], b["moss"],
			t["h"], t["s"], t["v"], t["dirt"], t["moss"], verdict])
	quit()
