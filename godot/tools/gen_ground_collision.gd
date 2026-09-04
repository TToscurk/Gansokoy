extends SceneTree
## Build a paint-target collision body for maps/slice.
##
## Why this exists: slice.tscn contains ZERO StaticBody3D nodes. Every
## brush-based editor plugin (SimpleGrassTextured, Asset Placer, ProtonScatter
## with a physics-projection modifier) raycasts against physics colliders to
## decide where a placed instance lands. With no collider the brush silently
## does nothing, which reads as "the plugin is broken".
##
## Output is a SEPARATE scene instanced into slice.tscn, never an edit to the
## hand-tuned nodes: the user adjusts slice.tscn by hand between rounds, so this
## generator must stay additive and re-runnable without clobbering their work.
##
## Collision is trimesh (ConcavePolygonShape3D) built from the live mesh
## surfaces — the exact geometry the brush must follow. Layer 32 keeps the paint
## target out of the way of gameplay physics on layers 1..8.
##
## Run: godot --headless --path godot --script tools/gen_ground_collision.gd

const SRC_SCENE := "res://maps/slice/slice.tscn"
const OUT_PATH := "res://maps/slice/gen/ground_collision.scn"

# Single named meshes to bake. Terrain is excluded deliberately: it is hidden in
# the live scene (superseded by UnifiedGround) and baking both would give the
# brush two surfaces at nearly the same height.
#
# EastRiverRevetment added 2026-09-02 — a separate mesh from the unified ground,
# so with only the ground baked the brush ray passed through the stone bank.
# Water is never baked; plants must not land on the river surface.
const TARGETS := [
	"UnifiedGround",
	"BasinHills",
	"EastRiverRevetment",
]

# Whole sub-trees to bake. find_phantom_meshes.gd showed the canal side of the
# village is entirely physics-invisible: the stone bank walls, water-access
# steps, walkways and field bank are decorative meshes with no collider, so
# every brush ray fell 2-4 m through them onto UnifiedGround below. That is the
# "this bank just won't paint" symptom — to physics, the aimed-at surface does
# not exist.
#
# Buildings are excluded on purpose: not paint targets, and a trimesh per
# machiya would cost geometry for nothing.
const TARGET_SUBTREES := [
	"MachiCanal/VillageStoneBank",
	"MachiCanal/Waterworks",
	"MachiCanal/ChannelGeometry",
]

# Name fragments inside those subtrees that must stay collision-free: water
# surfaces the brush should never plant on.
const SUBTREE_EXCLUDE := [
	"Water",
	"water",
]

# Decorative props above this triangle count are EXCLUDED from collision, not
# simplified. Measured by probe_waterworks_cost.gd: 田泵水口_南 spends 110066
# triangles on 6.6 m² of walkable surface and 分水堰 85390 on 6.9 m² — 16677
# and 12376 triangles per walkable m², where the stairs the player actually
# climbs spend 148 and the canal floor spends 0.13. Together they were 71% of
# the Waterworks body.
#
# Two simplifications were tried and BOTH were rejected by
# verify_waterworks_proxy.gd, which ray-compares the new body against the
# pre-change baseline:
#   - 10 cm world-space vertex clustering → 148 sample points beyond the
#     analytic ±8.7 cm bound, worst 4.0 m. Snapping an OPEN thin shell flips
#     which side a vertical ray hits first.
#   - AABB box proxy → worse, 543 points. probe_weir_hotspot.gd showed the box
#     adding surfaces that never existed: a floor at y=1.696 over the canal bed
#     at x=283.6 z=32.0, and one at y=-1.774 at x=292.8 z=-15.6. The player
#     would walk into invisible walls.
#
# Excluding them is the only option that changes nothing the player can reach:
# both are thin shells standing IN the canal bed, and a vertical ray through
# either one already landed on ChannelGeometry, not on the prop
# (probe_waterworks_reduce.gd). They keep their visual mesh; they simply stop
# contributing 195 456 collision triangles that nothing stands on.
const EXCLUDE_ABOVE_TRIS := 30000

const PAINT_LAYER := 32  # bit 32 -> value 1 << 31

var _root: Node3D
var _made := 0
var _faces_total := 0


