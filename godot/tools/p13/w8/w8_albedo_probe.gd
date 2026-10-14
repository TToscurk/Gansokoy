extends SceneTree
## P13 W8 TASK B 診断（唯読）：町家 Kit の LOD0／LOD1／LOD2 について、『現に効いている材質』の albedo（線形）を面積加重で類別平均する。
##   godot --path . --resolution 320x180 --script res://tools/p13/w8/w8_albedo_probe.gd -- <out.json> <group> [id,id,…]
##   group：batch（W7 第一批 50）／main（W2 主街 39）／pilot（R6a 24）／ids（引数で指定）
## 類：plaster／wood／kawara／stone（StandardMaterial3D：albedo_color × 質感平均 × 頂点色）／atlas_light／atlas_mid／atlas_dark（V2_MachiyaKit〔K 版〕＝atlas 画素 × 頂点色 × s2l(k)。k は kit_cal.gdshader と同じ帯分類）
## 出力：building → LOD → class → {area, rgb(linear)}。頂点色は線形として扱う（vertex_color_is_srgb=false）。質感の平均は原画像ファイルから（import に依存しない）。
const SCENE := "res://maps/village_v2/village_v2.tscn"
const ATLAS := "res://assets/village_v2/machiya_kit/machiya_kit_atlas.png"

var _tex_mean := {}
var _atlas: Image
var _kcal := {"k_dark": 0.75, "k_mid": 0.42, "k_light": 0.70, "bd": Vector2(0.26, 0.34), "bl": Vector2(0.55, 0.70)}


func _init() -> void:
	_run.call_deferred()


func _s2l(c: float) -> float:
	return c / 12.92 if c < 0.04045 else pow((c + 0.055) / 1.055, 2.4)


func _l2s(c: float) -> float:
	return c * 12.92 if c < 0.0031308 else 1.055 * pow(c, 1.0 / 2.4) - 0.055


func _lin(c: Color) -> Vector3:
	return Vector3(_s2l(c.r), _s2l(c.g), _s2l(c.b))


func _smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## 画像ファイルの平均色（線形）。ファイルは import に依存せず直接読む
func _mean_of(res_path: String) -> Vector3:
	if _tex_mean.has(res_path):
		return _tex_mean[res_path]
	var img := Image.load_from_file(ProjectSettings.globalize_path(res_path))
	var v := Vector3(0.5, 0.5, 0.5)
	if img != null:
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		var sx := maxi(1, w / 64)
		var sy := maxi(1, h / 64)
		var s := Vector3.ZERO
		var n := 0
		for y in range(0, h, sy):
			for x in range(0, w, sx):
				s += _lin(img.get_pixel(x, y))
				n += 1
		v = s / float(n)
	_tex_mean[res_path] = v
	return v


## atlas の UV 範囲（bbox）の平均画素（sRGB でなく線形）
func _atlas_px(uv0: Vector2, uv1: Vector2, uv2: Vector2) -> Vector3:
	var w := _atlas.get_width()
	var h := _atlas.get_height()
	var mn := Vector2(minf(uv0.x, minf(uv1.x, uv2.x)), minf(uv0.y, minf(uv1.y, uv2.y)))
	var mx := Vector2(maxf(uv0.x, maxf(uv1.x, uv2.x)), maxf(uv0.y, maxf(uv1.y, uv2.y)))
	mn = mn.clamp(Vector2.ZERO, Vector2.ONE)
	mx = mx.clamp(Vector2.ZERO, Vector2.ONE)
	var x0 := int(mn.x * (w - 1))
	var x1 := int(mx.x * (w - 1))
	var y0 := int(mn.y * (h - 1))
	var y1 := int(mx.y * (h - 1))
	var stepx := maxi(1, (x1 - x0) / 8)
	var stepy := maxi(1, (y1 - y0) / 8)
	var s := Vector3.ZERO
	var n := 0
	var y := y0
	while y <= y1:
		var x := x0
		while x <= x1:
			s += _lin(_atlas.get_pixel(x, y))
			n += 1
			x += stepx
		y += stepy
	return s / float(maxi(1, n))


func _material_for(mi: MeshInstance3D, si: int) -> Material:
	var m: Material = mi.get_surface_override_material(si)
	if m == null:
		m = mi.material_override
	if m == null and mi.mesh != null:
		m = mi.mesh.surface_get_material(si)
	return m


func _cls_of_std(m: StandardMaterial3D) -> String:
	var n := (m.resource_name + " " + m.resource_path).to_lower()
	if n.contains("plaster"):
		return "plaster"
	if n.contains("wood"):
		return "wood"
	if n.contains("kawara"):
		return "kawara"
	if n.contains("stone"):
		return "stone"
	return "other_std"


func _accumulate(acc: Dictionary, cls: String, area: float, rgb: Vector3, mname: String = "") -> void:
	if not acc.has(cls):
		acc[cls] = {"area": 0.0, "sum": Vector3.ZERO, "mats": {}}
	if mname != "":
		acc[cls]["mats"][mname] = true
	acc[cls]["area"] += area
	acc[cls]["sum"] += rgb * area


