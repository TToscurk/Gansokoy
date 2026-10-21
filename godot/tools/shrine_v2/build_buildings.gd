extends SceneTree
## 建築包裝場景：把委製 GLB 包成可單獨開啟編輯的 .tscn（Model＋Collision）。
##   godot --headless --path godot --script res://tools/shrine_v2/build_buildings.gd [-- --only=haiden,temizuya --force]
## 產出 assets/shrine_v2/bld/<id>.tscn ＋ <id>_col.res（碰撞三角網，已減面，快取；--force 重算）。
## 碰撞減面沿用快速通道的做法：ImporterMesh.generate_lods 取低階 LOD，再頂點聚類到面數上限。

const OUT_DIR := "res://assets/shrine_v2/bld/"

# id: [glb, 縮放, 碰撞面數上限, 備註]
const BUILDINGS := {
	"haiden": ["res://assets/shrine/拜殿.glb", 9.0, 26000],
	"temizuya": ["res://assets/shrine/手水舍.glb", 3.2, 14000],
}

var _force := false


func _init() -> void:
	_run.call_deferred()


func _rel_xform(n: Node3D, anc: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != anc:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _lod_faces(glb: String, mx: Transform3D, ratio: float) -> PackedVector3Array:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(glb), st) != OK:
		return PackedVector3Array()
	var nodes: Array = st.get_nodes()
	var gm: Array = st.get_meshes()
	var out := PackedVector3Array()
	for ni in nodes.size():
		var nd: GLTFNode = nodes[ni]
		if nd.get_mesh() < 0:
			continue
		var xf := Transform3D.IDENTITY
		var k := ni
		while k >= 0:
			xf = (nodes[k] as GLTFNode).get_xform() * xf
			k = (nodes[k] as GLTFNode).get_parent()
		xf = mx * xf
		var im: ImporterMesh = (gm[nd.get_mesh()] as GLTFMesh).get_mesh()
		im.generate_lods(60.0, 25.0, [])
		for s in im.get_surface_count():
			if im.get_surface_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arr := im.get_surface_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var base_n := idx.size() if idx.size() > 0 else verts.size()
			for l in im.get_surface_lod_count(s):
				var li := im.get_surface_lod_indices(s, l)
				idx = li
				if li.size() <= base_n * ratio:
					break
			if idx.is_empty():
				for v in verts:
					out.append(xf * v)
			else:
				for i in idx:
					out.append(xf * verts[i])
	return out


func _cluster(faces: PackedVector3Array, cell: float) -> PackedVector3Array:
	var n := faces.size()
	var keys := PackedInt64Array()
	keys.resize(n)
	var slot := {}
	var sums := PackedVector3Array()
	var cnts := PackedInt32Array()
	var inv := 1.0 / cell
	for i in n:
		var v := faces[i]
		var k := ((floori(v.x * inv) + 1048576) << 42) | ((floori(v.y * inv) + 1048576) << 21) | (floori(v.z * inv) + 1048576)
		var s: int = slot.get(k, -1)
		if s < 0:
			s = sums.size()
			slot[k] = s
			sums.append(Vector3.ZERO)
			cnts.append(0)
		sums[s] += v
		cnts[s] += 1
		keys[i] = s
	for s in sums.size():
		sums[s] /= cnts[s]
	var out := PackedVector3Array()
	for t in range(0, n - 2, 3):
		var a := keys[t]
		var b := keys[t + 1]
		var c := keys[t + 2]
		if a == b or b == c or a == c:
			continue
		out.append(sums[a])
		out.append(sums[b])
		out.append(sums[c])
	return out


func _collision_faces(glb: String, model: Node3D, mx: Transform3D, max_tris: int) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var meshes: Array = model.find_children("*", "MeshInstance3D", true, false)
	if model is MeshInstance3D:
		meshes.append(model)
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		var xf := mx * _rel_xform(mi, model)
		for v in mi.mesh.get_faces():
			faces.append(xf * v)
	var full := faces.size() / 3
	if full > max_tris:
		var lod := _lod_faces(glb, mx, float(max_tris) / full)
		if lod.size() > 0:
			print("  碰撞減面 LOD：%d → %d" % [full, lod.size() / 3])
			faces = lod
		if faces.size() / 3 > max_tris:
			var area := 0.0
			for t in range(0, faces.size() - 2, 3):
				area += (faces[t + 1] - faces[t]).cross(faces[t + 2] - faces[t]).length() * 0.5
			var cell := clampf(sqrt(2.0 * area / max_tris), 0.05, 1.0)
			for attempt in 5:
				var cl := _cluster(faces, cell)
				if cl.size() / 3 <= max_tris or attempt == 4:
					print("  碰撞減面 聚類 %.3f m → %d 三角形" % [cell, cl.size() / 3])
					faces = cl
					break
				cell *= 1.35
	return faces


func _pack(w: Node, path: String) -> void:
	var pk := PackedScene.new()
	var e := pk.pack(w)
	var e2 := ResourceSaver.save(pk, path)
	print("[BLD] %s pack=%d save=%d" % [path, e, e2])