func _init() -> void:
	var packed: PackedScene = load(SRC_SCENE)
	if packed == null:
		push_error("cannot load %s" % SRC_SCENE)
		quit(1)
		return

	var src := packed.instantiate()

	# Freeze anything that animates itself before reading a single vertex.
	#
	# 水車 carries scripts/water_wheel_spin.gd, which is @tool and starts
	# turning the wheel the moment the node enters the scene — including inside
	# this headless bake. Two consecutive runs of this generator produced
	# byte-different .scn files (verify_collision_subset.gd: 13906 "new"
	# triangles in a pass that only ever removes geometry), because the wheel's
	# 13925 triangles landed at a different angle each time. Collision output
	# must be a function of the scene alone, or no A/B comparison of it means
	# anything.
	_freeze_animated(src)

	_root = Node3D.new()
	_root.name = "GroundCollision"

	for target_name in TARGETS:
		var node := src.find_child(target_name, true, false)
		if node == null:
			print("[skip] 找不到節點: %s" % target_name)
			continue
		if not (node is MeshInstance3D):
			print("[skip] 不是 MeshInstance3D: %s" % target_name)
			continue
		_bake(node as MeshInstance3D, src, target_name)

	for sub_path in TARGET_SUBTREES:
		var group := src.get_node_or_null(sub_path)
		if group == null:
			print("[skip] 找不到子樹: %s" % sub_path)
			continue

		var group_faces := PackedVector3Array()
		var count := 0
		var seen_instances := {}
		for mi in _meshes(group):
			if not mi.visible:
				continue
			if _excluded(mi):
				continue
			var m: Mesh = mi.mesh
			if m == null:
				continue
			var f := m.get_faces()
			if f.is_empty():
				continue
			# Global transform relative to the scene root, so every wall in the
			# group lands in world space regardless of how deeply it is nested.
			var xf := _global_xform(mi, src)

			# Same surface baked twice. 牆_01 and 牆_05 each hold a mesh_node
			# plus a mesh_node2 that probe_waterworks_reduce.gd measured as
			# vertex-for-vertex identical (same 14465 faces, same zero offset).
			#
			# The key must be GEOMETRIC, not the mesh RID: the two copies are
			# different Resources — one is 塊石疊砌牆一段.glb::ArrayMesh_s6kc8,
			# the other waterway_art_review.tscn's own embedded copy of that
			# same ArrayMesh — so they have different RIDs and a RID-keyed check
			# silently passes both through (measured: first attempt still baked
			# all 12 walls). Hashing the world-space corners catches them.
			var dup_key := _geom_key(f, xf)
			if seen_instances.has(dup_key):
				print("[dedup] %s 與 %s 幾何完全重複，略過 %d 三角面" % [
					mi.name, seen_instances[dup_key], f.size() / 3])
				continue
			seen_instances[dup_key] = String(mi.name)

			# Dense decorative props contribute no collision at all — see
			# EXCLUDE_ABOVE_TRIS for the measurements and for the two
			# simplification attempts that were tried and rejected.
			if f.size() / 3 > EXCLUDE_ABOVE_TRIS:
				print("[exclude] %s %d 三角面（每可站立 m² 過高，排除碰撞）" % [
					mi.name, f.size() / 3])
				continue

			# The water wheel SPINS (scripts/water_wheel_spin.gd, 28 deg/s), so
			# its art mesh cannot be its collider: a trimesh baked from the
			# wheel's spokes is correct for exactly one frame and wrong for
			# every other. That non-determinism was already measured — two
			# consecutive bakes of this generator differed by 13 906 triangles,
			# all inside the wheel's swept volume, purely because the wheel had
			# turned between runs.
			#
			# A cylinder on the axle is the one shape that is invariant under
			# that rotation. probe_wheel_collision.gd measured the wheel at
			# 5.57 x 5.38 m across the face and 1.82 m thick, with the axle
			# along world X, and the face only 49.3% solid — so a disc-shaped
			# proxy also stops the player from walking through the gaps between
			# spokes, which a spoke-accurate trimesh would let them do half the
			# time and block the other half depending on the wheel's angle.
			if _is_spinner(mi):
				# Its OWN body, not merged into the Waterworks trimesh. Two
				# reasons: the wheel is a moving fixture and deserves to be
				# inspectable on its own in the editor, and merging it made the
				# proxy unverifiable — three separate attempts to pick the
				# cylinder back out of 65 000 merged Waterworks triangles (AABB
				# neighbourhood, trailing-triangle order, radius signature) all
				# picked up the wrong geometry. A named body needs no searching.
				var world_wheel := _wheel_proxy(f, xf)
				_add_body(world_wheel, "%s_旋轉代理" % _spinner_name(mi))
				print("[spinner] %s %d → %d 三角面（旋轉不變的軸向圓柱代理，獨立碰撞體）" % [
					mi.name, f.size() / 3, world_wheel.size() / 3])
				continue

			var world := PackedVector3Array()
			world.resize(f.size())
			for i in f.size():
				world[i] = xf * f[i]

			group_faces.append_array(world)
			count += 1

		if group_faces.is_empty():
			print("[skip] 子樹沒有可用網格: %s" % sub_path)
			continue

		# One body per subtree rather than per wall: the brush only needs a
		# surface to hit, and 12 separate bodies would just bloat the scene.
		_add_body(group_faces, sub_path.get_file())
		print("[ok] %s -> %d 個網格, %d 三角面" % [
			sub_path, count, group_faces.size() / 3])

	src.free()

	if _made == 0:
		push_error("no collision bodies produced")
		quit(1)
		return

	var out := PackedScene.new()
	var err := out.pack(_root)
	if err != OK:
		push_error("pack failed: %d" % err)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(OUT_PATH.get_base_dir())
	err = ResourceSaver.save(out, OUT_PATH)
	if err != OK:
		push_error("save failed: %d" % err)
		quit(1)
		return

	print("\n[done] %s  bodies=%d  triangles=%d  layer=%d" % [
		OUT_PATH, _made, _faces_total, PAINT_LAYER])
	quit(0)


