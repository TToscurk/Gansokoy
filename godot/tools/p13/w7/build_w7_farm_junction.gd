extends SceneTree
## P13 Wave 7 FarmJunctionFixP13 builder：gen/farm_junction_fix_p13.scn を書く。
##   godot --headless --path . --script res://tools/p13/w7/build_w7_farm_junction.gd [-- --dry]
## 表の値（x, z, 新 r〔踩み固め〕, 新 street〔UV2.y〕）がここの唯一の正。頂点は「FarmlandTerrain（元の mesh）の 2 m 格子点を x,z で完全一致」で引き当てる。
const SCENE := "res://maps/village_v2/village_v2.tscn"
const SCRIPT := "res://maps/village_v2/scripts_p13/farm_junction_fix.gd"
const OUT_SCENE := "res://maps/village_v2/gen/farm_junction_fix_p13.scn"
const TERRAIN := "Terrain/FarmlandTerrain"

## CrossStreetMid の南縁（z＝−33）と FarmPath_1（x＝372）の接点。楔は x 367.5–371.5、z −34.3…−32.5。
const PATCH := [
	# [x, z, r, street]
	[366.0, -34.0, 0.35, 0.55],
	[368.0, -34.0, 0.0, 1.0],
	[370.0, -34.0, 0.0, 1.0],
	[372.0, -34.0, 0.0, 1.0],
	[374.0, -34.0, 0.35, 0.55],
]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var dry := OS.get_cmdline_user_args().has("--dry")
	var v: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(v)
	for i in 6:
		await process_frame
	# 元の mesh（RoadBaseP10／他 overlay を外した状態）で引き当てる
	for nm in ["FarmJunctionFixP13", "RoadBaseP10"]:
		var n := v.get_node_or_null(nm)
		if n != null:
			n.set("enabled", false)
	await process_frame
	await process_frame
	var mi := v.get_node(TERRAIN) as MeshInstance3D
	var arr := (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var u2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var xf := mi.global_transform
	var idx := PackedInt32Array()
	var px := PackedFloat32Array()
	var pz := PackedFloat32Array()
	var pr := PackedFloat32Array()
	var ps := PackedFloat32Array()
	for row: Array in PATCH:
		var hit := -1
		var n_hit := 0
		for i in vs.size():
			var w := xf * vs[i]
			if absf(w.x - float(row[0])) < 0.01 and absf(w.z - float(row[1])) < 0.01:
				hit = i
				n_hit += 1
		if n_hit != 1:
			push_error("頂点が一意に決まらない (%s, %s): %d 件" % [row[0], row[1], n_hit])
			quit(1)
			return
		print("[W7J] (%.0f, %.0f) idx=%d  r %.2f→%.2f  street %.2f→%.2f" % [row[0], row[1], hit, cs[hit].r, row[2], u2[hit].y, row[3]])
		idx.append(hit)
		px.append(float(row[0]))
		pz.append(float(row[1]))
		pr.append(float(row[2]))
		ps.append(float(row[3]))
	if dry:
		print("[W7J] dry run: ", idx.size(), " 頂点")
		quit(0)
		return
	var node := Node3D.new()
	node.name = "FarmJunctionFixP13"
	node.set_script(load(SCRIPT))
	node.set("terrain_path", TERRAIN)
	node.set("vidx", idx)
	node.set("vx", px)
	node.set("vz", pz)
	node.set("new_r", pr)
	node.set("new_street", ps)
	var pk := PackedScene.new()
	pk.pack(node)
	var err := ResourceSaver.save(pk, OUT_SCENE)
	print("[W7J] saved ", OUT_SCENE, " err=", err, " verts=", idx.size())
	quit(0)
