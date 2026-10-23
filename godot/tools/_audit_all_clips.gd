
extends SceneTree
func _init():
    var dir = DirAccess.open("res://characters/yoriichi/animations")
    var files = []
    for f in dir.get_files():
        if f.ends_with(".res"): files.append(f)
    files.sort()
    print("COUNT ", files.size())
    for f in files:
        var a: Animation = load("res://characters/yoriichi/animations/%s" % f)
        if a == null: continue
        var tracks = a.get_track_count()
        var keys = 0
        var lin = 0; var cub = 0; var near = 0
        var dead = []      # 只有 1 key 的骨
        var hips_rot = 0
        for i in tracks:
            var n = a.track_get_key_count(i)
            keys += n
            match a.track_get_interpolation_type(i):
                0: near += 1
                1: lin += 1
                2: cub += 1
            if n <= 1:
                dead.append(str(a.track_get_path(i)).split(":")[-1])
            if a.track_get_type(i) == 2 and str(a.track_get_path(i)).ends_with(":Hips"):
                hips_rot = n
        print("A|%s|len=%.3f|tracks=%d|keys=%d|near=%d|lin=%d|cub=%d|hipsrot=%d|dead=%s" % [f.replace(".res",""), a.length, tracks, keys, near, lin, cub, hips_rot, ",".join(dead)])
    quit()
