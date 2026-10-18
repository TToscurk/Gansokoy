extends SceneTree
## 產生 res://data/wind/secondary/wolf.tres（狼 rig：尾 5 節、鬃毛 6 條 2 節、頸毛 1 條）。已存在不覆寫（--reset 才重建）。
##   Godot_v4.7.2-stable_win64_console.exe --headless --path godot --script res://tools/wind/secondary_profile_init.gd

const PATH := "res://data/wind/secondary/wolf.tres"


func _ch(label: String, r: String, t: String, kind: int, k: float, z: float, wi: float, inn: float, mx: float) -> SecondaryChain:
	var c := SecondaryChain.new()
	c.label = label
	c.root_bone = r
	c.tip_bone = t
	c.kind = kind
	c.stiffness = k
	c.damping = z
	c.wind_influence = wi
	c.inertia = inn
	c.max_angle_deg = mx
	return c


func _init() -> void:
	if ResourceLoader.exists(PATH) and not ("--reset" in OS.get_cmdline_user_args()):
		print("OK 已存在 ", PATH)
		quit()
		return
	var p := SecondaryMotionProfile.new()
	p.rig_name = "wolf (assets/enemies/wolf/wolf_pounce.glb)"
	p.chains.append(_ch("tail", "Tail1", "Tail5", 1, 28.0, 0.32, 1.0, 1.2, 40.0))
	for side in ["L", "R"]:
		for seg in ["B", "F", "M"]:
			p.chains.append(_ch("mane_%s_%s" % [seg, side], "Mane%s.%s1" % [seg, side], "Mane%s.%s2" % [seg, side], 0, 60.0, 0.5, 0.8, 0.6, 22.0))
	p.chains.append(_ch("ruff", "Ruff1", "Ruff2", 0, 70.0, 0.55, 0.6, 0.5, 15.0))
	var err := ResourceSaver.save(p, PATH)
	print("%s %s：%d 條鏈" % ["OK" if err == OK else "FAIL", PATH, p.chains.size()])
	quit(0 if err == OK else 1)
