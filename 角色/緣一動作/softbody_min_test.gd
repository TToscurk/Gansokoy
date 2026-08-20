extends Node3D
const SHOT_DIR := "D:/神社/shrine-yoriichi/角色/haori_work/softbody_shots/"
func _ready() -> void:
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45,30,0); add_child(sun)
	var env := WorldEnvironment.new(); var e := Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.2,0.2,0.25)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color(0.8,0.8,0.8)
	env.environment = e; add_child(env)
	var cam := Camera3D.new(); add_child(cam)
	cam.position = Vector3(0, 1.2, 3.2); cam.look_at(Vector3(0,0.8,0)); cam.current = true
	# floor static body
	var fb := StaticBody3D.new(); fb.collision_layer = 2; add_child(fb)
	var fcs := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(10,0.2,10)
	fcs.shape = box; fcs.position = Vector3(0,-0.1,0); fb.add_child(fcs)
	var fm := MeshInstance3D.new(); var pm2 := PlaneMesh.new(); pm2.size = Vector2(10,10); fm.mesh = pm2; add_child(fm)
	# TEST A: builtin plane softbody, pinned two corners
	var sb := SoftBody3D.new(); add_child(sb)
	var pm := PlaneMesh.new(); pm.size = Vector2(1,1); pm.subdivide_width = 12; pm.subdivide_depth = 12
	sb.mesh = pm
	sb.position = Vector3(-0.8, 1.5, 0)
	sb.collision_mask = 2
	sb.simulation_precision = 5
	print("TESTA points via mesh: builtin plane")
	# TEST B: proxy, no pins
	var pscene: PackedScene = load("res://haori_softbody_proxy.glb")
	var tmp := pscene.instantiate(); add_child(tmp)
	var mi: MeshInstance3D = tmp.find_children("*","MeshInstance3D",true,false)[0]
	var sb2 := SoftBody3D.new(); add_child(sb2)
	sb2.mesh = mi.mesh
	sb2.position = Vector3(1.0, 0.0, 0)
	sb2.collision_mask = 2
	tmp.queue_free()
	_seq.call_deferred()
func _seq() -> void:
	for i in 6:
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(SHOT_DIR + "min_%02d.png" % i)
		print("MINSHOT ", i)
	get_tree().quit()
