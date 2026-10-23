
extends SceneTree
var sb: SoftBody3D
var start := []
var n := 0
func _initialize():
    var root = Node3D.new()
    get_root().add_child(root)
    sb = SoftBody3D.new()
    var pm = PlaneMesh.new()
    pm.size = Vector2(1,1); pm.subdivide_width = 6; pm.subdivide_depth = 6
    sb.mesh = pm
    sb.simulation_precision = 5
    sb.total_mass = 1.0
    sb.position = Vector3(0,2,0)
    root.add_child(sb)
    for i in range(12): start.append(sb.get_point_transform(i))
    print("SOFT2 rid_valid=%s p0=%s" % [sb.get_physics_rid().is_valid(), str(start[0])])

func _physics_process(_d):
    n += 1
    if n >= 120:
        var moved := 0.0
        for i in range(12): moved += start[i].distance_to(sb.get_point_transform(i))
        print("SOFT2 frames=%d total_move=%.5f p0_now=%s" % [n, moved, str(sb.get_point_transform(0))])
        print("SOFT2 VERDICT=%s" % ("MOVES" if moved > 0.001 else "STATIC"))
        return true
    return false
