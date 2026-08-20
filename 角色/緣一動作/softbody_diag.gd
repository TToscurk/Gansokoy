extends Node3D
func _ready() -> void:
	# order A: mesh BEFORE add_child
	var sb := SoftBody3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(1,1); pm.subdivide_width=8; pm.subdivide_depth=8
	sb.mesh = pm
	sb.position = Vector3(0,1.5,0)
	add_child(sb)
	# order B: proxy mesh BEFORE add_child
	var pscene: PackedScene = load("res://haori_softbody_proxy.glb")
	var tmp := pscene.instantiate()
	var mi: MeshInstance3D = tmp.find_children("*","MeshInstance3D",true,false)[0]
	var sb2 := SoftBody3D.new()
	sb2.mesh = mi.mesh
	sb2.position = Vector3(1.5,0,0)
	add_child(sb2)
	tmp.free()
	_check.call_deferred(sb, sb2)
func _check(sb: SoftBody3D, sb2: SoftBody3D) -> void:
	await get_tree().create_timer(1.0).timeout
	print("PLANE server bounds: ", PhysicsServer3D.soft_body_get_bounds(sb.get_physics_rid()))
	print("PROXY server bounds: ", PhysicsServer3D.soft_body_get_bounds(sb2.get_physics_rid()))
	get_tree().quit()
