extends SceneTree
## P13 W7 診断（唯読）：FarmlandTerrain の頂点属性（COLOR=trodden/gravel/mud/rock、UV=forest/farm、UV2=wet/street）を
## 指定矩形で表にする。RoadBaseP10 適用後（現行）と元の mesh（enabled=false）の両方。
##   godot --headless --path . --script res://tools/p13/w7/w7_probe_terrain.gd -- <cx> <cz> <half> [chan]
## chan＝r|g|b|a|fx|fy|wx|wy（既定 r）。格子 2 m の値を行 z・列 x に並べる。
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _grid(mesh: ArrayMesh, xf: Transform3D, cx: float, cz: float, half: float, chan: String) -> Dictionary:
	var arr := mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var g := {}
	for i in vs.size():
		var w := xf * vs[i]
		if absf(w.x - cx) > half or absf(w.z - cz) > half:
			continue
		var val := 0.0
		match chan:
			"r": val = cs[i].r
			"g": val = cs[i].g
			"b": val = cs[i].b
			"a": val = cs[i].a
			"fx": val = uv[i].x
			"fy": val = uv[i].y
			"wx": val = uv2[i].x
			"wy": val = uv2[i].y
		g[Vector2i(roundi(w.x * 10.0), roundi(w.z * 10.0))] = [val, w.y]
	return g


func _print(g: Dictionary, label: String) -> void:
	var xs := {}
	var zs := {}
	for k: Vector2i in g.keys():
		xs[k.x] = true
		zs[k.y] = true
	var xl := xs.keys()
	xl.sort()
	var zl := zs.keys()
	zl.sort()
	print("[W7P] ", label, "  (列 x / 行 z、値×100)")
	var hdr := "z\\x    "
	for x in xl:
		hdr += "%6.1f" % (float(x) / 10.0)
	print("[W7P] ", hdr)
	for z in zl:
		var line := "%6.1f " % (float(z) / 10.0)
		for x in xl:
			var key := Vector2i(x, z)
			if g.has(key):
				line += "%6d" % roundi(float(g[key][0]) * 100.0)
			else:
				line += "     ."
		print("[W7P] ", line)


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var cx := float(a[0]) if a.size() > 0 else 372.0
	var cz := float(a[1]) if a.size() > 1 else -32.0
	var half := float(a[2]) if a.size() > 2 else 12.0
	var chan := String(a[3]) if a.size() > 3 else "r"
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 10:
		await process_frame
	var mi := v.get_node("Terrain/FarmlandTerrain") as MeshInstance3D
	print("[W7P] mesh now=", mi.mesh.resource_name, " path=", mi.mesh.resource_path, " verts=", (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size())
	_print(_grid(mi.mesh as ArrayMesh, mi.global_transform, cx, cz, half, chan), "NOW (RoadBaseP10 適用後) chan=" + chan)
	var rb := v.get_node("RoadBaseP10")
	rb.set("enabled", false)
	await process_frame
	await process_frame
	print("[W7P] mesh orig=", mi.mesh.resource_path)
	_print(_grid(mi.mesh as ArrayMesh, mi.global_transform, cx, cz, half, chan), "ORIG (元の mesh) chan=" + chan)
	quit(0)
