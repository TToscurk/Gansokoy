extends SceneTree
## Static-memory A/B: instantiate slice with and without a subtree and report
## Performance.MEMORY_STATIC + OBJECT_COUNT. Arg: --drop=<scene path>.
## Run: godot --headless --path godot --script tools/probe_memory_ab.gd -- --drop=MachiCanal/VillageContext

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var drop := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--drop="):
			drop = a.substr(7)
	var m0 := Performance.get_monitor(Performance.MEMORY_STATIC)
	var packed := ResourceLoader.load("res://maps/slice/slice.tscn", "PackedScene") as PackedScene
	var scene := packed.instantiate()
	if drop != "":
		var n := scene.get_node_or_null(drop)
		if n != null:
			n.get_parent().remove_child(n)
			n.free()
			print("[mem] 移除 %s" % drop)
		else:
			print("[mem] 找不到 %s" % drop)
	root.add_child(scene)
	for i in 3:
		await process_frame
	var m1 := Performance.get_monitor(Performance.MEMORY_STATIC)
	print("[mem] 靜態記憶體 %.0f MB（載入前 %.0f）  物件 %d  節點 %d  資源 %d" % [
		m1 / 1048576.0, m0 / 1048576.0,
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)])
	quit(0)
