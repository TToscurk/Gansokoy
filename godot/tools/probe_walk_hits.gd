extends SceneTree
## 走查異常點追根：射線由上而下逐層打，報出每一層命中的節點。
##   Godot --path godot --script tools/probe_walk_hits.gd

const PTS := [
	[0.0, -12.5, "庭院踏步上"],
	[0.0, -18.0, "庭院前段"],
	[0.0, -23.0, "拜殿階前"],
	[-14.0, -21.0, "庭院西(社務所)"],
	[14.0, -15.0, "庭院東(手水舍)"],
	[0.0, -33.0, "庭院北緣"],
]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	var pl := main.get_node_or_null("Player")
	if pl != null:
		(pl as Node3D).visible = false
	var space := root.world_3d.direct_space_state
	for p in PTS:
		var x: float = p[0]
		var z: float = p[1]
		var line := ""
		var ex := []
		for k in 6:
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(x, 200.0, z), Vector3(x, -60.0, z))
			var typed: Array[RID] = []
			for r in ex:
				typed.append(r)
			q.exclude = typed
			var hit := space.intersect_ray(q)
			if not hit.has("position"):
				break
			var col: Object = hit.get("collider")
			var nm: String = String(col.name) if col != null else "?"
			var py: float = hit["position"].y
			line += "%s y=%.2f | " % [nm, py]
			ex.append(hit["rid"])
		print("[HIT] %s (%.1f, %.1f) : %s" % [str(p[2]), x, z, line])
	print("[HIT] done")
	quit(0)
