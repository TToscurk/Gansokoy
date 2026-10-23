
extends SceneTree
func _init():
    var tn = ["VALUE","POS3D","ROT3D","SCL3D","BLEND","METHOD","BEZIER","AUDIO","ANIM"]
    var ipn = ["NEAREST","LINEAR","CUBIC","LINEAR_ANGLE","CUBIC_ANGLE"]
    for f in ["yoriichi_iai_stance","yoriichi_iai_slash"]:
        var a: Animation = load("res://characters/yoriichi/animations/%s.res" % f)
        print("=== ", f, " len=", a.length)
        for i in a.get_track_count():
            print("T %-6s %-6s n=%-4d %s" % [tn[a.track_get_type(i)], ipn[a.track_get_interpolation_type(i)], a.track_get_key_count(i), str(a.track_get_path(i))])
    quit()
