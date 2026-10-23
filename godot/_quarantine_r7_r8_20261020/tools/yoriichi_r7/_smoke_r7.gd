extends SceneTree
func _initialize():
	var g := StaticBody3D.new(); var cs := CollisionShape3D.new(); var bx := BoxShape3D.new(); bx.size = Vector3(50, 1, 50); cs.shape = bx; g.add_child(cs); g.position = Vector3(0, -0.5, 0); root.add_child(g)
	var p = (load("res://characters/yoriichi/player_yoriichi_r7.tscn") as PackedScene).instantiate()
	root.add_child(p)
	for i in 40:
		await physics_frame
	p.call("request_draw")
	for i in 60:
		await physics_frame
	print("FLOOR ", p.is_on_floor(), " sword ", p.sword_state)
	for id in [1, 8, 12, 2, 6]:
		var ok: bool = p.execute_form(id, true)
		print("FORM ", id, " -> ", ok, " atk=", p._active_attack_name, " real=", snappedf(p._action_real, 0.001), " wins=", p._r7_wins)
		for i in 150:
			await physics_frame
	quit()
