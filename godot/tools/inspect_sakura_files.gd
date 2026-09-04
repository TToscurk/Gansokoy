extends SceneTree
## Check what each sakura MultiMesh candidate actually contains.
##
## Why: the live resource now reports instance_count 0. Before restoring from a
## backup, confirm the backup holds the 17 transforms — restoring an equally
## empty file would waste another round, and git has an older committed copy as
## a second fallback.
##
## Run: godot --headless --path godot --script tools/inspect_sakura_files.gd

const CANDIDATES := [
	"res://maps/slice/gen/treemm_櫻花樹.res",
	"res://maps/slice/gen/treemm_櫻花樹.bak.res",
]


func _init() -> void:
	for path in CANDIDATES:
		print("\n=== %s ===" % path.get_file())
		if not ResourceLoader.exists(path):
			print("  檔案不存在")
			continue
		var mm = load(path)
		if mm == null or not (mm is MultiMesh):
			print("  << 不是 MultiMesh 或載入失敗")
			continue

		var n: int = mm.instance_count
		var buf: PackedFloat32Array = mm.buffer
		print("  instance_count: %d" % n)
		print("  visible_instance_count: %d" % mm.visible_instance_count)
		print("  transform_format: %d" % mm.transform_format)
		print("  buffer 長度: %d floats (需要 %d)" % [buf.size(), n * 12])
		print("  mesh: %s" % (mm.mesh.resource_path if mm.mesh else "<無>"))

		if n > 0 and buf.size() >= n * 12:
			var minv := Vector3(INF, INF, INF)
			var maxv := Vector3(-INF, -INF, -INF)
			for i in n:
				var b := i * 12
				var p := Vector3(buf[b + 3], buf[b + 7], buf[b + 11])
				minv = minv.min(p)
				maxv = maxv.max(p)
			print("  範圍: X %.1f~%.1f  Y %.2f~%.2f  Z %.1f~%.1f" % [
				minv.x, maxv.x, minv.y, maxv.y, minv.z, maxv.z])
			print("  << 可用")
		else:
			print("  << 空的，不可用")
	quit(0)
