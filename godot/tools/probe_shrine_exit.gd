extends SceneTree
## 神社南出口現況探勘：主軸高程、走廊內植被、遠景高程、資產尺寸。只量不改。
## Godot --headless --path godot --script tools/probe_shrine_exit.gd

const HALF_W := 9.0     # 走廊半寬（含邊坡）
const Z0 := 40.0
const Z1 := 80.0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var scn: Node3D = load("res://maps/shrine/shrine.tscn").instantiate()
	root.add_child(scn)
	await process_frame
	# 主軸高程（Terrain + Vista）
	for nm in ["Terrain", "Vista"]:
		var mi: MeshInstance3D = scn.get_node(nm)
		var a: Array = mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var xf: Transform3D = mi.global_transform
		var line := "%s axis y @z: " % nm
		for z in range(40, 96, 4):
			var best := INF; var y := NAN
			for v in verts:
				var w: Vector3 = xf * v
				if absf(w.x) > 3.0: continue
				var d := absf(w.z - float(z))
				if d < best: best = d; y = w.y
			line += "%d:%.2f " % [z, y]
		print("PROFILE " + line)
		# 橫斷面 z=60
		line = "%s xsec z=60: " % nm
		for x in range(-30, 31, 5):
			var best := INF; var y := NAN
			for v in verts:
				var w: Vector3 = xf * v
				if absf(w.z - 60.0) > 3.0: continue
				var d := absf(w.x - float(x))
				if d < best: best = d; y = w.y
			line += "%d:%.2f " % [x, y]
		print("XSEC " + line)
		var bb: AABB = xf * mi.mesh.get_aabb()
		print("EXTENT %s %s verts=%d" % [nm, bb, verts.size()])
	# 走廊內節點（植被／石頭等），列出父群組計數
	var counts := {}
	var stack: Array = [scn]
	var listed := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and n.mesh != null and n.is_visible_in_tree():
			if n.name in ["Terrain", "Vista"]: continue
			var bb: AABB = n.global_transform * n.mesh.get_aabb()
			if bb.end.x > -HALF_W and bb.position.x < HALF_W and bb.end.z > Z0 and bb.position.z < Z1:
				# 找到帶編號的祖先（樹種_編號 或 群組）
				var p: Node = n
				while p.get_parent() != scn and p.get_parent().get_parent() != scn:
					p = p.get_parent()
				var key := String(p.get_parent().name) + "/" + String(p.name).rsplit("_", true, 1)[0]
				counts[key] = counts.get(key, 0) + 1
				if listed < 40:
					print("IN_CORRIDOR %s bb_min=(%.1f,%.1f,%.1f) size=(%.1f,%.1f,%.1f)" % [p.get_path(), bb.position.x, bb.position.y, bb.position.z, bb.size.x, bb.size.y, bb.size.z])
					listed += 1
		if n is MultiMeshInstance3D and n.multimesh != null:
			var mm: MultiMesh = n.multimesh
			var hits := 0
			for j in mm.instance_count:
				var p: Vector3 = n.global_transform * mm.get_instance_transform(j).origin
				if absf(p.x) < HALF_W and p.z > Z0 and p.z < Z1: hits += 1
			if hits > 0: print("MM_IN_CORRIDOR %s %d" % [n.get_path(), hits])
	print("CORRIDOR_COUNTS " + JSON.stringify(counts))
	# 樹幹（樹節點原點）真正踩進走廊的：|x| < 7、z 50–90
	var trunks: Array = []
	var tstack: Array = scn.get_node("植被").get_children()
	while not tstack.is_empty():
		var n: Node = tstack.pop_back()
		if not (n is Node3D):
			continue
		var parts := String(n.name).rsplit("_", true, 1)
		if not (parts.size() == 2 and parts[1].is_valid_int() and not (n is MeshInstance3D)):
			tstack.append_array(n.get_children())
			continue
		var p: Vector3 = (n as Node3D).global_position
		if absf(p.x) < 7.0 and p.z > 50.0 and p.z < 90.0:
			trunks.append({"path": String(scn.get_path_to(n)), "x": snappedf(p.x, 0.01), "y": snappedf(p.y, 0.01), "z": snappedf(p.z, 0.01)})
	print("TRUNKS_IN_CORRIDOR %d %s" % [trunks.size(), JSON.stringify(trunks)])
	# 標記與邊界
	for m in scn.get_node("標記").get_children():
		print("MARKER %s %s meta=%s" % [m.name, m.global_position, m.get_meta_list()])
	for c in scn.get_node("Boundary").get_children():
		print("BOUNDARY %s pos=%s size=%s" % [c.name, c.global_position, (c.shape as BoxShape3D).size])
	var torii: Node3D = scn.get_node("主鳥居")
	print("TORII pos=%s scale=%s" % [torii.global_position, torii.scale])
	# 資產
	for p in ["res://assets/models/stone_lantern.glb", "res://assets/shrine/博麗鳥居.glb", "res://assets/_lod/踏石.glb", "res://assets/_lod/平台石.glb", "res://assets/_lod/袖石垣.glb", "res://assets/_lod/收頭石.glb"]:
		var ps: PackedScene = load(p)
		if ps == null: print("ASSET %s LOAD_FAIL" % p); continue
		var inst: Node3D = ps.instantiate()
		var acc := AABB(); var has := false; var faces := 0; var mats := []
		var st: Array = [[inst, Transform3D.IDENTITY]]
		while not st.is_empty():
			var pr: Array = st.pop_back()
			var nn: Node = pr[0]; var xf2: Transform3D = pr[1]
			if nn != inst and nn is Node3D: xf2 = xf2 * (nn as Node3D).transform
			if nn is MeshInstance3D and nn.mesh != null:
				var b: AABB = xf2 * nn.mesh.get_aabb()
				acc = acc.merge(b) if has else b; has = true
				faces += nn.mesh.get_faces().size() / 3
				for si in nn.mesh.get_surface_count():
					var m: Material = nn.mesh.surface_get_material(si)
					mats.append(m.get_class() if m else "null")
					if m is BaseMaterial3D: mats.append("tex=" + str((m as BaseMaterial3D).albedo_texture != null))
			for c in nn.get_children(): st.push_back([c, xf2])
		print("ASSET %s size=(%.3f,%.3f,%.3f) min_y=%.3f faces=%d mats=%s" % [p, acc.size.x, acc.size.y, acc.size.z, acc.position.y, faces, mats])
		inst.free()
	quit(0)
