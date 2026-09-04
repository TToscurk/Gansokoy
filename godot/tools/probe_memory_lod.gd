extends SceneTree
## Does the runtime LOD swap free the original 915k-tri buildings, or do they
## stay resident behind the swapped copies? Load slice with 使用減面建築 on and
## off and compare MEMORY_STATIC.
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var lod := true
	for a in OS.get_cmdline_user_args():
		if a == "--no-lod":
			lod = false
	var packed := ResourceLoader.load("res://maps/slice/slice.tscn", "PackedScene") as PackedScene
	var m_after_load := Performance.get_monitor(Performance.MEMORY_STATIC)
	var scene := packed.instantiate()
	var cull := scene.get_node_or_null("場景效能裁剪")
	if cull != null:
		cull.set("使用減面建築", lod)
	root.add_child(scene)
	for i in 3:
		await process_frame
	print("[lod] 減面=%s  載入PackedScene後 %.0f MB  instantiate+run後 %.0f MB" % [
		lod, m_after_load / 1048576.0, Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	quit(0)
