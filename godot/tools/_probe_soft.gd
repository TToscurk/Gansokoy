
extends SceneTree
func _init():
    # 實際跑起來的 3D 物理伺服器是哪個
    var s = PhysicsServer3D
    print("SERVER_CLASS ", s.get_class())
    var ps = ProjectSettings.get_setting("physics/3d/physics_engine", "<unset>")
    print("SETTING ", ps)
    # 列出可選引擎
    var info = ProjectSettings.get_property_list()
    for p in info:
        if str(p.name).begins_with("physics/3d/physics_engine"):
            print("ENGINE_HINT ", p.hint_string)
    # 真的建一個 SoftBody3D 並加平面 mesh 跑幾幀，看是否有動
    var root = Node3D.new()
    get_root().add_child(root)
    var sb = SoftBody3D.new()
    var pm = PlaneMesh.new()
    pm.size = Vector2(1,1)
    pm.subdivide_width = 8
    pm.subdivide_depth = 8
    sb.mesh = pm
    sb.simulation_precision = 5
    sb.total_mass = 1.0
    root.add_child(sb)
    print("SB_RID ", sb.get_physics_rid())
    print("SB_RID_VALID ", sb.get_physics_rid().is_valid())
    quit()