func _build(id: String, spec: Array) -> void:
	var glb: String = spec[0]
	var s: float = spec[1]
	var max_tris: int = spec[2]
	var src := load(glb) as PackedScene
	var model := src.instantiate() as Node3D
	var w := Node3D.new()
	w.name = id.capitalize()
	model.name = "Model"
	model.transform = Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3.ZERO)
	w.add_child(model)
	model.owner = w
	var colp := OUT_DIR + id + "_col.res"
	var shape: ConcavePolygonShape3D
	if not _force and ResourceLoader.exists(colp):
		shape = load(colp)
		print("  沿用碰撞快取 ", colp, " faces=", shape.get_faces().size() / 3)
	else:
		var mx := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3.ZERO)
		var faces := _collision_faces(glb, model, mx, max_tris)   # 已含縮放（聚類格寬單位＝公尺）
		shape = ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		ResourceSaver.save(shape, colp)
	var body := StaticBody3D.new()
	body.name = "Collision"
	w.add_child(body)
	body.owner = w
	var cs := CollisionShape3D.new()
	cs.name = "Trimesh"
	cs.shape = shape
	body.add_child(cs)
	cs.owner = w
	var bb := AABB()
	var first := true
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var b := model.transform * _rel_xform(mi, model) * mi.get_aabb()
		bb = b if first else bb.merge(b)
		first = false
	w.set_meta("aabb_pos", bb.position)
	w.set_meta("aabb_size", bb.size)
	w.set_meta("glb", glb)
	w.set_meta("scale", s)
	_pack(w, OUT_DIR + id + ".tscn")
	print("  %s  尺寸 %.2f x %.2f x %.2f m" % [id, bb.size.x, bb.size.y, bb.size.z])
	w.free()


func _build_torii() -> void:
	# 2026-10-22：9.6 → 7.4。9.6 倍時總高 7.17 m／外寬 9.58 m，比拜殿（高 6.1 m）還高，像紀念碑；
	# 7.4 倍＝總高 5.5 m、笠木寬 7.4 m、柱腳外緣 5.35 m，淨開口約 4.4 m，與 3.2 m 寬石階（含袖石 4.05 m）相稱。
	var s := 7.4
	var k := s / 9.6
	var src := load("res://assets/shrine/博麗鳥居.glb") as PackedScene
	var model := src.instantiate() as Node3D
	var w := Node3D.new()
	w.name = "Torii"
	model.name = "Model"
	model.transform = Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3.ZERO)
	w.add_child(model)
	model.owner = w
	var body := StaticBody3D.new()
	body.name = "Collision"
	w.add_child(body)
	body.owner = w
	# 柱心 ±0.2885 單位（×s）；柱腳外擴往上收成柱身（尺寸以 9.6 倍時的 1.35×0.8×1.7／R0.5×4.6 m 乘 k）
	for sx in [-1.0, 1.0]:
		var base := CollisionShape3D.new()
		base.name = "柱腳_" + ("L" if sx < 0 else "R")
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.35, 0.8, 1.7) * k
		base.shape = bs
		base.position = Vector3(sx * 0.2885 * s, 0.4 * k, 0.0)
		body.add_child(base)
		base.owner = w
		var shaft := CollisionShape3D.new()
		shaft.name = "柱身_" + ("L" if sx < 0 else "R")
		var cy := CylinderShape3D.new()
		cy.radius = 0.5 * k
		cy.height = 4.6 * k
		shaft.shape = cy
		shaft.position = Vector3(sx * 0.2885 * s, 3.1 * k, 0.0)
		body.add_child(shaft)
		shaft.owner = w
	w.set_meta("aabb_size", Vector3(0.998, 0.747, 0.193) * s)
	w.set_meta("scale", s)
	_pack(w, OUT_DIR + "torii.tscn")
	w.free()


func _build_orb() -> void:
	# 陰陽玉（彩蛋 LEVEL 3）：直徑 0.26 m，粗糙度由 GLB 材質決定；不做碰撞（拳頭大的小物）
	var src := load("res://assets/shrine/陰陽玉.glb") as PackedScene
	var model := src.instantiate() as Node3D
	var w := Node3D.new()
	w.name = "OnmyoDama"
	model.name = "Model"
	model.transform = Transform3D(Basis.from_scale(Vector3.ONE * 0.26), Vector3.ZERO)
	w.add_child(model)
	model.owner = w
	w.set_meta("easter_egg", "§25-27 LEVEL 3 實體陰陽玉，全圖僅此 1 顆。直徑 0.26 m（規格 0.18-0.35）。")
	_pack(w, OUT_DIR + "onmyoudama.tscn")
	w.free()


func _run() -> void:
	var only: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
		elif a == "--force":
			_force = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for id in BUILDINGS:
		if only.size() > 0 and not (id in only):
			continue
		print("[BLD] ", id)
		_build(id, BUILDINGS[id])
	if only.size() == 0 or "torii" in only:
		_build_torii()
	if only.size() == 0 or "orb" in only:
		_build_orb()
	quit()
