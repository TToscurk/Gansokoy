
extends SceneTree
func _init():
    var files = ["yoriichi_iai_stance","yoriichi_iai_slash","yoriichi_idle_grounded","yoriichi_attack_combo"]
    for f in files:
        var p = "res://characters/yoriichi/animations/%s.res" % f
        var a: Animation = load(p)
        if a == null:
            print("R MISSING ", p); continue
        var counts = {}
        var total_keys = 0
        for i in a.get_track_count():
            var t = a.track_get_type(i)
            var interp = a.track_get_interpolation_type(i)
            var key = "%d/%d" % [t, interp]
            counts[key] = counts.get(key, 0) + 1
            total_keys += a.track_get_key_count(i)
        print("R %s len=%.3f tracks=%d keys=%d typeinterp=%s loop=%d" % [f, a.length, a.get_track_count(), total_keys, str(counts), a.loop_mode])
    quit()
