extends SceneTree
## 沿線取樣探針：godot --headless --path godot --script res://tools/beast_path/probe_line.gd -- --a=-60,-190 --b=-60,-150 --n=40
const BP := preload("res://tools/beast_path/bp_lib.gd")


func _initialize() -> void:
	var lib := BP.new()
	lib.setup(true, true)
	var a := Vector2.ZERO
	var b := Vector2.ONE
	var n := 40
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--a="):
			var v := arg.trim_prefix("--a=").split(",")
			a = Vector2(float(v[0]), float(v[1]))
		elif arg.begins_with("--b="):
			var v := arg.trim_prefix("--b=").split(",")
			b = Vector2(float(v[0]), float(v[1]))
		elif arg.begins_with("--n="):
			n = int(arg.trim_prefix("--n="))
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		var o := {}
		var hh: float = lib._h_stage(p, 4, o)
		var qm: Dictionary = lib.main.q(p)
		print("(%7.1f,%7.1f)  h=%7.2f  slope=%5.1f°  dmain=%5.1f  sdf=%6.1f  macro=%.2f" % [p.x, p.y, hh, lib.slope_deg_at(p.x, p.y), qm["d"], lib.mask_sdf(p), lib._macro_h(p)])
	quit(0)
