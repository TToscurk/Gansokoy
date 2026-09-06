extends SceneTree
## Verify the node-based sakura trees have real, correctly sized geometry.
##
## Why: the MultiMesh version reported valid data at every level yet rendered
## nothing, so "the file saved fine" is not evidence any more. Load the produced
## scene, walk to the actual MeshInstance3D leaves, and measure the WORLD-space
## height of each tree — the number that decides whether the user will see an
## 8 m tree or a 1 m shrub.
##
## Run: godot --headless --path godot --script tools/verify_sakura_nodes.gd

const SCENE := "res://maps/slice/gen/sakura_trees.tscn"


func _init() -> void:
	root.call_deferred("add_child", load(SCENE).instantiate())
	_run.call_deferred()


func _run() -> void:
	await process_frame

	var scene := root.get_child(root.get_child_count() - 1)
	var trees := scene.get_children()
	print("%s\n%d 株\n" % [SCENE, trees.size()])

	var heights: Array = []
	var no_geom := 0

	for t in trees:
		var box := AABB()
		var first := true
		for mi in _meshes(t):
			if mi.mesh == null:
				continue
			var b: AABB = mi.global_transform * mi.mesh.get_aabb()
			if first:
				box = b
				first = false
			else:
				box = box.merge(b)
		if first:
			no_geom += 1
			print("  %-14s << 沒有幾何" % t.name)
			continue
		heights.append(box.size.y)
		print("  %-14s 世界高 %5.2fm   位置(%.1f, %.2f, %.1f)" % [
			t.name, box.size.y,
			t.global_transform.origin.x,
			t.global_transform.origin.y,
			t.global_transform.origin.z])

	print("")
	if no_geom > 0:
		print("[FAIL] %d 株沒有幾何" % no_geom)
		quit(1)
		return

	heights.sort()
	var lo: float = heights[0]
	var hi: float = heights[-1]
	print("高度範圍 %.2f ~ %.2f m" % [lo, hi])

	# Sanity band: a sakura in this village should read as a real tree next to
	# the 6-8 m machiya, not a bush and not a skyscraper.
	if lo < 4.0:
		print("[FAIL] 最矮的只有 %.2fm，太小" % lo)
		quit(1)
	elif hi > 15.0:
		print("[FAIL] 最高的有 %.2fm，太大" % hi)
		quit(1)
	else:
		print("[PASS] 17 株都有幾何，尺寸合理（町屋約 6~8m）")
		quit(0)


func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
