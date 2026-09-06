extends SceneTree
## Audit hand-painted SimpleGrassTextured coverage in maps/slice.
##
## Why this exists: the user paints grass by hand between rounds; the point of
## painting (rather than generating) is UNEVEN distribution — dense at wall
## bases, worn bare on paths. A count alone cannot show that. This reports the
## spatial signature: extent, occupied cells on a coarse grid, and the density
## histogram across those cells, so "did they leave gaps" is measurable.
##
## Read-only. Loads the .tscn from disk, never touches the live editor scene.
##
## Run: godot --headless --path godot --script tools/audit_grass_paint.gd

const SCENE := "res://maps/slice/slice.tscn"
const CELL := 8.0  # metres; roughly one house frontage


func _init() -> void:
	var packed: PackedScene = load(SCENE)
	if packed == null:
		push_error("cannot load %s" % SCENE)
		quit(1)
		return

	var root := packed.instantiate()
	var brushes: Array[Node] = []
	_collect(root, brushes)

	if brushes.is_empty():
		print("no SimpleGrassTextured nodes found")
		root.free()
		quit(0)
		return

	var grand_total := 0

	for node in brushes:
		var mi := node as MultiMeshInstance3D
		var mm := mi.multimesh
		if mm == null:
			print("\n== %s ==\n  (no multimesh)" % mi.name)
			continue

		var n := mm.instance_count
		grand_total += n
		print("\n== %s ==" % mi.name)
		print("  叢數: %d" % n)
		if n == 0:
			print("  (空的 — 這個筆刷沒刷過)")
			continue

		# get_instance_transform() round-trips through RenderingServer, which is a
		# stub under --headless and returns identity for every instance. Read the
		# packed buffer instead: 12 floats per instance, row-major 3x4, with the
		# translation in elements 3, 7, 11.
		var buf := mm.buffer
		if buf.size() < n * 12:
			print("  (buffer 讀取失敗: %d floats)" % buf.size())
			continue

		var minv := Vector3(INF, INF, INF)
		var maxv := Vector3(-INF, -INF, -INF)
		var cells := {}

		for i in n:
			var b := i * 12
			var p := Vector3(buf[b + 3], buf[b + 7], buf[b + 11])
			minv = minv.min(p)
			maxv = maxv.max(p)
			var key := Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))
			cells[key] = cells.get(key, 0) + 1

		var span := maxv - minv
		print("  範圍: X %.1f~%.1f (%.1fm)  Z %.1f~%.1f (%.1fm)  Y %.2f~%.2f" % [
			minv.x, maxv.x, span.x, minv.z, maxv.z, span.z, minv.y, maxv.y])
		print("  覆蓋: %d 個 %.0fm 格  平均 %.1f 叢/格" % [
			cells.size(), CELL, float(n) / max(cells.size(), 1)])

		# Density spread across occupied cells: a flat histogram means the paint
		# is uniform (the failure mode we are trying to avoid); a long tail means
		# the user genuinely varied density.
		var counts := []
		for k in cells:
			counts.append(cells[k])
		counts.sort()
		var lo: int = counts[0]
		var hi: int = counts[-1]
		var mid: int = counts[counts.size() / 2]
		print("  每格叢數: 最少 %d / 中位 %d / 最多 %d  (比值 %.1fx)" % [
			lo, mid, hi, float(hi) / max(lo, 1)])

	print("\n---")
	print("總計 %d 叢，分佈於 %d 個筆刷節點" % [grand_total, brushes.size()])
	root.free()
	quit(0)


func _collect(node: Node, out: Array[Node]) -> void:
	if node is MultiMeshInstance3D and node.has_meta(&"SimpleGrassTextured"):
		out.append(node)
	for c in node.get_children():
		_collect(c, out)
