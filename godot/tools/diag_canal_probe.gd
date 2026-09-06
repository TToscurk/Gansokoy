extends SceneTree
## Why does gen_ground_collision skip B2_Canal/* now?

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var src: Node = (load("res://maps/slice/slice.tscn") as PackedScene).instantiate()
	var canal := src.get_node_or_null("B2_Canal")
	print("[P] B2_Canal 直接子節點? %s" % str(canal != null))
	if canal == null:
		for c in src.get_children():
			print("[P]   root child: %s" % c.name)
		var found := src.find_children("B2_Canal", "", true, false)
		for f in found:
			print("[P]   deep find: %s (parent=%s)" % [f.get_path(), f.get_parent().name])
	else:
		var bed := src.get_node_or_null("B2_Canal/CanalBed")
		print("[P] CanalBed via get_node: %s" % str(bed != null))
		for c in canal.get_children():
			print("[P]   child: %s visible=%s" % [c.name, str((c as Node3D).visible) if c is Node3D else "-"])
	quit(0)
