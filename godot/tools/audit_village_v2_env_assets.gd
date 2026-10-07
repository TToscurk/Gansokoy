extends SceneTree
## P9 R5-4 Existing Asset Environment Pass：環境資產盤點（唯讀；不改任何資產、不寫場景）。
##   量測：Godot --headless --path godot --script res://tools/audit_village_v2_env_assets.gd -- --out=<json>
##   縮圖：Godot --path godot --script ... -- --out=<json> --thumbs=<dir>（非 headless；SubViewport 隔離世界）
## 對象：assets/ 下的既有 GLB／glTF（舊 kit・CC0 包・Tripo／委製）＋ assets/village_v2/<kit>/mesh 的 LOD0 模組。
## 量測項：三角面、材質數、碰撞節點、世界 AABB 尺寸（m）、原點高度、是否帶 LOD1。
## 資產本體一律只讀（ResourceLoader 讀取＋instantiate 到孤立 SubViewport，結束即釋放）。

const LEGACY_DIRS := ["res://assets/lowpoly_scene", "res://assets/nature", "res://assets/market", "res://assets/riverbank",
	"res://assets/landscape", "res://assets/_incoming/gobkit_nature", "res://assets/models", "res://assets/landmark",
	"res://assets/bridges", "res://assets/shrine", "res://assets/machiya", "res://assets/vista"]
const KITS := ["street_kit", "market_kit", "mise_kit", "kiri_kit", "geidon_kit", "suzu_kit", "school_kit", "tower_kit",
	"waterside_kit", "garden_kit", "riverbank_kit", "bamboo_kit", "veg_kit"]
const TH := 224

var out_rows: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ""
	var thumbs := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--usage="):
			# 既存 overlay（maps/village_v2/gen/*.scn）がどの kit 模組を參照しているか（依存の直接列挙、唯讀）
			var use := {}
			for f in _files("res://maps/village_v2/gen", ["scn", "tscn"]):
				for dep: String in ResourceLoader.get_dependencies(f):
					var p := dep.split("::")[-1] if dep.contains("::") else dep
					if p.begins_with("res://assets/"):
						if not use.has(p):
							use[p] = []
						(use[p] as Array).append(f.get_file())
			var fu := FileAccess.open(a.trim_prefix("--usage="), FileAccess.WRITE)
			fu.store_string(JSON.stringify(use, " "))
			fu.close()
			print("[AUDIT] usage %d 件" % use.size())
			quit(0)
			return
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--thumbs="):
			thumbs = a.trim_prefix("--thumbs=")
	var vp: SubViewport = null
	var cam: Camera3D = null
	var holder: Node3D = null
	if thumbs != "":
		DirAccess.make_dir_recursive_absolute(thumbs)
		vp = SubViewport.new()
		vp.size = Vector2i(TH, TH)
		vp.own_world_3d = true
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.62, 0.66, 0.70)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.75, 0.78, 0.82)
		e.ambient_light_energy = 0.55
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.environment = e
		vp.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, -35, 0)
		sun.light_energy = 1.25
		vp.add_child(sun)
		cam = Camera3D.new()
		cam.fov = 28.0
		cam.far = 2000.0
		vp.add_child(cam)
		holder = Node3D.new()
		vp.add_child(holder)
	# 舊 kit／外部包
	for d: String in LEGACY_DIRS:
		for f in _files(d, ["glb", "gltf"]):
			var row := {"src": f, "group": d.get_file(), "kind": "legacy"}
			var ps := load(f) as PackedScene
			if ps == null:
				row["error"] = "load failed"
				out_rows.append(row)
				continue
			var n := ps.instantiate()
			_measure(n, row)
			if vp:
				await _thumb(vp, cam, holder, n, row, thumbs)
			else:
				n.free()
			out_rows.append(row)
	# V2 kit（LOD0 のみ）
	for k: String in KITS:
		var md := "res://assets/village_v2/%s/mesh" % k
		for f in _files(md, ["res"]):
			if f.get_basename().ends_with("_l1") or f.get_basename().ends_with("_l2") or f.get_basename().ends_with("_l3"):
				continue
			var m := load(f) as Mesh
			var row := {"src": f, "group": k, "kind": "v2_kit"}
			if m == null:
				row["error"] = "not a Mesh"
				out_rows.append(row)
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = m
			_measure(mi, row)
			row["lod1"] = ResourceLoader.exists(f.get_basename() + "_l1.res")
			if vp:
				await _thumb(vp, cam, holder, mi, row, thumbs)
			else:
				mi.free()
			out_rows.append(row)
	if out != "":
		var fa := FileAccess.open(out, FileAccess.WRITE)
		fa.store_string(JSON.stringify(out_rows, " "))
		fa.close()
	print("[AUDIT] %d 件 → %s" % [out_rows.size(), out])
	quit(0)


