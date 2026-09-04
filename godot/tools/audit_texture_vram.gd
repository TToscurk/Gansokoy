extends SceneTree
## Texture / VRAM census for maps/slice. The mesh audits count triangles; this
## counts the other half of GPU memory — every Texture2D reachable from a
## material in the instantiated scene, ranked by decoded size.
##
## Decoded VRAM estimate: width × height × bytes/px × 1.33 (mipmaps). bytes/px
## depends on the import: 4 for uncompressed RGBA8, 1 for S3TC/BPTC (DXT5/BC7 =
## 1 byte/px, DXT1 = 0.5). We read the actual Image format off the texture,
## so a wrongly-imported uncompressed 8K shows as ~350 MB, not 90.
##
## Run: godot --headless --path godot --script tools/audit_texture_vram.gd

const SCENE := "res://maps/slice/slice.tscn"

var _seen := {}   # texture rid/path -> entry


func _init() -> void:
	var packed: PackedScene = load(SCENE)
	var root: Node = packed.instantiate()
	_walk(root)

	var rows: Array = _seen.values()
	rows.sort_custom(func(a, b): return a["bytes"] > b["bytes"])
	var total := 0
	var by_size := {}
	for r in rows:
		total += r["bytes"]
		var k := "%dx%d" % [r["w"], r["h"]]
		by_size[k] = by_size.get(k, 0) + 1

	print("=== maps/slice 貼圖 VRAM 普查 ===")
	print("  獨立貼圖 %d 張，估計 VRAM %s" % [rows.size(), _mb(total)])
	print("  尺寸分布: %s" % str(by_size))
	print("")
	print("%-56s %10s %14s %9s %5s" % ["貼圖", "尺寸", "格式", "VRAM", "用者"])
	for i in min(40, rows.size()):
		var r = rows[i]
		print("%-56s %5dx%-5d %14s %9s %5d" % [
			_short(r["path"]), r["w"], r["h"], r["fmt"], _mb(r["bytes"]), r["users"]])

	# Which top-level scene groups own the most texture bytes?
	print("\n--- 依場景群組（同一貼圖只算一次，歸給第一個用者）---")
	var by_group := {}
	for r in rows:
		by_group[r["group"]] = by_group.get(r["group"], 0) + r["bytes"]
	var gk := by_group.keys()
	gk.sort_custom(func(a, b): return by_group[a] > by_group[b])
	for g in gk:
		if by_group[g] < 1024 * 1024:
			continue
		print("  %-30s %s" % [String(g).substr(0, 30), _mb(by_group[g])])

	root.free()
	quit(0)


func _walk(n: Node, group: String = "") -> void:
	if n.get_parent() != null and n.get_parent().get_parent() == null:
		group = String(n.name)
	var mats: Array[Material] = []
	if n is GeometryInstance3D:
		var gi := n as GeometryInstance3D
		if gi.material_override != null:
			mats.append(gi.material_override)
		if gi.material_overlay != null:
			mats.append(gi.material_overlay)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s)
				if m != null:
					mats.append(m)
	elif n is MultiMeshInstance3D:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm != null and mm.mesh != null:
			for s in mm.mesh.get_surface_count():
				var m := mm.mesh.surface_get_material(s)
				if m != null:
					mats.append(m)
	for m in mats:
		_scan_material(m, group)
	for c in n.get_children():
		_walk(c, group)


func _scan_material(m: Material, group: String) -> void:
	var depth := 0
	while m != null and depth < 4:
		if m is BaseMaterial3D:
			var bm := m as BaseMaterial3D
			for slot in [
				BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_METALLIC,
				BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_EMISSION,
				BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_RIM,
				BaseMaterial3D.TEXTURE_CLEARCOAT, BaseMaterial3D.TEXTURE_FLOWMAP,
				BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION, BaseMaterial3D.TEXTURE_HEIGHTMAP,
				BaseMaterial3D.TEXTURE_SUBSURFACE_SCATTERING,
				BaseMaterial3D.TEXTURE_SUBSURFACE_TRANSMITTANCE,
				BaseMaterial3D.TEXTURE_BACKLIGHT, BaseMaterial3D.TEXTURE_REFRACTION,
				BaseMaterial3D.TEXTURE_DETAIL_MASK, BaseMaterial3D.TEXTURE_DETAIL_ALBEDO,
				BaseMaterial3D.TEXTURE_DETAIL_NORMAL, BaseMaterial3D.TEXTURE_ORM,
			]:
				_add(bm.get_texture(slot), group)
		elif m is ShaderMaterial:
			var sm := m as ShaderMaterial
			if sm.shader != null:
				for p in sm.shader.get_shader_uniform_list():
					var v = sm.get_shader_parameter(p["name"])
					if v is Texture2D:
						_add(v, group)
		m = m.next_pass
		depth += 1


func _add(t: Texture2D, group: String) -> void:
	if t == null:
		return
	var key := t.resource_path if not t.resource_path.is_empty() else str(t.get_instance_id())
	if _seen.has(key):
		_seen[key]["users"] += 1
		return
	var w := t.get_width()
	var h := t.get_height()
	var fmt := "?"
	var bpp := 4.0
	var img := t.get_image()
	if img != null:
		fmt = _fmt_name(img.get_format())
		bpp = _bpp(img.get_format())
	var bytes := int(float(w) * float(h) * bpp * 1.333)
	_seen[key] = {"path": key, "w": w, "h": h, "fmt": fmt, "bytes": bytes, "users": 1, "group": group}


func _bpp(f: int) -> float:
	match f:
		Image.FORMAT_DXT1, Image.FORMAT_BPTC_RGBF, Image.FORMAT_ETC2_RGB8, Image.FORMAT_ETC:
			return 0.5
		Image.FORMAT_DXT3, Image.FORMAT_DXT5, Image.FORMAT_BPTC_RGBA, Image.FORMAT_RGTC_RG, Image.FORMAT_ETC2_RGBA8, Image.FORMAT_ETC2_RA_AS_RG, Image.FORMAT_DXT5_RA_AS_RG:
			return 1.0
		Image.FORMAT_RGTC_R:
			return 0.5
		Image.FORMAT_L8, Image.FORMAT_R8:
			return 1.0
		Image.FORMAT_LA8, Image.FORMAT_RG8:
			return 2.0
		Image.FORMAT_RGB8:
			return 3.0
		Image.FORMAT_RGBA8, Image.FORMAT_RGBA4444, Image.FORMAT_RGB565:
			return 4.0
		Image.FORMAT_RGBAF, Image.FORMAT_RGBF:
			return 16.0
		Image.FORMAT_RGBAH, Image.FORMAT_RGBH:
			return 8.0
	return 4.0


func _fmt_name(f: int) -> String:
	match f:
		Image.FORMAT_DXT1: return "DXT1"
		Image.FORMAT_DXT5: return "DXT5"
		Image.FORMAT_BPTC_RGBA: return "BC7"
		Image.FORMAT_RGTC_RG: return "RGTC_RG"
		Image.FORMAT_RGBA8: return "RGBA8 未壓縮"
		Image.FORMAT_RGB8: return "RGB8 未壓縮"
		Image.FORMAT_L8: return "L8"
		Image.FORMAT_ETC2_RGBA8: return "ETC2"
	return "fmt%d" % f


func _short(p: String) -> String:
	var s := p.get_file()
	if s.is_empty():
		s = p
	if s.length() > 56:
		s = s.substr(s.length() - 56)
	return s


func _mb(b: int) -> String:
	return "%.1f MB" % (float(b) / 1048576.0)
