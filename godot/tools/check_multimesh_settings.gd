extends SceneTree
## Inspect the sakura MultiMesh resource's own render-gating settings.
##
## Why: the node is visible, has no material override, no visibility range, and
## its buffer holds 17 valid transforms — yet the editor reports a zero-size
## AABB for it, which means the renderer believes it has nothing to draw. On a
## MultiMesh the usual cause is a resource-level switch rather than a node
## property, and the user says they "changed a setting" right before the trees
## disappeared. Compare every candidate against the tree types that still render.
##
## Run: godot --headless --path godot --script tools/check_multimesh_settings.gd

const DIR := "res://maps/slice/gen"


func _init() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		push_error("cannot open %s" % DIR)
		quit(1)
		return

	var names: Array = []
	for f in d.get_files():
		if f.begins_with("treemm_") and f.ends_with(".res"):
			names.append(f)
	names.sort()

	print("%-18s %6s %8s %8s %10s %s" % [
		"資源", "總數", "可見數", "格式", "AABB高", "AABB 範圍"])

	for f in names:
		var path := "%s/%s" % [DIR, f]
		var mm = load(path)
		if mm == null or not (mm is MultiMesh):
			print("%-18s  << 載入失敗" % f)
			continue

		var label: String = f.replace("treemm_", "").replace(".res", "")
		var total: int = mm.instance_count
		# visible_instance_count is the classic culprit: -1 means "draw all",
		# but any explicit value caps how many instances render, and 0 draws
		# nothing while leaving instance_count untouched.
		var vis: int = mm.visible_instance_count
		var box: AABB = mm.get_aabb()

		var flag := ""
		if vis == 0:
			flag = "  << 可見數為 0，完全不顯示"
		elif vis > 0 and vis < total:
			flag = "  << 只顯示前 %d 株" % vis
		if box.size == Vector3.ZERO:
			flag += "  << AABB 為零"
		if mm.mesh == null:
			flag += "  << 沒有 mesh"

		print("%-18s %6d %8d %8d %10.1f  %s%s" % [
			label, total, vis, mm.transform_format, box.size.y,
			"(%.0f,%.1f,%.0f)~(%.0f,%.1f,%.0f)" % [
				box.position.x, box.position.y, box.position.z,
				box.end.x, box.end.y, box.end.z],
			flag])

	quit(0)
