extends SceneTree
## P13 W7 診断（唯読・headless）：FarmlandTerrain の頂点データを窓（cx,cz,half）で JSON に書く。NOW（RoadBaseP10 適用後）と ORIG（元の mesh）。
##   godot --headless --path . --script res://tools/p13/w7/w7_dump_terrain.gd -- <out.json> <cx> <cz> <half>
## 各頂点 [x, y, z, r, g, b, a, fx, fy, wx, wy]（座標は world、重みは 0–1）と三角形 index（窓内に 3 点とも入るもの）。
const SCENE := "res://maps/village_v2/village_v2.tscn"


func _init() -> void:
	_run.call_deferred()


func _dump(mi: MeshInstance3D, cx: float, cz: float, half: float) -> Dictionary:
	var arr := (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var xf := mi.global_transform
	var keep := {}
	var rows := []
	for i in vs.size():
		var w := xf * vs[i]
		if absf(w.x - cx) <= half and absf(w.z - cz) <= half:
			keep[i] = rows.size()
			rows.append([snappedf(w.x, 0.001), snappedf(w.y, 0.001), snappedf(w.z, 0.001), snappedf(cs[i].r, 0.0001), snappedf(cs[i].g, 0.0001), snappedf(cs[i].b, 0.0001), snappedf(cs[i].a, 0.0001), snappedf(uv[i].x, 0.0001), snappedf(uv[i].y, 0.0001), snappedf(uv2[i].x, 0.0001), snappedf(uv2[i].y, 0.0001), i])
	var tris := []
	for t in range(0, ix.size(), 3):
		if keep.has(ix[t]) and keep.has(ix[t + 1]) and keep.has(ix[t + 2]):
			tris.append([keep[ix[t]], keep[ix[t + 1]], keep[ix[t + 2]]])
	return {"verts": rows, "tris": tris, "total_verts": vs.size()}


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out_path := String(a[0])
	var cx := float(a[1])
	var cz := float(a[2])
	var half := float(a[3])
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 10:
		await process_frame
	var mi := v.get_node("Terrain/FarmlandTerrain") as MeshInstance3D
	var res := {"now": _dump(mi, cx, cz, half)}
	v.get_node("RoadBaseP10").set("enabled", false)
	await process_frame
	await process_frame
	res["orig"] = _dump(mi, cx, cz, half)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(res))
	f.close()
	print("[W7D] now=", (res["now"]["verts"] as Array).size(), " orig=", (res["orig"]["verts"] as Array).size(), " -> ", out_path)
	quit(0)