func _files(d: String, exts: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var stack := [d]
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		var da := DirAccess.open(cur)
		if da == null:
			continue
		for sub in da.get_directories():
			if not FileAccess.file_exists(cur.path_join(sub).path_join(".gdignore")):
				stack.append(cur.path_join(sub))
		for f in da.get_files():
			if f.get_extension().to_lower() in exts:
				out.append(cur.path_join(f))
	out.sort()
	return out


func _measure(n: Node, row: Dictionary) -> void:
	var tris := 0
	var mats := {}
	var aabb := AABB()
	var first := true
	var meshes := 0
	var nodes: Array = [n] + n.find_children("*", "", true, false)
	var col := 0
	for c in nodes:
		if c is CollisionShape3D or c is CollisionPolygon3D:
			col += 1
		if not (c is MeshInstance3D) or (c as MeshInstance3D).mesh == null:
			continue
		var mi := c as MeshInstance3D
		meshes += 1
		var m := mi.mesh
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			tris += (idx.size() if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			var mat := mi.get_surface_override_material(s)
			if mat == null:
				mat = m.surface_get_material(s)
			if mat != null:
				mats[mat.resource_path if mat.resource_path != "" else str(mat.get_instance_id())] = true
		var xf := _xf_to(mi, n)
		var b := xf * m.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	row["tris"] = tris
	row["meshes"] = meshes
	row["materials"] = mats.size()
	row["collision"] = col
	row["size"] = [snappedf(aabb.size.x, 0.01), snappedf(aabb.size.y, 0.01), snappedf(aabb.size.z, 0.01)]
	row["min_y"] = snappedf(aabb.position.y, 0.01)


func _xf_to(c: Node, top: Node) -> Transform3D:
	# c から top（含む）までの局所 transform を積む（ツリー外でも使える）
	var xf := Transform3D.IDENTITY
	var cur := c
	while cur != null:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		if cur == top:
			break
		cur = cur.get_parent()
	return xf


func _thumb(vp: SubViewport, cam: Camera3D, holder: Node3D, n: Node, row: Dictionary, dir: String) -> void:
	holder.add_child(n)
	var s: Array = row["size"]
	var sz := Vector3(float(s[0]), float(s[1]), float(s[2]))
	var c := Vector3(0, float(row["min_y"]) + sz.y * 0.5, 0)
	# AABB 中心（x/z）を求め直す：ノード配置後のワールド AABB
	var ab := AABB()
	var first := true
	for mi in ([n] + n.find_children("*", "MeshInstance3D", true, false)):
		if mi is MeshInstance3D and (mi as MeshInstance3D).mesh != null:
			var b := (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).mesh.get_aabb()
			ab = b if first else ab.merge(b)
			first = false
	if not first:
		c = ab.get_center()
		sz = ab.size
	var r := maxf(0.15, sz.length() * 0.5)
	var dist := r / sin(deg_to_rad(cam.fov * 0.5)) * 1.05
	var dirv := Vector3(0.62, 0.42, 0.66).normalized()
	cam.global_transform = Transform3D(Basis(), c + dirv * dist).looking_at(c, Vector3.UP)
	cam.near = maxf(0.01, dist - r * 2.0)
	for i in 3:
		await process_frame
	var img := vp.get_texture().get_image()
	var fn := String(row["group"]) + "__" + String(row["src"]).get_file().get_basename()
	fn = fn.replace(" ", "_")
	img.save_png(dir.path_join(fn + ".png"))
	row["thumb"] = fn + ".png"
	holder.remove_child(n)
	n.queue_free()