func _prefix(n: String) -> String:
	var r := ""
	for ch in n:
		if ch.is_valid_int() or ch == "_" and r.length() > 0 and r.ends_with("_"):
			break
		r += ch
	return r.rstrip("_")


func _scan_lod(lod: Node) -> Dictionary:
	var acc := {}
	var pacc := {}
	for g in lod.find_children("*", "MeshInstance3D", true, false):
		var mi := g as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var m := _material_for(mi, si)
			var arr := mi.mesh.surface_get_arrays(si)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR] if arr[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var ntri := (idx.size() if idx.size() > 0 else vs.size()) / 3
			var std := m as StandardMaterial3D
			var sh := m as ShaderMaterial
			var pfx := _prefix(String(mi.name))
			var std_base := Vector3.ONE
			var cls_std := ""
			if std != null:
				cls_std = _cls_of_std(std)
				var tm := Vector3.ONE
				if std.albedo_texture != null:
					tm = _mean_of(std.albedo_texture.resource_path)
				std_base = _lin(std.albedo_color) * tm
			for t in ntri:
				var i0 := idx[t * 3] if idx.size() > 0 else t * 3
				var i1 := idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1
				var i2 := idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2
				var area := ((vs[i1] - vs[i0]).cross(vs[i2] - vs[i0])).length() * 0.5
				if area <= 0.0:
					continue
				var col := Vector3.ONE
				if cs.size() > 0:
					var c0 := cs[i0]
					var c1 := cs[i1]
					var c2 := cs[i2]
					col = Vector3((c0.r + c1.r + c2.r) / 3.0, (c0.g + c1.g + c2.g) / 3.0, (c0.b + c1.b + c2.b) / 3.0)
				if std != null:
					var vc := col if std.vertex_color_use_as_albedo else Vector3.ONE
					_accumulate(acc, cls_std, area, std_base * vc, (std.resource_name if std.resource_name != "" else std.resource_path.get_file()))
					_accumulate(pacc, pfx + "|" + cls_std, area, std_base * vc)
				elif sh != null and uvs.size() > 0:
					var px := _atlas_px(uvs[i0], uvs[i1], uvs[i2])
					var base := Vector3(px.x * col.x, px.y * col.y, px.z * col.z)
					var l := _l2s(base.dot(Vector3(0.2126, 0.7152, 0.0722)))
					var k := lerpf(_kcal["k_dark"], _kcal["k_mid"], _smooth(_kcal["bd"].x, _kcal["bd"].y, l))
					k = lerpf(k, _kcal["k_light"], _smooth(_kcal["bl"].x, _kcal["bl"].y, l))
					var cls := "atlas_light" if l >= 0.45 else ("atlas_dark" if l < 0.30 else "atlas_mid")
					_accumulate(acc, cls, area, base * _s2l(k))
					_accumulate(pacc, pfx + "|" + cls, area, base * _s2l(k))
	var out := {}
	for cls: String in acc:
		var a: float = acc[cls]["area"]
		var s: Vector3 = acc[cls]["sum"] / a
		out[cls] = {"area": snappedf(a, 0.01), "rgb": [snappedf(s.x, 0.0001), snappedf(s.y, 0.0001), snappedf(s.z, 0.0001)], "mats": acc[cls]["mats"].keys()}
	var po := {}
	for key: String in pacc:
		var a2: float = pacc[key]["area"]
		var s2: Vector3 = pacc[key]["sum"] / a2
		po[key] = [snappedf(a2, 0.01), snappedf(s2.x, 0.0001), snappedf(s2.y, 0.0001), snappedf(s2.z, 0.0001)]
	out["_parts"] = po
	return out


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := String(args[0])
	var group := String(args[1])
	_atlas = Image.load_from_file(ProjectSettings.globalize_path(ATLAS))
	_atlas.convert(Image.FORMAT_RGBA8)
	var ids: Array = []
	if group == "ids":
		ids = String(args[2]).split(",", false)
	else:
		var root_dir := ProjectSettings.globalize_path("res://")
		var f: String = {"batch": "data/village_v2_p13w7_batch1.json", "main": "data/village_v2_p13_mainstreet.json"}.get(group, "")
		if f != "":
			var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root_dir + f))
			for b: Dictionary in d["buildings"]:
				ids.append(String(b["id"]))
		else:
			var d2: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/village_v2/kit_cal_p10/kit_material_variants.json"))
			for p: String in d2["pilot_buildings"]:
				ids.append(p.get_file())
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 8:
		await process_frame
	var res := {}
	for id: String in ids:
		var b := v.get_node("Districts").find_child(id, true, false)
		if b == null:
			continue
		var kit := b.get_node_or_null("Kit")
		if kit == null:
			continue
		var per := {}
		for k in 3:
			per["L%d" % k] = _scan_lod(kit.get_node("LOD%d" % k))
		res[id] = per
	var f2 := FileAccess.open(out_path, FileAccess.WRITE)
	f2.store_string(JSON.stringify({"group": group, "n": res.size(), "buildings": res}, "\t") + "\n")
	f2.close()
	print("[W8B] ", group, " 棟数 ", res.size(), " → ", out_path)
	quit(0)
