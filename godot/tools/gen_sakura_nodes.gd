extends SceneTree
## Rebuild the sakura trees as INDIVIDUAL nodes instead of a MultiMesh.
##
## Why abandon the MultiMesh: every data-level check passes — 17 valid
## transforms, correct mesh (8 m tall, textured), visible node, no visibility
## range, visible_instance_count -1, settings byte-identical to the tree types
## that still render — yet the editor reports a zero-size AABB for this node
## alone and draws nothing. Rebuilding the resource and restarting Godot did not
## clear it. Rather than keep chasing a stuck render path, place the trees
## through a completely different one.
##
## The transforms are read from the existing MultiMesh buffer, so every tree
## lands exactly where it was. Each becomes an instanced GLB under a parent
## node, which also matches the user's stated preference for individually
## selectable objects over instance-count economy.
##
## Output: maps/slice/gen/sakura_trees.tscn
## Run: godot --headless --path godot --script tools/gen_sakura_nodes.gd

const MM_SRC := "res://maps/slice/gen/treemm_櫻花樹.res"
const GLB := "res://assets/landscape/櫻花樹.glb"
const OUT := "res://maps/slice/gen/sakura_trees.tscn"


func _init() -> void:
	var mm = load(MM_SRC)
	if mm == null or not (mm is MultiMesh):
		push_error("cannot load %s" % MM_SRC)
		quit(1)
		return

	var n: int = mm.instance_count
	var buf: PackedFloat32Array = mm.buffer
	if buf.size() < n * 12:
		push_error("buffer too small")
		quit(1)
		return

	var packed = load(GLB)
	if packed == null or not (packed is PackedScene):
		push_error("cannot load %s" % GLB)
		quit(1)
		return

	# Confirm the source model really has geometry before cloning it 17 times.
	var probe = packed.instantiate()
	var probe_box := AABB()
	var first := true
	for mi in _meshes(probe):
		if mi.mesh == null:
			continue
		var b: AABB = mi.mesh.get_aabb()
		if first:
			probe_box = b
			first = false
		else:
			probe_box = probe_box.merge(b)
	probe.free()
	if first or probe_box.size.y < 0.01:
		push_error("source GLB has no usable geometry")
		quit(1)
		return
	print("來源模型 %s：高 %.2fm" % [GLB.get_file(), probe_box.size.y])

	# The source GLB is unit-normalised (0.98 m tall) while the MultiMesh drew a
	# pre-scaled 8 m mesh, so the buffer's scale values are relative to that 8 m
	# version. Multiply through by the ratio, or every tree comes out ankle-high.
	var mm_mesh = load("res://maps/slice/gen/tree_櫻花樹.res")
	var target_h := 8.0
	if mm_mesh != null:
		target_h = mm_mesh.get_aabb().size.y
	var size_fix: float = target_h / probe_box.size.y
	print("尺度補正: GLB %.2fm -> 目標 %.2fm  (x%.2f)" % [
		probe_box.size.y, target_h, size_fix])

	var root := Node3D.new()
	root.name = "櫻花樹群"

	var minv := Vector3(INF, INF, INF)
	var maxv := Vector3(-INF, -INF, -INF)

	for i in n:
		var b := i * 12
		var basis := Basis(
			Vector3(buf[b + 0], buf[b + 4], buf[b + 8]),
			Vector3(buf[b + 1], buf[b + 5], buf[b + 9]),
			Vector3(buf[b + 2], buf[b + 6], buf[b + 10])
		)
		var origin := Vector3(buf[b + 3], buf[b + 7], buf[b + 11])

		var inst: Node3D = packed.instantiate()
		inst.name = "櫻花樹_%02d" % i
		inst.transform = Transform3D(basis.scaled(Vector3.ONE * size_fix), origin)
		root.add_child(inst)
		# Own only the instance root — never the GLB's internals, or Godot
		# reports node-name conflicts on load and silently renames them.
		inst.owner = root

		minv = minv.min(origin)
		maxv = maxv.max(origin)
		var sc := basis.get_scale()
		print("  %s  位置(%.1f, %.2f, %.1f)  縮放 %.2f" % [
			inst.name, origin.x, origin.y, origin.z, sc.y])

	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		push_error("pack failed: %d" % err)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	err = ResourceSaver.save(ps, OUT)
	if err != OK:
		push_error("save failed: %d" % err)
		quit(1)
		return

	print("\n%d 株，範圍 X %.1f~%.1f  Z %.1f~%.1f" % [
		n, minv.x, maxv.x, minv.z, maxv.z])
	print("[done] %s" % OUT)
	quit(0)


func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
