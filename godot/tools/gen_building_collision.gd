extends SceneTree
## Build gameplay colliders for the buildings in maps/slice.
##
## Why a separate generator instead of main.gd's trimesh pass: main.gd only
## trimeshes meshes with XZ span >= 15 m, so every machiya (6-10 m) and the
## torii are walk-through — audit_slice_collision.gd measured 4/4 buildings
## passable. The paint-brush body (gen_ground_collision.gd) excludes buildings
## on purpose because they are not paint targets.
##
## Shape choice: a trimesh of a 200k-triangle decimated building is far too
## much for a character controller to slide along, and a full trimesh of the
## 915k original is worse. A convex hull of the mesh is cheap and, for these
## rectangular Japanese townhouses, hugs the walls closely enough — the only
## real loss is deep eaves being solid down to the ground, which the player
## never walks under anyway because the wall is right there.
##
## Output is additive: a separate scene instanced into slice.tscn, on layer 1
## (player). Never edits the hand-tuned building nodes.
##
## Run: godot --headless --path godot --script tools/gen_building_collision.gd

const SRC_SCENE := "res://maps/slice/slice.tscn"
const OUT_PATH := "res://maps/slice/gen/building_collision.scn"

# Subtrees whose MeshInstance3Ds become colliders. Each building is a Node3D
# holding one instanced GLB; the convex hull is built from the live mesh in
# world space so the baked transform issue from the LOD swap cannot recur.
const SUBTREES := [
	"B1_Street",
	"鈴奈庵", "鯢吞亭", "霧雨店", "寺子屋", "龍神像", "稗田底新版", "火見櫓",
	"龍石像橋",
]
# Inside those subtrees, skip meshes that are ground/paving (already covered by
# the ground body) and decorative clutter under this triangle count.
const SKIP_NAMES := ["StreetPaving", "Plaza", "plaza", "Ground", "ground"]
const MIN_TRIS := 2000
# Convex hulls seal every opening. A torii is an arch you walk THROUGH; the
# sweep audit measured the hull stopping the player 43% of the way under it.
# These get a trimesh instead, built from the decimated LOD mesh (torii is
# ~200k tris at full res, too heavy for a character to slide along).
## A bridge is a surface you walk ON and pass UNDER. A convex hull of an arched
## deck is a sealed lump: probe_teahouse_bridge.gd measured a mid-height sweep
## across 龍石像橋 stopping at 4.8%, and the hull top is a smooth dome over the
## railings and dragon statues rather than the deck itself. 13.9k tris is well
## inside the budget for a trimesh.
const TRIMESH_NAMES := ["鳥居", "Tori", "torii", "橋", "Bri", "bridge"]

## Market clutter gets a BOX, not a hull. probe_building_hulls.gd measured the
## PlazaMarket zatsu props at 142-182 hull vertices each — the heaviest shapes in
## the whole building body after the three trimeshes, and they are barrels,
## crates and sacks: the player only needs to not walk through them. A box is 8
## vertices and reads identically at walking speed.
##
## 燈籠 (676 and 556 vertices on 鯢吞亭/霧雨店) are deliberately NOT here: they
## hang over the street at head height, and a box around a lantern's swept shape
## would stick out into the walkway.
const BOX_NAMES := ["zatsu", "雜物"]

var _root: Node3D
var _out: Node3D
var _made := 0
var _skipped := 0
## Owner + world AABB + triangle count. 龍石像橋 carries `mesh_node` (the GLB's)
## and a hand-added `mesh_node2` holding an identical ArrayMesh at the same
## transform; baking both produced two byte-identical trimeshes stacked on each
## other. Different resources, same geometry — dedupe on the geometry.
var _seen := {}


func _init() -> void:
	var packed: PackedScene = load(SRC_SCENE)
	_root = packed.instantiate()
	root.add_child(_root)
	# Use the ORIGINAL meshes for hulls, not the decimated ones: same footprint,
	# and the hull ignores interior detail anyway.
	var cull := _root.get_node_or_null("場景效能裁剪")
	if cull != null:
		cull.set("啟用", false)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame

	_out = Node3D.new()
	_out.name = "建物碰撞"

	for path in SUBTREES:
		var n := _root.get_node_or_null(path)
		if n == null:
			print("  找不到 %s，跳過" % path)
			continue
		_bake_subtree(n, path)

	var packed := PackedScene.new()
	packed.pack(_out)
	var err := ResourceSaver.save(packed, OUT_PATH)
	print("[建物碰撞] 寫入 %s：%d 個 hull，跳過 %d 個（err=%d）" % [OUT_PATH, _made, _skipped, err])
	quit(0)


