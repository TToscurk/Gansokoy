extends SceneTree
## Rebuild the sakura MultiMesh from its existing instance transforms.
##
## Why rebuild rather than re-scatter: the 17 original placements are still in
## the resource buffer and they were positioned deliberately. The trees stopped
## rendering after an editor setting change that undo did not reverse, and every
## data-level check (instance count, visible_instance_count, node visibility,
## mesh geometry, material) came back identical to the tree types that still
## display. So the fix is to write a FRESH MultiMesh resource carrying the same
## transforms — that drops whatever runtime state got stuck without moving a
## single tree.
##
## The old resource is backed up first; the positions are the user's, not ours
## to lose.
##
## Run: godot --headless --path godot --script tools/rebuild_sakura.gd

const SRC := "res://maps/slice/gen/treemm_櫻花樹.res"
const MESH := "res://maps/slice/gen/tree_櫻花樹.res"
const BACKUP := "res://maps/slice/gen/treemm_櫻花樹.bak.res"


func _init() -> void:
	var old = load(SRC)
	if old == null or not (old is MultiMesh):
		push_error("cannot load %s" % SRC)
		quit(1)
		return

	var n: int = old.instance_count
	var buf: PackedFloat32Array = old.buffer
	if buf.size() < n * 12:
		push_error("buffer too small: %d floats for %d instances" % [buf.size(), n])
		quit(1)
		return

	print("讀到 %d 株櫻花的變換資料" % n)

	# Keep a copy before overwriting.
	if not FileAccess.file_exists(BACKUP):
		var err := ResourceSaver.save(old, BACKUP)
		if err == OK:
			print("舊資源已備份到 %s" % BACKUP)

	var mesh = load(MESH)
	if mesh == null:
		push_error("cannot load mesh %s" % MESH)
		quit(1)
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = -1

	# Copy transforms across one by one rather than assigning the raw buffer, so
	# any malformed row surfaces here instead of rendering as a zero-scale
	# (invisible) instance.
	var bad := 0
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
		var sc := basis.get_scale()
		if sc.x < 0.001 or sc.y < 0.001 or sc.z < 0.001:
			bad += 1
			print("  [%d] 縮放為零 %s — 改用單位縮放" % [i, sc])
			basis = Basis().scaled(Vector3.ONE)
		mm.set_instance_transform(i, Transform3D(basis, origin))
		minv = minv.min(origin)
		maxv = maxv.max(origin)

	print("範圍: X %.1f~%.1f  Y %.2f~%.2f  Z %.1f~%.1f" % [
		minv.x, maxv.x, minv.y, maxv.y, minv.z, maxv.z])
	if bad > 0:
		print("修正了 %d 株縮放為零的實例" % bad)
	else:
		print("所有 %d 株變換資料正常" % n)

	var err := ResourceSaver.save(mm, SRC)
	if err != OK:
		push_error("save failed: %d" % err)
		quit(1)
		return
	print("\n[done] 已重建 %s" % SRC)
	quit(0)
