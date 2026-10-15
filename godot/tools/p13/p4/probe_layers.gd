extends SceneTree
## 診断（唯読）：village_v2 の CollisionObject3D を『overlay 名 × collision_layer × mask』で集計し、玩家（main.tscn の Player）の mask と SpringArm の mask も表示する。
func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var v: Node3D = (load("res://maps/village_v2/village_v2.tscn") as PackedScene).instantiate()
	root.add_child(v)
	for i in 6:
		await process_frame
	var tally := {}
	for co in v.find_children("*", "CollisionObject3D", true, false):
		var c := co as CollisionObject3D
		var p := String(v.get_path_to(c)).split("/")
		var top: String = p[0]
		if p.size() > 1 and (top == "Buildings" or top == "Districts"):
			top = "%s/%s" % [p[0], p[1]]
		var key := "%-34s layer=%-3d mask=%-3d (%s)" % [top, c.collision_layer, c.collision_mask, c.get_class()]
		tally[key] = int(tally.get(key, 0)) + 1
	var keys := tally.keys()
	keys.sort()
	for k in keys:
		print("[LAYER] %s  n=%d" % [k, tally[k]])
	var pl := (load("res://scenes/player.tscn") as PackedScene).instantiate()
	print("[LAYER] player scene root=%s class=%s layer=%d mask=%d" % [pl.name, pl.get_class(), (pl as CollisionObject3D).collision_layer if pl is CollisionObject3D else -1, (pl as CollisionObject3D).collision_mask if pl is CollisionObject3D else -1])
	for sa in pl.find_children("*", "SpringArm3D", true, false):
		print("[LAYER] SpringArm3D %s collision_mask=%d length=%.2f" % [sa.name, (sa as SpringArm3D).collision_mask, (sa as SpringArm3D).spring_length])
	quit(0)