func _bake_subtree(n: Node, label: String) -> void:
	for mi in _meshes(n):
		var nm := String(mi.name)
		var skip := false
		for s in SKIP_NAMES:
			if nm.findn(s) != -1 or String(mi.get_parent().name).findn(s) != -1:
				skip = true
		if skip or mi.mesh == null or _tris(mi.mesh) < MIN_TRIS:
			_skipped += 1
			continue

		var owner_nm := _owner_name(mi)
		var wb: AABB = mi.global_transform * mi.get_aabb()
		var key := "%s|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%d" % [
			owner_nm, wb.position.x, wb.position.y, wb.position.z,
			wb.size.x, wb.size.y, wb.size.z, _tris(mi.mesh)]
		if _seen.has(key):
			print("  重複幾何，跳過 %s/%s" % [owner_nm, nm])
			_skipped += 1
			continue
		_seen[key] = true

		var shape: Shape3D = null
		var wants_trimesh := false
		for t in TRIMESH_NAMES:
			if nm.findn(t) != -1 or owner_nm.findn(t) != -1:
				wants_trimesh = true

		var wants_box := false
		for t in BOX_NAMES:
			if nm.findn(t) != -1 or owner_nm.findn(t) != -1:
				wants_box = true

		if wants_trimesh:
			shape = _trimesh_shape(mi)
		elif wants_box:
			shape = _box_shape(mi)
		else:
			shape = _hull_shape(mi)
		if shape == null:
			_skipped += 1
			continue

		var body := StaticBody3D.new()
		body.name = "%s_%s" % [owner_nm, nm]
		body.collision_layer = 1
		body.collision_mask = 0
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		_out.add_child(body)
		body.owner = _out
		col.owner = _out
		_made += 1


## Exact geometry, world space, from the decimated LOD mesh so the face count
## is tolerable for a character to slide along. Falls back to the live mesh.
func _trimesh_shape(mi: MeshInstance3D) -> Shape3D:
	var src: Mesh = mi.mesh
	var rp := src.resource_path
	if rp.contains(".glb"):
		var lod_path := "res://assets/_lod/" + rp.get_slice("::", 0).get_file()
		if ResourceLoader.exists(lod_path):
			var ps := ResourceLoader.load(lod_path, "PackedScene") as PackedScene
			var inst := ps.instantiate()
			for f in _meshes(inst):
				if f.mesh != null:
					src = f.mesh
					break
			inst.free()
	var faces := PackedVector3Array()
	var xf := mi.global_transform
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx != null and idx.size() > 0:
			for i in idx:
				faces.append(xf * v[i])
		else:
			for p in v:
				faces.append(xf * p)
	if faces.size() < 3:
		return null
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape


## An axis-aligned box around the mesh's world AABB, as a 8-point convex hull.
##
## Why a hull of 8 corners rather than BoxShape3D: BoxShape3D is always centred
## on its CollisionShape3D's own transform, so using it would mean giving every
## prop its own offset transform. These bodies are built at world origin with the
## geometry already in world space (same as _hull_shape and _trimesh_shape), so
## an 8-point hull keeps that one convention. GJK cost on 8 points is the floor.
func _box_shape(mi: MeshInstance3D) -> Shape3D:
	var wb: AABB = mi.global_transform * mi.get_aabb()
	var pts := PackedVector3Array()
	for i in 8:
		pts.append(wb.get_endpoint(i))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	return shape


func _hull_shape(mi: MeshInstance3D) -> Shape3D:
	# Convex hull in WORLD space: walk the surface arrays through the
	# mesh's global transform so the hull lands where the building is.
	var pts := PackedVector3Array()
	var xf := mi.global_transform
	for s in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		# Subsample: a hull needs the outer extremes, not all 915k points.
		var step := maxi(1, verts.size() / 4000)
		for i in range(0, verts.size(), step):
			pts.append(xf * verts[i])
	if pts.size() < 8:
		return null

	# Compute the actual hull rather than storing thousands of raw points:
	# ConvexPolygonShape3D keeps whatever you give it, and 75 × 4000 points
	# was a 10 MB scene. QuickHull reduces a townhouse to ~100-300 verts.
	var tmp := ImmediateMesh.new()
	tmp.surface_begin(Mesh.PRIMITIVE_POINTS)
	for p in pts:
		tmp.surface_add_vertex(p)
	tmp.surface_end()
	var hull := tmp.create_convex_shape(true, false)
	if hull == null or hull.points.size() < 4:
		return null
	return hull


## The building node so hulls are named after the building, e.g. "kura_東_09"
## or "PlazaMarket_yatai_03", not the generic "mesh_node". Walks up from the
## mesh until it hits one of the SUBTREES roots (or the scene root) and joins
## the named ancestors between — so PlazaMarket stalls (three levels deep)
## get a name instead of Godot's "@StaticBody3D@37".
func _owner_name(mi: Node) -> String:
	var parts: Array[String] = []
	var n: Node = mi.get_parent()
	while n != null and n != _root:
		var nm := String(n.name)
		if nm == "B1_Street":
			break
		if not (nm.begins_with("mesh_node") or nm == "Armature" or nm.begins_with("Sketchfab") or nm.begins_with("RootNode")):
			parts.push_front(nm)
		n = n.get_parent()
	if parts.is_empty():
		return String(mi.name)
	# Drop the instanced-GLB's own root (e.g. "Stonebound Wooden Bri_1") when
	# it sits under a hand-named holder — keep the holder.
	if parts.size() >= 2 and (parts[-1].contains(" ") or parts[-1].contains("Meshy")):
		parts.remove_at(parts.size() - 1)
	return "_".join(parts)


func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


func _tris(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var idx = arr[Mesh.ARRAY_INDEX]
		t += (idx.size() / 3) if idx != null and idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX].size() / 3)
	return t