func _bake(mi: MeshInstance3D, scene_root: Node, label: String) -> void:
	var mesh: Mesh = mi.mesh
	if mesh == null:
		print("[skip] 沒有網格: %s" % label)
		return
	var faces := mesh.get_faces()
	if faces.is_empty():
		print("[skip] 網格沒有面: %s" % label)
		return

	var xform := _global_xform(mi, scene_root)
	if not xform.is_equal_approx(Transform3D.IDENTITY):
		var moved := PackedVector3Array()
		moved.resize(faces.size())
		for i in faces.size():
			moved[i] = xform * faces[i]
		faces = moved

	_add_body(faces, label)
	print("[ok] %s -> %d 三角面" % [label, faces.size() / 3])


func _add_body(faces: PackedVector3Array, label: String) -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)

	var body := StaticBody3D.new()
	body.name = "%s_碰撞" % label
	# Layer 32 for the paint brushes AND layer 1 for the player. These are the
	# ground, hills, revetment and canal banks — exactly what the character must
	# stand on and be stopped by. Audited 2026-09-03: with layer 32 only, the
	# player fell through the stone bank and the east river had no bed at all.
	body.collision_layer = (1 << (PAINT_LAYER - 1)) | 1
	body.collision_mask = 0

	var col := CollisionShape3D.new()
	col.name = "形狀"
	col.shape = shape
	body.add_child(col)

	_root.add_child(body)
	body.owner = _root
	col.owner = _root

	_faces_total += faces.size() / 3
	_made += 1


