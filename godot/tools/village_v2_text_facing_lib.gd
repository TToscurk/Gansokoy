extends RefCounted
## 字の向き監査の共通部（audit_village_v2_text_facing.gd／shot_village_v2_text_facing.gd／gate が使う）。
const TEXT_KEYS := ["nobori", "kanban", "andon", "fuda", "ichi_big", "sign", "plaque", "banner", "board_", "name_lantern",
	"kashihon", "chochin", "toban", "hanshi", "noren", "covers", "spines"]
const NOT_TEXT := ["noren_back", "sign_wood"]

var atlas_cache := {}

func atlas_for(tex_path: String) -> Dictionary:
	var d := tex_path.get_base_dir()
	if atlas_cache.has(d): return atlas_cache[d]
	var res := {}
	var p := d + "/atlas.json"
	if FileAccess.file_exists(p):
		var j = JSON.parse_string(FileAccess.get_file_as_string(p))
		if j is Dictionary and j.has("regions"):
			var size := float(j.get("size", 1.0))
			var regs := {}
			for k in j.regions:
				var name := String(k)
				var is_text := false
				for t in TEXT_KEYS: if name.contains(t): is_text = true
				for t in NOT_TEXT: if name == t: is_text = false
				if not is_text: continue
				var r: Array = j.regions[k]
				var s := 1.0
				for v in r: if float(v) > 1.0001: s = size
				if s == 1.0 and r.size() == 4 and float(r[2]) > 1.0001: s = size
				regs[name] = Rect2(float(r[0]) / s, float(r[1]) / s, (float(r[2]) - float(r[0])) / s, (float(r[3]) - float(r[1])) / s)
			res = {"regions": regs, "atlas": p}
	atlas_cache[d] = res
	return res

func mat_tex(mat: Material) -> Texture2D:
	if mat is BaseMaterial3D: return (mat as BaseMaterial3D).albedo_texture
	if mat is ShaderMaterial:
		for pn in ["albedo_texture", "texture_albedo", "albedo_tex", "tex"]:
			var t = (mat as ShaderMaterial).get_shader_parameter(pn)
			if t is Texture2D: return t
	return null

func mat_double(mat: Material) -> bool:
	if mat is BaseMaterial3D: return (mat as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader:
		return (mat as ShaderMaterial).shader.code.contains("cull_disabled")
	return false

func audit_mesh(mesh: Mesh, label: String, out: Dictionary, overrides: Array = []) -> void:
	for si in mesh.get_surface_count():
		var mat: Material = overrides[si] if si < overrides.size() and overrides[si] else mesh.surface_get_material(si)
		if mat == null: continue
		var tex := mat_tex(mat)
		if tex == null or tex.resource_path == "": continue
		var at := atlas_for(tex.resource_path)
		if at.is_empty() or (at.regions as Dictionary).is_empty(): continue
		var arr := mesh.surface_get_arrays(si)
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var N: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var UV: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var I = arr[Mesh.ARRAY_INDEX]
		if UV.is_empty(): continue
		var idx: PackedInt32Array = I if I != null and (I as PackedInt32Array).size() > 0 else PackedInt32Array(range(V.size()))
		var dbl := mat_double(mat)
		var faces := []   # [region, centroid, n, readable]
		for t in range(0, idx.size(), 3):
			var a := idx[t]; var b := idx[t + 1]; var c := idx[t + 2]
			var uc := (UV[a] + UV[b] + UV[c]) / 3.0
			var reg := ""
			for rn in at.regions:
				if (at.regions[rn] as Rect2).grow(0.0005).has_point(uc): reg = rn
			if reg == "": continue
			var e1 := V[b] - V[a]; var e2 := V[c] - V[a]
			var d1 := UV[b] - UV[a]; var d2 := UV[c] - UV[a]
			var det := d1.x * d2.y - d1.y * d2.x
			if absf(det) < 1e-12: continue
			var T := (e1 * d2.y - e2 * d1.y) / det
			var B := (e2 * d1.x - e1 * d2.x) / det
			var n := (N[a] + N[b] + N[c]).normalized() if N.size() == V.size() else e1.cross(e2).normalized()
			var s := T.cross(B).dot(n)
			var upside := absf(n.y) < 0.5 and B.normalized().y > 0.5
			faces.append([reg, (V[a] + V[b] + V[c]) / 3.0, n, s < 0.0, upside, e1.cross(e2).length() * 0.5])
		if faces.is_empty(): continue
		var key := label + "#" + str(si)
		var row := {"material": mat.resource_path, "double_sided": dbl, "regions": {}}
		for f in faces:
			var r: Dictionary = row.regions.get(f[0], {"readable": 0, "mirrored": 0, "upside_down": 0, "no_back_double": 0, "area_mirrored": 0.0})
			if f[3]: r.readable += 1
			else: r.mirrored += 1; r.area_mirrored += f[5]
			if f[4]: r.upside_down += 1
			if dbl:
				var has_back := false
				for g in faces:
					if g[0] == f[0] and (g[1] as Vector3).distance_to(f[1]) < 0.08 and (g[2] as Vector3).dot(f[2]) < -0.5: has_back = true; break
				if not has_back: r.no_back_double += 1
			row.regions[f[0]] = r
		out[key] = row

