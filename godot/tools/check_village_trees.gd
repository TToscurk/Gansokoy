extends SceneTree
## Check whether the sakura MultiMesh actually has instances, and where they are.
##
## Why: the user reports the cherry trees vanished from village_trees.tscn. The
## node and its resource both still exist on disk and git shows no edit to that
## node, so the question is whether the MultiMesh itself is empty, positioned
## elsewhere, or simply out of the current view — three very different fixes.
##
## Run: godot --headless --path godot --script tools/check_village_trees.gd

const SCENE := "res://maps/slice/gen/village_trees.tscn"


func _init() -> void:
	var packed: PackedScene = load(SCENE)
	if packed == null:
		push_error("cannot load %s" % SCENE)
		quit(1)
		return
	var root := packed.instantiate()

	print("%s\n" % SCENE)
	print("%-22s %10s %12s %s" % ["節點", "株數", "節點位移", "範圍(世界座標)"])

	for c in root.get_children():
		if not (c is MultiMeshInstance3D):
			continue
		var mi := c as MultiMeshInstance3D
		var mm := mi.multimesh
		if mm == null:
			print("%-22s %10s   (無 MultiMesh)" % [mi.name, "-"])
			continue

		var n := mm.instance_count
		var pos := mi.transform.origin
		if n == 0:
			print("%-22s %10d   位移(%.1f,%.1f,%.1f)   << 空的" % [
				mi.name, n, pos.x, pos.y, pos.z])
			continue

		# Read the packed buffer directly: get_instance_transform() goes through
		# RenderingServer, which is a stub under --headless.
		var buf := mm.buffer
		if buf.size() < n * 12:
			print("%-22s %10d   (buffer 讀取失敗)" % [mi.name, n])
			continue

		var minv := Vector3(INF, INF, INF)
		var maxv := Vector3(-INF, -INF, -INF)
		for i in n:
			var b := i * 12
			var p := Vector3(buf[b + 3], buf[b + 7], buf[b + 11]) + pos
			minv = minv.min(p)
			maxv = maxv.max(p)

		print("%-22s %10d   位移(%.1f,%.1f,%.1f)   X %.0f~%.0f  Y %.1f~%.1f  Z %.0f~%.0f" % [
			mi.name, n, pos.x, pos.y, pos.z,
			minv.x, maxv.x, minv.y, maxv.y, minv.z, maxv.z])

		if mm.mesh == null:
			print("%-22s %10s   << MultiMesh 沒有 mesh，不會顯示" % ["", ""])
		else:
			var surf := mm.mesh.get_surface_count()
			var mats := 0
			for s in surf:
				if mm.mesh.surface_get_material(s) != null:
					mats += 1
			print("%-22s   mesh: %d 個 surface, %d 個有材質" % ["", surf, mats])

	root.free()
	quit(0)