## Transform from a node's local space into the scene root's space. Cannot use
## global_transform here: the scene is instantiated outside the tree, so global
## transforms are not resolved.
func _global_xform(node: Node3D, scene_root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != scene_root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Water surfaces must stay collision-free, but the match has to be on the
## MESH's own name only. Walking up the ancestors wrongly excluded the whole
## Waterworks subtree (its parent contains "Water"), and its 親水階梯 steps are
## exactly the surface the user wants to plant on.
func _excluded(mi: MeshInstance3D) -> bool:
	var names := [mi.name]
	var p := mi.get_parent()
	if p != null:
		names.append(p.name)
	for nm in names:
		var s := str(nm)
		if s.contains("CanalWater") or s.contains("PaddyWater"):
			return true
		if s == "Water" or s.ends_with("_Water") or s.begins_with("Water_"):
			return true
		if s.contains("水面") or s.contains("水體"):
			return true
	return false


func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out


## Stop self-animating @tool nodes so the bake reads one fixed pose.
##
## Do NOT touch their transform. The first version also did
##   rotation = Vector3.ZERO
## to "return the node to its authored pose", but that erased the yaw the scene
## author gave the wheel to face it down the canal: the wheel's thin axis flipped
## from world X to world Z, and _wheel_proxy — which derives the axle from the
## thinnest axis — then built the cylinder lying on its side (measured 5.50 x
## 5.50 x 1.82 where the real wheel sweeps 1.82 x 5.82 x 5.82).
##
## Halting _process is enough for determinism, and the cylinder proxy is
## rotation-invariant anyway, so the wheel's exact angle no longer matters.
func _freeze_animated(root: Node) -> void:
	var stack: Array[Node] = [root]
	var frozen := 0
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n.get_script() == null:
			continue
		if n.has_method("_process"):
			n.set_process(false)
			n.set_physics_process(false)
			frozen += 1
	if frozen > 0:
		print("[freeze] 已停止 %d 個自更新節點的 _process（不改 transform）" % frozen)


## Geometric fingerprint of a mesh AS PLACED IN THE WORLD: face count plus a
## checksum over its world-space corners. Two nodes sharing this share the
## exact same collision surface, whatever Resource each one loaded it from.
## Sampled every 37th vertex — a stride, not a prefix, so meshes that agree at
## the start and diverge later still separate, at a fraction of the cost.
func _geom_key(faces: PackedVector3Array, xf: Transform3D) -> String:
	var sx := 0.0
	var sy := 0.0
	var sz := 0.0
	var i := 0
	while i < faces.size():
		var w := xf * faces[i]
		sx += w.x
		sy += w.y
		sz += w.z
		i += 37
	return "%d|%.5f|%.5f|%.5f" % [faces.size(), sx, sy, sz]


## Does this mesh belong to a node driven by the spin script?
func _is_spinner(mi: MeshInstance3D) -> bool:
	return _spinner_node(mi) != null


## The spinning node itself (the one carrying the script), so the collider can
## be named after 水車 rather than after its inner mesh_node.
func _spinner_node(mi: MeshInstance3D) -> Node:
	var n: Node = mi
	while n != null:
		var s: Script = n.get_script()
		if s != null and String(s.resource_path).ends_with("water_wheel_spin.gd"):
			return n
		n = n.get_parent()
	return null


func _spinner_name(mi: MeshInstance3D) -> String:
	var n := _spinner_node(mi)
	return String(mi.name) if n == null else String(n.name)


## A closed cylinder on the wheel's axle, in world space.
##
## The axle is DERIVED from the geometry, not hard-coded: it is the world axis
## the mesh is thinnest along (a wheel is a disc, so its thickness axis is the
## axle). Hard-coding "Z" would have been wrong here — the spin script's LOCAL
## axis is Z, but the instance is yawed into place, so in world space the axle
## runs along X (probe_wheel_collision.gd: world size 1.82 x 5.57 x 5.38).
## Deriving it means re-placing or re-orienting the wheel in the editor cannot
## silently produce a collider lying on its side.
##
## Radius covers the wheel's full sweep, so a paddle at any angle stays inside.
func _wheel_proxy(faces: PackedVector3Array, xf: Transform3D) -> PackedVector3Array:
	var box := AABB(xf * faces[0], Vector3.ZERO)
	for v in faces:
		box = box.expand(xf * v)

	var axis := 0
	if box.size.y < box.size.x and box.size.y <= box.size.z:
		axis = 1
	elif box.size.z < box.size.x and box.size.z <= box.size.y:
		axis = 2

	var centre := box.get_center()
	var half_len: float = box.size[axis] * 0.5
	# Radius = the furthest any vertex sits from the axle, i.e. the wheel's true
	# sweep radius. Using half the AABB extent instead would under-cover a wheel
	# whose disc is not axis-aligned, letting paddle tips poke out of their own
	# collider at some angles.
	var i1 := (axis + 1) % 3
	var i2 := (axis + 2) % 3
	var r := 0.0
	for v in faces:
		var w := xf * v
		var d1: float = w[i1] - centre[i1]
		var d2: float = w[i2] - centre[i2]
		r = maxf(r, sqrt(d1 * d1 + d2 * d2))

	var a := Vector3.ZERO
	a[axis] = 1.0
	var u := Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT
	var e1 := a.cross(u).normalized()
	var e2 := a.cross(e1).normalized()

	var segs := 24
	var out := PackedVector3Array()
	var c0 := centre - a * half_len
	var c1 := centre + a * half_len
	for i in segs:
		var t0 := TAU * float(i) / float(segs)
		var t1 := TAU * float(i + 1) / float(segs)
		var p0 := e1 * cos(t0) * r + e2 * sin(t0) * r
		var p1 := e1 * cos(t1) * r + e2 * sin(t1) * r
		# side wall
		out.append(c0 + p0)
		out.append(c1 + p0)
		out.append(c1 + p1)
		out.append(c0 + p0)
		out.append(c1 + p1)
		out.append(c0 + p1)
		# end caps, so the player cannot enter along the axle
		out.append(c0)
		out.append(c0 + p1)
		out.append(c0 + p0)
		out.append(c1)
		out.append(c1 + p0)
		out.append(c1 + p1)
	return out
