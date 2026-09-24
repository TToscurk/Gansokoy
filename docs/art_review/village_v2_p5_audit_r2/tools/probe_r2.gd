extends SceneTree
## P5 audit r2 probe（唯讀）：參道鳥居兩柱腳、龍神像基座四角的地面高度。

func _init() -> void:
	_run.call_deferred()

func _ray(space: PhysicsDirectSpaceState3D, p: Vector2) -> String:
	# 穿過 Landmarks 下的 placeholder，只回報第一個非 Landmark 碰撞（地形／路面）
	var ex: Array[RID] = []
	var out := ""
	for i in 8:
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 120, p.y), Vector3(p.x, -40, p.y))
		q.exclude = ex
		var r := space.intersect_ray(q)
		if r.is_empty():
			return out + " miss"
		var n := r["collider"] as Node
		var path := String(n.get_path())
		out += "%.2f(%s/%s) " % [float(r["position"].y), n.get_parent().name, n.name]
		if path.find("/Landmarks/") < 0:
			return out
		ex.append(r["rid"])
	return out

func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	# 參道鳥居 at (289.6,-166) yaw 22；柱心距 4.5 → 左右各 2.25 m（沿鳥居本地 X）
	var c := Vector2(289.6, -166)
	var yaw := deg_to_rad(22.0)
	var ax := Vector2(cos(yaw), -sin(yaw))
	for s: float in [-1.0, 1.0]:
		var p: Vector2 = c + ax * 2.25 * s
		print("[PROBE] HILL_TORII pillar ", s, " @", p, " y=", _ray(space, p))
	# 龍神像 10×10 基座四角 + 中心
	var d := Vector2(388, -188)
	for off: Vector2 in [Vector2.ZERO, Vector2(-5, -5), Vector2(5, -5), Vector2(-5, 5), Vector2(5, 5)]:
		print("[PROBE] DRAGON ", off, " y=", _ray(space, d + off))
	quit()
